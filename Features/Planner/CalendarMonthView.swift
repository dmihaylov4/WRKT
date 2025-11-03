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

// MARK: - Calendar View
struct CalendarMonthView: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.modelContext) private var context

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date = .now
    @State private var plannedWorkouts: [PlannedWorkout] = []

    // Tutorial state
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showTutorial = false
    @State private var currentTutorialStep = 0
    @State private var headerFrame: CGRect = .zero
    @State private var calendarGridFrame: CGRect = .zero
    @State private var dayDetailFrame: CGRect = .zero
    @State private var plannerButtonFrame: CGRect = .zero
    @State private var framesReady = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let cellHeight: CGFloat = 44

    // Convenience
    private var startOfCurrentMonth: Date {
        guard let interval = Calendar.current.dateInterval(of: .month, for: .now) else {
            // Fallback to first day of current month if dateInterval fails (should never happen)
            return Calendar.current.startOfDay(for: .now)
        }
        return interval.start
    }
    private var hasActiveWorkout: Bool { (store.currentWorkout?.entries.isEmpty == false) }

    // Daily streak (legacy)
    private var streakLength: Int { max(store.streak(), 0) }
    private func hasActivity(on d: Date) -> Bool {
        !store.workouts(on: d).isEmpty || !store.runs(on: d).isEmpty
    }
    private func isInActiveStreak(_ d: Date) -> Bool {
        guard streakLength > 0 else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -(streakLength - 1), to: today) else { return false }
        let startOfD = cal.startOfDay(for: d)
        let inWindow = (startOfD >= windowStart) && (startOfD <= today)
        return inWindow && hasActivity(on: d)
    }

    // Weekly goal streak
    private var weeklyGoalStreak: Int {
        RewardsEngine.shared.weeklyGoalStreak()
    }

    private func weeklyGoal() -> WeeklyGoal? {
        let fd = FetchDescriptor<WeeklyGoal>(predicate: #Predicate { $0.isSet })
        return try? context.fetch(fd).first
    }

    // Cache week progress by week start date for efficient lookups
    // Pre-calculated in updateWeekProgressCache() to avoid state modification during rendering
    @State private var weekProgressCache: [Date: WeeklyProgress] = [:]

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

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Header
                MonthHeader(
                    monthAnchor: $monthAnchor,
                    canGoForward: canGoForward,
                    onBack: { bump(-1) },
                    onForward: { bump(+1) },
                    onToday: { jumpToToday() },
                    weeklyStreak: weeklyGoalStreak,
                    currentWeekProgress: currentWeekProgress()
                )
                .padding(.top, 12)
                .captureFrame(in: .global) { frame in
                    headerFrame = frame
                    checkFramesReady()
                }

                // Weekday labels
                //WeekdayRow().padding(.horizontal, 16)
                Spacer(minLength: 32)
                // Month grid
                let days = daysInMonth()
                let rows = max(1, days.count / 7)
                let gridHeight = CGFloat(rows) * cellHeight + CGFloat((rows - 1)) * 6

                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(days, id: \.self) { day in
                        let stats = dayStat(for: day)
                        let inMonth = Calendar.current.isDate(day, equalTo: monthAnchor, toGranularity: .month)
                        DayCellV2(
                            date: day,
                            stats: stats,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                            inMonth: inMonth,
                            inActiveStreak: isInActiveStreak(day),
                            inCompletedWeek: isPartOfCompletedWeek(day),
                            inSuperWeek: isPartOfSuperWeek(day),
                            inCurrentWeek: isInCurrentWeek(day),
                            cellHeight: cellHeight
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDay = day }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24) // Increased from 16 to prevent chip overlap with divider
                .frame(height: gridHeight)
                .captureFrame(in: .global) { frame in
                    calendarGridFrame = frame
                    checkFramesReady()
                }
                Spacer(minLength: 5)
                Divider()
                    .overlay(DS.Semantic.border)
                    .padding(.top, 12) // Increased from 8 for more spacing
                    .padding(.bottom, 16)

                // MARK: - Sync Progress
                if healthKit.isSyncing {
                    HealthKitSyncProgressView(healthKit: healthKit)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // Day detail — simplified & workout-centric
                DayDetail(date: selectedDay)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .captureFrame(in: .global) { frame in
                        dayDetailFrame = frame
                        checkFramesReady()
                    }
            }
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .tint(DS.Theme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PlannerSetupCarouselView()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Theme.accent)
                }
                .captureFrame(in: .global) { frame in
                    plannerButtonFrame = frame
                    checkFramesReady()
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if hasActiveWorkout { Color.clear.frame(height: 65) } }
        .task {
            // Auto-sync when calendar appears (throttled to max once per 5 min)
            let didSync = await healthKit.autoSyncIfNeeded()
            if didSync {
                // If we synced new data, try matching workouts
                store.matchAllWorkoutsWithHealthKit()
            }
        }
        .onAppear {
            // Reset to today when view appears
            selectedDay = .now
            loadPlannedWorkouts()
            updateWeekProgressCache()

            // Fallback: if frames haven't loaded after 2.5 seconds, show tutorial anyway
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if !framesReady && !onboardingManager.hasSeenCalendar && !showTutorial {
                    showTutorial = true
                }
            }
        }
        .onChange(of: monthAnchor) { _, _ in
            // Reload planned workouts when month changes
            loadPlannedWorkouts()
            // Recalculate week progress cache when month changes
            updateWeekProgressCache()
        }
        .onChange(of: framesReady) { _, ready in
            // Show tutorial once frames are captured
            if ready && !onboardingManager.hasSeenCalendar && !showTutorial {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showTutorial = true
                }
            }
        }
        .overlay {
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

    private func dayStat(for date: Date) -> DayStat {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let planned = plannedWorkouts.first { Calendar.current.isDate($0.scheduledDate, inSameDayAs: startOfDay) }

        // Get all HealthKit activities for this day
        let runs = store.runs(on: date)

        // Get matched HealthKit UUIDs from app workouts (to avoid counting duplicates)
        let workouts = store.workouts(on: date)
        let matchedHealthKitUUIDs = Set(workouts.compactMap { $0.matchedHealthKitUUID })

        // Separate strength workouts from cardio
        // Exclude strength workouts that are already matched to app workouts
        let strengthWorkouts = runs.filter { run in
            guard run.countsAsStrengthDay else { return false }
            guard let uuid = run.healthKitUUID else { return false }
            return !matchedHealthKitUUIDs.contains(uuid)
        }
        let cardioRuns = runs.filter { !$0.countsAsStrengthDay }

        // Get cardio activity types (excluding strength)
        let cardioActivities = cardioRuns.map { CardioActivityType(from: $0.workoutType) }

        return DayStat(
            date: date,
            workoutCount: workouts.count,
            runCount: cardioRuns.count, // Only cardio runs
            cardioActivities: cardioActivities,
            healthKitStrengthWorkouts: strengthWorkouts, // Only unmatched Apple Watch strength workouts
            plannedWorkout: planned
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

    private func checkFramesReady() {
        // Check if all frames have been captured and are valid
        let headerReady = headerFrame != .zero && headerFrame.width > 0
        let gridReady = calendarGridFrame != .zero && calendarGridFrame.width > 0
        let detailReady = dayDetailFrame != .zero && dayDetailFrame.width > 0
        let plannerReady = plannerButtonFrame != .zero && plannerButtonFrame.width > 0

        if headerReady && gridReady && detailReady && plannerReady && !framesReady {

            framesReady = true
        }
    }

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
                    var frame = clampedFrame(plannerButtonFrame, insetBy: UIEdgeInsets(top: 12, left: 1, bottom: 12, right: 25))
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
                spotlightFrame: clampedFrame(headerFrame, insetBy: UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)),
                tooltipPosition: .center,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Activity Calendar",
                message: "Days with workouts are highlighted. Yellow-bordered days are part of your active streak. Tap any day to view its details below.",
                spotlightFrame: clampedFrame(calendarGridFrame, insetBy: UIEdgeInsets(top: 45, left: 16, bottom: 16, right: 16)),
                tooltipPosition: .bottom,
                highlightCornerRadius: 20
            ),
            TutorialStep(
                title: "Day Details",
                message: "View all workouts and runs for the selected day. Tap any workout to see full details or edit it.",
                spotlightFrame: clampedFrame(dayDetailFrame, insetBy: UIEdgeInsets(top: 7, left: 16, bottom: 20, right: 20)),
                tooltipPosition: .top,
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
        onboardingManager.complete(.calendar)
    }
}
