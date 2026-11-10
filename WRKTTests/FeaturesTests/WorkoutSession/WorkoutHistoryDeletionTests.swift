import XCTest
@testable import WRKT

@MainActor
final class WorkoutHistoryDeletionTests: XCTestCase {
    func testHistoryLoadFailureIsVisibleAndRetryPreservesSavedWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutHistoryDeletionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let workout = TestFixtures.makeCompletedWorkout()
        try await storage.saveWorkouts([workout], prIndex: [:])
        let ignored = directory.appendingPathComponent("ignored_healthkit_uuids.json")
        try Data("{truncated".utf8).write(to: ignored)
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        do {
            try await store.waitForStorage()
            XCTFail("Unreadable deletion history must block edits")
        } catch { }
        XCTAssertFalse(store.isStorageLoaded)
        XCTAssertNotNil(store.storageLoadError)
        try Data("[]".utf8).write(to: ignored)
        store.retryStorageLoad()
        try await store.waitForStorage()
        XCTAssertTrue(store.isStorageLoaded)
        XCTAssertNil(store.storageLoadError)
        XCTAssertEqual(store.completedWorkouts.map(\.id), [workout.id])
        let saved = try await storage.loadWorkouts()
        XCTAssertEqual(saved.workouts.map(\.id), [workout.id])
    }

    func testCorruptActiveWorkoutBlocksWritesAndPreservesRecoveryData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutHistoryDeletionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let currentFile = directory.appendingPathComponent("current_workout_v2.json")
        let truncated = Data("{truncated workout".utf8)
        try truncated.write(to: currentFile)
        let relaunched = WorkoutStoreV2(storage: storage, defaults: defaults)
        do {
            try await relaunched.waitForStorage()
            XCTFail("Corruption must not be treated as a missing workout")
        } catch { }
        XCTAssertFalse(relaunched.isStorageLoaded)
        relaunched.startWorkoutIfNeeded()
        try await relaunched.flushPendingSaves()
        XCTAssertEqual(try Data(contentsOf: currentFile), truncated)
    }

    func testRelaunchPreservesActiveWorkoutAfterRecentBackgrounding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutHistoryDeletionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try "migrated".write(to: directory.appendingPathComponent(".migrated"), atomically: true, encoding: .utf8)
        let workout = CurrentWorkout(entries: [
            WorkoutEntry(exerciseID: UUID().uuidString, exerciseName: "Bench Press", muscleGroups: [],
                sets: [SetInput(reps: 8, weight: 60, isCompleted: true)])
        ])
        try await storage.saveCurrentWorkout(workout)
        // These keys were written by the previous app before ordinary backgrounding.
        defaults.set(true, forKey: "app.cleanShutdown")
        defaults.set(true, forKey: "app.hadActiveWorkout")
        defaults.set(Date(), forKey: "app.backgroundTimestamp")

        let relaunched = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await relaunched.waitForStorage()
        XCTAssertEqual(relaunched.currentWorkout?.id, workout.id)
        XCTAssertEqual(relaunched.currentWorkout?.entries.first?.sets.first?.reps, 8)
        let durable = try await storage.loadCurrentWorkout()
        XCTAssertEqual(durable?.id, workout.id, "Launch must never infer permission to discard")
    }

    func testDeletingAllHistoryDoesNotRestoreNonemptyBackupsOnLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutHistoryDeletionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let original = WorkoutStorage(directory: directory)
        try "migrated".write(to: directory.appendingPathComponent(".migrated"), atomically: true, encoding: .utf8)
        try await original.saveWorkouts([TestFixtures.makeCompletedWorkout()], prIndex: [:])
        try await original.saveRuns([Run(date: Date(), distanceKm: 5, durationSec: 1800)])

        // A new storage instance creates a backup before committing the deletion.
        let deletion = WorkoutStorage(directory: directory)
        try await deletion.saveWorkouts([], prIndex: [:])
        try await deletion.saveRuns([])
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Backups").path)
        XCTAssertEqual(backups.count, 2)

        let relaunched = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await relaunched.waitForStorage()
        XCTAssertTrue(relaunched.completedWorkouts.isEmpty, "Deleted strength workouts must stay deleted")
        XCTAssertTrue(relaunched.runs.isEmpty, "Deleted runs must stay deleted")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Backups").path).count, 2)
    }

    func testNewerDeletionWinsOverQueuedWorkoutSaves() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutHistoryDeletionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try "migrated".write(to: directory.appendingPathComponent(".migrated"), atomically: true, encoding: .utf8)
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        for _ in 0..<20 {
            store.addWorkout(TestFixtures.makeCompletedWorkout())
            store.clearAllWorkouts()
        }
        try await store.flushPendingSaves()
        let saved = try await WorkoutStorage(directory: directory).loadWorkouts()
        XCTAssertTrue(saved.workouts.isEmpty)
        XCTAssertTrue(saved.prIndex.isEmpty)
    }

    func testCorruptPrimaryCanBeExplicitlyRestoredWithoutDeletingBackups() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = WorkoutStorage(directory: directory)
        let workout = TestFixtures.makeCompletedWorkout()
        try await original.saveWorkouts([workout], prIndex: [:])
        let replacement = WorkoutStorage(directory: directory)
        try await replacement.saveWorkouts([], prIndex: [:])
        let backups = try await replacement.listBackups()
        let backup = try XCTUnwrap(backups.first)
        try Data("{truncated".utf8).write(to: directory.appendingPathComponent("workouts_v2.json"))
        do {
            _ = try await replacement.loadWorkouts()
            XCTFail("Corruption must not be represented as empty history")
        } catch {}
        try await replacement.restoreFromBackup(at: backup)
        let recovered = try await replacement.loadWorkouts()
        XCTAssertEqual(recovered.workouts.map(\.id), [workout.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }
}
