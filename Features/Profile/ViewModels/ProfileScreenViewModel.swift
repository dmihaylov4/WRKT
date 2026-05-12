//
//  ProfileViewModel.swift
//  WRKT
//
//  Profile screen state owner for cache rebuilds, stats refresh, and HealthKit sync orchestration.
//

import Foundation
import Observation
import SwiftData

enum ProfileCollectionDestination: String, CaseIterable, Identifiable {
    case prCollection
    case milestones

    var id: String { rawValue }

    var titleLocalizationKey: String {
        switch self {
        case .prCollection: return "PR Collection"
        case .milestones: return "Milestones"
        }
    }

    var subtitleLocalizationKey: String {
        switch self {
        case .prCollection: return "View personal records"
        case .milestones: return "View achievements"
        }
    }

    var iconName: String {
        switch self {
        case .prCollection: return "crown.fill"
        case .milestones: return "trophy.fill"
        }
    }

    var scrollID: String {
        switch self {
        case .prCollection: return "dex"
        case .milestones: return "milestones"
        }
    }

    var accessibilityIdentifier: String {
        "profile.collection.\(rawValue)"
    }
}

@MainActor
@Observable
final class ProfileScreenViewModel {
    var allExercises: [Exercise] = []
    var dexPreviewCache: [DexItem] = []
    var cachedWeekProgress: WeeklyProgress?
    var cachedMilestones: [Achievement] = []
    var statsRefreshTrigger = 0

    private var lastHealthSyncDate: Date?

    var dexPreview: [DexItem] {
        Array(dexPreviewCache.prefix(8))
    }

    var unlockedPRCount: Int {
        dexPreviewCache.filter { $0.isUnlocked }.count
    }

    func loadExercises(using repo: ExerciseRepository) async {
        allExercises = await repo.getAllExercises()
    }

    func rebuildDexPreview(stamps: [DexStamp]) {
        let unlockedDates: [String: Date] = Dictionary(
            uniqueKeysWithValues: stamps.compactMap { stamp in
                guard let unlockedAt = stamp.unlockedAt else { return nil }
                return (stamp.key, unlockedAt)
            }
        )
        let unlockedSet = Set(unlockedDates.keys)

        var unlocked: [DexItem] = []
        var locked: [DexItem] = []

        unlocked.reserveCapacity(allExercises.count / 2)
        locked.reserveCapacity(allExercises.count / 2)

        for exercise in allExercises {
            let key = canonicalExerciseKey(from: exercise.id)
            let unlockedAt = unlockedDates[key]
            let short = DexText.shortName(exercise.name)

            let item = DexItem(
                id: exercise.id,
                name: exercise.name,
                short: short,
                ruleId: "ach.pr.\(exercise.id)",
                progress: unlockedAt == nil ? 0 : 1,
                target: 1,
                unlockedAt: unlockedAt,
                searchKey: DexItem.buildSearchKey(name: exercise.name, short: short, id: exercise.id)
            )

            if unlockedSet.contains(key) {
                unlocked.append(item)
            } else {
                locked.append(item)
            }
        }

        unlocked.sort { $0.short < $1.short }
        locked.sort { $0.short < $1.short }
        dexPreviewCache = unlocked + locked
    }

    func updateWeekProgress(
        goals: [WeeklyGoal],
        store: WorkoutStoreV2,
        context: ModelContext
    ) {
        guard let goal = goals.first else {
            cachedWeekProgress = nil
            return
        }

        cachedWeekProgress = store.currentWeekProgress(goal: goal, context: context)
    }

    func updateMilestones(achievements: [Achievement]) {
        cachedMilestones = achievements
            .filter { !$0.id.hasPrefix("ach.pr.") }
            .sorted { lhs, rhs in
                if (lhs.unlockedAt != nil) != (rhs.unlockedAt != nil) {
                    return lhs.unlockedAt != nil
                }
                return false
            }
    }

    func refreshStats(store: WorkoutStoreV2) {
        statsRefreshTrigger += 1

        guard !store.completedWorkouts.isEmpty else { return }

        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 200_000_000)

            let (statsAggregator, workouts) = await MainActor.run {
                (store.stats, store.completedWorkouts)
            }

            if let stats = statsAggregator,
               let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                await stats.reindex(all: workouts, cutoff: cutoff)
                AppLogger.info("Stats refreshed from ProfileViewModel", category: AppLogger.statistics)
            }
        }
    }

    func syncHealthKitIfNeeded(
        store: WorkoutStoreV2,
        context: ModelContext,
        goals: [WeeklyGoal]
    ) async {
        guard shouldSyncHealthKit else { return }
        await syncHealthKit(store: store, context: context, goals: goals)
        lastHealthSyncDate = Date()
    }

    func syncHealthKit(
        store: WorkoutStoreV2,
        context: ModelContext,
        goals: [WeeklyGoal]
    ) async {
        do {
            if HealthKitManager.shared.connectionState != .connected {
                try await HealthKitManager.shared.requestAuthorization()
                await HealthKitManager.shared.setupBackgroundObservers()
            }

            await HealthKitManager.shared.syncExerciseTimeIncremental()
        } catch {
            // Best-effort sync; cache refresh and streak validation still run below.
        }

        RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)
        checkWeeklyGoalStreak(goals: goals, store: store, context: context)
        updateWeekProgress(goals: goals, store: store, context: context)
    }

    private var shouldSyncHealthKit: Bool {
        guard let lastHealthSyncDate else { return true }
        return Date().timeIntervalSince(lastHealthSyncDate) > 300
    }

    private func checkWeeklyGoalStreak(
        goals: [WeeklyGoal],
        store: WorkoutStoreV2,
        context: ModelContext
    ) {
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
}
