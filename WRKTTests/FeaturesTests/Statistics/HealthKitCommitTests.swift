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

    /// What the flush wrote must survive a power loss before the anchor commits: the barrier
    /// (`F_FULLFSYNC`) runs after the run and ignored-workout writes, and a failed barrier
    /// fails the flush like a failed write.
    func testAnchorCommitsOnlyAfterTheBarrierFollowingTheWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "HealthKitCommitTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let fileSystem = RecordingDurableFileSystem()
        let storage = WorkoutStorage(directory: directory, fileSystem: fileSystem)
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

        // A failed barrier: the files are written, but the anchor must not move.
        let run = Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: UUID())
        store.addRun(run)
        store.addIgnoredHealthKitUUID(UUID())
        fileSystem.fail(.flushDevice)
        do {
            try await anchor.commit(HKQueryAnchor(fromValue: 2), in: context) {
                try await store.flushHealthKitChanges()
            }
            XCTFail("The anchor must not commit before the barrier succeeds")
        } catch { }
        XCTAssertEqual(anchor.anchorData, originalData)
        XCTAssertEqual(anchor.syncCount, originalCount)

        // The next flush has nothing left to write, but must still run the barrier.
        fileSystem.fail(nil)
        fileSystem.reset()
        try await anchor.commit(HKQueryAnchor(fromValue: 2), in: context) {
            try await store.flushHealthKitChanges()
        }
        XCTAssertEqual(fileSystem.calls, [.flushDevice])
        XCTAssertEqual(anchor.syncCount, originalCount + 1)
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.map(\.id), [run.id])

        // A later flush writes the run file, then the barrier, in that order.
        fileSystem.reset()
        store.addRun(Run(date: .now, distanceKm: 3, durationSec: 900, healthKitUUID: UUID()))
        try await store.flushHealthKitChanges()
        let names = fileSystem.callsWithNames
        let rename = try XCTUnwrap(names.firstIndex(of: "rename runs_v2.json"))
        let barrier = try XCTUnwrap(names.lastIndex { $0.hasPrefix("flushDevice") })
        XCTAssertLessThan(rename, barrier)
        XCTAssertEqual(names.last.map { $0.hasPrefix("flushDevice") }, true)

        // With nothing written since the last barrier, a flush does not flush the device again.
        fileSystem.reset()
        try await store.flushHealthKitChanges()
        XCTAssertEqual(fileSystem.calls, [])
    }

    /// A process starts as if something were unflushed: a previous one may have written its
    /// files and been killed before its barrier.
    func testFirstFlushOfAProcessRunsTheBarrierEvenWithoutWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileSystem = RecordingDurableFileSystem()
        let storage = WorkoutStorage(directory: directory, fileSystem: fileSystem)
        try await storage.makeWritesDurable()
        XCTAssertEqual(fileSystem.calls, [.flushDevice])
        try await storage.makeWritesDurable()
        XCTAssertEqual(fileSystem.calls, [.flushDevice])
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
