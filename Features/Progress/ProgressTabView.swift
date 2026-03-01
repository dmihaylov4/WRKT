//
//  ProgressTabView.swift
//  WRKT
//
//  Unified progress tracking: stats, cardio, achievements, goals
//

import SwiftUI
import SwiftData

struct ProgressTabView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context

    @Query private var progress: [RewardProgress]
    @Query(sort: \Achievement.lastUpdatedAt, order: .reverse) private var achievements: [Achievement]
    @Query private var stamps: [DexStamp]
    @Query private var goals: [WeeklyGoal]
    @Query private var thisWeek: [WeeklyTrainingSummary]

    // Cache expensive calculations
    @State private var cachedWeekProgress: WeeklyProgress?
    @State private var cachedMilestones: [Achievement] = []
    @State private var lastSyncDate: Date?
    @State private var statsRefreshTrigger = 0
    @State private var allExercises: [Exercise] = []
    @State private var dexPreviewCache: [DexItem] = []

    init() {
        // Compute weekStart once for this view's init
        let cal = Calendar.current
        let anchor = 2 // Monday
        let ws = cal.startOfWeek(for: .now, anchorWeekday: anchor)
        _thisWeek = Query(
            filter: #Predicate<WeeklyTrainingSummary> { $0.weekStart == ws },
            sort: \WeeklyTrainingSummary.weekStart,
            order: .forward
        )
        _goals = Query(filter: #Predicate<WeeklyGoal> { $0.isSet == true })
    }

    private var dexPreview: [DexItem] {
        Array(dexPreviewCache.prefix(8))
    }

    private var unlockedPRCount: Int {
        dexPreviewCache.filter { $0.isUnlocked }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Level & Progress Overview
                    if let p = progress.first {
                        if let goal = goals.first, goal.isSet {
                            ProgressOverviewCard(
                                level: p.level,
                                xp: p.xp,
                                prevXP: p.prevLevelXP,
                                nextXP: p.nextLevelXP,
                                streak: p.currentStreak,
                                longest: p.longestStreak,
                                progress: p,
                                weekProgress: cachedWeekProgress,
                                goal: goal
                            )
                            .task {
                                if shouldSyncHealthKit() {
                                    await syncHealthKitMinutes()
                                    lastSyncDate = Date()
                                }
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
                        }

                        // Weekly Goal Streak Card
                        if let goal = goals.first, goal.isSet, let weekProgress = cachedWeekProgress {
                            WeeklyStreakCard(
                                currentStreak: p.weeklyGoalStreakCurrent,
                                longestStreak: p.weeklyGoalStreakLongest,
                                progress: weekProgress,
                                isFrozen: p.streakFrozen
                            )
                            .padding(.horizontal, 4)
                        }
                    }

                    // Training Stats Section
                    VStack(spacing: 16) {
                        ProfileStatsView()
                        TrainingBalanceSection(weeks: 12)
                    }
                    .padding(.horizontal, 4)
                    .id(statsRefreshTrigger)

                    // PR Collection Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PR Collection")
                                    .font(.headline)

                                Text("\(unlockedPRCount) / \(dexPreviewCache.count) unlocked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            NavigationLink(destination: AchievementsDexView()) {
                                Text("View All")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DS.Semantic.brand)
                            }
                        }
                        .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(dexPreview) { item in
                                DexTile(item: item).equatable()
                            }
                        }
                        .padding(.horizontal, 4)
                        .transaction { $0.animation = nil }
                    }

                    // Milestones Preview
                    if !cachedMilestones.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Milestones")
                                    .font(.headline)

                                Spacer()

                                NavigationLink("See All", destination: AchievementsView())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DS.Semantic.brand)
                            }
                            .padding(.horizontal, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(cachedMilestones.prefix(12)) { a in
                                        MilestoneChip(a: a)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }

                    // Cardio Activity Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cardio Activity")
                                .font(.headline)

                            Spacer()

                            NavigationLink("View All", destination: CardioView())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DS.Semantic.brand)
                        }
                        .padding(.horizontal, 4)

                        // Recent cardio preview (you can add a small list here)
                        NavigationLink {
                            CardioView()
                        } label: {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("View Runs & Activities")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DS.Semantic.textPrimary)

                                    Text("Track cardio from Apple Health")
                                        .font(.caption)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                            .padding(16)
                            .background(DS.Semantic.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(DS.Semantic.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical)
            }
            .background(DS.Semantic.surface)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            // Load exercises for dex preview
            allExercises = await repo.getAllExercises()
            rebuildDexPreview()
        }
        .onChange(of: stamps) { _ in
            rebuildDexPreview()
        }
        .onChange(of: repo.exercises) { _ in
            Task {
                allExercises = await repo.getAllExercises()
                rebuildDexPreview()
            }
        }
        .onChange(of: store.completedWorkouts.count) { _, newCount in
            updateWeekProgressCache()
            if newCount > 0 {
                refreshStats()
            }
        }
        .onChange(of: achievements) { _, _ in
            updateMilestonesCache()
        }
        .onAppear {
            updateWeekProgressCache()
            updateMilestonesCache()
            refreshStats()
        }
    }

    // MARK: - Helper Methods

    private func syncHealthKitMinutes() async {
        do {
            if HealthKitManager.shared.connectionState != .connected {
                try await HealthKitManager.shared.requestAuthorization()
                await HealthKitManager.shared.setupBackgroundObservers()
            }

            await HealthKitManager.shared.syncExerciseTimeIncremental()

            await MainActor.run {
                checkWeeklyGoalStreak()
                updateWeekProgressCache()
            }
        } catch {
            await MainActor.run {
                checkWeeklyGoalStreak()
                updateWeekProgressCache()
            }
        }
    }

    private func checkWeeklyGoalStreak() {
        // NOTE: Don't validate/rebuild streak here - validation should only happen on app cold start
        // to avoid recalculating and potentially corrupting the correct stored value.
        // Just check current week's progress for potential streak increment.
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

    private func updateWeekProgressCache() {
        guard let goal = goals.first else {
            cachedWeekProgress = nil
            return
        }
        cachedWeekProgress = store.currentWeekProgress(goal: goal, context: context)
    }

    private func updateMilestonesCache() {
        cachedMilestones = achievements
            .filter { !$0.id.hasPrefix("ach.pr.") }
            .sorted { a, b in
                if (a.unlockedAt != nil) != (b.unlockedAt != nil) {
                    return a.unlockedAt != nil
                }
                return false
            }
    }

    private func refreshStats() {
        statsRefreshTrigger += 1

        guard store.completedWorkouts.count > 0 else { return }

        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 200_000_000)

            guard let stats = store.stats else { return }
            if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                await stats.reindex(all: store.completedWorkouts, cutoff: cutoff)
                AppLogger.info("Stats refreshed from ProgressView", category: AppLogger.statistics)
            }
        }
    }

    private func shouldSyncHealthKit() -> Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > 300 // 5 minutes
    }

    private func rebuildDexPreview() {
        let unlockedDates: [String: Date] = Dictionary(
            uniqueKeysWithValues: stamps.compactMap { s in
                guard let d = s.unlockedAt else { return nil }
                return (s.key, d)
            }
        )
        let unlockedSet = Set(unlockedDates.keys)

        var unlocked: [DexItem] = []
        var locked: [DexItem] = []

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
}

// MARK: - Milestone Chip

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
