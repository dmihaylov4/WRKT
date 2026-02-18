//  CalendarMonthView.swift (refactored)
//  WRKT
//
//  A brighter, streak-first calendar with a simple, workout-centric day detail.
//  Main calendar view coordination and state management.
//

import SwiftUI
import SwiftData
import Foundation
import OSLog
import Combine

// MARK: - Tutorial State
class TutorialState: ObservableObject {
    @Published var isActive = false
    @Published var currentStep = 0
    @Published var headerFrame: CGRect = .zero
    @Published var calendarGridFrame: CGRect = .zero
    @Published var dayDetailFrame: CGRect = .zero
    @Published var plannerButtonFrame: CGRect = .zero

    var framesReady: Bool {
        headerFrame != .zero && headerFrame.width > 0 &&
        calendarGridFrame != .zero && calendarGridFrame.width > 0 &&
        dayDetailFrame != .zero && dayDetailFrame.width > 0 &&
        plannerButtonFrame != .zero && plannerButtonFrame.width > 0
    }
}

// MARK: - Calendar View
struct CalendarMonthView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var repo: ExerciseRepository
    @Environment(\.modelContext) private var context

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now
    @State private var plannedWorkouts: [PlannedWorkout] = []
    @State private var selectedAction: DayActionCard.DayAction? = nil
    @State private var selectedWeekProgress: WeeklyProgress? = nil  // NEW: Track selected week stats
    @State private var showPlannerSetup = false  // NEW: For planner navigation
    @State private var showHealthKitAuthAlert = false  // HealthKit authorization prompt

    // Phase 2: Today's workout flow
    @State private var showingWorkoutTypeSelector = false
    @State private var workoutStartDate: Date? = nil
    @State private var exerciseBrowserConfig: ExerciseBrowserConfig? = nil

    struct ExerciseBrowserConfig: Identifiable {
        let id = UUID()
        let muscleFilter: MuscleFilter?
        let title: String
    }

    // Phase 3: Future day planning
    @State private var plannedWorkoutEditorConfig: PlannedWorkoutEditorConfig? = nil

    struct PlannedWorkoutEditorConfig: Identifiable {
        let id = UUID()
        let date: Date
        let existingWorkout: PlannedWorkout?
    }

    // Phase 4: Past day retrospective logging
    @State private var retrospectiveWorkoutDate: Date? = nil

    // Swipe gesture state
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    // Tutorial state (consolidated for better performance)
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var tutorialState = TutorialState()

    // 7 flexible day columns + 1 fixed-width streak column
    private static let gridColumns: [GridItem] = {
        var columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        columns.append(GridItem(.fixed(36), spacing: 6)) // Smaller fixed-width streak column
        return columns
    }()
    private let cellHeight: CGFloat = 44

    // Swipe gesture for month navigation
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Only process horizontal swipes
                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)

                // Require predominantly horizontal movement
                guard horizontalAmount > verticalAmount * 1.5 else { return }

                isDragging = true
                // Apply resistance - limit drag offset to 80 points max
                let maxOffset: CGFloat = 80
                dragOffset = max(-maxOffset, min(maxOffset, value.translation.width * 0.3))
            }
            .onEnded { value in
                let horizontalAmount = value.translation.width
                let verticalAmount = abs(value.translation.height)

                // Only trigger if predominantly horizontal and past threshold
                let threshold: CGFloat = 60
                let isHorizontalSwipe = abs(horizontalAmount) > abs(verticalAmount) * 1.5

                if isHorizontalSwipe && abs(horizontalAmount) > threshold {
                    // Swipe left = next month, swipe right = previous month
                    if horizontalAmount < 0 {
                        bump(1) // Next month
                    } else {
                        bump(-1) // Previous month
                    }
                }

                // Reset state
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dragOffset = 0
                    isDragging = false
                }
            }
    }

    // Convenience
    private var startOfCurrentMonth: Date {
        guard let interval = Calendar.current.dateInterval(of: .month, for: .now) else {
            // Fallback to first day of current month if dateInterval fails (should never happen)
            return Calendar.current.startOfDay(for: .now)
        }
        return interval.start
    }
    private var hasActiveWorkout: Bool { (store.currentWorkout?.entries.isEmpty == false) }

    // Grid dimensions - use cached days directly
    private var monthDays: [Date] {
        cachedMonthDays.isEmpty ? daysInMonth() : cachedMonthDays
    }
    private var gridRows: Int { max(1, monthDays.count / 7) }
    private var gridHeight: CGFloat { CGFloat(gridRows) * cellHeight + CGFloat((gridRows - 1)) * 6 }

    // Calendar grid view
    private var calendarGrid: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 6) {
            ForEach(0..<gridRows, id: \.self) { row in
                // 7 day cells for this week
                ForEach(0..<7) { col in
                    let index = row * 7 + col
                    if index < monthDays.count {
                        dayCellView(for: monthDays[index], row: row)
                    } else {
                        Color.clear.frame(height: cellHeight)
                    }
                }

                // 8th column: Week streak indicator
                weekIndicatorView(for: row)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(height: gridHeight)
        .offset(x: dragOffset)
        .opacity(isDragging ? 0.7 : 1.0)
        .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: dragOffset)
        .animation(.easeOut(duration: 0.2), value: isDragging)
        .gesture(monthSwipeGesture)
        .captureFrame(in: .global) { frame in
            tutorialState.calendarGridFrame = frame
        }
    }

    // Daily streak (legacy)
    private var streakLength: Int { max(store.streak(), 0) }
    private func hasActivity(on d: Date) -> Bool {
        !store.workouts(on: d).isEmpty || !store.runs(on: d).isEmpty
    }

    /// Update streak window once instead of recalculating for every day cell
    private func updateStreakWindow() {
        let length = streakLength
        guard length > 0 else {
            streakWindow = nil
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let windowStart = cal.date(byAdding: .day, value: -(length - 1), to: today) ?? today
        streakWindow = (start: windowStart, end: today)
    }

    private func isInActiveStreak(_ d: Date) -> Bool {
        guard let window = streakWindow else { return false }
        let startOfD = Calendar.current.startOfDay(for: d)
        return (startOfD >= window.start) && (startOfD <= window.end) && hasActivity(on: d)
    }

    // Weekly goal streak (cached to ensure view updates)
    @State private var weeklyGoalStreak: Int = 0

    private func updateWeeklyGoalStreakCache() {
        weeklyGoalStreak = RewardsEngine.shared.weeklyGoalStreak()
    }

    /// Get cached weekly goal (read-only during view updates)
    private func weeklyGoal() -> WeeklyGoal? {
        return cachedWeeklyGoal
    }

    /// Update the weekly goal cache (call from proper lifecycle methods)
    private func updateWeeklyGoalCache() {
        let fd = FetchDescriptor<WeeklyGoal>(predicate: #Predicate { $0.isSet })
        cachedWeeklyGoal = try? context.fetch(fd).first
    }

    // Cache week progress by week start date for efficient lookups
    // Pre-calculated in updateWeekProgressCache() to avoid state modification during rendering
    @State private var weekProgressCache: [Date: WeeklyProgress] = [:]

    // Cache day stats to avoid N-query problem (calculating stats for each day on every render)
    @State private var dayStatsCache: [Date: DayStat] = [:]

    // Optimized cache key using struct for better performance
    private struct CacheKey: Equatable {
        let monthTimestamp: TimeInterval
        let workoutCount: Int
        let runCount: Int
        let plannedCount: Int
    }
    @State private var cacheKey: CacheKey? = nil

    // Cache month days calculation
    @State private var cachedMonthDays: [Date] = []
    @State private var cachedMonthDaysAnchor: Date? = nil

    // Debounce state for data change handlers
    @State private var dataChangeDebounce: Task<Void, Never>? = nil

    // Pre-calculated streak window for performance
    @State private var streakWindow: (start: Date, end: Date)? = nil

    // Cached weekly goal to avoid repeated SwiftData queries
    @State private var cachedWeeklyGoal: WeeklyGoal? = nil

    /// Update cached month days when month changes
    private func updateMonthDaysCache() {
        cachedMonthDays = daysInMonth()
        cachedMonthDaysAnchor = monthAnchor
    }

    /// Pre-calculate week progress for all weeks visible in the current month
    /// This prevents state modification during view rendering
    private func updateWeekProgressCache() {
        guard let goal = weeklyGoal() else {
            weekProgressCache = [:]
            return
        }

        let cal = Calendar.current
        let days = daysInMonth()

        // Get unique week start dates for all visible days
        let weekStarts = Set(days.map { cal.startOfWeek(for: $0, anchorWeekday: goal.anchorWeekday) })

        // Pre-calculate progress for each week
        var newCache: [Date: WeeklyProgress] = [:]
        for weekStart in weekStarts {
            let progress = store.currentWeekProgress(goal: goal, context: context, now: weekStart)
            newCache[weekStart] = progress
        }

        weekProgressCache = newCache
    }

    private func progressForWeek(containing date: Date) -> WeeklyProgress? {
        guard let goal = weeklyGoal() else { return nil }
        let cal = Calendar.current
        let weekStart = cal.startOfWeek(for: date, anchorWeekday: goal.anchorWeekday)
        return weekProgressCache[weekStart]
    }

    private func isPartOfCompletedWeek(_ date: Date) -> Bool {
        guard let goal = weeklyGoal() else { return false }
        guard let progress = progressForWeek(containing: date) else { return false }

        // Check if this week met the goal (EITHER strength OR MVPA)
        let strengthGoalMet = progress.strengthDaysDone >= goal.targetStrengthDays
        let mvpaGoalMet = goal.targetActiveMinutes > 0 ? (progress.mvpaDone >= goal.targetActiveMinutes) : true
        return strengthGoalMet || mvpaGoalMet
    }

    private func isPartOfSuperWeek(_ date: Date) -> Bool {
        guard let goal = weeklyGoal() else { return false }
        guard let progress = progressForWeek(containing: date) else { return false }

        // Super week: BOTH goals met
        let strengthGoalMet = progress.strengthDaysDone >= goal.targetStrengthDays
        let mvpaGoalMet = goal.targetActiveMinutes > 0 ? (progress.mvpaDone >= goal.targetActiveMinutes) : true
        return strengthGoalMet && mvpaGoalMet
    }

    // Cached weekly progress to avoid recalculating for every day cell
    private var cachedWeeklyProgress: WeeklyProgress? {
        guard let goal = weeklyGoal() else { return nil }
        return store.currentWeekProgress(goal: goal, context: context)
    }

    private func currentWeekProgress() -> WeeklyProgress? {
        return cachedWeeklyProgress
    }

    private func isInCurrentWeek(_ date: Date) -> Bool {
        guard let goal = weeklyGoal() else { return false }
        let cal = Calendar.current
        let nowWeekStart = cal.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
        guard let nowWeekEnd = cal.date(byAdding: .day, value: 7, to: nowWeekStart) else { return false }
        let dateDay = cal.startOfDay(for: date)
        return dateDay >= nowWeekStart && dateDay < nowWeekEnd
    }

    // MARK: - Main Content View

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerView
                Spacer(minLength: 48)
                calendarGrid
                Spacer(minLength: 5)
                dividerView
                syncProgressView
                dayDetailView
            }
        }
        .refreshable {
            await handlePullToRefresh()
        }
    }

    /// Handle pull-to-refresh: sync HealthKit and match workouts
    private func handlePullToRefresh() async {
        AppLogger.info("Pull-to-refresh triggered - syncing HealthKit and matching workouts", category: AppLogger.health)

        // Always try to request authorization first if needed
        if healthKit.needsAuthorization {
            AppLogger.info("HealthKit needs authorization, requesting...", category: AppLogger.health)
            do {
                try await healthKit.requestAuthorization()
            } catch {
                AppLogger.warning("HealthKit authorization request failed: \(error.localizedDescription)", category: AppLogger.health)
            }
        }

        // 1. Sync recent workouts from HealthKit
        await healthKit.syncRecentWorkouts()

        // 2. Check if sync failed - show auth alert if still not connected
        if healthKit.syncError != nil && healthKit.connectionState != .connected {
            await MainActor.run {
                showHealthKitAuthAlert = true
            }
            AppLogger.warning("HealthKit sync failed, showing authorization alert", category: AppLogger.health)
            return
        }

        // 3. Small delay to allow UI to update
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 4. Match all recent app workouts with HealthKit data
        await MainActor.run {
            store.matchRecentWorkoutsWithHealthKit(days: 30)
            // Update caches after matching
            handleDataChange()
        }

        AppLogger.success("Pull-to-refresh completed", category: AppLogger.health)
    }

    private var headerView: some View {
        MonthHeader(
            monthAnchor: $monthAnchor,
            canGoForward: canGoForward,
            onBack: { bump(-1) },
            onForward: { bump(+1) },
            onToday: { jumpToToday() },
            onPlannerTap: { showPlannerSetup = true },
            weeklyStreak: weeklyGoalStreak,
            currentWeekProgress: currentWeekProgress(),
            selectedWeekProgress: selectedWeekProgress,
            captureButtonFrame: { frame in
                tutorialState.plannerButtonFrame = frame
            }
        )
        .padding(.top, 12)
        .captureFrame(in: .global) { frame in
            tutorialState.headerFrame = frame
        }
    }

    private var dividerView: some View {
        Divider()
            .overlay(DS.Semantic.border)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private var syncProgressView: some View {
        if healthKit.isSyncing {
            HealthKitSyncProgressView(healthKit: healthKit)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    private var dayDetailView: some View {
        DayDetail(date: selectedDay, selectedAction: $selectedAction)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .captureFrame(in: .global) { frame in
                tutorialState.dayDetailFrame = frame
            }
    }


    @ViewBuilder
    private var bottomInset: some View {
        if hasActiveWorkout {
            Color.clear.frame(height: 65)
        }
    }

    private func actionHandler(_ oldValue: DayActionCard.DayAction?, _ newValue: DayActionCard.DayAction?) {
        if let action = newValue {
            handleDayAction(action)
            selectedAction = nil
        }
    }

    var body: some View {
        contentWithModifiers
            .sheet(isPresented: $showingWorkoutTypeSelector) {
                workoutTypeSelectorSheet
            }
            .fullScreenCover(item: $exerciseBrowserConfig) { config in
                exerciseBrowserView(for: config)
            }
            .sheet(item: $plannedWorkoutEditorConfig) { config in
                plannedWorkoutEditorView(for: config)
            }
            .sheet(item: Binding(
                get: { retrospectiveWorkoutDate.map { RetrospectiveWrapper(date: $0) } },
                set: { retrospectiveWorkoutDate = $0?.date }
            )) { wrapper in
                RetrospectiveWorkoutBuilder(date: wrapper.date)
                    .environmentObject(store)
                    .environmentObject(repo)
            }
            .task {
                await handleAutoSync()
            }
            .onAppear {
                handleOnAppear()
            }
            .onReceive(NotificationCenter.default.publisher(for: .plannedWorkoutsChanged)) { _ in
                loadPlannedWorkouts()
                updateDayStatsCache()
            }
            .onChange(of: monthAnchor) { _, _ in
                handleMonthChange()
            }
            .onChange(of: store.completedWorkouts.count) { _, _ in
                scheduleDataUpdate()
            }
            .onChange(of: store.runs.count) { _, _ in
                scheduleDataUpdate()
            }
            .onChange(of: tutorialState.framesReady) { _, ready in
                if ready && !onboardingManager.hasSeenCalendar && !tutorialState.isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        tutorialState.isActive = true
                    }
                }
            }
            .overlay {
                tutorialOverlay
            }
            .alert("Connect to Apple Health", isPresented: $showHealthKitAuthAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Try Again") {
                    Task {
                        try? await healthKit.requestAuthorization()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("WRKT needs access to Apple Health to sync your Apple Watch workouts and show heart rate, calories, and workout duration.\n\nGo to Settings > Privacy & Security > Health > WRKT and enable Workouts.")
            }
    }

    struct RetrospectiveWrapper: Identifiable {
        let id = UUID()
        let date: Date
    }

    private var contentWithModifiers: some View {
        ZStack {
            mainContent
                .background(DS.Semantic.surface.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .tint(DS.Theme.accent)
                .safeAreaInset(edge: .bottom) { bottomInset }
                .onChange(of: selectedAction, actionHandler)

            // Hidden NavigationLink for planner setup
            NavigationLink(
                destination: PlannerSetupCarouselView(),
                isActive: $showPlannerSetup
            ) {
                EmptyView()
            }
            .hidden()
        }
    }

    @ViewBuilder
    private var workoutTypeSelectorSheet: some View {
        if let date = workoutStartDate {
            QuickWorkoutTypeSelector(date: date) { workoutType in
                handleWorkoutTypeSelection(workoutType, for: date)
            }
        }
    }

    private func exerciseBrowserView(for config: ExerciseBrowserConfig) -> some View {
        FilteredExerciseBrowser(
            muscleFilter: config.muscleFilter,
            title: config.title
        )
    }

    private func plannedWorkoutEditorView(for config: PlannedWorkoutEditorConfig) -> some View {
        PlannedWorkoutEditor(
            date: config.date,
            existingWorkout: config.existingWorkout
        )
        .environmentObject(repo)
        .environmentObject(store)
    }

    @ViewBuilder
    private var tutorialOverlay: some View {
        if tutorialState.isActive {
            SpotlightOverlay(
                currentStep: tutorialSteps[tutorialState.currentStep],
                currentIndex: tutorialState.currentStep,
                totalSteps: tutorialSteps.count,
                onNext: advanceTutorial,
                onSkip: skipTutorial
            )
            .transition(.opacity)
            .zIndex(1000)
        }
    }

    private func handleAutoSync() async {
        let didSync = await healthKit.autoSyncIfNeeded()
        if didSync {
            store.matchRecentWorkoutsWithHealthKit(days: 30)
        }
    }

    private func handleOnAppear() {
        // NOTE: Don't call validateWeeklyStreakOnAppear here - it recalculates and can
        // overwrite the correct stored value. Validation should only happen on cold start.
        // Just read the stored streak value instead.

        selectedDay = .now
        updateWeeklyGoalCache()
        updateWeeklyGoalStreakCache()  // Read current streak from RewardsEngine
        updateMonthDaysCache()
        loadPlannedWorkouts()
        updateWeekProgressCache()
        updateDayStatsCache()
        updateStreakWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if tutorialState.framesReady && !onboardingManager.hasSeenCalendar && !tutorialState.isActive {
                tutorialState.isActive = true
            }
        }
    }

    private func handleMonthChange() {
        updateWeeklyGoalCache()
        updateWeeklyGoalStreakCache()  // Sync streak with RewardsEngine
        updateMonthDaysCache()
        loadPlannedWorkouts()
        updateWeekProgressCache()
        updateDayStatsCache()
        updateStreakWindow()
    }

    private func handleDataChange() {
        updateWeeklyGoalCache()
        updateWeeklyGoalStreakCache()  // Sync streak with RewardsEngine
        updateDayStatsCache()
        updateWeekProgressCache()
        updateStreakWindow()
    }

    /// Debounced data update to prevent duplicate cache calculations when multiple data sources change simultaneously
    private func scheduleDataUpdate() {
        dataChangeDebounce?.cancel()
        dataChangeDebounce = Task {
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                handleDataChange()
            }
        }
    }

    // MARK: - Navigation helpers
    private var canGoForward: Bool {
        // Allow navigating to future months for planning
        return true
    }

    private func bump(_ delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = next
        if let first = cal.dateInterval(of: .month, for: monthAnchor)?.start {
            selectedDay = first
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func jumpToToday() {
        monthAnchor = .now
        selectedDay = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Data helpers
    private func daysInMonth() -> [Date] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: monthAnchor) else { return [] }
        var days: [Date] = []
        var d = interval.start

        // pad first row
        let wd = Calendar.current.component(.weekday, from: d) - Calendar.current.firstWeekday
        let pad = wd < 0 ? wd + 7 : wd
        for i in stride(from: pad, to: 0, by: -1) {
            if let prev = Calendar.current.date(byAdding: .day, value: -i, to: d) { days.append(prev) }
        }
        // month days
        while d < interval.end {
            days.append(d)
            d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d
        }
        // pad last row
        while days.count % 7 != 0 {
            guard let lastDay = days.last else {
                // Should never happen, but prevents crash if days array is unexpectedly empty
                break
            }
            days.append(lastDay.addingTimeInterval(86_400))
        }
        return days
    }

    /// Batch calculate stats for all visible days at once to avoid N-query problem
    /// This is much faster than calling store.runs(on:) and store.workouts(on:) for each day individually
    /// PERFORMANCE: Computation moved off main thread to prevent UI blocking
    private func updateDayStatsCache() {
        let days = daysInMonth()

        // Create a cache key based on relevant data to detect changes (using struct for better performance)
        let newKey = CacheKey(
            monthTimestamp: monthAnchor.timeIntervalSince1970,
            workoutCount: store.completedWorkouts.count,
            runCount: store.runs.count,
            plannedCount: plannedWorkouts.count
        )

        // Only recalculate if data has actually changed
        guard newKey != cacheKey else { return }
        cacheKey = newKey

        // Capture data needed for background computation
        let workouts = store.completedWorkouts
        let runs = store.runs
        let planned = plannedWorkouts
        let weekProgress = weekProgressCache
        let goal = weeklyGoal()
        let cal = Calendar.current

        // Move heavy computation to background task
        Task.detached(priority: .userInitiated) {
            // Pre-group workouts and runs by day for O(1) lookup instead of filtering for each day
            let workoutsByDay = Dictionary(grouping: workouts) { workout in
                cal.startOfDay(for: workout.date)
            }
            let runsByDay = Dictionary(grouping: runs) { run in
                cal.startOfDay(for: run.date)
            }

            // Pre-calculate week status for performance
            let nowWeekStart: Date?
            if let goal = goal {
                nowWeekStart = cal.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
            } else {
                nowWeekStart = nil
            }

            // Batch calculate all stats at once
            var newCache: [Date: DayStat] = [:]

            for day in days {
                let startOfDay = cal.startOfDay(for: day)
                let plannedWorkout = planned.first { cal.isDate($0.scheduledDate, inSameDayAs: startOfDay) }

                let dayWorkouts = workoutsByDay[startOfDay] ?? []
                let dayRuns = runsByDay[startOfDay] ?? []

                // Get matched HealthKit UUIDs to avoid counting duplicates
                let matchedHealthKitUUIDs = Set(dayWorkouts.compactMap { $0.matchedHealthKitUUID })

                // Separate strength workouts from cardio
                let strengthWorkouts = dayRuns.filter { run in
                    guard run.countsAsStrengthDay else { return false }
                    guard let uuid = run.healthKitUUID else { return false }
                    return !matchedHealthKitUUIDs.contains(uuid)
                }
                let cardioRuns = dayRuns.filter { !$0.countsAsStrengthDay }
                let cardioActivities = cardioRuns.map { CardioActivityType(from: $0.workoutType) }

                // Pre-calculate week status (optimization to avoid repeated calculations during rendering)
                var isCompletedWeek = false
                var isSuperWeek = false
                var isCurrentWeek = false

                if let goal = goal {
                    let weekStart = cal.startOfWeek(for: day, anchorWeekday: goal.anchorWeekday)

                    if let progress = weekProgress[weekStart] {
                        let strengthGoalMet = progress.strengthDaysDone >= goal.targetStrengthDays
                        let mvpaGoalMet = goal.targetActiveMinutes > 0 ? (progress.mvpaDone >= goal.targetActiveMinutes) : true
                        isCompletedWeek = strengthGoalMet || mvpaGoalMet
                        isSuperWeek = strengthGoalMet && mvpaGoalMet
                    }

                    if let nowStart = nowWeekStart {
                        if let nowEnd = cal.date(byAdding: .day, value: 7, to: nowStart) {
                            isCurrentWeek = startOfDay >= nowStart && startOfDay < nowEnd
                        }
                    }
                }

                newCache[startOfDay] = DayStat(
                    date: day,
                    workoutCount: dayWorkouts.count,
                    runCount: cardioRuns.count,
                    cardioActivities: cardioActivities,
                    healthKitStrengthWorkouts: strengthWorkouts,
                    plannedWorkout: plannedWorkout,
                    isPartOfCompletedWeek: isCompletedWeek,
                    isPartOfSuperWeek: isSuperWeek,
                    isInCurrentWeek: isCurrentWeek
                )
            }

            // Update cache on main thread
            await MainActor.run {
                self.dayStatsCache = newCache
            }
        }
    }

    /// Fast cache lookup instead of expensive filtering
    private func dayStat(for date: Date) -> DayStat {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return dayStatsCache[startOfDay] ?? DayStat(
            date: date,
            workoutCount: 0,
            runCount: 0,
            cardioActivities: [],
            healthKitStrengthWorkouts: [],
            plannedWorkout: nil,
            isPartOfCompletedWeek: false,
            isPartOfSuperWeek: false,
            isInCurrentWeek: false
        )
    }

    /// Load planned workouts for all visible days (including padding from adjacent months)
    private func loadPlannedWorkouts() {
        let visibleDays = daysInMonth()
        guard let firstDay = visibleDays.first,
              let lastDay = visibleDays.last else { return }

        let startOfFirstDay = Calendar.current.startOfDay(for: firstDay)
        let startOfLastDay = Calendar.current.startOfDay(for: lastDay)
        guard let endOfLastDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfLastDay) else { return }

        let predicate = #Predicate<PlannedWorkout> { planned in
            planned.scheduledDate >= startOfFirstDay && planned.scheduledDate < endOfLastDay
        }

        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\PlannedWorkout.scheduledDate)]
        )

        do {
            plannedWorkouts = try context.fetch(descriptor)
        } catch {
            AppLogger.error("Failed to fetch planned workouts: \(error)", category: AppLogger.app)
            plannedWorkouts = []
        }
    }

    // MARK: - Tutorial Logic

    /// Clamps a frame to stay within screen bounds with safe padding
    private func clampedFrame(_ frame: CGRect, insetBy insets: UIEdgeInsets) -> CGRect {
        let screenBounds = UIScreen.main.bounds
        let padding: CGFloat = 8 // Minimum padding from screen edges

        var expanded = CGRect(
            x: frame.origin.x - insets.left,
            y: frame.origin.y - insets.top,
            width: frame.width + insets.left + insets.right,
            height: frame.height + insets.top + insets.bottom
        )

        // Clamp to screen bounds with padding
        expanded.origin.x = max(padding, expanded.origin.x)
        expanded.origin.y = max(padding, expanded.origin.y)

        if expanded.maxX > screenBounds.width - padding {
            expanded.size.width = screenBounds.width - padding - expanded.origin.x
        }
        if expanded.maxY > screenBounds.height - padding {
            expanded.size.height = screenBounds.height - padding - expanded.origin.y
        }

        return expanded
    }

    private var tutorialSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Split Planner",
                message: "Tap here to create a workout split and schedule your training week. Plan your workouts in advance and track your progress!",
                spotlightFrame: {
                    var frame = clampedFrame(tutorialState.plannerButtonFrame, insetBy: UIEdgeInsets(top: 12, left: 1, bottom: 12, right: 25))
                    frame.origin.x -= 12  // Move whole container to the left by 8
                    frame.size.width += 15  // Increase width to compensate
                    return frame
                }(),
                tooltipPosition: .center,
                highlightCornerRadius: 12
            ),
            TutorialStep(
                title: "Streak Tracking",
                message: "Your current workout streak is shown at the top. Keep training consistently to build and maintain your streak!",
                spotlightFrame: clampedFrame(tutorialState.headerFrame, insetBy: UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)),
                tooltipPosition: .center,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Activity Calendar",
                message: "Days with workouts are highlighted. Yellow-bordered days are part of your active streak. Tap any day to view its details below.",
                spotlightFrame: clampedFrame(tutorialState.calendarGridFrame, insetBy: UIEdgeInsets(top: 45, left: 16, bottom: 16, right: 16)),
                tooltipPosition: .bottom,
                highlightCornerRadius: 20
            ),
            TutorialStep(
                title: "Day Details",
                message: "View all workouts and runs for the selected day. Tap any workout to see full details or edit it.",
                spotlightFrame: clampedFrame(tutorialState.dayDetailFrame, insetBy: UIEdgeInsets(top: 7, left: 16, bottom: 20, right: 20)),
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

    private func skipTutorial() {
        completeTutorial()
    }

    private func completeTutorial() {
        withAnimation(.easeOut(duration: 0.2)) {
            tutorialState.isActive = false
        }
        onboardingManager.complete(.calendar)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func dayCellView(for day: Date, row: Int) -> some View {
        let stats = dayStat(for: day)
        let inMonth = Calendar.current.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        DayCellV2(
            date: day,
            stats: stats,
            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
            inMonth: inMonth,
            inActiveStreak: isInActiveStreak(day),
            inCompletedWeek: stats.isPartOfCompletedWeek,
            inSuperWeek: stats.isPartOfSuperWeek,
            inCurrentWeek: stats.isInCurrentWeek,
            cellHeight: cellHeight,
            showWeekdayLabel: row == 0
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = day }
    }

    @ViewBuilder
    private func weekIndicatorView(for row: Int) -> some View {
        let weekStartIndex = row * 7
        if weekStartIndex < monthDays.count {
            let weekDay = monthDays[weekStartIndex]
            let stats = dayStat(for: weekDay)
            let weekProgress = progressForWeek(containing: weekDay)
            WeekStatusIndicator(
                isCompletedWeek: stats.isPartOfCompletedWeek,
                isSuperWeek: stats.isPartOfSuperWeek,
                isCurrentWeek: stats.isInCurrentWeek,
                onTap: {
                    // Show/hide stats for this week
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let current = selectedWeekProgress,
                           let selected = weekProgress,
                           Calendar.current.isDate(current.weekStart, inSameDayAs: selected.weekStart) {
                            selectedWeekProgress = nil
                        } else {
                            selectedWeekProgress = weekProgress
                        }
                    }
                }
            )
            .frame(height: cellHeight)
        } else {
            Color.clear.frame(height: cellHeight)
        }
    }

    // MARK: - Workout Type Selection

    private func handleWorkoutTypeSelection(_ type: QuickWorkoutTypeSelector.WorkoutType, for date: Date) {
        // Map workout type to muscle filter and create config
        let config: ExerciseBrowserConfig

        switch type {
        case .upperBody:
            config = ExerciseBrowserConfig(muscleFilter: .upperBody, title: "Upper Body")
        case .lowerBody:
            config = ExerciseBrowserConfig(muscleFilter: .lowerBody, title: "Lower Body")
        case .custom:
            config = ExerciseBrowserConfig(muscleFilter: nil, title: "All Exercises")
        }

        // Dismiss the type selector first, then show exercise browser
        // Small delay to avoid jarring sheet->fullScreen transition
        showingWorkoutTypeSelector = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.exerciseBrowserConfig = config
        }
    }

    // MARK: - Day Action Handler

    private func handleDayAction(_ action: DayActionCard.DayAction) {
        switch action {
        case .startWorkout(let date):
            workoutStartDate = date
            showingWorkoutTypeSelector = true

        case .planWorkout(let date):
            plannedWorkoutEditorConfig = PlannedWorkoutEditorConfig(date: date, existingWorkout: nil)

        case .editPlannedWorkout(let planned):
            plannedWorkoutEditorConfig = PlannedWorkoutEditorConfig(date: planned.scheduledDate, existingWorkout: planned)

        case .logWorkout(let date):
            retrospectiveWorkoutDate = date
        }
    }
}
