//
//  ExerciseListComponents.swift
//  WRKT
//
//  Small reusable components for exercise lists
//

import SwiftUI

// MARK: - Meta Pill

struct MetaPill: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.18), in: ChamferedRectangle(.small))
        .overlay(ChamferedRectangle(.small).stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Favorite Heart Button

struct FavoriteHeartButton: View {
    @EnvironmentObject private var favs: FavoritesStore
    let exerciseID: String
    var size: CGFloat = 22

    var body: some View {
        let isFav = favs.contains(exerciseID)
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                favs.toggle(exerciseID)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isFav ? DS.Palette.marone : .secondary)
                .symbolEffect(.bounce, value: isFav)
                .scaleEffect(isFav ? 1.0 : 0.95)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFav ? .isSelected : [])
    }
}

// MARK: - Custom Exercise Badge

struct CustomExerciseBadge: View {
    var body: some View {
        Text("CUSTOM")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DS.Palette.marone, in: ChamferedRectangle(.micro))
            .overlay(ChamferedRectangle(.micro).stroke(DS.Palette.marone.opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Mechanic Pill

struct MechanicPill: View {
    let mechanic: String

    private var displayText: String {
        mechanic.lowercased() == "compound" ? "Compound" : "Isolation"
    }

    private var color: Color {
        mechanic.lowercased() == "compound" ? DS.Charts.legs : DS.Charts.push
    }

    var body: some View {
        Text(displayText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: ChamferedRectangle(.small))
            .overlay(ChamferedRectangle(.small).stroke(color.opacity(0.3), lineWidth: 1))
    }
}
