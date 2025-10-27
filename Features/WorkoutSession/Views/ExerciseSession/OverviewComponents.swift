//
//  OverviewComponents.swift
//  WRKT
//
//  Overview card with equipment chips and technique tips
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Overview Card

struct OverviewCard: View {
    let meta: ExerciseGuideMeta
    @State private var showAllTips = false

    var chips: [ChipItem] {
        var c: [ChipItem] = []
        if !meta.difficulty.isEmpty   { c.append(.init(icon: "dial.medium.fill", label: meta.difficulty)) }
        if !meta.equipment.isEmpty    { c.append(.init(icon: "dumbbell.fill",    label: meta.equipment)) }
        if !meta.mechanics.isEmpty    { c.append(.init(icon: "gearshape",        label: meta.mechanics)) }
        if !meta.forceType.isEmpty    { c.append(.init(icon: "arrow.left.arrow.right", label: meta.forceType)) }
        if !meta.grip.isEmpty         { c.append(.init(icon: "hand.raised.fill", label: meta.grip)) }
        if !meta.classification.isEmpty { c.append(.init(icon: "tag.fill",       label: meta.classification)) }
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
    

            // Technique tips
            if !meta.cues.isEmpty {
                Text("Technique tips")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                let tips = Array(meta.cues.prefix(showAllTips ? meta.cues.count : 3))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tips, id: \.self) { cue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(cue)
                                .foregroundStyle(.white.opacity(0.92))
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if meta.cues.count > 3 {
                        Button(showAllTips ? "Show less" : "Show more") {
                            withAnimation(.easeInOut(duration: 0.18)) { showAllTips.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    struct ChipItem: Identifiable, Hashable {
        let id = UUID()
        let icon: String
        let label: String

        var color: Color {
            // Smart color mapping based on content
            switch label.lowercased() {
            // Equipment
            case let s where s.contains("dumbbell"): return .blue
            case let s where s.contains("barbell"): return .blue
            case let s where s.contains("cable"): return .cyan
            case let s where s.contains("machine"): return .purple
            case let s where s.contains("band"): return .pink
            case let s where s.contains("bodyweight"): return .green

            // Force/Movement
            case let s where s.contains("push"): return .orange
            case let s where s.contains("pull"): return .green
            case let s where s.contains("static"): return .purple

            // Mechanics
            case let s where s.contains("compound"): return .orange
            case let s where s.contains("isolation"): return .cyan

            // Difficulty
            case let s where s.contains("beginner"): return .green
            case let s where s.contains("intermediate"): return .yellow
            case let s where s.contains("advanced"): return .orange
            case let s where s.contains("expert"): return .red

            default: return Theme.accent
            }
        }
    }

    private struct ChipView: View {
        let item: ChipItem

        var body: some View {
            HStack(spacing: 7) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.color)

                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    // Base dark background
                    Capsule()
                        .fill(Color(hex: "#1A1A1A"))

                    // Subtle color glow
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [item.color.opacity(0.15), item.color.opacity(0.05)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [item.color.opacity(0.4), item.color.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
        }
    }
}
