//
//  PlanAdherenceCard.swift
//  WRKT
//

import SwiftUI

struct PlanAdherenceCard: View {
    let weeklyAdherence: [PlanAdherence]  // 4 entries, index 0 = oldest, 3 = current
    let currentWeekEnded: Bool

    private var current: PlanAdherence? { weeklyAdherence.last }

    private var rollingPlanned: Int { weeklyAdherence.reduce(0) { $0 + $1.plannedSessions } }
    private var rollingCompleted: Int { weeklyAdherence.reduce(0) { $0 + $1.completedOnPlan } }
    private var rollingRate: Double {
        rollingPlanned > 0 ? Double(rollingCompleted) / Double(rollingPlanned) : 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan adherence")
                .dsFont(.footnote, weight: .semibold)
                .foregroundStyle(DS.Semantic.textSecondary)

            if let current {
                currentWeekRow(current)
            }

            if rollingPlanned > 0 {
                HStack {
                    Text("4-week: \(rollingCompleted) of \(rollingPlanned)")
                        .dsFont(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", rollingRate * 100))
                        .dsFont(.caption2, weight: .semibold)
                        .foregroundStyle(rollingRate >= 0.8 ? DS.Semantic.brand : DS.Semantic.textSecondary)
                }
            }
        }
        .padding(12)
        .background(DS.Semantic.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }

    @ViewBuilder
    private func currentWeekRow(_ adherence: PlanAdherence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(adherence.completedOnPlan) of \(adherence.plannedSessions) planned")
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)
                Spacer()
                statusLabel(adherence)
            }

            ProgressView(value: adherence.plannedSessions > 0 ? Double(adherence.completedOnPlan) / Double(adherence.plannedSessions) : 1.0)
                .tint(DS.Semantic.brand)
        }
    }

    @ViewBuilder
    private func statusLabel(_ adherence: PlanAdherence) -> some View {
        if currentWeekEnded && adherence.missedSessions > 0 {
            Text("Missed: \(adherence.missedSessions)")
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
        } else if !currentWeekEnded {
            let remaining = adherence.plannedSessions - adherence.completedOnPlan
            if remaining > 0 {
                Text("\(remaining) remaining")
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
    }
}
