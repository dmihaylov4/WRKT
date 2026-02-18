import SwiftUI


struct GoalOnboardingCard: View {
    let onSet: () -> Void

    init(onSet: @escaping () -> Void = {}) {
        self.onSet = onSet
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set your weekly goal")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Customize your fitness targets and track progress")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(DS.Theme.accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [DS.Theme.cardTop, DS.Theme.cardBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .foregroundStyle(.white)
    }
}

// Color(hex:) is now available from DS.swift, no need to redefine
