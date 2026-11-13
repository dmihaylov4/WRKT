//
//  CutMeHost.swift
//  WRKT
//
//  Feeds the Cut Me tab from what ProfileView already reads: RewardProgress, the weekly goal,
//  achievements and dex stamps, ProfileScreenViewModel (week progress, PR count, stats refresh,
//  Health sync), PlannerStore adherence and the same statistics summaries the Training Trends and
//  Training Balance sections query. Same Settings, weekly goal, freeze, share, streak recovery
//  and collection flows; only the presentation differs. The trends and balance details are the
//  legacy sections on their own page.
//

import SwiftUI
import SwiftData

struct CutMeHost: View {
    @EnvironmentObject private var repo: ExerciseRepository
    @EnvironmentObject private var authService: SupabaseAuthService
    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context

    @Query private var progress: [RewardProgress]
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @Query private var stamps: [DexStamp]
    @Query private var goals: [WeeklyGoal]
    // The windows ProfileChartsView and TrainingBalanceSection use (12 weeks).
    @Query private var weekly: [WeeklyTrainingSummary]
    @Query private var movingAvgs: [MovingAverage]
    @Query private var pushPull: [PushPullBalance]
    @Query(sort: \MuscleGroupFrequency.lastTrained, order: .reverse) private var muscles: [MuscleGroupFrequency]

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var badgeManager = NotificationBadgeManager.shared
    @State private var viewModel = ProfileScreenViewModel()
    @State private var planAdherenceData: [PlanAdherence] = []
    @State private var showStreakRecovery = false
    @State private var brokenStreakCount = 0
    @State private var destination: Destination?
    @State private var showsPlateWall = false

    private enum Destination: Hashable {
        case settings, weeklyGoal, goalSetup, prCollection, milestones, trends, balance
    }

    init() {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .distantPast
        _goals = Query(filter: #Predicate<WeeklyGoal> { $0.isSet == true })
        _weekly = Query(filter: #Predicate<WeeklyTrainingSummary> { $0.weekStart >= cutoff },
                        sort: \WeeklyTrainingSummary.weekStart, order: .forward)
        _movingAvgs = Query(filter: #Predicate<MovingAverage> { $0.weekStart >= cutoff },
                            sort: \MovingAverage.weekStart, order: .forward)
        _pushPull = Query(filter: #Predicate<PushPullBalance> { $0.weekStart >= cutoff },
                          sort: \PushPullBalance.weekStart, order: .forward)
    }

    private var goal: WeeklyGoal? { goals.first.flatMap { $0.isSet ? $0 : nil } }

    // MARK: Model

    private var facts: CutMeFacts {
        let goalIsSet = goal != nil
        var facts = CutMeFacts()
        if let p = progress.first {
            facts.progress = CutMeFacts.Progress(
                level: p.level, xp: p.xp, prevLevelXP: p.prevLevelXP, nextLevelXP: p.nextLevelXP,
                dailyStreak: p.currentStreak, dailyStreakLongest: p.longestStreak, dailyFrozen: p.streakFrozen,
                weeklyStreak: p.weeklyGoalStreakCurrent, weeklyStreakLongest: p.weeklyGoalStreakLongest,
                weeklyFrozen: p.weeklyStreakFrozen, superStreak: p.weeklySuperStreakCurrent
            )
            let status = goalIsSet
                ? RewardsEngine.shared.canActivateWeeklyStreakFreeze()
                : RewardsEngine.shared.canActivateStreakFreeze()
            facts.freeze = CutMeFacts.Freeze(canActivate: status.canActivate, reason: status.reason)
        }
        facts.goalIsSet = goalIsSet
        facts.goalProgress = viewModel.cachedWeekProgress.map {
            CutMeFacts.GoalProgress(strengthDone: $0.strengthDaysDone, strengthTarget: $0.strengthTarget,
                                    minutesDone: $0.mvpaDone, minutesTarget: $0.mvpaTarget)
        }
        facts.adherence = planAdherenceData.map {
            CutMeFacts.Adherence(planned: $0.plannedSessions, completed: $0.completedOnPlan, missed: $0.missedSessions)
        }
        facts.currentWeekEnded = isCurrentWeekEnded
        facts.weeks = weekly.map { CutMeFacts.Week(weekStart: $0.weekStart, volumeKg: $0.totalVolume) }
        facts.latestWeekChange = movingAvgs.last?.percentChange
        facts.pushVolume = pushPull.last?.pushVolume
        facts.pullVolume = pushPull.last?.pullVolume
        facts.muscles = muscles.map { CutMeFacts.Muscle(name: $0.muscleGroup, lastTrained: $0.lastTrained) }
        facts.prCount = viewModel.unlockedPRCount
        facts.milestoneCount = CutMeLogic.milestoneCount(achievements.map { ($0.id, $0.unlockedAt != nil) })
        facts.unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
        return facts
    }

    var body: some View {
        CutMeView(model: CutMeLogic.model(facts, now: .now), actions: actions)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $destination) { destination in
                destinationView(destination)
            }
            .sheet(isPresented: $showsPlateWall) {
                PlateWallView()
            }
            .sheet(isPresented: $showStreakRecovery) {
                StreakRecoverySheet(
                    brokenStreak: brokenStreakCount,
                    isPresented: $showStreakRecovery,
                    onJoinChallenge: {
                        NotificationCenter.default.post(name: .navigateToCompeteTab, object: nil)
                    },
                    onChallengeFriend: {
                        NotificationCenter.default.post(name: .navigateToCompeteTab, object: nil)
                        Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            NotificationCenter.default.post(name: .openBattleCreateSheet, object: nil)
                        }
                    }
                )
            }
            .task {
                await viewModel.loadExercises(using: repo)
                viewModel.rebuildDexPreview(stamps: stamps)
                await badgeManager.refreshBadges()
            }
            .task(id: goal?.persistentModelID) {
                // The legacy card ran this only while a weekly goal is set.
                guard goal != nil else { return }
                await viewModel.syncHealthKitIfNeeded(store: store, context: context, goals: goals)
                checkForStreakBreak()
            }
            .onChange(of: stamps) { _, _ in
                viewModel.rebuildDexPreview(stamps: stamps)
            }
            .onChange(of: repo.exercises) { _, _ in
                Task {
                    await viewModel.loadExercises(using: repo)
                    viewModel.rebuildDexPreview(stamps: stamps)
                }
            }
            .onChange(of: store.completedWorkouts.count) { _, newCount in
                viewModel.updateWeekProgress(goals: goals, store: store, context: context)
                if newCount > 0 { viewModel.refreshStats(store: store) }
            }
            .onAppear {
                checkForStreakBreak()
                viewModel.updateWeekProgress(goals: goals, store: store, context: context)
                viewModel.refreshStats(store: store)
                loadAdherence()
            }
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
                .environmentObject(authService)
        case .weeklyGoal:
            if let goal, let weekProgress = viewModel.cachedWeekProgress {
                WeeklyGoalDetailView(progress: weekProgress, goal: goal)
            }
        case .goalSetup:
            WeeklyGoalSetupView(goal: goal)
        case .prCollection:
            AchievementsDexView()
        case .milestones:
            AchievementsView()
        case .trends:
            CutMeLegacySectionPage(title: "Training Trends") {
                ProfileStatsView()
            }
        case .balance:
            CutMeLegacySectionPage(title: "Training Balance") {
                TrainingBalanceSection(weeks: 12)
            }
        }
    }

    // MARK: Actions

    private var actions: CutMeActions {
        CutMeActions(
            openSettings: { destination = .settings },
            openWeeklyGoal: {
                Haptics.light()
                destination = .weeklyGoal
            },
            setUpGoal: { destination = .goalSetup },
            customizeGoal: { destination = .goalSetup },
            resetGoal: {
                guard let goal else { return }
                goal.isSet = false
                try? context.save()
            },
            activateFreeze: {
                if goal != nil {
                    RewardsEngine.shared.activateWeeklyStreakFreeze()
                } else {
                    RewardsEngine.shared.activateStreakFreeze()
                }
            },
            shareWeek: postCommitment,
            openTrends: { destination = .trends },
            openBalance: { destination = .balance },
            openRecords: { destination = .prCollection },
            openMilestones: { destination = .milestones },
            openBarbell: { showsPlateWall = true }
        )
    }

    // MARK: ProfileView's flows

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

    private func checkForStreakBreak() {
        guard UserDefaults.standard.object(forKey: "streak_break_detected_at") as? Date != nil else { return }
        UserDefaults.standard.removeObject(forKey: "streak_break_detected_at")
        let previousStreak = UserDefaults.standard.integer(forKey: "streak_break_previous_streak")
        UserDefaults.standard.removeObject(forKey: "streak_break_previous_streak")
        guard previousStreak > 0 else { return }

        brokenStreakCount = previousStreak
        showStreakRecovery = true
    }

    /// The legacy "Make it Public": hands the week to Social's progress share sheet.
    private func postCommitment() {
        guard let goal else { return }

        let calendar = Calendar(identifier: .gregorian)
        let weekStart = calendar.startOfWeek(for: Date(), anchorWeekday: goal.anchorWeekday)
        let workoutsThisWeek = store.completedWorkouts
            .filter { $0.date >= weekStart }
            .sorted { $0.date > $1.date }

        let totalVolume = workoutsThisWeek.reduce(0.0) { sum, w in
            sum + w.entries.reduce(0.0) { $0 + $1.sets.reduce(0.0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) } }
        }
        let uniqueExercises = Set(workoutsThisWeek.flatMap { $0.entries.map(\.exerciseName) }).count
        let totalSets = workoutsThisWeek.flatMap { $0.entries }.flatMap { $0.sets }.filter { $0.isCompleted }.count

        let wp = viewModel.cachedWeekProgress
        let stats = WeeklyProgressStats(
            weekStart: weekStart,
            totalVolumeKg: totalVolume,
            totalExercises: uniqueExercises,
            totalSets: totalSets,
            strengthDaysDone: wp?.strengthDaysDone ?? workoutsThisWeek.count,
            strengthTarget: goal.targetStrengthDays,
            activeMinutesDone: wp?.mvpaDone ?? 0,
            activeMinutesTarget: goal.targetActiveMinutes,
            streak: progress.first?.weeklyGoalStreakCurrent ?? 0,
            superStreak: progress.first?.weeklySuperStreakCurrent ?? 0
        )

        ProgressShareCoordinator.shared.set(workouts: workoutsThisWeek, stats: stats)
        NotificationCenter.default.post(name: .navigateToCompeteTab, object: nil)
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            NotificationCenter.default.post(name: .openProgressShareSheet, object: nil)
        }
    }
}

/// A legacy Profile section (Training Trends, Training Balance) on its own page, unchanged,
/// so every chart, list and info button of the old tab stays one tap away.
private struct CutMeLegacySectionPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 56, system: 36))
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .shellNavigationBarBackground(DS.Semantic.surface)
    }
}
