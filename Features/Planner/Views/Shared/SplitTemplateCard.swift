//
//  SplitTemplateCard.swift
//  WRKT
//
//  Reusable card for displaying split templates

import SwiftUI

struct SplitTemplateCard: View {
    let template: SplitTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.icon)
                        .dsFont(.title2)
                        .foregroundStyle(DS.Palette.marone)
                        .frame(width: 44, height: 44)
                        .background(DS.Palette.marone.opacity(0.1), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .dsFont(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Label("\(template.recommendedFrequency) days/week", systemImage: "calendar")
                            Text("•")
                            Text(template.difficulty.rawValue)
                        }
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .dsFont(.title3)
                            .foregroundStyle(DS.Palette.marone)
                    }
                }

                Text(template.description)
                    .dsFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label(template.focus, systemImage: "target")
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(template.days.count) workouts")
                        .dsFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(isSelected ? DS.Palette.marone.opacity(0.1) : DS.Semantic.surface)
            .clipShape(ChamferedRectangle(.medium))
            .overlay(
                ChamferedRectangle(.medium)
                    .stroke(isSelected ? DS.Palette.marone : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
