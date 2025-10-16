//
//  DexKeying.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//

import Foundation
import SwiftUI
import SwiftData

// A single place to define the canonical "suffix" used by PR achievements.
func canonicalExerciseKey(from raw: String) -> String {
    // remove parentheticals like " (Barbell)"
    var s = raw.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression)
    s = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    // normalize punctuation/spaces -> "-"
    s = s.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    // collapse duplicate hyphens
    s = s.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
    // trim hyphens
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return s
}

/// Given all achievements and one exercise, find the matching PR achievement
/// trying several suffix candidates (id, name, canonical forms, legacy name-based ids).
func prAchievement(for exercise: Exercise, from achievements: [Achievement]) -> Achievement? {
    // Build a lookup by **suffix** (id without the "ach.pr." prefix), lowercased
    let bySuffix: [String: Achievement] = Dictionary(
        uniqueKeysWithValues: achievements
            .filter { $0.id.hasPrefix("ach.pr.") }
            .map { (String($0.id.dropFirst("ach.pr.".count)).lowercased(), $0) }
    )

    // Candidates in priority order (add more if you carry aliases/slugs on Exercise)
    var cands: [String] = []
    cands.append(exercise.id.lowercased())
    cands.append(canonicalExerciseKey(from: exercise.id))
    cands.append(exercise.name.lowercased())
    cands.append(canonicalExerciseKey(from: exercise.name))

    // Try to match the first candidate present in the map
    for k in cands {
        if let hit = bySuffix[k] { return hit }
    }
    return nil
}



@Model
final class DexStamp {
    @Attribute(.unique) var key: String
    var unlockedAt: Date?

    init(key: String, unlockedAt: Date? = nil) {
        self.key = key
        self.unlockedAt = unlockedAt
    }
}
