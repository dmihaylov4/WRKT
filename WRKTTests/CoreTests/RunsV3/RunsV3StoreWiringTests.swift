import SwiftData
import HealthKit
import XCTest
@testable import WRKT

/// The store with the per-workout history behind it (spec 3.4, 3.7, 4, 5): the switch, both
/// paths through the same API, handles, the modes, and the Health anchor rule.
@MainActor
final class RunsV3StoreWiringTests: XCTestCase {
    private var root: URL!
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3Wiring-" + UUID().uuidString)
        directory = root.appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "RunsV3StoreWiringTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "runs.deduplication.v1")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func store(_ fileSystem: DurableFileSystem = POSIXDurableFileSystem(),
                       protectedData: @escaping @MainActor () -> Bool = { true }) async throws -> WorkoutStoreV2 {
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory, fileSystem: fileSystem),
                                   defaults: defaults, protectedDataAvailable: protectedData)
        try await store.waitForStorage()
        return store
    }

    private static func run(_ n: Int, points: Int = 0, name: String? = nil) -> Run { V3.run(n, points: points, name: name) }

    private func describe(_ store: WorkoutStoreV2) async throws -> [String] {
        var lines: [String] = []
        for summary in store.runSummaries {
            guard case .loaded(let run) = try await store.loadRun(id: summary.id) else {
                lines.append("\(summary.id.uuidString.suffix(4)) unreadable")
                continue
            }
            XCTAssertEqual(RunSummary(run), summary)
            lines.append("\(summary.id.uuidString.suffix(4)) \(run.distanceKm) \(run.workoutName ?? "-") \(run.routeWithHR?.count ?? -1) \(run.hrSamples?.count ?? -1)")
        }
        return lines
    }

    // MARK: - The switch

    /// With no runs_v3 entry the app runs today's code and creates nothing new on disk.
    func testWithoutRunsV3AFullCycleUsesTodaysFilesOnly() async throws {
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let seedStorage = WorkoutStorage(directory: directory)
        try await seedStorage.saveWorkouts([], prIndex: [:])
        try await seedStorage.saveRuns([Self.run(1, points: 4), Self.run(2)])
        let store = try await store()
        XCTAssertEqual(store.runsV3CachedRunCount, 0)
        store.addRun(Self.run(3))
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "edited" }))
        _ = await store.editRunsIfStoredFormChanges([RunEdit(id: V3.id(2), light: { $0.calories = 1 })])
        store.removeRun(withId: V3.id(2))
        store.addIgnoredHealthKitUUID(UUID())
        try await store.flushHealthKitChanges()
        let relaunched = try await self.store()
        XCTAssertEqual(relaunched.runSummaries.map(\.id), [V3.id(3), V3.id(1)])
        let names = V3Disk.tree(directory).filter { !$0.hasPrefix("Backups/") }
        XCTAssertEqual(Set(names), ["Backups", ".migrated", "runs_v2.json", "workouts_v2.json", "ignored_healthkit_uuids.json"])
        XCTAssertFalse(names.contains { $0.contains("runs_v3") || $0.contains("tmp") })
    }

    func testStartupValidationSkipsTheFrozenV2FileOnlyWhenRunsV3Exists() throws {
        let documents = root.appendingPathComponent("Documents")
        let storage = documents.appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try Data().write(to: storage.appendingPathComponent(".migrated"))
        try Data("{damaged".utf8).write(to: storage.appendingPathComponent("runs_v2.json"))
        let support = root.appendingPathComponent("Support")
        XCTAssertThrowsError(try WorkoutStorage.validateExistingData(applicationSupport: support, documents: documents),
                             "today: a damaged runs_v2.json keeps the app on the recovery screen")
        try V3Disk.seed(storage, [Self.run(1)])
        let history = try XCTUnwrap(try WorkoutStorage.validateExistingData(applicationSupport: support, documents: documents))
        XCTAssertNil(history.runs, "runs_v2.json is not decoded once runs_v3 exists")
        XCTAssertEqual(history.runsV3?.history.map(\.id), [V3.id(1)])
    }

    // MARK: - Same script, both paths

    /// The writers' scripted sequence (as in RunHistoryDiskReplayTests) through the store API,
    /// once on each path: the same history after a relaunch.
    func testTheWritersScriptEndsWithTheSameHistoryOnBothPaths() async throws {
        let seed = [Self.run(1, points: 5), Self.run(2), Self.run(3)]
        // v2
        let v2Root = root.appendingPathComponent("v2")
        let v2Dir = v2Root.appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: v2Dir, withIntermediateDirectories: true)
        try Data().write(to: v2Dir.appendingPathComponent(".migrated"))
        try await WorkoutStorage(directory: v2Dir).saveRuns(seed)
        let v2 = WorkoutStoreV2(storage: WorkoutStorage(directory: v2Dir), defaults: defaults)
        try await v2.waitForStorage()
        try await script(v2)
        // v3
        try V3Disk.seed(directory, seed)
        let v3 = try await store()
        var noOpTrees: [String: [String]] = [:]
        try await script(v3) { name in noOpTrees[name] = V3Disk.tree(self.directory).filter { $0.hasPrefix("runs_v3/runs/") } }
        XCTAssertEqual(v3.runsV3SummaryMismatches, 0)
        // Steps that changed nothing wrote no workout file.
        for (before, after) in [("before duplicate", "import duplicate"), ("before unchanged", "import update unchanged"),
                                ("before delete missing", "delete missing")] {
            XCTAssertEqual(noOpTrees[before], noOpTrees[after], after)
        }

        let v2Back = WorkoutStoreV2(storage: WorkoutStorage(directory: v2Dir), defaults: defaults)
        try await v2Back.waitForStorage()
        let v3Back = try await store()
        XCTAssertEqual(v3Back.runSummaries.map(\.id), v2Back.runSummaries.map(\.id))
        let v2Lines = try await describe(v2Back)
        let v3Lines = try await describe(v3Back)
        XCTAssertEqual(v3Lines, v2Lines)
        XCTAssertEqual(v3Back.runSummaries, v2Back.runSummaries)
    }

    private func script(_ store: WorkoutStoreV2, checkpoint: (String) -> Void = { _ in }) async throws {
        store.addRun(Self.run(4, name: "Long"))
        try await store.flushHealthKitChanges()
        checkpoint("before duplicate")
        store.addRun(Self.run(4, name: "Long"))
        try await store.flushHealthKitChanges()
        checkpoint("import duplicate")
        store.editRun(RunEdit(id: V3.id(1), light: { $0.distanceKm = 5.2; $0.calories = 320 }))
        try await store.flushHealthKitChanges()
        checkpoint("before unchanged")
        store.editRun(RunEdit(id: V3.id(1), light: { $0.distanceKm = 5.2; $0.calories = 320 }))
        try await store.flushHealthKitChanges()
        checkpoint("import update unchanged")
        store.editRun(RunEdit(id: V3.id(3), light: { $0.avgHeartRate = 118 },
                              hrSamples: .some((0..<4).map { HeartRateSample(timestamp: V3.start.addingTimeInterval(Double($0) * 60), bpm: 100) })))
        try await store.flushHealthKitChanges()
        let route = (0..<7).map { RoutePoint(lat: 48 + Double($0) * 0.001, lon: 16, t: V3.start.addingTimeInterval(Double($0)), hr: 130) }
        let walk = RunEdit(id: V3.id(2), light: { $0.workoutName = "Walk" }, route: .some(route.map { Coordinate(lat: $0.lat, lon: $0.lon) }),
                           routeWithHR: .some(route), splits: .some([KilometerSplit(number: 1, distanceKm: 1, durationSec: 430)]))
        _ = await store.editRunsIfStoredFormChanges([walk])
        try await store.flushHealthKitChanges()
        _ = await store.editRunsIfStoredFormChanges([walk])   // nothing new
        try await store.flushHealthKitChanges()
        store.editRuns([V3.id(1), V3.id(4)].map { id in RunEdit(id: id, light: { $0.workoutName = "Renamed"; $0.durationSec += 1 }) })
        try await store.flushHealthKitChanges()
        store.removeRun(withId: V3.id(3))
        try await store.flushHealthKitChanges()
        checkpoint("before delete missing")
        store.removeRun(withId: V3.id(3))
        try await store.flushHealthKitChanges()
        checkpoint("delete missing")
    }

    // MARK: - Handles (spec 5.1)

    func testADetailHandleLoadsOffTheMainThreadAndFollowsEdits() async throws {
        try V3Disk.seed(directory, [Self.run(1, points: 6), Self.run(2)])
        let slow = FaultyFileSystem()
        let store = try await store(slow)
        slow.readDelay = 0.3
        let detail = store.runDetail(id: V3.id(1))
        XCTAssertTrue(detail.isLoading, "the first frame shows the loading state, not a stale run")
        try await waitUntil { !detail.isLoading }
        XCTAssertEqual(detail.run?.routeWithHR?.count, 6)
        // An edit while the screen is open updates it in the same main-actor turn.
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "open" }))
        XCTAssertEqual(detail.run?.workoutName, "open")
        XCTAssertEqual(store.runSummary(id: V3.id(1))?.workoutName, "open")
        // Removal keeps what the screen showed.
        store.removeRun(withId: V3.id(1))
        XCTAssertEqual(detail.phase, .unavailable(.removed))
        XCTAssertEqual(detail.run?.workoutName, "open")
        try await store.flushHealthKitChanges()
    }

    func testAnEditBeforeTheHandleLoadedIsShownOnceItLoads() async throws {
        try V3Disk.seed(directory, [Self.run(1, points: 6)])
        let slow = FaultyFileSystem()
        let store = try await store(slow)
        slow.readDelay = 0.3
        let detail = store.runDetail(id: V3.id(1))
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "early" }))
        try await waitUntil { !detail.isLoading }
        XCTAssertEqual(detail.run?.workoutName, "early")
        XCTAssertEqual(detail.run?.routeWithHR?.count, 6)
    }

    func testADamagedWorkoutFileShowsUnreadable() async throws {
        try V3Disk.seed(directory, [Self.run(1, points: 3), Self.run(2)])
        try Data("damaged".utf8).write(to: RunsV3Layout(storage: directory).runFile(RunsV3FileName(id: V3.id(1), rev: 1)))
        let store = try await store()
        let detail = store.runDetail(id: V3.id(1))
        try await waitUntil { !detail.isLoading }
        XCTAssertEqual(detail.phase, .unavailable(.unreadable))
        XCTAssertNil(detail.run)
        guard case .unreadable = try await store.loadRun(id: V3.id(1)) else { return XCTFail("expected unreadable") }
        XCTAssertEqual(store.runSummaries.count, 2, "the workout stays listed")
    }

    func testAHandleThatGoesAwayIsNotReadFor() async throws {
        try V3Disk.seed(directory, [Self.run(1, points: 3)])
        let slow = FaultyFileSystem()
        let store = try await store(slow)
        slow.readDelay = 0.2
        // Occupy the queue so the handle's read waits its turn, then drop the handle.
        store.addRun(Self.run(9))
        var detail: RunDetail? = store.runDetail(id: V3.id(1))
        XCTAssertTrue(detail?.isLoading == true)
        detail = nil
        try await store.flushHealthKitChanges()
        XCTAssertEqual(store.runsV3CachedRunCount, 1, "only the added run; the dropped handle's run was never read")
    }

    func testOnlyAFewRunsStayInMemory() async throws {
        let runs = (1...12).map { Self.run($0, points: 20) }
        try V3Disk.seed(directory, runs)
        let store = try await store()
        XCTAssertEqual(store.runsV3CachedRunCount, 0, "launch holds summaries only")
        for run in runs { _ = try await store.loadRun(id: run.id) }
        XCTAssertEqual(store.runsV3CachedRunCount, 3)
        let held = store.runDetail(id: V3.id(1))
        try await waitUntil { !held.isLoading }
        for run in runs.dropFirst() { _ = try await store.loadRun(id: run.id) }
        XCTAssertEqual(store.runsV3CachedRunCount, 4, "three recent plus the one a screen shows")
        XCTAssertNotNil(held.run)
    }

    func testLoadRunHonoursCancellation() async throws {
        try V3Disk.seed(directory, [Self.run(1, points: 3)])
        let slow = FaultyFileSystem()
        let store = try await store(slow)
        slow.readDelay = 0.3
        let task = Task { try await store.loadRun(id: V3.id(1)) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError { }
    }

    // MARK: - Writes and the anchor (spec 3.7)

    func testAFailedBarrierKeepsTheAnchorAndARelaunchLosesAndDuplicatesNothing() async throws {
        try V3Disk.seed(directory, [Self.run(1)])
        let faulty = FaultyFileSystem()
        let store = try await store(faulty)
        let container = try ModelContainer(for: HealthSyncAnchor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let anchor = HealthSyncAnchor(dataType: "all_workouts")
        container.mainContext.insert(anchor)
        try await anchor.commit(HKQueryAnchor(fromValue: 1), in: container.mainContext) { }
        let before = (anchor.anchorData, anchor.syncCount)

        let imported = Self.run(7)
        store.addRun(imported)
        faulty.failFlushes = 5
        do {
            try await anchor.commit(HKQueryAnchor(fromValue: 2), in: container.mainContext) { try await store.flushHealthKitChanges() }
            XCTFail("the anchor must not commit before the run is durable")
        } catch { }
        XCTAssertEqual(anchor.anchorData, before.0)
        XCTAssertEqual(anchor.syncCount, before.1)

        // Relaunch (the anchor did not move, so Health delivers the workout again).
        faulty.failFlushes = 0
        let relaunched = try await self.store()
        relaunched.addRun(imported)
        try await anchor.commit(HKQueryAnchor(fromValue: 2), in: container.mainContext) { try await relaunched.flushHealthKitChanges() }
        XCTAssertEqual(anchor.syncCount, before.1 + 1)
        XCTAssertEqual(relaunched.runSummaries.filter { $0.healthKitUUID == imported.healthKitUUID }.count, 1)
        let back = try await self.store()
        XCTAssertEqual(back.runSummaries.map(\.id), [V3.id(7), V3.id(1)])
    }

    func testTheFlushCoversTheIgnoredWorkoutsFileWithTheBarrier() async throws {
        try V3Disk.seed(directory, [Self.run(1)])
        let recording = RecordingDurableFileSystem()
        let store = try await store(recording)
        recording.reset()
        store.addIgnoredHealthKitUUID(UUID())
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "x" }))
        try await store.flushHealthKitChanges()
        let calls = recording.callsWithNames
        let ignored = try XCTUnwrap(calls.lastIndex(of: "rename ignored_healthkit_uuids.json"))
        let lastBarrier = try XCTUnwrap(calls.lastIndex { $0.hasPrefix("flushDevice") })
        XCTAssertLessThan(ignored, lastBarrier, "the ignored workouts file is covered by a barrier")
        recording.fail(.flushDevice)
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "y" }))
        do {
            try await store.flushHealthKitChanges()
            XCTFail("a failed barrier fails the flush")
        } catch { }
        recording.fail(nil)
        try await store.flushHealthKitChanges()
    }

    func testABurstOfChangesRewritesTheIndexOnce() async throws {
        try V3Disk.seed(directory, (1...5).map { Self.run($0) })
        let recording = RecordingDurableFileSystem()
        let store = try await store(recording)
        recording.reset()
        for n in 10..<30 { store.addRun(Self.run(n)); try await store.flushHealthKitChanges() }
        XCTAssertFalse(recording.callsWithNames.contains("rename index.json"), "no index write per change")
        try await waitUntil(timeout: 5) { recording.callsWithNames.contains("rename index.json") }
        XCTAssertEqual(recording.callsWithNames.filter { $0 == "rename index.json" }.count, 1)
        let back = try await self.store()
        XCTAssertEqual(back.runSummaries.count, 25)
    }

    func testDedupeAndClearWorkWithoutTheFullHistory() async throws {
        var twin = Self.run(2)
        twin.id = V3.id(20)
        try V3Disk.seed(directory, [Self.run(1), Self.run(2), twin])
        defaults.set(false, forKey: "runs.deduplication.v1")
        let store = try await store()
        XCTAssertEqual(store.runSummaries.map(\.id), [V3.id(1), V3.id(2)], "the later duplicate by Health id goes")
        try await store.flushHealthKitChanges()
        store.clearAllRuns()
        try await store.flushHealthKitChanges()
        let back = try await self.store()
        XCTAssertTrue(back.runSummaries.isEmpty)
    }

    // MARK: - Modes (spec 4)

    func testReadOnlyHistoryLoadsAndRefusesRunChanges() async throws {
        try V3Disk.seed(directory, [Self.run(1)], format: RunsV3FormatV1(formatVersion: 2, minimumReaderVersion: 1, minimumWriterVersion: 2,
                                                                          createdAt: V3.start, createdByBuild: "future", migratedFrom: nil))
        let before = V3Disk.tree(directory)
        let store = try await store()
        XCTAssertTrue(store.isStorageLoaded)
        XCTAssertEqual(store.runSummaries.map(\.id), [V3.id(1)])
        store.addRun(Self.run(2))
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "no" }))
        store.removeRun(withId: V3.id(1))
        XCTAssertEqual(store.runSummaries.map(\.id), [V3.id(1)])
        XCTAssertNil(store.runSummaries.first?.workoutName)
        do {
            try await store.flushHealthKitChanges()
            XCTFail("a read-only history never lets an anchor advance")
        } catch StorageError.runHistoryReadOnly { }
        XCTAssertEqual(V3Disk.tree(directory).filter { $0.hasPrefix("runs_v3") }, before.filter { $0.hasPrefix("runs_v3") })
        guard case .loaded = try await store.loadRun(id: V3.id(1)) else { return XCTFail("still readable") }
    }

    func testAHistoryNeedingANewerAppShowsTheUpdateScreen() async throws {
        try V3Disk.seed(directory, [Self.run(1)], format: RunsV3FormatV1(formatVersion: 2, minimumReaderVersion: 2, minimumWriterVersion: 2,
                                                                          createdAt: V3.start, createdByBuild: "future", migratedFrom: nil))
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try? await store.waitForStorage()
        XCTAssertFalse(store.isStorageLoaded)
        XCTAssertEqual((store.storageLoadError as? StorageError)?.needsNewerApp, true)
    }

    func testAnInvalidLayoutShowsTheRecoveryScreen() async throws {
        try Data("x".utf8).write(to: directory.appendingPathComponent("runs_v3"))
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try? await store.waitForStorage()
        XCTAssertFalse(store.isStorageLoaded)
        guard case StorageError.runHistoryInvalidLayout? = store.storageLoadError as? StorageError else {
            return XCTFail("expected the invalid layout error, got \(String(describing: store.storageLoadError))")
        }
    }

    func testBeforeTheFirstUnlockTheLoadWaitsAndThenRetries() async throws {
        try V3Disk.seed(directory, [Self.run(1)])
        var available = false
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults,
                                   protectedDataAvailable: { available })
        try? await store.waitForStorage()
        XCTAssertFalse(store.isStorageLoaded)
        XCTAssertNil(store.storageLoadError, "no recovery screen: the launch screen waits")
        available = true
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        try await waitUntil { store.isStorageLoaded }
        XCTAssertEqual(store.runSummaries.map(\.id), [V3.id(1)])
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
