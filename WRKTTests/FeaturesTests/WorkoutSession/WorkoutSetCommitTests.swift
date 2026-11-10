import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class WorkoutSetCommitTests: XCTestCase {
    func testPausedHostControlsPersistAdjustmentAndSkipWithoutChangingNextRest() async throws {
        try await withFixture { store, _, defaults, _, timerStorage, _ in
            let now = Date()
            let timer = RestTimerManager(defaults: defaults, storage: timerStorage,
                observeSystemEvents: false, now: { now })
            timer.startTimer(duration: 90, exerciseID: "plank", exerciseName: "Plank")
            let id = try XCTUnwrap(timerStorage.load()?.id)
            try await timer.perform(.pause, timerID: id, operationID: UUID(), using: store)
            try await timer.perform(.adjust(15), timerID: id, operationID: UUID(), using: store)
            XCTAssertEqual(timer.state, .paused(remainingSeconds: 105, exerciseID: "plank",
                exerciseName: "Plank", originalDuration: 105, wasAdjusted: true))
            try await timer.perform(.skip, timerID: id, operationID: UUID(), using: store)
            XCTAssertTrue(timer.isCompleted)
            XCTAssertEqual(try timerStorage.load()?.appliedOperationIDs?.count, 3)
            XCTAssertEqual(timer.getRestDuration(), 90)
        }
    }

    func testDistinctAdjustmentsAccumulateAndReplayRemainsDeduplicatedAfterRelaunch() async throws {
        try await withFixture { store, _, defaults, _, timerStorage, _ in
            let timer = RestTimerManager(defaults: defaults, storage: timerStorage, observeSystemEvents: false)
            timer.startTimer(duration: 90, exerciseID: "plank", exerciseName: "Plank")
            let original = try XCTUnwrap(timerStorage.load())
            guard case .running(let initialEnd, _, _, _, _) = original.state else { return XCTFail() }
            let operations = [UUID(), UUID(), UUID()]
            for operation in operations {
                try await timer.perform(.adjust(15), timerID: original.id, operationID: operation, using: store)
            }
            let updated = try XCTUnwrap(timerStorage.load())
            guard case .running(let updatedEnd, _, _, _, _) = updated.state else { return XCTFail() }
            XCTAssertEqual(updatedEnd.timeIntervalSince(initialEnd), 45, accuracy: 0.001)
            XCTAssertEqual(updated.appliedOperationIDs, operations)

            let relaunched = RestTimerManager(defaults: defaults, storage: timerStorage, observeSystemEvents: false)
            try await relaunched.perform(.adjust(15), timerID: original.id, operationID: operations[0], using: store)
            XCTAssertEqual(try timerStorage.load()?.revision, updated.revision)
            XCTAssertEqual(try timerStorage.load()?.state, updated.state)
        }
    }

    func testStaleIntentCannotStopAReplacementTimer() async throws {
        try await withFixture { store, _, defaults, _, timerStorage, _ in
            let timer = RestTimerManager(defaults: defaults, storage: timerStorage, observeSystemEvents: false)
            timer.startTimer(duration: 90, exerciseID: "plank", exerciseName: "Plank")
            let old = try XCTUnwrap(timerStorage.load())
            timer.startTimer(duration: 60, exerciseID: "squat", exerciseName: "Squat")
            let replacement = try timerStorage.load()
            do {
                try await timer.perform(.stop, timerID: old.id, operationID: UUID(), using: store)
                XCTFail("An old activity must not stop the new timer")
            } catch { }
            XCTAssertEqual(try timerStorage.load(), replacement)
        }
    }

    func testHostActionAwaitsWorkoutRestorationBeforeLogging() async throws {
        try await withFixture { store, storage, defaults, rewards, timerStorage, _ in
            _ = try completedTimer(store: store, defaults: defaults, storage: timerStorage)
            let saved = try XCTUnwrap(timerStorage.load())
            let restoredTimer = RestTimerManager(defaults: defaults, storage: timerStorage, observeSystemEvents: false)
            let restoringStore = WorkoutStoreV2(storage: storage, defaults: defaults, rewardsEngine: rewards)
            try await restoredTimer.perform(.nextSet, timerID: saved.id, operationID: UUID(), using: restoringStore)
            XCTAssertTrue(restoringStore.isStorageLoaded)
            XCTAssertTrue(restoredTimer.isRunning)
            let durable = try await storage.loadCurrentWorkout()
            XCTAssertEqual(durable?.entries.first?.sets.count, 5)
            XCTAssertEqual(durable?.setLogReceipts.first?.operationID, saved.id)
        }
    }

    func testReceiptAndSetSurviveRelaunchAndDuplicateDelivery() async throws {
        try await withFixture { store, storage, defaults, rewards, _, _ in
            let workout = try XCTUnwrap(store.currentWorkout)
            let entry = try XCTUnwrap(workout.entries.first)
            let operationID = UUID()
            async let first = store.logNextSet(workoutID: workout.id, entryID: entry.id, exerciseID: entry.exerciseID,
                operationID: operationID, restDuration: 90)
            async let duplicate = store.logNextSet(workoutID: workout.id, entryID: entry.id, exerciseID: entry.exerciseID,
                operationID: operationID, restDuration: 90)
            let receipts = try await (first, duplicate)
            XCTAssertEqual(receipts.0, receipts.1)
            XCTAssertEqual(receipts.0.setIndex, 4)

            let saved = try await storage.loadCurrentWorkout()
            XCTAssertEqual(saved?.entries.first?.sets.count, 5)
            XCTAssertEqual(saved?.setLogReceipts, [receipts.0])
            XCTAssertEqual(saved?.entries.first?.sets.last?.durationSeconds, 45)
            XCTAssertEqual(saved?.entries.first?.sets.last?.restAfterSeconds, 90)
            XCTAssertNotNil(saved?.entries.first?.sets.last?.completionTime)

            let restarted = WorkoutStoreV2(storage: storage, defaults: defaults, rewardsEngine: rewards)
            let replayed = try await restarted.logNextSet(workoutID: workout.id, entryID: entry.id, exerciseID: entry.exerciseID,
                operationID: operationID, restDuration: 90)
            XCTAssertEqual(replayed, receipts.0)
            XCTAssertEqual(restarted.currentWorkout?.entries.first?.sets.count, 5)
        }
    }

    func testFailedWorkoutWriteDoesNotStartRestAndRetryDoesNotDuplicateSet() async throws {
        try await withFixture { store, storage, defaults, _, timerStorage, directory in
            let timer = try completedTimer(store: store, defaults: defaults, storage: timerStorage)
            let source = timer.state
            let currentFile = directory.appendingPathComponent("current_workout_v2.json")
            let preserved = directory.appendingPathComponent("preserved-current.json")
            try FileManager.default.moveItem(at: currentFile, to: preserved)
            try FileManager.default.createDirectory(at: currentFile, withIntermediateDirectories: false)
            do {
                try await timer.startNextSetTimer(using: store)
                XCTFail("A failed workout save must reject the action")
            } catch { }
            XCTAssertEqual(timer.state, source)

            try FileManager.default.removeItem(at: currentFile)
            try FileManager.default.moveItem(at: preserved, to: currentFile)
            try await timer.startNextSetTimer(using: store)
            XCTAssertTrue(timer.isRunning)
            let saved = try await storage.loadCurrentWorkout()
            XCTAssertEqual(saved?.entries.first?.sets.count, 5)
            XCTAssertEqual(saved?.setLogReceipts.count, 1)
        }
    }

    func testRetryAfterSetCommittedButTimerWriteFailedDoesNotLogAnotherSet() async throws {
        try await withFixture { store, storage, defaults, _, timerStorage, _ in
            let timer = try completedTimer(store: store, defaults: defaults, storage: timerStorage)
            let previousTimer = try Data(contentsOf: timerStorage.fileURL)
            try Data("unreadable timer".utf8).write(to: timerStorage.fileURL)
            do {
                try await timer.startNextSetTimer(using: store)
                XCTFail("A failed timer commit must reject the action")
            } catch { }
            let savedSet = try await storage.loadCurrentWorkout()
            XCTAssertEqual(savedSet?.entries.first?.sets.count, 5)
            XCTAssertTrue(timer.isCompleted)

            try previousTimer.write(to: timerStorage.fileURL)
            try await timer.startNextSetTimer(using: store)
            XCTAssertTrue(timer.isRunning)
            let retried = try await storage.loadCurrentWorkout()
            XCTAssertEqual(retried?.entries.first?.sets.count, 5)
            XCTAssertEqual(timer.getRestDuration(), 90)
        }
    }

    func testPrematureOrDifferentWorkoutActionIsRejected() async throws {
        try await withFixture { store, _, defaults, _, timerStorage, _ in
            let workout = try XCTUnwrap(store.currentWorkout)
            let entry = try XCTUnwrap(workout.entries.first)
            let timer = RestTimerManager(defaults: defaults, storage: timerStorage, observeSystemEvents: false)
            timer.startTimer(duration: 90, exerciseID: entry.exerciseID, exerciseName: entry.exerciseName,
                workoutID: workout.id, entryID: entry.id)
            do {
                try await timer.startNextSetTimer(using: store)
                XCTFail("A running rest must not log a set prematurely")
            } catch { }
            timer.skipTimer()
            store.currentWorkout = CurrentWorkout(entries: [entry])
            do {
                try await timer.startNextSetTimer(using: store)
                XCTFail("An old timer must not log against a new workout")
            } catch { }
            var swapped = workout
            swapped.entries[0].exerciseID = "different-exercise"
            store.currentWorkout = swapped
            do {
                try await timer.startNextSetTimer(using: store)
                XCTFail("An old timer must not log against a replacement exercise")
            } catch { }
            XCTAssertEqual(store.currentWorkout?.entries.first?.sets.count, 4)
            XCTAssertTrue(timer.isCompleted)
        }
    }

    private func completedTimer(store: WorkoutStoreV2, defaults: UserDefaults,
                                storage: RestTimerStorage) throws -> RestTimerManager {
        let workout = try XCTUnwrap(store.currentWorkout)
        let entry = try XCTUnwrap(workout.entries.first)
        let timer = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false)
        timer.startTimer(duration: 90, exerciseID: entry.exerciseID, exerciseName: entry.exerciseName,
            workoutID: workout.id, entryID: entry.id)
        timer.skipTimer()
        return timer
    }

    private func withFixture(_ test: (WorkoutStoreV2, WorkoutStorage, UserDefaults, RewardsEngine,
                                     RestTimerStorage, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutSetCommitTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: "auto_add_set_on_rest_timer")
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let container = try ModelContainer(for: DexStamp.self, RewardProgress.self, Wallet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let rewards = RewardsEngine()
        rewards.context = container.mainContext
        let completed = SetInput(reps: 0, weight: 0, tag: .backoff, isCompleted: true,
            durationSeconds: 45, trackingMode: .timed)
        let entry = WorkoutEntry(exerciseID: "plank", exerciseName: "Plank", muscleGroups: [],
            sets: Array(repeating: completed, count: 4))
        try await storage.saveCurrentWorkout(CurrentWorkout(entries: [entry]))
        let store = WorkoutStoreV2(storage: storage, defaults: defaults, rewardsEngine: rewards)
        try await store.waitForStorage()
        let timerStorage = RestTimerStorage(fileURL: directory.appendingPathComponent("timer.json"))
        try await test(store, storage, defaults, rewards, timerStorage, directory)
        try await store.flushPendingSaves()
    }
}
