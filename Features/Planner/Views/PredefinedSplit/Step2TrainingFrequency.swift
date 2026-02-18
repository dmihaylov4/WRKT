//
//  Step2TrainingFrequency.swift
//  WRKT
//
//  Step 2: Choose training frequency

import SwiftUI

struct Step2TrainingFrequency: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    private var availableFrequencies: [Int] {
        guard let template = config.selectedTemplate else { return [3, 4, 5, 6] }

        // PPL can be 3x or 6x
        if template.id == "ppl" { return [3, 6] }

        // Upper/Lower is typically 4x (2 upper, 2 lower)
        if template.id == "upper-lower" { return [2, 4] }

        // Full body can be 2-4x
        if template.id == "full-body" { return [2, 3, 4] }

        // Bro split is typically 5x
        if template.id == "bro-split" { return [5, 6] }

        return [3, 4, 5, 6]
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How many days per week?")
                    .font(.title2.bold())

                Text("Choose how often you want to train each week.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                ForEach(availableFrequencies, id: \.self) { days in
                    FrequencyButton(
                        days: days,
                        isSelected: config.trainingDaysPerWeek == days,
                        onTap: {
                            config.trainingDaysPerWeek = days
                        },
                        onAutoAdvance: onAutoAdvance
                    )
                }
            }
            .padding(.horizontal)

            if config.trainingDaysPerWeek > 0 {
                VStack(spacing: 8) {
                    Text("Rest days: \(7 - config.trainingDaysPerWeek) per week")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let template = config.selectedTemplate {
                        Text(frequencyNote(for: template, days: config.trainingDaysPerWeek))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
                .background(DS.Semantic.surface)
                .clipShape(ChamferedRectangle(.medium))
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }

    private func frequencyNote(for template: SplitTemplate, days: Int) -> String {
        if template.id == "ppl" && days == 6 {
            return "Running PPL twice per week for maximum growth"
        } else if template.id == "ppl" && days == 3 {
            return "Each muscle group trained once per week"
        } else if template.id == "upper-lower" && days == 4 {
            return "Upper and lower body each trained twice per week"
        }
        return "Balanced training frequency"
    }
}

// MARK: - Frequency Button Component

struct FrequencyButton: View {
    let days: Int
    let isSelected: Bool
    let onTap: () -> Void
    var onAutoAdvance: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onTap()
            // Auto-advance after selection
            if let advance = onAutoAdvance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    advance()
                }
            }
        }) {
            VStack(spacing: 8) {
                Text("\(days)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .primary)

                Text(days == 1 ? "day" : "days")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(isSelected ? DS.Palette.marone.opacity(0.12) : DS.Semantic.surface)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(isSelected ? DS.Palette.marone : Color.gray.opacity(0.2), lineWidth: isSelected ? 2.5 : 1.5)
            )
            .shadow(color: isSelected ? DS.Palette.marone.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
