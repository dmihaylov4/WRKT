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

    // Progressive overload
    @Published var appliedProgression: ProgressionSuggestion? = nil

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
        setupWatchNotificationListener()
    }

    private func setupWatchNotificationListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WorkoutUpdatedFromWatch"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            // Reload the entry when watch makes changes
            if let entryIDString = notification.userInfo?["entryID"] as? String,
               let entryID = UUID(uuidString: entryIDString),
               entryID == self.currentEntryID {
                AppLogger.info("♻️ Reloading exercise session from watch update", category: AppLogger.app)
                self.reloadFromStore()
            }
        }
    }

    private func reloadFromStore() {
        guard let workoutStore = workoutStore,
              let workout = workoutStore.currentWorkout,
              let entryID = currentEntryID,
              let entry = workout.entries.first(where: { $0.id == entryID }) else {
            return
        }

        // Update local state with latest from store
        self.sets = entry.sets
        // activeSetIndex is Int, not Int?, so just assign it directly
        self.activeSetIndex = entry.activeSetIndex

        AppLogger.success("✅ Reloaded sets from store", category: AppLogger.app)
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

        AppLogger.debug("[Prefill] Starting prefill for \(exercise.name)", category: AppLogger.workout)

        // Find most recent completed workout with this exercise
        if let lastWorkout = workoutStore.completedWorkouts.first(where: {
            $0.entries.contains(where: { $0.exerciseID == exercise.id })
        }),
           let lastEntry = lastWorkout.entries.first(where: { $0.exerciseID == exercise.id }) {

            AppLogger.info("[Prefill] Found last workout with \(lastEntry.sets.count) sets", category: AppLogger.workout)

            // Check if we should apply progressive overload suggestion
            var suggestedWeight: Double? = nil
            var suggestedReps: Int? = nil

            // Use the average of the last workout's working sets as baseline
            let workingSets = lastEntry.sets.filter { $0.tag == .working }
            AppLogger.info("[Prefill] Found \(workingSets.count) working sets in last workout", category: AppLogger.workout)

            if !workingSets.isEmpty {
                let avgWeight = workingSets.map { $0.weight }.reduce(0, +) / Double(workingSets.count)
                let avgReps = (Double(workingSets.map { $0.reps }.reduce(0, +)) / Double(workingSets.count)).safeInt

                AppLogger.info("[Prefill] Calling progression helper with avg: \(avgWeight)kg x \(avgReps) reps", category: AppLogger.workout)

                if let progression = WeightSuggestionHelper.suggestProgression(
                    for: exercise,
                    lastSetWeight: avgWeight,
                    lastSetReps: avgReps,
                    workoutStore: workoutStore
                ) {
                    suggestedWeight = progression.suggestedWeight
                    suggestedReps = progression.suggestedReps

                    // Store the progression for UI display
                    appliedProgression = progression

                    // Log the suggestion
                    AppLogger.info("✅ Progressive overload applied to prefill: \(progression.reason)", category: AppLogger.workout)
                } else {
                    AppLogger.info("[Prefill] No progression suggestion returned", category: AppLogger.workout)
                }
            }

            // Pre-fill only the FIRST set with progression (user adds more with "Add Set" button)
            // Get the first working set as template
            guard let firstWorkingSet = workingSets.first ?? lastEntry.sets.first else {
                AppLogger.warning("No sets available for prefill", category: AppLogger.workout)
                sets = [SetInput(reps: 10, weight: 0, tag: .working, autoWeight: true)]
                return
            }

            // Apply progression if available, otherwise use last workout's values
            let finalReps = suggestedReps ?? firstWorkingSet.reps
            let finalWeight = suggestedWeight ?? firstWorkingSet.weight

            // Set autoWeight = false if we applied progression, otherwise the SetRow will overwrite it
            let appliedProgression = suggestedWeight != nil

            sets = [SetInput(
                reps: finalReps,
                weight: finalWeight,
                tag: .working,
                autoWeight: !appliedProgression,  // Disable auto-weight if we applied progression
                didSeedFromMemory: true
            )]
        } else {
            // No history - create a default first set
            sets = [SetInput(reps: 10, weight: 0, tag: .working, autoWeight: true)]
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

        AppLogger.info("[AddSet] Adding new set - last set was \(lastSet.weight)kg x \(lastSet.reps) reps", category: AppLogger.workout)

        // Try to get progression suggestion based on workout history
        var suggestedWeight = lastSet.weight
        var suggestedReps = lastSet.reps

        if let workoutStore = workoutStore {
            AppLogger.info("[AddSet] Calling progression helper...", category: AppLogger.workout)

            if let progression = WeightSuggestionHelper.suggestProgression(
                for: exercise,
                lastSetWeight: lastSet.weight,
                lastSetReps: lastSet.reps,
                workoutStore: workoutStore
            ) {
                // Use suggested progression
                suggestedWeight = progression.suggestedWeight
                suggestedReps = progression.suggestedReps

                // Log for debugging (can remove in production)
                AppLogger.info("✅ Progressive overload suggestion: \(progression.reason)", category: AppLogger.workout)
            } else {
                AppLogger.info("[AddSet] No progression suggestion returned", category: AppLogger.workout)
            }
        } else {
            AppLogger.debug("[AddSet] No workout store available", category: AppLogger.workout)
        }

        let newSet = SetInput(
            reps: suggestedReps,
            weight: suggestedWeight,
            tag: .working,
            autoWeight: true
        )
        AppLogger.info("[AddSet] Created new set: \(suggestedWeight)kg x \(suggestedReps) reps", category: AppLogger.workout)
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
