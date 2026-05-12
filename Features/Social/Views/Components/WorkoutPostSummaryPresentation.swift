import SwiftUI

struct WorkoutPostSummaryPresentation: Equatable {
    let title: String
    let badge: String?
    let stats: [WorkoutPostSummaryStat]
    let biometrics: [String]
    let previewLine: String?
    let breakdownRows: [WorkoutBreakdownRow]

    static func make(for workouts: [CompletedWorkout]) -> WorkoutPostSummaryPresentation {
        WorkoutPostSummaryPresentationBuilder(workouts: workouts).build()
    }
}

struct WorkoutPostSummaryStat: Equatable, Identifiable {
    var id: String { "\(label)-\(value)-\(unit)" }
    let label: String
    let value: String
    let unit: String
}

struct WorkoutBreakdownRow: Equatable, Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let value: String
}

private struct WorkoutPostSummaryPresentationBuilder {
    let workouts: [CompletedWorkout]

    func build() -> WorkoutPostSummaryPresentation {
        let visibleWorkouts = workouts
        let strengthWorkouts = visibleWorkouts.filter { !$0.entries.isEmpty || !$0.isCardioWorkout }
        let cardioWorkouts = visibleWorkouts.filter { $0.entries.isEmpty && $0.isCardioWorkout }
        let badge = visibleWorkouts.count > 1 ? "\(visibleWorkouts.count) workouts" : nil

        if visibleWorkouts.isEmpty {
            return emptySummary()
        }

        if strengthWorkouts.count == visibleWorkouts.count {
            return strengthSummary(workouts: strengthWorkouts, badge: badge)
        }

        if visibleWorkouts.count == 1, let cardio = cardioWorkouts.first {
            return cardioSummary(workout: cardio)
        }

        return mixedSummary(workouts: visibleWorkouts, badge: badge)
    }

    private func emptySummary() -> WorkoutPostSummaryPresentation {
        WorkoutPostSummaryPresentation(
            title: "Workout",
            badge: nil,
            stats: [],
            biometrics: [],
            previewLine: nil,
            breakdownRows: []
        )
    }

    private func strengthSummary(workouts: [CompletedWorkout], badge: String?) -> WorkoutPostSummaryPresentation {
        let entries = workouts.flatMap(\.entries)
        let totalVolume = workouts.reduce(0.0) { $0 + WorkoutPostStatsViews.totalVolume(for: $1) }
        let totalSets = workouts.reduce(0) { $0 + WorkoutPostStatsViews.totalSets(for: $1) }
        let duration = totalDuration(for: workouts)
        let calories = totalCalories(for: workouts)
        let heartRate = averageHeartRate(for: workouts)

        return WorkoutPostSummaryPresentation(
            title: "Strength Session",
            badge: badge,
            stats: [
                WorkoutPostSummaryStat(label: "Volume", value: WorkoutPostStatsViews.formatVolume(totalVolume), unit: "KG"),
                WorkoutPostSummaryStat(label: "Exercises", value: "\(entries.count)", unit: "EX"),
                WorkoutPostSummaryStat(label: "Sets", value: "\(totalSets)", unit: "TOTAL"),
                WorkoutPostSummaryStat(label: "Duration", value: WorkoutPostStatsViews.durationText(duration), unit: "TIME")
            ],
            biometrics: biometricStrings(heartRate: heartRate, calories: calories),
            previewLine: exercisePreview(entries: entries),
            breakdownRows: entries.prefix(6).map { entry in
                WorkoutBreakdownRow(
                    title: entry.exerciseName,
                    detail: "\(entry.sets.count) \(entry.sets.count == 1 ? "set" : "sets")",
                    value: "\(WorkoutPostStatsViews.formatVolume(entryVolume(entry))) kg"
                )
            }
        )
    }

    private func cardioSummary(workout: CompletedWorkout) -> WorkoutPostSummaryPresentation {
        let distance = workout.matchedHealthKitDistance ?? 0
        let duration = workout.matchedHealthKitDuration
        let pace = duration.flatMap { distance > 0 ? Double($0) / (distance / 1000) : nil }
        let calories = workout.matchedHealthKitCalories
        let title = workout.workoutName ?? workout.workoutTypeDisplayName

        return WorkoutPostSummaryPresentation(
            title: title,
            badge: nil,
            stats: [
                WorkoutPostSummaryStat(label: "Distance", value: String(format: "%.2f", distance / 1000), unit: "KM"),
                WorkoutPostSummaryStat(label: "Duration", value: duration.map(WorkoutPostStatsViews.formatCardioDuration) ?? "0:00", unit: "TIME"),
                WorkoutPostSummaryStat(label: "Pace", value: pace.map(WorkoutPostStatsViews.formatPace) ?? "--", unit: "/KM"),
                WorkoutPostSummaryStat(label: "Calories", value: calories.map { String(format: "%.0f", $0) } ?? "0", unit: "KCAL")
            ],
            biometrics: biometricStrings(heartRate: workout.matchedHealthKitHeartRate, calories: nil),
            previewLine: title,
            breakdownRows: [
                WorkoutBreakdownRow(
                    title: title,
                    detail: WorkoutPostStatsViews.durationText(WorkoutPostStatsViews.duration(for: workout)),
                    value: calories.map { "\(Int($0)) kcal" } ?? ""
                )
            ]
        )
    }

    private func mixedSummary(workouts: [CompletedWorkout], badge: String?) -> WorkoutPostSummaryPresentation {
        let totalVolume = workouts.reduce(0.0) { $0 + WorkoutPostStatsViews.totalVolume(for: $1) }
        let duration = totalDuration(for: workouts)
        let calories = totalCalories(for: workouts)
        let heartRate = averageHeartRate(for: workouts)

        return WorkoutPostSummaryPresentation(
            title: "Strength + Cardio",
            badge: badge,
            stats: [
                WorkoutPostSummaryStat(label: "Volume", value: WorkoutPostStatsViews.formatVolume(totalVolume), unit: "KG"),
                WorkoutPostSummaryStat(label: "Workouts", value: "\(workouts.count)", unit: "TOTAL"),
                WorkoutPostSummaryStat(label: "Duration", value: WorkoutPostStatsViews.durationText(duration), unit: "TIME"),
                WorkoutPostSummaryStat(label: "Calories", value: calories.map { String(format: "%.0f", $0) } ?? "0", unit: "KCAL")
            ],
            biometrics: biometricStrings(heartRate: heartRate, calories: calories),
            previewLine: workouts.prefix(3).map { $0.workoutName ?? $0.workoutTypeDisplayName }.joined(separator: ", "),
            breakdownRows: workouts.prefix(6).map { workout in
                WorkoutBreakdownRow(
                    title: workout.workoutName ?? workout.workoutTypeDisplayName,
                    detail: WorkoutPostStatsViews.durationText(WorkoutPostStatsViews.duration(for: workout)),
                    value: workout.matchedHealthKitCalories.map { "\(Int($0)) kcal" } ?? "\(WorkoutPostStatsViews.totalSets(for: workout)) sets"
                )
            }
        )
    }

    private func totalDuration(for workouts: [CompletedWorkout]) -> TimeInterval? {
        let durations = workouts.compactMap { WorkoutPostStatsViews.duration(for: $0) }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    private func totalCalories(for workouts: [CompletedWorkout]) -> Double? {
        let values = workouts.compactMap(\.matchedHealthKitCalories)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func averageHeartRate(for workouts: [CompletedWorkout]) -> Double? {
        let values = workouts.compactMap(\.matchedHealthKitHeartRate)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func biometricStrings(heartRate: Double?, calories: Double?) -> [String] {
        var strings: [String] = []
        if let heartRate {
            strings.append("\(Int(heartRate.rounded())) BPM")
        }
        if let calories {
            strings.append("\(Int(calories.rounded())) kcal")
        }
        return strings
    }

    private func exercisePreview(entries: [WorkoutEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let names = entries.prefix(2).map(\.exerciseName)
        let remaining = entries.count - names.count
        if remaining > 0 {
            return "\(names.joined(separator: ", ")) + \(remaining) more"
        }
        return names.joined(separator: ", ")
    }

    private func entryVolume(_ entry: WorkoutEntry) -> Double {
        entry.sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }
    }
}
