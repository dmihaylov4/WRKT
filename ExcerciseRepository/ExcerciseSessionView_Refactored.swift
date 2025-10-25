//
//  ExerciseSessionView.swift
//  WRKT
//
//  Main exercise session view - refactored into modular components
//

import SwiftUI
import Foundation
import SVGView
//import AppModels

// Use the theme from ExerciseSessionModels
typealias Theme = ExerciseSessionTheme

// MARK: - Exercise Session View

struct ExerciseSessionView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    let exercise: Exercise
    var currentEntryID: UUID? = nil
    var returnToHomeOnSave: Bool = false

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    @Environment(\.dismiss) private var dismiss

    @State private var sets: [SetInput] = [SetInput(reps: 10, weight: 0)]
    @State private var activeSetIndex: Int = 0
    @State private var didPreloadExisting = false
    @State private var showEmptyAlert = false
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
    private let manualYAdjustment: CGFloat = 70

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
                .navigationBarTitleDisplayMode(.inline)
                .background(Theme.bg.ignoresSafeArea())
                .toolbarBackground(Theme.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .alert("Empty workout", isPresented: $showEmptyAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Add at least one set with reps to save.")
                }
                .onAppear {
                    preloadExistingIfNeeded()
                    DispatchQueue.main.async {
                        yOffset = geometry.safeAreaInsets.top
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if !framesReady && !onboardingManager.hasSeenExerciseSession && !showTutorial {
                            showTutorial = true
                        }
                    }
                }
                .onChange(of: currentEntryID) { _ in preloadExistingIfNeeded(force: true) }
                .onChange(of: framesReady) { _, ready in
                    if ready && !onboardingManager.hasSeenExerciseSession && !showTutorial {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTutorial = true
                        }
                    }
                }
                .onReceive(RestTimerManager.shared.$state) { state in
                    if case .completed(let exerciseID, _) = state,
                       exerciseID == exercise.id,
                       activeSetIndex < sets.count {
                        sets[activeSetIndex].isCompleted = true
                        let wasLastSet = (activeSetIndex == sets.count - 1)
                        if wasLastSet {
                            generateNextSet()
                            activeSetIndex += 1
                        } else {
                            activeSetIndex += 1
                        }
                        if let entryID = currentEntryID {
                            store.updateEntrySetsAndActiveIndex(entryID: entryID, sets: sets, activeSetIndex: activeSetIndex)
                        }
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

    // MARK: - Modern Header

    private var modernHeader: some View {
        VStack(spacing: 0) {
            RestTimerBanner(exerciseID: exercise.id)

            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            StatBadge(icon: "list.bullet", value: "\(workingSets)", label: "sets")
                            StatBadge(icon: "repeat", value: "\(totalReps)", label: "reps")

                            if let e1rmKg = store.bestE1RM(exercise: exercise) {
                                let e1rmDisplay = unit == .kg ? e1rmKg : e1rmKg * 2.20462
                                StatBadge(
                                    icon: "star.fill",
                                    value: String(format: "%.0f", e1rmDisplay),
                                    label: "1RM \(unit.rawValue)",
                                    accent: true
                                )
                            }
                        }
                    }

                    Spacer()

                    Button {
                        showInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 44, height: 44)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                    .accessibilityLabel("Exercise info")
                    .captureFrame(in: .global) { frame in
                        infoButtonFrame = frame
                        checkFramesReady()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .overlay(Divider().background(Theme.border), alignment: .bottom)
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
                    sets.remove(at: idx)
                    if activeSetIndex >= sets.count {
                        activeSetIndex = max(0, sets.count - 1)
                    }
                },
                onDuplicate: { idx in duplicateSet(at: idx) },
                onAdd: {
                    let last = sets.last ?? SetInput(reps: 10, weight: 0)
                    sets.append(SetInput(
                        reps: last.reps,
                        weight: last.weight,
                        tag: last.tag,
                        autoWeight: last.autoWeight,
                        didSeedFromMemory: false
                    ))
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
        let onAdd: () -> Void

        var onSetsSectionFrameCaptured: ((CGRect) -> Void)? = nil
        var onSetTypeFrameCaptured: ((CGRect) -> Void)? = nil
        var onCarouselsFrameCaptured: ((CGRect) -> Void)? = nil
        var onPresetsFrameCaptured: ((CGRect) -> Void)? = nil
        var onAddSetButtonFrameCaptured: ((CGRect) -> Void)? = nil

        var body: some View {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondary)

                    Text("Sets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Text("\(sets.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .captureFrame(in: .global) { frame in
                    onSetsSectionFrameCaptured?(frame)
                }

                ForEach(Array(sets.indices), id: \.self) { i in
                    let isActive = (i == activeSetIndex)
                    let isCompleted = sets[i].isCompleted
                    let isGhost = sets[i].isGhost && !isCompleted

                    SetRowUnified(
                        index: i + 1,
                        set: $sets[i],
                        unit: unit,
                        exercise: exercise,
                        isActive: isActive,
                        isGhost: isGhost,
                        onDuplicate: { onDuplicate(i) },
                        onActivate: {
                            activeSetIndex = i
                        },
                        onSetTypeFrameCaptured: i == 0 ? onSetTypeFrameCaptured : nil,
                        onCarouselsFrameCaptured: i == 0 ? onCarouselsFrameCaptured : nil
                    )
                    .listRowInsets(.init(top: 6, leading: 6, bottom: 6, trailing: 6))
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        isCompleted ? Theme.accent.opacity(0.05) :
                        isActive ? Theme.accent.opacity(0.03) :
                        Theme.surface
                    )
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
            if let lastWorkingSet = store.lastWorkingSet(exercise: exercise) {
                sets.append(SetInput(
                    reps: lastWorkingSet.reps,
                    weight: lastWorkingSet.weightKg,
                    tag: .working,
                    autoWeight: true,
                    didSeedFromMemory: true
                ))
            }
        }

        private func applyFiveByFive() {
            sets = (1...5).map { _ in
                SetInput(reps: 5, weight: 0, tag: .working, autoWeight: true)
            }
        }

        private func tryOneRM() {
            guard let e1rm = store.bestE1RM(exercise: exercise) else { return }
            sets.append(SetInput(
                reps: 1,
                weight: e1rm,
                tag: .working,
                autoWeight: false,
                didSeedFromMemory: false
            ))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        let totalOffset = yOffset + manualYAdjustment

        func adjustFrame(_ frame: CGRect) -> CGRect {
            CGRect(
                x: frame.origin.x,
                y: frame.origin.y - totalOffset,
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
        if currentEntryID == nil {
            return "Save to Current Workout"
        }

        if activeSetIndex < sets.count && sets[activeSetIndex].isGhost {
            return "Log Set \(activeSetIndex + 1)"
        }

        let allCompleted = sets.allSatisfy { $0.isCompleted || $0.isGhost }
        if allCompleted {
            return "Update Workout"
        }

        return "Log Set \(activeSetIndex + 1)"
    }

    private func handleSave() {
        if activeSetIndex < sets.count && sets[activeSetIndex].isGhost {
            sets[activeSetIndex].isGhost = false
        }

        if currentEntryID == nil {
            saveAsNewEntry()
        } else {
            saveToCurrentWithoutDismiss()
        }

        startRestTimerIfEnabled()
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
