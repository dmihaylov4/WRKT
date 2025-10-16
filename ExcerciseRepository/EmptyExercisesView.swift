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
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onClear()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Clear filters")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DS.Palette.marone, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(DS.Semantic.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Semantic.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
}
