//
//  LastWorkoutCard.swift
//  WRKT
//
//  Shows summary of most recent workout
//

import SwiftUI

struct LastWorkoutCard: View {
    let workout: CompletedWorkout

    private var topExercise: WorkoutEntry? {
        // Get exercise with most volume
        workout.entries.max(by: { lhs, rhs in
            let lhsVolume = lhs.sets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
            let rhsVolume = rhs.sets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
            return lhsVolume < rhsVolume
        })
    }

    private var relativeDateString: String {
        let calendar = Calendar.current

        // Get start of day for both dates to compare calendar days
        let workoutDay = calendar.startOfDay(for: workout.date)
        let today = calendar.startOfDay(for: .now)

        let daysSince = calendar.dateComponents([.day], from: workoutDay, to: today).day ?? 0

        if daysSince == 0 {
            return "Today"
        } else if daysSince == 1 {
            return "Yesterday"
        } else {
            return "\(daysSince) days ago"
        }
    }

    private var workoutName: String {
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

    private var totalVolume: Double {
        workout.entries.reduce(0.0) { total, entry in
            total + entry.sets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
        }
    }

    private var totalSets: Int {
        workout.entries.reduce(0) { total, entry in
            total + entry.sets.filter { $0.isCompleted }.count
        }
    }

    private var duration: String? {
        // Use actual workout timing if available
        if let start = workout.startedAt {
            let durationInSeconds = workout.date.timeIntervalSince(start)
            let minutes = (durationInSeconds / 60).safeInt

            if minutes < 60 {
                return "\(minutes) min"
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                return "\(hours)h \(remainingMinutes)m"
            }
        }

        // Fallback to estimated duration from set timing
        if let estimatedDuration = workout.estimatedDuration {
            let minutes = (estimatedDuration / 60).safeInt

            if minutes < 60 {
                return "\(minutes) min"
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                return "\(hours)h \(remainingMinutes)m"
            }
        }

        return nil
    }

    private var topExercises: [WorkoutEntry] {
        // Get top 3 exercises by volume
        workout.entries.sorted { lhs, rhs in
            let lhsVolume = lhs.sets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
            let rhsVolume = rhs.sets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
            return lhsVolume > rhsVolume
        }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with date - reserve space for arrow on left
            HStack {
                Text(relativeDateString)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24) // Space for arrow

                Spacer()

                // Compact stats
                if let durationText = duration {
                    Text(durationText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("\(totalSets) sets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(formatVolume(totalVolume) + " kg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Workout name
            Text(workoutName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.top, 4) // Extra spacing from top row

            // Top 2 exercises only
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(topExercises.prefix(2).enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 6) {
                        Text(entry.exerciseName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // Show PR badge if applicable
                        if hasPR(entry: entry) {
                            Text("PR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange)
                                .cornerRadius(3)
                        }

                        Spacer()

                        // Show best set
                        if let bestSet = entry.sets.filter({ $0.isCompleted }).max(by: { $0.weight < $1.weight }) {
                            Text("\(bestSet.weight.safeInt) × \(bestSet.reps)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Show exercise count if more than 2
                if workout.entries.count > 2 {
                    Text("+ \(workout.entries.count - 2) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            DS.tint.opacity(0.06),
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

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK", volume / 1000)
        } else {
            return "\(volume.safeInt)"
        }
    }

    private func hasPR(entry: WorkoutEntry) -> Bool {
        // Simple heuristic: check if any set has very high weight
        // This is simplified - real implementation would compare against historical data
        return entry.sets.contains { $0.weight > 200 && $0.isCompleted }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        LastWorkoutCard(
            workout: CompletedWorkout(
                date: Date().addingTimeInterval(-86400), // Yesterday
                entries: [
                    WorkoutEntry(
                        exerciseID: "bench-press",
                        exerciseName: "Bench Press",
                        muscleGroups: ["Chest", "Triceps"],
                        sets: [
                            SetInput(reps: 10, weight: 225, tag: .working, autoWeight: false, isCompleted: true),
                            SetInput(reps: 8, weight: 225, tag: .working, autoWeight: false, isCompleted: true),
                            SetInput(reps: 6, weight: 225, tag: .working, autoWeight: false, isCompleted: true)
                        ]
                    ),
                    WorkoutEntry(
                        exerciseID: "incline-press",
                        exerciseName: "Incline Dumbbell Press",
                        muscleGroups: ["Chest", "Shoulders"],
                        sets: [
                            SetInput(reps: 12, weight: 60, tag: .working, autoWeight: false, isCompleted: true)
                        ]
                    ),
                    WorkoutEntry(
                        exerciseID: "tricep-pushdown",
                        exerciseName: "Tricep Pushdown",
                        muscleGroups: ["Triceps"],
                        sets: [
                            SetInput(reps: 15, weight: 50, tag: .working, autoWeight: false, isCompleted: true)
                        ]
                    )
                ]
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
