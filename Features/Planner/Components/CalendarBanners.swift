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
            Image("streak-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Color.black)
                .padding(8)
                .background(DS.Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)-day streak")
                    .dsFont(.headline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)
                Text("Don't break the chain.")
                    .dsFont(.caption)
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
            Image("streak-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Color.black)
                .padding(8)
                .background(DS.Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)-week goal streak")
                    .dsFont(.headline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)
                Text("Keep meeting your weekly goal!")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: min(Double(streak)/12.0, 1.0))
                    .tint(DS.Theme.accent)
                    .frame(width: 80)
                Text("Next: 12 wks")
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Current Week Progress Banner
/// Uses alternate chamfered corners (top-left/bottom-right) to contrast with the streak banner above
struct CurrentWeekProgressBanner: View {
    let progress: WeeklyProgress
    let isFrozenWeek: Bool

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
        isFrozenWeek || strengthGoalMet || mvpaGoalMet
    }

    private var weekLabel: String {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekStart = calendar.startOfDay(for: calendar.startOfWeek(for: now, anchorWeekday: 2))

        if calendar.isDate(progress.weekStart, inSameDayAs: currentWeekStart) {
            return "This Week"
        } else {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: progress.weekStart) ?? progress.weekStart
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: progress.weekStart)) - \(formatter.string(from: weekEnd))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(weekLabel)
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                // Show super streak encouragement or achievement
                if isSuperWeek {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .dsFont(.caption2)
                        Text("Super Week!")
                            .dsFont(.caption2, weight: .bold)
                    }
                    .foregroundStyle(DS.Theme.accent)
                } else if isFrozenWeek {
                    HStack(spacing: 4) {
                        Image(systemName: "snowflake")
                            .dsFont(.caption2)
                        Text("Freeze Protected")
                            .dsFont(.caption2, weight: .bold)
                    }
                    .foregroundStyle(.blue)
                } else if weekGoalMet {
                    // Encourage completing the other goal for super streak
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .dsFont(.caption2)
                        Text(strengthGoalMet ? "Finish MVPA for Super Streak!" : "Finish Strength for Super Streak!")
                            .dsFont(.caption2, weight: .medium)
                    }
                    .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                // MVPA minutes progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .dsFont(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Text("\(isFrozenWeek ? progress.mvpaTarget : progress.mvpaDone)/\(progress.mvpaTarget) min")
                            .dsFont(.caption2, weight: .medium)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    ProgressView(value: min(Double(isFrozenWeek ? progress.mvpaTarget : progress.mvpaDone), Double(progress.mvpaTarget)), total: Double(progress.mvpaTarget))
                        .tint(isFrozenWeek ? .blue : DS.Theme.accent)
                        .frame(height: 4)
                }

                Divider()
                    .frame(height: 30)

                // Strength days progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill")
                            .dsFont(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Text("\(isFrozenWeek ? progress.strengthTarget : progress.strengthDaysDone)/\(progress.strengthTarget) days")
                            .dsFont(.caption2, weight: .medium)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    ProgressView(value: min(Double(isFrozenWeek ? progress.strengthTarget : progress.strengthDaysDone), Double(progress.strengthTarget)), total: Double(progress.strengthTarget))
                        .tint(isFrozenWeek ? .blue : DS.Theme.accent)
                        .frame(height: 4)
                }
            }
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangleAlt(.large))
        .overlay(ChamferedRectangleAlt(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }
}
