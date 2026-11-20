//
//  RunsV3Store.swift
//  WRKT
//
//  Reads, repairs and writes a runs_v3 directory. Specification:
//  docs/run-storage-v3-format-spec.md, sections 3 to 6. Not used by the app yet: nothing outside
//  this file, RunsV3Format.swift and their tests may refer to it until the store is wired in.
//
//  The core rule: the live history is a function of the names in runs/ and the files they name.
//  Every workout file is immutable once named; the live revision of a workout is its highest
//  decodable revision; history order is `seq` descending. index.json is only a cache.
//

import CryptoKit
import Foundation

/// One live workout as the store knows it.
nonisolated struct RunsV3Entry: Equatable {
    let id: UUID
    /// The live revision: the file `runs/<id>.<rev>.json`.
    var rev: Int
    var seq: Int64
    var summary: RunSummary
    var size: Int
    var sha256: String
    /// Listed, but no revision of it can be read (missing or damaged file).
    var unavailable: Bool
}

/// One change to one workout, applied in order by `drain`.
nonisolated enum RunsV3Operation {
    /// A new workout (or a re-added id) at history position `seq`.
    case add(Run, seq: Int64)
    /// The whole run, keeping the workout's position. Dropped if the workout is gone.
    case replace(Run)
    /// A pure function of the stored run. Dropped if the workout is gone.
    case edit((Run) -> Run)
    case delete
}

nonisolated enum RunsV3Mode: Equatable {
    case writable
    /// `minimumWriterVersion` is above this build's: history is shown, nothing is written.
    case readOnly
}

nonisolated enum RunsV3OpenResult: Equatable {
    /// No `runs_v3/`: the history is in runs_v2.json.
    case notActive
    /// Protected data is unavailable (before the first unlock) or access was denied: nothing was
    /// concluded and nothing may be written; open again later.
    case deferred
    /// The directory needs a newer reader.
    case unsupported(minimumReaderVersion: Int)
    /// Something that is not a directory is named `runs_v3`.
    case invalidLayout(String)
    case active(RunsV3Mode)
}

/// What `open` found, for logs and counters. No user-facing text.
nonisolated struct RunsV3OpenReport: Equatable {
    enum IndexState: Equatable { case valid, stale, missing, unreadable, newer }
    var indexState: IndexState = .missing
    /// Summaries derived from files because the index did not have the live revision.
    var rederived: [UUID] = []
    /// Listed by the index, no file, a deletion recorded in trash: an interrupted delete.
    var completedDeletes: [UUID] = []
    /// Listed by the index, no file, no deletion recorded: kept as unavailable.
    var missingFiles: [UUID] = []
    /// A live id none of whose revisions decodes; kept as unavailable when the index lists it.
    var unreadable: [UUID] = []
    /// Files of an id the index does not list and none of which decodes: cannot be shown.
    var unlistedUnreadable: [UUID] = []
    var corruptRevisions: [RunsV3FileName] = []
    var newerFormatRevisions: [RunsV3FileName] = []
    var supersededRevisions: [RunsV3FileName] = []
    var ignoredNames: [String] = []
    var duplicateIndexEntries = 0
    var formatMissing = false
}

/// What `repair` did.
nonisolated struct RunsV3RepairReport: Equatable {
    var removedTemporary = 0
    var removedLeftoverDirectories = 0
    var quarantined = 0
    var retired = 0
    var createdDirectories = 0
    var rewroteFormat = false
    var wroteIndex = false
}

nonisolated enum RunsV3ReadResult {
    case loaded(Run)
    /// No live workout with this id.
    case removed
    /// Listed, but no revision can be read.
    case unreadable
    /// Protected data unavailable or access denied: try again later.
    case temporarilyUnavailable
}

/// The outcome of one `drain`, per workout id.
nonisolated struct RunsV3DrainResult {
    /// Every operation of these ids is on permanent storage (or changed nothing). Includes ids
    /// written by an earlier drain whose barrier failed.
    var durable: Set<UUID> = []
    /// Written, but the barrier failed: do not submit their operations again; a later drain's
    /// barrier makes them durable.
    var awaitingBarrier: Set<UUID> = []
    /// Their operations did not reach disk (disk full, protected data, an I/O error): submit them
    /// again. Applying them again is safe: the drain recomputes from what is on disk.
    var failed: [UUID: Error] = [:]
    /// Edits dropped because the stored workout cannot be read (permanent); not a failure.
    var dropped: [UUID: String] = [:]
    var barrierError: Error?
    var indexError: Error?
    var indexWritten = false

    /// What `flushHealthKitChanges` needs: nothing failed and nothing waits for a barrier.
    var isFullyDurable: Bool { failed.isEmpty && awaitingBarrier.isEmpty && barrierError == nil }
}

nonisolated enum RunsV3StoreError: Error, Equatable {
    case notOpen
    case readOnly
    case unreadableStoredRun(UUID)
}

/// The runs_v3 directory of one storage directory. Not thread safe: one owner (in the app, the
/// storage actor) calls it serially. Its file system, clock and random sources are injected.
nonisolated final class RunsV3Store {
    struct Environment {
        var fileSystem: DurableFileSystem
        var now: () -> Date
        /// 16 random bits for trash names.
        var random: () -> UInt16
        /// Temporary file names.
        var token: @Sendable () -> UUID
        /// Recorded in a rewritten format.json.
        var build: String
    }

    let layout: RunsV3Layout
    private let environment: Environment
    private var fileSystem: DurableFileSystem { environment.fileSystem }
    private let writer: DurableFileWriter
    private let encoder = RunsV3.makeEncoder()
    private let decoder = RunsV3.makeDecoder()

    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60
    static let trashCapBytes = 200 * 1024 * 1024
    static let trashCapDeletedMinimumAge: TimeInterval = 7 * 24 * 60 * 60

    private(set) var mode: RunsV3Mode?
    private(set) var report = RunsV3OpenReport()
    private(set) var entries: [UUID: RunsV3Entry] = [:]
    /// Every revision with a valid name in runs/, per id, ascending.
    private(set) var revisions: [UUID: [Int]] = [:]
    private var indexStale = false
    private var indexGeneration = 0
    /// The revision the index.json on disk lists for each id. Their `deleted` trash files are
    /// evidence (R8), and a new revision always exceeds it, so the index never names a file
    /// whose content it does not describe.
    private var onDiskIndexRevisions: [UUID: Int] = [:]
    /// The highest revision in trash per id (read from trash/ once, on the first new id, then
    /// kept up to date): a re-added id continues above it, so an older index generation that a
    /// power loss brings back can never name the new file.
    private var trashedRevisions: [UUID: Int]?
    /// True from open (an earlier process may have renamed files without a barrier) and after
    /// every write or move, until a barrier succeeds.
    private var needsBarrier = true
    private var writtenAwaitingBarrier: Set<UUID> = []
    /// Revisions to retire once an index listing their successor is on disk.
    private var pendingRetirement: [UUID: (rev: Int, detailRemoved: Bool)] = [:]
    private var formatNeedsRewrite = false
    private var evidenceStorage: [UUID: Int]?
    /// Ids whose superseded revision was unlinked or moved after the last barrier.
    private var retiredSinceBarrier: Set<UUID> = []
    /// Revisions found damaged when open or a read decoded them, moved to trash by `repair`.
    private var quarantine: Set<RunsV3FileName> = []

    init(storage: URL, environment: Environment) {
        self.layout = RunsV3Layout(storage: storage)
        self.environment = environment
        self.writer = DurableFileWriter(fileSystem: environment.fileSystem, token: environment.token)
    }

    /// The live history: `seq` descending, then id ascending.
    var history: [RunsV3Entry] {
        entries.values.sorted { $0.seq != $1.seq ? $0.seq > $1.seq : $0.id.uuidString < $1.id.uuidString }
    }

    var nextSeq: Int64 { (entries.values.map(\.seq).max() ?? 0) + 1 }

    // MARK: - Open (spec 5, R0 to R9): reads only

    private struct Deferred: Error {}

    /// Reads the directory into memory. Writes nothing.
    func open(isProtectedDataAvailable: Bool) -> RunsV3OpenResult {
        mode = nil
        report = RunsV3OpenReport()
        entries = [:]
        revisions = [:]
        quarantine = []
        indexStale = false
        formatNeedsRewrite = false
        onDiskIndexRevisions = [:]
        evidenceStorage = nil
        trashedRevisions = nil
        pendingRetirement = [:]
        writtenAwaitingBarrier = []
        retiredSinceBarrier = []
        needsBarrier = true
        guard isProtectedDataAvailable else { return .deferred }
        do {
            return try openActive()
        } catch is Deferred {
            entries = [:]
            mode = nil
            return .deferred
        } catch {
            entries = [:]
            mode = nil
            return .deferred
        }
    }

    private func openActive() throws -> RunsV3OpenResult {
        // R1
        guard let rootInfo = try permissionAware({ try fileSystem.itemInfo(layout.root) }) else { return .notActive }
        guard rootInfo.kind == .directory else { return .invalidLayout("runs_v3 is not a directory") }

        // R2
        var writable = true
        var format: RunsV3FormatV1?
        if let data = try readIfPresent(layout.format) {
            format = try? decoder.decode(RunsV3FormatV1.self, from: data)
        }
        if let format {
            if format.minimumReaderVersion > RunsV3.readerVersion {
                return .unsupported(minimumReaderVersion: format.minimumReaderVersion)
            }
            if format.minimumWriterVersion > RunsV3.writerVersion { writable = false }
        } else {
            report.formatMissing = true
        }
        var sawNewerFormat = false

        // R4
        var byID: [UUID: [Int]] = [:]
        let names = (try readDirectoryIfPresent(layout.runs)) ?? []
        for name in names {
            if let parsed = RunsV3FileName.parse(name) {
                byID[parsed.id, default: []].append(parsed.rev)
            } else {
                report.ignoredNames.append(name)
            }
        }
        for key in byID.keys { byID[key]!.sort() }
        revisions = byID

        // R5
        var indexEntries: [UUID: RunsV3IndexV1.Entry] = [:]
        if let data = try readIfPresent(layout.index) {
            if let header = try? decoder.decode(RunsV3IndexV1.Header.self, from: data) {
                if header.minimumReaderVersion > RunsV3.readerVersion {
                    report.indexState = .newer
                    sawNewerFormat = true
                } else if let index = try? decoder.decode(RunsV3IndexV1.self, from: data) {
                    report.indexState = .valid
                    if index.formatVersion > RunsV3.readerVersion { sawNewerFormat = true }
                    indexGeneration = index.generation
                    for entry in index.entries {
                        onDiskIndexRevisions[entry.id] = max(onDiskIndexRevisions[entry.id] ?? 0, entry.rev)
                        if let existing = indexEntries[entry.id] {
                            report.duplicateIndexEntries += 1
                            // Keep the entry naming the live (highest) revision.
                            if entry.rev == byID[entry.id]?.last, existing.rev != entry.rev { indexEntries[entry.id] = entry }
                        } else {
                            indexEntries[entry.id] = entry
                        }
                    }
                } else {
                    report.indexState = .unreadable
                }
            } else {
                report.indexState = .unreadable
            }
        }
        if report.indexState != .valid || report.duplicateIndexEntries > 0 { indexStale = true }

        // R6, R7
        for (id, revs) in byID {
            let top = revs.last!
            let listed = indexEntries[id]
            // Trust the index for a single revision it names. With several revisions, decode the
            // top so the lower ones are retired only behind a readable successor.
            if let listed, listed.rev == top, revs.count == 1 {
                entries[id] = RunsV3Entry(id: id, rev: top, seq: listed.seq, summary: listed.summary,
                                          size: listed.size, sha256: listed.sha256, unavailable: false)
                continue
            }
            var found: (rev: Int, file: RunFileV1, data: Data)?
            for rev in revs.reversed() {
                let name = RunsV3FileName(id: id, rev: rev)
                switch try decodeRevision(name) {
                case .decoded(let file, let data):
                    found = (rev, file, data)
                case .newer:
                    report.newerFormatRevisions.append(name)
                    sawNewerFormat = true
                case .corrupt:
                    report.corruptRevisions.append(name)
                }
                if found != nil { break }
            }
            if let found {
                let summary = RunSummary(found.file.run.run)
                if listed?.rev != found.rev || listed?.summary != summary || listed?.seq != found.file.seq {
                    indexStale = true
                    report.rederived.append(id)
                }
                entries[id] = RunsV3Entry(id: id, rev: found.rev, seq: found.file.seq, summary: summary,
                                          size: found.data.count, sha256: Self.sha256(found.data), unavailable: false)
                for rev in revs where rev < found.rev {
                    report.supersededRevisions.append(RunsV3FileName(id: id, rev: rev))
                }
                // Damaged revisions are quarantined only behind a readable one, so an id never
                // loses its last file to repair.
                for name in report.corruptRevisions where name.id == id { quarantine.insert(name) }
            } else if let listed, (try deletionEvidence())[id].map({ $0 >= listed.rev }) == true {
                // The revision the index lists was deleted (it is in trash), and every revision
                // left is damaged: an interrupted re-add that never became durable, not the
                // deleted workout. Not shown; its damaged files are quarantined.
                report.completedDeletes.append(id)
                indexStale = true
                for rev in revs { quarantine.insert(RunsV3FileName(id: id, rev: rev)) }
            } else if let listed {
                report.unreadable.append(id)
                entries[id] = RunsV3Entry(id: id, rev: top, seq: listed.seq, summary: listed.summary,
                                          size: listed.size, sha256: listed.sha256, unavailable: true)
                indexStale = indexStale || listed.rev != top
            } else {
                report.unlistedUnreadable.append(id)
            }
        }

        // R8
        let unlisted = indexEntries.keys.filter { byID[$0] == nil }
        if !unlisted.isEmpty {
            let deleted = try deletionEvidence()
            for id in unlisted {
                if let deletedRev = deleted[id], deletedRev >= (indexEntries[id]?.rev ?? 0) {
                    report.completedDeletes.append(id)
                    indexStale = true
                } else if let listed = indexEntries[id] {
                    report.missingFiles.append(id)
                    entries[id] = RunsV3Entry(id: id, rev: listed.rev, seq: listed.seq, summary: listed.summary,
                                              size: listed.size, sha256: listed.sha256, unavailable: true)
                }
            }
        }

        if report.indexState == .valid && !indexStale { report.indexState = .valid }
        else if report.indexState == .valid { report.indexState = .stale }
        if report.formatMissing && sawNewerFormat { writable = false }
        formatNeedsRewrite = report.formatMissing && writable
        mode = writable ? .writable : .readOnly
        return .active(mode!)
    }

    private enum DecodedRevision {
        case decoded(RunFileV1, Data)
        case newer
        case corrupt
    }

    /// Reads and decodes one revision. Permission errors propagate as `Deferred`.
    private func decodeRevision(_ name: RunsV3FileName) throws -> DecodedRevision {
        let data: Data
        do {
            data = try fileSystem.readFile(layout.runFile(name))
        } catch let error as DurableFileError where error.isPermission {
            throw Deferred()
        } catch {
            return .corrupt
        }
        guard let header = try? decoder.decode(RunFileV1.Header.self, from: data) else { return .corrupt }
        if header.format > RunsV3.readerVersion { return .newer }
        guard header.id == name.id, header.rev == name.rev,
              let file = try? decoder.decode(RunFileV1.self, from: data), file.run.run.id == name.id else { return .corrupt }
        return .decoded(file, data)
    }

    /// The highest revision with a `deleted` or `merged` file in trash, per id: a recorded
    /// deletion of that revision. `corrupt` and `superseded` files are not evidence of a
    /// deletion. Read once per open.
    private func deletionEvidence() throws -> [UUID: Int] {
        if let cachedEvidence { return cachedEvidence }
        var evidence: [UUID: Int] = [:]
        for name in ((try readDirectoryIfPresent(layout.trash)) ?? []).compactMap(RunsV3TrashName.parse)
        where name.reason == .deleted || name.reason == .merged {
            evidence[name.id] = max(evidence[name.id] ?? 0, name.rev)
        }
        cachedEvidence = evidence
        return evidence
    }
    private var cachedEvidence: [UUID: Int]? {
        get { evidenceStorage }
        set { evidenceStorage = newValue }
    }

    private func permissionAware<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as DurableFileError where error.isPermission {
            throw Deferred()
        }
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try fileSystem.readFile(url)
        } catch let error as DurableFileError where error.isPermission {
            throw Deferred()
        } catch let error as DurableFileError where error.isMissing {
            return nil
        }
    }

    private func readDirectoryIfPresent(_ url: URL) throws -> [String]? {
        do {
            return try fileSystem.contentsOfDirectory(url)
        } catch let error as DurableFileError where error.isPermission {
            throw Deferred()
        } catch let error as DurableFileError where error.isMissing {
            return nil
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Repair (spec 5, R10)

    /// Cleans up and repairs what `open` found, writable mode only: temporary files, staging and
    /// retired directories, damaged and superseded revisions, format.json and the index. Never
    /// unlinks a workout file: those are moved to trash.
    @discardableResult
    func repair() throws -> RunsV3RepairReport {
        guard let mode else { throw RunsV3StoreError.notOpen }
        guard mode == .writable else { throw RunsV3StoreError.readOnly }
        var done = RunsV3RepairReport()
        var touched: Set<URL> = []

        for directory in [layout.runs, layout.trash, layout.tmp] where try fileSystem.itemInfo(directory) == nil {
            try fileSystem.createDirectory(directory, protection: RunsV3.protection)
            touched.insert(layout.root)
            done.createdDirectories += 1
        }
        for name in try fileSystem.contentsOfDirectory(layout.tmp) {
            let url = layout.tmp.appendingPathComponent(name)
            if try fileSystem.itemInfo(url)?.kind == .directory { try fileSystem.removeTree(url) } else { fileSystem.remove(url) }
            done.removedTemporary += 1
        }
        for name in try fileSystem.contentsOfDirectory(layout.root)
        where RunsV3Layout.rootFileNames.contains(where: { DurableFileWriter.isTemporaryName(name, for: $0) }) {
            let url = layout.root.appendingPathComponent(name)
            if try fileSystem.itemInfo(url)?.kind == .file {
                fileSystem.remove(url)
                done.removedTemporary += 1
            }
        }
        for name in try fileSystem.contentsOfDirectory(layout.storage) where Self.isDisposableSibling(name) {
            try fileSystem.removeTree(layout.storage.appendingPathComponent(name))
            done.removedLeftoverDirectories += 1
        }

        for name in quarantine.sorted(by: { $0.string < $1.string }) {
            try moveToTrash(name, reason: .corrupt)
            touched.formUnion([layout.runs, layout.trash])
            done.quarantined += 1
        }
        quarantine = []
        for name in report.supersededRevisions where revisions[name.id]?.contains(name.rev) == true {
            try moveToTrash(name, reason: .superseded)
            touched.formUnion([layout.runs, layout.trash])
            done.retired += 1
        }

        if formatNeedsRewrite {
            let format = RunsV3FormatV1(formatVersion: 1, minimumReaderVersion: 1, minimumWriterVersion: 1,
                                        createdAt: environment.now(), createdByBuild: environment.build, migratedFrom: nil)
            try writer.write(try encoder.encode(format), to: layout.format, protection: RunsV3.protection)
            formatNeedsRewrite = false
            done.rewroteFormat = true
        }
        if !touched.isEmpty || needsBarrier {
            needsBarrier = true
            try writer.barrier(directories: touched.isEmpty ? [layout.runs] : touched.sorted { $0.path < $1.path })
            needsBarrier = false
            retiredSinceBarrier = []
        }
        if indexStale {
            try writeIndex()
            done.wroteIndex = true
        }
        return done
    }

    /// `runs_v3.staging` and `runs_v3.retired-<digits>`: never read, always disposable.
    static func isDisposableSibling(_ name: String) -> Bool {
        if name == RunsV3.stagingDirectoryName { return true }
        guard name.hasPrefix(RunsV3.retiredDirectoryPrefix) else { return false }
        let digits = name.dropFirst(RunsV3.retiredDirectoryPrefix.count)
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Read one workout (spec 5.1)

    /// One workout's full record, from its live revision, else from a lower revision still in
    /// runs/. A damaged revision found here is moved to trash by the next `repair`.
    func readRun(id: UUID) -> RunsV3ReadResult {
        guard var entry = entries[id] else { return .removed }
        let revs = (revisions[id] ?? []).filter { $0 <= entry.rev }.reversed()
        for rev in revs {
            let name = RunsV3FileName(id: id, rev: rev)
            let decoded: DecodedRevision
            do {
                decoded = try decodeRevision(name)
            } catch {
                return .temporarilyUnavailable
            }
            switch decoded {
            case .decoded(let file, let data):
                if rev == entry.rev, Self.sha256(data) != entry.sha256 {
                    AppLogger.warning("runs_v3: \(name.string) does not match its index checksum", category: AppLogger.storage)
                }
                return .loaded(file.run.run)
            case .newer:
                continue
            case .corrupt:
                if revs.count > 1 { quarantine.insert(name) }
            }
        }
        entry.unavailable = true
        entries[id] = entry
        return .unreadable
    }

    // MARK: - Drain (spec 3.5)

    /// Applies one batch of operations, per workout in the given order, then the barrier, then
    /// (with `writeIndex`) the index, then retires superseded revisions. Without `writeIndex` the
    /// index and the retirement wait for `writeIndexIfStale`, so a burst of drains rewrites the
    /// index once.
    func drain(_ batch: [(id: UUID, operations: [RunsV3Operation])], writeIndex: Bool = true) -> RunsV3DrainResult {
        var result = RunsV3DrainResult()
        guard let mode else {
            for item in batch { result.failed[item.id] = RunsV3StoreError.notOpen }
            return result
        }
        guard mode == .writable else {
            for item in batch { result.failed[item.id] = RunsV3StoreError.readOnly }
            return result
        }
        var touched: Set<URL> = []
        var handled: Set<UUID> = []
        var written: Set<UUID> = []

        for (id, operations) in batch {
            do {
                switch try apply(operations, to: id, touched: &touched) {
                case .unchanged: handled.insert(id)
                case .changed: handled.insert(id); written.insert(id)
                case .dropped(let reason): result.dropped[id] = reason; handled.insert(id)
                }
            } catch {
                result.failed[id] = error
            }
        }

        if needsBarrier || !touched.isEmpty {
            needsBarrier = true
            writtenAwaitingBarrier.formUnion(written)
            do {
                try writer.barrier(directories: touched.isEmpty ? [layout.runs] : touched.sorted { $0.path < $1.path })
                needsBarrier = false
                retiredSinceBarrier = []
                result.durable = handled.union(writtenAwaitingBarrier)
                writtenAwaitingBarrier = []
            } catch {
                result.barrierError = error
                result.awaitingBarrier = writtenAwaitingBarrier
                result.durable = handled.subtracting(writtenAwaitingBarrier)
                return result
            }
        } else {
            result.durable = handled
        }

        guard writeIndex else { return result }
        if indexStale {
            do {
                try self.writeIndex()
                result.indexWritten = true
            } catch {
                result.indexError = error
                return result
            }
        }
        retireSuperseded()
        return result
    }

    /// Writes the index if it is stale, then retires superseded revisions. Skipped (false) while
    /// a barrier is owed: the index never lists a file that is not yet durable.
    @discardableResult
    func writeIndexIfStale() throws -> Bool {
        guard let mode else { throw RunsV3StoreError.notOpen }
        guard mode == .writable else { throw RunsV3StoreError.readOnly }
        guard indexStale, !needsBarrier else { return false }
        try writeIndex()
        retireSuperseded()
        return true
    }

    /// Whether the index on disk no longer describes the history.
    var isIndexStale: Bool { indexStale }

    private enum Applied {
        case unchanged, changed
        case dropped(String)
    }

    private func apply(_ operations: [RunsV3Operation], to id: UUID, touched: inout Set<URL>) throws -> Applied {
        let disk = entries[id]
        var diskRun: Run?
        var diskLoaded = false
        func loadDisk() throws -> Run? {
            if diskLoaded { return diskRun }
            diskLoaded = true
            guard let disk else { return nil }
            switch try decodeRevision(RunsV3FileName(id: id, rev: disk.rev)) {
            case .decoded(let file, _): diskRun = file.run.run
            case .newer, .corrupt: diskRun = nil
            }
            return diskRun
        }

        // 1. The target, from the stored state and the operations in order.
        var target: Run? = nil
        var exists = disk != nil
        var seq = disk?.seq ?? 0
        var startedFromDisk = true
        var droppedReason: String?
        do {
            for operation in operations {
                switch operation {
                case .add(let run, let newSeq):
                    target = run
                    seq = newSeq
                    exists = true
                    startedFromDisk = false
                case .replace(let run):
                    guard exists else { continue }
                    target = run
                    startedFromDisk = false
                case .edit(let transform):
                    guard exists else { continue }
                    if target == nil {
                        guard let stored = try loadDisk() else {
                            droppedReason = "stored workout cannot be read"
                            continue
                        }
                        target = stored
                    }
                    target = transform(target!)
                case .delete:
                    target = nil
                    exists = false
                    startedFromDisk = false
                }
            }
        } catch is Deferred {
            throw DurableFileError(operation: "read", path: id.uuidString, code: EPERM)
        }
        _ = startedFromDisk

        // 2. Decide.
        if !exists {
            guard disk != nil || revisions[id] != nil else { return droppedReason.map { .dropped($0) } ?? .unchanged }
            try deleteAllRevisions(of: id, touched: &touched)
            return .changed
        }
        guard let target else {
            // Only edits on an unreadable workout: nothing to write.
            return droppedReason.map { .dropped($0) } ?? .unchanged
        }
        let stored = try? loadDisk()
        if let disk, let stored, seq == disk.seq,
           try encoder.encode(StoredRun(target)) == encoder.encode(StoredRun(stored)) {
            return droppedReason.map { .dropped($0) } ?? .unchanged
        }
        let trashed = disk == nil ? try highestTrashedRevision(of: id) : 0
        let rev = max(disk?.rev ?? 0, revisions[id]?.last ?? 0, onDiskIndexRevisions[id] ?? 0, trashed) + 1
        let file = RunFileV1(format: 1, id: id, rev: rev, seq: seq, run: StoredRun(target))
        let data = try encoder.encode(file)
        let name = RunsV3FileName(id: id, rev: rev)
        needsBarrier = true
        try writer.writeNew(data, to: layout.runFile(name), temporaryDirectory: layout.tmp, protection: RunsV3.protection)
        // The rename moved the file from tmp/ to runs/: both directories must be synchronized
        // before the barrier counts it durable.
        touched.formUnion([layout.runs, layout.tmp])
        revisions[id, default: []].append(rev)
        let summary = RunSummary(target)
        if let disk {
            let removed = stored.map { Self.detailRemoved(from: RunSummary($0), to: summary) } ?? true
            pendingRetirement[id] = (disk.rev, removed)
        }
        entries[id] = RunsV3Entry(id: id, rev: rev, seq: seq, summary: summary, size: data.count,
                                  sha256: Self.sha256(data), unavailable: false)
        indexStale = true
        return droppedReason.map { .dropped($0) } ?? .changed
    }

    /// Moves every revision of `id` to trash as `deleted`, lowest first and the live one last, so
    /// a kill part way never leaves an older revision live. Against a power loss, which may keep
    /// a later directory change and lose an earlier one, each removal below the live revision is
    /// made durable before the next move, and so is a retirement of this id that has not been
    /// through a barrier yet: otherwise the live revision could reach trash while an older one
    /// comes back.
    private func deleteAllRevisions(of id: UUID, touched: inout Set<URL>) throws {
        needsBarrier = true
        let revs = revisions[id] ?? []
        if retiredSinceBarrier.contains(id) && !revs.isEmpty {
            try writer.barrier(directories: [layout.runs, layout.trash])
        }
        for (index, rev) in revs.enumerated() {
            try moveToTrash(RunsV3FileName(id: id, rev: rev), reason: .deleted)
            touched.formUnion([layout.runs, layout.trash])
            if index < revs.count - 1 { try writer.barrier(directories: [layout.runs, layout.trash]) }
        }
        revisions[id] = nil
        entries[id] = nil
        pendingRetirement[id] = nil
        indexStale = true
    }

    /// True when the edit removed or shrank a detail array: then the old revision is kept in
    /// trash instead of being unlinked.
    static func detailRemoved(from old: RunSummary, to new: RunSummary) -> Bool {
        func shrank(_ a: Int?, _ b: Int?) -> Bool { guard let a else { return false }; return (b ?? -1) < a }
        return shrank(old.routePointCount, new.routePointCount)
            || shrank(old.routeWithHRPointCount, new.routeWithHRPointCount)
            || shrank(old.heartRateSampleCount, new.heartRateSampleCount)
            || shrank(old.splitCount, new.splitCount)
    }

    private func moveToTrash(_ name: RunsV3FileName, reason: RunsV3TrashReason) throws {
        let source = layout.runFile(name)
        var attempt = 0
        while true {
            let random = String(format: "%04x", environment.random())
            let milliseconds = Int64((environment.now().timeIntervalSince1970 * 1000).rounded(.down))
            let trashName = RunsV3TrashName(id: name.id, rev: name.rev, reason: reason,
                                            milliseconds: max(0, milliseconds), random: random)
            do {
                needsBarrier = true
                try fileSystem.renameExclusive(source, to: layout.trash.appendingPathComponent(trashName.string))
                break
            } catch let error as DurableFileError where error.code == EEXIST && attempt < 5 {
                attempt += 1
            } catch let error as DurableFileError where error.isMissing {
                break   // Already moved: the operation is idempotent.
            }
        }
        if trashedRevisions != nil { trashedRevisions![name.id] = max(trashedRevisions![name.id] ?? 0, name.rev) }
        if var revs = revisions[name.id] {
            revs.removeAll { $0 == name.rev }
            revisions[name.id] = revs.isEmpty ? nil : revs
        }
    }

    private func highestTrashedRevision(of id: UUID) throws -> Int {
        if trashedRevisions == nil {
            var highest: [UUID: Int] = [:]
            for name in (try fileSystem.contentsOfDirectory(layout.trash)).compactMap(RunsV3TrashName.parse) {
                highest[name.id] = max(highest[name.id] ?? 0, name.rev)
            }
            trashedRevisions = highest
        }
        return trashedRevisions?[id] ?? 0
    }

    // MARK: - Baseline (spec 2.6, 8)

    /// The v2 reconciliation point; nil when there is none (a history not made by the migration)
    /// or it cannot be read.
    func readBaseline() -> RunsV3BaselineV1? {
        guard let data = try? fileSystem.readFile(layout.baseline) else { return nil }
        return try? decoder.decode(RunsV3BaselineV1.self, from: data)
    }

    /// Replaces baseline.json and makes it durable (write, then the barrier). The merge calls
    /// this only after the drain that applied it was durable.
    func writeBaseline(_ baseline: RunsV3BaselineV1) throws {
        guard let mode else { throw RunsV3StoreError.notOpen }
        guard mode == .writable else { throw RunsV3StoreError.readOnly }
        try writer.write(try encoder.encode(baseline), to: layout.baseline, protection: RunsV3.protection)
        try writer.barrier(directories: [layout.root])
    }

    /// Ids with a deletion recorded in trash (any revision).
    func deletedIDs() -> Set<UUID> {
        let names = (try? fileSystem.contentsOfDirectory(layout.trash)) ?? []
        return Set(names.compactMap(RunsV3TrashName.parse).filter { $0.reason == .deleted || $0.reason == .merged }.map(\.id))
    }

    /// What a migrated history records about where it came from (format.json), or nil.
    func migratedFrom() -> RunsV3FormatV1.Source? {
        guard let data = try? fileSystem.readFile(layout.format) else { return nil }
        return (try? decoder.decode(RunsV3FormatV1.self, from: data))?.migratedFrom
    }

    private func writeIndex() throws {
        let ordered = history
        let index = RunsV3IndexV1(
            formatVersion: 1, minimumReaderVersion: 1, generation: indexGeneration + 1,
            entries: ordered.map { .init(id: $0.id, rev: $0.rev, seq: $0.seq, size: $0.size, sha256: $0.sha256, summary: $0.summary) })
        try writer.write(try encoder.encode(index), to: layout.index, protection: RunsV3.protection)
        indexGeneration += 1
        indexStale = false
        // Keep the highest revision ever listed: an older index generation may still be on disk
        // after a power loss, so a new revision must exceed what any of them listed.
        for entry in ordered { onDiskIndexRevisions[entry.id] = max(onDiskIndexRevisions[entry.id] ?? 0, entry.rev) }
    }

    /// After an index naming their successors is on disk: unlink superseded revisions, or keep
    /// them in trash when the edit removed detail. Failures are left for the next launch.
    private func retireSuperseded() {
        for (id, retirement) in pendingRetirement {
            guard let live = entries[id], live.rev > retirement.rev,
                  revisions[id]?.contains(retirement.rev) == true else { continue }
            let name = RunsV3FileName(id: id, rev: retirement.rev)
            retiredSinceBarrier.insert(id)
            if retirement.detailRemoved {
                try? moveToTrash(name, reason: .superseded)
            } else {
                fileSystem.remove(layout.runFile(name))
                if var revs = revisions[id] {
                    revs.removeAll { $0 == retirement.rev }
                    revisions[id] = revs.isEmpty ? nil : revs
                }
            }
        }
        pendingRetirement = [:]
    }

    // MARK: - Trash purge (spec 3.6)

    /// Unlinks trash files older than 30 days, then the oldest superseded ones and deleted ones
    /// older than 7 days while trash exceeds 200 MB. A `deleted` or `merged` file is kept while
    /// the index.json on disk lists its id. Returns how many files were removed.
    @discardableResult
    func purgeTrash() throws -> Int {
        guard let mode else { throw RunsV3StoreError.notOpen }
        guard mode == .writable else { throw RunsV3StoreError.readOnly }
        let now = environment.now()
        let protected: Set<UUID>
        if let data = try readIfPresent(layout.index), let index = try? decoder.decode(RunsV3IndexV1.self, from: data) {
            protected = Set(index.entries.map(\.id))
        } else {
            protected = Set(onDiskIndexRevisions.keys).union(entries.keys)
        }
        var files: [(name: RunsV3TrashName, size: Int)] = []
        for raw in try fileSystem.contentsOfDirectory(layout.trash) {
            guard let name = RunsV3TrashName.parse(raw),
                  let info = try fileSystem.itemInfo(layout.trash.appendingPathComponent(raw)), info.kind == .file else { continue }
            files.append((name, info.size))
        }
        func isEvidence(_ name: RunsV3TrashName) -> Bool {
            (name.reason == .deleted || name.reason == .merged) && protected.contains(name.id)
        }
        func age(_ name: RunsV3TrashName) -> TimeInterval { now.timeIntervalSince1970 - Double(name.milliseconds) / 1000 }
        var removed = 0
        var kept: [(name: RunsV3TrashName, size: Int)] = []
        for file in files {
            if age(file.name) > Self.trashRetention && !isEvidence(file.name) {
                fileSystem.remove(layout.trash.appendingPathComponent(file.name.string))
                removed += 1
            } else {
                kept.append(file)
            }
        }
        var total = kept.reduce(0) { $0 + $1.size }
        let candidates = kept.filter { $0.name.reason == .superseded }.sorted { $0.name.milliseconds < $1.name.milliseconds }
            + kept.filter { ($0.name.reason == .deleted || $0.name.reason == .merged)
                && age($0.name) > Self.trashCapDeletedMinimumAge && !isEvidence($0.name) }
                .sorted { $0.name.milliseconds < $1.name.milliseconds }
        for file in candidates where total > Self.trashCapBytes {
            fileSystem.remove(layout.trash.appendingPathComponent(file.name.string))
            total -= file.size
            removed += 1
        }
        return removed
    }

    // MARK: - Wipe (spec 3.8, steps 2 and 3)

    /// Deactivates runs_v3 with one rename, makes that durable, then deletes the retired
    /// directory. The caller removes runs_v2.json first (step 1). A kill after the rename leaves
    /// no history; the next `repair` deletes a retired directory left behind.
    static func wipe(storage: URL, fileSystem: DurableFileSystem, now: Date) throws {
        let layout = RunsV3Layout(storage: storage)
        guard try fileSystem.itemInfo(layout.root) != nil else { return }
        let retired = storage.appendingPathComponent(
            RunsV3.retiredDirectoryPrefix + String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down))))
        try fileSystem.renameExclusive(layout.root, to: retired)
        try fileSystem.synchronizeDirectory(storage)
        try fileSystem.flushDevice(at: storage)
        try fileSystem.removeTree(retired)
    }
}
