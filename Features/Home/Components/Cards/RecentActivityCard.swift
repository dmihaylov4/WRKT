//
//  RecentActivityCard.swift
//  WRKT
//
//  Combined card showing both strength and cardio activities
//

import SwiftUI

struct RecentActivityCard: View {
    let summary: RecentActivitySummary
    var onWorkoutTap: ((CompletedWorkout) -> Void)? = nil
    var onCardioTap: ((Run) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with "Recent Activity" label (no arrow for this card)
            HStack {
                Text("Recent Activity")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if summary.hasBoth {
                // Show both side by side (2 columns) - each independently tappable
                HStack(spacing: 8) {
                    // Strength column (button with chevron)
                    if let workout = summary.lastWorkout {
                        Button {
                            Haptics.light()
                            onWorkoutTap?(workout)
                        } label: {
                            strengthSection(workout: workout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ClickableSectionStyle())
                    }

                    // Cardio column (button with chevron)
                    if let cardio = summary.lastCardio {
                        Button {
                            Haptics.light()
                            onCardioTap?(cardio)
                        } label: {
                            cardioSection(run: cardio)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ClickableSectionStyle())
                    }
                }
            } else if let workout = summary.lastWorkout {
                // Only strength - full width
                strengthSection(workout: workout)
            } else if let cardio = summary.lastCardio {
                // Only cardio - full width
                cardioSection(run: cardio)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            DS.tint.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Strength Section

    @ViewBuilder
    private func strengthSection(workout: CompletedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon + Type + Chevron
            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill")
                    .font(.caption2)
                    .foregroundStyle(DS.tint)

                Text("Strength")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // Chevron to indicate clickable
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.tint)
            }

            // Workout name (auto-classified)
            Text(workoutName(for: workout))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Date
            Text(relativeDateString(for: workout.date))
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Compact stats
            HStack(spacing: 8) {
                // Sets
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalSets(for: workout))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("sets")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                // Volume
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatVolume(totalVolume(for: workout)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("kg")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Cardio Section

    @ViewBuilder
    private func cardioSection(run: Run) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon + Type + Chevron
            HStack(spacing: 4) {
                Image(systemName: activityIcon(for: run))
                    .font(.caption2)
                    .foregroundStyle(DS.Semantic.warning)

                Text("Cardio")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // Chevron to indicate clickable
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Semantic.warning)
            }

            // Activity type
            Text(activityType(for: run))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Date
            Text(relativeDateString(for: run.date))
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Compact stats
            HStack(spacing: 8) {
                // Distance
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", run.distanceKm))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("km")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                // Duration
                VStack(alignment: .leading, spacing: 2) {
                    Text(durationFormatted(run: run))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("time")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func relativeDateString(for date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)
        let daysSince = calendar.dateComponents([.day], from: day, to: today).day ?? 0

        if daysSince == 0 {
            return "Today"
        } else if daysSince == 1 {
            return "Yesterday"
        } else {
            return "\(daysSince) days ago"
        }
    }

    private func workoutName(for workout: CompletedWorkout) -> String {
        if let name = workout.workoutName {
            return name
        }

        // Auto-classify based on exercises
        let muscles = Set(workout.entries.flatMap { $0.muscleGroups })
        let upperMuscles: Set<String> = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms"]
        let lowerMuscles: Set<String> = ["Quads", "Hamstrings", "Glutes", "Calves"]

        let upperCount = muscles.intersection(upperMuscles).count
        let lowerCount = muscles.intersection(lowerMuscles).count

        if upperCount > 0 && lowerCount == 0 {
            return "Upper Body"
        } else if lowerCount > 0 && upperCount == 0 {
            return "Lower Body"
        } else if upperCount > 0 && lowerCount > 0 {
            return "Full Body"
        } else {
            return "Workout"
        }
    }

    private func totalVolume(for workout: CompletedWorkout) -> Double {
        workout.entries.reduce(0.0) { total, entry in
            total + entry.sets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
        }
    }

    private func totalSets(for workout: CompletedWorkout) -> Int {
        workout.entries.reduce(0) { total, entry in
            total + entry.sets.filter { $0.isCompleted }.count
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK", volume / 1000)
        } else {
            return "\(volume.safeInt)"
        }
    }

    private func activityType(for run: Run) -> String {
        if let workoutType = run.workoutType {
            return workoutType
        }
        return "Cardio"
    }

    private func activityIcon(for run: Run) -> String {
        let type = run.workoutType?.lowercased() ?? ""
        if type.contains("run") {
            return "figure.run"
        } else if type.contains("walk") {
            return "figure.walk"
        } else if type.contains("cycl") || type.contains("bike") {
            return "figure.outdoor.cycle"
        } else if type.contains("hik") {
            return "figure.hiking"
        } else if type.contains("swim") {
            return "figure.pool.swim"
        } else {
            return "heart.fill"
        }
    }

    private func durationFormatted(run: Run) -> String {
        let minutes = run.durationSec / 60
        let seconds = run.durationSec % 60

        if minutes < 60 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Button Style

/// Custom button style for clickable card sections
struct ClickableSectionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? DS.Semantic.fillSubtle.opacity(0.8) : DS.Semantic.fillSubtle.opacity(0.5))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

