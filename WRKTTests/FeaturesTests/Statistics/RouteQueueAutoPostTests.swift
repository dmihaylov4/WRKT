import SwiftData
import XCTest
@testable import WRKT

/// A route queue pass posts a run once its route is stored. The task is completed by then and
/// never runs again, so the post must happen even if the pass is cancelled right after its commit.
@MainActor
final class RouteQueueAutoPostTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var container: ModelContainer!
    private var store: WorkoutStoreV2!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "RouteQueueAutoPostTests." + UUID().uuidString
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

    private final class PassBox {
        var pass: Task<Bool, Never>?
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000)

    func testAutoPostHappensEvenWhenThePassIsCancelledRightAfterItsCommit() async throws {
        let run = Run(date: Self.start, distanceKm: 5.2, durationSec: 1_800, healthKitUUID: UUID(), avgHeartRate: 150,
                      workoutType: "Running")
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts([], prIndex: [:])
        try await previous.saveRuns([run])
        defaults.set(true, forKey: "runs.deduplication.v1")
        store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        let task = RouteFetchTask(workoutUUID: run.healthKitUUID!.uuidString, workoutDate: run.date, allowAutoPost: true)
        container.mainContext.insert(task)
        try container.mainContext.save()

        let manager = HealthKitManager()
        manager.modelContext = container.mainContext
        manager.workoutStore = store
        var posted: [Run] = []
        manager.runAutoPost = { posted.append($0) }
        let box = PassBox()
        manager.routeQueueDidCommit = { box.pass?.cancel() }

        let route = (0..<6).map { RoutePoint(lat: 48.2 + Double($0) * 0.001, lon: 16.3, t: Self.start, hr: 150) }
        let read = HealthKitManager.DetailedRunEnrichment(
            distanceKm: 5.2, durationSec: 1_800, calories: nil, workoutType: "Running", workoutName: nil,
            route: route.map { Coordinate(lat: $0.lat, lon: $0.lon) }, routeWithHR: route, splits: nil, avgHeartRate: 150, maxHeartRate: nil, minHeartRate: nil,
            hrSamples: nil, avgRunningPower: nil, avgCadence: nil, avgStrideLength: nil, avgGroundContactTime: nil,
            avgVerticalOscillation: nil)
        box.pass = Task { await manager.processRouteFetchQueue { _ in read } }
        _ = await box.pass?.value
        XCTAssertEqual(task.status, "completed")

        for _ in 0..<100 where posted.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(posted.map(\.id), [run.id], "the completed task's run must still be posted")
        XCTAssertEqual(posted.first?.routeWithHR?.count, 6, "posted with the route the pass stored")
    }
}
