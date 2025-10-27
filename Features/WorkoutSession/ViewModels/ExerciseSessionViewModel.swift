//
//  ExerciseSessionViewModel.swift
//  WRKT
//
//  ViewModel for ExerciseSessionView - handles business logic and state
//

import SwiftUI
import Combine

@MainActor
class ExerciseSessionViewModel: ObservableObject {

    // MARK: - Dependencies (Injected for testability)

    private var workoutStore: WorkoutStoreV2
    private let exerciseRepo: ExerciseRepository
    private let onboardingManager: OnboardingManager

    // MARK: - Published State (UI binds to these)

    @Published var currentEntryID: UUID?
    @Published var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    @Published var activeSetIndex: Int = 0
    @Published var didPreloadExisting = false
    @Published var didPrefillFromHistory = false

    // Alert states
    @Published var showEmptyAlert = false
    @Published var showUnsavedSetsAlert = false
    @Published var showInfo = false
    @Published var showDemo = false

    // Tutorial states
    @Published var showTutorial = false
    @Published var currentTutorialStep = 0
    @Published var setsSectionFrame: CGRect = .zero
    @Published var setTypeFrame: CGRect = .zero
    @Published var carouselsFrame: CGRect = .zero
    @Published var presetsFrame: CGRect = .zero
    @Published var addSetButtonFrame: CGRect = .zero
    @Published var infoButtonFrame: CGRect = .zero
    @Published var saveButtonFrame: CGRect = .zero
    @Published var framesReady = false

    // MARK: - Input Properties

    let exercise: Exercise
    let initialEntryID: UUID?
    let returnToHomeOnSave: Bool

    // MARK: - Computed Properties

    var totalReps: Int {
        sets.reduce(0) { $0 + max(0, $1.reps) }
    }

    var workingSets: Int {
        sets.filter { $0.reps > 0 }.count
    }

    var saveButtonTitle: String {
        if currentEntryID != nil {
            return "Update Exercise"
        } else {
            return "Save Exercise"
        }
    }

    // MARK: - Initialization

    init(
        exercise: Exercise,
        initialEntryID: UUID? = nil,
        returnToHomeOnSave: Bool = false,
        workoutStore: WorkoutStoreV2,
        exerciseRepo: ExerciseRepository = .shared,
        onboardingManager: OnboardingManager = .shared
    ) {
        self.exercise = exercise
        self.initialEntryID = initialEntryID
        self.returnToHomeOnSave = returnToHomeOnSave
        self.workoutStore = workoutStore
        self.exerciseRepo = exerciseRepo
        self.onboardingManager = onboardingManager
    }

    // MARK: - Lifecycle Methods

    func onAppear() {
        loadExistingEntry()
        prefillFromHistory()
        checkIfShouldShowTutorial()
    }

    func onScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            // Handle app becoming active
        }
    }

    // MARK: - Business Logic

    func loadExistingEntry() {
        guard !didPreloadExisting else { return }
        didPreloadExisting = true

        if let entryID = initialEntryID,
           let entry = workoutStore.currentWorkout?.entries.first(where: { $0.id == entryID }) {
            currentEntryID = entryID
            sets = entry.sets
            activeSetIndex = entry.activeSetIndex
        }
    }

    func prefillFromHistory() {
        guard !didPrefillFromHistory, currentEntryID == nil else { return }
        didPrefillFromHistory = true

        // Find most recent completed workout with this exercise
        if let lastWorkout = workoutStore.completedWorkouts.first(where: {
            $0.entries.contains(where: { $0.exerciseID == exercise.id })
        }),
           let lastEntry = lastWorkout.entries.first(where: { $0.exerciseID == exercise.id }) {
            sets = lastEntry.sets.map { set in
                SetInput(
                    reps: set.reps,
                    weight: set.weight,
                    tag: set.tag,
                    autoWeight: true,
                    didSeedFromMemory: true
                )
            }
        }
    }

    func checkIfShouldShowTutorial() {
        if !onboardingManager.hasSeenExerciseSession {
            showTutorial = true
        }
    }

    func handleSave(dismiss: DismissAction) {
        // Validate sets
        let validSets = sets.filter { $0.reps > 0 && $0.weight >= 0 }

        guard !validSets.isEmpty else {
            showEmptyAlert = true
            return
        }

        // Update or create entry
        if let entryID = currentEntryID {
            // Update existing entry
            workoutStore.updateEntrySetsAndActiveIndex(
                entryID: entryID,
                sets: validSets,
                activeSetIndex: activeSetIndex
            )
        } else {
            // Add new entry
            let entryID = workoutStore.addExerciseToCurrent(exercise)
            workoutStore.updateEntrySets(entryID: entryID, sets: validSets)
        }

        // Mark tutorial as complete
        if showTutorial {
            onboardingManager.complete(.exerciseSession)
        }

        dismiss()
    }

    func addSet() {
        let lastSet = sets.last ?? SetInput(reps: 10, weight: 0)
        let newSet = SetInput(
            reps: lastSet.reps,
            weight: lastSet.weight,
            tag: .working,
            autoWeight: true
        )
        sets.append(newSet)
    }

    func deleteSet(at index: Int) {
        guard sets.count > 1 else { return }
        sets.remove(at: index)

        if activeSetIndex >= sets.count {
            activeSetIndex = max(0, sets.count - 1)
        }
    }

    func updateSet(at index: Int, _ updatedSet: SetInput) {
        guard sets.indices.contains(index) else { return }
        sets[index] = updatedSet
    }

    func checkFramesReady() {
        framesReady = setsSectionFrame != .zero &&
                     setTypeFrame != .zero &&
                     carouselsFrame != .zero &&
                     saveButtonFrame != .zero
    }

    func advanceTutorial() {
        if currentTutorialStep < 5 {
            currentTutorialStep += 1
        } else {
            showTutorial = false
            onboardingManager.complete(.exerciseSession)
        }
    }

    func skipTutorial() {
        showTutorial = false
        onboardingManager.complete(.exerciseSession)
    }
}
