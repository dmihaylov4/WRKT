import XCTest
@testable import WRKT

/// The merge as the store runs it on the real disk (spec 8), the removal of the rolling run
/// backups, and runs in the export and import (spec 9), on both history formats.
@MainActor
final class RunsV3MergeStoreTests: XCTestCase {
    private var root: URL!
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3Merge-" + UUID().uuidString)
        directory = root.appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "RunsV3MergeStoreTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "runs.deduplication.v1")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static let history: [Run] = (1...12).map { V3.run($0, points: $0 % 3 == 0 ? 5 : 0, samples: $0 % 4 == 0 ? 3 : nil) }
    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }

    private func store(_ fs: DurableFileSystem = POSIXDurableFileSystem(), healthImport: Bool = false) async throws -> WorkoutStoreV2 {
        let storage = WorkoutStorage(directory: directory, fileSystem: fs, availableCapacity: { _ in 50_000_000_000 })
        let store = WorkoutStoreV2(storage: storage, defaults: defaults, protectedDataAvailable: { true },
                                   migrationGate: { true }, isHealthImportRunning: { healthImport })
        store.migrationDelay = .seconds(3600)
        store.mergeDelay = .seconds(3600)
        store.mergeImportWaitLimit = 0
        try await store.waitForStorage()
        return store
    }

    /// v2 seeded with `history`, then migrated (the real migration).
    private func migrated() async throws -> WorkoutStoreV2 {
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        try await WorkoutStorage(directory: directory).saveWorkouts([], prIndex: [:])
        try await WorkoutStorage(directory: directory).saveRuns(Self.history)
        let store = try await store()
        let result = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(result, .migrated)
        return store
    }

    /// What an older build leaves: runs_v2.json rewritten as 5.4.3 writes it (pretty, without
    /// the routeFromRouteWithHR marker), after `change`.
    private func olderBuildWrites(_ change: (inout [Run]) -> Void) throws {
        var runs = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: runsFile)).map(\.run)
        change(&runs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let stripped = runs.map { run -> Run in
            var copy = run
            if StoredRun.routeRepeatsRouteWithHR(copy) { copy.route = nil }
            return copy
        }
        try encoder.encode(stripped).write(to: runsFile, options: .atomic)
    }

    private func shown(_ store: WorkoutStoreV2) async throws -> [String] {
        var lines: [String] = []
        for summary in store.runSummaries {
            guard case .loaded(let run) = try await store.loadRun(id: summary.id) else { lines.append("unreadable"); continue }
            lines.append("\(run.id.uuidString.suffix(3)) \(run.distanceKm) \(run.workoutName ?? "-") \(run.route?.count ?? -1) \(run.routeWithHR?.count ?? -1)")
        }
        return lines
    }

    // MARK: - The merge

    func testAnOlderBuildsChangesAreMergedOnceAndThenLeftAlone() async throws {
        let v3 = try await migrated()
        // Meanwhile on v3: one new workout, one deleted, one edited.
        v3.addRun(V3.run(40))
        v3.removeRun(withId: V3.id(2))
        v3.editRun(RunEdit(id: V3.id(3), light: { $0.workoutName = "v3 edit" }))
        try await v3.flushHealthKitChanges()
        // The older build: imports 50, re-imports 40 under a new id, edits 4, deletes 6, and
        // keeps the v3-deleted 2 as it was.
        try olderBuildWrites { runs in
            var again = V3.run(40)
            again.id = V3.id(41)
            runs.insert(again, at: 0)
            runs.insert(V3.run(50, points: 2), at: 0)
            if let i = runs.firstIndex(where: { $0.id == V3.id(4) }) { runs[i].workoutName = "older build edit" }
            runs.removeAll { $0.id == V3.id(6) }
        }
        let back = try await store()
        XCTAssertTrue(back.isOnPerWorkoutHistory)
        let record = await back.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(record?.outcome, "merged")
        XCTAssertEqual(record?.counts?.added, 1)
        XCTAssertEqual(record?.counts?.replaced, 1)
        XCTAssertEqual(record?.counts?.trashed, 1)
        XCTAssertEqual(record?.counts?.deduplicated, 1)
        let ids = back.runSummaries.map(\.id)
        XCTAssertEqual(ids.first, V3.id(50))
        XCTAssertEqual(Set(ids), Set([V3.id(50), V3.id(40)] + Self.history.map(\.id)).subtracting([V3.id(2), V3.id(6)]))
        XCTAssertEqual(back.runSummary(id: V3.id(4))?.workoutName, "older build edit")
        XCTAssertEqual(back.runSummary(id: V3.id(3))?.workoutName, "v3 edit")
        guard case .loaded(let three) = try await back.loadRun(id: V3.id(3)) else { return XCTFail("3") }
        XCTAssertEqual(three.route?.count, 5, "the marker-free rewrite does not lose v3's route")
        let merged = try await shown(back)
        // The next launch: nothing more, without decoding runs_v2.json again.
        let again = try await store()
        let second = await again.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(second?.outcome, "unchanged: runs_v2.json as recorded")
        let againShown = try await shown(again)
        XCTAssertEqual(againShown, merged)
        XCTAssertEqual(again.lastRunHistoryMerge?.outcome, second?.outcome)
    }

    func testARestoreWithTheSameContentOnlyRecordsTheNewStamp() async throws {
        _ = try await migrated()
        let data = try Data(contentsOf: runsFile)
        try FileManager.default.removeItem(at: runsFile)
        try data.write(to: runsFile)   // same content, a new file number and date
        let back = try await store()
        let first = await back.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(first?.outcome, "recorded: same content under a new stamp (a restore): recorded")
        let next = try await store()
        let second = await next.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(second?.outcome, "unchanged: runs_v2.json as recorded")
    }

    func testADamagedOrMissingFrozenFileIsLoggedAndNeverBlocks() async throws {
        _ = try await migrated()
        let before = Self.history.map(\.id)
        try Data("{damaged".utf8).write(to: runsFile)
        let back = try await store()
        XCTAssertTrue(back.isStorageLoaded, "never the recovery screen")
        let damaged = await back.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(damaged?.outcome, "recorded: runs_v2.json changed but cannot be decoded: skipped")
        XCTAssertEqual(back.runSummaries.map(\.id), before)
        let next = try await store()
        let unchanged = await next.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(unchanged?.outcome, "unchanged: runs_v2.json as recorded")
        try FileManager.default.removeItem(at: runsFile)
        let gone = try await store()
        let goneRecord = await gone.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(goneRecord?.outcome, "recorded: runs_v2.json is gone: nothing to merge")
        XCTAssertEqual(gone.runSummaries.map(\.id), before, "a missing file never reads as every workout deleted")
    }

    func testTheValveHoldsBackAMassDeletion() async throws {
        _ = try await migrated()
        try olderBuildWrites { runs in runs.removeAll { [1, 2, 3, 4, 5, 6].map(V3.id).contains($0.id) } }
        let back = try await store()
        let record = await back.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(record?.outcome, "merged, deletions held back by the valve")
        XCTAssertEqual(record?.counts?.skippedByValve, 6)
        XCTAssertEqual(back.runSummaries.count, Self.history.count, "everything kept")
    }

    func testTheMergeWaitsForAHealthImport() async throws {
        _ = try await migrated()
        try olderBuildWrites { runs in runs.insert(V3.run(60), at: 0) }
        let busy = try await store(healthImport: true)
        let record = await busy.mergeOlderBuildChangesIfNeeded()
        XCTAssertEqual(record?.outcome, "skipped: a Health import is running")
        XCTAssertNil(busy.runSummary(id: V3.id(60)))
    }

    /// A kill at every file system call of the merge (real disk), then a relaunch that merges
    /// again: always the result of one uninterrupted merge.
    func testAKillAtEveryCallOfTheMergeGivesTheSameResult() async throws {
        _ = try await migrated()
        try olderBuildWrites { runs in
            runs.insert(V3.run(70, points: 3), at: 0)
            if let i = runs.firstIndex(where: { $0.id == V3.id(8) }) { runs[i].workoutName = "older" }
            runs.removeAll { $0.id == V3.id(9) }
        }
        let pristine = root.appendingPathComponent("pristine")
        try FileManager.default.copyItem(at: directory, to: pristine)
        let probe = FaultyFileSystem()
        let probeStore = try await store(probe)
        let start = probe.calls
        _ = await probeStore.mergeOlderBuildChangesIfNeeded()
        let total = probe.calls - start
        let expected = try await shown(try await store())
        XCTAssertEqual(expected.first?.hasPrefix("070"), true)
        for cut in 0..<total {
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.copyItem(at: pristine, to: directory)
            let faulty = FaultyFileSystem()
            let store = try await store(faulty)
            faulty.killAfter = faulty.calls + cut
            _ = await store.mergeOlderBuildChangesIfNeeded()
            let relaunched = try await self.store()
            _ = await relaunched.mergeOlderBuildChangesIfNeeded()
            let shownNow = try await shown(try await self.store())
            XCTAssertEqual(shownNow, expected, "cut at \(cut)")
        }
        print("store merge kills: \(total) calls")
    }

    // MARK: - Rolling run backups

    func testRollingRunBackupsGoAfterAVerifiedMigrationOnly() async throws {
        let backups = directory.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let kept = ["workouts_backup_2026-11-19T10-00-00Z_6F9619FF-8B86-D011-B42D-00C04FC964FF.json",
                    "runs_backup_2026-11-19T10-00-00Z_aaaaaaaa-8b86-d011-b42d-00c04fc964ff.json",
                    "runs_backup_2026-11-19T10-00-00Z.json", "runs_backup_notes.txt"]
        let removed = ["runs_backup_2026-11-19T10-00-00Z_6F9619FF-8B86-D011-B42D-00C04FC964FF.json",
                       "runs_backup_2026-11-18T09-30-12Z_00000000-0000-0000-0000-000000000001.json"]
        for name in kept + removed { try Data(count: 1000).write(to: backups.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: backups.appendingPathComponent("runs_backup_2026-11-17T09-30-12Z_00000000-0000-0000-0000-000000000002.json"),
                                                withIntermediateDirectories: false)
        let v2 = try await migrated()   // the v2 load does not remove anything
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.appendingPathComponent(removed[0]).path))
        v2.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "x" }))
        try await v2.flushHealthKitChanges()
        let back = try await store()   // the first runs_v3 launch
        XCTAssertTrue(back.isOnPerWorkoutHistory)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: backups.path))
        for name in removed { XCTAssertFalse(names.contains(name), name) }
        for name in kept { XCTAssertTrue(names.contains(name), name) }
        XCTAssertTrue(names.contains("runs_backup_2026-11-17T09-30-12Z_00000000-0000-0000-0000-000000000002.json"), "directories are never removed")
        XCTAssertFalse(names.contains { $0.hasPrefix("runs_backup_") && !kept.contains($0) && !$0.hasPrefix("runs_backup_2026-11-17") },
                       "no new whole-file run backup on runs_v3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runsFile.path), "the frozen runs_v2.json stays")
    }

    func testBackupsStayWhenAWorkoutIsUnavailableOrTheHistoryWasNotMigrated() async throws {
        let backups = directory.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = "runs_backup_2026-11-19T10-00-00Z_6F9619FF-8B86-D011-B42D-00C04FC964FF.json"
        try Data(count: 10).write(to: backups.appendingPathComponent(name))
        // Not made by a migration (no migratedFrom): kept.
        try V3Disk.seed(directory, Self.history)
        _ = try await store()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.appendingPathComponent(name).path))
        // Migrated, but a workout file is missing: kept.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("runs_v3"))
        _ = try await migrated()
        try FileManager.default.removeItem(at: RunsV3Layout(storage: directory).runFile(RunsV3FileName(id: V3.id(3), rev: 1)))
        try Data(count: 10).write(to: backups.appendingPathComponent(name))
        _ = try await store()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.appendingPathComponent(name).path))
    }

    // MARK: - Export and import

    private func export(_ store: WorkoutStoreV2, routes: Bool) async throws -> ExportBundle {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var bundle = ExportBundle(version: ExportBundle.currentVersion, appVersion: "test", exportedAt: V3.start,
                                  completedWorkouts: [], earnedPlates: [])
        bundle.runsWithoutDetail = !routes
        let url = root.appendingPathComponent("export-\(UUID().uuidString).json")
        try await DataPortabilityService.writeStreaming(head: try encoder.encode(bundle), to: url, encoder: encoder) { emit in
            _ = try await store.exportRuns { run in try emit(StoredRun(routes ? run : ExportBundle.withoutDetail(run))) }
        }
        return try RunsV3.makeDecoder().decode(ExportBundle.self, from: Data(contentsOf: url))
    }

    func testExportAndImportOnBothFormats() async throws {
        for format in ["v2", "v3"] {
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source: WorkoutStoreV2
            if format == "v3" {
                source = try await migrated()
            } else {
                try Data().write(to: directory.appendingPathComponent(".migrated"))
                try await WorkoutStorage(directory: directory).saveRuns(Self.history)
                source = try await store()
            }
            let full = try await export(source, routes: true)
            XCTAssertEqual(full.version, 2)
            XCTAssertEqual(full.runs?.map(\.run), Self.history, format)
            XCTAssertEqual(full.runsWithoutDetail, false)
            let light = try await export(source, routes: false)
            XCTAssertEqual(light.runs?.map(\.run.id), Self.history.map(\.id))
            XCTAssertTrue(light.runs?.allSatisfy { $0.run.routeWithHR == nil && $0.run.route == nil && $0.run.hrSamples == nil } == true)
            XCTAssertEqual(light.runs?.map(\.run.distanceKm), Self.history.map(\.distanceKm))

            // Import into the same history: everything is already there.
            let same = try await source.importRuns(Self.history)
            XCTAssertEqual(same, 0)
            // Into a history missing some, with a Health duplicate under another id: only the missing.
            source.removeRun(withId: V3.id(5))
            source.removeRun(withId: V3.id(6))
            try await source.flushHealthKitChanges()
            var twin = Self.history[0]
            twin.id = UUID()
            let added = try await source.importRuns(try XCTUnwrap(full.runs).map(\.run) + [twin])
            XCTAssertEqual(added, 2, format)
            XCTAssertEqual(Set(source.runSummaries.map(\.id)), Set(Self.history.map(\.id)), format)
        }
    }

    func testAVersionOneBackupStillImportsAndAReadOnlyHistoryAddsNothing() async throws {
        let v1 = Data(#"{"version":1,"appVersion":"5.4.3","exportedAt":"2026-11-01T10:00:00Z","completedWorkouts":[],"earnedPlates":[]}"#.utf8)
        let bundle = try RunsV3.makeDecoder().decode(ExportBundle.self, from: v1)
        XCTAssertEqual(bundle.version, 1)
        XCTAssertNil(bundle.runs)
        try V3Disk.seed(directory, Self.history, format: RunsV3FormatV1(formatVersion: 2, minimumReaderVersion: 1, minimumWriterVersion: 2,
                                                                          createdAt: V3.start, createdByBuild: "future", migratedFrom: nil))
        let readOnly = try await store()
        let added = try await readOnly.importRuns([V3.run(90)])
        XCTAssertEqual(added, 0)
    }

    // MARK: - Wipe

    /// The development wipe on runs_v3: runs_v2.json first, then runs_v3 (baseline with it):
    /// nothing can bring the history back.
    func testAWipedDeviceDoesNotGetItsHistoryBack() async throws {
        _ = try await migrated()
        try await WorkoutStorage(directory: directory).wipeAllData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: runsFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("runs_v3").path))
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let back = try await store()
        XCTAssertTrue(back.runSummaries.isEmpty)
        let record = await back.mergeOlderBuildChangesIfNeeded()
        XCTAssertNil(record, "no runs_v3: no merge")
    }
}
