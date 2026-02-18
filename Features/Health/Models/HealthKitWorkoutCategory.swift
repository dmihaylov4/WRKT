//  HealthKitWorkoutCategory.swift
//  WRKT
//
//  Categorization system for HealthKit workout types
//  Identifies which workouts should count toward weekly strength goals
//

import Foundation

/// Category of workout based on primary training modality
enum HealthKitWorkoutCategory {
    case strength        // Counts toward strength day goal
    case cardio          // Pure cardio (running, cycling, etc.)
    case hybrid          // Mix of strength and cardio (HIIT, CrossFit, etc.)
    case flexibility     // Yoga, stretching, etc.
    case other           // Everything else

    /// Determines if this workout type should count toward weekly strength day goals
    var countsAsStrengthDay: Bool {
        switch self {
        case .strength, .hybrid:
            return true
        case .cardio, .flexibility, .other:
            return false
        }
    }

    /// Categorizes a workout based on its HealthKit workout type name
    /// - Parameter workoutType: The workout type string from HealthKit (e.g., "Strength Training", "HIIT")
    /// - Returns: The appropriate category for this workout
    static func categorize(_ workoutType: String?) -> HealthKitWorkoutCategory {
        guard let type = workoutType?.lowercased() else { return .other }

        // Strength training workouts
        if type.contains("strength") ||
           type.contains("functional training") ||
           type.contains("core training") {
            return .strength
        }

        // Hybrid workouts (high intensity with strength components)
        if type.contains("hiit") ||
           type.contains("high intensity") ||
           type.contains("cross training") ||
           type.contains("crossfit") ||
           type.contains("mixed cardio") ||
           type.contains("circuit") {
            return .hybrid
        }

        // Pure cardio
        if type.contains("running") ||
           type.contains("cycling") ||
           type.contains("walking") ||
           type.contains("swimming") ||
           type.contains("rowing") ||
           type.contains("elliptical") ||
           type.contains("stair") {
            return .cardio
        }

        // Flexibility
        if type.contains("yoga") ||
           type.contains("pilates") ||
           type.contains("flexibility") ||
           type.contains("cooldown") ||
           type.contains("stretching") {
            return .flexibility
        }

        return .other
    }
}

/// Helper extension on Run model to determine workout category
extension Run {
    /// The category of this workout
    var category: HealthKitWorkoutCategory {
        HealthKitWorkoutCategory.categorize(workoutType)
    }

    /// Whether this HealthKit workout should count as a strength day
    var countsAsStrengthDay: Bool {
        // Only count if this is a HealthKit workout (has UUID)
        guard healthKitUUID != nil else { return false }
        return category.countsAsStrengthDay
    }
}
