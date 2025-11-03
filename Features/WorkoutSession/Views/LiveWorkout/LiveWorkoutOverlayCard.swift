// LiveWorkoutOverlayCard.swift
import SwiftUI
import SwiftData

struct LiveWorkoutOverlayCard: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @ObservedObject private var restTimer = RestTimerManager.shared
    @Environment(\.modelContext) private var context

    let namespace: Namespace.ID
    let title: String
    let subtitle: String
    let showContent: Bool
    let onClose: () -> Void
    let startDate: Date

    @State private var dragOffset: CGFloat = 0
    @State private var editingEntry: WorkoutEntry? = nil
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .matchedGeometryEffect(id: "liveHeader", in: namespace)

            Divider().overlay(DS.Semantic.border).opacity(0.7)

            Group {
                if let current = store.currentWorkout, !current.entries.isEmpty {
                    content(for: current)
                } else {
                    ContentUnavailableView("No active workout", systemImage: "bolt.heart")
                        .padding(.vertical, 40)
                }
            }
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.98, anchor: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: showContent)
        }
        .foregroundStyle(DS.Semantic.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DS.Theme.cardBottom, DS.Theme.cardBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(DS.Semantic.border, lineWidth: 1)
                )
                .matchedGeometryEffect(id: "liveCardBG", in: namespace)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 18, x: 0, y: 10)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in dragOffset = max(0, value.translation.height) }
                .onEnded { value in
                    let shouldClose = value.translation.height > 80 || value.velocity > 600
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        if shouldClose { onClose() }
                        dragOffset = 0
                    }
                }
        )
        .sheet(item: $editingEntry) { entry in
            if let ex = store.exerciseForEntry(entry) {
                NavigationStack {
                    ExerciseSessionView(
                        exercise: ex,
                        initialEntryID: entry.id,
                        returnToHomeOnSave: false
                    )
                    .environmentObject(store)
                }
            } else {
                Text("Exercise not found")
            }
        }
        .onChange(of: restTimer.state) { oldState, newState in
            handleTimerStateChange(newState: newState)
        }
        .onAppear {
            checkForPendingSetGeneration()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeneratePendingSetBeforeTimer"))) { notification in
            if let exerciseID = notification.userInfo?["exerciseID"] as? String {
                generatePendingSetImmediately(exerciseID: exerciseID)
            }
        }
    }

    // MARK: - Timer Completion Handler

    private func handleTimerStateChange(newState: RestTimerState) {
        // Check if timer just completed
        guard case .completed(let exerciseID, _) = newState else { return }

        // Find the entry for this exercise
        guard let entry = store.currentWorkout?.entries.first(where: { $0.exerciseID == exerciseID }) else {
            return
        }

        // Generate new set for this entry
        generateNewSetAfterRest(for: entry)

        // Clear pending flag
        restTimer.clearPendingSetGeneration(for: exerciseID)
    }

    /// Check for pending set generation (e.g., when timer completed while app was closed)
    private func checkForPendingSetGeneration() {
        guard let workout = store.currentWorkout else { return }

        // Check each entry for pending set generation
        for entry in workout.entries {
            if restTimer.hasPendingSetGeneration(for: entry.exerciseID) {
                AppLogger.debug("Found pending set generation for \(entry.exerciseName), generating now", category: AppLogger.workout)
                generateNewSetAfterRest(for: entry)
                restTimer.clearPendingSetGeneration(for: entry.exerciseID)
            }
        }
    }

    /// Generate pending set immediately (called from notification)
    private func generatePendingSetImmediately(exerciseID: String) {
        guard let workout = store.currentWorkout else { return }

        // Find the entry for this exercise
        guard let entry = workout.entries.first(where: { $0.exerciseID == exerciseID }) else {
            AppLogger.warning("Cannot generate set - exercise not found: \(exerciseID)", category: AppLogger.workout)
            return
        }

        // Only generate if there's a pending flag
        if restTimer.hasPendingSetGeneration(for: exerciseID) {
            AppLogger.debug("Generating pending set immediately for \(entry.exerciseName) before starting timer", category: AppLogger.workout)
            generateNewSetAfterRest(for: entry)
            restTimer.clearPendingSetGeneration(for: exerciseID)
        } else {
            AppLogger.debug("No pending set for \(entry.exerciseName), skipping generation", category: AppLogger.workout)
        }
    }

    private func generateNewSetAfterRest(for entry: WorkoutEntry) {
        // Find the last completed set to use as a template
        guard let lastCompletedSet = entry.sets.last(where: { $0.isCompleted }) else { return }

        // Check if we already have an incomplete set at the end - if so, do nothing
        if let lastSet = entry.sets.last, !lastSet.isCompleted {
            return
        }

        // Generate a new set with the same values as the last completed set
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

        var updatedSets = entry.sets
        updatedSets.append(newSet)

        // Update the entry in the store
        store.updateEntrySetsAndActiveIndex(entryID: entry.id, sets: updatedSets, activeSetIndex: updatedSets.count - 1)

        AppLogger.debug("Auto-generated new set for \(entry.exerciseName) after rest timer completed", category: AppLogger.workout)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.heart.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)

                    // Show rest timer OR workout timer, not both
                    if restTimer.isActive {
                        RestTimerCompact()
                    } else {
                        WorkoutTimerText(startDate: startDate)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            // Close
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .accessibilityLabel("Close live workout")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Exercise State Logic

    fileprivate enum ExerciseState {
        case finished      // All sets completed
        case inProgress    // At least one set completed, but not all
        case upNext        // No completed sets yet
    }

    private func exerciseState(_ entry: WorkoutEntry) -> ExerciseState {
        guard !entry.sets.isEmpty else { return .upNext }

        let completedSets = entry.sets.filter { $0.isCompleted }

        if completedSets.isEmpty {
            return .upNext
        }

        // Finished only if ALL sets completed (including hero)
        if completedSets.count == entry.sets.count {
            return .finished
        } else {
            return .inProgress
        }
    }

    // MARK: - Computed Properties

    private var heroEntry: WorkoutEntry? {
        guard let current = store.currentWorkout else { return nil }

        // 1. Explicit selection by user (activeEntryID)
        if let activeID = current.activeEntryID,
           let entry = current.entries.first(where: { $0.id == activeID }) {
            return entry
        }

        // 2. First "in progress" exercise (has some completed but not all)
        if let firstInProgress = current.entries.first(where: { exerciseState($0) == .inProgress }) {
            return firstInProgress
        }

        // 3. First "up next" exercise (no completed sets)
        if let firstUpNext = current.entries.first(where: { exerciseState($0) == .upNext }) {
            return firstUpNext
        }

        // 4. If all exercises are finished, show the last one as hero
        if let lastFinished = current.entries.last(where: { exerciseState($0) == .finished }) {
            return lastFinished
        }

        // 5. Fallback to first exercise
        return current.entries.first
    }

    private var completedEntries: [WorkoutEntry] {
        guard let current = store.currentWorkout else { return [] }
        return current.entries.filter { entry in
            entry.id != heroEntry?.id && exerciseState(entry) == .finished
        }
    }

    private var inProgressEntries: [WorkoutEntry] {
        guard let current = store.currentWorkout else { return [] }
        return current.entries.filter { entry in
            entry.id != heroEntry?.id && exerciseState(entry) == .inProgress
        }
    }

    private var upNextEntries: [WorkoutEntry] {
        guard let current = store.currentWorkout else { return [] }
        return current.entries.filter { entry in
            entry.id != heroEntry?.id && exerciseState(entry) == .upNext
        }
    }

    /// Check if there are any incomplete exercises (up next OR in progress)
    private var hasIncompleteExercises: Bool {
        guard let current = store.currentWorkout else { return false }
        return current.entries.contains { entry in
            let state = exerciseState(entry)
            return state == .upNext || state == .inProgress
        }
    }

    /// Check and update weekly goal streak after workout completion
    private func checkWeeklyGoalStreak() {
        // Fetch weekly goal from context
        let goalDescriptor = FetchDescriptor<WeeklyGoal>(
            predicate: #Predicate { $0.isSet == true }
        )
        guard let goal = try? context.fetch(goalDescriptor).first else {
            // No weekly goal set, skip streak check
            return
        }

        // Calculate current week progress
        let weekProgress = store.currentWeekProgress(goal: goal, context: context)

        // Check if weekly goal is met and update streak
        RewardsEngine.shared.checkWeeklyGoalStreak(
            weekStart: weekProgress.weekStart,
            strengthDaysDone: weekProgress.strengthDaysDone,
            strengthTarget: goal.targetStrengthDays,
            mvpaMinutesDone: weekProgress.mvpaDone,
            mvpaTarget: goal.targetActiveMinutes
        )
    }

    // MARK: Content
    @ViewBuilder
    private func content(for current: CurrentWorkout) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Completed Section - What you've finished
                if !completedEntries.isEmpty {
                    ExerciseGroupSection(
                        title: "Completed",
                        entries: completedEntries,
                        onOpen: { entry in
                            store.setActiveEntry(entry.id)
                            editingEntry = entry
                        },
                        onRemove: { entryID in
                            store.removeEntry(entryID: entryID)
                        }
                    )
                    .padding(.top, 12)
                }

                // Hero Exercise Card - Primary focus
                if let hero = heroEntry {
                    CurrentExerciseHeroCard(
                        entry: hero,
                        state: exerciseState(hero),
                        onOpen: {
                            store.setActiveEntry(hero.id)
                            editingEntry = hero
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, completedEntries.isEmpty ? 12 : 16)
                }

                // In Progress Section - Started but not finished
                if !inProgressEntries.isEmpty {
                    ExerciseGroupSection(
                        title: "In Progress",
                        entries: inProgressEntries,
                        onOpen: { entry in
                            store.setActiveEntry(entry.id)
                            editingEntry = entry
                        },
                        onRemove: { entryID in
                            store.removeEntry(entryID: entryID)
                        }
                    )
                    .padding(.top, 16)
                }

                // Up Next Section - Not started yet
                if !upNextEntries.isEmpty {
                    ExerciseGroupSection(
                        title: "Up Next",
                        entries: upNextEntries,
                        onOpen: { entry in
                            store.setActiveEntry(entry.id)
                            editingEntry = entry
                        },
                        onRemove: { entryID in
                            store.removeEntry(entryID: entryID)
                        }
                    )
                    .padding(.top, 16)
                }

                Spacer(minLength: 120)
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.colorScheme, .dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OverlayBottomActions(
                hasIncompleteExercises: hasIncompleteExercises,
                showDiscardConfirmation: $showDiscardConfirmation,
                onFinish: {
                    // 1) Finish & get PR count to report
                    let result = store.finishCurrentWorkoutAndReturnPRs()   // (workoutId, prCount)

                    // 2) Calculate new exercises (first time completing them)
                    let seen = Set(store.completedWorkouts.dropFirst().flatMap { $0.entries.map(\.exerciseID) })
                    let thisIDs = Set((store.completedWorkouts.first?.entries ?? []).map(\.exerciseID))
                    let newIDs = thisIDs.subtracting(seen)

                    // 3) Send reward events
                    RewardsEngine.shared.process(event: "workout_completed", payload: [
                        "workoutId": result.workoutId
                    ])

                    if newIDs.count > 0 {
                        RewardsEngine.shared.process(event: "exercise_new", payload: [
                            "count": newIDs.count
                        ])
                    }

                    if result.prCount > 0 {
                        RewardsEngine.shared.process(event: "pr_achieved", payload: [
                            "count": result.prCount
                        ])
                    }

                    // 4) Check weekly goal streak
                    checkWeeklyGoalStreak()

                    // 5) Close UI
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
                },
                onDiscardConfirmed: {
                    store.discardCurrentWorkout()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
                }
            )
            //OverlayBottomActions(
              //  onFinish: {
                //    store.finishCurrentWorkout()
                  //  UINotificationFeedbackGenerator().notificationOccurred(.success)
                    //withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
               // },
                //onDiscard: {
                  //  store.discardCurrentWorkout()
                    //UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    //withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
               // }
           // )
            //.background(LinearGradient(
              //  colors: [Theme.cardBottom.opacity(0.0), Theme.cardBottom.opacity(0.25)],
                //startPoint: .top, endPoint: .bottom
            //))
        }
    }
}

// MARK: - Helpers
private extension DragGesture.Value {
    var velocity: CGFloat {
        let dy = predictedEndLocation.y - location.y
        return abs(dy) * 10
    }
}

// MARK: - Bottom actions (dark/brand styling)
private struct OverlayBottomActions: View {
    let hasIncompleteExercises: Bool
    @Binding var showDiscardConfirmation: Bool
    let onFinish: () -> Void
    let onDiscardConfirmed: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Show message if there are incomplete exercises
            if hasIncompleteExercises {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(DS.Theme.accent)
                    Text("Complete or remove all exercises to finish")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Theme.accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DS.Theme.accent.opacity(0.25), lineWidth: 1)
                        )
                )
            }

            // Swipe — disabled if there are incomplete exercises
            SwipeToConfirm(
                text: hasIncompleteExercises ? "Complete exercises first" : "Slide to finish workout",
                systemImage: "checkmark.seal.fill",
                background: .thinMaterial,
                trackColor: DS.Theme.track,
                knobSize: 52,
                onConfirm: onFinish
            )
            .tint(hasIncompleteExercises ? DS.Semantic.textSecondary : DS.Theme.accent)
            .opacity(hasIncompleteExercises ? 0.4 : 1.0)
            .disabled(hasIncompleteExercises)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                showDiscardConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Discard Workout", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .foregroundStyle(DS.Semantic.textSecondary)
            .confirmationDialog("Discard Workout", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) {
                    onDiscardConfirmed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to discard this workout? You can undo this action.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Row
private struct LiveWorkoutRow: View {
    let entry: WorkoutEntry
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onDuplicate: (() -> Void)?

    private var summary: String {
        if entry.sets.isEmpty { return "No sets yet" }
        return entry.sets.map { "\($0.reps)×\(Int($0.weight))kg" }.joined(separator: "  •  ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.exerciseName)
                    .font(.subheadline.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel("Remove \(entry.exerciseName)")
        }
    
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            if let onDuplicate {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            if let onDuplicate {
                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            }
        }
    }
}

// MARK: - Timer (numbers only, tiny neon pill)
struct WorkoutTimerText: View {
    let startDate: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startDate))
            let h = Int(elapsed) / 3600
            let m = (Int(elapsed) % 3600) / 60
            let s = Int(elapsed) % 60
            Text(String(format: "%02d:%02d:%02d", h, m, s))
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(DS.Theme.accent)
                .background(DS.Theme.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(DS.Theme.accent.opacity(0.35), lineWidth: 1))
        }
    }
}

// MARK: - Current Exercise Hero Card
private struct CurrentExerciseHeroCard: View {
    let entry: WorkoutEntry
    let state: LiveWorkoutOverlayCard.ExerciseState
    let onOpen: () -> Void

    private var stateLabel: String {
        switch state {
        case .finished: return "COMPLETED"
        case .inProgress: return "CURRENT"
        case .upNext: return "UP NEXT"
        }
    }

    private var stateColor: Color {
        switch state {
        case .finished: return DS.Theme.accent  // Keep yellow for completed hero
        case .inProgress: return DS.Theme.accent
        case .upNext: return DS.Exercise.upNext
        }
    }

    private var statusText: String {
        if entry.sets.isEmpty { return "Tap to add sets" }
        let completedCount = entry.sets.filter { $0.isCompleted }.count

        if completedCount == 0 {
            return "\(entry.sets.count) sets planned"
        } else if completedCount == entry.sets.count {
            return "All sets completed"
        } else {
            return "\(completedCount) of \(entry.sets.count) sets completed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(stateLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(stateColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.exerciseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)

                // Status text
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)

                // Set data pills
                if !entry.sets.isEmpty {
                    SetDataDisplay(sets: entry.sets, maxDisplay: 6, style: .detailed)
                        .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(stateColor.opacity(0.4), lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

// MARK: - Exercise Group Section (Generic for all states)
private struct ExerciseGroupSection: View {
    let title: String
    let entries: [WorkoutEntry]
    let onOpen: (WorkoutEntry) -> Void
    let onRemove: (UUID) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Text("\(entries.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable list
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.id) { entry in
                        ExerciseGroupRow(
                            entry: entry,
                            onOpen: { onOpen(entry) },
                            onRemove: { onRemove(entry.id) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Exercise Group Row
private struct ExerciseGroupRow: View {
    let entry: WorkoutEntry
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.exerciseName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)

                SetDataDisplay(sets: entry.sets, maxDisplay: 4, style: .compact)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 32)  // Indent to show it's nested
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

// MARK: - Set Data Display Component
private struct SetDataDisplay: View {
    let sets: [SetInput]
    var maxDisplay: Int = 5
    var style: DisplayStyle = .detailed

    enum DisplayStyle {
        case detailed  // Show all info
        case compact   // More condensed
    }

    private var displaySets: [SetInput] {
        Array(sets.prefix(maxDisplay))
    }

    private var remainingCount: Int {
        max(0, sets.count - maxDisplay)
    }

    var body: some View {
        if sets.isEmpty {
            Text("No sets yet")
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(Array(displaySets.enumerated()), id: \.offset) { index, set in
                    SetPill(set: set, index: index + 1, style: style)
                }

                if remainingCount > 0 {
                    Text("+\(remainingCount) more")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DS.Semantic.textSecondary.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.03))
                        )
                }
            }
        }
    }
}

// MARK: - Set Pill
private struct SetPill: View {
    let set: SetInput
    let index: Int
    var style: SetDataDisplay.DisplayStyle

    private var displayText: String {
        let weight = Int(set.weight)
        if set.reps > 0 {
            return weight > 0 ? "\(weight)kg×\(set.reps)" : "\(set.reps) reps"
        } else {
            return weight > 0 ? "\(weight)kg" : "—"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(DS.Theme.accent)
            }

            Text(displayText)
                .font(style == .compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                .foregroundStyle(set.isCompleted ? DS.Semantic.textPrimary : DS.Semantic.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, style == .compact ? 6 : 8)
        .padding(.vertical, style == .compact ? 3 : 4)
        .background(
            Capsule()
                .fill(set.isCompleted ? DS.Theme.accent.opacity(0.15) : Color.white.opacity(0.04))
                .overlay(
                    Capsule()
                        .stroke(
                            set.isCompleted ? DS.Theme.accent.opacity(0.3) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .opacity(set.isCompleted ? 1.0 : 0.6)
    }
}

// MARK: - Flow Layout (for wrapping pills)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))

                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
