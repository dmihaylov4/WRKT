//
//  CreateCustomSplitCard.swift
//  WRKT
//
//  Card for creating custom splits

import SwiftUI

struct CreateCustomSplitCard: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DS.Palette.marone)
                        .frame(width: 44, height: 44)
                        .background(DS.Palette.marone.opacity(0.1), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Custom Split")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Build your own program")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DS.Palette.marone)
                    }
                }

                Text("Design a personalized training split tailored to your goals. Choose your own exercises, sets, and rep ranges.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label("Fully customizable", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("2-4 workout parts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(isSelected ? DS.Palette.marone.opacity(0.1) : DS.Semantic.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.Palette.marone : DS.Semantic.border, lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
