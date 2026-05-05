//
//  WorkoutStorePRAttemptTests.swift
//  WRKTTests
//

import XCTest
@testable import WRKT

@MainActor
final class WorkoutStorePRAttemptTests: WRKTTestCase {
    private func makeStore() -> WorkoutStoreV2 {
        WorkoutStoreV2(repo: .shared)
    }

    private func workout(
        exercise: Exercise = TestFixtures.benchPress,
        date: Date = Date(),
        sets: [SetInput]
    ) -> CompletedWorkout {
        let entry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles,
            sets: sets
        )
        return CompletedWorkout(date: date, entries: [entry])
    }

    private func currentWorkout(
        exercise: Exercise = TestFixtures.benchPress,
        sets: [SetInput]
    ) -> CurrentWorkout {
        let entry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles,
            sets: sets
        )
        return CurrentWorkout(startedAt: Date(), entries: [entry])
    }

    func testPersonalRecordAttemptIgnoresCurrentUnsavedWorkout() {
        let store = makeStore()
        let exercise = TestFixtures.benchPress

        store.currentWorkout = currentWorkout(
            exercise: exercise,
            sets: [SetInput(reps: 12, weight: 100, tag: .working)]
        )

        XCTAssertNil(store.lastWorkingSet(exercise: exercise))
        XCTAssertNil(store.personalRecordAttempt(for: exercise))
    }

    func testPersonalRecordAttemptUsesCompletedWorkoutHistory() {
        let store = makeStore()
        let exercise = TestFixtures.benchPress

        store.addWorkout(workout(
            exercise: exercise,
            sets: [SetInput(reps: 12, weight: 100, tag: .working)]
        ))

        let attempt = store.personalRecordAttempt(for: exercise)

        XCTAssertEqual(attempt?.reps, 12)
        XCTAssertEqual(attempt?.weightKg, 102.5)
        XCTAssertEqual(attempt?.previousWeightAtReps, 100)
    }

    func testDeletedCompletedWorkoutNoLongerCountsForPersonalRecordAttempt() {
        let store = makeStore()
        let exercise = TestFixtures.benchPress
        let saved = workout(
            exercise: exercise,
            sets: [SetInput(reps: 12, weight: 100, tag: .working)]
        )

        store.addWorkout(saved)
        XCTAssertNotNil(store.personalRecordAttempt(for: exercise))

        store.deleteWorkout(saved)

        XCTAssertNil(store.bestWeightForExactReps(exercise: exercise, reps: 12))
        XCTAssertNil(store.lastWorkingSet(exercise: exercise))
        XCTAssertNil(store.personalRecordAttempt(for: exercise))
    }
}
