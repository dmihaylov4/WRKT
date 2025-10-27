//
//  ExerciseSessionViewModelTests.swift
//  WRKTTests
//
//  Tests for ExerciseSessionViewModel business logic
//

import XCTest
@testable import WRKT

@MainActor
final class ExerciseSessionViewModelTests: WRKTTestCase {

    // Helper to create a test workout store
    private func makeTestStore() -> WorkoutStoreV2 {
        return WorkoutStoreV2(repo: .shared)
    }

    // MARK: - Initialization Tests

    func testInitializationWithDefaults() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(
            exercise: exercise,
            workoutStore: store
        )

        XCTAssertEqual(viewModel.exercise.id, exercise.id)
        XCTAssertNil(viewModel.initialEntryID)
        XCTAssertFalse(viewModel.returnToHomeOnSave)
        XCTAssertEqual(viewModel.sets.count, 1)
        XCTAssertEqual(viewModel.activeSetIndex, 0)
    }

    func testInitializationWithExistingEntry() {
        let exercise = TestFixtures.benchPress
        let entryID = UUID()
        let store = makeTestStore()

        let viewModel = ExerciseSessionViewModel(
            exercise: exercise,
            initialEntryID: entryID,
            returnToHomeOnSave: true,
            workoutStore: store
        )

        XCTAssertEqual(viewModel.initialEntryID, entryID)
        XCTAssertTrue(viewModel.returnToHomeOnSave)
    }

    // MARK: - Computed Properties Tests

    func testTotalReps() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [
            SetInput(reps: 10, weight: 60),
            SetInput(reps: 8, weight: 80),
            SetInput(reps: 6, weight: 90)
        ]

        XCTAssertEqual(viewModel.totalReps, 24)
    }

    func testWorkingSetsCount() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [
            SetInput(reps: 10, weight: 60),
            SetInput(reps: 0, weight: 0),  // Invalid set
            SetInput(reps: 8, weight: 80)
        ]

        XCTAssertEqual(viewModel.workingSets, 2)
    }

    func testSaveButtonTitleForNewEntry() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.currentEntryID = nil

        XCTAssertEqual(viewModel.saveButtonTitle, "Save Exercise")
    }

    func testSaveButtonTitleForExistingEntry() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.currentEntryID = UUID()

        XCTAssertEqual(viewModel.saveButtonTitle, "Update Exercise")
    }

    // MARK: - Add/Delete Set Tests

    func testAddSet() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        let initialCount = viewModel.sets.count
        viewModel.addSet()

        XCTAssertEqual(viewModel.sets.count, initialCount + 1)

        let newSet = viewModel.sets.last!
        XCTAssertTrue(newSet.autoWeight)
        XCTAssertEqual(newSet.tag, .working)
    }

    func testAddSetCopiesLastSetValues() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [SetInput(reps: 8, weight: 100)]
        viewModel.addSet()

        let newSet = viewModel.sets.last!
        XCTAssertEqual(newSet.reps, 8)
        XCTAssertEqual(newSet.weight, 100)
    }

    func testDeleteSet() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [
            SetInput(reps: 10, weight: 60),
            SetInput(reps: 8, weight: 80),
            SetInput(reps: 6, weight: 90)
        ]

        viewModel.deleteSet(at: 1)

        XCTAssertEqual(viewModel.sets.count, 2)
        XCTAssertEqual(viewModel.sets[0].reps, 10)
        XCTAssertEqual(viewModel.sets[1].reps, 6)
    }

    func testDeleteSetDoesNotRemoveLastSet() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [SetInput(reps: 10, weight: 60)]
        viewModel.deleteSet(at: 0)

        XCTAssertEqual(viewModel.sets.count, 1)
    }

    func testDeleteSetAdjustsActiveSetIndex() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [
            SetInput(reps: 10, weight: 60),
            SetInput(reps: 8, weight: 80)
        ]
        viewModel.activeSetIndex = 1

        viewModel.deleteSet(at: 1)

        XCTAssertEqual(viewModel.activeSetIndex, 0)
    }

    // MARK: - Update Set Tests

    func testUpdateSet() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [
            SetInput(reps: 10, weight: 60),
            SetInput(reps: 8, weight: 80)
        ]

        let updatedSet = SetInput(reps: 12, weight: 70)
        viewModel.updateSet(at: 0, updatedSet)

        XCTAssertEqual(viewModel.sets[0].reps, 12)
        XCTAssertEqual(viewModel.sets[0].weight, 70)
    }

    func testUpdateSetIgnoresInvalidIndex() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.sets = [SetInput(reps: 10, weight: 60)]

        let updatedSet = SetInput(reps: 12, weight: 70)
        viewModel.updateSet(at: 5, updatedSet)

        // Should not crash, original set unchanged
        XCTAssertEqual(viewModel.sets[0].reps, 10)
    }

    // MARK: - Tutorial Tests

    func testAdvanceTutorial() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.currentTutorialStep = 0
        viewModel.showTutorial = true

        viewModel.advanceTutorial()

        XCTAssertEqual(viewModel.currentTutorialStep, 1)
        XCTAssertTrue(viewModel.showTutorial)
    }

    func testAdvanceTutorialCompletesAtEnd() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.currentTutorialStep = 5
        viewModel.showTutorial = true

        viewModel.advanceTutorial()

        XCTAssertFalse(viewModel.showTutorial)
    }

    func testSkipTutorial() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.showTutorial = true

        viewModel.skipTutorial()

        XCTAssertFalse(viewModel.showTutorial)
    }

    // MARK: - Frame Tracking Tests

    func testCheckFramesReady() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.setsSectionFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        viewModel.setTypeFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        viewModel.carouselsFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        viewModel.saveButtonFrame = CGRect(x: 0, y: 0, width: 100, height: 100)

        viewModel.checkFramesReady()

        XCTAssertTrue(viewModel.framesReady)
    }

    func testCheckFramesReadyFailsWithZeroFrames() {
        let exercise = TestFixtures.benchPress
        let store = makeTestStore()
        let viewModel = ExerciseSessionViewModel(exercise: exercise, workoutStore: store)

        viewModel.setsSectionFrame = .zero
        viewModel.checkFramesReady()

        XCTAssertFalse(viewModel.framesReady)
    }
}
