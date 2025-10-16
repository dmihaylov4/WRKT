//
//  RewardSummary.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// RewardSummary+Merge.swift
import Foundation

public struct RewardSummary: Equatable {
    let xp: Int
    let coins: Int
    let levelUpTo: Int?
    let streakOld: Int
    let streakNew: Int
    let hitStreakMilestone: Bool
    let unlockedAchievements: [String]
    let prCount: Int
}

extension RewardSummary {
    var shouldPresent: Bool {
        (xp > 0) ||
        (coins > 0) ||
        (prCount > 0) ||
        (levelUpTo != nil) ||
        (streakNew > streakOld) ||
        !unlockedAchievements.isEmpty
    }

    func merged(with other: RewardSummary) -> RewardSummary {
        RewardSummary(
            xp: xp + other.xp,
            coins: coins + other.coins,
            levelUpTo: max(levelUpTo ?? 0, other.levelUpTo ?? 0).nonZeroOrNil,
            streakOld: min(streakOld, other.streakOld),
            streakNew: max(streakNew, other.streakNew),
            hitStreakMilestone: hitStreakMilestone || other.hitStreakMilestone,
            unlockedAchievements: Array(Set(unlockedAchievements + other.unlockedAchievements)),
            prCount: prCount + other.prCount
        )
    }
}

private extension Int {
    var nonZeroOrNil: Int? { self == 0 ? nil : self }
}
