//
//  RewardSummary.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// RewardSummary+Merge.swift
import Foundation

// MARK: - XP Breakdown Models

public struct XPSnapshot: Equatable {
    let beforeXP: Int
    let beforeLevel: Int
    let beforeFloor: Int
    let beforeCeiling: Int

    let afterXP: Int
    let afterLevel: Int
    let afterFloor: Int
    let afterCeiling: Int

    var leveledUp: Bool { afterLevel > beforeLevel }
    var xpGained: Int { afterXP - beforeXP }
}

public struct XPLineItem: Equatable, Identifiable {
    public let id: String    // Unique ID from ledger entry
    let source: String        // e.g., "Active Minutes", "Strength Day", "PR", "New Exercise"
    let xp: Int
    let icon: String         // SF Symbol name
    let detail: String?      // e.g., "Bench Press"
}

public struct RewardSummary: Equatable {
    let xp: Int
    let coins: Int
    let levelUpTo: Int?
    let streakOld: Int
    let streakNew: Int
    let hitStreakMilestone: Bool
    let unlockedAchievements: [String]
    let prCount: Int
    let newExerciseCount: Int

    // Enhanced XP breakdown
    let xpSnapshot: XPSnapshot?
    let xpLineItems: [XPLineItem]
    let streakFrozen: Bool
    let streakBonusXP: Int  // Bonus XP for completing workout after frozen streak

    // Lucky bonus (variable ratio reinforcement)
    let gotLuckyBonus: Bool
    let bonusMultiplier: Double  // 1.0 = no bonus, 1.5/2.0/3.0 = bonus
}

extension RewardSummary {
    var shouldPresent: Bool {
        (xp > 0) ||
        (coins > 0) ||
        (prCount > 0) ||
        (newExerciseCount > 0) ||
        (levelUpTo != nil) ||
        (streakNew > streakOld) ||
        !unlockedAchievements.isEmpty
    }

    func merged(with other: RewardSummary) -> RewardSummary {
        // Merge snapshots properly: use earliest "before" and latest "after"
        let mergedSnapshot: XPSnapshot?
        switch (xpSnapshot, other.xpSnapshot) {
        case (let s1?, let s2?):
            // Both have snapshots: merge them properly
            mergedSnapshot = XPSnapshot(
                beforeXP: s1.beforeXP,           // Use first snapshot's "before"
                beforeLevel: s1.beforeLevel,
                beforeFloor: s1.beforeFloor,
                beforeCeiling: s1.beforeCeiling,
                afterXP: s2.afterXP,             // Use last snapshot's "after"
                afterLevel: s2.afterLevel,
                afterFloor: s2.afterFloor,
                afterCeiling: s2.afterCeiling
            )
        case (let s?, nil):
            mergedSnapshot = s
        case (nil, let s?):
            mergedSnapshot = s
        case (nil, nil):
            mergedSnapshot = nil
        }

        return RewardSummary(
            xp: xp + other.xp,
            coins: coins + other.coins,
            levelUpTo: max(levelUpTo ?? 0, other.levelUpTo ?? 0).nonZeroOrNil,
            streakOld: min(streakOld, other.streakOld),
            streakNew: max(streakNew, other.streakNew),
            hitStreakMilestone: hitStreakMilestone || other.hitStreakMilestone,
            unlockedAchievements: Array(Set(unlockedAchievements + other.unlockedAchievements)),
            prCount: prCount + other.prCount,
            newExerciseCount: newExerciseCount + other.newExerciseCount,
            xpSnapshot: mergedSnapshot,
            xpLineItems: xpLineItems + other.xpLineItems,
            streakFrozen: streakFrozen || other.streakFrozen,
            streakBonusXP: streakBonusXP + other.streakBonusXP,
            gotLuckyBonus: gotLuckyBonus || other.gotLuckyBonus,
            bonusMultiplier: max(bonusMultiplier, other.bonusMultiplier)
        )
    }

    // Convenience init for backward compatibility (basic)
    init(xp: Int, coins: Int, levelUpTo: Int?, streakOld: Int, streakNew: Int,
         hitStreakMilestone: Bool, unlockedAchievements: [String], prCount: Int,
         newExerciseCount: Int) {
        self.xp = xp
        self.coins = coins
        self.levelUpTo = levelUpTo
        self.streakOld = streakOld
        self.streakNew = streakNew
        self.hitStreakMilestone = hitStreakMilestone
        self.unlockedAchievements = unlockedAchievements
        self.prCount = prCount
        self.newExerciseCount = newExerciseCount
        self.xpSnapshot = nil
        self.xpLineItems = []
        self.streakFrozen = false
        self.streakBonusXP = 0
        self.gotLuckyBonus = false
        self.bonusMultiplier = 1.0
    }

    // Full init with XP breakdown (lucky bonus defaults to false)
    init(xp: Int, coins: Int, levelUpTo: Int?, streakOld: Int, streakNew: Int,
         hitStreakMilestone: Bool, unlockedAchievements: [String], prCount: Int,
         newExerciseCount: Int, xpSnapshot: XPSnapshot?, xpLineItems: [XPLineItem],
         streakFrozen: Bool, streakBonusXP: Int) {
        self.xp = xp
        self.coins = coins
        self.levelUpTo = levelUpTo
        self.streakOld = streakOld
        self.streakNew = streakNew
        self.hitStreakMilestone = hitStreakMilestone
        self.unlockedAchievements = unlockedAchievements
        self.prCount = prCount
        self.newExerciseCount = newExerciseCount
        self.xpSnapshot = xpSnapshot
        self.xpLineItems = xpLineItems
        self.streakFrozen = streakFrozen
        self.streakBonusXP = streakBonusXP
        self.gotLuckyBonus = false
        self.bonusMultiplier = 1.0
    }


    /// Apply lucky bonus calculation (12% chance)
    func withLuckyBonusCheck() -> RewardSummary {
        // 12% chance of bonus
        guard Double.random(in: 0...1) < 0.12 else { return self }

        // Weighted multiplier selection: 1.5x (60%), 2x (30%), 3x (10%)
        let roll = Double.random(in: 0...1)
        let multiplier: Double
        if roll < 0.6 {
            multiplier = 1.5
        } else if roll < 0.9 {
            multiplier = 2.0
        } else {
            multiplier = 3.0
        }

        // Apply bonus to XP
        let bonusXP = Int(Double(xp) * multiplier)

        // Recalculate snapshot with bonus
        let newSnapshot: XPSnapshot?
        if let snap = xpSnapshot {
            let bonusGained = bonusXP - xp
            newSnapshot = XPSnapshot(
                beforeXP: snap.beforeXP,
                beforeLevel: snap.beforeLevel,
                beforeFloor: snap.beforeFloor,
                beforeCeiling: snap.beforeCeiling,
                afterXP: snap.afterXP + bonusGained,
                afterLevel: snap.afterLevel,
                afterFloor: snap.afterFloor,
                afterCeiling: snap.afterCeiling
            )
        } else {
            newSnapshot = nil
        }

        return RewardSummary(
            xp: bonusXP,
            coins: coins,
            levelUpTo: levelUpTo,
            streakOld: streakOld,
            streakNew: streakNew,
            hitStreakMilestone: hitStreakMilestone,
            unlockedAchievements: unlockedAchievements,
            prCount: prCount,
            newExerciseCount: newExerciseCount,
            xpSnapshot: newSnapshot,
            xpLineItems: xpLineItems,
            streakFrozen: streakFrozen,
            streakBonusXP: streakBonusXP,
            gotLuckyBonus: true,
            bonusMultiplier: multiplier
        )
    }
}

private extension Int {
    var nonZeroOrNil: Int? { self == 0 ? nil : self }
}
