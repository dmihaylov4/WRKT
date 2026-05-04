//
//  StreakResult.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 13.10.25.
//


// StreakResult.swift
import Foundation
import SwiftUI
import SwiftData

extension RewardsEngine {

    struct StreakResult {
        let old: Int
        let new: Int
        let milestoneXP: Int
        let didIncrease: Bool
        let hitMilestone: Bool
        let ledger: [RewardLedgerEntry]
    }

    /// Async version of process that runs heavy operations in background
    /// This is the preferred method for workout completion to avoid blocking the main thread
    func processAsync(event name: String, payload: [String:Any] = [:]) {
        guard let mainContext = context else { return }

        // Capture minimal state on main thread (fast)
        let container = mainContext.container
        let rulesSnapshot = rules  // Capture rules for background thread

        // Offload heavy work to background
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // Create background context for all SwiftData operations
            let backgroundContext = ModelContext(container)

            await self.processInBackground(
                event: name,
                payload: payload,
                context: backgroundContext,
                rules: rulesSnapshot
            )
        }
    }

    /// Internal method that does all the heavy lifting on a background context
    /// NOT @MainActor - runs on background thread for performance
    private func processInBackground(event name: String, payload: [String:Any], context bgContext: ModelContext, rules: RewardsRules) {
        var totalXP = 0
        var totalCoins = 0
        var newLedger: [RewardLedgerEntry] = []
        var unlocked: [String] = []
        var prCount = 0
        var newExerciseCount = 0
        var xpLineItems: [XPLineItem] = []

        // Fetch singletons on background context
        let bgProgress = fetchOrCreateProgress(context: bgContext)
        let bgWallet = fetchOrCreateWallet(context: bgContext)

        // Capture BEFORE snapshot
        let beforeXP = bgProgress.xp
        let beforeLevel = bgProgress.level
        let (_, beforeFloor, beforeCeiling) = levelCurveFloors(for: beforeXP)

        // 1) XP - use background context
        let xpAward = applyXPRulesInBackground(event: name, payload: payload, context: bgContext, rules: rules)
        totalXP += xpAward.delta
        newLedger += xpAward.ledger

        for entry in xpAward.ledger where entry.deltaXP > 0 {
            xpLineItems.append(buildXPLineItem(from: entry))
        }

        // 2) Achievements - use background context
        let achAward = applyAchievementRulesInBackground(event: name, payload: payload, context: bgContext, progress: bgProgress, rules: rules)
        totalXP += achAward.deltaXP
        totalCoins += achAward.deltaCoins
        newLedger += achAward.ledger
        unlocked += achAward.ledger.compactMap { $0.ruleId }

        for entry in achAward.ledger where entry.deltaXP > 0 {
            xpLineItems.append(buildXPLineItem(from: entry))
        }

        // 3) Streak
        var streakOld = bgProgress.currentStreak
        var streakNew = streakOld
        var hitMilestone = false
        var streakBonusXP = 0
        let isFrozen = bgProgress.streakFrozen

        if countsAsActivity(event: name) {
            let streak = updateStreaksInBackground(progress: bgProgress, context: bgContext)
            streakOld = streak.old
            streakNew = streak.new
            hitMilestone = streak.hitMilestone
            totalXP += streak.milestoneXP
            newLedger += streak.ledger

            // Streak bonus XP
            if isFrozen && streakNew > 1 {
                let alreadyGaveBonus = hasEventRecordedTodayInBackground(
                    event: "streak_freeze_bonus",
                    contains: "freeze_return_bonus",
                    context: bgContext
                )

                if !alreadyGaveBonus {
                    streakBonusXP = 50
                    totalXP += streakBonusXP
                    let bonusEntry = RewardLedgerEntry(
                        event: "streak_freeze_bonus",
                        ruleId: "freeze_return_bonus",
                        deltaXP: streakBonusXP,
                        deltaCoins: 0,
                        metadataJSON: encodeJSON(["streak": streakNew])
                    )
                    newLedger.append(bonusEntry)
                    xpLineItems.append(XPLineItem(
                        id: bonusEntry.id,
                        source: "Streak Freeze Bonus",
                        xp: streakBonusXP,
                        icon: "snowflake",
                        detail: "Returned after freeze"
                    ))
                    bgProgress.streakFrozen = false
                }
            }

            for entry in streak.ledger where entry.deltaXP > 0 {
                xpLineItems.append(buildXPLineItem(from: entry))
            }
        }

        // Extract counts
        if name == "pr_achieved", let c = payload["count"] as? Int {
            prCount = c
        }
        if name == "exercise_new", let c = payload["count"] as? Int {
            newExerciseCount = c
        }

        // 4) Barbell plate evaluation: evaluate only, inserts are deferred until after shouldNotify guard
        var earnedPlates: [EarnedPlateInfo] = []
        var earnedPlateSyncPayloads: [EarnedPlateSyncPayload] = []
        var barbellPlateEventSyncPayloads: [BarbellPlateEventSyncPayload] = []
        var cosmeticUnlockDrafts: [BarbellCosmeticUnlockDraft] = []
        var cosmeticUnlockSyncPayloads: [BarbellCosmeticUnlockSyncPayload] = []
        var earnedPlateDate: Date = .now
        let earnedPlatesWorkoutID: String? = payload["workoutId"] as? String
        let completedWorkoutsForProjection = payload["completedWorkouts"] as? [CompletedWorkout]
        let rewardPresentationSource = BarbellRewardPresentationSource(
            rawValue: payload["rewardPresentationSource"] as? String ?? ""
        ) ?? .syncRepair
        if name == "workout_completed",
           let workout = payload["completedWorkout"] as? CompletedWorkout,
           !workout.isCardioWorkout {   // only strength workouts earn plates
            earnedPlateDate = workout.date

            let configFD = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
            let bgConfig: BarbellConfig
            if let existing = try? bgContext.fetch(configFD).first {
                bgConfig = existing
            } else {
                bgConfig = BarbellConfig()
                bgContext.insert(bgConfig)
            }

            // Increment strength workout count BEFORE evaluate (rules read updated count)
            bgConfig.totalStrengthWorkouts += 1

            let existingFD = FetchDescriptor<EarnedPlate>()
            let existingPlates = (try? bgContext.fetch(existingFD)) ?? []
            let existingEvents = existingPlates.map(\.earnedByEvent)
            let existingUnlocks = (try? bgContext.fetch(FetchDescriptor<BarbellCosmeticUnlock>())) ?? []

            var plates = BarbellUnlockRules.evaluate(workout: workout, config: bgConfig, existingEvents: existingEvents)
            cosmeticUnlockDrafts = BarbellUnlockRules.evaluateSeasonalCosmetics(
                workout: workout,
                config: bgConfig,
                existingCosmeticUnlockIDs: existingUnlocks.map(\.cosmeticID)
            )

            // Gold streak: append to plates array, then re-sort so rarity order is always correct
            if bgProgress.currentStreak >= 90 {
                if let gold = BarbellUnlockRules.evaluateGoldStreak(existingEvents: existingEvents) {
                    plates.append(gold)
                    bgConfig.lastStreakCheckDate = .now
                }
            }

            // Re-sort after merging so Gold (legendary) always leads regardless of insertion order
            let rarityForTier: [Int: Int] = [6: 5, 5: 4, 4: 3, 3: 3, 2: 2, 1: 1, 0: 0]
            earnedPlates = plates.sorted { (rarityForTier[$0.tierID] ?? 0) > (rarityForTier[$1.tierID] ?? 0) }
        }
        var barbellRewardEvents = earnedPlates.map { info in
            BarbellRewardEvent(
                id: "plate_\(info.earnedByEvent)",
                kind: .newPlate,
                title: info.engravingText.isEmpty ? "New plate" : info.engravingText,
                detail: "\(Int(info.weightKg))kg plate",
                occurredAt: earnedPlateDate,
                workoutID: earnedPlatesWorkoutID,
                plate: info
            )
        }
        if prCount > 0 {
            barbellRewardEvents.append(BarbellRewardEvent(
                id: "pr_\(earnedPlatesWorkoutID ?? UUID().uuidString)",
                kind: .personalRecord,
                title: "\(prCount) PR\(prCount == 1 ? "" : "s")",
                detail: "Added to plate biography",
                occurredAt: earnedPlateDate,
                workoutID: earnedPlatesWorkoutID
            ))
        }
        for draft in cosmeticUnlockDrafts {
            let item = BarbellCosmeticCatalog.current.item(id: draft.cosmeticID)
            barbellRewardEvents.append(BarbellRewardEvent(
                id: "cosmetic_\(draft.cosmeticID)",
                kind: .cosmeticUnlock,
                title: item?.name ?? "New cosmetic",
                detail: "Seasonal unlock",
                occurredAt: draft.unlockedAt,
                workoutID: draft.sourceWorkoutID
            ))
        }
        let rewardQueue = BarbellUnlockRules.makePresentationQueue(
            events: barbellRewardEvents,
            occurredAt: earnedPlateDate,
            source: rewardPresentationSource
        )

        // 5) Persist
        let shouldNotify = (totalXP != 0 || totalCoins != 0 || !newLedger.isEmpty
                            || prCount > 0 || newExerciseCount > 0 || !earnedPlates.isEmpty
                            || !cosmeticUnlockDrafts.isEmpty)
        guard shouldNotify else { return }

        // Persist earned plates (after guard: bgContext.save() is guaranteed to run from here)
        for info in earnedPlates {
            let plate = EarnedPlate(
                tierID: info.tierID,
                weightKg: info.weightKg,
                engravingText: info.engravingText,
                earnedAt: earnedPlateDate,
                earnedByEvent: info.earnedByEvent,
                sourceWorkoutID: earnedPlatesWorkoutID,
                liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(info.liftTypeID)
            )
            bgContext.insert(plate)
            earnedPlateSyncPayloads.append(EarnedPlateSyncPayload(
                info: info,
                earnedAt: earnedPlateDate,
                sourceWorkoutID: earnedPlatesWorkoutID
            ))
        }
        for draft in cosmeticUnlockDrafts {
            bgContext.insert(draft.toModel())
            cosmeticUnlockSyncPayloads.append(BarbellCosmeticUnlockSyncPayload(draft: draft))
        }

        if name == "workout_completed",
           let completedWorkoutsForProjection,
           !completedWorkoutsForProjection.isEmpty {
            BarbellProgressService.applyProgressionProjection(
                completedWorkouts: completedWorkoutsForProjection,
                context: bgContext
            )

            let allPlates = (try? bgContext.fetch(FetchDescriptor<EarnedPlate>())) ?? []
            let syncedPlates = allPlates.filter { $0.earnedByEvent != "starter" }
            earnedPlateSyncPayloads = syncedPlates.map(EarnedPlateSyncPayload.init(plate:))
            let earnedEventByPlateID = Dictionary(uniqueKeysWithValues: syncedPlates.map { ($0.id, $0.earnedByEvent) })
            let allPlateEvents = (try? bgContext.fetch(FetchDescriptor<BarbellPlateEvent>())) ?? []
            barbellPlateEventSyncPayloads = allPlateEvents.compactMap { event in
                guard let earnedByEvent = earnedEventByPlateID[event.plateID] else { return nil }
                return BarbellPlateEventSyncPayload(event: event, earnedByEvent: earnedByEvent)
            }
        }

        for entry in newLedger { bgContext.insert(entry) }
        let prevLevel = bgProgress.level
        applyWalletAndLevelInBackground(
            deltaXP: totalXP,
            deltaCoins: totalCoins,
            progress: bgProgress,
            wallet: bgWallet
        )
        let didSave: Bool
        do {
            try bgContext.save()
            didSave = true
        } catch {
            didSave = false
            AppLogger.error("Failed to save reward processing result: \(error)", category: AppLogger.rewards)
        }
        let newLevel = bgProgress.level
        let leveled = (newLevel > prevLevel) ? newLevel : nil

        // Capture AFTER snapshot
        let afterXP = bgProgress.xp
        let afterLevel = bgProgress.level
        let (_, afterFloor, afterCeiling) = levelCurveFloors(for: afterXP)

        let snapshot = XPSnapshot(
            beforeXP: beforeXP, beforeLevel: beforeLevel,
            beforeFloor: beforeFloor, beforeCeiling: beforeCeiling,
            afterXP: afterXP, afterLevel: afterLevel,
            afterFloor: afterFloor, afterCeiling: afterCeiling
        )

        let summary = RewardSummary(
            xp: totalXP, coins: totalCoins,
            levelUpTo: leveled,
            streakOld: streakOld,
            streakNew: streakNew,
            hitStreakMilestone: hitMilestone,
            unlockedAchievements: unlocked,
            prCount: prCount,
            newExerciseCount: newExerciseCount,
            xpSnapshot: snapshot,
            xpLineItems: xpLineItems,
            streakFrozen: bgProgress.streakFrozen,
            streakBonusXP: streakBonusXP,
            earnedPlates: earnedPlates,
            rewardQueue: rewardQueue
        )

        // Post notification on main thread
        DispatchQueue.main.async {
            if didSave {
                BarbellProgressService.shared.syncEarnedPlateAwardsToSupabase(
                    earnedPlateSyncPayloads,
                    eventPayloads: barbellPlateEventSyncPayloads
                )
                BarbellProgressService.shared.syncBarbellCosmeticUnlocksToSupabase(cosmeticUnlockSyncPayloads)
            }
            NotificationCenter.default.post(
                name: .rewardsDidSummarize,
                object: summary
            )
        }
    }

    /// Original synchronous version - kept for backward compatibility
    func process(event name: String, payload: [String:Any] = [:]) {
        guard context != nil else { return }

        var totalXP = 0
        var totalCoins = 0
        var newLedger: [RewardLedgerEntry] = []
        var unlocked: [String] = []
        var prCount = 0
        var newExerciseCount = 0
        var xpLineItems: [XPLineItem] = []

        // Capture BEFORE snapshot
        ensureSingletons()
        let beforeXP = progress?.xp ?? 0
        let beforeLevel = progress?.level ?? 1
        let (_, beforeFloor, beforeCeiling) = levelCurveFloors(for: beforeXP)

        // 1) XP
        let xpAward = applyXPRules(event: name, payload: payload)
        totalXP += xpAward.delta
        newLedger += xpAward.ledger

        // Build XP line items from XP awards
        for entry in xpAward.ledger where entry.deltaXP > 0 {
            xpLineItems.append(buildXPLineItem(from: entry))
        }

        // 2) Achievements
        let achAward = applyAchievementRules(event: name, payload: payload)
        totalXP += achAward.deltaXP
        totalCoins += achAward.deltaCoins
        newLedger += achAward.ledger
        unlocked += achAward.ledger.compactMap { $0.ruleId }

        // Build XP line items from achievements
        for entry in achAward.ledger where entry.deltaXP > 0 {
            xpLineItems.append(buildXPLineItem(from: entry))
        }

        // 3) Streak & Streak Freeze
        var streakOld = progress?.currentStreak ?? 0
        var streakNew = streakOld
        var hitMilestone = false
        var streakBonusXP = 0
        let isFrozen = progress?.streakFrozen ?? false

        if countsAsActivity(event: name) {
            let streak = updateStreaks()
            streakOld = streak.old
            streakNew = streak.new
            hitMilestone = streak.hitMilestone
            totalXP += streak.milestoneXP
            newLedger += streak.ledger

            // Streak bonus XP if returning after freeze (only once per day)
            if isFrozen && streakNew > 1 {
                // Check if we already gave the bonus today
                let alreadyGaveBonus = hasEventRecordedToday(event: "streak_freeze_bonus", contains: "freeze_return_bonus")

                if !alreadyGaveBonus {
                    streakBonusXP = 50  // Bonus for completing workout after freeze
                    totalXP += streakBonusXP
                    let bonusEntry = RewardLedgerEntry(
                        event: "streak_freeze_bonus",
                        ruleId: "freeze_return_bonus",
                        deltaXP: streakBonusXP,
                        deltaCoins: 0,
                        metadataJSON: encodeJSON(["streak": streakNew])
                    )
                    newLedger.append(bonusEntry)
                    xpLineItems.append(XPLineItem(
                        id: bonusEntry.id,
                        source: "Streak Freeze Bonus",
                        xp: streakBonusXP,
                        icon: "snowflake",
                        detail: "Returned after freeze"
                    ))
                    progress?.streakFrozen = false  // Clear freeze after use
                }
            }

            // Build XP line items from streak
            for entry in streak.ledger where entry.deltaXP > 0 {
                xpLineItems.append(buildXPLineItem(from: entry))
            }
        }

        // Extract prCount and newExerciseCount from payload
        if name == "pr_achieved", let c = payload["count"] as? Int {
            prCount = c
        }
        if name == "exercise_new", let c = payload["count"] as? Int {
            newExerciseCount = c
        }

        // 4) Persist + level + notify
        let shouldNotify = (totalXP != 0 || totalCoins != 0 || !newLedger.isEmpty || prCount > 0 || newExerciseCount > 0)
        guard shouldNotify else { return }

        for entry in newLedger { context.insert(entry) }
        let prevLevel = progress?.level ?? 1
        applyWalletAndLevel(deltaXP: totalXP, deltaCoins: totalCoins)
        try? context.save()
        let newLevel = progress?.level ?? prevLevel
        let leveled = (newLevel > prevLevel) ? newLevel : nil

        // Capture AFTER snapshot
        let afterXP = progress?.xp ?? 0
        let afterLevel = progress?.level ?? 1
        let (_, afterFloor, afterCeiling) = levelCurveFloors(for: afterXP)

        let snapshot = XPSnapshot(
            beforeXP: beforeXP, beforeLevel: beforeLevel,
            beforeFloor: beforeFloor, beforeCeiling: beforeCeiling,
            afterXP: afterXP, afterLevel: afterLevel,
            afterFloor: afterFloor, afterCeiling: afterCeiling
        )

   

        NotificationCenter.default.post(
            name: .rewardsDidSummarize,
            object: RewardSummary(
                xp: totalXP, coins: totalCoins,
                levelUpTo: leveled,
                streakOld: streakOld,
                streakNew: streakNew,
                hitStreakMilestone: hitMilestone,
                unlockedAchievements: unlocked,
                prCount: prCount,
                newExerciseCount: newExerciseCount,
                xpSnapshot: snapshot,
                xpLineItems: xpLineItems,
                streakFrozen: progress?.streakFrozen ?? false,
                streakBonusXP: streakBonusXP
            )
        )
    }

    private func buildXPLineItem(from entry: RewardLedgerEntry) -> XPLineItem {
        let (source, icon, detail) = interpretLedgerEntry(entry)
        return XPLineItem(id: entry.id, source: source, xp: entry.deltaXP, icon: icon, detail: detail)
    }

    private func interpretLedgerEntry(_ entry: RewardLedgerEntry) -> (source: String, icon: String, detail: String?) {
        switch entry.event {
        case "workout_completed":
            return ("Workout Complete", "checkmark.circle.fill", nil)
        case "set_logged":
            // Extract exercise name from metadata if available
            if let json = entry.metadataJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let exerciseName = dict["exerciseName"] as? String {
                return ("Exercise Logged", "square.stack.3d.up.fill", exerciseName)
            }
            return ("Exercise Logged", "square.stack.3d.up.fill", nil)
        case "pr_achieved":
            if let json = entry.metadataJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let exerciseName = dict["exerciseName"] as? String {
                return ("Personal Record", "crown.fill", exerciseName)
            }
            return ("Personal Record", "crown.fill", nil)
        case "exercise_new":
            return ("New Exercise", "star.fill", nil)
        case "streak_milestone":
            if let json = entry.metadataJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let streak = dict["streak"] as? Int {
                return ("Streak Milestone", "flame.fill", "\(streak) days")
            }
            return ("Streak Milestone", "flame.fill", nil)
        case "achievement_unlocked":
            return ("Achievement", "medal.fill", entry.ruleId)
        default:
            return (entry.event.capitalized, "sparkles", nil)
        }
    }

    /// Count exactly once per local day.
    func updateStreaks(activityDate: Date = .now,
                       calendar: Calendar = .current) -> StreakResult {
        ensureSingletons()
        guard let prog = progress else {
            return .init(old: 0, new: 0, milestoneXP: 0, didIncrease: false, hitMilestone: false, ledger: [])
        }
        let today   = calendar.startOfDay(for: activityDate)
        let lastDay = prog.lastActivityAt.map { calendar.startOfDay(for: $0) }

        if let last = lastDay, calendar.isDate(last, inSameDayAs: today) {
            return .init(old: prog.currentStreak, new: prog.currentStreak, milestoneXP: 0, didIncrease: false, hitMilestone: false, ledger: [])
        }

        let diffDays = lastDay.flatMap { calendar.dateComponents([.day], from: $0, to: today).day } ?? 999
        let hasFreezeActive = prog.streakFrozen

        let newCurrent: Int
        switch (diffDays, hasFreezeActive) {
        case (1, _):         newCurrent = max(1, prog.currentStreak + 1)  // consecutive day
        case (2, true):      newCurrent = prog.currentStreak + 1          // 1-day gap with freeze active
        default:             newCurrent = 1                               // streak broken
        }

        let milestones = [3,7,14,30,100]
        let milestoneXP = [3:30, 7:70, 14:160, 30:500, 100:2000][newCurrent] ?? 0
        let hit = milestones.contains(newCurrent)

        prog.currentStreak = newCurrent
        prog.longestStreak = max(prog.longestStreak, newCurrent)
        prog.lastActivityAt = today

        var ledger: [RewardLedgerEntry] = []
        if hit && milestoneXP > 0 {
            ledger.append(RewardLedgerEntry(
                event: "streak_milestone",
                ruleId: "streak_\(newCurrent)",
                deltaXP: milestoneXP,
                deltaCoins: 0,
                metadataJSON: encodeJSON(["streak": newCurrent])
            ))
        }

        return .init(old: newCurrent == 1 ? 0 : newCurrent - 1,
                     new: newCurrent,
                     milestoneXP: milestoneXP,
                     didIncrease: true,
                     hitMilestone: hit,
                     ledger: ledger)
    }

    /// Update weekly goal streaks based on week completion
    /// Call this when a week ends or when a workout is completed that might complete the week
    func updateWeeklyGoalStreaks(
        weekStart: Date,
        strengthDaysDone: Int,
        strengthTarget: Int,
        mvpaMinutesDone: Int,
        mvpaTarget: Int,
        calendar: Calendar = .current
    ) -> StreakResult {
        ensureSingletons()
        guard let prog = progress else {
            return .init(old: 0, new: 0, milestoneXP: 0, didIncrease: false, hitMilestone: false, ledger: [])
        }

        // Check if this week met the goal
        // MVPA is optional - only check if target > 0 (user has set MVPA goal)
        let strengthGoalMet = strengthDaysDone >= strengthTarget
        let mvpaGoalMet = mvpaTarget > 0 ? (mvpaMinutesDone >= mvpaTarget) : true

        // Regular streak: Complete EITHER goal
        let weekGoalMet = strengthGoalMet || mvpaGoalMet

        // Super streak: Complete BOTH goals
        let isSuperStreak = strengthGoalMet && mvpaGoalMet

        guard weekGoalMet else {
            // Week not complete yet, return current streak without changes
            return .init(
                old: prog.weeklyGoalStreakCurrent,
                new: prog.weeklyGoalStreakCurrent,
                milestoneXP: 0,
                didIncrease: false,
                hitMilestone: false,
                ledger: []
            )
        }

        // Check if we've already counted this week for regular streak
        let alreadyCountedRegular = prog.lastWeekGoalMet.map { calendar.isDate($0, equalTo: weekStart, toGranularity: .weekOfYear) } ?? false

        // Check if we've already counted this week for super streak
        let alreadyCountedSuper = prog.lastWeekSuperStreakMet.map { calendar.isDate($0, equalTo: weekStart, toGranularity: .weekOfYear) } ?? false

        // If we've already counted both regular AND super streak, return early
        if alreadyCountedRegular && (alreadyCountedSuper || !isSuperStreak) {
            return .init(
                old: prog.weeklyGoalStreakCurrent,
                new: prog.weeklyGoalStreakCurrent,
                milestoneXP: 0,
                didIncrease: false,
                hitMilestone: false,
                ledger: []
            )
        }

        // Calculate if this is consecutive with the last completed week
        let newCurrent: Int
        let oldStreak = prog.weeklyGoalStreakCurrent
        var ledger: [RewardLedgerEntry] = []
        var totalMilestoneXP = 0
        var hit = false

        // Only update regular streak if we haven't counted this week yet
        if !alreadyCountedRegular {
            // Calculate new streak based on consecutive weeks
            let calculatedStreak: Int
            if let lastWeek = prog.lastWeekGoalMet {
                // Check if this week is consecutive (allowing for freeze)
                // Count weeks by iterating forward
                var weekCount = 0
                var testDate = lastWeek
                while testDate < weekStart {
                    testDate = calendar.date(byAdding: .day, value: 7, to: testDate) ?? testDate
                    weekCount += 1
                    if weekCount > 100 { break }
                }
                let weeksGap = weekCount

                AppLogger.debug("Weekly streak calculation: lastWeek=\(lastWeek.formatted(date: .abbreviated, time: .omitted)), currentWeek=\(weekStart.formatted(date: .abbreviated, time: .omitted)), weeksGap=\(weeksGap), frozen=\(prog.weeklyStreakFrozen), currentStreak=\(prog.weeklyGoalStreakCurrent)", category: AppLogger.rewards)

                switch (weeksGap, prog.weeklyStreakFrozen) {
                case (1, _):         // Consecutive week
                    calculatedStreak = prog.weeklyGoalStreakCurrent + 1
                    AppLogger.info("Weekly streak: Consecutive week, incrementing to \(calculatedStreak)", category: AppLogger.rewards)
                case (2, true):      // 1-week gap with freeze active
                    calculatedStreak = prog.weeklyGoalStreakCurrent + 1
                    prog.weeklyFreezeProtectedWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)
                    AppLogger.info("Weekly streak: 1-week gap with freeze, incrementing to \(calculatedStreak)", category: AppLogger.rewards)
                    prog.weeklyStreakFrozen = false
                default:             // Streak broken
                    calculatedStreak = 1
                    AppLogger.warning("Weekly streak: Broken (gap=\(weeksGap)), resetting to 1", category: AppLogger.rewards)
                }
            } else {
                // First week ever
                calculatedStreak = 1
                AppLogger.info("Weekly streak: First week ever (lastWeekGoalMet=nil), setting to 1", category: AppLogger.rewards)
            }

            newCurrent = calculatedStreak

            // Weekly goal streak milestones: 2, 4, 8, 12, 26, 52 weeks
            let milestones = [2, 4, 8, 12, 26, 52]
            let milestoneXP = [2: 50, 4: 100, 8: 200, 12: 400, 26: 800, 52: 2000][newCurrent] ?? 0
            hit = milestones.contains(newCurrent)

            prog.weeklyGoalStreakCurrent = newCurrent
            prog.weeklyGoalStreakLongest = max(prog.weeklyGoalStreakLongest, newCurrent)
            prog.lastWeekGoalMet = weekStart
            AppLogger.info("Weekly streak updated: current=\(newCurrent), longest=\(prog.weeklyGoalStreakLongest), lastWeekGoalMet=\(weekStart.formatted(date: .abbreviated, time: .omitted))", category: AppLogger.rewards)

            totalMilestoneXP = milestoneXP
            if hit && milestoneXP > 0 {
                ledger.append(RewardLedgerEntry(
                    event: "weekly_goal_streak_milestone",
                    ruleId: "weekly_streak_\(newCurrent)",
                    deltaXP: milestoneXP,
                    deltaCoins: 0,
                    metadataJSON: encodeJSON(["streak": newCurrent, "weekStart": Int(weekStart.timeIntervalSince1970)])
                ))
            }
        } else {
            // Week already counted, keep current streak
            newCurrent = prog.weeklyGoalStreakCurrent
        }

        // Handle super streak (both goals met)
        if isSuperStreak {
            // Only update super streak if we haven't counted this week yet for super streak
            if !alreadyCountedSuper {
                // Calculate super streak
                let newSuperStreak: Int
                if let lastSuperWeek = prog.lastWeekSuperStreakMet {
                    let weeksGap = calendar.dateComponents([.weekOfYear], from: lastSuperWeek, to: weekStart).weekOfYear ?? 999
                    // Super streaks need consecutive weeks (no freeze for premium tier)
                    newSuperStreak = (weeksGap == 1) ? prog.weeklySuperStreakCurrent + 1 : 1
                } else {
                    newSuperStreak = 1
                }

                prog.weeklySuperStreakCurrent = newSuperStreak
                prog.weeklySuperStreakLongest = max(prog.weeklySuperStreakLongest, newSuperStreak)
                prog.lastWeekSuperStreakMet = weekStart
                AppLogger.info("Super streak updated: current=\(newSuperStreak), longest=\(prog.weeklySuperStreakLongest), lastWeekSuperStreakMet=\(weekStart.formatted(date: .abbreviated, time: .omitted))", category: AppLogger.rewards)

                // Super streak milestones with premium XP bonuses
                let superMilestones = [2, 4, 8, 12, 26, 52]
                let superMilestoneXP = [2: 100, 4: 200, 8: 400, 12: 800, 26: 1600, 52: 4000][newSuperStreak] ?? 0
                let hitSuperMilestone = superMilestones.contains(newSuperStreak)

                if hitSuperMilestone && superMilestoneXP > 0 {
                    ledger.append(RewardLedgerEntry(
                        event: "super_weekly_streak_milestone",
                        ruleId: "super_streak_\(newSuperStreak)",
                        deltaXP: superMilestoneXP,
                        deltaCoins: 0,
                        metadataJSON: encodeJSON(["superStreak": newSuperStreak, "weekStart": Int(weekStart.timeIntervalSince1970)])
                    ))
                    totalMilestoneXP += superMilestoneXP
                }

                // Always give bonus XP for super streak week (even without milestone)
                if superMilestoneXP == 0 {
                    let superBonus = 30  // Bonus XP for any super week
                    ledger.append(RewardLedgerEntry(
                        event: "super_weekly_bonus",
                        ruleId: "super_week_bonus",
                        deltaXP: superBonus,
                        deltaCoins: 0,
                        metadataJSON: encodeJSON(["superStreak": newSuperStreak, "weekStart": Int(weekStart.timeIntervalSince1970)])
                    ))
                    totalMilestoneXP += superBonus
                }
            }
        }

        return .init(
            old: oldStreak,
            new: newCurrent,
            milestoneXP: totalMilestoneXP,
            didIncrease: newCurrent > oldStreak,
            hitMilestone: hit,
            ledger: ledger
        )
    }

    /// Helper to check if a week met the goal
    private func weekMetGoal(
        weekStart: Date,
        goal: WeeklyGoal,
        completedWorkouts: [CompletedWorkout],
        runs: [Run],
        context: ModelContext,
        calendar: Calendar
    ) -> (met: Bool, strengthMet: Bool, mvpaMet: Bool) {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        // Get data cutoff date
        let cutoffDate: Date
        if let progress = try? context.fetch(FetchDescriptor<RewardProgress>()).first {
            cutoffDate = progress.dataCutoffDate
        } else {
            cutoffDate = goal.createdAt
        }

        // Filter workouts and runs for this week
        let weekWorkouts = completedWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd && $0.date >= cutoffDate }
        let weekRuns = runs.filter { $0.date >= weekStart && $0.date < weekEnd && $0.date >= cutoffDate }

        // Calculate strength days
        let inAppStrengthDays: Set<Date> = Set(
            weekWorkouts.compactMap { w in
                let didStrength = w.entries.contains { e in
                    e.sets.contains { $0.tag == .working && $0.reps > 0 }
                }
                return didStrength ? calendar.startOfDay(for: w.date) : nil
            }
        )

        let healthKitStrengthDays: Set<Date> = Set(
            weekRuns
                .filter { $0.healthKitUUID != nil && $0.countsAsStrengthDay }
                .map { calendar.startOfDay(for: $0.date) }
        )

        let strengthDone = inAppStrengthDays.union(healthKitStrengthDays).count

        // Calculate MVPA minutes using exact day-level HealthKit cache for the goal week
        // window so custom anchor weekdays cannot double-count overlapping ISO-week rows.
        let summariesDescriptor = FetchDescriptor<WeeklyTrainingSummary>(
            predicate: #Predicate { $0.weekStart >= weekStart && $0.weekStart < weekEnd }
        )
        let weeklyRows = (try? context.fetch(summariesDescriptor)) ?? []
        let validRows = weeklyRows.filter { row in
            let weekEndDate = calendar.date(byAdding: .day, value: 7, to: row.weekStart) ?? row.weekStart
            return weekEndDate > cutoffDate
        }

        let minutesFromSummaries = validRows.reduce(0) { $0 + $1.minutes }
        let dailyExerciseDescriptor = FetchDescriptor<DailyAppleExerciseSummary>(
            predicate: #Predicate { $0.dayStart < weekEnd }
        )
        let dailyExerciseRows = ((try? context.fetch(dailyExerciseDescriptor)) ?? []).filter { row in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: row.dayStart) ?? row.dayStart
            return row.dayStart < weekEnd && dayEnd > max(weekStart, cutoffDate)
        }
        let appleExerciseMinutes = HealthAggregationStore.appleExerciseMinutes(
            from: max(weekStart, cutoffDate),
            to: weekEnd,
            in: context,
            calendar: calendar
        )

        // NOTE: We do NOT add cardio run durations because Apple Watch exercise minutes
        // already include MVPA from cardio activities. Adding run durations would double-count.
        let validRuns = weekRuns.filter { run in
            guard let _ = run.healthKitUUID else { return false }
            return !run.countsAsStrengthDay
        }
        let mvpaFromRuns = validRuns.reduce(0) { $0 + ($1.durationSec / 60) }

        // Total MVPA = strength workout minutes + Apple Watch MVPA
        // We exclude mvpaFromRuns to avoid double-counting (runs are already in appleExerciseMinutes)
        let mvpaDone = minutesFromSummaries + appleExerciseMinutes

        // Check if goals met
        let strengthMet = strengthDone >= goal.targetStrengthDays
        let mvpaMet = goal.targetActiveMinutes > 0 ? (mvpaDone >= goal.targetActiveMinutes) : true
        let weekMet = strengthMet || mvpaMet

        AppLogger.info("🔍   Week \(weekStart.formatted(date: .abbreviated, time: .omitted)): Strength=\(strengthDone)/\(goal.targetStrengthDays) (\(strengthMet ? "✅" : "❌")), MVPA=\(mvpaDone)/\(goal.targetActiveMinutes) (\(mvpaMet ? "✅" : "❌")), Overall=\(weekMet ? "✅" : "❌")", category: AppLogger.rewards)
        AppLogger.info("🔍     MVPA breakdown: strength_mins=\(minutesFromSummaries), apple_exercise=\(appleExerciseMinutes), cardio_runs=\(Int(mvpaFromRuns)) (from \(validRuns.count) runs)", category: AppLogger.rewards)

        // Log individual runs for debugging
        if !validRuns.isEmpty {
            for run in validRuns {
                let mins = run.durationSec / 60
                let type = run.workoutType ?? "Unknown"
                AppLogger.info("🔍       Run: \(run.date.formatted(date: .abbreviated, time: .shortened)) - \(mins)min (\(type))", category: AppLogger.rewards)
            }
        }

        // Log weekly summaries for debugging
        if !validRows.isEmpty {
            for row in validRows {
                AppLogger.info("🔍       Summary: week \(row.weekStart.formatted(date: .abbreviated, time: .omitted)) - strength:\(row.minutes)min, apple:\(row.appleExerciseMinutes ?? 0)min", category: AppLogger.rewards)
            }
        }

        if !dailyExerciseRows.isEmpty {
            for row in dailyExerciseRows.sorted(by: { $0.dayStart < $1.dayStart }) {
                AppLogger.info("🔍       Apple Exercise Day: \(row.dayStart.formatted(date: .abbreviated, time: .omitted)) - \(row.minutes)min", category: AppLogger.rewards)
            }
        } else {
            AppLogger.info("🔍       Apple Exercise Day: none", category: AppLogger.rewards)
        }

        return (weekMet, strengthMet, mvpaMet)
    }

    /// Validates and resets weekly goal streak if previous week was not completed
    /// Call this when views appear to ensure streak accuracy
    /// Returns true if streak was reset
    func validateWeeklyGoalStreak(
        store: WorkoutStoreV2,
        calendar: Calendar = .current
    ) -> Bool {
        AppLogger.info("🔍 Streak validation STARTED", category: AppLogger.rewards)
        ensureSingletons()
        guard let prog = progress else {
            AppLogger.warning("🔍 Streak validation: No progress found", category: AppLogger.rewards)
            return false
        }

        AppLogger.info("🔍 Current streak: \(prog.weeklyGoalStreakCurrent), frozen: \(prog.weeklyStreakFrozen)", category: AppLogger.rewards)

        // Get the user's weekly goal to use correct anchor weekday
        guard let weeklyGoal = fetchWeeklyGoal(context: context!),
              let context = context else {
            AppLogger.warning("🔍 Streak validation: No weekly goal or context", category: AppLogger.rewards)
            return false
        }

        let anchorWeekday = weeklyGoal.anchorWeekday
        let now = Date.now
        let currentWeekStart = calendar.startOfDay(for: calendar.startOfWeek(for: now, anchorWeekday: anchorWeekday))

        AppLogger.info("🔍 Current week start: \(currentWeekStart.formatted(date: .abbreviated, time: .omitted))", category: AppLogger.rewards)
        AppLogger.info("🔍 Weekly goal: \(weeklyGoal.targetStrengthDays) days, \(weeklyGoal.targetActiveMinutes) mins", category: AppLogger.rewards)
        AppLogger.info("🔍 Total workouts in store: \(store.completedWorkouts.count), Total runs: \(store.runs.count)", category: AppLogger.rewards)

        // ALWAYS rebuild streak from ALL weeks since goal creation
        let goalCreationWeek = calendar.startOfWeek(for: weeklyGoal.createdAt, anchorWeekday: anchorWeekday)
        let weeksToCheck = max(4, calendar.dateComponents([.weekOfYear], from: goalCreationWeek, to: currentWeekStart).weekOfYear ?? 4)
        AppLogger.info("🔍 Rebuilding streak from ALL \(weeksToCheck) weeks since goal creation...", category: AppLogger.rewards)

        // Check all weeks going backwards from current week
        var consecutiveWeeks = 0
        var checkDate = currentWeekStart
        var firstBrokenWeekStart: Date?

        for i in 0..<weeksToCheck {
            checkDate = calendar.date(byAdding: .day, value: -7, to: checkDate) ?? checkDate

            // Don't check weeks before goal was created
            if checkDate < goalCreationWeek {
                AppLogger.info("🔍 Reached goal creation week, stopping", category: AppLogger.rewards)
                break
            }

            let result = weekMetGoal(
                weekStart: checkDate,
                goal: weeklyGoal,
                completedWorkouts: store.completedWorkouts,
                runs: store.runs,
                context: context,
                calendar: calendar
            )

            if result.met {
                consecutiveWeeks += 1
                AppLogger.info("🔍 Week \(checkDate.formatted(date: .abbreviated, time: .omitted)) met goal (consecutive: \(consecutiveWeeks))", category: AppLogger.rewards)
            } else if let protectedWeek = prog.weeklyFreezeProtectedWeekStart,
                      calendar.isDate(protectedWeek, equalTo: checkDate, toGranularity: .weekOfYear) {
                consecutiveWeeks += 1
                AppLogger.info("🔍 Week \(checkDate.formatted(date: .abbreviated, time: .omitted)) preserved by historical weekly freeze (consecutive: \(consecutiveWeeks))", category: AppLogger.rewards)
            } else {
                // Stop at first incomplete week
                firstBrokenWeekStart = checkDate
                AppLogger.info("🔍 Week \(checkDate.formatted(date: .abbreviated, time: .omitted)) did NOT meet goal, stopping at week \(i+1)/\(weeksToCheck)", category: AppLogger.rewards)
                break
            }
        }

        let oldStreak = prog.weeklyGoalStreakCurrent
        let oldLastWeekGoalMet = prog.lastWeekGoalMet
        let oldFreezeState = prog.weeklyStreakFrozen
        let oldFreezeUsedAt = prog.weeklyFreezeUsedAt
        let oldProtectedWeekStart = prog.weeklyFreezeProtectedWeekStart

        // Update streak
        prog.weeklyGoalStreakCurrent = consecutiveWeeks
        prog.weeklyGoalStreakLongest = max(prog.weeklyGoalStreakLongest, consecutiveWeeks)

        if consecutiveWeeks > 0 {
            prog.lastWeekGoalMet = calendar.date(byAdding: .day, value: -7, to: currentWeekStart)
            prog.weeklyStreakFrozen = false
        } else {
            prog.lastWeekGoalMet = nil
        }

        // If validation would break an existing streak, auto-consume a monthly weekly freeze once.
        if consecutiveWeeks < oldStreak && oldStreak > 0 {
            if let protectedWeek = oldProtectedWeekStart,
               let brokenWeek = firstBrokenWeekStart,
               calendar.isDate(protectedWeek, equalTo: brokenWeek, toGranularity: .weekOfYear) {
                prog.weeklyGoalStreakCurrent = oldStreak
                prog.lastWeekGoalMet = oldLastWeekGoalMet
                prog.weeklyStreakFrozen = false
                prog.weeklyFreezeUsedAt = oldFreezeUsedAt
                prog.weeklyFreezeProtectedWeekStart = protectedWeek
                AppLogger.info("🔍 Historical weekly freeze already covers \(brokenWeek.formatted(date: .abbreviated, time: .omitted)) - preserving streak at \(oldStreak)", category: AppLogger.rewards)
            } else if oldProtectedWeekStart == nil,
                      let priorFreezeUse = oldFreezeUsedAt,
                      let brokenWeek = firstBrokenWeekStart,
                      oldStreak == consecutiveWeeks + 1,
                      !hasWeeklyFreezeAvailable(prog, now: now, calendar: calendar) {
                prog.weeklyGoalStreakCurrent = oldStreak
                prog.lastWeekGoalMet = oldLastWeekGoalMet
                prog.weeklyStreakFrozen = false
                prog.weeklyFreezeUsedAt = priorFreezeUse
                prog.weeklyFreezeProtectedWeekStart = brokenWeek
                AppLogger.info("🔍 Backfilled historical weekly freeze for \(brokenWeek.formatted(date: .abbreviated, time: .omitted)) based on prior freeze usage - preserving streak at \(oldStreak)", category: AppLogger.rewards)
            } else if oldFreezeState, let brokenWeek = firstBrokenWeekStart {
                prog.weeklyGoalStreakCurrent = oldStreak
                prog.lastWeekGoalMet = oldLastWeekGoalMet
                prog.weeklyStreakFrozen = false
                prog.weeklyFreezeUsedAt = oldFreezeUsedAt ?? now
                prog.weeklyFreezeProtectedWeekStart = brokenWeek
                AppLogger.info("🔍 Consumed active weekly freeze for \(brokenWeek.formatted(date: .abbreviated, time: .omitted)) - preserving streak at \(oldStreak)", category: AppLogger.rewards)
            } else if hasWeeklyFreezeAvailable(prog, now: now, calendar: calendar) {
                prog.weeklyGoalStreakCurrent = oldStreak
                prog.lastWeekGoalMet = oldLastWeekGoalMet
                prog.weeklyStreakFrozen = false
                prog.weeklyFreezeUsedAt = now
                prog.weeklyFreezeProtectedWeekStart = firstBrokenWeekStart
                AppLogger.info("🔍 Auto-used weekly freeze to preserve streak at \(oldStreak)", category: AppLogger.rewards)

                Task { @MainActor in
                    await SmartNudgeManager.shared.sendWeeklyFreezeUsedNotification(streak: oldStreak)
                }
            } else {
                prog.weeklyFreezeProtectedWeekStart = oldProtectedWeekStart
            }
        }

        AppLogger.success("🔍 Rebuilt streak: \(oldStreak) -> \(prog.weeklyGoalStreakCurrent) weeks", category: AppLogger.rewards)

        // Also rebuild super streak
        var consecutiveSuperWeeks = 0
        checkDate = currentWeekStart
        for _ in 0..<consecutiveWeeks {
            checkDate = calendar.date(byAdding: .day, value: -7, to: checkDate) ?? checkDate
            let result = weekMetGoal(
                weekStart: checkDate,
                goal: weeklyGoal,
                completedWorkouts: store.completedWorkouts,
                runs: store.runs,
                context: context,
                calendar: calendar
            )

            if result.strengthMet && result.mvpaMet {
                consecutiveSuperWeeks += 1
            } else {
                break // Super streak requires consecutive super weeks
            }
        }

        let oldSuperStreak = prog.weeklySuperStreakCurrent
        prog.weeklySuperStreakCurrent = consecutiveSuperWeeks
        prog.weeklySuperStreakLongest = max(prog.weeklySuperStreakLongest, consecutiveSuperWeeks)

        if consecutiveSuperWeeks > 0 {
            prog.lastWeekSuperStreakMet = calendar.date(byAdding: .day, value: -7, to: currentWeekStart)
        } else {
            prog.lastWeekSuperStreakMet = nil
        }

        AppLogger.success("🔍 Rebuilt super streak: \(oldSuperStreak) -> \(consecutiveSuperWeeks) weeks", category: AppLogger.rewards)

        try? context.save()
        return oldStreak != consecutiveWeeks || oldSuperStreak != consecutiveSuperWeeks
    }

    /// Fetch weekly goal from context
    private func fetchWeeklyGoal(context: ModelContext) -> WeeklyGoal? {
        let fd = FetchDescriptor<WeeklyGoal>(predicate: #Predicate { $0.isSet })
        return try? context.fetch(fd).first
    }

    // Richer summary notification

    // MARK: - Background Processing Helpers

    /// Fetch or create progress singleton on a given context
    private func fetchOrCreateProgress(context: ModelContext) -> RewardProgress {
        let fd = FetchDescriptor<RewardProgress>(predicate: #Predicate { $0.id == "global" })
        if let existing = try? context.fetch(fd).first {
            return existing
        } else {
            let created = RewardProgress()
            context.insert(created)
            return created
        }
    }

    /// Fetch or create wallet singleton on a given context
    private func fetchOrCreateWallet(context: ModelContext) -> Wallet {
        let fd = FetchDescriptor<Wallet>(predicate: #Predicate { $0.id == "wallet" })
        if let existing = try? context.fetch(fd).first {
            return existing
        } else {
            let created = Wallet()
            context.insert(created)
            return created
        }
    }

    /// Background-safe XP rules application
    private func applyXPRulesInBackground(event name: String, payload: [String:Any], context: ModelContext, rules: RewardsRules) -> XPAward {
        guard let rule = rules.xp[name] else { return .init(delta: 0, ledger: []) }

        var grant = rule.amount

        // Per-day maximum
        if let maxPerDay = rule.max_per_day {
            let awardedToday = xpAwardedTodayInBackground(forEvent: name, context: context)
            let room = max(0, maxPerDay - awardedToday)
            grant = min(grant, room)
        }

        // Once per workout
        if rule.once_per_workout == true, let workoutId = payload["workoutId"] as? String {
            if hasEventRecordedTodayInBackground(event: name, contains: #""workoutId":"\#(workoutId)""#, context: context) {
                grant = 0
            }
        }

        // Per-workout cap
        if let cap = rule.cap_per_workout, let workoutId = payload["workoutId"] as? String {
            let alreadyForWorkout = xpAwardedForWorkoutTodayInBackground(event: name, workoutId: workoutId, context: context)
            let room = max(0, cap - alreadyForWorkout)
            grant = min(grant, room)
        }

        // Per-exercise daily
        if let maxPerExerciseDaily = rule.max_per_exercise_daily,
           let exerciseId = payload["exerciseId"] as? String {
            let awarded = countEntriesTodayInBackground(event: name, contains: #""exerciseId":"\#(exerciseId)""#, context: context)
            if awarded >= maxPerExerciseDaily { grant = 0 }
        }

        guard grant > 0 else { return .init(delta: 0, ledger: []) }

        let entry = RewardLedgerEntry(
            event: name,
            ruleId: name,
            deltaXP: grant,
            deltaCoins: 0,
            metadataJSON: encodeJSON(payload)
        )
        return .init(delta: grant, ledger: [entry])
    }

    /// Background-safe achievement rules application
    private func applyAchievementRulesInBackground(event name: String, payload: [String:Any], context: ModelContext, progress: RewardProgress, rules: RewardsRules) -> AchievementAward {
        var totalXP = 0
        var totalCoins = 0
        var entries: [RewardLedgerEntry] = []

        // 1) Dynamic per-exercise PR achievement
        if name == "pr_achieved",
           let exId = payload["exerciseId"] as? String,
           let exName = payload["exerciseName"] as? String {
            let achId = "ach.pr.\(exId)"
            let ach = fetchOrCreateAchievementInBackground(
                id: achId,
                title: "PR: \(exName)",
                desc: "Set a personal record in \(exName).",
                target: 1,
                tier: nil,
                context: context
            )
            if ach.unlockedAt == nil {
                ach.progress = 1
                ach.unlockedAt = .now
                entries.append(
                    RewardLedgerEntry(
                        event: "achievement_unlocked",
                        ruleId: achId,
                        deltaXP: 0, deltaCoins: 0,
                        metadataJSON: encodeJSON(["achievementId": achId])
                    )
                )
            }
        }

        // 2) Static JSON-driven achievements
        let triggered = rules.achievements.filter { $0.trigger == name }
        for rule in triggered {
            let ach = fetchOrCreateAchievementInBackground(
                id: rule.id, title: rule.title, desc: rule.desc,
                target: rule.threshold, tier: rule.tier, context: context
            )

            if let inc = payload["amount"] as? Int {
                ach.progress += inc
            } else {
                ach.progress += 1
            }
            ach.lastUpdatedAt = .now

            if ach.unlockedAt == nil, ach.progress >= ach.target {
                ach.unlockedAt = .now
                let dxp = rule.reward.xp ?? 0
                let dcn = rule.reward.coins ?? 0
                totalXP += dxp
                totalCoins += dcn
                entries.append(
                    RewardLedgerEntry(
                        event: "achievement_unlocked",
                        ruleId: rule.id,
                        deltaXP: dxp,
                        deltaCoins: dcn,
                        metadataJSON: encodeJSON(["achievementId": rule.id])
                    )
                )
            }
        }

        return .init(deltaXP: totalXP, deltaCoins: totalCoins, ledger: entries)
    }

    private func fetchOrCreateAchievementInBackground(id: String, title: String, desc: String, target: Int, tier: String?, context: ModelContext) -> Achievement {
        let fd = FetchDescriptor<Achievement>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(fd).first { return existing }
        let ach = Achievement(id: id, title: title, desc: desc, target: target)
        if let tier { ach.tier = AchievementTier(rawValue: tier) }
        context.insert(ach)
        return ach
    }

    /// Background-safe streak update
    private func updateStreaksInBackground(progress prog: RewardProgress, context: ModelContext, activityDate: Date = .now, calendar: Calendar = .current) -> StreakResult {
        let today   = calendar.startOfDay(for: activityDate)
        let lastDay = prog.lastActivityAt.map { calendar.startOfDay(for: $0) }

        if let last = lastDay, calendar.isDate(last, inSameDayAs: today) {
            return .init(old: prog.currentStreak, new: prog.currentStreak, milestoneXP: 0, didIncrease: false, hitMilestone: false, ledger: [])
        }

        let diffDays = lastDay.flatMap { calendar.dateComponents([.day], from: $0, to: today).day } ?? 999
        let hasFreezeActive = prog.streakFrozen

        let newCurrent: Int
        switch (diffDays, hasFreezeActive) {
        case (1, _):         newCurrent = max(1, prog.currentStreak + 1)
        case (2, true):      newCurrent = prog.currentStreak + 1
        default:             newCurrent = 1
        }

        let milestones = [3,7,14,30,100]
        let milestoneXP = [3:30, 7:70, 14:160, 30:500, 100:2000][newCurrent] ?? 0
        let hit = milestones.contains(newCurrent)

        prog.currentStreak = newCurrent
        prog.longestStreak = max(prog.longestStreak, newCurrent)
        prog.lastActivityAt = today

        var ledger: [RewardLedgerEntry] = []
        if hit && milestoneXP > 0 {
            ledger.append(RewardLedgerEntry(
                event: "streak_milestone",
                ruleId: "streak_\(newCurrent)",
                deltaXP: milestoneXP,
                deltaCoins: 0,
                metadataJSON: encodeJSON(["streak": newCurrent])
            ))
        }

        return .init(old: newCurrent == 1 ? 0 : newCurrent - 1,
                     new: newCurrent,
                     milestoneXP: milestoneXP,
                     didIncrease: true,
                     hitMilestone: hit,
                     ledger: ledger)
    }

    /// Background-safe wallet and level update
    private func applyWalletAndLevelInBackground(deltaXP: Int, deltaCoins: Int, progress prog: RewardProgress, wallet wal: Wallet) {
        if deltaCoins != 0 { wal.coins = max(0, wal.coins + deltaCoins) }
        if deltaXP == 0 { return }

        prog.xp = max(0, prog.xp + deltaXP)

        let (lvl, cur, nxt) = levelCurveFloors(for: prog.xp)
        prog.level = lvl
        prog.prevLevelXP = cur
        prog.nextLevelXP = nxt
    }

    // Background-safe ledger queries
    private func xpAwardedTodayInBackground(forEvent event: String, context: ModelContext) -> Int {
        let sod = startOfDay(); let eod = endOfDay()
        let fd = FetchDescriptor<RewardLedgerEntry>(
            predicate: #Predicate { $0.event == event && $0.occurredAt >= sod && $0.occurredAt < eod }
        )
        let items = (try? context.fetch(fd)) ?? []
        return items.reduce(0) { $0 + $1.deltaXP }
    }

    private func countEntriesTodayInBackground(event: String, contains token: String, context: ModelContext) -> Int {
        let sod = startOfDay(); let eod = endOfDay()
        let fd = FetchDescriptor<RewardLedgerEntry>(
            predicate: #Predicate {
                $0.event == event &&
                $0.occurredAt >= sod && $0.occurredAt < eod &&
                ($0.metadataJSON?.contains(token) ?? false)
            }
        )
        return (try? context.fetch(fd).count) ?? 0
    }

    private func hasEventRecordedTodayInBackground(event: String, contains token: String, context: ModelContext) -> Bool {
        countEntriesTodayInBackground(event: event, contains: token, context: context) > 0
    }

    private func xpAwardedForWorkoutTodayInBackground(event: String, workoutId: String, context: ModelContext) -> Int {
        let sod = startOfDay(); let eod = endOfDay()
        let token = #""workoutId":"\#(workoutId)""#
        let fd = FetchDescriptor<RewardLedgerEntry>(
            predicate: #Predicate {
                $0.event == event &&
                $0.occurredAt >= sod && $0.occurredAt < eod &&
                ($0.metadataJSON?.contains(token) ?? false)
            }
        )
        let items = (try? context.fetch(fd)) ?? []
        return items.reduce(0) { $0 + $1.deltaXP }
    }

}
