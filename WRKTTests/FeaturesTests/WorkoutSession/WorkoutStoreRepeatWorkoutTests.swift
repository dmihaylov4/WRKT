//
//  WorkoutStoreRepeatWorkoutTests.swift
//  WRKTTests
//
//  Starting a past workout again from the Cut Train tab: the current workout it builds,
//  that it never replaces a workout in progress, and what it does with missing exercises.
//

import XCTest
@testable import WRKT

@MainActor
final class WorkoutStoreRepeatWorkoutTests: WRKTTestCase {
    private var directory: URL!
    private var suiteName: String!

    override func setUp() async throws {
        continueAfterFailure = true
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "WorkoutStoreRepeatWorkoutTests." + UUID().uuidString
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeLoadedStore() async throws -> WorkoutStoreV2 {
        let storage = WorkoutStorage(directory: directory)
        try "migrated".write(to: directory.appendingPathComponent(".migrated"), atomically: true, encoding: .utf8)
        let store = WorkoutStoreV2(repo: ExerciseRepository(), storage: storage,
                                   defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        try await store.waitForStorage()
        return store
    }

    private var lastTime: CompletedWorkout {
        let group = UUID()
        return CompletedWorkout(date: Date().addingTimeInterval(-86_400 * 2), entries: [
            WorkoutEntry(exerciseID: "bench", exerciseName: "Bench Press", muscleGroups: ["Chest"], sets: [
                SetInput(reps: 10, weight: 60, tag: .warmup, isCompleted: true),
                SetInput(reps: 8, weight: 100, tag: .working, isCompleted: true, rpe: 8),
                SetInput(reps: 6, weight: 105, tag: .working, isCompleted: true),
                SetInput(reps: 6, weight: 105, tag: .working, isCompleted: false)
            ], supersetGroupID: group, orderInSuperset: 0),
            WorkoutEntry(exerciseID: "row", exerciseName: "Barbell Row", muscleGroups: ["Back"], sets: [
                SetInput(reps: 10, weight: 70, tag: .working, isCompleted: true)
            ], supersetGroupID: group, orderInSuperset: 1),
            WorkoutEntry(exerciseID: "plank", exerciseName: "Plank", muscleGroups: ["Abs"], sets: [
                SetInput(reps: 0, weight: 0, isCompleted: true, durationSeconds: 60, trackingMode: .timed)
            ]),
            WorkoutEntry(exerciseID: "custom_deleted", exerciseName: "Old Custom", muscleGroups: ["Chest"], sets: [
                SetInput(reps: 12, weight: 20, isCompleted: true)
            ])
        ], workoutName: "Push Day")
    }

    private let inLibrary: (String) -> Bool = { $0 != "custom_deleted" }

    func testStartingAPastWorkoutBuildsTheExpectedCurrentWorkout() async throws {
        let store = try await makeLoadedStore()
        let source = lastTime
        store.addWorkout(source)

        XCTAssertTrue(store.startRepeatedWorkout(source, isAvailable: inLibrary))

        let current = try XCTUnwrap(store.currentWorkout)
        XCTAssertEqual(current.entries.map(\.exerciseID), ["bench", "row", "plank"])
        XCTAssertEqual(current.entries.map(\.exerciseName), ["Bench Press", "Barbell Row", "Plank"])
        XCTAssertEqual(current.activeEntryID, current.entries.first?.id)
        XCTAssertNil(current.plannedWorkoutID)
        XCTAssertLessThan(abs(current.startedAt.timeIntervalSinceNow), 5)

        let bench = current.entries[0].sets
        XCTAssertEqual(bench.map(\.reps), [10, 8, 6])
        XCTAssertEqual(bench.map(\.weight), [60, 100, 105])
        XCTAssertEqual(bench.map(\.tag), [.warmup, .working, .working])
        XCTAssertTrue(current.entries.flatMap(\.sets).allSatisfy { !$0.isCompleted && !$0.isGhost && $0.rpe == nil })
        XCTAssertEqual(current.entries[2].sets.first?.trackingMode, .timed)
        XCTAssertEqual(current.entries[2].sets.first?.durationSeconds, 60)

        let group = try XCTUnwrap(current.entries[0].supersetGroupID)
        XCTAssertEqual(current.entries[1].supersetGroupID, group)
        XCTAssertNotEqual(group, source.entries[0].supersetGroupID)
        XCTAssertNil(current.entries[2].supersetGroupID)

        // History is untouched.
        XCTAssertEqual(store.completedWorkouts.first?.entries, source.entries)
    }

    func testAWorkoutInProgressIsNeverReplaced() async throws {
        let store = try await makeLoadedStore()
        store.addExerciseToCurrent(TestFixtures.benchPress)
        let before = try XCTUnwrap(store.currentWorkout)

        XCTAssertFalse(store.startRepeatedWorkout(lastTime, isAvailable: inLibrary))
        XCTAssertEqual(store.currentWorkout, before)
    }

    func testAnEmptyCurrentWorkoutIsReplacedAsAPlannedStartWould() async throws {
        let store = try await makeLoadedStore()
        store.currentWorkout = CurrentWorkout(entries: [])

        XCTAssertTrue(store.startRepeatedWorkout(lastTime, isAvailable: inLibrary))
        XCTAssertEqual(store.currentWorkout?.entries.count, 3)
    }

    func testNothingStartsWhenEveryExerciseIsGone() async throws {
        let store = try await makeLoadedStore()

        XCTAssertFalse(store.startRepeatedWorkout(lastTime, isAvailable: { _ in false }))
        XCTAssertNil(store.currentWorkout)
    }

    func testTheStoreLooksExercisesUpInItsRepository() async throws {
        // An empty repository: nothing is in the library, so nothing starts and nothing crashes.
        let store = try await makeLoadedStore()

        XCTAssertFalse(store.startRepeatedWorkout(lastTime))
        XCTAssertNil(store.currentWorkout)
    }
}
