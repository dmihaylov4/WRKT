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

// MARK: - Difficulty Badge

struct DifficultyBadge: View {
    let level: DifficultyLevel

    var body: some View {
        let c = DifficultyTheme.color(for: level)
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(level.label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.white.opacity(0.9))
        .background(c.opacity(0.16), in: ChamferedRectangle(.small))
        .overlay(ChamferedRectangle(.small).stroke(c.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Difficulty: \(level.label)")
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

// MARK: - Difficulty Chip

struct DifficultyChip: View {
    let filter: DifficultyFilter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let c: Color = {
            if let lvl = filter.level { return DifficultyTheme.color(for: lvl) }
            return Color.white.opacity(0.75) // neutral for "All"
        }()

        Button(action: onTap) {
            HStack(spacing: 8) {
                if filter != .all {
                    Circle().fill(c).frame(width: 8, height: 8)
                }
                Text(filter.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (isSelected ? c.opacity(0.22) : Color.clear),
                in: ChamferedRectangle(.small)
            )
            .overlay(
                ChamferedRectangle(.small).stroke(c.opacity(isSelected ? 0.55 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: \(filter.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
