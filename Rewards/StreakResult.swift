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

        // 1) XP
        let xpAward = applyXPRules(event: name, payload: payload)
        totalXP += xpAward.delta
        newLedger += xpAward.ledger

        // 2) Achievements
        let achAward = applyAchievementRules(event: name, payload: payload)
        totalXP += achAward.deltaXP
        totalCoins += achAward.deltaCoins
        newLedger += achAward.ledger
        unlocked += achAward.ledger.compactMap { $0.ruleId }

        // 3) Streak
        var streakOld = progress?.currentStreak ?? 0
        var streakNew = streakOld
        var hitMilestone = false
        if countsAsActivity(event: name) {
            let streak = updateStreaks()
            streakOld = streak.old
            streakNew = streak.new
            hitMilestone = streak.hitMilestone
            totalXP += streak.milestoneXP
            newLedger += streak.ledger
        }

        // 4) Persist + level + notify
        if totalXP != 0 || totalCoins != 0 || !newLedger.isEmpty {
            for entry in newLedger { context.insert(entry) }
            let prevLevel = progress?.level ?? 1
            applyWalletAndLevel(deltaXP: totalXP, deltaCoins: totalCoins)
            try? context.save()
            let newLevel = progress?.level ?? prevLevel
            let leveled = (newLevel > prevLevel) ? newLevel : nil

            if name == "pr_achieved", let c = payload["count"] as? Int {
                   prCount = c
               }
            // ⬅️ KEY CHANGE: include prCount in the notify condition
             let shouldNotify = (totalXP != 0 || totalCoins != 0 || !newLedger.isEmpty || prCount > 0)
             guard shouldNotify else { return }

             // persist & level etc. (unchanged) ...
             for entry in newLedger { context.insert(entry) }
                          applyWalletAndLevel(deltaXP: totalXP, deltaCoins: totalCoins)
             try? context.save()
            
            

             NotificationCenter.default.post(
                 name: .rewardsDidSummarize,
                 object: RewardSummary(
                     xp: totalXP, coins: totalCoins,
                     levelUpTo: leveled,
                     streakOld: progress?.currentStreak ?? 0,  // or the values you computed
                     streakNew: progress?.currentStreak ?? 0,
                     hitStreakMilestone: false,                // fill as you already do
                     unlockedAchievements: unlocked,
                     prCount: prCount
                 )
             )
        }
        print("🎯 PROCESS event:", name, "payload:", payload)
        print("📣 SUMMARY xp:", totalXP, "coins:", totalCoins, "ledger:", newLedger.count)
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
        let usedFreeze = false

        let newCurrent: Int
        switch (diffDays, usedFreeze) {
        case (1, _), (2, true): newCurrent = max(1, prog.currentStreak + 1)
        default:                newCurrent = 1
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

    // Richer summary notification
  
}
