//
//  CardioStatsCard.swift
//  WRKT
//
//  Shows weekly active minutes progress
//

import SwiftUI

struct CardioStatsCard: View {
    let activeMinutes: Int
    let targetMinutes: Int

    private var percentage: Double {
        guard targetMinutes > 0 else { return 0 }
        return min(Double(activeMinutes) / Double(targetMinutes) * 100.0, 100.0)
    }

    private var statusColor: Color {
        if percentage >= 100 {
            return .green
        } else if percentage >= 75 {
            return DS.tint
        } else if percentage >= 50 {
            return .orange
        } else {
            return .red.opacity(0.8)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Minutes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("This week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Big number
                Text("\(activeMinutes)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(statusColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(statusColor)
                        .frame(
                            width: geometry.size.width * (percentage / 100.0),
                            height: 8
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: percentage)
                }
            }
            .frame(height: 8)

            // Target
            HStack {
                Text("Goal: \(targetMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if percentage >= 100 {
                    Text("Goal complete!")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text("\(targetMinutes - activeMinutes) min to go")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(DS.card)
        .cornerRadius(14)
    }
}

// MARK: - Preview

#Preview("50% Progress") {
    VStack {
        CardioStatsCard(activeMinutes: 75, targetMinutes: 150)
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Complete") {
    VStack {
        CardioStatsCard(activeMinutes: 150, targetMinutes: 150)
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Just Started") {
    VStack {
        CardioStatsCard(activeMinutes: 20, targetMinutes: 150)
        Spacer()
    }
    .padding()
    .background(Color.black)
}
