//
//  ExerciseSessionViewModel.swift
//  WRKT
//
//  ViewModel for ExerciseSessionView - handles business logic and state
//

import SwiftUI
import Combine
import OSLog

@MainActor
class ExerciseSessionViewModel: ObservableObject {

    // MARK: - Dependencies (Injected for testability)

    internal var workoutStore: WorkoutStoreV2?  // Internal to allow injection from view's onAppear, optional to avoid creating new instances
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
    @Published var showInfo = false
    @Published var showDemo = false
    @Published var showLastSetDeletionAlert = false

    // Tutorial states
    @Published var showTutorial = false
    @Published var currentTutorialStep = 0

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
        // All sets are auto-saved when logged, so this button just closes the view
        return "Done"
    }

    // MARK: - Initialization

    init(
        exercise: Exercise,
        initialEntryID: UUID? = nil,
        returnToHomeOnSave: Bool = false,
        workoutStore: WorkoutStoreV2? = nil,  // Optional to avoid creating new instances in view init
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
        guard let workoutStore = workoutStore else { return }
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
        guard let workoutStore = workoutStore else { return }
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
        // Proceed with cleanup and dismiss
        // Note: Swipe-to-complete functionality now prevents completing sets with unsaved changes
        cleanupAndDismiss(dismiss: dismiss)
    }

    func cleanupAndDismiss(dismiss: DismissAction) {


        // Save all sets (both completed and incomplete) when dismissing
        // This preserves planned sets so users can come back and complete them later
        if let entryID = currentEntryID, let workoutStore = workoutStore {
            AppLogger.debug("Saving all sets: \(sets.count) total, \(sets.filter { $0.isCompleted }.count) completed", category: AppLogger.workout)
            workoutStore.updateEntrySets(entryID: entryID, sets: sets)
        }

        // Mark tutorial as complete
        if showTutorial {
            onboardingManager.complete(.exerciseSession)
        }

       
        dismiss()

        // Handle navigation based on returnToHomeOnSave
        if returnToHomeOnSave {
           
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
            AppBus.postResetHome(reason: .user_intent)
        } else {
            
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
        }
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
        guard sets.indices.contains(index) else { return }

        // If this is the last set, show alert to confirm exercise deletion
        if sets.count == 1 {
            showLastSetDeletionAlert = true
            Haptics.warning()
            return
        }

        sets.remove(at: index)

        if activeSetIndex >= sets.count {
            activeSetIndex = max(0, sets.count - 1)
        }
    }

    /// Handles deletion of the entire exercise from the workout
    func deleteExerciseFromWorkout(dismiss: DismissAction) {
        guard let entryID = currentEntryID, let workoutStore = workoutStore else {
            // No entry ID or workout store means the exercise hasn't been added to the workout yet
            // Just dismiss the view
            dismiss()
            return
        }

        // Check if this is the only exercise in the workout BEFORE removing it
        let wasLastExercise = workoutStore.currentWorkout?.entries.count == 1

        if wasLastExercise {
            // If this is the only exercise, discard the entire workout
            // This preserves the full workout for undo functionality
            workoutStore.discardCurrentWorkout()

            // Dismiss the view first
            dismiss()

            // Navigate back to HomeView after a brief delay
            // This ensures the user can see the undo toast in HomeView where the grab tab will work properly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                AppBus.postResetHome(reason: .user_intent)
            }
        } else {
            // Multiple exercises exist, just remove this one
            workoutStore.removeEntry(entryID: entryID)

            // Just dismiss the view - stay in current location
            dismiss()
        }

        // Haptic feedback
        Haptics.soft()
    }

    /// Marks the last set as uncompleted so the user can edit it
    func makeLastSetEditable() {
        guard sets.count == 1 else { return }
        sets[0].isCompleted = false
        activeSetIndex = 0
        Haptics.light()
    }

    func updateSet(at index: Int, _ updatedSet: SetInput) {
        guard sets.indices.contains(index) else { return }
        sets[index] = updatedSet
    }


    func advanceTutorial() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            // Only 1 step, so always dismiss
            showTutorial = false
            onboardingManager.complete(.exerciseSession)
        }
    }

    func skipTutorial() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showTutorial = false
            onboardingManager.complete(.exerciseSession)
        }
    }
}
