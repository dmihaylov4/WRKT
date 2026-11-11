//
//  DifficultyComponents.swift
//  WRKT
//
//  Difficulty level UI components and theming
//

import SwiftUI

// MARK: - Difficulty Theme

enum DifficultyTheme {
    // Dark-mode friendly hues, distinct from main accent yellow (#F4E409)
    static let novice       = DS.Status.success // green
    static let beginner     = Color(hex: "#2DD4BF") // teal-400
    static let intermediate = DS.Status.warning // amber
    static let advanced     = DS.Status.error // red

    static func color(for level: DifficultyLevel) -> Color {
        switch level {
        case .novice:       return novice
        case .beginner:     return beginner
        case .intermediate: return intermediate
        case .advanced:     return advanced
        }
    }
}

// MARK: - Difficulty Filter

enum DifficultyFilter: CaseIterable, Hashable {
    case all, novice, beginner, intermediate, advanced

    var label: String {
        switch self {
        case .all: "All"
        case .novice: "Novice"
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    var level: DifficultyLevel? {
        switch self {
        case .all: nil
        case .novice: .novice
        case .beginner: .beginner
        case .intermediate: .intermediate
        case .advanced: .advanced
        }
    }
}
