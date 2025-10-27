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
            streakBonusXP: streakBonusXP + other.streakBonusXP
        )
    }

    // Convenience init for backward compatibility
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
    }
}

private extension Int {
    var nonZeroOrNil: Int? { self == 0 ? nil : self }
}
