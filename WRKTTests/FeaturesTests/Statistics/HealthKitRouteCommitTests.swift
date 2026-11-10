import XCTest
import SwiftData
import HealthKit
@testable import WRKT

@MainActor
final class HealthKitRouteCommitTests: XCTestCase {
    func testFailedRunWriteKeepsRoutePendingAndRetryCommitsBeforeCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "HealthKitRouteCommitTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let uuid = UUID()
        let run = Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: uuid)
        try await storage.saveRuns([run])
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        let container = try ModelContainer(for: RouteFetchTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let routeTask = RouteFetchTask(workoutUUID: uuid.uuidString, workoutDate: run.date, allowAutoPost: false)
        context.insert(routeTask)
        try context.save()
        let manager = HealthKitManager()
        manager.modelContext = context
        manager.workoutStore = store
        let runsFile = directory.appendingPathComponent("runs_v2.json")
        try FileManager.default.removeItem(at: runsFile)
        try FileManager.default.createDirectory(at: runsFile, withIntermediateDirectories: false)

        await manager.processRouteFetchQueue { _ in Self.enrichment() }
        XCTAssertEqual(routeTask.status, "pending", "A route job cannot finish before its run is durable")
        XCTAssertEqual(routeTask.attemptCount, 0, "Local storage failure must not exhaust HealthKit retries")

        try FileManager.default.removeItem(at: runsFile)
        await manager.processRouteFetchQueue { _ in Self.enrichment() }
        XCTAssertEqual(routeTask.status, "completed")
        let saved = try await storage.loadRuns()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.route?.count, 2)
        XCTAssertEqual(saved.first?.avgHeartRate, 145)
    }

    func testConcurrentDeliveryHasOneWorkerAndDeletionDuringQueryStaysDeleted() async throws {
        try await withFixture { manager, store, storage, routeTask in
            var resumeQuery: CheckedContinuation<Void, Never>?
            let first = Task { await manager.processRouteFetchQueue { _ in
                await withCheckedContinuation { resumeQuery = $0 }
                return Self.enrichment()
            } }
            while resumeQuery == nil { await Task.yield() }
            var secondQueryCount = 0
            let second = await manager.processRouteFetchQueue { _ in
                secondQueryCount += 1
                return Self.enrichment()
            }
            XCTAssertFalse(second)
            XCTAssertEqual(secondQueryCount, 0)
            store.clearAllRuns()
            try await store.flushHealthKitChanges()
            resumeQuery?.resume()
            _ = await first.value
            let saved = try await storage.loadRuns()
            XCTAssertTrue(saved.isEmpty)
            XCTAssertEqual(routeTask.status, "failed")
        }
    }

    func testCancellationAfterQueryPreservesPendingWorkWithoutSpendingRetry() async throws {
        try await withFixture { manager, _, _, routeTask in
            var resumeQuery: CheckedContinuation<Void, Never>?
            let worker = Task { await manager.processRouteFetchQueue { _ in
                await withCheckedContinuation { resumeQuery = $0 }
                return Self.enrichment()
            } }
            while resumeQuery == nil { await Task.yield() }
            worker.cancel()
            resumeQuery?.resume()
            let succeeded = await worker.value
            XCTAssertFalse(succeeded)
            XCTAssertEqual(routeTask.status, "pending")
            XCTAssertEqual(routeTask.attemptCount, 0)
            let retried = await manager.processRouteFetchQueue { _ in Self.enrichment() }
            XCTAssertTrue(retried)
            XCTAssertEqual(routeTask.status, "completed")
        }
    }

    func testLateRoutesRemainPendingAndDoNotStarveUnattemptedWork() async throws {
        try await withFixture { manager, store, _, firstTask in
            let secondUUID = UUID()
            let earlier = Date.now.addingTimeInterval(-3600)
            store.addRun(Run(date: earlier, distanceKm: 5, durationSec: 1800, healthKitUUID: secondUUID))
            let secondTask = RouteFetchTask(workoutUUID: secondUUID.uuidString, workoutDate: earlier, allowAutoPost: false)
            manager.modelContext?.insert(secondTask)
            try manager.modelContext?.save()
            var attempts: [UUID] = []
            for _ in 0..<2 {
                await manager.processRouteFetchQueue(limit: 1) { uuid in
                    attempts.append(uuid)
                    return Self.enrichment(hasRoute: false)
                }
            }
            XCTAssertEqual(attempts, [UUID(uuidString: firstTask.workoutUUID)!, secondUUID])
            XCTAssertEqual(firstTask.status, "pending")
            XCTAssertEqual(secondTask.status, "pending")
            XCTAssertEqual(firstTask.attemptCount, 1)
            XCTAssertEqual(secondTask.attemptCount, 1)
        }
    }

    func testLockedHealthDataPreservesRetryWithoutSpendingAttempt() async throws {
        try await withFixture { manager, _, _, routeTask in
            let succeeded = await manager.processRouteFetchQueue { _ in
                throw HKError(.errorDatabaseInaccessible)
            }
            XCTAssertFalse(succeeded)
            XCTAssertEqual(routeTask.status, "pending")
            XCTAssertEqual(routeTask.attemptCount, 0)
        }
    }

    private func withFixture(_ body: (HealthKitManager, WorkoutStoreV2, WorkoutStorage, RouteFetchTask) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "HealthKitRouteCommitTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let uuid = UUID()
        try await storage.saveRuns([Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: uuid)])
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        let container = try ModelContainer(for: RouteFetchTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let routeTask = RouteFetchTask(workoutUUID: uuid.uuidString, workoutDate: .now, allowAutoPost: false)
        container.mainContext.insert(routeTask)
        try container.mainContext.save()
        let manager = HealthKitManager()
        manager.modelContext = container.mainContext
        manager.workoutStore = store
        try await body(manager, store, storage, routeTask)
    }

    private static func enrichment(hasRoute: Bool = true) -> HealthKitManager.DetailedRunEnrichment {
        .init(distanceKm: 5, durationSec: 1800, calories: 300, workoutType: "Running", workoutName: nil,
              route: hasRoute ? [Coordinate(lat: 48.2, lon: 16.3), Coordinate(lat: 48.21, lon: 16.31)] : nil,
              routeWithHR: nil, splits: nil, avgHeartRate: 145, maxHeartRate: nil, minHeartRate: nil,
              hrSamples: nil, avgRunningPower: nil, avgCadence: nil, avgStrideLength: nil,
              avgGroundContactTime: nil, avgVerticalOscillation: nil)
    }
}
