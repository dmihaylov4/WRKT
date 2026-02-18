//
//  Utilities.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//
import SwiftUI
import CoreData
import Foundation
import HealthKit

extension String {
    var normalized: String {
        self.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}

extension Array where Element == Exercise {
    func allMuscleGroups() -> [String] {
        let muscles = self.flatMap { $0.primaryMuscles + $0.secondaryMuscles }
        let groups = Set(muscles)
        return groups.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

enum CardioActivityType: String, Hashable {
    case running = "Running"
    case walking = "Walking"
    case cycling = "Cycling"
    case strength = "Strength"
    case functionalTraining = "Functional Training"
    case hiit = "HIIT"
    case coreTraining = "Core Training"
    case yoga = "Yoga"
    case swimming = "Swimming"
    case rowing = "Rowing"
    case other = "Other"

    init(from workoutType: String?) {
        guard let type = workoutType else {
            self = .other
            return
        }

        let lowercased = type.lowercased()

        // Map HealthKit workout types to our categories
        if lowercased.contains("running") || lowercased.contains("run") {
            self = .running
        } else if lowercased.contains("walking") || lowercased.contains("walk") {
            self = .walking
        } else if lowercased.contains("cycling") || lowercased.contains("bike") || lowercased.contains("biking") {
            self = .cycling
        } else if lowercased.contains("strength training") || lowercased.contains("traditional strength") {
            self = .strength
        } else if lowercased.contains("functional") {
            self = .functionalTraining
        } else if lowercased.contains("hiit") || lowercased.contains("high intensity") {
            self = .hiit
        } else if lowercased.contains("core") {
            self = .coreTraining
        } else if lowercased.contains("yoga") {
            self = .yoga
        } else if lowercased.contains("swimming") || lowercased.contains("swim") {
            self = .swimming
        } else if lowercased.contains("rowing") || lowercased.contains("row") {
            self = .rowing
        } else {
            self = .other
        }
    }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .functionalTraining: return "figure.strengthtraining.functional"
        case .hiit: return "bolt.fill"
        case .coreTraining: return "figure.core.training"
        case .yoga: return "figure.yoga"
        case .swimming: return "figure.pool.swim"
        case .rowing: return "figure.rower"
        case .other: return "figure.cardio"
        }
    }

    /// Whether this activity type should count toward strength day goals
    var countsAsStrengthDay: Bool {
        switch self {
        case .strength, .functionalTraining, .hiit, .coreTraining:
            return true
        case .running, .walking, .cycling, .yoga, .swimming, .rowing, .other:
            return false
        }
    }
}

struct DayStat: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let workoutCount: Int
    let runCount: Int // Deprecated - use cardioActivities instead
    let cardioActivities: [CardioActivityType] // Types of cardio activities on this day
    let healthKitStrengthWorkouts: [Run] // Apple Watch strength workouts (Traditional Strength, HIIT, Functional, Core)
    let plannedWorkout: PlannedWorkout?

    // Pre-calculated week status for performance (avoids recalculating for each cell)
    let isPartOfCompletedWeek: Bool
    let isPartOfSuperWeek: Bool
    let isInCurrentWeek: Bool

    init(id: UUID = UUID(),
         date: Date,
         workoutCount: Int,
         runCount: Int = 0,
         cardioActivities: [CardioActivityType] = [],
         healthKitStrengthWorkouts: [Run] = [],
         plannedWorkout: PlannedWorkout? = nil,
         isPartOfCompletedWeek: Bool = false,
         isPartOfSuperWeek: Bool = false,
         isInCurrentWeek: Bool = false) {
        self.id = id
        self.date = date
        self.workoutCount = workoutCount
        self.runCount = runCount
        self.cardioActivities = cardioActivities
        self.healthKitStrengthWorkouts = healthKitStrengthWorkouts
        self.plannedWorkout = plannedWorkout
        self.isPartOfCompletedWeek = isPartOfCompletedWeek
        self.isPartOfSuperWeek = isPartOfSuperWeek
        self.isInCurrentWeek = isInCurrentWeek
    }

    // Helper computed properties
    var hasPlannedWorkout: Bool { plannedWorkout != nil }
    var isPlannedCompleted: Bool { plannedWorkout?.workoutStatus == .completed }
    var isPlannedPartial: Bool { plannedWorkout?.workoutStatus == .partial }
    var isPlannedSkipped: Bool { plannedWorkout?.workoutStatus == .skipped }
    var isPlannedScheduled: Bool { plannedWorkout?.workoutStatus == .scheduled }

    // Has any strength activity (in-app or HealthKit)
    var hasStrengthActivity: Bool {
        workoutCount > 0 || !healthKitStrengthWorkouts.isEmpty
    }

    // Total strength sessions (in-app + HealthKit)
    var totalStrengthSessions: Int {
        workoutCount + healthKitStrengthWorkouts.count
    }

    // Check if planned workout has been completed by checking if any completed workout links to it
    func isPlannedWorkoutCompleted(completedWorkouts: [CompletedWorkout]) -> Bool {
        guard let plannedID = plannedWorkout?.id else { return false }
        return completedWorkouts.contains { $0.plannedWorkoutID == plannedID }
    }

    static func == (lhs: DayStat, rhs: DayStat) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Apple Watch Detection

enum DeviceCapability {
    /// Detects if the user likely has an Apple Watch paired
    /// This checks if Apple Exercise Time data exists in HealthKit
    @MainActor
    static func hasAppleWatch() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            return false
        }

        let store = HKHealthStore()

        // Check authorization status
        let status = store.authorizationStatus(for: exerciseType)
        guard status != .notDetermined else {
            // Not authorized yet - can't determine
            return false
        }

        // Query for recent exercise time data (last 7 days)
        let now = Date()
        guard let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            return false
        }

        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: exerciseType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let samples = samples, !samples.isEmpty {
                    // Found exercise time data - likely has Apple Watch
                    continuation.resume(returning: true)
                } else {
                    // No exercise time data - likely no Apple Watch
                    continuation.resume(returning: false)
                }
            }

            store.execute(query)
        }
    }

    /// Determines the recommended tracking mode based on device capability
    @MainActor
    static func recommendedTrackingMode() async -> ActivityTrackingMode {
        let hasWatch = await hasAppleWatch()
        return hasWatch ? .exerciseMinutes : .steps
    }
}

// MARK: - Time Formatting

/// Format duration in seconds to human-readable string
/// Examples: "45s", "1m 30s", "1h 15m"
func formatDuration(_ seconds: Int) -> String {
    guard seconds > 0 else { return "—" }

    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
        if minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(hours)h"
    } else if minutes > 0 {
        if secs > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(minutes)m"
    } else {
        return "\(secs)s"
    }
}

// MARK: - Safe Double to Int Conversion

extension Double {
    /// Safely converts Double to Int, handling NaN and infinity cases
    /// Returns 0 for NaN or infinite values to prevent runtime crashes
    nonisolated var safeInt: Int {
        guard isFinite else { return 0 }
        return Int(self)
    }
}
