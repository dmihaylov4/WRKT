//
//  CutPlanHost.swift
//  WRKT
//
//  Feeds CutPlanView from what the legacy calendar already loads: the workout store's workouts
//  and runs, the planned workouts for the visible weeks, the plan library, the weekly goal and
//  the rewards streak. Same fetches, refresh triggers, sheets and destinations as
//  CalendarMonthView; only the presentation differs. Owned by PlanView inside its NavigationStack.
//

import SwiftUI
import SwiftData

struct CutPlanHost: View {
    let onProgramLibraryTap: () -> Void

    @Environment(\.dependencies) private var dependencies
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var repo: ExerciseRepository
    @Environment(\.modelContext) private var context

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now
    @State private var facts: [Date: CutPlanDayFacts] = [:]
    @State private var hasExistingPlans = false
    @State private var hasActivePlan = false
    @State private var dataChangeDebounce: Task<Void, Never>?

    // Weekly goal and streak, read on the same triggers as the legacy calendar.
    @State private var cachedWeeklyGoal: WeeklyGoal?
    @State private var weeklyGoalStreak = 0

    // Flows shared with the legacy calendar.
    @State private var showPlannerSetup = false
    @State private var showHealthKitAuthAlert = false
    @State private var showingWorkoutTypeSelector = false
    @State private var workoutStartDate: Date?
    @State private var exerciseBrowserConfig: CalendarMonthView.ExerciseBrowserConfig?
    @State private var plannedWorkoutEditorConfig: CalendarMonthView.PlannedWorkoutEditorConfig?
    @State private var retrospectiveWorkoutDate: Date?
    @State private var selectedCompletedWorkoutForDetail: CompletedWorkout?
    /// Actions raised inside the pushed day page (the legacy DayDetail).
    @State private var selectedAction: DayActionCard.DayAction?
    @State private var destination: Destination?

    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var tutorialState = TutorialState()

    enum Destination: Hashable {
        case day(Date)
        case week(Date)
        case appWorkout(UUID)
        case healthKitStrength(UUID)
        case cardio(UUID)
    }

    private var hasActiveWorkout: Bool { store.currentWorkout?.entries.isEmpty == false }

    var body: some View {
        CutPlanView(model: model, actions: actions) {
            CutPlanSyncProgress()
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if hasActiveWorkout { Color.clear.frame(height: 65) }
        }
        .onChange(of: selectedAction) { _, newValue in
            if let action = newValue {
                handleDayAction(action)
                selectedAction = nil
            }
        }
        .navigationDestination(item: $destination) { destination in
            destinationView(destination)
        }
        .navigationDestination(isPresented: $showPlannerSetup) {
            PlannerSetupCarouselView(launchMode: .create)
        }
        .sheet(isPresented: $showingWorkoutTypeSelector) {
            if let date = workoutStartDate {
                QuickWorkoutTypeSelector(date: date) { type in
                    handleWorkoutTypeSelection(type)
                }
            }
        }
        .fullScreenCover(item: $exerciseBrowserConfig) { config in
            FilteredExerciseBrowser(muscleFilter: config.muscleFilter, title: config.title)
        }
        .sheet(item: $plannedWorkoutEditorConfig) { config in
            PlannedWorkoutEditor(date: config.date, existingWorkout: config.existingWorkout)
                .environmentObject(repo)
                .environmentObject(store)
        }
        .sheet(item: Binding(
            get: { retrospectiveWorkoutDate.map { CalendarMonthView.RetrospectiveWrapper(date: $0) } },
            set: { retrospectiveWorkoutDate = $0?.date }
        )) { wrapper in
            RetrospectiveWorkoutBuilder(date: wrapper.date)
                .environmentObject(store)
                .environmentObject(repo)
        }
        .sheet(item: $selectedCompletedWorkoutForDetail) { workout in
            WorkoutDetailView(workout: workout)
        }
        .task {
            let didSync = await healthKit.autoSyncIfNeeded()
            if didSync {
                store.matchRecentWorkoutsWithHealthKit(days: 30)
            }
        }
        .onAppear(perform: handleOnAppear)
        .onReceive(NotificationCenter.default.publisher(for: .plannedWorkoutsChanged)) { _ in
            reloadFacts()
        }
        .onChange(of: monthAnchor) { _, _ in handleDataChange() }
        .onChange(of: store.completedWorkouts.count) { _, _ in scheduleDataUpdate() }
        .onChange(of: store.runs.count) { _, _ in scheduleDataUpdate() }
        .onChange(of: tutorialState.framesReady) { _, ready in
            if ready && !onboardingManager.hasSeenCalendar && !tutorialState.isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    tutorialState.isActive = true
                }
            }
        }
        .overlay { tutorialOverlay }
        .alert("Connect to Apple Health", isPresented: $showHealthKitAuthAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Try Again") {
                Task { try? await healthKit.requestAuthorization() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WRKT needs access to Apple Health to sync your Apple Watch workouts and show heart rate, calories, and workout duration.\n\nGo to Settings > Privacy & Security > Health > WRKT and enable Workouts.")
        }
    }

    // MARK: Model

    private var model: CutPlanModel {
        CutPlanLogic.model(monthAnchor: monthAnchor, selectedDay: selectedDay, today: .now,
                           facts: facts, hasActivePlan: hasActivePlan, calendar: .current)
    }

    // MARK: Actions

    private var actions: CutPlanActions {
        CutPlanActions(
            previousMonth: { bump(-1) },
            nextMonth: { bump(1) },
            goToToday: jumpToToday,
            selectDay: { selectedDay = $0 },
            editPlan: handlePlanHeaderAction,
            openWeek: { destination = .week(selectedDay) },
            perform: perform,
            refresh: handlePullToRefresh,
            reportFrame: { target, frame in
                switch target {
                case .editPlan: tutorialState.plannerButtonFrame = frame
                case .week: tutorialState.headerFrame = frame
                case .calendar: tutorialState.calendarGridFrame = frame
                case .day: tutorialState.dayDetailFrame = frame
                }
            }
        )
    }

    private func perform(_ action: CutPlanDayPanel.Action) {
        let day = selectedDay
        switch action {
        case .startPlanned(let id):
            if let planned = fetchPlannedWorkout(on: day), planned.id == id {
                handleDayAction(.startPlannedWorkout(planned))
            }
        case .startWorkout:
            handleDayAction(.startWorkout(day))
        case .viewWorkout(.app(let id)):
            destination = .appWorkout(id)
        case .viewWorkout(.healthKitStrength(let id)):
            destination = .healthKitStrength(id)
        case .viewWorkout(.cardio(let id)):
            destination = .cardio(id)
        case .viewDay:
            destination = .day(day)
        case .logWorkout:
            handleDayAction(.logWorkout(day))
        case .planWorkout:
            handleDayAction(.planWorkout(day))
        case .editPlanned(let id):
            if let planned = fetchPlannedWorkout(on: day), planned.id == id {
                handleDayAction(.editPlannedWorkout(planned))
            }
        }
    }

    /// The legacy calendar's day action handler.
    private func handleDayAction(_ action: DayActionCard.DayAction) {
        switch action {
        case .startWorkout(let date):
            workoutStartDate = date
            showingWorkoutTypeSelector = true
        case .startPlannedWorkout(let planned):
            store.startPlannedWorkout(planned)
            NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
        case .planWorkout(let date):
            plannedWorkoutEditorConfig = .init(date: date, existingWorkout: nil)
        case .editPlannedWorkout(let planned):
            plannedWorkoutEditorConfig = .init(date: planned.scheduledDate, existingWorkout: planned)
        case .logWorkout(let date):
            retrospectiveWorkoutDate = date
        case .viewCompletedWorkout(let id):
            selectedCompletedWorkoutForDetail = store.completedWorkouts.first { $0.id == id }
        }
    }

    private func handleWorkoutTypeSelection(_ type: QuickWorkoutTypeSelector.WorkoutType) {
        let config: CalendarMonthView.ExerciseBrowserConfig
        switch type {
        case .upperBody: config = .init(muscleFilter: .upperBody, title: "Upper Body")
        case .lowerBody: config = .init(muscleFilter: .lowerBody, title: "Lower Body")
        case .custom: config = .init(muscleFilter: nil, title: "All Exercises")
        }
        // Dismiss the type selector first, then show the browser (as the legacy calendar does).
        showingWorkoutTypeSelector = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exerciseBrowserConfig = config
        }
    }

    private func bump(_ delta: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = next
        if let first = calendar.dateInterval(of: .month, for: monthAnchor)?.start {
            selectedDay = first
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func jumpToToday() {
        monthAnchor = .now
        selectedDay = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Create a plan when none exists, else the program library.
    private func handlePlanHeaderAction() {
        refreshPlanLibraryState()
        switch PlanHeaderAction.primaryAction(hasExistingPlans: hasExistingPlans) {
        case .createPlan: showPlannerSetup = true
        case .openProgramLibrary: onProgramLibraryTap()
        }
    }

    // MARK: Destinations

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .day(let date):
            CutPlanDayPage(date: date, selectedAction: $selectedAction)
        case .week(let date):
            weekPage(for: date)
        case .appWorkout(let id):
            if let workout = store.completedWorkouts.first(where: { $0.id == id }) {
                WorkoutDetailView(workout: workout)
            }
        case .healthKitStrength(let id):
            if let run = store.runs.first(where: { $0.id == id }) {
                HealthKitStrengthDetailView(run: run)
            }
        case .cardio(let id):
            if let run = store.runs.first(where: { $0.id == id }) {
                CardioDetailView(run: run)
            }
        }
    }

    /// The legacy banners (goal streak, week progress, push/pull balance) for the week of `date`.
    private func weekPage(for date: Date) -> some View {
        let calendar = Calendar.current
        let goal = cachedWeeklyGoal
        let current = goal.map { store.currentWeekProgress(goal: $0, context: context) }
        let selected = goal.map {
            store.currentWeekProgress(goal: $0, context: context,
                                      now: calendar.startOfWeek(for: date, anchorWeekday: $0.anchorWeekday))
        }
        return CutPlanWeekPage(
            header: MonthHeader(
                monthAnchor: .constant(monthAnchor),
                canGoForward: true,
                onBack: {}, onForward: {}, onToday: {},
                hasExistingPlans: hasExistingPlans,
                onPlanAction: { _ in },
                weeklyStreak: weeklyGoalStreak,
                currentWeekProgress: current,
                selectedWeekProgress: selected,
                currentWeekFrozen: current.map { isFrozenWeek($0.weekStart) } ?? false,
                selectedWeekFrozen: selected.map { isFrozenWeek($0.weekStart) } ?? false
            ),
            hasContent: goal != nil || weeklyGoalStreak > 0
        )
    }

    private func isFrozenWeek(_ date: Date) -> Bool {
        guard let goal = cachedWeeklyGoal, let progress = RewardsEngine.shared.progress else { return false }
        let calendar = Calendar.current
        return CutPlanLogic.isFrozenWeek(
            weekStart: calendar.startOfWeek(for: date, anchorWeekday: goal.anchorWeekday),
            currentWeekStart: calendar.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday),
            protectedWeekStart: progress.weeklyFreezeProtectedWeekStart,
            streakFrozen: progress.weeklyStreakFrozen,
            calendar: calendar)
    }

    // MARK: Data

    private func handleOnAppear() {
        selectedDay = .now
        handleDataChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if tutorialState.framesReady && !onboardingManager.hasSeenCalendar && !tutorialState.isActive {
                tutorialState.isActive = true
            }
        }
    }

    private func handleDataChange() {
        cachedWeeklyGoal = try? context.fetch(FetchDescriptor<WeeklyGoal>(predicate: #Predicate { $0.isSet })).first
        weeklyGoalStreak = RewardsEngine.shared.weeklyGoalStreak()
        reloadFacts()
        refreshPlanLibraryState()
    }

    /// Debounced, so a workout and a run landing together recompute once.
    private func scheduleDataUpdate() {
        dataChangeDebounce?.cancel()
        dataChangeDebounce = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await MainActor.run { handleDataChange() }
        }
    }

    /// Planned workouts for the visible weeks (the legacy fetch) folded with the store's
    /// workouts and runs into one value per day.
    private func reloadFacts() {
        let calendar = Calendar.current
        let days = CutPlanLogic.gridDays(for: monthAnchor, calendar: calendar)
        guard let firstDay = days.first, let lastDay = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) else { return }
        let start = calendar.startOfDay(for: firstDay)
        let descriptor = FetchDescriptor(
            predicate: #Predicate<PlannedWorkout> { $0.scheduledDate >= start && $0.scheduledDate < end },
            sortBy: [SortDescriptor(\PlannedWorkout.scheduledDate)]
        )
        let planned: [PlannedWorkout]
        do {
            planned = try context.fetch(descriptor)
        } catch {
            AppLogger.error("Failed to fetch planned workouts: \(error)", category: AppLogger.app)
            planned = []
        }
        facts = CutPlanLogic.facts(
            days: days,
            workouts: store.completedWorkouts,
            runs: store.runs,
            planned: planned.map {
                ($0.scheduledDate, CutPlanDayFacts.Planned(id: $0.id, name: $0.splitDayName,
                                                           exerciseCount: $0.exercises.count, status: $0.workoutStatus))
            },
            ignoredHealthKitUUIDs: store.ignoredHealthKitUUIDs,
            calendar: calendar,
            workoutName: { workout in
                if let name = workout.workoutName, !name.isEmpty { return name }
                return MuscleGroupClassifier.classify(workout)
            },
            healthKitStrengthName: MuscleGroupClassifier.classifyHealthKitStrength
        )
    }

    /// The day's planned workout, fetched as the legacy day detail does.
    private func fetchPlannedWorkout(on date: Date) -> PlannedWorkout? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<PlannedWorkout> { $0.scheduledDate == startOfDay }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    private func refreshPlanLibraryState() {
        do {
            hasExistingPlans = try !dependencies.plannerStore.splitLibrary().isEmpty
        } catch {
            AppLogger.error("Failed to load plan library state", error: error, category: AppLogger.app)
            hasExistingPlans = true
        }
        hasActivePlan = ((try? dependencies.plannerStore.activeSplit()) ?? nil) != nil
    }

    /// The legacy pull-to-refresh: Health sync, then match recent workouts.
    private func handlePullToRefresh() async {
        AppLogger.info("Pull-to-refresh triggered - syncing HealthKit and matching workouts", category: AppLogger.health)
        if healthKit.needsAuthorization {
            do {
                try await healthKit.requestAuthorization()
            } catch {
                AppLogger.warning("HealthKit authorization request failed: \(error.localizedDescription)", category: AppLogger.health)
            }
        }
        await healthKit.syncRecentWorkouts()
        if healthKit.syncError != nil && healthKit.connectionState != .connected {
            await MainActor.run { showHealthKitAuthAlert = true }
            AppLogger.warning("HealthKit sync failed, showing authorization alert", category: AppLogger.health)
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            store.matchRecentWorkoutsWithHealthKit(days: 30)
            handleDataChange()
        }
        AppLogger.success("Pull-to-refresh completed", category: AppLogger.health)
    }

    // MARK: Tutorial

    @ViewBuilder
    private var tutorialOverlay: some View {
        if tutorialState.isActive {
            let steps = tutorialSteps
            SpotlightOverlay(
                currentStep: steps[min(tutorialState.currentStep, steps.count - 1)],
                currentIndex: tutorialState.currentStep,
                totalSteps: steps.count,
                onNext: advanceTutorial,
                onSkip: completeTutorial
            )
            .transition(.opacity)
            .zIndex(1000)
        }
    }

    /// The legacy calendar's four steps, pointed at the Cut controls.
    private var tutorialSteps: [TutorialStep] {
        func padded(_ frame: CGRect, _ amount: CGFloat) -> CGRect { frame.insetBy(dx: -amount, dy: -amount) }
        return [
            TutorialStep(
                title: "Split Planner",
                message: "Tap the pencil to create a workout split and schedule your training week. Plan your workouts in advance and track your progress!",
                spotlightFrame: padded(tutorialState.plannerButtonFrame, 6),
                tooltipPosition: .center,
                highlightCornerRadius: 30
            ),
            TutorialStep(
                title: "Streak Tracking",
                message: "Your weekly goal streak and the week's progress are behind the flame. Keep training consistently to build and maintain your streak!",
                spotlightFrame: padded(tutorialState.headerFrame, 6),
                tooltipPosition: .center,
                highlightCornerRadius: 30
            ),
            TutorialStep(
                title: "Activity Calendar",
                message: "Days with workouts carry a small mark: lime for strength, white for cardio, an outline for a planned session. Tap any day to see it below.",
                spotlightFrame: padded(tutorialState.calendarGridFrame, 8),
                tooltipPosition: .bottom,
                highlightCornerRadius: 20
            ),
            TutorialStep(
                title: "Day Details",
                message: "The selected day and what you can do with it. View day shows all its workouts and runs.",
                spotlightFrame: padded(tutorialState.dayDetailFrame, 8),
                tooltipPosition: .top,
                highlightCornerRadius: 16
            )
        ]
    }

    private func advanceTutorial() {
        if tutorialState.currentStep < tutorialSteps.count - 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                tutorialState.currentStep += 1
            }
        } else {
            completeTutorial()
        }
    }

    private func completeTutorial() {
        withAnimation(.easeOut(duration: 0.2)) {
            tutorialState.isActive = false
        }
        onboardingManager.complete(.calendar)
    }
}

// MARK: - Sync progress

/// The legacy Health sync progress, observed by this leaf only.
private struct CutPlanSyncProgress: View {
    @EnvironmentObject private var healthKit: HealthKitManager

    var body: some View {
        if healthKit.isSyncing {
            HealthKitSyncProgressView(healthKit: healthKit)
                .padding(.top, 12)
        }
    }
}

// MARK: - Pushed pages

/// "View day": the legacy day detail (summary, actions, planned session, workouts, cardio).
struct CutPlanDayPage: View {
    let date: Date
    @Binding var selectedAction: DayActionCard.DayAction?

    var body: some View {
        ScrollView {
            DayDetail(date: date, selectedAction: $selectedAction)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Weekly goal": the legacy streak, week progress and push/pull banners.
struct CutPlanWeekPage: View {
    let header: MonthHeader
    let hasContent: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !hasContent {
                    Text("No weekly goal set yet.")
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle("Weekly goal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
