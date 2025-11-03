//
//  PremiumChip.swift
//  WRKT
//
//  Reusable chip component with icon and colored glow effect

import SwiftUI

struct PremiumChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                // Base dark background
                Capsule()
                    .fill(Color(hex: "#1A1A1A"))

                // Subtle color glow
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.4), color.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        PremiumChip(title: "Equipment", icon: "dumbbell.fill", color: .blue)
        PremiumChip(title: "Push", icon: "arrow.up.forward", color: .orange)
        PremiumChip(title: "Pull", icon: "arrow.down.backward", color: .green)
        PremiumChip(title: "Core", icon: "arrow.right", color: .purple)
    }
    .padding()
    .background(Color.black)
}
