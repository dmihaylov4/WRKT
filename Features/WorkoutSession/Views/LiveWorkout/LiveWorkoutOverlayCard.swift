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
    @State private var showShareWorkout = false
    @State private var completedWorkoutToShare: CompletedWorkout?

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
            ChamferedRectangle(.hero)
                .fill(
                    LinearGradient(
                        colors: [DS.Theme.cardBottom, DS.Theme.cardBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    ChamferedRectangle(.hero)
                        .stroke(DS.Semantic.border, lineWidth: 1)
                )
                .matchedGeometryEffect(id: "liveCardBG", in: namespace)
        )
        .clipShape(ChamferedRectangle(.hero))
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
        .sheet(isPresented: $showShareWorkout) {
            if let workout = completedWorkoutToShare {
                PostCreationView(workout: workout)
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

        // Check if we should auto-generate a new set
        // Only auto-add sets up to 4 total completed sets (best practice to prevent annoying auto-generation)
        let completedSetsCount = entry.sets.filter { $0.isCompleted }.count
        if completedSetsCount >= 4 {
            AppLogger.info("Already have \(completedSetsCount) completed sets for \(entry.exerciseName), not auto-generating more", category: AppLogger.workout)

            // Show toast to inform user they need to manually add more sets
            WorkoutToastManager.shared.show(
                message: "\(completedSetsCount) sets completed! Tap + to add more",
                icon: "checkmark.circle.fill"
            )
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

    // MARK: - Superset Grouping

    /// Groups entries by their superset, preserving order
    fileprivate struct SupersetGroup: Identifiable {
        let id: UUID // supersetGroupID or entry.id for standalone
        let entries: [WorkoutEntry]
        var isSuperset: Bool { entries.count > 1 }
    }

    /// Get the overall state of a superset group (based on least complete exercise)
    private func groupState(_ group: SupersetGroup) -> ExerciseState {
        let states = group.entries.map { exerciseState($0) }
        // Group is only finished if ALL exercises are finished
        if states.allSatisfy({ $0 == .finished }) {
            return .finished
        }
        // Group is in progress if any exercise has started
        if states.contains(where: { $0 == .inProgress || $0 == .finished }) {
            return .inProgress
        }
        return .upNext
    }

    /// Groups entries into superset groups or standalone entries
    private func groupedEntries(from entries: [WorkoutEntry]) -> [SupersetGroup] {
        var groups: [SupersetGroup] = []
        var processedIDs: Set<UUID> = []

        for entry in entries {
            guard !processedIDs.contains(entry.id) else { continue }

            if let supersetID = entry.supersetGroupID {
                // Find all entries in this superset
                let supersetEntries = entries
                    .filter { $0.supersetGroupID == supersetID }
                    .sorted { ($0.orderInSuperset ?? 0) < ($1.orderInSuperset ?? 0) }

                supersetEntries.forEach { processedIDs.insert($0.id) }
                groups.append(SupersetGroup(id: supersetID, entries: supersetEntries))
            } else {
                // Standalone entry
                processedIDs.insert(entry.id)
                groups.append(SupersetGroup(id: entry.id, entries: [entry]))
            }
        }

        return groups
    }

    // MARK: - Computed Properties

    private var heroEntry: WorkoutEntry? {
        guard let current = store.currentWorkout else { return nil }

        // 1. Explicit selection by user (activeEntryID) — only if not fully completed
        if let activeID = current.activeEntryID,
           let entry = current.entries.first(where: { $0.id == activeID }),
           exerciseState(entry) != .finished {
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

        // 4. All exercises finished — no hero, they go into the Completed section
        return nil
    }

    /// True when all exercises are finished and there's no hero
    private var allExercisesCompleted: Bool {
        guard let current = store.currentWorkout, !current.entries.isEmpty else { return false }
        return current.entries.allSatisfy { exerciseState($0) == .finished }
    }

    /// All groups excluding the hero entry's group (if there is a hero)
    private var nonHeroGroups: [SupersetGroup] {
        guard let current = store.currentWorkout else { return [] }
        let groups = groupedEntries(from: current.entries)

        // No hero — all groups go into sections
        guard let hero = heroEntry else { return groups }

        // If hero is in a superset, exclude the entire group
        if let heroSupersetID = hero.supersetGroupID {
            return groups.filter { $0.id != heroSupersetID }
        } else {
            return groups.filter { !$0.entries.contains(where: { $0.id == hero.id }) }
        }
    }

    private var completedGroups: [SupersetGroup] {
        nonHeroGroups.filter { groupState($0) == .finished }
    }

    private var inProgressGroups: [SupersetGroup] {
        nonHeroGroups.filter { groupState($0) == .inProgress }
    }

    private var upNextGroups: [SupersetGroup] {
        nonHeroGroups.filter { groupState($0) == .upNext }
    }

    // Legacy computed properties for backwards compatibility
    private var completedEntries: [WorkoutEntry] {
        completedGroups.flatMap { $0.entries }
    }

    private var inProgressEntries: [WorkoutEntry] {
        inProgressGroups.flatMap { $0.entries }
    }

    private var upNextEntries: [WorkoutEntry] {
        upNextGroups.flatMap { $0.entries }
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
                if !completedGroups.isEmpty {
                    SupersetGroupSection(
                        title: "Completed",
                        groups: completedGroups,
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

                // Hero Exercise Card - Primary focus (show entire superset if hero is in one)
                if let hero = heroEntry {
                    if let supersetID = hero.supersetGroupID,
                       let heroGroup = groupedEntries(from: current.entries).first(where: { $0.id == supersetID }) {
                        // Hero is in a superset - show the superset card
                        SupersetHeroCard(
                            group: heroGroup,
                            heroEntryID: hero.id,
                            stateForEntry: exerciseState,
                            onOpen: { entry in
                                store.setActiveEntry(entry.id)
                                editingEntry = entry
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, completedGroups.isEmpty ? 12 : 16)
                    } else {
                        // Standalone hero
                        CurrentExerciseHeroCard(
                            entry: hero,
                            state: exerciseState(hero),
                            onOpen: {
                                store.setActiveEntry(hero.id)
                                editingEntry = hero
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, completedGroups.isEmpty ? 12 : 16)
                    }
                } else if allExercisesCompleted {
                    // All exercises finished — show completion prompt
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(DS.Theme.accent)

                        Text("All exercises completed")
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text("Slide below to finish your workout")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                }

                // In Progress Section - Started but not finished
                if !inProgressGroups.isEmpty {
                    SupersetGroupSection(
                        title: "In Progress",
                        groups: inProgressGroups,
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
                if !upNextGroups.isEmpty {
                    SupersetGroupSection(
                        title: "Up Next",
                        groups: upNextGroups,
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
        .overlay {
            if showDiscardConfirmation {
                DiscardConfirmationDialog(
                    isPresented: $showDiscardConfirmation,
                    onConfirm: {
                        store.discardCurrentWorkout()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }
                    }
                )
            }
        }
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

                    // 3) Send reward events (async to avoid blocking UI)
                    RewardsEngine.shared.processAsync(event: "workout_completed", payload: [
                        "workoutId": result.workoutId
                    ])

                    if newIDs.count > 0 {
                        RewardsEngine.shared.processAsync(event: "exercise_new", payload: [
                            "count": newIDs.count
                        ])
                    }

                    if result.prCount > 0 {
                        RewardsEngine.shared.processAsync(event: "pr_achieved", payload: [
                            "count": result.prCount
                        ])
                    }

                    // 4) Check weekly goal streak
                    checkWeeklyGoalStreak()

                    // 5) Close UI
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { onClose() }

                    // 6) Show share workout sheet (after animation completes)
                    if let completedWorkout = store.completedWorkouts.first {
                        // Delay to allow close animation to complete first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            completedWorkoutToShare = completedWorkout
                            showShareWorkout = true
                        }
                    }
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
                    ChamferedRectangle(.large)
                        .fill(DS.Theme.accent.opacity(0.12))
                        .overlay(
                            ChamferedRectangle(.large)
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
                    ChamferedRectangle(.large)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            ChamferedRectangle(.large)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Discard Confirmation Dialog
private struct DiscardConfirmationDialog: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }

            // Dialog box
            VStack(spacing: 20) {
                // Title & Message
                VStack(spacing: 8) {
                    Text("Discard Workout?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("Are you sure you want to discard this workout? You can undo this action.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Actions
                VStack(spacing: 12) {
                    // Destructive action
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        // Small delay before calling onConfirm to let animation finish
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onConfirm()
                        }
                    } label: {
                        Text("Discard Workout")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                ChamferedRectangle(.large)
                                    .fill(Color.red)
                            )
                    }

                    // Cancel action
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                ChamferedRectangle(.large)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        ChamferedRectangle(.large)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(
                ChamferedRectangle(.xl)
                    .fill(Color.black)
                    .overlay(
                        ChamferedRectangle(.xl)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 32, x: 0, y: 16)
            .padding(.horizontal, 32)
            .scaleEffect(isPresented ? 1.0 : 0.9)
            .opacity(isPresented ? 1.0 : 0)
        }
        .transition(.opacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
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
        return entry.sets.map { "\($0.reps)×\($0.weight.safeInt)kg" }.joined(separator: "  •  ")
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
    @EnvironmentObject var store: WorkoutStoreV2
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

                // Superset badge
                if entry.isInSuperset {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text("SUPERSET")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(DS.Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.Theme.accent.opacity(0.15), in: Capsule())
                }

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
            ChamferedRectangle(.large)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    ChamferedRectangle(.large)
                        .stroke(stateColor.opacity(0.4), lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button(action: onOpen) {
                Label("Edit Exercise", systemImage: "pencil")
            }

            if entry.isInSuperset {
                Button {
                    store.removeFromSuperset(entryID: entry.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Remove from Superset", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }
}

// MARK: - Superset Group Section (Groups superset exercises together)
private struct SupersetGroupSection: View {
    let title: String
    let groups: [LiveWorkoutOverlayCard.SupersetGroup]
    let onOpen: (WorkoutEntry) -> Void
    let onRemove: (UUID) -> Void

    @State private var isExpanded = false

    private var totalEntries: Int {
        groups.reduce(0) { $0 + $1.entries.count }
    }

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

                    Text("\(totalEntries)")
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

            // Expandable list with superset grouping
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        if group.isSuperset {
                            SupersetGroupRow(
                                entries: group.entries,
                                onOpen: onOpen,
                                onRemove: onRemove
                            )
                        } else if let entry = group.entries.first {
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
}

// MARK: - Superset Group Row (Connected exercises in a superset)
private struct SupersetGroupRow: View {
    @EnvironmentObject var store: WorkoutStoreV2
    let entries: [WorkoutEntry]
    let onOpen: (WorkoutEntry) -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Superset header
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.semibold))
                Text("SUPERSET")
                    .font(.caption2.weight(.bold))
                Spacer()
            }
            .foregroundStyle(DS.Theme.accent)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .padding(.horizontal, 12)

            // Connected exercises
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 0) {
                    // Connector line
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(index == 0 ? Color.clear : DS.Theme.accent.opacity(0.4))
                            .frame(width: 2)
                        Circle()
                            .fill(DS.Theme.accent)
                            .frame(width: 8, height: 8)
                        Rectangle()
                            .fill(index == entries.count - 1 ? Color.clear : DS.Theme.accent.opacity(0.4))
                            .frame(width: 2)
                    }
                    .frame(width: 16)

                    // Entry content
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.exerciseName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .lineLimit(2)

                        SetDataDisplay(sets: entry.sets, maxDisplay: 4, style: .compact)
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 8)

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        onRemove(entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DS.Semantic.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .onTapGesture { onOpen(entry) }
            }
        }
        .padding(.bottom, 10)
        .background(
            ChamferedRectangle(.medium)
                .fill(DS.Theme.accent.opacity(0.08))
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Superset Hero Card (Main focus card for superset)
private struct SupersetHeroCard: View {
    @EnvironmentObject var store: WorkoutStoreV2
    let group: LiveWorkoutOverlayCard.SupersetGroup
    let heroEntryID: UUID
    let stateForEntry: (WorkoutEntry) -> LiveWorkoutOverlayCard.ExerciseState
    let onOpen: (WorkoutEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.semibold))
                Text("SUPERSET")
                    .font(.caption2.weight(.bold))
                Spacer()
            }
            .foregroundStyle(DS.Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Exercise list
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    let isHero = entry.id == heroEntryID
                    let state = stateForEntry(entry)
                    let isCompleted = state == .finished

                    SupersetHeroRow(
                        entry: entry,
                        isHero: isHero,
                        isCompleted: isCompleted,
                        isFirst: index == 0,
                        isLast: index == group.entries.count - 1,
                        onOpen: { onOpen(entry) }
                    )
                }
            }
            .padding(.bottom, 12)
        }
        .background(
            ChamferedRectangle(.large)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    ChamferedRectangle(.large)
                        .stroke(DS.Theme.accent.opacity(0.4), lineWidth: 2)
                )
        )
    }
}

// MARK: - Superset Hero Row (Individual exercise in hero superset)
private struct SupersetHeroRow: View {
    let entry: WorkoutEntry
    let isHero: Bool
    let isCompleted: Bool
    let isFirst: Bool
    let isLast: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Connector
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : DS.Theme.accent.opacity(0.5))
                    .frame(width: 2, height: 12)

                Circle()
                    .fill(isCompleted ? DS.Theme.accent : DS.Theme.accent.opacity(0.3))
                    .frame(width: 10, height: 10)

                Rectangle()
                    .fill(isLast ? Color.clear : DS.Theme.accent.opacity(0.5))
                    .frame(width: 2)
            }
            .frame(width: 24)
            .padding(.leading, 16)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Status label for hero
                if isHero {
                    Text("CURRENT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DS.Theme.accent)
                }

                HStack(alignment: .top) {
                    Text(entry.exerciseName)
                        .font(isHero ? .headline.weight(.semibold) : .subheadline.weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .padding(.top, 2)
                }

                SetDataDisplay(sets: entry.sets, maxDisplay: 5, style: isHero ? .detailed : .compact)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(
            isHero
                ? RoundedRectangle(cornerRadius: 10)
                    .fill(DS.Theme.accent.opacity(0.1))
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

// MARK: - Exercise Group Section (Generic for all states) - Legacy, kept for compatibility
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
    @EnvironmentObject var store: WorkoutStoreV2
    let entry: WorkoutEntry
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(entry.exerciseName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    // Superset badge
                    if entry.isInSuperset {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                            Text("SS")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(DS.Theme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.Theme.accent.opacity(0.15), in: Capsule())
                    }
                }

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
        .contextMenu {
            Button(action: onOpen) {
                Label("Edit Exercise", systemImage: "pencil")
            }

            if entry.isInSuperset {
                Button {
                    store.removeFromSuperset(entryID: entry.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Remove from Superset", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Divider()

            Button(role: .destructive, action: onRemove) {
                Label("Remove Exercise", systemImage: "trash")
            }
        }
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
        let weight = set.weight.safeInt
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
