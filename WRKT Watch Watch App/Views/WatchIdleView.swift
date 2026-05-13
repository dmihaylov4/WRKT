// WatchIdleView.swift
// Shown when no workout or rest timer is active.

import SwiftUI

struct WatchIdleView: View {
    private let accent = Color(hex: "#CCFF00")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("VOLIA")
                    .font(.barlow(28, weight: .black))
                    .foregroundColor(accent)
                    .tracking(3)

                Text("Workouts on iPhone")
                    .font(.barlow(11, weight: .regular))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
