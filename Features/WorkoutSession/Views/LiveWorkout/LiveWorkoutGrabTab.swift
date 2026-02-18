// LiveWorkoutGrabTab.swift

import SwiftUI
// LiveWorkoutGrabTab.swift
struct LiveWorkoutGrabTab: View {
    let namespace: Namespace.ID
    let title: String
    let subtitle: String
    let startDate: Date
    let onOpen: () -> Void
    let onCollapse: () -> Void

    @ObservedObject private var restTimer = RestTimerManager.shared

    private let brand = DS.Theme.accent
    private let pill  = DS.Theme.cardBottom
    private let border = DS.Semantic.border
    let r = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(brand)
                Image("symbol")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.black)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    // Show rest timer OR workout timer, not both
                    if restTimer.isActive {
                        RestTimerCompact()
                    } else {
                        WorkoutTimerText(startDate: startDate)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(brand.opacity(0.9))
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()
            Image(systemName: "chevron.up")
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(r.fill(pill))                // pill
        .overlay(r.stroke(border, lineWidth: 1))// border
        .overlay(alignment: .leading) {
          Capsule()
            .fill(brand)
            .frame(width: 4)
            .padding(.leading, 0.5) // tiny inset so it’s clearly inside
        }
        .clipShape(r)                                               // ⬅️ keeps stripe inside the pill
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
        .onTapGesture { onOpen() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open live workout")
        .accessibilityAddTraits(.isButton)
    }
}



