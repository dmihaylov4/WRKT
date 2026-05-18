//
//  UnifiedWeeklyStatsCard.swift
//  WRKT
//
//  Unified weekly progress card showing both strength and cardio goals
//

import SwiftUI

enum WeeklyProgressGoalState: Equatable {
    case inProgress
    case complete
}

struct WeeklyProgressGoalPresentation: Equatable {
    let state: WeeklyProgressGoalState
    let trailingText: String
    let showsIcon: Bool
}

func weeklyProgressGoalPresentation(
    completed: Int,
    target: Int,
    unitLabel: String
) -> WeeklyProgressGoalPresentation {
    if target > 0 && completed >= target {
        return WeeklyProgressGoalPresentation(
            state: .complete,
            trailingText: "Complete",
            showsIcon: false
        )
    }

    return WeeklyProgressGoalPresentation(
        state: .inProgress,
        trailingText: "\(completed)/\(target) \(unitLabel)",
        showsIcon: false
    )
}

func weeklyPlanAdherenceLabel(_ adherence: PlanAdherence) -> String {
    adherence.completedOnPlan == adherence.plannedSessions
        ? "Plan complete"
        : "Planned: \(adherence.completedOnPlan)/\(adherence.plannedSessions)"
}

func weeklyProgressCompletionMessage(
    strengthComplete: Bool,
    cardioComplete: Bool
) -> String? {
    switch (strengthComplete, cardioComplete) {
    case (true, true):
        return "All goals locked in"
    case (true, false):
        return "Strength complete"
    case (false, true):
        return "Cardio complete"
    case (false, false):
        return nil
    }
}

struct UnifiedWeeklyStatsCard: View {
    let strengthCompleted: Int
    let strengthTarget: Int
    let cardioMinutes: Int
    let cardioTarget: Int
    let daysRemaining: Int

    // Streak data (optional for backward compatibility)
    var currentStreak: Int = 0
    var nextMilestone: Int? = nil
    var milestoneProgress: Double = 0
    var urgencyLevel: StreakUrgencyLevel? = nil
    var urgencyMessage: String? = nil

    // Plan adherence
    var planAdherence: PlanAdherence? = nil
    var weekEnded: Bool = false

    private var strengthPercentage: Double {
        guard strengthTarget > 0 else { return 0 }
        return min(Double(strengthCompleted) / Double(strengthTarget) * 100.0, 100.0)
    }

    private var cardioPercentage: Double {
        guard cardioTarget > 0 else { return 0 }
        return min(Double(cardioMinutes) / Double(cardioTarget) * 100.0, 100.0)
    }

    private var overallPercentage: Double {
        (strengthPercentage + cardioPercentage) / 2.0
    }

    private var strengthComplete: Bool {
        strengthPercentage >= 100
    }

    private var cardioComplete: Bool {
        cardioPercentage >= 100
    }

    private var strengthPresentation: WeeklyProgressGoalPresentation {
        weeklyProgressGoalPresentation(
            completed: strengthCompleted,
            target: strengthTarget,
            unitLabel: "workouts"
        )
    }

    private var cardioPresentation: WeeklyProgressGoalPresentation {
        weeklyProgressGoalPresentation(
            completed: cardioMinutes,
            target: cardioTarget,
            unitLabel: "min"
        )
    }

    private var statusColor: Color {
        if overallPercentage >= 100 {
            return DS.tint
        } else if overallPercentage == 0 {
            return .secondary  // Week just started — don't show alarm on day 1
        } else if overallPercentage >= 50 || daysRemaining > 2 {
            return DS.tint     // Making progress, or still plenty of time
        } else {
            return DS.Semantic.warning  // Behind AND time is running out
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Progress")
                        .font(DS.Typography.font(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(daysRemaining == 0 ? "Last day!" : "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left")
                        .dsFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Overall percentage
                Text("\(Int(overallPercentage))%")
                    .font(DS.Typography.custom(size: 28, weight: .bold, relativeTo: .title2, monospacedDigits: true))
                    .foregroundStyle(statusColor)
            }

            // NEW: Streak Section (if user has streak)
            if currentStreak > 0 {
                streakSection
            }

            // Strength Section
            VStack(spacing: 6) {
                HStack {
                    Image("tab-train")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text("Strength")
                        .font(DS.Typography.font(.caption, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    goalTrailingValue(strengthPresentation)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(DS.tint)
                            .frame(
                                width: geometry.size.width * (strengthPercentage / 100.0),
                                height: 6
                            )
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: strengthPercentage)
                    }
                }
                .frame(height: 6)
            }

            // Cardio Section
            VStack(spacing: 6) {
                HStack {
                    Image("tab-cardio")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text("Cardio")
                        .font(DS.Typography.font(.caption, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    goalTrailingValue(cardioPresentation)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(DS.tint)
                            .frame(
                                width: geometry.size.width * (cardioPercentage / 100.0),
                                height: 6
                            )
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardioPercentage)
                    }
                }
                .frame(height: 6)
            }

            // Footer: status text + optional plan chip on the same row
            HStack(spacing: 8) {
                if weekEnded && (strengthCompleted < strengthTarget || cardioMinutes < cardioTarget) {
                    // Week ended, missed goal
                    HStack(spacing: 4) {
                        if strengthCompleted < strengthTarget {
                            let missed = strengthTarget - strengthCompleted
                            Text("Missed \(missed) strength session\(missed == 1 ? "" : "s")")
                        }
                        if strengthCompleted < strengthTarget && cardioMinutes < cardioTarget {
                            Text("•")
                        }
                        if cardioMinutes < cardioTarget {
                            Text("Missed \(cardioTarget - cardioMinutes) cardio min")
                        }
                    }
                    .dsFont(.caption2)
                    .foregroundStyle(.secondary)
                } else if let completionMessage = weeklyProgressCompletionMessage(
                    strengthComplete: strengthComplete,
                    cardioComplete: cardioComplete
                ) {
                    Text(completionMessage)
                        .font(DS.Typography.font(.caption, weight: .medium))
                        .foregroundStyle(DS.tint)
                } else {
                    HStack(spacing: 4) {
                        if strengthCompleted < strengthTarget {
                            Text("•")
                            Text("\(strengthTarget - strengthCompleted) workouts to go")
                        }
                        if strengthCompleted < strengthTarget && cardioMinutes < cardioTarget {
                            Text("•")
                        }
                        if cardioMinutes < cardioTarget {
                            Text("\(cardioTarget - cardioMinutes) min to go")
                        }
                    }
                    .dsFont(.caption2)
                    .foregroundStyle(.secondary)
                }

                if let adherence = planAdherence {
                    Spacer()
                    planAdherenceChip(adherence: adherence)
                }
            }
        }
        .padding(12)
        .background(DS.card, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Components

    @ViewBuilder
    private func goalTrailingValue(_ presentation: WeeklyProgressGoalPresentation) -> some View {
        switch presentation.state {
        case .complete:
            completeChip(presentation)
        case .inProgress:
            Text(presentation.trailingText)
                .dsFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func completeChip(_ presentation: WeeklyProgressGoalPresentation) -> some View {
        HStack(spacing: 3) {
            if presentation.showsIcon {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }

            Text(presentation.trailingText)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(DS.tint)
        .clipShape(ChamferedRectangleAlt(.micro))
        .overlay(
            ChamferedRectangleAlt(.micro)
                .stroke(DS.tint.opacity(0.45), lineWidth: 1)
        )
        .fixedSize()
    }

    @ViewBuilder
    private func planAdherenceChip(adherence: PlanAdherence) -> some View {
        let chipColor: Color = adherence.rate >= 1.0 ? DS.tint : (adherence.rate >= 0.6 ? DS.tint : .orange)
        let label = weeklyPlanAdherenceLabel(adherence)

        HStack(spacing: 5) {
            Image("tab-plan")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
            Text(label)
                .font(DS.Typography.font(.caption, weight: .semibold))
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(chipColor.opacity(0.12))
        .clipShape(ChamferedRectangleAlt(.micro))
        .overlay(ChamferedRectangleAlt(.micro).stroke(chipColor.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func urgencyBanner(level: StreakUrgencyLevel, message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon on the left, aligned with text
            Image(systemName: level == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .dsFont(.caption)
                .foregroundStyle(level.color)

            // Text aligned to the left
            Text(message)
                .font(DS.Typography.font(.caption, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(level.color.opacity(0.15))
        .cornerRadius(8)
    }

    private var streakSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image("streak-icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(DS.Palette.marone)

                Text("Weekly Streak")
                    .font(DS.Typography.font(.caption, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(currentStreak) week\(currentStreak == 1 ? "" : "s")")
                    .font(DS.Typography.font(.caption, weight: .bold))
                    .foregroundStyle(DS.Palette.marone)
            }

            // Milestone progress
            if let nextMilestone = nextMilestone {
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.Palette.marone)
                                .frame(width: geometry.size.width * milestoneProgress, height: 6)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: milestoneProgress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("Next milestone:")
                            .dsFont(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(nextMilestone) weeks")
                            .font(DS.Typography.font(.caption2, weight: .medium))
                            .foregroundStyle(DS.Palette.marone)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Partial Progress") {
    VStack {
        UnifiedWeeklyStatsCard(
            strengthCompleted: 3,
            strengthTarget: 5,
            cardioMinutes: 75,
            cardioTarget: 150,
            daysRemaining: 2
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("All Complete") {
    VStack {
        UnifiedWeeklyStatsCard(
            strengthCompleted: 5,
            strengthTarget: 5,
            cardioMinutes: 150,
            cardioTarget: 150,
            daysRemaining: 1
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Strength Complete Only") {
    VStack {
        UnifiedWeeklyStatsCard(
            strengthCompleted: 4,
            strengthTarget: 4,
            cardioMinutes: 80,
            cardioTarget: 150,
            daysRemaining: 3
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Just Started") {
    VStack {
        UnifiedWeeklyStatsCard(
            strengthCompleted: 1,
            strengthTarget: 5,
            cardioMinutes: 20,
            cardioTarget: 150,
            daysRemaining: 6
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
