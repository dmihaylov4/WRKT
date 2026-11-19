import XCTest
import SwiftData
@testable import WRKT

/// Loading storage queues a failed route task again only once its last attempt is a week old,
/// so workouts that will never have a route are not queried on every launch, while data that
/// reaches HealthKit later is still picked up.
@MainActor
final class RouteTaskRepairRetryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(for: RouteFetchTask.self, MapSnapshotCache.self, HealthSyncAnchor.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDown() async throws { container = nil }

    /// A walk without a route, as HealthKit leaves it when the Watch recorded none.
    private func routelessWalk() -> Run {
        Run(date: .now.addingTimeInterval(-90 * 86_400), distanceKm: 2, durationSec: 1500,
            healthKitUUID: UUID(), workoutType: "Walking")
    }

    private func failedTask(for run: Run, lastAttemptDaysAgo days: Double?, attempts: Int = 3) throws -> RouteFetchTask {
        let task = RouteFetchTask(workoutUUID: run.healthKitUUID!.uuidString, workoutDate: run.date,
                                  allowAutoPost: false, attemptCount: attempts, status: "failed")
        task.lastAttemptDate = days.map { Date.now.addingTimeInterval(-$0 * 86_400) }
        context.insert(task)
        try context.save()
        return task
    }

    /// The manager has no workout store, so a queue pass the repair starts returns at once.
    private func repair(_ runs: [Run]) async -> HealthKitManager {
        let manager = HealthKitManager()
        manager.modelContext = context
        await manager.repairOperationalStateIfNeeded(runs: runs)
        return manager
    }

    func testRecentlyFailedTaskStaysFailed() async throws {
        let run = routelessWalk()
        XCTAssertTrue(run.needsHistoricalEnrichment)
        let task = try failedTask(for: run, lastAttemptDaysAgo: 1)

        _ = await repair([run])

        XCTAssertEqual(task.status, "failed")
        XCTAssertEqual(task.attemptCount, 3)
    }

    func testFailedTaskIsStillLeftAloneJustInsideTheInterval() async throws {
        let run = routelessWalk()
        let task = try failedTask(for: run, lastAttemptDaysAgo: 6.9)

        _ = await repair([run])

        XCTAssertEqual(task.status, "failed")
    }

    func testFailedTaskWhoseLastAttemptIsAWeekOldIsQueuedAgain() async throws {
        let run = routelessWalk()
        let task = try failedTask(for: run, lastAttemptDaysAgo: 7.1)

        _ = await repair([run])

        XCTAssertEqual(task.status, "pending")
        XCTAssertEqual(task.attemptCount, 0)
        XCTAssertNotNil(task.lastAttemptDate, "The last attempt is kept, so the next failure rests again")
    }

    func testFailedTaskWithNoRecordedAttemptIsQueuedAgain() async throws {
        let run = routelessWalk()
        let task = try failedTask(for: run, lastAttemptDaysAgo: nil)

        _ = await repair([run])

        XCTAssertEqual(task.status, "pending")
    }

    func testStuckFetchingTaskIsStillRecoveredAfterTwoMinutes() async throws {
        let run = routelessWalk()
        let task = RouteFetchTask(workoutUUID: run.healthKitUUID!.uuidString, workoutDate: run.date,
                                  allowAutoPost: false, attemptCount: 1, status: "fetching")
        task.lastAttemptDate = .now.addingTimeInterval(-300)
        context.insert(task)
        try context.save()

        _ = await repair([run])

        XCTAssertEqual(task.status, "pending")
    }

    func testOnlyDueTasksOfManyAreQueued() async throws {
        let runs = (0..<100).map { _ in routelessWalk() }
        // Attempts spread over the last 30 days, as a week of passes leaves them.
        let tasks = try runs.enumerated().map { index, run in
            try failedTask(for: run, lastAttemptDaysAgo: Double(index) * 0.3)
        }

        _ = await repair(runs)

        let queued = tasks.filter { $0.status == "pending" }.count
        XCTAssertEqual(queued, tasks.filter { ($0.lastAttemptDate ?? .distantPast) < .now.addingTimeInterval(-7 * 86_400) }.count)
        XCTAssertLessThan(queued, 100)
    }

    func testManualRetryResetsARecentlyFailedTask() async throws {
        let run = routelessWalk()
        let task = try failedTask(for: run, lastAttemptDaysAgo: 0.01)
        let manager = await repair([run])
        XCTAssertEqual(task.status, "failed")

        await manager.retryFailedRouteTaskIfNeeded(for: run.healthKitUUID!)

        XCTAssertEqual(task.status, "pending")
        XCTAssertEqual(task.attemptCount, 0)
    }
}
