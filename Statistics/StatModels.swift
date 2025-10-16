//
//  StatModels.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//

// StatsModels.swift
import Foundation
import SwiftData

@Model
final class WeeklyTrainingSummary {
    @Attribute(.unique) var key: String      // "yyyy-ww" (ISO week)
    var weekStart: Date                      // normalized to local start-of-week
    var totalVolume: Double                  // Σ (reps * weightKg)
    var sessions: Int
    var totalSets: Int
    var totalReps: Int
    var minutes: Int

    init(key: String, weekStart: Date, totalVolume: Double, sessions: Int, totalSets: Int, totalReps: Int, minutes: Int) {
        self.key = key
        self.weekStart = weekStart
        self.totalVolume = totalVolume
        self.sessions = sessions
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.minutes = minutes
    }
}

@Model
final class ExerciseVolumeSummary {
    @Attribute(.unique) var key: String
    var exerciseID: String
    var weekStart: Date
    var volume: Double

    init(exerciseID: String, weekStart: Date, volume: Double) {
        self.exerciseID = exerciseID
        self.weekStart = weekStart
        self.volume = volume
        self.key = "\(exerciseID)|\(Self.weekKey(from: weekStart))"
    }

    static func weekKey(from weekStart: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
        let y = comps.yearForWeekOfYear ?? 0
        let w = comps.weekOfYear ?? 0
        return "\(y)-\(w)"
    }
}

@Model
final class PRStamp { // if you already have DexStamp for PRs, use that; otherwise this is minimal.
    @Attribute(.unique) var id: String      // "<exerciseID>|<yyyy-MM-dd>"
    var exerciseID: String
    var when: Date
    var value: Double? // e.g., best 1RM or best working set weight

    init(exerciseID: String, when: Date, value: Double?) {
        self.exerciseID = exerciseID
        self.when = when
        self.value = value
        let day = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: when))
        self.id = "\(exerciseID)|\(day)"
    }
}
