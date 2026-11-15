//
//  CutPlanWeekView.swift
//  WRKT
//
//  "Weekly goal" in the Cut language: a modest hero with the week under it, the goal as the
//  V mark carrying data (left arm strength, right arm cardio) beside its two numbers, as on the
//  Train tab, then the goal streak as slanted segments and the push and pull note as plain text.
//  Takes plain values and closures (see CutPlanWeekHost for live data).
//

import SwiftUI

struct CutPlanWeekView: View {
    let model: CutPlanWeekModel
    var dismissBalance: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Weekly goal")
                    .cutHero(.xs, minimumScaleFactor: 0.6)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if let goal = model.goal {
                    Text(goal.weekLabel)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .padding(.top, 6)
                    CutPlanWeekGoalView(goal: goal).padding(.top, 28)
                }
                if model.showsEmpty {
                    Text("No weekly goal set yet.")
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .padding(.top, 16)
                }
                if let streak = model.streak {
                    streakSection(streak).padding(.top, 36)
                }
                if let message = model.balanceMessage {
                    balanceSection(message).padding(.top, 36)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    private func streakSection(_ streak: CutPlanWeekModel.Streak) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Goal streak")
            CutHairline()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(streak.value)
                        .font(DS.Cut.Typography.numeral(.medium))
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                    Text(streak.label)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                CutSegmentProgress(total: streak.totalSegments, filled: streak.filledSegments, thickness: .thin,
                                   accessibilityLabel: Text("Weeks to the next milestone"))
                Text(streak.milestoneLine)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func balanceSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Push and pull")
            CutHairline()
            Text(message)
                .cutFont(.body)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Button("Dismiss") {
                Haptics.light()
                dismissBalance()
            }
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .padding(.top, 6)
        }
    }
}

/// The V mark beside its two numbers, as the Train tab draws the weekly goal, then the status.
/// Also drawn by the Me tab's weekly goal page (CutWeeklyGoalView).
struct CutPlanWeekGoalView: View {
    let goal: CutPlanWeekModel.Goal

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Large text: the numbers go under the mark and each unit under its number.
                    VStack(alignment: .leading, spacing: 18) {
                        mark.frame(width: 150)
                        VStack(alignment: .leading, spacing: 14) {
                            stacked(goal.strengthValue, "strength")
                            stacked(goal.cardioValue, "cardio min")
                        }
                    }
                } else {
                    HStack(spacing: 22) {
                        mark.frame(minWidth: 96, maxWidth: 150)
                        numbers.layoutPriority(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            if let status = goal.status {
                Text(status)
                    .font(DS.Cut.Typography.font(.secondary).weight(goal.isSuperWeek ? .bold : .medium))
                    .foregroundStyle(goal.isSuperWeek ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(goal.accessibilityLabel))
    }

    private var mark: some View {
        VMarkProgress(left: goal.strengthFraction, right: goal.cardioFraction,
                      accessibilityLabel: goal.accessibilityLabel)
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(goal.strengthValue, "strength")
            line(goal.cardioValue, "cardio min")
        }
        .fixedSize()
    }

    private func stacked(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .cutNumeral(.medium)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(unit)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
        }
    }

    private func line(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(DS.Cut.Typography.numeral(.medium))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(unit)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
        }
    }
}
