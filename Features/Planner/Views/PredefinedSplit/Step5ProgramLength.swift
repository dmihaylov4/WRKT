//
//  Step5ProgramLength.swift
//  WRKT
//
//  Step 5: Choose program length

import SwiftUI
struct Step5ProgramLength: View {
    @ObservedObject var config: PlanConfig
    let onAutoAdvance: () -> Void

    private let weekOptions = [4, 6, 8, 12]

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How long should this program run?")
                    .font(.title2.bold())

                Text("Choose your training block length.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                ForEach(weekOptions, id: \.self) { weeks in
                    ProgramLengthButton(
                        weeks: weeks,
                        isSelected: config.programWeeks == weeks,
                        isRecommended: weeks == 8
                    ) {
                        config.programWeeks = weeks
                        onAutoAdvance()
                    }
                }
            }
            .padding(.horizontal)

            Toggle("Include deload weeks", isOn: $config.includeDeload)
                .padding()
                .background(DS.Semantic.surface)
                .cornerRadius(12)
                .padding(.horizontal)

            if config.includeDeload {
                Text("Every 4th week will be a deload week at 70% volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }
}

struct ProgramLengthButton: View {
    let weeks: Int
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text("\(weeks)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .primary)

                Text("weeks")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? DS.Palette.marone : .secondary)

                // Empty spacer that's visible only for recommended badge
                Group {
                    if isRecommended {
                        Text("RECOMMENDED")
                            .font(.caption2.bold())
                            .foregroundStyle(isSelected ? DS.Palette.marone : DS.Palette.marone.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isSelected ? DS.Palette.marone.opacity(0.15) : DS.Palette.marone.opacity(0.08),
                                in: Capsule()
                            )
                    } else {
                        Text(" ")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .opacity(0)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(isSelected ? DS.Palette.marone.opacity(0.12) : DS.Semantic.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? DS.Palette.marone : (isRecommended ? DS.Palette.marone.opacity(0.4) : Color.gray.opacity(0.2)),
                        lineWidth: isSelected ? 2.5 : (isRecommended ? 2 : 1.5)
                    )
            )
            .shadow(color: isSelected ? DS.Palette.marone.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 6: Review (Placeholder)
