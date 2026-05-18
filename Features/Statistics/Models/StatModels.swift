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

    // MARK: - Cardio & MVPA (unified source for WeeklyGoal)
    var appleExerciseMinutes: Int?           // Apple Exercise Time (MVPA) from HealthKit
    var cardioSessions: Int?                 // Running, cycling, swimming, etc.
    var lastHealthSync: Date?                // Last successful HealthKit sync

    var containsBodyweightEstimates: Bool = false  // at least one bodyweight exercise contributed to volume this week

    init(key: String, weekStart: Date, totalVolume: Double, sessions: Int, totalSets: Int, totalReps: Int, minutes: Int,
         appleExerciseMinutes: Int? = nil, cardioSessions: Int? = nil, lastHealthSync: Date? = nil) {
        self.key = key
        self.weekStart = weekStart
        self.totalVolume = totalVolume
        self.sessions = sessions
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.minutes = minutes
        self.appleExerciseMinutes = appleExerciseMinutes
        self.cardioSessions = cardioSessions
        self.lastHealthSync = lastHealthSync
    }

    // Computed: total active time (strength + cardio)
    var totalActiveMinutes: Int {
        minutes + (appleExerciseMinutes ?? 0)
    }

    // Computed: total training sessions (strength + cardio)
    var totalSessions: Int {
        sessions + (cardioSessions ?? 0)
    }
}

@Model
final class DailyAppleExerciseSummary {
    @Attribute(.unique) var key: String      // "yyyy-MM-dd" in local calendar
    var dayStart: Date                       // normalized local start of day
    var minutes: Int                         // Apple Exercise Time minutes for that exact day
    var lastHealthSync: Date?

    init(dayStart: Date, minutes: Int = 0, lastHealthSync: Date? = nil) {
        let normalized = Calendar.current.startOfDay(for: dayStart)
        self.dayStart = normalized
        self.minutes = minutes
        self.lastHealthSync = lastHealthSync

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.key = formatter.string(from: normalized)
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

enum HealthAggregationStore {
    static func appleExerciseMinutes(
        from start: Date,
        to end: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Int {
        let descriptor = FetchDescriptor<DailyAppleExerciseSummary>(
            predicate: #Predicate { $0.dayStart < end }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.reduce(0) { total, row in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: row.dayStart) ?? row.dayStart
            guard row.dayStart < end && dayEnd > start else { return total }
            return total + row.minutes
        }
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

@Model
final class MovingAverage {
    @Attribute(.unique) var key: String      // "yyyy-ww" (ISO week)
    var weekStart: Date
    var fourWeekAvg: Double                  // Rolling 4-week average volume
    var stdDev: Double                       // Standard deviation
    var personalAvg: Double                  // Overall average (all-time)
    var percentChange: Double                // % change from previous week
    var isAboveAverage: Bool                 // Week is above personal average

    init(key: String, weekStart: Date, fourWeekAvg: Double, stdDev: Double, personalAvg: Double, percentChange: Double, isAboveAverage: Bool) {
        self.key = key
        self.weekStart = weekStart
        self.fourWeekAvg = fourWeekAvg
        self.stdDev = stdDev
        self.personalAvg = personalAvg
        self.percentChange = percentChange
        self.isAboveAverage = isAboveAverage
    }
}

// MARK: - Exercise-Level Progression Tracking (Priority 2)

@Model
final class ExerciseProgressionSummary {
    @Attribute(.unique) var key: String          // "exerciseID|yyyy-ww"
    var exerciseID: String
    var weekStart: Date
    var totalVolume: Double                      // Total volume for this exercise this week
    var maxWeight: Double                        // Heaviest weight lifted this week
    var totalSets: Int                           // Sets performed this week
    var totalReps: Int                           // Total reps this week
    var sessionCount: Int                        // How many times trained this week
    var avgE1RM: Double                          // Average estimated 1RM

    init(exerciseID: String, weekStart: Date, totalVolume: Double, maxWeight: Double, totalSets: Int, totalReps: Int, sessionCount: Int, avgE1RM: Double) {
        self.exerciseID = exerciseID
        self.weekStart = weekStart
        self.totalVolume = totalVolume
        self.maxWeight = maxWeight
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.sessionCount = sessionCount
        self.avgE1RM = avgE1RM
        self.key = "\(exerciseID)|\(ExerciseVolumeSummary.weekKey(from: weekStart))"
    }
}

@Model
final class ExerciseTrend {
    @Attribute(.unique) var exerciseID: String
    var trendDirection: String                   // "improving", "stable", "declining"
    var volumeChange: Double                     // % change in volume (6-week window)
    var strengthChange: Double                   // % change in max weight (6-week window)
    var lastUpdated: Date
    var sampleCount: Int = 0                     // total ExerciseVolumeSummary records in comparison window
    var lowConfidence: Bool = false              // true when sampleCount < 6

    init(exerciseID: String, trendDirection: String, volumeChange: Double, strengthChange: Double) {
        self.exerciseID = exerciseID
        self.trendDirection = trendDirection
        self.volumeChange = volumeChange
        self.strengthChange = strengthChange
        self.lastUpdated = .now
    }
}

// MARK: - Training Balance Tracking (Priority 3)

@Model
final class PushPullBalance {
    @Attribute(.unique) var key: String          // "yyyy-ww"
    var weekStart: Date
    var pushVolume: Double                       // Volume from push exercises
    var pullVolume: Double                       // Volume from pull exercises
    var horizontalPushVolume: Double             // Bench, push-ups
    var horizontalPullVolume: Double             // Rows
    var verticalPushVolume: Double               // Overhead press
    var verticalPullVolume: Double               // Pull-ups, lat pulldowns
    var ratio: Double                            // pullVolume / pushVolume

    init(key: String, weekStart: Date, pushVolume: Double, pullVolume: Double,
         horizontalPushVolume: Double, horizontalPullVolume: Double,
         verticalPushVolume: Double, verticalPullVolume: Double) {
        self.key = key
        self.weekStart = weekStart
        self.pushVolume = pushVolume
        self.pullVolume = pullVolume
        self.horizontalPushVolume = horizontalPushVolume
        self.horizontalPullVolume = horizontalPullVolume
        self.verticalPushVolume = verticalPushVolume
        self.verticalPullVolume = verticalPullVolume
        // When pushVolume = 0: use 999 if there are pull exercises (indicates "all pull"), otherwise 0 (no data)
        self.ratio = pushVolume > 0 ? pullVolume / pushVolume : (pullVolume > 0 ? 999.0 : 0.0)
    }
}

@Model
final class MuscleGroupFrequency {
    @Attribute(.unique) var muscleGroup: String
    var lastTrained: Date
    var weeklyFrequency: Int                     // Times trained in last 7 days
    var totalVolume: Double                      // Volume in last 7 days
    var weeklySetCount: Int = 0                  // Working sets in last 7 days
    var weeklyHardSetCount: Int = 0              // Working sets with RPE >= 7 in last 7 days

    init(muscleGroup: String, lastTrained: Date, weeklyFrequency: Int, totalVolume: Double) {
        self.muscleGroup = muscleGroup
        self.lastTrained = lastTrained
        self.weeklyFrequency = weeklyFrequency
        self.totalVolume = totalVolume
    }
}

@Model
final class MovementPatternBalance {
    @Attribute(.unique) var key: String          // "yyyy-ww"
    var weekStart: Date
    var compoundVolume: Double
    var isolationVolume: Double
    var bilateralVolume: Double
    var unilateralVolume: Double
    var hingeVolume: Double                      // Deadlifts, RDLs
    var squatVolume: Double                      // Squats, lunges

    init(key: String, weekStart: Date, compoundVolume: Double, isolationVolume: Double,
         bilateralVolume: Double, unilateralVolume: Double,
         hingeVolume: Double, squatVolume: Double) {
        self.key = key
        self.weekStart = weekStart
        self.compoundVolume = compoundVolume
        self.isolationVolume = isolationVolume
        self.bilateralVolume = bilateralVolume
        self.unilateralVolume = unilateralVolume
        self.hingeVolume = hingeVolume
        self.squatVolume = squatVolume
    }
}
