//
//  RestTimerHeroContent.swift
//  WRKT
//
//  Dynamic hero content for active workout with rest timer
//

import SwiftUI

struct RestTimerHeroContent: View {
    let exercises: Int
    let completedSets: Int
    let startDate: Date
    let restTimeRemaining: TimeInterval
    let exerciseName: String
    let onSkipRest: () -> Void
    let onAddExercise: () -> Void
    let onViewWorkout: () -> Void
    var onExtendRest: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Compact header
            compactHeader
                .padding(.top, 32)
                .padding(.horizontal, 20)

            // Center: Rest timer (clean & prominent)
            Spacer()
            restTimerSection
            Spacer()

            // Bottom: Simple actions
            actionButtons
                .padding(.bottom, 32)
                .padding(.horizontal, 20)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Rest indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(DS.Theme.accent)
                    .frame(width: 8, height: 8)

                Text("REST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DS.Theme.accent)
            }

            // Exercise name
            Text(exerciseName)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Semantic.textSecondary)
                .lineLimit(1)

            Spacer()

            // Workout duration (minimal)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                let h = Int(elapsed) / 3600
                let m = (Int(elapsed) % 3600) / 60
                let s = Int(elapsed) % 60

                if h > 0 {
                    Text(String(format: "%d:%02d:%02d", h, m, s))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    Text(String(format: "%02d:%02d", m, s))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
        }
    }

    private var restTimerSection: some View {
        VStack(spacing: 16) {
            // Large timer display
            Text(formatTime(restTimeRemaining))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.Theme.accent)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(DS.Theme.accent.opacity(0.15))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(DS.Theme.accent)
                        .frame(width: geo.size.width * pulseProgress, height: 4)
                        .animation(.linear(duration: 1), value: restTimeRemaining)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 40)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Skip rest
            Button(action: onSkipRest) {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // +15s extend
            Button { onExtendRest?() } label: {
                Text("+15s")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Add exercise
            Button(action: onAddExercise) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(DS.Semantic.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Semantic.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // View workout
            Button(action: onViewWorkout) {
                HStack(spacing: 4) {
                    Text("View")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(DS.Semantic.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Semantic.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var pulseProgress: CGFloat {
        // Show progress ring as countdown (full at start, empty at end)
        let progress = restTimeRemaining / 180.0 // Assuming max 3 min rest
        return max(0, min(1, progress))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    RestTimerHeroContent(
        exercises: 5,
        completedSets: 12,
        startDate: Date().addingTimeInterval(-2700), // 45 min ago
        restTimeRemaining: 150, // 2:30
        exerciseName: "Bench Press",
        onSkipRest: {},
        onAddExercise: {},
        onViewWorkout: {}
    )
    .frame(height: UIScreen.main.bounds.height * 0.28)
    .background(Color.black)
    .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(DS.Theme.accent, lineWidth: 1.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .padding()
}
