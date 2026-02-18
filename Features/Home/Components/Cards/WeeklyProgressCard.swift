//
//  WeeklyProgressCard.swift
//  WRKT
//
//  Shows progress toward weekly workout goal
//

import SwiftUI

struct WeeklyProgressCard: View {
    let progress: WeeklyProgressData

    private var progressColor: Color {
        if progress.percentage >= 100 {
            return .green
        } else if progress.percentage >= 75 {
            return DS.tint
        } else if progress.percentage >= 50 {
            return .orange
        } else {
            return .red.opacity(0.8)
        }
    }

    private var statusMessage: String {
        if progress.percentage >= 100 {
            return "Goal complete!"
        } else if progress.daysRemaining == 0 {
            return "Week ending today"
        } else if progress.daysRemaining == 1 {
            return "1 day left"
        } else {
            return "\(progress.daysRemaining) days left"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Weekly Progress")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress numbers
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress.completedDays)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(progressColor)

                Text("/\(progress.targetDays)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("workouts")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Spacer()

                // Percentage badge
                Text("\(progress.percentage.safeInt)%")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(progressColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 12)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(progressColor)
                        .frame(
                            width: geometry.size.width * min(progress.percentage / 100.0, 1.0),
                            height: 12
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress.percentage)
                }
            }
            .frame(height: 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            DS.tint.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Preview

#Preview("50% Progress") {
    VStack {
        WeeklyProgressCard(
            progress: WeeklyProgressData(
                completedDays: 2,
                targetDays: 4,
                percentage: 50,
                daysRemaining: 3
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("75% Progress") {
    VStack {
        WeeklyProgressCard(
            progress: WeeklyProgressData(
                completedDays: 3,
                targetDays: 4,
                percentage: 75,
                daysRemaining: 2
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("100% Complete") {
    VStack {
        WeeklyProgressCard(
            progress: WeeklyProgressData(
                completedDays: 4,
                targetDays: 4,
                percentage: 100,
                daysRemaining: 1
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Behind - 25%") {
    VStack {
        WeeklyProgressCard(
            progress: WeeklyProgressData(
                completedDays: 1,
                targetDays: 4,
                percentage: 25,
                daysRemaining: 1
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
