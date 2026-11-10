import XCTest
import SwiftData
import HealthKit
@testable import WRKT

@MainActor
final class HealthKitCommitTests: XCTestCase {
    func testFailedRunWriteCannotBeMaskedByAnotherSaveOrAdvanceTheAnchor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "HealthKitCommitTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        let container = try ModelContainer(for: HealthSyncAnchor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let anchor = HealthSyncAnchor(dataType: "all_workouts")
        context.insert(anchor)
        try await anchor.commit(HKQueryAnchor(fromValue: 1), in: context) { }
        let originalData = anchor.anchorData
        let originalCount = anchor.syncCount

        let runsFile = directory.appendingPathComponent("runs_v2.json")
        // Block only run writes; an unrelated current-workout save still succeeds.
        try FileManager.default.createDirectory(at: runsFile, withIntermediateDirectories: false)
        let run = Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: UUID())
        store.addRun(run)
        store.startWorkoutIfNeeded()
        try await store.flushPendingSaves()
        do {
            try await anchor.commit(HKQueryAnchor(fromValue: 2), in: context) {
                try await store.flushHealthKitChanges()
            }
            XCTFail("The anchor must not acknowledge a failed run write")
        } catch { }
        XCTAssertEqual(anchor.anchorData, originalData)
        XCTAssertEqual(anchor.syncCount, originalCount)

        try FileManager.default.removeItem(at: runsFile)
        try await anchor.commit(HKQueryAnchor(fromValue: 2), in: context) {
            try await store.flushHealthKitChanges()
        }
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.map(\.id), [run.id])
        XCTAssertEqual(anchor.syncCount, originalCount + 1)
        XCTAssertNotEqual(anchor.anchorData, originalData)
    }

    func testCancelledDataCommitKeepsAnchorAndSyncMetadata() async throws {
        let container = try ModelContainer(for: HealthSyncAnchor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let anchor = HealthSyncAnchor(dataType: "exercise_time")
        context.insert(anchor)
        try await anchor.commit(HKQueryAnchor(fromValue: 1), in: context) { }
        let previous = (anchor.anchorData, anchor.lastSyncDate, anchor.syncCount)
        do {
            try await anchor.commit(HKQueryAnchor(fromValue: 2), in: context) { throw CancellationError() }
            XCTFail("A cancelled import cannot advance its anchor")
        } catch is CancellationError { }
        XCTAssertEqual(anchor.anchorData, previous.0)
        XCTAssertEqual(anchor.lastSyncDate, previous.1)
        XCTAssertEqual(anchor.syncCount, previous.2)
    }
}
