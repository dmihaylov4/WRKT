//
//  RewardProgress.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 11.10.25.
//


// WRKT/Features/Rewards/RewardsModels.swift
import Foundation
import SwiftData


@Model final class RewardProgress {
    @Attribute(.unique) var id: String = "global"
    var xp: Int = 0
    var level: Int = 1
    var prevLevelXP: Int = 0      // ✅ default value for migration
    var nextLevelXP: Int = 150

    // Data cutoff date - only workouts after this date count toward progress/streaks
    // Set when app is first installed or when user resets all data
    var dataCutoffDate: Date = Date.now

    // Daily activity streaks (legacy system)
    var longestStreak: Int = 0
    var currentStreak: Int = 0
    var lastActivityAt: Date? = nil
    var streakFrozen: Bool = false  // Streak freeze active
    var freezeUsedAt: Date? = nil   // When freeze was last used

    // Weekly goal streaks
    var weeklyGoalStreakCurrent: Int = 0
    var weeklyGoalStreakLongest: Int = 0
    var lastWeekGoalMet: Date? = nil  // Week start date of last completed week

    // Super streak tracking (both strength + MVPA in same week)
    var weeklySuperStreakCurrent: Int = 0
    var weeklySuperStreakLongest: Int = 0
    var lastWeekSuperStreakMet: Date? = nil  // Week start date of last super week

    // Track last awarded milestone to prevent duplicate XP awards
    var lastAwardedMilestoneLevel: Int = 0  // The milestone level that was last awarded XP

    init(xp: Int = 0, level: Int = 1,
         prevLevelXP: Int = 0, nextLevelXP: Int = 150,
         longestStreak: Int = 0, currentStreak: Int = 0,
         lastActivityAt: Date? = nil,
         weeklyGoalStreakCurrent: Int = 0,
         weeklyGoalStreakLongest: Int = 0,
         lastWeekGoalMet: Date? = nil,
         dataCutoffDate: Date = Date.now) {
        self.xp = xp; self.level = level
        self.prevLevelXP = prevLevelXP
        self.nextLevelXP = nextLevelXP
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.lastActivityAt = lastActivityAt
        self.weeklyGoalStreakCurrent = weeklyGoalStreakCurrent
        self.weeklyGoalStreakLongest = weeklyGoalStreakLongest
        self.lastWeekGoalMet = lastWeekGoalMet
        self.dataCutoffDate = dataCutoffDate
    }
}

enum AchievementTier: String, Codable, CaseIterable { case bronze, silver, gold }
enum ChallengeKind: String, Codable { case daily, weekly, seasonal }

@Model final class Achievement {
    @Attribute(.unique) var id: String            // same as ruleId
    var title: String
    var desc: String
    var tierRaw: String?                          // bronze/silver/gold if tiered
    var progress: Int
    var target: Int
    var unlockedAt: Date?
    var lastUpdatedAt: Date

    var tier: AchievementTier? {
        get { tierRaw.flatMap { AchievementTier(rawValue: $0) } }
        set { tierRaw = newValue?.rawValue }
    }

    init(id: String, title: String, desc: String, target: Int) {
        self.id = id; self.title = title; self.desc = desc
        self.target = target; self.progress = 0; self.lastUpdatedAt = .now
    }
}

@Model final class ChallengeAssignment {
    @Attribute(.unique) var id: String            // ruleId + startDate
    var ruleId: String
    var kindRaw: String                           // daily/weekly/seasonal
    var startedAt: Date
    var expiresAt: Date
    var completedAt: Date?
    var claimedAt: Date?

    var kind: ChallengeKind {
        ChallengeKind(rawValue: kindRaw) ?? .daily  // Fallback to daily if invalid
    }

    init(ruleId: String, kind: ChallengeKind, startedAt: Date, expiresAt: Date) {
        self.id = "\(ruleId)_\(Int(startedAt.timeIntervalSince1970))"
        self.ruleId = ruleId; self.kindRaw = kind.rawValue
        self.startedAt = startedAt; self.expiresAt = expiresAt
    }
}

@Model final class RewardLedgerEntry {
    @Attribute(.unique) var id: String
    var occurredAt: Date
    var event: String              // e.g., "workout_completed"
    var ruleId: String?            // which rule awarded
    var deltaXP: Int
    var deltaCoins: Int
    var metadataJSON: String?      // compact payload blob

    init(event: String, ruleId: String?, deltaXP: Int, deltaCoins: Int, metadataJSON: String?) {
        self.id = UUID().uuidString
        self.occurredAt = .now
        self.event = event; self.ruleId = ruleId
        self.deltaXP = deltaXP; self.deltaCoins = deltaCoins
        self.metadataJSON = metadataJSON
    }
}

@Model final class Wallet {
    @Attribute(.unique) var id: String
    var coins: Int

    // ✅ Explicit init so callers can do `Wallet()` or `Wallet(id:..., coins:...)`
    init(id: String = "wallet", coins: Int = 0) {
        self.id = id
        self.coins = coins
    }
}
