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
                    .font(.title3)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DS.card)
            .cornerRadius(12)
        }
    }
}

