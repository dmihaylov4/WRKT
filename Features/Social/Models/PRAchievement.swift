//
//  PRAchievement.swift
//  WRKT
//
//  Details about a PR achievement for social auto-posting
//

import Foundation

/// Details about a PR achievement
struct PRAchievement: Sendable {
    let exerciseId: String
    let exerciseName: String
    let previousBest: Double?
    let newBest: Double
    let reps: Int
    let weight: Double
    let improvement: Double?  // Percentage improvement
    let isFirstPR: Bool        // First time doing this exercise

    var improvementPercentage: String? {
        guard let improvement = improvement else { return nil }
        return String(format: "%.1f%%", improvement * 100)
    }
}
