//
//  Step3RestDays.swift
//  WRKT
//
//  Step 3: Choose rest day placement

import SwiftUI

struct Step3RestDays: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("When do you want rest days?")
                    .font(.title2.bold())

                Text("Choose how to schedule your recovery days.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            VStack(spacing: 16) {
                RestDayOptionCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "After Each Workout",
                    description: "Alternate between training and rest days for maximum recovery",
                    isSelected: config.restDayPlacement == .afterEachWorkout
                ) {
                    config.restDayPlacement = .afterEachWorkout
                    onAutoAdvance()
                }

                RestDayOptionCard(
                    icon: "calendar.badge.clock",
                    title: "Weekends",
                    description: "Rest on Saturday and Sunday, train weekdays",
                    isSelected: config.restDayPlacement == .weekends
                ) {
                    config.restDayPlacement = .weekends
                    onAutoAdvance()
                }
            }
            .padding(.horizontal)

            if let placement = config.restDayPlacement {
                VStack(spacing: 8) {
                    Text(restDayDescription(for: placement))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }

    private func restDayDescription(for placement: PlanConfig.RestDayPlacement) -> String {
        switch placement {
        case .afterEachWorkout:
            return "You'll have \(7 - config.trainingDaysPerWeek) rest days alternating with your \(config.trainingDaysPerWeek) training days"
        case .afterEverySecondWorkout:
            return "Rest after every 2 training days for optimal recovery"
        case .weekends:
            return "Training Monday-Friday, resting on weekends"
        case .custom:
            return "Custom rest day schedule"
        }
    }
}
