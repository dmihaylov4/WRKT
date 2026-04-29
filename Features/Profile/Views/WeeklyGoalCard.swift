// WeeklyGoalCard.swift
import SwiftUI

struct WeeklyGoalCard: View {
    let progress: WeeklyProgress
    let onTap: () -> Void

    private var paceChip: (label: String, color: Color) {
        switch progress.paceStatus {
        case .ahead:   return ("Ahead", .green)
        case .onTrack: return ("On track", .green)
        case .behind:  return ("Behind", .orange)
        }
    }

    private var leftLine: String {
        var parts: [String] = []
        if progress.minutesLeft > 0 {
            parts.append("\(progress.minutesLeft) min left")
        }
        if progress.strengthDaysLeft > 0 {
            parts.append("\(progress.strengthDaysLeft) strength day\(progress.strengthDaysLeft == 1 ? "" : "s") left")
        }
        return parts.isEmpty ? "Weekly targets complete" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Left: MVPA ring
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress.mvpaPct)
                        .stroke(
                            AngularGradient(colors: [DS.Theme.accent,
                                                     DS.Theme.accent.opacity(0.7),
                                                     DS.Theme.accent],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(progress.mvpaPct * 100))%")
                            .dsFont(.headline, monospacedDigits: true)
                        Text("MVPA").dsFont(.caption2).opacity(0.7)
                    }
                }
                .frame(width: 72, height: 72)

                // Right: text + bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("This week").dsFont(.headline)
                        PaceChip(text: paceChip.label, color: paceChip.color)
                    }

                    // “112/150 min • 2/3 strength”
                    Text("\(progress.mvpaDone)/\(progress.mvpaTarget) min  •  \(progress.strengthDaysDone)/\(progress.strengthTarget) strength")
                        .dsFont(.subheadline, monospacedDigits: true)
                        .foregroundStyle(.secondary)

                    // bar for MVPA minutes
                    GeometryReader { geo in
                        let w = geo.size.width
                        let p = CGFloat(progress.mvpaPct)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(DS.Theme.accent).frame(width: max(8, w * p))
                        }
                    }
                    .frame(height: 8)

                    // Left to go (or done)
                    Text(leftLine)
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                     
                }

                Spacer()

                Image(systemName: "arrow.up.right.circle.fill")
                    .dsFont(.title2)
                    .foregroundStyle(DS.Theme.accent)
            }
            .padding(16)
            .background(
                ChamferedRectangle(.xl)
                    .fill(Color.black)
                    .overlay(ChamferedRectangle(.xl).stroke(.white.opacity(0.08), lineWidth: 1))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

private struct PaceChip: View {
    let text: String; let color: Color
    var body: some View {
        Text(text)
            .dsFont(.caption2, weight: .semibold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
            .foregroundStyle(color)
    }
}

struct WeeklyStreakCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let progress: WeeklyProgress?
    let isFrozen: Bool

    private var isOnTrack: Bool {
        guard let progress = progress else { return false }
        return progress.paceStatus == .ahead || progress.paceStatus == .onTrack
    }

    private var statusColor: Color {
        if currentStreak == 0 { return .gray }
        if isFrozen { return .cyan }
        if isOnTrack { return .green }
        return .orange
    }

    private var statusIcon: String {
        if currentStreak == 0 { return "flame" }
        if isFrozen { return "snowflake" }
        if isOnTrack { return "checkmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusText: String {
        if currentStreak == 0 { return "Start your streak!" }
        if isFrozen { return "Freeze active" }
        if let progress = progress {
            let strengthMet = progress.strengthDaysDone >= progress.strengthTarget
            let mvpaMet = progress.mvpaTarget > 0 ? (progress.mvpaDone >= progress.mvpaTarget) : true
            let weekComplete = strengthMet || mvpaMet
            let isSuperWeek = strengthMet && mvpaMet

            if isSuperWeek {
                return "Super week complete!"
            } else if weekComplete {
                // Encourage completing the other goal
                if strengthMet {
                    return "Finish active minutes for super streak"
                } else {
                    return "Finish strength days for super streak"
                }
            } else {
                return "Complete this week to continue"
            }
        }
        return "Keep it going!"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Goal Streak")
                        .dsFont(.headline)
                    Text(statusText)
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Stats with Super Streak
            HStack(spacing: 16) {
                // Current streak
                VStack(spacing: 6) {
                    Text("Current")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)

                    Text("\(currentStreak)")
                        .font(DS.Typography.custom(size: 36, weight: .bold))
                        .foregroundStyle(DS.Theme.accent)

                    Text("week\(currentStreak == 1 ? "" : "s")")
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 70)
                    .background(Color.white.opacity(0.1))

                // Super Streak
                VStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Theme.accent)
                        Text("Super")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.8))
                            .textCase(.uppercase)
                    }

                    Text("\(RewardsEngine.shared.progress?.weeklySuperStreakCurrent ?? 0)")
                        .font(DS.Typography.custom(size: 28, weight: .bold))
                        .foregroundStyle(DS.Theme.accent)

                    Text("week\(RewardsEngine.shared.progress?.weeklySuperStreakCurrent ?? 0 == 1 ? "" : "s")")
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 70)
                    .background(Color.white.opacity(0.1))

                // Longest streak
                VStack(spacing: 6) {
                    Text("Longest")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)

                    Text("\(longestStreak)")
                        .font(DS.Typography.custom(size: 28, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("week\(longestStreak == 1 ? "" : "s")")
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Progress bar (weeks toward next milestone)
            if currentStreak > 0 {
                let nextMilestone = [2, 4, 8, 12, 26, 52].first { $0 > currentStreak } ?? 52
                let progress = Double(currentStreak) / Double(nextMilestone)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Next milestone: \(nextMilestone) weeks")
                            .dsFont(.caption, weight: .medium)
                        Spacer()
                        Text("\(currentStreak)/\(nextMilestone)")
                            .dsFont(.caption, monospacedDigits: true)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.15))
                            Capsule()
                                .fill(DS.Theme.accent)
                                .frame(width: max(8, geo.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            ChamferedRectangle(.xl)
                .fill(Color.black)
                .overlay(ChamferedRectangle(.xl).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .foregroundStyle(.white)
    }
}

// Color(hex:) is now available from DS.swift, no need to redefine
