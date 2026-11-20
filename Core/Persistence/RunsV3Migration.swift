//
//  RunsV3Migration.swift
//  WRKT
//
//  Copies the run history from runs_v2.json into a new runs_v3 directory (spec section 7.1,
//  steps 2 and 4 to 11). Everything is written into runs_v3.staging, verified, made durable,
//  and only then renamed to runs_v3: that rename is the switch. Before it, runs_v2.json is the
//  history and staging is disposable; after it, runs_v3 is complete. runs_v2.json is only
//  read (by the caller, for the source and its checksum), never written, moved or removed.
//
//  Off: nothing calls this unless RunHistoryConfiguration.migrationMayStart (see
//  RunsV3Format.swift), which is false in every Release build.
//

import CryptoKit
import Foundation

nonisolated enum RunsV3Migration {
    /// What is migrated: the history as runs_v2.json holds it, read by the caller.
    struct Source {
        /// History order.
        let runs: [Run]
        /// runs_v2.json as it was read; `present` false when there is no file (empty history).
        let v2: RunsV3BaselineV1.V2State
    }

    enum Step: String, Sendable {
        case removeStaging, createStaging, writeWorkouts, writeIndex, writeBaseline, writeFormat
        case verify, syncStaging, sourceChanged, rename, syncSwitch
    }

    struct Failure: Error, CustomStringConvertible {
        let step: Step
        let underlying: Error?
        var description: String { "migration failed at \(step.rawValue): \(underlying.map { "\($0)" } ?? "verification")" }
    }

    struct Outcome {
        let workoutCount: Int
        /// Bytes of the workout files written.
        let bytesWritten: Int
        /// False when the barrier after the rename failed: the switch happened (the rename is
        /// done) and the next barrier, which the store always runs first, makes it durable.
        let switchDurable: Bool
    }

    static func stagingURL(_ storage: URL) -> URL { storage.appendingPathComponent(RunsV3.stagingDirectoryName, isDirectory: true) }

    /// Runs the migration. Throws `Failure` for every outcome but the switch; staging is then
    /// removed (best effort) and runs_v2.json stays the history. `sourceUnchanged` is asked right
    /// before the rename: false aborts (something wrote runs_v2.json meanwhile).
    static func migrate(_ source: Source, storage: URL, environment: RunsV3Store.Environment,
                        sourceUnchanged: () -> Bool) throws -> Outcome {
        let fs = environment.fileSystem
        let writer = DurableFileWriter(fileSystem: fs, token: environment.token)
        let staging = stagingURL(storage)
        let layout = RunsV3Layout(storage: storage)
        let stagingLayout = StagingLayout(root: staging)
        let encoder = RunsV3.makeEncoder()
        let decoder = RunsV3.makeDecoder()

        func step<T>(_ step: Step, _ body: () throws -> T) throws -> T {
            do {
                return try body()
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure(step: step, underlying: error)
            }
        }

        // Never over an existing runs_v3: v3 is active, a migration must not run.
        guard try fs.itemInfo(layout.root) == nil else {
            throw Failure(step: .rename, underlying: DurableFileError(operation: "migrate", path: layout.root.path, code: EEXIST))
        }
        do {
            // 2. A leftover staging directory is disposable.
            try step(.removeStaging) { try fs.removeTree(staging) }
            // 4.
            try step(.createStaging) {
                for url in [staging, stagingLayout.runs, stagingLayout.trash, stagingLayout.tmp] {
                    try fs.createDirectory(url, protection: RunsV3.protection)
                }
            }
            // 5. One file per workout, revision 1, seq n - i; each fsynced as it is written.
            let count = source.runs.count
            var written: [(name: RunsV3FileName, size: Int, sha256: String)] = []
            written.reserveCapacity(count)
            var bytes = 0
            try step(.writeWorkouts) {
                for (i, run) in source.runs.enumerated() {
                    let name = RunsV3FileName(id: run.id, rev: 1)
                    let data = try encoder.encode(RunFileV1(format: 1, id: run.id, rev: 1, seq: Int64(count - i), run: StoredRun(run)))
                    try writer.writeNew(data, to: stagingLayout.runs.appendingPathComponent(name.string),
                                        temporaryDirectory: stagingLayout.tmp, protection: RunsV3.protection)
                    written.append((name, data.count, RunsV3Store.sha256(data)))
                    bytes += data.count
                }
            }
            // 6. Index, baseline (computed in the same pass), format.
            try step(.writeIndex) {
                let entries = zip(source.runs, written).enumerated().map { i, pair in
                    RunsV3IndexV1.Entry(id: pair.0.id, rev: 1, seq: Int64(count - i), size: pair.1.size,
                                        sha256: pair.1.sha256, summary: RunSummary(pair.0))
                }
                try writer.write(try encoder.encode(RunsV3IndexV1(formatVersion: 1, minimumReaderVersion: 1, generation: 1, entries: entries)),
                                 to: stagingLayout.root.appendingPathComponent("index.json"), protection: RunsV3.protection)
            }
            let baseline = RunsV3BaselineV1(
                formatVersion: 1, reconciledAt: environment.now(), v2: source.v2,
                entries: source.runs.enumerated().map { i, run in .init(id: run.id, hash: StoredRun.normalHash(run), seq: Int64(count - i)) })
            try step(.writeBaseline) {
                try writer.write(try encoder.encode(baseline), to: stagingLayout.root.appendingPathComponent("baseline.json"),
                                 protection: RunsV3.protection)
            }
            let format = RunsV3FormatV1(
                formatVersion: 1, minimumReaderVersion: 1, minimumWriterVersion: 1, createdAt: environment.now(),
                createdByBuild: environment.build,
                migratedFrom: .init(fileName: "runs_v2.json", size: source.v2.size ?? 0, sha256: source.v2.sha256 ?? "", workoutCount: count))
            try step(.writeFormat) {
                try writer.write(try encoder.encode(format), to: stagingLayout.root.appendingPathComponent("format.json"),
                                 protection: RunsV3.protection)
            }

            // 7. Verify everything against the source, reading it back from disk.
            try step(.verify) {
                let names = try fs.contentsOfDirectory(stagingLayout.runs)
                guard Set(names) == Set(written.map(\.name.string)), names.count == count else {
                    throw Failure(step: .verify, underlying: nil)
                }
                for (i, run) in source.runs.enumerated() {
                    let data = try fs.readFile(stagingLayout.runs.appendingPathComponent(written[i].name.string))
                    let file = try decoder.decode(RunFileV1.self, from: data)
                    guard RunsV3Store.sha256(data) == written[i].sha256, file.format == 1, file.id == run.id, file.rev == 1,
                          file.seq == Int64(count - i), file.run.run == run,
                          try encoder.encode(StoredRun(file.run.run)) == encoder.encode(StoredRun(run)) else {
                        throw Failure(step: .verify, underlying: nil)
                    }
                }
                let index = try decoder.decode(RunsV3IndexV1.self, from: fs.readFile(stagingLayout.root.appendingPathComponent("index.json")))
                guard index.entries.map(\.id) == source.runs.map(\.id),
                      index.entries.map(\.summary) == source.runs.map(RunSummary.init),
                      zip(index.entries, index.entries.dropFirst()).allSatisfy({ $0.seq > $1.seq }) else {
                    throw Failure(step: .verify, underlying: nil)
                }
                let readBaseline = try decoder.decode(RunsV3BaselineV1.self, from: fs.readFile(stagingLayout.root.appendingPathComponent("baseline.json")))
                let readFormat = try decoder.decode(RunsV3FormatV1.self, from: fs.readFile(stagingLayout.root.appendingPathComponent("format.json")))
                // Compared as stored: dates keep whole seconds in the files.
                guard try encoder.encode(readBaseline) == encoder.encode(baseline),
                      try encoder.encode(readFormat) == encoder.encode(format) else {
                    throw Failure(step: .verify, underlying: nil)
                }
            }
            // 8. Everything in staging on permanent storage before the switch.
            try step(.syncStaging) {
                try writer.barrier(directories: [stagingLayout.runs, stagingLayout.trash, stagingLayout.tmp, stagingLayout.root])
            }
            // 9.
            guard sourceUnchanged() else { throw Failure(step: .sourceChanged, underlying: nil) }
            // 10. The switch: fails rather than replace anything named runs_v3.
            try step(.rename) { try fs.renameExclusive(staging, to: layout.root) }
            // 11. The switch on permanent storage before anything is written to v3.
            var durable = true
            do {
                try writer.barrier(directories: [storage])
            } catch {
                durable = false
                AppLogger.warning("runs_v3 migration: the switch is not yet durable: \(error)", category: AppLogger.storage)
            }
            return Outcome(workoutCount: count, bytesWritten: bytes, switchDurable: durable)
        } catch let failure as Failure {
            // Every failure happens before the switch (a failed barrier after it is not a
            // failure): staging is removed, runs_v2.json stays the history.
            if (try? fs.itemInfo(layout.root)) == nil { try? fs.removeTree(staging) }
            throw failure
        }
    }

    private struct StagingLayout {
        let root: URL
        var runs: URL { root.appendingPathComponent("runs", isDirectory: true) }
        var trash: URL { root.appendingPathComponent("trash", isDirectory: true) }
        var tmp: URL { root.appendingPathComponent("tmp", isDirectory: true) }
    }
}
