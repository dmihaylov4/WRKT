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

    private let brand = Color(hex: "#F4E409")
    private let pill  = Color(hex: "#333333")
    private let border = Color.white.opacity(0.10)
    let r = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(brand)
                Image(systemName: "bolt.heart.fill")
                    .font(.subheadline.weight(.bold))
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
        .background(r.fill(Color(hex: "#333333")))                // pill
        .overlay(r.stroke(Color.white.opacity(0.10), lineWidth: 1))// border
        .overlay(alignment: .leading) {
          Capsule()
            .fill(Color(hex: "#F4E409"))
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



