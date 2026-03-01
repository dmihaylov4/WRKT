//
//  UnifiedWeeklyStatsCard.swift
//  WRKT
//
//  Unified weekly progress card showing both strength and cardio goals
//

import SwiftUI

struct UnifiedWeeklyStatsCard: View {
    let strengthCompleted: Int
    let strengthTarget: Int
    let cardioMinutes: Int
    let cardioTarget: Int
    let daysRemaining: Int

    // NEW: Streak data (optional for backward compatibility)
    var currentStreak: Int = 0
    var nextMilestone: Int? = nil
    var milestoneProgress: Double = 0
    var urgencyLevel: StreakUrgencyLevel? = nil
    var urgencyMessage: String? = nil

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

    private var statusColor: Color {
        if overallPercentage >= 100 {
            return DS.Semantic.success
        } else if overallPercentage >= 75 {
            return DS.tint
        } else if overallPercentage >= 50 {
            return DS.Semantic.warning
        } else {
            return DS.Semantic.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(daysRemaining == 0 ? "Last day!" : "\(daysRemaining) days left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Overall percentage
                Text("\(Int(overallPercentage))%")
                    .font(.system(size: 28, weight: .bold))
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
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(strengthCompleted)/\(strengthTarget) workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        // Progress fill - green when complete, brand color when in progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(strengthPercentage >= 100 ? Color.green : DS.tint)
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
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(cardioMinutes)/\(cardioTarget) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        // Progress fill - green when complete, brand color when in progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(cardioPercentage >= 100 ? Color.green : DS.tint)
                            .frame(
                                width: geometry.size.width * (cardioPercentage / 100.0),
                                height: 6
                            )
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardioPercentage)
                    }
                }
                .frame(height: 6)
            }

            // Status message
            if strengthPercentage >= 100 && cardioPercentage >= 100 {
                Text("All goals complete!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if strengthPercentage >= 100 {
                Text("Strength goal complete!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if cardioPercentage >= 100 {
                Text("Cardio goal complete!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .background(DS.card, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - New Components

    @ViewBuilder
    private func urgencyBanner(level: StreakUrgencyLevel, message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon on the left, aligned with text
            Image(systemName: level == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(level.color)

            // Text aligned to the left
            Text(message)
                .font(.caption.weight(.medium))
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
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)

                Text("Weekly Streak")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(currentStreak) week\(currentStreak == 1 ? "" : "s")")
                    .font(.caption.weight(.bold))
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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(nextMilestone) weeks")
                            .font(.caption2.weight(.medium))
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
