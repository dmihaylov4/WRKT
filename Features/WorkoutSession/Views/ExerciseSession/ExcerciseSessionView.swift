//
//  ExerciseSessionView.swift
//  WRKT
//
//  Main exercise session view - refactored into modular components
//

import SwiftUI
import Foundation
import SVGView
// Use the theme from ExerciseSessionModels
private typealias Theme = ExerciseSessionTheme

// MARK: - Exercise Session View

struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    let exercise: Exercise
    let initialEntryID: UUID?
    var returnToHomeOnSave: Bool = false

    // ✅ ViewModel (will be initialized in custom init)
    @StateObject private var viewModel: ExerciseSessionViewModel

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Tutorial state (only non-ViewModel state remains)
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var yOffset: CGFloat = 0
    @State private var showWorkoutCreatedBanner = false
    @State private var workoutBannerMessage = ""

    private let debugFrames = true
    private let contentCoordinateSpace = "ExerciseSessionContent"

    // MARK: - Initialization

    /// Custom initializer to support ViewModel while maintaining backward compatibility
    /// with all existing call sites (8 locations in the codebase)
    init(exercise: Exercise, initialEntryID: UUID? = nil, returnToHomeOnSave: Bool = false) {
        self.exercise = exercise
        self.initialEntryID = initialEntryID
        self.returnToHomeOnSave = returnToHomeOnSave

        // Initialize ViewModel without a WorkoutStoreV2 to avoid creating new instances
        // The actual store from @EnvironmentObject will be passed in onAppear
        _viewModel = StateObject(wrappedValue: ExerciseSessionViewModel(
            exercise: exercise,
            initialEntryID: initialEntryID,
            returnToHomeOnSave: returnToHomeOnSave,
            workoutStore: nil  // Don't create new instance - will be set from environment in onAppear
        ))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                mainContentStack(geometry: geometry)

                // Tutorial overlay
                if viewModel.showTutorial {
                    SpotlightOverlay(
                        currentStep: tutorialSteps[viewModel.currentTutorialStep],
                        currentIndex: viewModel.currentTutorialStep,
                        totalSteps: tutorialSteps.count,
                        onNext: viewModel.advanceTutorial,
                        onSkip: viewModel.skipTutorial
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                }

                // Workout created/added banner
                if showWorkoutCreatedBanner {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body.weight(.semibold))
                            Text(workoutBannerMessage)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.accent)
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        )
                        .padding(.top, geometry.safeAreaInsets.top + 16)
                        .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                    .zIndex(999)
                }
            }
        }
    }

    // MARK: - Main Content Stack

    @ViewBuilder
    private func mainContentStack(geometry: GeometryProxy) -> some View {
        baseContentView
            .modifier(NavigationAndAlertsModifier(
                viewModel: viewModel,
                dismiss: dismiss
            ))
            .modifier(LifecycleModifier(
                geometry: geometry,
                initialEntryID: initialEntryID,
                scenePhase: scenePhase,
                onAppear: { handleOnAppear(geometry: geometry) },
                onEntryIDChange: handleEntryIDChange,
                onScenePhaseChange: handleScenePhaseChange,
                onTimerStateChange: handleTimerStateChange
            ))
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeneratePendingSetBeforeTimer"))) { notification in
                // WorkoutStoreV2 handles the actual set generation/logging
                // ExerciseSessionView just needs to reload the sets to show the update
                if let exerciseID = notification.userInfo?["exerciseID"] as? String,
                   exerciseID == exercise.id {
                    // Small delay to let WorkoutStoreV2 finish updating
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        reloadSetsFromStore()
                    }
                }
            }
    }

    // MARK: - Base Content View

    private var baseContentView: some View {
        VStack(spacing: 0) {
            modernHeader
            contentList
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
                .simultaneousGesture(DragGesture().onChanged { _ in hideKeyboard() })
        }
        .coordinateSpace(name: contentCoordinateSpace)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButtonSection
        }
    }

    // MARK: - Lifecycle Handlers

    private func handleOnAppear(geometry: GeometryProxy) {
        // Connect real store from environment to ViewModel
        viewModel.workoutStore = store

        // Initialize current entry ID - check both initialEntryID and existing entry in workout
        if initialEntryID != nil {
            viewModel.currentEntryID = initialEntryID
        } else if let existingEntry = store.existingEntry(for: exercise.id) {
            // Exercise was added to workout while view was closed (e.g., from widget)
            viewModel.currentEntryID = existingEntry.id
            AppLogger.debug("Found existing entry for \(exercise.name) - loading \(existingEntry.sets.count) sets", category: AppLogger.workout)
        }

        preloadExistingIfNeeded()

        // If no existing entry, try to prefill from workout history
        if viewModel.currentEntryID == nil && !viewModel.didPrefillFromHistory {
            prefillFromWorkoutHistory()
        }

        autoSelectFirstIncompleteSet()

        // Check if timer completed while view was dismissed and generate set if needed
        checkForCompletedTimerAndGenerateSet()

        DispatchQueue.main.async {
            yOffset = geometry.safeAreaInsets.top
        }

        // Show tutorial if needed (simplified - no frame waiting)
        if !onboardingManager.hasSeenExerciseSession && !viewModel.showTutorial {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.viewModel.showTutorial = true
            }
        }
    }

    private func handleEntryIDChange(_ newID: UUID?) {
        viewModel.currentEntryID = newID
        preloadExistingIfNeeded(force: true)
        autoSelectFirstIncompleteSet()
    }

    private func handleFramesReadyChange(_ ready: Bool) {
        // No longer needed - tutorial doesn't require frame validation
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        // Check for completed timer when app becomes active (e.g., unlocking phone)
        if newPhase == .active {
            checkForCompletedTimerAndGenerateSet()
        }
    }

    // MARK: - Save Button Section

    private var saveButtonSection: some View {
        VStack(spacing: 10) {
            PrimaryCTA(title: viewModel.saveButtonTitle) {
                viewModel.handleSave(dismiss: dismiss)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.bg)
        .overlay(Divider().background(Theme.border), alignment: .top)
    }

    // MARK: - Compact Header (Focus on Sets)

    private var modernHeader: some View {
        VStack(spacing: 0) {
            // Compact header content
            HStack(spacing: 12) {
                // Exercise name and progress (compact)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    // Inline stats
                    HStack(spacing: 8) {
                        // Current set progress
                        Text("Set \(viewModel.activeSetIndex + 1)/\(viewModel.sets.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondary)

                        // PR badge (compact, inline)
                        if let e1rmKg = store.bestE1RM(exercise: exercise) {
                            let e1rmDisplay = unit == .kg ? e1rmKg : e1rmKg * 2.20462
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                Text("PR \(String(format: "%.0f", e1rmDisplay))\(unit.rawValue)")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Info button - prominent and attention-grabbing
                Button {
                    viewModel.showInfo.toggle()
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Theme.accent.opacity(0.15))
                        )
                }
                .accessibilityLabel("Exercise info")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .overlay(Divider().background(Theme.border.opacity(0.5)), alignment: .bottom)
        .sheet(isPresented: $viewModel.showInfo) {
            exerciseInfoSheet
        }
    }

    private var exerciseInfoSheet: some View {
        NavigationStack {
            ScrollView {
                if let media = repo.media(for: exercise),
                   let s = media.youtube {
                    YouTubePlayerView(url: s)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                    if let videoURL = repo.media(for: exercise)?.youtube {
                        Link("Watch on YouTube", destination: videoURL)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                VStack(spacing: 16) {
                    OverviewCard(meta: guideMeta)
                    RestTimerSettingsCard(exercise: exercise)
                    ExerciseMusclesSection(exercise: exercise, focus: .full)
                }
                .padding(16)
                .background(Theme.bg.ignoresSafeArea())
            }
            .navigationTitle("Exercise Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.showInfo = false
                    }
                }
            }
            .background(Theme.bg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        List {
            SetsSection(
                sets: $viewModel.sets,
                activeSetIndex: $viewModel.activeSetIndex,
                unit: unit,
                exercise: exercise,
                onDelete: { idx in
                    viewModel.deleteSet(at: idx)
                },
                onDuplicate: { idx in duplicateSet(at: idx) },
                onLogSet: { idx in logSet(at: idx) },
                onAdd: {
                    viewModel.addSet()
                    // Select the newly added set
                    viewModel.activeSetIndex = viewModel.sets.count - 1
                },
                onTimerStart: {
                    ensureExerciseInWorkout()
                }
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Sets Section

    private struct SetsSection: View {
        @Binding var sets: [SetInput]
        @Binding var activeSetIndex: Int
        @EnvironmentObject private var store: WorkoutStoreV2

        let unit: WeightUnit
        let exercise: Exercise
        let onDelete: (Int) -> Void
        let onDuplicate: (Int) -> Void
        let onLogSet: (Int) -> Void
        let onAdd: () -> Void
        let onTimerStart: () -> Void

        var body: some View {
            Section {
                // Minimal section header - just a subtle divider


                ForEach(Array(sets.indices), id: \.self) { i in
                    let isActive = (i == activeSetIndex)
                    let isCompleted = sets[i].isCompleted
                    let isGhost = sets[i].isGhost && !isCompleted

                    // Determine if this set has the active timer
                    let hasActiveTimer: Bool = {
                        let manager = RestTimerManager.shared

                        // Must have a timer running for this exercise
                        guard manager.isTimerFor(exerciseID: exercise.id) && manager.isRunning else { return false }

                        // If timer was manually started from widget (not from logging a set), don't show badge
                        // This handles the case where user skips timer and presses "Log Next Set" from widget
                        guard !manager.isManuallyStartedTimer else { return false }

                        // Timer was started from logging a set - show on last completed set
                        guard isCompleted else { return false }
                        guard let lastCompletedIndex = sets.lastIndex(where: { $0.isCompleted }),
                              lastCompletedIndex == i else { return false }

                        return true
                    }()

                    AdaptiveSetRow(
                        index: i + 1,
                        set: $sets[i],
                        unit: unit,
                        exercise: exercise,
                        isActive: isActive,
                        isGhost: isGhost,
                        hasActiveTimer: hasActiveTimer,
                        onDuplicate: { onDuplicate(i) },
                        onActivate: {
                            activeSetIndex = i
                        },
                        onLogSet: {
                            onLogSet(i)
                        },
                        onTimerStart: onTimerStart
                    )
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if isCompleted {
                            Button {
                                sets[i].isCompleted = false
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.black)
                                    Text("Incomplete")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .tint(DS.Palette.marone)
                        } else {
                            Button {
                                sets[i].isCompleted = true
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.black)
                                    Text("Complete")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .tint(DS.Palette.marone)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            onDelete(i)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                    .font(.title2)
                                    .foregroundStyle(DS.Palette.marone)
                                Text("Delete")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(DS.Palette.marone)
                            }
                        }
                        .tint(.black)
                    }
                }

                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        PresetButton(title: "Use Last", icon: "clock.arrow.circlepath") {
                            useLast()
                        }

                        PresetButton(title: "5×5", icon: "number.circle") {
                            applyFiveByFive()
                        }

                        if store.bestE1RM(exercise: exercise) != nil {
                            PresetButton(title: "Try 1RM", icon: "star.circle") {
                                tryOneRM()
                            }
                        }
                    }

                    Button(action: onAdd) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Set")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(.init(top: 12, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bg)
            }
        }

        private func useLast() {
            Haptics.light()
            if let lastWorkingSet = store.lastWorkingSet(exercise: exercise) {
                sets.append(SetInput(
                    reps: lastWorkingSet.reps,
                    weight: lastWorkingSet.weightKg,
                    tag: .working,
                    autoWeight: true,
                    didSeedFromMemory: true
                ))
                // Make the newly added set active
                activeSetIndex = sets.count - 1
            }
        }

        private func applyFiveByFive() {
            Haptics.light()
            sets = (1...5).map { _ in
                SetInput(reps: 5, weight: 0, tag: .working, autoWeight: true)
            }
            // Make the first set active
            activeSetIndex = 0
        }

        private func tryOneRM() {
            Haptics.light()
            guard let e1rm = store.bestE1RM(exercise: exercise) else { return }
            sets.append(SetInput(
                reps: 1,
                weight: e1rm,
                tag: .working,
                autoWeight: false,
                didSeedFromMemory: false
            ))
            // Make the newly added set active
            activeSetIndex = sets.count - 1
        }
    }

    // MARK: - Helper Functions

    private func cleaned(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty, t.lowercased() != "nan" else { return nil }
        return t
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        for v in values { if let t = cleaned(v) { return t } }
        return ""
    }

    private var guideMeta: ExerciseGuideMeta {
        let difficulty = firstNonEmpty(exercise.level)
        let equipment  = firstNonEmpty(exercise.equipment, "Bodyweight")
        let classif    = firstNonEmpty(exercise.category)
        let mechanics  = firstNonEmpty(exercise.mechanic)
        let forceType  = firstNonEmpty(exercise.force)
        let grip       = firstNonEmpty(exercise.grip)

        let pattern = "", plane = "", posture = "", laterality = ""

        var cues: [String] = []
        if mechanics.lowercased() == "isolation" { cues.append("Control the eccentric; avoid swinging.") }
        if mechanics.lowercased() == "compound"  { cues.append("Brace your core; keep ribs down.") }
        if forceType.lowercased() == "pull"      { cues.append("Initiate the pull without shrugging your shoulders.") }
        if !equipment.isEmpty && equipment.lowercased().contains("cable") {
            cues.append("Use a steady tempo (e.g., 3-1-1) to keep tension on the target muscle.")
        }
        if !grip.isEmpty { cues.append(gripCue(for: grip)) }

        return ExerciseGuideMeta(
            difficulty: difficulty,
            equipment: equipment,
            classification: classif,
            mechanics: mechanics,
            forceType: forceType,
            pattern: pattern,
            plane: plane,
            posture: posture,
            grip: grip,
            laterality: laterality,
            cues: cues
        )
    }

    private func gripCue(for grip: String) -> String {
        let g = grip.lowercased()
        switch true {
        case g.contains("pronated"):
            return "Pronated grip: palms away—keep wrists straight and elbows ~45°."
        case g.contains("supinated"):
            return "Supinated grip: palms toward you—tuck elbows; avoid wrist extension."
        case g.contains("neutral"):
            return "Neutral grip: palms facing—stack wrists under forearms and don't flare."
        case g.contains("mixed"):
            return "Mixed grip: rotate sides between sets and keep both wrists neutral."
        case g.contains("hook"):
            return "Hook grip: thumb under fingers—keep wrist straight to reduce strain."
        default:
            return "Use a \(grip) grip and keep wrists neutral—not bent back."
        }
    }

    private func duplicateSet(at index: Int) {
        guard viewModel.sets.indices.contains(index) else { return }
        let s = viewModel.sets[index]
        viewModel.sets.append(s)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteSet(at index: Int) {
        guard viewModel.sets.indices.contains(index) else { return }

        let deletedSet = viewModel.sets[index]

        // Check if this was the most recently completed set
        let lastCompletedIndex = viewModel.sets.lastIndex(where: { $0.isCompleted })
        let wasLastCompletedSet = deletedSet.isCompleted && lastCompletedIndex == index

        // Remove the set
        viewModel.sets.remove(at: index)

        // If we deleted the most recently completed set, stop the timer
        if wasLastCompletedSet {
            let manager = RestTimerManager.shared
            if manager.isTimerFor(exerciseID: exercise.id) {
                manager.stopTimer()
            }
        }

        // Adjust active index if needed
        if viewModel.activeSetIndex >= viewModel.sets.count {
            viewModel.activeSetIndex = max(0, viewModel.sets.count - 1)
        }
    }

    private func generateNextSet() {
        if let lastSet = viewModel.sets.last {
            let newSet = SetInput(
                reps: lastSet.reps,
                weight: lastSet.weight,
                tag: lastSet.tag,
                autoWeight: false,
                didSeedFromMemory: false,
                isCompleted: false,
                isGhost: false
            )
            viewModel.sets.append(newSet)
        } else {
            viewModel.sets.append(SetInput(reps: 10, weight: 0, tag: .working, autoWeight: true))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func preloadExistingIfNeeded(force: Bool = false) {
        guard let id = viewModel.currentEntryID else { return }
        guard force || !viewModel.didPreloadExisting else { return }
        if let entry = store.currentWorkout?.entries.first(where: { $0.id == id }),
           !entry.sets.isEmpty {
            viewModel.sets = entry.sets
            viewModel.activeSetIndex = entry.activeSetIndex
        }
        viewModel.didPreloadExisting = true
    }

    private func prefillFromWorkoutHistory() {
        guard !viewModel.didPrefillFromHistory else { return }

        // Check if user has completed this exercise before
        if let lastSet = store.lastWorkingSet(exercise: exercise) {
            // User has history - prefill with their last performance
            viewModel.sets = [SetInput(
                reps: lastSet.reps,
                weight: lastSet.weightKg,
                tag: .working,
                autoWeight: false,
                didSeedFromMemory: true
            )]
           
        } else {
            // No history - use weight suggestion helper
            let suggestedWeight = WeightSuggestionHelper.suggestInitialWeight(for: exercise)
            let suggestedReps = WeightSuggestionHelper.suggestInitialReps(for: exercise)
            viewModel.sets = [SetInput(
                reps: suggestedReps,
                weight: suggestedWeight,
                tag: .working,
                autoWeight: true,
                didSeedFromMemory: false
            )]
           
        }

        viewModel.didPrefillFromHistory = true
    }

    private func autoSelectFirstIncompleteSet() {
        // Find the first set that is not completed
        if let firstIncomplete = viewModel.sets.firstIndex(where: { !$0.isCompleted && !$0.isGhost }) {
            viewModel.activeSetIndex = firstIncomplete
        } else {
            // If all sets are completed, select the last one
            viewModel.activeSetIndex = max(0, viewModel.sets.count - 1)
        }
    }

    // MARK: - Set Logging Logic (Auto-Save)

    private func logSet(at index: Int) {
        guard index < viewModel.sets.count else { return }

        // 1. Mark set as completed
        viewModel.sets[index].isCompleted = true

        // 2. Auto-save to workout (best practice: immediate save)
        if let entryID = viewModel.currentEntryID {
            // Existing entry - update sets
            store.updateEntrySetsAndActiveIndex(entryID: entryID, sets: viewModel.sets, activeSetIndex: viewModel.activeSetIndex)
        } else {
            // First logged set - automatically add exercise to workout
            let entryID = store.addExerciseToCurrent(exercise)
            store.updateEntrySets(entryID: entryID, sets: cleanSets())
            viewModel.currentEntryID = entryID  // Track this entry for future updates
        }

        // 3. Advance to next set if available (but don't generate a new one yet)
        if index < viewModel.sets.count - 1 {
            // Move to next existing set
            viewModel.activeSetIndex = index + 1
        }
        // Note: New set will be generated when rest timer completes

        // 4. Start rest timer
        startRestTimerIfEnabled()

        // 5. Haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Timer Completion Handler

    private func handleTimerStateChange(newState: RestTimerState) {
        // Check if timer just completed for this exercise
        if case .completed(let exerciseID, _) = newState,
           exerciseID == exercise.id {
            // Timer completed for this exercise - generate new set
            generateNewSetAfterRest()

            // Clear pending flag since we just generated the set
            RestTimerManager.shared.clearPendingSetGeneration(for: exercise.id)
        }
    }

    private func checkForCompletedTimerAndGenerateSet() {
        let manager = RestTimerManager.shared

        // Check if timer is in completed state for this exercise
        if case .completed(let exerciseID, _) = manager.state,
           exerciseID == exercise.id {
            // Timer completed for this exercise - generate set if needed
            generateNewSetAfterRest()

            // Dismiss the completed state so it doesn't re-trigger
            manager.dismissCompleted()
            return
        }

        // Also check if there's a pending set generation flag for this exercise
        // This handles cases where timer completed while view was dismissed/backgrounded
        if manager.hasPendingSetGeneration(for: exercise.id) {
            // Generate the pending set
            generateNewSetAfterRest()

            // Clear the pending flag
            manager.clearPendingSetGeneration(for: exercise.id)
        }
    }

    private func generateNewSetAfterRest() {
        // Find the last completed set to use as a template
        guard let lastCompletedSet = viewModel.sets.last(where: { $0.isCompleted }) else { return }

        // Check if we already have an incomplete set at the end - if so, just activate it
        if let lastSet = viewModel.sets.last, !lastSet.isCompleted {
            viewModel.activeSetIndex = viewModel.sets.count - 1
            return
        }

        // Generate a new set with the same values as the last completed set
        // Mark it as auto-generated placeholder so it can be silently deleted if untouched
        let newSet = SetInput(
            reps: lastCompletedSet.reps,
            weight: lastCompletedSet.weight,
            tag: lastCompletedSet.tag,
            autoWeight: false,
            didSeedFromMemory: false,
            isCompleted: false,
            isGhost: false,
            isAutoGeneratedPlaceholder: true  // Mark as auto-generated
        )

        viewModel.sets.append(newSet)
        viewModel.activeSetIndex = viewModel.sets.count - 1

        // Auto-save the new set to the workout
        if let entryID = viewModel.currentEntryID {
            store.updateEntrySetsAndActiveIndex(entryID: entryID, sets: viewModel.sets, activeSetIndex: viewModel.activeSetIndex)
        }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Reload sets from workout store (called after WorkoutStoreV2 updates the workout from widget)
    private func reloadSetsFromStore() {
        // Find the entry for this exercise in the workout
        guard let entry = store.existingEntry(for: exercise.id) else {
            AppLogger.debug("No entry found for \(exercise.name) when reloading sets", category: AppLogger.workout)
            return
        }

        // Update the view model with the latest sets from the store
        viewModel.sets = entry.sets
        viewModel.activeSetIndex = entry.activeSetIndex
        viewModel.currentEntryID = entry.id

        AppLogger.debug("Reloaded sets from store for \(exercise.name) - \(entry.sets.count) sets", category: AppLogger.workout)

        // Auto-select the newly added incomplete set (if any)
        autoSelectFirstIncompleteSet()
    }

    private func cleanSets() -> [SetInput] {
        viewModel.sets.map {
            var s = $0
            s.reps = max(0, s.reps)
            s.weight = max(0, s.weight)
            return s
        }
    }

    // MARK: - Tutorial Logic
    // Tutorial logic is now in ViewModel

    private var tutorialSteps: [TutorialStep] {
        return [
            TutorialStep(
                title: "Track Your Exercise",
                message: "Use +/- buttons to adjust reps and weight. Tap the colored badge to change set type. Swipe right on a set to log it, left to delete. Tap the info button for exercise details and rest timer settings. When done, tap the button at the bottom to save.",
                spotlightFrame: nil,  // No spotlight, just overlay
                tooltipPosition: .center,
                highlightCornerRadius: 16
            )
        ]
    }

    // MARK: - Workout Management

    /// Ensures the exercise is added to the current workout (or creates a new workout if needed)
    /// Called when user starts a timer on a timed exercise
    private func ensureExerciseInWorkout() {
        var createdNewWorkout = false

        // If there's no current workout, create one
        if store.currentWorkout == nil {
            store.startWorkoutIfNeeded()
            createdNewWorkout = true
            AppLogger.info("Auto-created workout for timed exercise: \(exercise.name)", category: AppLogger.workout)
        }

        // Check if this exercise already exists in the current workout
        if let existingEntry = store.existingEntry(for: exercise.id) {
            // Exercise already in workout - just make sure we're using it
            viewModel.currentEntryID = existingEntry.id
            AppLogger.debug("Exercise already in workout, using existing entry", category: AppLogger.workout)
        } else {
            // Exercise not in workout yet - create entry now so it shows in LiveWorkoutGrabTab
            let newEntryID = store.addExerciseToCurrent(exercise)
            viewModel.currentEntryID = newEntryID

            // Initialize the entry with current sets (even if empty/incomplete)
            store.updateEntrySets(entryID: newEntryID, sets: viewModel.sets)

            AppLogger.info("Added exercise to workout: \(exercise.name)", category: AppLogger.workout)
        }

        // Show banner feedback
        workoutBannerMessage = createdNewWorkout ? "Workout started with \(exercise.name)" : "Added to current workout"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showWorkoutCreatedBanner = true
        }

        // Auto-hide banner after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showWorkoutCreatedBanner = false
            }
        }

        // Haptic feedback to confirm action
        Haptics.soft()
    }

    // MARK: - Save Logic
    // All save logic is now in ViewModel

    private func startRestTimerIfEnabled() {
        let prefs = RestTimerPreferences.shared
        guard prefs.isEnabled else { return }

        let manager = RestTimerManager.shared

        if manager.isTimerFor(exerciseID: exercise.id) && manager.isRunning {
            let adjustedDuration = manager.remainingSeconds
            manager.startTimer(duration: adjustedDuration, exerciseID: exercise.id, exerciseName: exercise.name)
        } else {
            let duration = prefs.restDuration(for: exercise)
            manager.startTimer(duration: duration, exerciseID: exercise.id, exerciseName: exercise.name)
        }
    }
}

// MARK: - View Modifiers

/// Handles navigation bar, background, toolbar, and alerts
private struct NavigationAndAlertsModifier: ViewModifier {
    @ObservedObject var viewModel: ExerciseSessionViewModel
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .navigationBarHidden(true)
            .background(ExerciseSessionTheme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(ExerciseSessionTheme.accent)
                }
            }
            .alert("Empty workout", isPresented: $viewModel.showEmptyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Add at least one set with reps to save.")
            }
            .alert("Last Set", isPresented: $viewModel.showLastSetDeletionAlert) {
                Button("Delete Exercise", role: .destructive) {
                    viewModel.deleteExerciseFromWorkout(dismiss: dismiss)
                }
                Button("Edit Set", role: .cancel) {
                    viewModel.makeLastSetEditable()
                }
            } message: {
                Text("This is the last set from this exercise. Do you wish to delete the whole exercise or edit the set instead?")
            }
    }
}

/// Handles all lifecycle events (onAppear, onChange, onReceive)
private struct LifecycleModifier: ViewModifier {
    let geometry: GeometryProxy
    let initialEntryID: UUID?
    let scenePhase: ScenePhase
    let onAppear: () -> Void
    let onEntryIDChange: (UUID?) -> Void
    let onScenePhaseChange: (ScenePhase) -> Void
    let onTimerStateChange: (RestTimerState) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                onAppear()
            }
            .onChange(of: initialEntryID) { _, newID in
                onEntryIDChange(newID)
            }
            .onReceive(RestTimerManager.shared.$state) { newState in
                onTimerStateChange(newState)
            }
            .onChange(of: scenePhase) { _, newPhase in
                onScenePhaseChange(newPhase)
            }
    }
}

// Sync modifiers removed - ViewModel is now the single source of truth
