import XCTest
@testable import WRKT

/// The migration as the store runs it (spec 7.1): off by default, its preconditions, the
/// switch, changes made while it runs, failures and the attempt limit, and a kill at every
/// file system call on the real disk followed by a relaunch.
@MainActor
final class RunsV3MigrationStoreTests: XCTestCase {
    private var root: URL!
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3Migration-" + UUID().uuidString)
        directory = root.appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "RunsV3MigrationStoreTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "runs.deduplication.v1")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static let history: [Run] = [V3.run(5, points: 6, samples: 2, splits: 1), V3.run(1), V3.run(9, points: 3),
                                         V3.run(2), V3.run(7)]

    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }

    private func seedV2(_ runs: [Run] = history) async throws {
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let storage = WorkoutStorage(directory: directory)
        try await storage.saveWorkouts([], prIndex: [:])
        try await storage.saveRuns(runs)
    }

    private func store(_ fs: DurableFileSystem = POSIXDurableFileSystem(), gate: Bool = true,
                       capacity: Int64? = 50_000_000_000, healthImport: Bool = false,
                       protectedData: Bool = true) async throws -> WorkoutStoreV2 {
        let storage = WorkoutStorage(directory: directory, fileSystem: fs, availableCapacity: { _ in capacity })
        let store = WorkoutStoreV2(storage: storage, defaults: defaults, protectedDataAvailable: { protectedData },
                                   migrationGate: { gate }, isHealthImportRunning: { healthImport })
        store.migrationDelay = .seconds(3600)
        try await store.waitForStorage()
        return store
    }

    /// Ids and stored forms, in history order, as a fresh launch shows them.
    private func shown(_ store: WorkoutStoreV2) async throws -> [String] {
        var lines: [String] = []
        let encoder = RunsV3.makeEncoder()
        for summary in store.runSummaries {
            guard case .loaded(let run) = try await store.loadRun(id: summary.id) else {
                lines.append("\(summary.id) unreadable")
                continue
            }
            lines.append(String(decoding: try encoder.encode(StoredRun(run)), as: UTF8.self))
        }
        return lines
    }

    private func expected(_ runs: [Run]) -> [String] {
        let encoder = RunsV3.makeEncoder()
        return runs.map { String(decoding: try! encoder.encode(StoredRun($0)), as: UTF8.self) }
    }

    private func names() -> Set<String> { Set(V3Disk.tree(directory).filter { !$0.hasPrefix("Backups/") && !$0.hasPrefix("runs_v3/") }) }

    // MARK: - Off

    /// The most important test of the batch: with the gate closed, launch and use create no
    /// staging directory and no runs_v3, whatever the opt-in key says without the launch argument.
    func testWithTheGateClosedNothingIsEverMigrated() async throws {
        XCTAssertFalse(RunHistoryConfiguration.migrationEnabled)
        XCTAssertFalse(RunHistoryConfiguration.migrationMayStart, "no launch argument in tests: the gate is closed")
        let previous = UserDefaults.standard.object(forKey: RunHistoryConfiguration.debugOptInKey)
        UserDefaults.standard.set(true, forKey: RunHistoryConfiguration.debugOptInKey)
        defer { UserDefaults.standard.set(previous, forKey: RunHistoryConfiguration.debugOptInKey) }
        XCTAssertFalse(RunHistoryConfiguration.debugOptIn(), "the key alone does not open it")
        XCTAssertTrue(RunHistoryConfiguration.debugOptIn(defaults: .standard, arguments: [RunHistoryConfiguration.debugOptInArgument]))

        try await seedV2()
        let storage = WorkoutStorage(directory: directory)
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)   // the production gate
        store.migrationDelay = .zero
        try await store.waitForStorage()
        store.addRun(V3.run(30))
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "x" }))
        store.removeRun(withId: V3.id(2))
        try await store.flushHealthKitChanges()
        let result = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(result, .notAllowed)
        try await Task.sleep(for: .milliseconds(200))
        let relaunched = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        relaunched.migrationDelay = .zero
        try await relaunched.waitForStorage()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(relaunched.isOnPerWorkoutHistory)
        let all = V3Disk.tree(directory)
        XCTAssertFalse(all.contains { $0.contains("runs_v3") || $0.contains("staging") || $0.contains("tmp") }, "\(all)")
        XCTAssertNil(defaults.object(forKey: RunHistoryConfiguration.lastAttemptKey))
    }

    func testTheReleaseBuildCompilesTheOptInOut() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Core/Persistence/RunsV3Format.swift")
        guard let text = try? String(contentsOf: source, encoding: .utf8) else { throw XCTSkip("sources not readable") }
        XCTAssertTrue(text.contains("static let migrationEnabled = false"))
        XCTAssertTrue(text.contains("static var migrationMayStart: Bool { migrationEnabled || debugOptIn() }"))
        let release = try XCTUnwrap(text.range(of: "#else\n    static func debugOptIn() -> Bool { false }\n    #endif"))
        let debug = try XCTUnwrap(text.range(of: "#if DEBUG\n    /// Debug-only opt-in"))
        XCTAssertLessThan(debug.lowerBound, release.lowerBound)
        XCTAssertFalse(text[debug.lowerBound..<release.lowerBound].contains("#else"), "the opt-in exists only in the DEBUG branch")
    }

    // MARK: - The migration

    func testTheMigrationSwitchesTheStoreAndLeavesRunsV2Alone() async throws {
        try await seedV2()
        let bytes = try Data(contentsOf: runsFile)
        let modified = try FileManager.default.attributesOfItem(atPath: runsFile.path)[.modificationDate] as? Date
        let store = try await store()
        let before = try await shown(store)
        let handle = store.runDetail(id: V3.id(5))
        let awaited1 = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited1, .migrated)
        XCTAssertTrue(store.isOnPerWorkoutHistory)
        XCTAssertEqual(store.runSummaries.map(\.id), Self.history.map(\.id))
        XCTAssertEqual(handle.run, Self.history[0], "an open screen keeps its workout")
        XCTAssertLessThanOrEqual(store.runsV3CachedRunCount, 1, "the full history is let go")
        XCTAssertEqual(try Data(contentsOf: runsFile), bytes, "runs_v2.json is never written")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: runsFile.path)[.modificationDate] as? Date, modified)
        XCTAssertEqual(try runsFile.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("runs_v3.staging").path))
        XCTAssertEqual(store.lastRunHistoryMigration?.result, "migrated")
        XCTAssertEqual(store.runHistoryMigrationAttempts, 0)
        let awaited2 = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited2, .skipped("already on runs_v3"))

        let relaunched = try await self.store()
        XCTAssertTrue(relaunched.isOnPerWorkoutHistory)
        let after = try await shown(relaunched)
        XCTAssertEqual(after, before)
        let awaited3 = await relaunched.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited3, .skipped("already on runs_v3"), "never repeated")
    }

    func testAnEmptyHistoryAndOneWorkoutMigrate() async throws {
        for runs in [[], [V3.run(3)]] as [[Run]] {
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await seedV2(runs)
            let store = try await store()
            let awaited4 = await store.migrateRunHistoryIfAllowed()
            XCTAssertEqual(awaited4, .migrated)
            let relaunched = try await self.store()
            let awaited5 = try await shown(relaunched)
            XCTAssertEqual(awaited5, expected(runs))
        }
    }

    /// Changes made while the migration runs are carried over and nothing is lost: the save
    /// queue holds every save behind the migration; the store, at the switch, queues the
    /// difference as per-workout changes; the whole-file saves queued meanwhile are dropped.
    func testChangesMadeWhileItRunsAreKept() async throws {
        try await seedV2()
        let slow = FaultyFileSystem()
        let store = try await store(slow)
        slow.createDelay = 0.05
        let migration = Task { await store.migrateRunHistoryIfAllowed() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(store.isOnPerWorkoutHistory, "still migrating")
        store.addRun(V3.run(40, points: 3))
        store.editRun(RunEdit(id: V3.id(9), light: { $0.workoutName = "during" }))
        store.removeRun(withId: V3.id(2))
        let flush = Task { try await store.flushHealthKitChanges() }
        let awaited6 = await migration.value
        XCTAssertEqual(awaited6, .migrated)
        try await flush.value
        slow.createDelay = 0
        var expectedRuns = Self.history.filter { $0.id != V3.id(2) }
        expectedRuns[2].workoutName = "during"
        expectedRuns.insert(V3.run(40, points: 3), at: 0)
        XCTAssertEqual(store.runSummaries.map(\.id), expectedRuns.map(\.id))
        XCTAssertEqual(store.runsV3SummaryMismatches, 0)
        let relaunched = try await self.store()
        XCTAssertTrue(relaunched.isOnPerWorkoutHistory)
        let awaited7 = try await shown(relaunched)
        XCTAssertEqual(awaited7, expected(expectedRuns))
    }

    /// After the switch runs_v2.json is frozen, even for a session still holding the whole-file
    /// history (if the migrated history could not be opened right after the switch).
    func testRunsV2IsFrozenOnceRunsV3Exists() async throws {
        try await seedV2()
        let bytes = try Data(contentsOf: runsFile)
        try V3Disk.seed(directory, Self.history)
        do {
            _ = try await WorkoutStorage(directory: directory).saveRuns([V3.run(70)])
            XCTFail("runs_v2.json must not be written once runs_v3 exists")
        } catch StorageError.runHistoryReadOnly { }
        XCTAssertEqual(try Data(contentsOf: runsFile), bytes)
    }

    // MARK: - Preconditions (none counts as an attempt)

    func testEachPreconditionStopsItBeforeAnything() async throws {
        try await seedV2()
        let before = names()
        func check(_ store: WorkoutStoreV2, _ expected: String, file: StaticString = #filePath, line: UInt = #line) async {
            let result = await store.migrateRunHistoryIfAllowed()
            guard case .skipped(let reason) = result, reason.contains(expected) else {
                return XCTFail("expected skipped(\(expected)), got \(result)", file: file, line: line)
            }
            XCTAssertEqual(store.runHistoryMigrationAttempts, 0, file: file, line: line)
            XCTAssertFalse(store.isOnPerWorkoutHistory, file: file, line: line)
        }
        let gateClosed = try await store(gate: false)
        let awaited8 = await gateClosed.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited8, .notAllowed)
        await check(try await store(protectedData: false), "protected data unavailable")
        await check(try await store(healthImport: true), "Health import")
        await check(try await store(capacity: 10_000_000), "notEnoughSpace")
        await check(try await store(capacity: nil), "notEnoughSpace")
        let busy = try await store()
        busy.startWorkoutIfNeeded()
        await check(busy, "workout is in progress")
        busy.discardCurrentWorkout()
        try? await busy.flushPendingSaves()
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("current_workout_v2.json"))
        defaults.set(3, forKey: RunHistoryConfiguration.attemptsKey(build: RunHistoryConfiguration.currentBuild))
        let limited = try await store()
        let result = await limited.migrateRunHistoryIfAllowed()
        XCTAssertEqual(result, .skipped("attempt limit reached for this build"))
        defaults.removeObject(forKey: RunHistoryConfiguration.attemptsKey(build: RunHistoryConfiguration.currentBuild))
        _ = before
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("runs_v3").path))
    }

    func testDuplicateIdsInTheSourceAreNeverMigrated() async throws {
        try await seedV2([V3.run(1), V3.run(1, distance: 9)])
        let store = try await store()
        let awaited9 = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited9, .skipped("duplicate workout ids"))
    }

    func testUnsavedChangesThatCannotBeSavedStopIt() async throws {
        try await seedV2()
        let faulty = FaultyFileSystem()
        let store = try await store(faulty)
        faulty.failWritesContaining = "runs_v2.json"
        store.addRun(V3.run(50))
        try? await store.flushPendingSaves()
        let result = await store.migrateRunHistoryIfAllowed()
        guard case .skipped(let reason) = result, reason.contains("unsaved") else { return XCTFail("\(result)") }
        XCTAssertEqual(store.runHistoryMigrationAttempts, 0)
        faulty.failWritesContaining = nil
        let awaited10 = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited10, .migrated, "once the change is saved")
        XCTAssertEqual(store.runSummaries.first?.id, V3.id(50))
    }

    // MARK: - Failures

    func testAFailedAttemptStaysOnV2CountsAndStopsAfterThree() async throws {
        try await seedV2()
        let faulty = FaultyFileSystem()
        faulty.failReadsContaining = "runs_v3.staging/runs/"   // verification cannot read back
        let store = try await store(faulty)
        for attempt in 1...3 {
            guard case .failed = await store.migrateRunHistoryIfAllowed() else { return XCTFail("attempt \(attempt)") }
            XCTAssertEqual(store.runHistoryMigrationAttempts, attempt)
            XCTAssertFalse(store.isOnPerWorkoutHistory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("runs_v3.staging").path))
            XCTAssertTrue(store.lastRunHistoryMigration?.result.hasPrefix("failed") == true)
        }
        let awaited11 = await store.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited11, .skipped("attempt limit reached for this build"))
        // The app keeps working on v2 exactly as before.
        store.addRun(V3.run(60))
        try await store.flushHealthKitChanges()
        let decoded = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: runsFile)).map(\.run)
        XCTAssertEqual(decoded.first?.id, V3.id(60))
    }

    /// A kill at every file system call of the whole migration (real disk), then a relaunch:
    /// the full history in the original order, on v2 or on v3, never a mixture; a retry then
    /// completes.
    func testAKillAtEveryCallLeavesTheFullHistory() async throws {
        try await seedV2()
        let pristine = root.appendingPathComponent("pristine")
        try FileManager.default.copyItem(at: directory, to: pristine)
        let probe = FaultyFileSystem()
        let probeStore = try await store(probe)
        let start = probe.calls
        let awaited12 = await probeStore.migrateRunHistoryIfAllowed()
        XCTAssertEqual(awaited12, .migrated)
        let total = probe.calls - start
        let original = expected(Self.history)
        var onV3 = 0
        for cut in 0..<total {
            defaults.removeObject(forKey: RunHistoryConfiguration.attemptsKey(build: RunHistoryConfiguration.currentBuild))
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.copyItem(at: pristine, to: directory)
            let faulty = FaultyFileSystem()
            let store = try await store(faulty)
            faulty.killAfter = faulty.calls + cut
            _ = await store.migrateRunHistoryIfAllowed()
            let relaunched = try await self.store()
            let awaited13 = try await shown(relaunched)
            XCTAssertEqual(awaited13, original, "cut at \(cut)")
            if relaunched.isOnPerWorkoutHistory {
                onV3 += 1
            } else {
                defaults.removeObject(forKey: RunHistoryConfiguration.attemptsKey(build: RunHistoryConfiguration.currentBuild))
                let awaited14 = await relaunched.migrateRunHistoryIfAllowed()
                XCTAssertEqual(awaited14, .migrated, "retry after a cut at \(cut)")
                let awaited15 = try await shown(try await self.store())
                XCTAssertEqual(awaited15, original, "cut at \(cut), after the retry")
            }
        }
        print("store migration kills: \(total) calls, \(onV3) left the switch done")
    }
}
