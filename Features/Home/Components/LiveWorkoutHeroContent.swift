//
//  LiveWorkoutHeroContent.swift
//  WRKT
//
//  Dynamic hero content for active workout (no rest timer)
//

import SwiftUI

struct LiveWorkoutHeroContent: View {
    let exercises: Int
    let completedSets: Int
    let startDate: Date
    let onAddExercise: () -> Void
    let onViewWorkout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Compact stats header
            compactHeader
                .padding(.top, 32)
                .padding(.horizontal, 20)

            // Center: Large CTA
            Spacer()
            addExerciseSection
            Spacer()

            // Bottom: Simple action button
            viewWorkoutButton
                .padding(.bottom, 32)
                .padding(.horizontal, 20)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Live indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(DS.Theme.accent)
                    .frame(width: 8, height: 8)

                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DS.Theme.accent)
            }

            // Stats (inline)
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Text("\(exercises)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)
                    Text("ex")
                        .font(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))

                HStack(spacing: 3) {
                    Text("\(completedSets)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)
                    Text("sets")
                        .font(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            Spacer()

            // Duration (minimal)
            WorkoutDurationText(startDate: startDate)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(DS.Semantic.textSecondary)
        }
    }

    private var addExerciseSection: some View {
        Button(action: onAddExercise) {
            VStack(spacing: 12) {
                // Large plus icon
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DS.Theme.accent)
                    .symbolEffect(.pulse.byLayer, options: .repeating)

                Text("Add Exercise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private var viewWorkoutButton: some View {
        Button(action: onViewWorkout) {
            HStack(spacing: 6) {
                Text("View Workout")
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

/// Live updating duration display
struct WorkoutDurationText: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            let h = Int(elapsed) / 3600
            let m = (Int(elapsed) % 3600) / 60
            let s = Int(elapsed) % 60

            if h > 0 {
                Text(String(format: "%d:%02d:%02d", h, m, s))
            } else {
                Text(String(format: "%02d:%02d", m, s))
            }
        }
    }
}

#Preview {
    LiveWorkoutHeroContent(
        exercises: 5,
        completedSets: 12,
        startDate: Date().addingTimeInterval(-2700), // 45 min ago
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
