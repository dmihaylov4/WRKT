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

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentEntryID: UUID? = nil
    @State private var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    @State private var activeSetIndex: Int = 0
    @State private var didPreloadExisting = false
    @State private var didPrefillFromHistory = false
    @State private var showEmptyAlert = false
    @State private var showUnsavedSetsAlert = false
    @State private var showInfo = false
    @State private var showDemo = false

    private var totalReps: Int { sets.reduce(0) { $0 + max(0, $1.reps) } }
    private var workingSets: Int { sets.filter { $0.reps > 0 }.count }

    // Tutorial state
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showTutorial = false
    @State private var currentTutorialStep = 0
    @State private var setsSectionFrame: CGRect = .zero
    @State private var setTypeFrame: CGRect = .zero
    @State private var carouselsFrame: CGRect = .zero
    @State private var presetsFrame: CGRect = .zero
    @State private var addSetButtonFrame: CGRect = .zero
    @State private var infoButtonFrame: CGRect = .zero
    @State private var saveButtonFrame: CGRect = .zero
    @State private var framesReady = false
    @State private var yOffset: CGFloat = 0

    private let debugFrames = true
    private let frameUpwardAdjustment: CGFloat = 70  // Move all frames up by this amount

    // MARK: - Body

    var body: some View { 
        GeometryReader { geometry in
            ZStack {
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 10) {
                        PrimaryCTA(title: saveButtonTitle) {
                            handleSave()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(Theme.bg)
                    .overlay(Divider().background(Theme.border), alignment: .top)
                    .captureFrame(in: .global) { frame in
                        saveButtonFrame = frame
                        checkFramesReady()
                    }
                }
                .navigationBarHidden(true)
                .background(Theme.bg.ignoresSafeArea())
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.accent)
                    }
                }
                .alert("Empty workout", isPresented: $showEmptyAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Add at least one set with reps to save.")
                }
                .alert("Unsaved Sets", isPresented: $showUnsavedSetsAlert) {
                    Button("Go Back", role: .cancel) { }
                    Button("Discard", role: .destructive) {
                        cleanupAndDismiss()
                    }
                } message: {
                    let count = countUnloggedModifiedSets()
                    Text("You have \(count) unlogged set\(count > 1 ? "s" : "") with changes that will be discarded.")
                }
                .onAppear {
                    // Initialize current entry ID from the initial value
                    currentEntryID = initialEntryID
                    preloadExistingIfNeeded()

                    // If no existing entry, try to prefill from workout history
                    if initialEntryID == nil && !didPrefillFromHistory {
                        prefillFromWorkoutHistory()
                    }

                    autoSelectFirstIncompleteSet()

                    // Check if timer completed while view was dismissed and generate set if needed
                    checkForCompletedTimerAndGenerateSet()

                    DispatchQueue.main.async {
                        yOffset = geometry.safeAreaInsets.top
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if !framesReady && !onboardingManager.hasSeenExerciseSession && !showTutorial {
                            showTutorial = true
                        }
                    }
                }
                .onChange(of: initialEntryID) { _, newID in
                    currentEntryID = newID
                    preloadExistingIfNeeded(force: true)
                    autoSelectFirstIncompleteSet()
                }
                .onChange(of: framesReady) { _, ready in
                    if ready && !onboardingManager.hasSeenExerciseSession && !showTutorial {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTutorial = true
                        }
                    }
                }
                .onReceive(RestTimerManager.shared.$state) { newState in
                    handleTimerStateChange(newState: newState)
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Check for completed timer when app becomes active (e.g., unlocking phone)
                    if newPhase == .active {
                        checkForCompletedTimerAndGenerateSet()
                    }
                }

                // Tutorial overlay
                if showTutorial {
                    SpotlightOverlay(
                        currentStep: tutorialSteps[currentTutorialStep],
                        currentIndex: currentTutorialStep,
                        totalSteps: tutorialSteps.count,
                        onNext: advanceTutorial,
                        onSkip: skipTutorial
                    )
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
        }
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
                        Text("Set \(activeSetIndex + 1)/\(sets.count)")
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
                    showInfo.toggle()
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
                .captureFrame(in: .global) { frame in
                    infoButtonFrame = frame
                    checkFramesReady()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .overlay(Divider().background(Theme.border.opacity(0.5)), alignment: .bottom)
        .sheet(isPresented: $showInfo) {
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
                        showInfo = false
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
                sets: $sets,
                activeSetIndex: $activeSetIndex,
                unit: unit,
                exercise: exercise,
                onDelete: { idx in
                    deleteSet(at: idx)
                },
                onDuplicate: { idx in duplicateSet(at: idx) },
                onLogSet: { idx in logSet(at: idx) },
                onAdd: {
                    let last = sets.last ?? SetInput(reps: 10, weight: 0)
                    sets.append(SetInput(
                        reps: last.reps,
                        weight: last.weight,
                        tag: last.tag,
                        autoWeight: last.autoWeight,
                        didSeedFromMemory: false
                    ))
                    // Select the newly added set
                    activeSetIndex = sets.count - 1
                },
                onSetsSectionFrameCaptured: { frame in
                    setsSectionFrame = frame
                    checkFramesReady()
                },
                onSetTypeFrameCaptured: { frame in
                    setTypeFrame = frame
                    checkFramesReady()
                },
                onCarouselsFrameCaptured: { frame in
                    carouselsFrame = frame
                    checkFramesReady()
                },
                onPresetsFrameCaptured: { frame in
                    presetsFrame = frame
                    checkFramesReady()
                },
                onAddSetButtonFrameCaptured: { frame in
                    addSetButtonFrame = frame
                    checkFramesReady()
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

        var onSetsSectionFrameCaptured: ((CGRect) -> Void)? = nil
        var onSetTypeFrameCaptured: ((CGRect) -> Void)? = nil
        var onCarouselsFrameCaptured: ((CGRect) -> Void)? = nil
        var onPresetsFrameCaptured: ((CGRect) -> Void)? = nil
        var onAddSetButtonFrameCaptured: ((CGRect) -> Void)? = nil

        var body: some View {
            Section {
                // Minimal section header - just a subtle divider


                ForEach(Array(sets.indices), id: \.self) { i in
                    let isActive = (i == activeSetIndex)
                    let isCompleted = sets[i].isCompleted
                    let isGhost = sets[i].isGhost && !isCompleted

                    // Determine if this set has the active timer
                    let hasActiveTimer: Bool = {
                        // Must be completed
                        guard isCompleted else { return false }
                        // Must be the most recently completed set
                        guard let lastCompletedIndex = sets.lastIndex(where: { $0.isCompleted }),
                              lastCompletedIndex == i else { return false }
                        // Must have a timer running for this exercise
                        let manager = RestTimerManager.shared
                        return manager.isTimerFor(exerciseID: exercise.id) && manager.isRunning
                    }()

                    SetRowUnified(
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
                        onSetTypeFrameCaptured: i == 0 ? onSetTypeFrameCaptured : nil,
                        onCarouselsFrameCaptured: i == 0 ? onCarouselsFrameCaptured : nil
                    )
                    .captureFrame(in: .global) { frame in
                        // Capture the frame of the first set to represent the sets section
                        if i == 0 {
                            onSetsSectionFrameCaptured?(frame)
                        }
                    }
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if isCompleted {
                            Button {
                                sets[i].isCompleted = false
                            } label: {
                                Label("Mark Incomplete", systemImage: "arrow.uturn.backward.circle")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                sets[i].isCompleted = true
                            } label: {
                                Label("Mark Complete", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { onDelete(i) }
                        Button("Duplicate") { onDuplicate(i) }
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
                    .captureFrame(in: .global) { frame in
                        onPresetsFrameCaptured?(frame)
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
                    .captureFrame(in: .global) { frame in
                        onAddSetButtonFrameCaptured?(frame)
                    }
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
        guard sets.indices.contains(index) else { return }
        let s = sets[index]
        sets.append(s)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteSet(at index: Int) {
        guard sets.indices.contains(index) else { return }

        let deletedSet = sets[index]

        // Check if this was the most recently completed set
        let lastCompletedIndex = sets.lastIndex(where: { $0.isCompleted })
        let wasLastCompletedSet = deletedSet.isCompleted && lastCompletedIndex == index

        // Remove the set
        sets.remove(at: index)

        // If we deleted the most recently completed set, stop the timer
        if wasLastCompletedSet {
            let manager = RestTimerManager.shared
            if manager.isTimerFor(exerciseID: exercise.id) {
                manager.stopTimer()
            }
        }

        // Adjust active index if needed
        if activeSetIndex >= sets.count {
            activeSetIndex = max(0, sets.count - 1)
        }
    }

    private func generateNextSet() {
        if let lastSet = sets.last {
            let newSet = SetInput(
                reps: lastSet.reps,
                weight: lastSet.weight,
                tag: lastSet.tag,
                autoWeight: false,
                didSeedFromMemory: false,
                isCompleted: false,
                isGhost: false
            )
            sets.append(newSet)
        } else {
            sets.append(SetInput(reps: 10, weight: 0, tag: .working, autoWeight: true))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func preloadExistingIfNeeded(force: Bool = false) {
        guard let id = currentEntryID else { return }
        guard force || !didPreloadExisting else { return }
        if let entry = store.currentWorkout?.entries.first(where: { $0.id == id }),
           !entry.sets.isEmpty {
            sets = entry.sets
            activeSetIndex = entry.activeSetIndex
        }
        didPreloadExisting = true
    }

    private func prefillFromWorkoutHistory() {
        guard !didPrefillFromHistory else { return }

        // Check if user has completed this exercise before
        if let lastSet = store.lastWorkingSet(exercise: exercise) {
            // User has history - prefill with their last performance
            sets = [SetInput(
                reps: lastSet.reps,
                weight: lastSet.weightKg,
                tag: .working,
                autoWeight: false,
                didSeedFromMemory: true
            )]
            print("✅ Prefilled exercise '\(exercise.name)' with last performance: \(lastSet.reps) reps @ \(lastSet.weightKg)kg")
        } else {
            // No history - use weight suggestion helper
            let suggestedWeight = WeightSuggestionHelper.suggestInitialWeight(for: exercise)
            let suggestedReps = WeightSuggestionHelper.suggestInitialReps(for: exercise)
            sets = [SetInput(
                reps: suggestedReps,
                weight: suggestedWeight,
                tag: .working,
                autoWeight: true,
                didSeedFromMemory: false
            )]
            if suggestedWeight > 0 {
                print("✅ Suggested initial weight for '\(exercise.name)': \(suggestedWeight)kg @ \(suggestedReps) reps")
            }
        }

        didPrefillFromHistory = true
    }

    private func autoSelectFirstIncompleteSet() {
        // Find the first set that is not completed
        if let firstIncomplete = sets.firstIndex(where: { !$0.isCompleted && !$0.isGhost }) {
            activeSetIndex = firstIncomplete
        } else {
            // If all sets are completed, select the last one
            activeSetIndex = max(0, sets.count - 1)
        }
    }

    // MARK: - Set Logging Logic (Auto-Save)

    private func logSet(at index: Int) {
        guard index < sets.count else { return }

        // 1. Mark set as completed
        sets[index].isCompleted = true

        // 2. Auto-save to workout (best practice: immediate save)
        if let entryID = currentEntryID {
            // Existing entry - update sets
            store.updateEntrySetsAndActiveIndex(entryID: entryID, sets: sets, activeSetIndex: activeSetIndex)
        } else {
            // First logged set - automatically add exercise to workout
            let entryID = store.addExerciseToCurrent(exercise)
            store.updateEntrySets(entryID: entryID, sets: cleanSets())
            currentEntryID = entryID  // Track this entry for future updates
        }

        // 3. Advance to next set if available (but don't generate a new one yet)
        if index < sets.count - 1 {
            // Move to next existing set
            activeSetIndex = index + 1
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
        guard let lastCompletedSet = sets.last(where: { $0.isCompleted }) else { return }

        // Check if we already have an incomplete set at the end - if so, just activate it
        if let lastSet = sets.last, !lastSet.isCompleted {
            activeSetIndex = sets.count - 1
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

        sets.append(newSet)
        activeSetIndex = sets.count - 1

        // Auto-save the new set to the workout
        if let entryID = currentEntryID {
            store.updateEntrySetsAndActiveIndex(entryID: entryID, sets: sets, activeSetIndex: activeSetIndex)
        }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cleanSets() -> [SetInput] {
        sets.map {
            var s = $0
            s.reps = max(0, s.reps)
            s.weight = max(0, s.weight)
            return s
        }
    }

    // MARK: - Tutorial Logic

    private func checkFramesReady() {
        let setsReady = setsSectionFrame != .zero && setsSectionFrame.height > 0
        let setTypeReady = setTypeFrame != .zero && setTypeFrame.width > 0
        let carouselsReady = carouselsFrame != .zero && carouselsFrame.width > 0
        let presetsReady = presetsFrame != .zero && presetsFrame.width > 0
        let addSetReady = addSetButtonFrame != .zero && addSetButtonFrame.width > 0
        let infoReady = infoButtonFrame != .zero && infoButtonFrame.width > 0
        let saveReady = saveButtonFrame != .zero && saveButtonFrame.width > 0

        if setsReady && setTypeReady && carouselsReady && presetsReady && addSetReady && infoReady && saveReady && !framesReady {
            framesReady = true
        }
    }

    private var tutorialSteps: [TutorialStep] {
        // Move all frames up to align with UI elements
        func adjustFrame(_ frame: CGRect) -> CGRect {
            return CGRect(
                x: frame.origin.x,
                y: frame.origin.y - frameUpwardAdjustment,
                width: frame.width,
                height: frame.height
            )
        }

        return [
            TutorialStep(
                title: "Sets Section",
                message: "This is where you track your sets. Each row represents one set with reps and weight.",
                spotlightFrame: adjustFrame(setsSectionFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Set Type",
                message: "Tap the colored dot to cycle through set types: Working, Warmup, Drop set, or Failure set.",
                spotlightFrame: adjustFrame(setTypeFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 12
            ),
            TutorialStep(
                title: "Reps & Weight",
                message: "Use the scroll wheels to adjust reps and weight. Swipe up or down to change values quickly.",
                spotlightFrame: adjustFrame(carouselsFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 14
            ),
            TutorialStep(
                title: "Quick Presets",
                message: "Use Last copies your previous workout. 5×5 creates five sets of five reps. Try 1RM appears when you have a personal record.",
                spotlightFrame: adjustFrame(presetsFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 12
            ),
            TutorialStep(
                title: "Add Set",
                message: "Tap here to add more sets to your workout. New sets copy the values from your last set.",
                spotlightFrame: adjustFrame(addSetButtonFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 14
            ),
            TutorialStep(
                title: "Exercise Info",
                message: "Tap the info button to see exercise details, watch tutorial videos, and adjust rest timer settings.",
                spotlightFrame: adjustFrame(infoButtonFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 24
            ),
            TutorialStep(
                title: "Save Workout",
                message: "When you're done, tap here to save all your sets to your current workout session.",
                spotlightFrame: adjustFrame(saveButtonFrame).insetBy(dx: -8, dy: -8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            )
        ]
    }

    private func advanceTutorial() {
        if currentTutorialStep < tutorialSteps.count - 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentTutorialStep += 1
            }
        } else {
            completeTutorial()
        }
    }

    private func skipTutorial() {
        completeTutorial()
    }

    private func completeTutorial() {
        withAnimation(.easeOut(duration: 0.2)) {
            showTutorial = false
        }
        onboardingManager.complete(.exerciseSession)
    }

    // MARK: - Save Logic

    private var saveButtonTitle: String {
        // All sets are auto-saved when logged, so this button just closes the view
        return "Done"
    }

    private func handleSave() {
        // Check if there are unlogged sets that appear to be modified
        if hasUnloggedModifiedSets() {
            showUnsavedSetsAlert = true
            return
        }

        // No modified sets, proceed with cleanup and dismiss
        cleanupAndDismiss()
    }

    private func cleanupAndDismiss() {
        // Silently remove any unlogged sets before dismissing
        if let entryID = currentEntryID {
            let loggedSets = sets.filter { $0.isCompleted }
            if !loggedSets.isEmpty {
                store.updateEntrySets(entryID: entryID, sets: loggedSets)
            }
        }

        dismiss()

        if returnToHomeOnSave {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
            AppBus.postResetHome(reason: .user_intent)
        } else {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
        }
    }

    // MARK: - Unlogged Sets Detection

    private func hasUnloggedModifiedSets() -> Bool {
        sets.contains { set in
            !set.isCompleted && isSetModified(set)
        }
    }

    private func countUnloggedModifiedSets() -> Int {
        sets.filter { set in
            !set.isCompleted && isSetModified(set)
        }.count
    }

    private func isSetModified(_ set: SetInput) -> Bool {
        // A set is considered "modified" (should warn before deleting) if:
        // 1. It has meaningful values (reps > 0 or weight > 0)
        // 2. AND it's NOT an untouched auto-generated placeholder that matches the last completed set

        let hasValues = set.reps > 0 || set.weight > 0

        // If it's an auto-generated placeholder, check if it matches the last completed set
        if set.isAutoGeneratedPlaceholder {
            guard let lastCompletedSet = sets.last(where: { $0.isCompleted }) else {
                // No completed sets to compare against - treat as unmodified placeholder
                return false
            }

            // Compare with last completed set - if values match exactly, it's unmodified
            let matchesLastSet = (
                set.reps == lastCompletedSet.reps &&
                abs(set.weight - lastCompletedSet.weight) < 0.01 && // Float comparison
                set.tag == lastCompletedSet.tag
            )

            if matchesLastSet {
                // Auto-generated and unchanged from template → safe to silently delete
                return false
            } else {
                // Auto-generated but user modified it → warn before deleting
                return hasValues
            }
        }

        // Not an auto-generated placeholder, so consider it modified if it has values
        return hasValues
    }

    private func saveAsNewEntry() {
        let clean = cleanSets()

        guard clean.contains(where: { $0.reps > 0 || $0.weight > 0 }) else {
            showEmptyAlert = true
            return
        }

        let entryID = store.addExerciseToCurrent(exercise)
        store.updateEntrySets(entryID: entryID, sets: clean)

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        dismiss()

        if returnToHomeOnSave {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
            AppBus.postResetHome(reason: .user_intent)
        } else {
            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
        }
    }

    private func saveToCurrentWithoutDismiss() {
        guard let entryID = currentEntryID else { return }
        let clean = cleanSets()

        guard clean.contains(where: { $0.reps > 0 || $0.weight > 0 }) else {
            showEmptyAlert = true
            return
        }

        store.updateEntrySetsAndActiveIndex(entryID: entryID, sets: clean, activeSetIndex: activeSetIndex)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

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
