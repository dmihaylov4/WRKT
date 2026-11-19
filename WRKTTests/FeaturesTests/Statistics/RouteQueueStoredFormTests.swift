import XCTest
import SwiftData
@testable import WRKT

/// A route queue pass that learns nothing new must not rewrite the runs file, and every pass
/// that does learn something must still write it before its task can complete.
@MainActor
final class RouteQueueStoredFormTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var container: ModelContainer!
    /// The manager holds its store weakly.
    private var store: WorkoutStoreV2!

    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }
    private var backups: URL { directory.appendingPathComponent("Backups") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "RouteQueueStoredFormTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        container = try ModelContainer(for: RouteFetchTask.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        store = nil
    }

    // MARK: - Fixture

    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000.25)

    /// A run as HealthKit reports it: timestamps carry sub-second precision the file drops.
    private static func healthKitRun(uuid: UUID = UUID(), withRoute: Bool = true) -> Run {
        let points = (0..<4).map { i in
            RoutePoint(lat: 48.2 + Double(i) * 0.001, lon: 16.3 + Double(i) * 0.001,
                       t: start.addingTimeInterval(Double(i) * 5 + 0.37), hr: 140 + Double(i))
        }
        let samples = (0..<6).map { i in
            HeartRateSample(timestamp: start.addingTimeInterval(Double(i) * 4.2 + 0.613), bpm: 139.5 + Double(i))
        }
        return Run(date: start.addingTimeInterval(1800), distanceKm: 5.123456789, durationSec: 1800,
                   healthKitUUID: uuid, avgHeartRate: 142.33333333333334, maxHeartRate: 144.5,
                   minHeartRate: 139.5, hrSamples: samples, calories: 312.7,
                   route: withRoute ? points.map { Coordinate(lat: $0.lat, lon: $0.lon) } : nil,
                   routeWithHR: withRoute ? points : nil,
                   splits: [KilometerSplit(number: 1, distanceKm: 1, durationSec: 352)],
                   workoutType: "Running", avgRunningPower: 251.1, avgCadence: 171.25,
                   avgStrideLength: 1.12, avgGroundContactTime: 241.5, avgVerticalOscillation: 8.4)
    }

    /// What a fresh HealthKit read of `run` returns.
    private static func enrichment(of run: Run) -> HealthKitManager.DetailedRunEnrichment {
        .init(distanceKm: run.distanceKm, durationSec: run.durationSec, calories: run.calories,
              workoutType: run.workoutType ?? "Running", workoutName: run.workoutName,
              route: run.route, routeWithHR: run.routeWithHR, splits: run.splits,
              avgHeartRate: run.avgHeartRate, maxHeartRate: run.maxHeartRate, minHeartRate: run.minHeartRate,
              hrSamples: run.hrSamples, avgRunningPower: run.avgRunningPower, avgCadence: run.avgCadence,
              avgStrideLength: run.avgStrideLength, avgGroundContactTime: run.avgGroundContactTime,
              avgVerticalOscillation: run.avgVerticalOscillation)
    }

    /// Saves `runs` the way an earlier launch did and opens a store on a fresh storage, so the
    /// store holds what decoding the file gives, as on a real relaunch.
    private func relaunch(runs: [Run], tasks: [RouteFetchTask]) async throws -> (HealthKitManager, WorkoutStoreV2, WorkoutStorage) {
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts([], prIndex: [:])
        try await previous.saveRuns(runs)
        let storage = WorkoutStorage(directory: directory)
        store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        for task in tasks { container.mainContext.insert(task) }
        try container.mainContext.save()
        let manager = HealthKitManager()
        manager.modelContext = container.mainContext
        manager.workoutStore = store
        return (manager, store, storage)
    }

    private func task(for run: Run, createdDaysAgo days: Double = 0) -> RouteFetchTask {
        let task = RouteFetchTask(workoutUUID: run.healthKitUUID!.uuidString, workoutDate: run.date, allowAutoPost: false)
        task.createdAt = Date.now.addingTimeInterval(-days * 86_400)
        return task
    }

    private func backupCount() -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        return names.filter { $0.hasPrefix("runs_backup_") }.count
    }

    // MARK: - Nothing new learned

    func testPassWithEnrichmentMatchingStoredRunWritesNothingAndCompletesTask() async throws {
        let original = Self.healthKitRun()
        let routeTask = task(for: original)
        let (manager, store, _) = try await relaunch(runs: [original], tasks: [routeTask])
        let stamp = try XCTUnwrap(FileStamp(runsFile))
        // The precondition the phone showed: the fresh read differs in memory from the decoded run.
        XCTAssertNotEqual(store.runs.first, original)

        let succeeded = await manager.processRouteFetchQueue { _ in Self.enrichment(of: original) }

        XCTAssertTrue(succeeded)
        XCTAssertEqual(FileStamp(runsFile), stamp, "A pass that learned nothing rewrote the runs file")
        XCTAssertEqual(backupCount(), 0)
        XCTAssertEqual(routeTask.status, "completed")
    }

    func testOldTaskWithoutRouteAndUnchangedDataWritesNothingAndStillRecordsTheAttempt() async throws {
        let original = Self.healthKitRun(withRoute: false)
        let routeTask = task(for: original, createdDaysAgo: 200)
        let (manager, store, _) = try await relaunch(runs: [original], tasks: [routeTask])
        let stamp = try XCTUnwrap(FileStamp(runsFile))
        XCTAssertNotEqual(store.runs.first, original)

        await manager.processRouteFetchQueue { _ in Self.enrichment(of: original) }

        XCTAssertEqual(FileStamp(runsFile), stamp)
        XCTAssertEqual(routeTask.status, "failed")
        XCTAssertEqual(routeTask.attemptCount, 1)
        XCTAssertNotNil(routeTask.lastAttemptDate)
    }

    // MARK: - Something new learned

    func testNewRouteIsWrittenAndCompletesTask() async throws {
        let withoutRoute = Self.healthKitRun(withRoute: false)
        let routeTask = task(for: withoutRoute)
        let (manager, _, storage) = try await relaunch(runs: [withoutRoute], tasks: [routeTask])
        let stamp = FileStamp(runsFile)
        let arrived = Self.healthKitRun(uuid: withoutRoute.healthKitUUID!)

        await manager.processRouteFetchQueue { _ in Self.enrichment(of: arrived) }

        XCTAssertNotEqual(FileStamp(runsFile), stamp)
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.routeWithHR?.count, 4)
        XCTAssertEqual(durable.first?.route?.count, 4)
        XCTAssertEqual(routeTask.status, "completed")
    }

    func testChangedHeartRateSampleIsWritten() async throws {
        let original = Self.healthKitRun()
        let (manager, _, storage) = try await relaunch(runs: [original], tasks: [task(for: original)])
        var changed = original
        changed.hrSamples![2] = HeartRateSample(timestamp: original.hrSamples![2].timestamp, bpm: 171)

        await manager.processRouteFetchQueue { _ in Self.enrichment(of: changed) }

        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.hrSamples?[2].bpm, 171)
    }

    func testChangedSplitIsWritten() async throws {
        let original = Self.healthKitRun()
        let (manager, _, storage) = try await relaunch(runs: [original], tasks: [task(for: original)])
        var changed = original
        changed.splits = [KilometerSplit(number: 1, distanceKm: 1, durationSec: 349)]

        await manager.processRouteFetchQueue { _ in Self.enrichment(of: changed) }

        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.splits?.first?.durationSec, 349)
    }

    // MARK: - Failed writes

    func testFailedWriteKeepsTaskPendingIsReportedAndTheIdenticalRetryStillWrites() async throws {
        let withoutRoute = Self.healthKitRun(withRoute: false)
        let routeTask = task(for: withoutRoute)
        let (manager, store, storage) = try await relaunch(runs: [withoutRoute], tasks: [routeTask])
        let arrived = Self.healthKitRun(uuid: withoutRoute.healthKitUUID!)
        // A directory in place of the file makes every run write fail.
        try FileManager.default.removeItem(at: runsFile)
        try FileManager.default.createDirectory(at: runsFile, withIntermediateDirectories: false)

        let failed = await manager.processRouteFetchQueue { _ in Self.enrichment(of: arrived) }

        XCTAssertFalse(failed)
        XCTAssertNotNil(manager.syncError)
        XCTAssertEqual(routeTask.status, "pending")
        XCTAssertEqual(routeTask.attemptCount, 0)

        // The retry learns nothing beyond what is already in memory, but the file never got it.
        try FileManager.default.removeItem(at: runsFile)
        XCTAssertEqual(store.runs.first?.routeWithHR?.count, 4)
        let retried = await manager.processRouteFetchQueue { _ in Self.enrichment(of: arrived) }

        XCTAssertTrue(retried)
        XCTAssertEqual(routeTask.status, "completed")
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.routeWithHR?.count, 4)
    }

    // MARK: - Retries

    func testRecentWorkoutRouteThatArrivesLateIsFetchedAndWritten() async throws {
        let withoutRoute = Self.healthKitRun(withRoute: false)
        let routeTask = task(for: withoutRoute)
        let (manager, _, storage) = try await relaunch(runs: [withoutRoute], tasks: [routeTask])

        await manager.processRouteFetchQueue { _ in Self.enrichment(of: withoutRoute) }
        XCTAssertEqual(routeTask.status, "pending", "A recent workout keeps waiting for its Watch route")

        let arrived = Self.healthKitRun(uuid: withoutRoute.healthKitUUID!)
        await manager.processRouteFetchQueue { _ in Self.enrichment(of: arrived) }

        XCTAssertEqual(routeTask.status, "completed")
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.routeWithHR?.count, 4)
    }

    func testManualRetryOfAFailedOldTaskFetchesARouteThatIsNowAvailable() async throws {
        let withoutRoute = Self.healthKitRun(withRoute: false)
        let routeTask = task(for: withoutRoute, createdDaysAgo: 200)
        routeTask.status = "failed"
        routeTask.attemptCount = 7
        let (manager, _, storage) = try await relaunch(runs: [withoutRoute], tasks: [routeTask])

        await manager.retryFailedRouteTaskIfNeeded(for: withoutRoute.healthKitUUID!)
        XCTAssertEqual(routeTask.status, "pending")
        XCTAssertEqual(routeTask.attemptCount, 0)

        let arrived = Self.healthKitRun(uuid: withoutRoute.healthKitUUID!)
        await manager.processRouteFetchQueue { _ in Self.enrichment(of: arrived) }

        XCTAssertEqual(routeTask.status, "completed")
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.routeWithHR?.count, 4)
    }

    // MARK: - Stored-form comparison

    func testStoredFormComparisonMatchesWhatTheFileWouldHold() async throws {
        let original = Self.healthKitRun()
        let (_, store, _) = try await relaunch(runs: [original], tasks: [])
        let decoded = try XCTUnwrap(store.runs.first)
        var heavier = original
        heavier.avgHeartRate = 150

        let identical = await store.runsEncodeIdentically([(decoded, original), (decoded, heavier), (decoded, decoded)])

        XCTAssertEqual(identical, [true, false, true])
    }

    func testRunThatCannotBeEncodedCountsAsChanged() async throws {
        let original = Self.healthKitRun()
        let (_, store, _) = try await relaunch(runs: [original], tasks: [])
        let decoded = try XCTUnwrap(store.runs.first)
        var unencodable = decoded
        unencodable.avgHeartRate = .nan

        let identical = await store.runsEncodeIdentically([(decoded, unencodable)])

        XCTAssertEqual(identical, [false])
    }
}
