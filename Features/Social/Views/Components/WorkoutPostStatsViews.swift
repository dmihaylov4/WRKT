//
//  WorkoutPostStatsViews.swift
//  WRKT
//
//  Shared stat formatting helpers for workout post views.
//

import SwiftUI
import Kingfisher

struct WorkoutPostStatsViews {
    static func duration(for workout: CompletedWorkout) -> TimeInterval? {
        if let hkDuration = workout.matchedHealthKitDuration {
            return TimeInterval(hkDuration)
        }
        guard let startedAt = workout.startedAt else { return nil }
        return workout.date.timeIntervalSince(startedAt)
    }

    static func durationText(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "Unknown" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func formatCardioDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d", h, m) }
        return String(format: "%d:%02d", m, s)
    }

    static func formatPace(_ secPerKm: Double) -> String {
        let minutes = Int(secPerKm) / 60
        let seconds = Int(secPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 { return String(format: "%.1fk", volume / 1000) }
        return String(format: "%.0f", volume)
    }

    static func exerciseCount(for workout: CompletedWorkout) -> Int {
        workout.entries.count
    }

    static func totalSets(for workout: CompletedWorkout) -> Int {
        workout.entries.reduce(0) { $0 + $1.sets.count }
    }

    static func totalVolume(for workout: CompletedWorkout) -> Double {
        workout.entries.reduce(0.0) { total, entry in
            total + entry.sets.reduce(0.0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
        }
    }
}
