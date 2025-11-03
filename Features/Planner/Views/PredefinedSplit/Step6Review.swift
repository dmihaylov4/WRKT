//
//  Step6Review.swift
//  WRKT
//
//  Step 6: Review and generate plan

import SwiftUI

struct Step6Review: View {
    @ObservedObject var config: PlanConfig
    let onGenerate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review your plan")
                    .font(.title2.bold())
                    .padding(.horizontal)

                // Start date picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("When do you want to start?")
                        .font(.headline)

                    DatePicker(
                        "Start Date",
                        selection: $config.startDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(DS.Palette.marone)
                }
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)

                // Configuration summary
                if let template = config.selectedTemplate {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(.headline)

                        Divider()

                        HStack {
                            Text("Split:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(template.name)
                                .bold()
                        }

                        HStack {
                            Text("Training Frequency:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(config.trainingDaysPerWeek) days/week")
                                .bold()
                        }

                        HStack {
                            Text("Rest Days:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(7 - config.trainingDaysPerWeek) days/week")
                                .bold()
                        }

                        HStack {
                            Text("Program Length:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(config.programWeeks) weeks")
                                .bold()
                        }

                        if config.includeDeload {
                            HStack {
                                Text("Deload Weeks:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Every 4th week")
                                    .bold()
                            }
                        }

                        HStack {
                            Text("Start Date:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(config.startDate.formatted(date: .abbreviated, time: .omitted))
                                .bold()
                        }
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
    }
}
