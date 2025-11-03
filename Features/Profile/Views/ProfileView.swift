//
//  ProfileView.swift
//  WRKT
//

import SwiftUI
import SwiftData




struct ProfileView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @Query private var progress: [RewardProgress]
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @Query private var stamps: [DexStamp]
    @Query private var goals: [WeeklyGoal]
    @Query private var thisWeek: [WeeklyTrainingSummary]

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context

    // Tutorial state
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showTutorial = false
    @State private var currentTutorialStep = 0
    @State private var levelCardFrame: CGRect = .zero
    @State private var graphsFrame: CGRect = .zero
    @State private var dexFrame: CGRect = .zero
    @State private var milestonesFrame: CGRect = .zero
    @State private var settingsFrame: CGRect = .zero
    @State private var framesReady = false
    @State private var allExercises: [Exercise] = []
    @State private var dexPreviewCache: [DexItem] = []

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
    
    private func strengthDaysThisWeek(weekStart: Date) -> Int {
        let cal = Calendar.current
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let days = Set(
            store.completedWorkouts
                .filter { $0.date >= weekStart && $0.date < weekEnd }
                .map { cal.startOfDay(for: $0.date) }
        )
        return days.count
    }

    private func syncHealthKitMinutes() async {
        do {
            // Request authorization if not already connected
            if HealthKitManager.shared.connectionState != .connected {
                try await HealthKitManager.shared.requestAuthorization()
                await HealthKitManager.shared.setupBackgroundObservers()
            }

            // Trigger incremental sync (will update WeeklyTrainingSummary models)
            await HealthKitManager.shared.syncExerciseTimeIncremental()

            // Check weekly goal streak after syncing
            await MainActor.run {
                checkWeeklyGoalStreak()
            }
        } catch {
            // Silently fail - authorization may not be granted yet
            await MainActor.run {
                checkWeeklyGoalStreak()
            }
        }
    }

    private func checkWeeklyGoalStreak() {
        guard let goal = goals.first else { return }
        let weekProgress = store.currentWeekProgress(goal: goal, context: context)
        RewardsEngine.shared.checkWeeklyGoalStreak(
            weekStart: weekProgress.weekStart,
            strengthDaysDone: weekProgress.strengthDaysDone,
            strengthTarget: goal.targetStrengthDays,
            mvpaMinutesDone: weekProgress.mvpaDone,
            mvpaTarget: goal.targetActiveMinutes
        )
    }
    
    // MARK: - PR Dex preview items (unlocked first, then alpha; first 8)
    private var dexPreview: [DexItem] {
        Array(dexPreviewCache.prefix(8))
    }

    private func rebuildDexPreview() {
        let unlockedDates: [String: Date] = Dictionary(
            uniqueKeysWithValues: stamps.compactMap { s in
                guard let d = s.unlockedAt else { return nil }
                return (s.key, d)
            }
        )
        let unlockedSet = Set(unlockedDates.keys)

        // Split → sort → merge (using ALL exercises)
        var unlocked: [DexItem] = []
        var locked:   [DexItem] = []

        unlocked.reserveCapacity(allExercises.count / 2)
        locked.reserveCapacity(allExercises.count / 2)

        for ex in allExercises {
            let key = canonicalExerciseKey(from: ex.id)
            let unlockedAt = unlockedDates[key]
            let short = DexText.shortName(ex.name)

            let item = DexItem(
                id: ex.id,
                name: ex.name,
                short: short,
                ruleId: "ach.pr.\(ex.id)",
                progress: unlockedAt == nil ? 0 : 1,
                target: 1,
                unlockedAt: unlockedAt,
                searchKey: DexItem.buildSearchKey(name: ex.name, short: short, id: ex.id)
            )

            if unlockedSet.contains(key) { unlocked.append(item) } else { locked.append(item) }
        }

        unlocked.sort { $0.short < $1.short }
        locked.sort { $0.short < $1.short }

        dexPreviewCache = unlocked + locked
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // UNIFIED PROGRESS OVERVIEW
                if let p = progress.first {
                    Section {
                        if let goal = goals.first, goal.isSet {
                            let weekProgress = store.currentWeekProgress(goal: goal, context: context)

                            ProgressOverviewCard(
                                level: p.level,
                                xp: p.xp,
                                prevXP: p.prevLevelXP,
                                nextXP: p.nextLevelXP,
                                streak: p.currentStreak,
                                longest: p.longestStreak,
                                progress: p,
                                weekProgress: weekProgress,
                                goal: goal
                            )
                            .task {
                                await syncHealthKitMinutes()
                            }
                            .captureFrame(in: .global) { frame in
                                levelCardFrame = frame
                                checkFramesReady()
                            }
                        } else {
                            ProgressOverviewCard(
                                level: p.level,
                                xp: p.xp,
                                prevXP: p.prevLevelXP,
                                nextXP: p.nextLevelXP,
                                streak: p.currentStreak,
                                longest: p.longestStreak,
                                progress: p,
                                weekProgress: nil,
                                goal: nil
                            )
                            .captureFrame(in: .global) { frame in
                                levelCardFrame = frame
                                checkFramesReady()
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear)
                    .id("levelCard")
                } else {
                    Section {
                        ContentUnavailableView("No profile yet",
                                               systemImage: "person.crop.circle.badge.questionmark",
                                               description: Text("Start a workout to earn XP and level up."))
                    }
                }

                // Weekly Goal Streak Card
                if let p = progress.first, let goal = goals.first, goal.isSet {
                    Section {
                        let weekProgress = store.currentWeekProgress(goal: goal, context: context)
                        WeeklyStreakCard(
                            currentStreak: p.weeklyGoalStreakCurrent,
                            longestStreak: p.weeklyGoalStreakLongest,
                            progress: weekProgress,
                            isFrozen: p.streakFrozen
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear)
                    .id("weeklyStreak")
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
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
                .id("graphs")

                // "DEX" PREVIEW — same tiles as the Dex screen (compact variant)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("PR Collection").font(.headline)
                            Spacer()
                            NavigationLink("Open Dex") { AchievementsDexView() }
                                .font(.subheadline.weight(.semibold))
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(dexPreview) { item in
                                DexTile(item: item).equatable()

                            }
                        }
                        .padding(.top, 2)
                        .transaction { $0.animation = nil } // snappy scrolling
                    }
                    .padding(.vertical, 6)
                    .captureFrame(in: .global) { frame in
                        dexFrame = frame
                        checkFramesReady()
                    }
                }
                .id("dex")

                // MILESTONES (non-PR achievements)
                let milestones = achievements
                    .filter { !$0.id.hasPrefix("ach.pr.") }
                    .sorted { a, b in
                        // Sort completed achievements first
                        if (a.unlockedAt != nil) != (b.unlockedAt != nil) {
                            return a.unlockedAt != nil
                        }
                        // Within same completion status, maintain original order (lastUpdatedAt)
                        return false
                    }
                if !milestones.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Milestones").font(.headline)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(milestones.prefix(12)) { a in
                                        MilestoneChip(a: a)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }

                            NavigationLink("See all achievements") { AchievementsView() }
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                        .captureFrame(in: .global) { frame in
                            milestonesFrame = frame
                            checkFramesReady()
                        }
                    }
                    .id("milestones")
                }

                // SETTINGS
                Section("Settings & Connections") {
                    NavigationLink("Preferences") { PreferencesView() }
                    NavigationLink("Health & Sync") { ConnectionsView() }
                }
                .captureFrame(in: .global) { frame in
                    settingsFrame = frame
                    checkFramesReady()
                }
                .id("settings")
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
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
        .task {
            // Load ALL exercises for the dex preview
            allExercises = await repo.getAllExercises()
            rebuildDexPreview()
        }
        .onChange(of: stamps) { _ in
            // Rebuild when stamps change (new PRs unlocked)
            rebuildDexPreview()
        }
        .onChange(of: repo.exercises) { _ in
            // Reload all exercises when exercises update
            Task {
                allExercises = await repo.getAllExercises()
                rebuildDexPreview()
            }
        }
        .onAppear {


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

    // MARK: - Tutorial Logic

    private func checkFramesReady() {
        // Check if all frames have been captured and are valid (with minimum size threshold)
        let minSize: CGFloat = 50 // Minimum frame dimension to be considered valid

        let levelReady = levelCardFrame != .zero && levelCardFrame.width > minSize && levelCardFrame.height > minSize
        let graphsReady = graphsFrame != .zero && graphsFrame.width > minSize && graphsFrame.height > minSize
        let dexReady = dexFrame != .zero && dexFrame.width > minSize && dexFrame.height > minSize
        // Milestones and Settings are optional (might not exist for new users)
        let milestonesReady = (milestonesFrame != .zero && milestonesFrame.width > minSize) || achievements.filter { !$0.id.hasPrefix("ach.pr.") }.isEmpty
        let settingsReady = settingsFrame != .zero && settingsFrame.width > minSize && settingsFrame.height > minSize

        if levelReady && graphsReady && dexReady && milestonesReady && settingsReady && !framesReady {
            // Add a small delay to ensure frames are stable before showing tutorial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                framesReady = true
            }
        }
    }

    private func scrollToStep(_ step: Int, proxy: ScrollViewProxy) {
        // Map tutorial steps to section IDs
        let hasMilestones = !achievements.filter({ !$0.id.hasPrefix("ach.pr.") }).isEmpty

        var sectionIDs: [String] = ["levelCard", "graphs", "dex"]
        if hasMilestones {
            sectionIDs.append("milestones")
        }
        sectionIDs.append("settings")

        guard step < sectionIDs.count else { return }

        let sectionID = sectionIDs[step]

        // Custom anchor for steps 2+ (Dex, Milestones, Settings): slightly above center
        let higherAnchor = UnitPoint(x: 0.5, y: 0.35)

        // Determine if we need to scroll based on step
        // Step 0 (Level Card) - no scroll needed (top of screen)
        // Step 1 (Training Trends) - check if visible, scroll to top if needed
        // Step 2+ (Dex, Milestones, Settings) - always scroll to higher position

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
            // Always scroll for Dex, Milestones, Settings to ensure they're rendered
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
        let screenHeight = UIScreen.main.bounds.height
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 8

        // For scrollable sections, calculate position based on scroll anchor (35% from top)
        let scrolledAnchorY = screenHeight * 0.35

        // Helper to create frame at scrolled position with optional Y offset
        func scrolledFrame(width: CGFloat, height: CGFloat, padding: CGFloat = 8, yOffset: CGFloat = 0) -> CGRect {
            return CGRect(
                x: padding,
                y: scrolledAnchorY - padding + yOffset,
                width: screenWidth - (padding * 2),
                height: height + (padding * 2)
            )
        }

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
                spotlightFrame: {
                    var frame = scrolledFrame(
                        width: dexFrame.width,
                        height: 550,
                        padding: padding,
                        yOffset: -180  // Move up to start earlier on screen
                    )
                    frame.origin.y += 5  // Move upper border down by 5
                    frame.size.height += 20  // Extend lower border by 20
                    return frame
                }(),
                tooltipPosition: .bottom,
                highlightCornerRadius: 16
            ),
            TutorialStep(
                title: "Settings",
                message: "Customize your preferences and connect to Apple Health for seamless workout tracking.",
                spotlightFrame: CGRect(
                    x: padding,
                    y: max(100, screenHeight * 0.65) + 100 - 5,  // Position in lower portion of screen + move up by 5
                    width: screenWidth - (padding * 2),
                    height: 100  // Fixed height for settings section
                ),
                tooltipPosition: .top,
                highlightCornerRadius: 16
            )
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
            // Step 2+ (Dex, Milestones, Settings) - longer delay for scroll and render
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

private struct ProgressOverviewCard: View {
    let level: Int
    let xp: Int
    let prevXP: Int
    let nextXP: Int
    let streak: Int
    let longest: Int
    let progress: RewardProgress
    let weekProgress: WeeklyProgress?
    let goal: WeeklyGoal?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Level & XP Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Level \(level)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    // Streak chip - shows weekly goal streak if goal is set, otherwise daily streak
                    VStack(spacing: 2) {
                        Label {
                            Text("\(goal != nil ? progress.weeklyGoalStreakCurrent : streak)")
                                .font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: "flame.fill")
                        }
                        .labelStyle(.titleAndIcon)

                    
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.90))
                }

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
                        .font(.caption.monospacedDigit())
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
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Streak Freeze Button
            StreakFreezeButton(progress: progress)

            // Weekly Goals Section (if set)
            if let weekProgress = weekProgress, let goal = goal {
                Divider()
                    .background(.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink {
                        WeeklyGoalDetailView(progress: weekProgress, goal: goal)
                    } label: {
                        HStack {
                            Text("Weekly Goals")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    HStack(spacing: 16) {
                        // MVPA Progress
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.run")
                                    .font(.caption)
                                Text("Active Minutes")
                                    .font(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.7))

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(weekProgress.mvpaDone)")
                                    .font(.title3.weight(.semibold))
                                Text("/ \(weekProgress.mvpaTarget)")
                                    .font(.caption)
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
                                    .font(.caption)
                                Text("Strength Days")
                                    .font(.caption)
                            }
                            .foregroundStyle(.white.opacity(0.7))

                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(weekProgress.strengthDaysDone)")
                                    .font(.title3.weight(.semibold))
                                Text("/ \(weekProgress.strengthTarget)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .foregroundStyle(.white)

                            ProgressView(value: min(Double(weekProgress.strengthDaysDone), Double(weekProgress.strengthTarget)), total: Double(max(weekProgress.strengthTarget, 1)))
                                .tint(DS.Theme.accent)
                                .scaleEffect(y: 0.8)
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
                            .font(.body)
                            .foregroundStyle(DS.Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set Weekly Goals")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Track active minutes & strength days")
                                .font(.caption)
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DS.Theme.cardTop, DS.Theme.cardBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
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
                Image(systemName: item.isUnlocked ? "trophy.fill" : "trophy")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(item.isUnlocked ? DS.Theme.accent : .secondary)
                    .font(.title2.weight(.bold))
            }
            .frame(height: 62)

            Text(item.short)
                .font(.footnote.weight(.semibold))
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
            Image(systemName: a.unlockedAt == nil ? "trophy" : "trophy.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(a.unlockedAt == nil ? .secondary : DS.Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(.subheadline.weight(.semibold))
                if let when = a.unlockedAt {
                    Text(when, style: .date).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(a.progress)/\(a.target)")
                        .font(.caption.monospacedDigit())
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
                        .font(.title2.weight(.bold))

                    HStack(spacing: 24) {
                        // MVPA Progress
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Minutes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(progress.mvpaDone)")
                                    .font(.title.weight(.semibold))
                                Text("/ \(progress.mvpaTarget)")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(Double(progress.mvpaDone), Double(progress.mvpaTarget)), total: Double(max(progress.mvpaTarget, 1)))
                                .tint(DS.Theme.accent)
                        }

                        Divider()

                        // Strength Days Progress
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Strength Days")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(progress.strengthDaysDone)")
                                    .font(.title.weight(.semibold))
                                Text("/ \(progress.strengthTarget)")
                                    .font(.title3)
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
                            .font(.subheadline.weight(.medium))
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
                                    .font(.headline)
                                Text("\(progress.strengthDaysLeft) day\(progress.strengthDaysLeft == 1 ? "" : "s") remaining")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
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
                                    .font(.headline)
                                Text("\(progress.minutesLeft) min remaining")
                                    .font(.caption)
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
                                    .font(.headline)
                                Text("Import runs and exercise minutes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
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
                        Text("Weekly targets complete! 🎉")
                            .font(.headline)
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
                        .font(.subheadline.weight(.semibold))
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

    @State private var showActivateAlert = false

    private var freezeStatus: (canActivate: Bool, reason: String?) {
        RewardsEngine.shared.canActivateStreakFreeze()
    }

    var body: some View {
        Button {
            if freezeStatus.canActivate {
                showActivateAlert = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: progress.streakFrozen ? "snowflake.circle.fill" : "snowflake.circle")
                    .font(.subheadline)

                if progress.streakFrozen {
                    Text("Freeze Active")
                        .font(.caption.weight(.semibold))
                } else if let reason = freezeStatus.reason {
                    Text(reason)
                        .font(.caption.weight(.medium))
                } else {
                    Text("Freeze Streak")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                progress.streakFrozen ? Color.blue.opacity(0.15) : Color.white.opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    progress.streakFrozen ? Color.blue.opacity(0.3) : Color.white.opacity(0.15),
                    lineWidth: 1
                )
            )
            .foregroundStyle(progress.streakFrozen ? .blue : .white.opacity(0.85))
        }
        .disabled(!freezeStatus.canActivate)
        .alert("Activate Streak Freeze?", isPresented: $showActivateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Activate") {
                RewardsEngine.shared.activateStreakFreeze()
            }
        } message: {
            Text("Protect your \(progress.currentStreak)-day streak. If you miss tomorrow, your streak won't break and you'll earn +50 XP bonus when you return!")
        }
    }
}
