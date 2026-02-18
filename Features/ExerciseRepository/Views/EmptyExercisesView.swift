//
//  EmptyExercisesView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// EmptyExercisesView.swift
import SwiftUI

struct EmptyExercisesView: View {
    let title: String
    let message: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)

            Button {
                onClear()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                    Text("Clear filters")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.Palette.marone.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(DS.Semantic.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Semantic.border.opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
