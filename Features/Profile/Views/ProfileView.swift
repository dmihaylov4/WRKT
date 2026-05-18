//
//  ProfileView.swift
//  WRKT
//

import SwiftUI
import SwiftData




struct ProfileView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var authService: SupabaseAuthService
    @Query private var progress: [RewardProgress]
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @Query private var stamps: [DexStamp]
    @Query private var goals: [WeeklyGoal]
    @Query private var thisWeek: [WeeklyTrainingSummary]

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context

    // Badge manager for social notifications
    @State private var badgeManager = NotificationBadgeManager.shared

    // Tutorial state
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showTutorial = false
    @State private var currentTutorialStep = 0
    @State private var levelCardFrame: CGRect = .zero
    @State private var graphsFrame: CGRect = .zero
    @State private var dexFrame: CGRect = .zero
    @State private var milestonesFrame: CGRect = .zero
    @State private var framesReady = false
    @State private var showSettings = false
    @State private var viewModel = ProfileScreenViewModel()
    @State private var planAdherenceData: [PlanAdherence] = []

    init() {
        // compute weekStart once for this view’s init
        let cal = Calendar.current
        let anchor = 2 // Monday; if you want it dynamic, you can read from UserDefaults
        let ws = cal.startOfWeek(for: .now, anchorWeekday: anchor)
        _thisWeek = Query(
            filter: #Predicate<WeeklyTrainingSummary> { $0.weekStart == ws },
            sort: \WeeklyTrainingSummary.weekStart,
            order: .forward
        )
        _goals = Query(filter: #Predicate<WeeklyGoal> { $0.isSet == true })
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // UNIFIED PROGRESS OVERVIEW
                if let p = progress.first {
                    Section {
                        progressOverview(for: p)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .id("levelCard")
                } else {
                    Section {
                        ContentUnavailableView("No profile yet",
                                               systemImage: "person.crop.circle.badge.questionmark",
                                               description: Text("Start a workout to earn XP and level up."))
                    }
                }

                if planAdherenceData.contains(where: { $0.plannedSessions > 0 }) {
                    Section {
                        PlanAdherenceCard(
                            weeklyAdherence: planAdherenceData,
                            currentWeekEnded: isCurrentWeekEnded
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    VStack(spacing: 16) {
                        ProfileStatsView()
                        TrainingBalanceSection(weeks: 12)
                    }
                    .captureFrame(in: .global) { frame in
                        graphsFrame = frame
                        checkFramesReady()
                    }
                    .id(viewModel.statsRefreshTrigger) // Force refresh when this changes
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .id("graphs")

                Section {
                    VStack(spacing: 10) {
                        ForEach(ProfileCollectionDestination.allCases) { destination in
                            NavigationLink {
                                collectionDestinationView(for: destination)
                            } label: {
                                ProfileCollectionDestinationButton(destination: destination)
                            }
                            .buttonStyle(.plain)
                            .captureFrame(in: .global) { frame in
                                switch destination {
                                case .prCollection:
                                    dexFrame = frame
                                case .milestones:
                                    milestonesFrame = frame
                                }
                                checkFramesReady()
                            }
                            .id(destination.scrollID)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .id("profileCollections")

                // Bottom spacer for custom tab bar (UITabBar.isHidden breaks safe area propagation)
                Section {
                    Color.clear.frame(height: 56)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(0)
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(authService)
            }
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: currentTutorialStep) { _, newStep in
                // Auto-scroll to the highlighted section when tutorial step changes
                scrollToStep(newStep, proxy: proxy)
            }
            .onChange(of: showTutorial) { _, isShowing in
                // Scroll to current step when tutorial appears (but not for step 0)
                if isShowing && currentTutorialStep > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToStep(currentTutorialStep, proxy: proxy)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .background(DS.Semantic.surface.ignoresSafeArea(edges: .top))
        }
        .task {
            await viewModel.loadExercises(using: repo)
            viewModel.rebuildDexPreview(stamps: stamps)

            // Refresh friend request badges
            await badgeManager.refreshBadges()
        }
        .onChange(of: stamps) { _ in
            viewModel.rebuildDexPreview(stamps: stamps)
        }
        .onChange(of: repo.exercises) { _ in
            Task {
                await viewModel.loadExercises(using: repo)
                viewModel.rebuildDexPreview(stamps: stamps)
            }
        }
        .onChange(of: store.completedWorkouts.count) { _, newCount in
            viewModel.updateWeekProgress(goals: goals, store: store, context: context)

            if newCount > 0 {
                viewModel.refreshStats(store: store)
            }
        }
        .onChange(of: achievements) { _, _ in
            viewModel.updateMilestones(achievements: achievements)
        }
        .onAppear {
            viewModel.updateWeekProgress(goals: goals, store: store, context: context)
            viewModel.updateMilestones(achievements: achievements)
            viewModel.refreshStats(store: store)
            loadAdherence()

            // Fallback: if frames haven't loaded after 1 second, show tutorial anyway
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !framesReady && !onboardingManager.hasSeenProfileStats && !showTutorial {
                    showTutorial = true
                }
            }
        }
        .onChange(of: framesReady) { _, ready in
            // Show tutorial once frames are captured (reduced delay)
            if ready && !onboardingManager.hasSeenProfileStats && !showTutorial {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

    private var isCurrentWeekEnded: Bool {
        let cal = Calendar.current
        let anchor = goals.first?.anchorWeekday ?? 2
        let weekStart = cal.startOfWeek(for: .now, anchorWeekday: anchor)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return Date() >= weekEnd
    }

    private func loadAdherence() {
        let cal = Calendar.current
        let anchor = goals.first?.anchorWeekday ?? 2
        let currentWeekStart = cal.startOfWeek(for: .now, anchorWeekday: anchor)
        let weekStarts = (0..<4).compactMap { offset in
            cal.date(byAdding: .day, value: -7 * (3 - offset), to: currentWeekStart)
        }
        planAdherenceData = PlannerStore.shared.adherence(forWeeks: weekStarts)
    }

    @ViewBuilder
    private func progressOverview(for progress: RewardProgress) -> some View {
        if let goal = goals.first, goal.isSet {
            // Use cached week progress instead of recalculating
            ProgressOverviewCard(
                level: progress.level,
                xp: progress.xp,
                prevXP: progress.prevLevelXP,
                nextXP: progress.nextLevelXP,
                streak: progress.currentStreak,
                longest: progress.longestStreak,
                progress: progress,
                weekProgress: viewModel.cachedWeekProgress,
                goal: goal,
                onSettingsTapped: openSettings
            )
            .task {
                await viewModel.syncHealthKitIfNeeded(store: store, context: context, goals: goals)
            }
            .captureFrame(in: .global, onChange: updateLevelCardFrame)
        } else {
            ProgressOverviewCard(
                level: progress.level,
                xp: progress.xp,
                prevXP: progress.prevLevelXP,
                nextXP: progress.nextLevelXP,
                streak: progress.currentStreak,
                longest: progress.longestStreak,
                progress: progress,
                weekProgress: nil,
                goal: nil,
                onSettingsTapped: openSettings
            )
            .captureFrame(in: .global, onChange: updateLevelCardFrame)
        }
    }

    private func openSettings() {
        showSettings = true
    }

    private func updateLevelCardFrame(_ frame: CGRect) {
        levelCardFrame = frame
        checkFramesReady()
    }

    @ViewBuilder
    private func collectionDestinationView(for destination: ProfileCollectionDestination) -> some View {
        switch destination {
        case .prCollection:
            AchievementsDexView()
        case .milestones:
            AchievementsView()
        }
    }

    // MARK: - Tutorial Logic

    private func checkFramesReady() {
        // Check if all frames have been captured and are valid (with minimum size threshold)
        let minSize: CGFloat = 50 // Minimum frame dimension to be considered valid

        let levelReady = levelCardFrame != .zero && levelCardFrame.width > minSize && levelCardFrame.height > minSize
        let graphsReady = graphsFrame != .zero && graphsFrame.width > minSize && graphsFrame.height > minSize
        let dexReady = dexFrame != .zero && dexFrame.width > minSize && dexFrame.height > minSize
        let milestonesReady = milestonesFrame != .zero && milestonesFrame.width > minSize && milestonesFrame.height > minSize

        if levelReady && graphsReady && dexReady && milestonesReady && !framesReady {
            // Add a small delay to ensure frames are stable before showing tutorial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                framesReady = true
            }
        }
    }

    private func scrollToStep(_ step: Int, proxy: ScrollViewProxy) {
        // Map tutorial steps to section IDs
        let sectionIDs: [String] = ["levelCard", "graphs", "dex"]

        guard step < sectionIDs.count else { return }

        let sectionID = sectionIDs[step]

        // Custom anchor for scrollable tutorial sections: slightly above center
        let higherAnchor = UnitPoint(x: 0.5, y: 0.35)

        // Determine if we need to scroll based on step
        // Step 0 (Level Card) - no scroll needed (top of screen)
        // Step 1 (Training Trends) - check if visible, scroll to top if needed
        // Step 2 (PR Collection) - always scroll to higher position

        if step == 0 {
            // No scroll for first step (already at top)
            return
        } else if step == 1 {
            // Check if Training Trends is visible
            let screenBounds = UIScreen.main.bounds
            let isVisible = graphsFrame.minY >= 0 && graphsFrame.maxY <= screenBounds.height

            if !isVisible {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(sectionID, anchor: .top)
                }
            }
        } else {
            // Always scroll for PR Collection to ensure it's rendered
            // Use higher anchor (35% from top) for better visibility
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(sectionID, anchor: higherAnchor)
            }
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
        var steps: [TutorialStep] = [
            TutorialStep(
                title: "Level & Progress",
                message: "Track your level, XP, and workout streak. Set weekly goals to stay on track with your fitness journey!",
                spotlightFrame: clampedFrame(levelCardFrame, insetBy: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)),
                tooltipPosition: .bottom,
                highlightCornerRadius: 20
            ),
            TutorialStep(
                title: "Training Trends",
                message: "View your training trends and muscle group balance. These graphs help you optimize your workout distribution.",
                spotlightFrame: {
                    var frame = clampedFrame(graphsFrame, insetBy: UIEdgeInsets(top: 345, left: 16, bottom: 16, right: 16))
                    frame.origin.y += 5  // Move upper border down by 5
                    return frame
                }(),
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "PR Collection",
                message: "Unlock personal records by achieving new max weights for each exercise. Build your collection!",
                spotlightFrame: clampedFrame(
                    dexFrame,
                    insetBy: UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
                ),
                tooltipPosition: .top,
                highlightCornerRadius: 16
            ),
        ]

        return steps
    }

    private func advanceTutorial() {
        if currentTutorialStep < tutorialSteps.count - 1 {
            // Hide spotlight temporarily
            showTutorial = false

            // Advance to next step
            currentTutorialStep += 1

            // Different delays based on which step we're moving to
            // Step 1 (Training Trends) - shorter delay since it's already visible
            // Step 2 (PR Collection) - longer delay for scroll and render
            let delay: Double = (currentTutorialStep == 1) ? 0.15 : 0.5

            // Wait for scroll and frame updates, then show spotlight
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showTutorial = true
                }
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
        onboardingManager.complete(.profileStats)
    }
}

// MARK: - Unified Progress Overview Card

private struct ProfileCollectionDestinationButton: View {
    let destination: ProfileCollectionDestination

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ChamferedRectangle(.medium)
                    .fill(DS.Semantic.brand.opacity(0.16))

                Image(systemName: destination.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(destination.titleLocalizationKey))
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(LocalizedStringKey(destination.subtitleLocalizationKey))
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .contentShape(ChamferedRectangle(.large))
        .accessibilityIdentifier(destination.accessibilityIdentifier)
    }
}

struct ProgressOverviewCard: View {
    let level: Int
    let xp: Int
    let prevXP: Int
    let nextXP: Int
    let streak: Int
    let longest: Int
    let progress: RewardProgress
    let weekProgress: WeeklyProgress?
    let goal: WeeklyGoal?
    var onSettingsTapped: (() -> Void)? = nil

    @Environment(\.modelContext) private var context

    private var xpFrac: Double {
        let cur = effectivePrev
        let nxt = max(nextXP, cur + 1)
        let num = max(0, xp - cur)
        let den = max(1, nxt - cur)
        return min(Double(num) / Double(den), 1.0)
    }

    private var xpText: String {
        let cur = effectivePrev
        let nxt = max(nextXP, cur + 1)
        let num = max(0, xp - cur)
        let den = max(1, nxt - cur)
        return "\(num) / \(den) XP"
    }

    private func delta(_ level: Int) -> Int { 100 + 50 * max(0, level - 1) }

    private var effectivePrev: Int {
        max(prevXP, nextXP - delta(level))
    }

    private var currentStreakValue: Int {
        goal != nil ? progress.weeklyGoalStreakCurrent : streak
    }

    private var streakStatusText: String {
        let current = progress.weeklyGoalStreakCurrent
        if current == 0 { return "Start your streak!" }
        if progress.weeklyStreakFrozen { return "Freeze active" }
        if let wp = weekProgress {
            if wp.guidelineComplete { return "Super week complete!" }
            let strengthMet = wp.strengthDaysDone >= wp.strengthTarget
            let mvpaMet = wp.mvpaTarget > 0 ? (wp.mvpaDone >= wp.mvpaTarget) : true
            if strengthMet { return "Finish active minutes for super streak" }
            if mvpaMet { return "Finish strength days for super streak" }
        }
        return "Complete this week to continue"
    }

    private var levelHeader: some View {
        HStack {
            Text("Level \(level)")
                .dsFont(.title2, weight: .bold)
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 8) {
                streakChip
                settingsButton
            }
        }
    }

    private var streakChip: some View {
        VStack(spacing: 2) {
            Label {
                Text("\(currentStreakValue)")
                    .dsFont(.subheadline, weight: .semibold)
            } icon: {
                Image("streak-icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(currentStreakValue > 0 ? DS.Theme.accent : .white.opacity(0.50))
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let onSettingsTapped {
            Button(action: onSettingsTapped) {
                Image("settings-wheel-icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.15), in: ChamferedRectangle(.small))
                    .overlay(
                        ChamferedRectangle(.small)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Level & XP Section
            VStack(alignment: .leading, spacing: 8) {
                levelHeader

                // XP Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [DS.Theme.accent, DS.Theme.accent.opacity(0.7)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, geo.size.width * xpFrac))
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(xpText)
                        .dsFont(.caption, monospacedDigits: true)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text({
                        if let goal = goal {
                            let weeks = progress.weeklyGoalStreakLongest
                            return "Longest: \(weeks) week\(weeks == 1 ? "" : "s")"
                        } else {
                            return "Longest: \(longest) day\(longest == 1 ? "" : "s")"
                        }
                    }())
                        .dsFont(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Streak Freeze Button
            StreakFreezeButton(progress: progress, hasWeeklyGoal: goal != nil)

            // Weekly Goals Section (if set)
            if let weekProgress = weekProgress, let goal = goal {
                Divider()
                    .background(.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink {
                        WeeklyGoalDetailView(progress: weekProgress, goal: goal)
                    } label: {
                        Text("Weekly Goals")
                            .dsFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 16) {
                        // MVPA Progress
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.run")
                                    .dsFont(.caption)
                                Text("Active Minutes")
                                    .dsFont(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.7))

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(weekProgress.mvpaDone)")
                                    .dsFont(.title3, weight: .semibold)
                                Text("/ \(weekProgress.mvpaTarget)")
                                    .dsFont(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .foregroundStyle(.white)

                            ProgressView(value: min(Double(weekProgress.mvpaDone), Double(weekProgress.mvpaTarget)), total: Double(max(weekProgress.mvpaTarget, 1)))
                                .tint(DS.Theme.accent)
                                .scaleEffect(y: 0.8)
                        }

                        Divider()
                            .frame(height: 50)

                        // Strength Days Progress
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "dumbbell.fill")
                                    .dsFont(.caption)
                                Text("Strength Days")
                                    .dsFont(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.7))

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(weekProgress.strengthDaysDone)")
                                    .dsFont(.title3, weight: .semibold)
                                Text("/ \(weekProgress.strengthTarget)")
                                    .dsFont(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .foregroundStyle(.white)

                            ProgressView(value: min(Double(weekProgress.strengthDaysDone), Double(weekProgress.strengthTarget)), total: Double(max(weekProgress.strengthTarget, 1)))
                                .tint(DS.Theme.accent)
                                .scaleEffect(y: 0.8)
                        }
                    }

                    Divider()
                        .background(.white.opacity(0.12))

                    // Weekly Goal Streak
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly Goal Streak")
                            .dsFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.white)
                        Text(streakStatusText)
                            .dsFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("Current")
                                .dsFont(.caption, weight: .semibold)
                                .foregroundStyle(.white.opacity(0.8))
                                .textCase(.uppercase)
                            Text("\(progress.weeklyGoalStreakCurrent)")
                                .font(DS.Typography.custom(size: 32, weight: .bold))
                                .foregroundStyle(DS.Theme.accent)
                            Text("week\(progress.weeklyGoalStreakCurrent == 1 ? "" : "s")")
                                .dsFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(width: 1, height: 60)

                        VStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DS.Theme.accent)
                                Text("Super")
                                    .dsFont(.caption, weight: .semibold)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .textCase(.uppercase)
                            }
                            Text("\(RewardsEngine.shared.progress?.weeklySuperStreakCurrent ?? 0)")
                                .font(DS.Typography.custom(size: 28, weight: .bold))
                                .foregroundStyle(DS.Theme.accent)
                            Text("week\(RewardsEngine.shared.progress?.weeklySuperStreakCurrent ?? 0 == 1 ? "" : "s")")
                                .dsFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(width: 1, height: 60)

                        VStack(spacing: 4) {
                            Text("Longest")
                                .dsFont(.caption, weight: .semibold)
                                .foregroundStyle(.white.opacity(0.8))
                                .textCase(.uppercase)
                            Text("\(progress.weeklyGoalStreakLongest)")
                                .font(DS.Typography.custom(size: 28, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("week\(progress.weeklyGoalStreakLongest == 1 ? "" : "s")")
                                .dsFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if progress.weeklyGoalStreakCurrent > 0 {
                        let current = progress.weeklyGoalStreakCurrent
                        let nextMilestone = [2, 4, 8, 12, 26, 52].first { $0 > current } ?? 52
                        let milestonePct = Double(current) / Double(nextMilestone)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Next milestone: \(nextMilestone) weeks")
                                    .dsFont(.caption, weight: .medium)
                                Spacer()
                                Text("\(current)/\(nextMilestone)")
                                    .dsFont(.caption, monospacedDigits: true)
                                    .foregroundStyle(.secondary)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.15))
                                    Capsule()
                                        .fill(DS.Theme.accent)
                                        .frame(width: max(8, geo.size.width * milestonePct))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            } else {
                // No weekly goal set - show setup prompt
                Divider()
                    .background(.white.opacity(0.12))

                NavigationLink {
                    WeeklyGoalSetupView(goal: goal)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .dsFont(.body)
                            .foregroundStyle(DS.Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set Weekly Goals")
                                .dsFont(.subheadline, weight: .semibold)
                                .foregroundStyle(.white)
                            Text("Track active minutes & strength days")
                                .dsFont(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(DS.Theme.accent)
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(
            ChamferedRectangle(.xl)
                .fill(Color.black)
                .overlay(ChamferedRectangle(.xl).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .contextMenu {
            if let goal = goal {
                NavigationLink {
                    WeeklyGoalSetupView(goal: goal)
                } label: {
                    Label("Customize Goal", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    goal.isSet = false
                    try? context.save()
                } label: {
                    Label("Reset Weekly Goal", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}

// MARK: - Dex preview


private struct DexBadge: View {
    let item: DexItem
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(item.isUnlocked ? DS.Theme.accent.opacity(0.18) : Color.gray.opacity(0.12))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary)
                ProfileSectionIcon(
                    kind: .achievementCup,
                    color: item.isUnlocked ? DS.Theme.accent : .secondary,
                    size: 26
                )
            }
            .frame(height: 62)

            Text(item.short)
                .dsFont(.footnote, weight: .semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(minHeight: 128)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Milestones (non-PR)

private struct MilestoneChip: View {
    let a: Achievement

    var body: some View {
        HStack(spacing: 8) {
            ProfileSectionIcon(
                kind: .achievementCup,
                color: a.unlockedAt == nil ? .secondary : DS.Theme.accent,
                size: 18
            )
            .frame(width: 28, height: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).dsFont(.subheadline, weight: .semibold)
                if let when = a.unlockedAt {
                    Text(when, style: .date).dsFont(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(a.progress)/\(a.target)")
                        .dsFont(.caption, monospacedDigits: true)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary))
    }
}

// Color(hex:) is now available from DS.swift, no need to redefine

// MARK: - Weekly Goal Detail View

private struct WeeklyGoalDetailView: View {
    let progress: WeeklyProgress
    let goal: WeeklyGoal

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Progress Summary Section
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This Week's Progress")
                        .dsFont(.title2, weight: .bold)

                    HStack(spacing: 24) {
                        // MVPA Progress
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Minutes")
                                .dsFont(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(progress.mvpaDone)")
                                    .dsFont(.title, weight: .semibold)
                                Text("/ \(progress.mvpaTarget)")
                                    .dsFont(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(Double(progress.mvpaDone), Double(progress.mvpaTarget)), total: Double(max(progress.mvpaTarget, 1)))
                                .tint(DS.Theme.accent)
                        }

                        Divider()

                        // Strength Days Progress
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Strength Days")
                                .dsFont(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(progress.strengthDaysDone)")
                                    .dsFont(.title, weight: .semibold)
                                Text("/ \(progress.strengthTarget)")
                                    .dsFont(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(Double(progress.strengthDaysDone), Double(progress.strengthTarget)), total: Double(max(progress.strengthTarget, 1)))
                                .tint(DS.Theme.accent)
                        }
                    }

                    // Pace Status
                    HStack {
                        Image(systemName: paceIcon)
                            .foregroundStyle(paceColor)
                        Text(progress.statusLine)
                            .dsFont(.subheadline, weight: .medium)
                            .foregroundStyle(paceColor)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(paceColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.vertical, 8)
            }

            // Quick Actions
            Section("Quick Actions") {
                // Start Strength Workout
                if progress.strengthDaysLeft > 0 {
                    Button {
                        // Navigate to Home and start workout
                        //NotificationCenter.default.post(name: .resetHomeToRoot, object: nil)
                        AppBus.postResetHome(reason: .user_intent)

                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(DS.Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start Strength Workout")
                                    .dsFont(.headline)
                                Text("\(progress.strengthDaysLeft) day\(progress.strengthDaysLeft == 1 ? "" : "s") remaining")
                                    .dsFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .dsFont(.caption, weight: .semibold)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // Log Cardio / Import from Health
                if progress.minutesLeft > 0 {
                    NavigationLink {
                        CardioView()
                    } label: {
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Cardio Activity")
                                    .dsFont(.headline)
                                Text("\(progress.minutesLeft) min remaining")
                                    .dsFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    Button {
                        Task {
                            await store.importRunsFromHealth()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync from Apple Health")
                                    .dsFont(.headline)
                                Text("Import runs and exercise minutes")
                                    .dsFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .dsFont(.caption, weight: .semibold)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // All done!
                if progress.minutesLeft == 0 && progress.strengthDaysLeft == 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Weekly targets complete!")
                            .dsFont(.headline)
                    }
                }
            }

            // Goal Settings
            Section("Goal Settings") {
                HStack {
                    Text("Target Active Minutes")
                    Spacer()
                    Text("\(goal.targetActiveMinutes) min")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Target Strength Days")
                    Spacer()
                    Text("\(goal.targetStrengthDays) days")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Week Starts")
                    Spacer()
                    Text(weekdayName(for: goal.anchorWeekday))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Weekly Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    WeeklyGoalSetupView(goal: goal)
                } label: {
                    Text("Edit")
                        .dsFont(.subheadline, weight: .semibold)
                }
            }
        }
    }

    private var paceIcon: String {
        switch progress.paceStatus {
        case .ahead: return "hare.fill"
        case .onTrack: return "checkmark.circle.fill"
        case .behind: return "tortoise.fill"
        }
    }

    private var paceColor: Color {
        switch progress.paceStatus {
        case .ahead: return .green
        case .onTrack: return .green
        case .behind: return .orange
        }
    }

    private func weekdayName(for weekday: Int) -> String {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        let index = (weekday - 1) % 7
        return symbols[index]
    }
}



// MARK: - Streak Freeze Button

private struct StreakFreezeButton: View {
    let progress: RewardProgress
    let hasWeeklyGoal: Bool

    @State private var showActivateAlert = false

    private var freezeStatus: (canActivate: Bool, reason: String?) {
        hasWeeklyGoal
            ? RewardsEngine.shared.canActivateWeeklyStreakFreeze()
            : RewardsEngine.shared.canActivateStreakFreeze()
    }

    var body: some View {
        Button {
            // Only show alert when button is explicitly tapped and freeze is available
            guard freezeStatus.canActivate else { return }
            showActivateAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: freezeIsActive ? "snowflake.circle.fill" : "snowflake.circle")
                    .dsFont(.subheadline)

                if freezeIsActive {
                    Text("Freeze Active")
                        .dsFont(.caption, weight: .semibold)
                } else if let reason = freezeStatus.reason {
                    Text(reason)
                        .dsFont(.caption, weight: .medium)
                } else {
                    Text("Freeze Streak")
                        .dsFont(.caption, weight: .semibold)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                freezeIsActive ? Color.blue.opacity(0.15) : Color.white.opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    freezeIsActive ? Color.blue.opacity(0.3) : Color.white.opacity(0.15),
                    lineWidth: 1
                )
            )
            .foregroundStyle(freezeIsActive ? .blue : .white.opacity(0.85))
            .contentShape(Capsule()) // Ensure tap target is only the capsule shape
        }
        .buttonStyle(.plain) // Prevent any default button animations that might trigger accidentally
        .disabled(!freezeStatus.canActivate)
        .alert("Activate Streak Freeze?", isPresented: $showActivateAlert) {
            Button("Cancel", role: .cancel) {
                showActivateAlert = false
            }
            Button("Activate") {
                if hasWeeklyGoal {
                    RewardsEngine.shared.activateWeeklyStreakFreeze()
                } else {
                    RewardsEngine.shared.activateStreakFreeze()
                }
                showActivateAlert = false
            }
        } message: {
            Text(
                hasWeeklyGoal
                    ? "Protect your \(progress.weeklyGoalStreakCurrent)-week streak. If you miss this week's goal, your streak will be preserved once."
                    : "Protect your \(progress.currentStreak)-day streak. If you miss tomorrow, your streak won't break and you'll earn +50 XP bonus when you return!"
            )
        }
    }

    private var freezeIsActive: Bool {
        hasWeeklyGoal ? progress.weeklyStreakFrozen : progress.streakFrozen
    }
}
