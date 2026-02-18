//
//  ComparativeStatsCard.swift
//  WRKT
//
//  You vs. Friends weekly workout comparison card
//

import SwiftUI
import Charts

struct ComparativeStatsCard: View {
    let stats: ComparativeStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("You vs. Friends")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24) // Space for arrow

                Spacer()

                Text(stats.weekRange)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Status badge
            HStack(spacing: 6) {
                Image(systemName: stats.performanceStatus.icon)
                    .font(.title3)
                    .foregroundStyle(stats.performanceStatus.color)

                Text(stats.performanceStatus.message)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 2)

            // Comparison bars
            VStack(spacing: 16) {
                // User's workouts
                ComparisonRow(
                    label: "You",
                    value: stats.userWorkouts,
                    total: max(stats.userWorkouts, (stats.friendsAverage.rounded(.up)).safeInt),
                    color: DS.Palette.marone,
                    isUser: true
                )

                // Friends average
                ComparisonRow(
                    label: "Friends (\(stats.friendCount))",
                    value: (stats.friendsAverage.rounded()).safeInt,
                    total: max(stats.userWorkouts, (stats.friendsAverage.rounded(.up)).safeInt),
                    color: .gray,
                    isUser: false,
                    showDecimal: stats.friendsAverage.truncatingRemainder(dividingBy: 1) > 0.1
                )
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            DS.Palette.marone.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
    }
}

// MARK: - Comparison Row

private struct ComparisonRow: View {
    let label: String
    let value: Int
    let total: Int
    let color: Color
    let isUser: Bool
    var showDecimal: Bool = false

    private var percentage: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(isUser ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer()

                if showDecimal {
                    Text(String(format: "%.1f", Double(value)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text("\(value)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text("workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * percentage), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Preview

#Preview("Crushing It") {
    VStack {
        ComparativeStatsCard(
            stats: ComparativeStats(
                userWorkouts: 5,
                friendsAverage: 2.3,
                friendCount: 8,
                weekRange: "Dec 18-24"
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Behind") {
    VStack {
        ComparativeStatsCard(
            stats: ComparativeStats(
                userWorkouts: 2,
                friendsAverage: 4.7,
                friendCount: 12,
                weekRange: "Dec 18-24"
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("On Par") {
    VStack {
        ComparativeStatsCard(
            stats: ComparativeStats(
                userWorkouts: 3,
                friendsAverage: 3.2,
                friendCount: 5,
                weekRange: "Dec 18-24"
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
