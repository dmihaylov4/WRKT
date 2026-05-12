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
        } else if progress.weekEnded {
            return "Week ended"
        } else if progress.daysRemaining == 0 {
            return "Last day"
        } else if progress.daysRemaining == 1 {
            return "1 day left"
        } else {
            return "\(progress.daysRemaining) days left"
        }
    }

    @ViewBuilder
    private func planAdherenceChip(adherence: PlanAdherence) -> some View {
        let chipColor: Color = adherence.rate >= 1.0 ? .green : (adherence.rate >= 0.6 ? DS.tint : .orange)
        let label = adherence.completedOnPlan == adherence.plannedSessions
            ? "Plan complete"
            : "Plan: \(adherence.completedOnPlan) / \(adherence.plannedSessions) sessions"

        HStack(spacing: 5) {
            Image(systemName: "calendar.badge.checkmark")
                .dsFont(.caption2, weight: .semibold)
            Text(label)
                .dsFont(.caption, weight: .semibold)
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(chipColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(chipColor.opacity(0.3), lineWidth: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Weekly Progress")
                    .dsFont(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(statusMessage)
                    .dsFont(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress numbers
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress.completedDays)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(progressColor)

                Text("/\(progress.targetDays)")
                    .dsFont(.title2, weight: .semibold)
                    .foregroundStyle(.secondary)

                Text("workouts")
                    .dsFont(.subheadline)
                    .foregroundStyle(.tertiary)

                Spacer()

                // Percentage badge
                Text("\(progress.percentage.safeInt)%")
                    .dsFont(.title2, weight: .bold)
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

            // Plan adherence chip
            if let adherence = progress.planAdherence {
                planAdherenceChip(adherence: adherence)
            }

            // Missed sessions note — only after week has ended
            if progress.weekEnded && progress.completedDays < progress.targetDays {
                let missed = progress.targetDays - progress.completedDays
                Text("Missed by \(missed) session\(missed == 1 ? "" : "s") this week")
                    .dsFont(.caption)
                    .foregroundStyle(.secondary)
            }
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
                daysRemaining: 3,
                weekEnded: false,
                planAdherence: nil
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("75% with Plan") {
    VStack {
        WeeklyProgressCard(
            progress: WeeklyProgressData(
                completedDays: 3,
                targetDays: 4,
                percentage: 75,
                daysRemaining: 2,
                weekEnded: false,
                planAdherence: PlanAdherence(plannedSessions: 5, completedOnPlan: 3)
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
                daysRemaining: 1,
                weekEnded: false,
                planAdherence: PlanAdherence(plannedSessions: 4, completedOnPlan: 4)
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Week Ended — Missed") {
    VStack {
        WeeklyProgressCard(
            progress: WeeklyProgressData(
                completedDays: 2,
                targetDays: 4,
                percentage: 50,
                daysRemaining: 0,
                weekEnded: true,
                planAdherence: PlanAdherence(plannedSessions: 5, completedOnPlan: 2)
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
