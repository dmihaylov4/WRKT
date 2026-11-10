import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class WorkoutSetGenerationTests: XCTestCase {
    func testExplicitFifthAndSixthSetsPreserveTimedExerciseValues() async throws {
        try await withStore { store in
            let exerciseID = UUID().uuidString
            let template = SetInput(reps: 0, weight: 0, tag: .backoff, isCompleted: true,
                durationSeconds: 45, trackingMode: .timed)
            store.currentWorkout = CurrentWorkout(entries: [
                WorkoutEntry(exerciseID: exerciseID, exerciseName: "Plank", muscleGroups: [],
                    sets: Array(repeating: template, count: 4))
            ])
            for expectedCount in [5, 6] {
                requestSet(store, exerciseID: exerciseID, complete: true)
                let sets = try XCTUnwrap(store.currentWorkout?.entries.first?.sets)
                XCTAssertEqual(sets.count, expectedCount)
                XCTAssertEqual(sets.last?.durationSeconds, 45)
                XCTAssertEqual(sets.last?.trackingMode, .timed)
                XCTAssertEqual(sets.last?.tag, .backoff)
                XCTAssertEqual(sets.last?.isCompleted, true)
            }
        }
    }

    func testPassiveGenerationKeepsCapAndExplicitLoggingUsesPrefilledFifthSet() async throws {
        try await withStore { store in
            let exerciseID = UUID().uuidString
            let completed = SetInput(reps: 10, weight: 0, isCompleted: true, trackingMode: .bodyweight)
            var entry = WorkoutEntry(exerciseID: exerciseID, exerciseName: "Push-up", muscleGroups: [],
                sets: Array(repeating: completed, count: 4))
            store.currentWorkout = CurrentWorkout(entries: [entry])
            requestSet(store, exerciseID: exerciseID, complete: false)
            XCTAssertEqual(store.currentWorkout?.entries.first?.sets.count, 4)

            entry.sets.append(SetInput(reps: 12, weight: 0, trackingMode: .bodyweight))
            entry.activeSetIndex = 4
            store.currentWorkout = CurrentWorkout(entries: [entry])
            requestSet(store, exerciseID: exerciseID, complete: true)
            let sets = try XCTUnwrap(store.currentWorkout?.entries.first?.sets)
            XCTAssertEqual(sets.count, 5)
            XCTAssertEqual(sets.last?.reps, 12)
            XCTAssertEqual(sets.last?.trackingMode, .bodyweight)
            XCTAssertEqual(sets.last?.isCompleted, true)
        }
    }

    private func requestSet(_ store: WorkoutStoreV2, exerciseID: String, complete: Bool) {
        let key = "pending_set_generation_exercises"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set([exerciseID], forKey: key)
        store.handleGeneratePendingSet(exerciseID: exerciseID, shouldLogSet: complete)
    }

    private func withStore(_ test: (WorkoutStoreV2) throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutSetGenerationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let storage = WorkoutStorage(directory: directory)
        try "migrated".write(to: directory.appendingPathComponent(".migrated"), atomically: true, encoding: .utf8)
        let container = try ModelContainer(for: DexStamp.self, RewardProgress.self, Wallet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let rewards = RewardsEngine()
        rewards.context = container.mainContext
        let store = WorkoutStoreV2(storage: storage, defaults: defaults, rewardsEngine: rewards)
        try await store.waitForStorage()
        try test(store)
        try await store.flushPendingSaves()
    }
}
