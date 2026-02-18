//
//  MuscleChip.swift
//  WRKT
//
//  Simple muscle selection chip for filtering exercises by muscle group
//

import SwiftUI

struct MuscleChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed: Bool = false

    private var fillColor: Color {
        isSelected ? DS.Palette.marone.opacity(0.15) : DS.Semantic.surface50.opacity(0.3)
    }

    private var borderColor: Color {
        isSelected ? DS.Palette.marone.opacity(0.5) : DS.Semantic.border.opacity(0.3)
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.5 : 1
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onTap()
            }
        }) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? DS.Palette.marone : DS.Semantic.textPrimary.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ChamferedRectangle(.small).fill(fillColor))
                .overlay(ChamferedRectangle(.small).stroke(borderColor, lineWidth: borderWidth))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: 50) {
            // On release
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Tap to \(isSelected ? "deselect" : "select") \(title)")
    }
}

// MARK: - Preview

#Preview("Selected") {
    HStack {
        MuscleChip(title: "Chest", isSelected: true, onTap: {})
        MuscleChip(title: "Back", isSelected: false, onTap: {})
        MuscleChip(title: "Shoulders", isSelected: false, onTap: {})
    }
    .padding()
    .background(DS.Semantic.surface)
}

#Preview("All Muscle Groups") {
    ScrollView(.horizontal) {
        HStack(spacing: 8) {
            MuscleChip(title: "All", isSelected: true, onTap: {})
            MuscleChip(title: "Chest", isSelected: false, onTap: {})
            MuscleChip(title: "Back", isSelected: false, onTap: {})
            MuscleChip(title: "Shoulders", isSelected: false, onTap: {})
            MuscleChip(title: "Biceps", isSelected: false, onTap: {})
            MuscleChip(title: "Triceps", isSelected: false, onTap: {})
        }
        .padding()
    }
    .background(DS.Semantic.surface)
}
