//
//  RestDayOptionCard.swift
//  WRKT
//
//  Reusable card for rest day options

import SwiftUI

struct RestDayOptionCard: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(DS.Palette.marone)
                    .frame(width: 50, height: 50)
                    .background(DS.Palette.marone.opacity(isSelected ? 0.15 : 0.1), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Always reserve space for checkmark to prevent text shifting
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Palette.marone)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding()
            .background(isSelected ? DS.Palette.marone.opacity(0.1) : DS.Semantic.surface)
            .clipShape(ChamferedRectangle(.medium))
            .overlay(
                ChamferedRectangle(.medium)
                    .stroke(isSelected ? DS.Palette.marone : Color.gray.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
