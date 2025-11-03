//  CalendarBanners.swift
//  WRKT
//
//  Banner components for displaying streaks and progress in the calendar
//

import SwiftUI

// MARK: - Streak Banner (Daily Streak - Legacy)
struct StreakBanner: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, DS.Theme.accent)
                .padding(8)
                .background(DS.Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)-day streak")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                Text("Don't break the chain.")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            ProgressView(value: min(Double(streak)/30.0, 1.0))
                .tint(DS.Theme.accent)
                .frame(width: 80)
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Weekly Streak Banner
struct WeeklyStreakBanner: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, DS.Theme.accent)
                .padding(8)
                .background(DS.Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)-week goal streak")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                Text("Keep meeting your weekly goal!")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            ProgressView(value: min(Double(streak)/12.0, 1.0))
                .tint(DS.Theme.accent)
                .frame(width: 80)
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Current Week Progress Banner
struct CurrentWeekProgressBanner: View {
    let progress: WeeklyProgress

    private var statusColor: Color {
        switch progress.paceStatus {
        case .ahead: return .green
        case .onTrack: return DS.Theme.accent
        case .behind: return .orange
        }
    }

    private var statusIcon: String {
        switch progress.paceStatus {
        case .ahead: return "checkmark.circle.fill"
        case .onTrack: return "circle.fill"
        case .behind: return "exclamationmark.circle.fill"
        }
    }

    private var strengthGoalMet: Bool {
        progress.strengthDaysDone >= progress.strengthTarget
    }

    private var mvpaGoalMet: Bool {
        progress.mvpaTarget > 0 ? (progress.mvpaDone >= progress.mvpaTarget) : true
    }

    private var isSuperWeek: Bool {
        strengthGoalMet && mvpaGoalMet
    }

    private var weekGoalMet: Bool {
        strengthGoalMet || mvpaGoalMet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("This Week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                // Show super streak encouragement or achievement
                if isSuperWeek {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text("Super Week!")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(DS.Theme.accent)
                } else if weekGoalMet {
                    // Encourage completing the other goal for super streak
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.caption2)
                        Text(strengthGoalMet ? "Finish MVPA for Super Streak!" : "Finish Strength for Super Streak!")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                // Strength days progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .font(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Text("\(progress.strengthDaysDone)/\(progress.strengthTarget) days")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    ProgressView(value: Double(progress.strengthDaysDone), total: Double(progress.strengthTarget))
                        .tint(DS.Theme.accent)
                        .frame(height: 4)
                }

                Divider()
                    .frame(height: 30)

                // MVPA minutes progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Text("\(progress.mvpaDone)/\(progress.mvpaTarget) min")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    ProgressView(value: Double(progress.mvpaDone), total: Double(progress.mvpaTarget))
                        .tint(DS.Theme.accent)
                        .frame(height: 4)
                }
            }
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }
}
