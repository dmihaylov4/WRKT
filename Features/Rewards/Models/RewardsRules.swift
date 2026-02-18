//
//  RewardsRules.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 11.10.25.
//


// Parses rewards_rules_v1.json and offers helpers.
import Foundation

struct RewardsRules: Decodable {
    struct XP: Decodable { let amount: Int; let max_per_day: Int?; let cap_per_workout: Int?; let once_per_workout: Bool?; let max_per_exercise_daily: Int?; let once_per_week: Bool? }
    struct AchievementRule: Decodable { let id, title, desc, trigger: String; let threshold: Int; let tier: String?; let reward: RewardBounty }
    struct RewardBounty: Decodable { let xp: Int?; let coins: Int? }

    let version: Int
    let xp: [String: XP]
    let achievements: [AchievementRule]
    // streaks/challenges omitted for brevity but same idea

    static let empty = RewardsRules(version: 0, xp: [:], achievements: [])
}

enum RewardsRulesLoader {
    static func load(bundleFile: String) -> RewardsRules {
        guard let url = Bundle.main.url(forResource: bundleFile, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode(RewardsRules.self, from: data) else { return .empty }
        return rules
    }
}
