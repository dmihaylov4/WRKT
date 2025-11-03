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

        // If we've already counted this week, don't count it again
        if let lastWeek = prog.lastWeekGoalMet,
           calendar.isDate(lastWeek, equalTo: weekStart, toGranularity: .weekOfYear) {
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
        if let lastWeek = prog.lastWeekGoalMet {
            // Get the week that should come after lastWeek
            guard let expectedNextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: lastWeek) else {
                newCurrent = 1
                prog.weeklyGoalStreakCurrent = newCurrent
                prog.weeklyGoalStreakLongest = max(prog.weeklyGoalStreakLongest, newCurrent)
                prog.lastWeekGoalMet = weekStart
                return .init(old: 0, new: 1, milestoneXP: 0, didIncrease: true, hitMilestone: false, ledger: [])
            }

            // Check if this week is consecutive (allowing for freeze)
            let weeksGap = calendar.dateComponents([.weekOfYear], from: lastWeek, to: weekStart).weekOfYear ?? 999

            switch (weeksGap, prog.streakFrozen) {
            case (1, _):         // Consecutive week
                newCurrent = prog.weeklyGoalStreakCurrent + 1
            case (2, true):      // 1-week gap with freeze active
                newCurrent = prog.weeklyGoalStreakCurrent + 1
            default:             // Streak broken
                newCurrent = 1
            }
        } else {
            // First week ever
            newCurrent = 1
        }

        // Weekly goal streak milestones: 2, 4, 8, 12, 26, 52 weeks
        let milestones = [2, 4, 8, 12, 26, 52]
        let milestoneXP = [2: 50, 4: 100, 8: 200, 12: 400, 26: 800, 52: 2000][newCurrent] ?? 0
        let hit = milestones.contains(newCurrent)

        let oldStreak = prog.weeklyGoalStreakCurrent
        prog.weeklyGoalStreakCurrent = newCurrent
        prog.weeklyGoalStreakLongest = max(prog.weeklyGoalStreakLongest, newCurrent)
        prog.lastWeekGoalMet = weekStart

        var ledger: [RewardLedgerEntry] = []
        var totalMilestoneXP = milestoneXP
        if hit && milestoneXP > 0 {
            ledger.append(RewardLedgerEntry(
                event: "weekly_goal_streak_milestone",
                ruleId: "weekly_streak_\(newCurrent)",
                deltaXP: milestoneXP,
                deltaCoins: 0,
                metadataJSON: encodeJSON(["streak": newCurrent, "weekStart": Int(weekStart.timeIntervalSince1970)])
            ))
        }

        // Handle super streak (both goals met)
        if isSuperStreak {
            // Check if we already counted this week for super streak
            let alreadyCountedSuper = prog.lastWeekSuperStreakMet.map { calendar.isDate($0, equalTo: weekStart, toGranularity: .weekOfYear) } ?? false

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

    // Richer summary notification

}
