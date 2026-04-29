//
//  MuscleGroupButton.swift
//  WRKT
//
//  Compact button for quick muscle group access
//

import SwiftUI

struct MuscleGroupButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .dsFont(.title3)
                    .foregroundStyle(.primary)

                Text(title)
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DS.card)
            .cornerRadius(12)
        }
    }
}

