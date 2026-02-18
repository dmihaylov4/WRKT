//
//  MetricCalculator.swift
//  WRKT
//
//  Flexible metric calculation system for battles and challenges
//  Supports various workout metrics: volume, reps, cardio, HR zones, etc.
//

import Foundation

// MARK: - Metric Types

enum MetricType: String, Codable, CaseIterable {
    // Volume-based metrics
    case totalVolume = "total_volume"                    // Total weight lifted (lbs)
    case volumeForMuscleGroup = "volume_muscle_group"    // Volume for specific muscle group
    case volumeForExercise = "volume_exercise"           // Volume for specific exercise

    // Count-based metrics
    case workoutCount = "workout_count"                  // Number of workouts completed
    case exerciseCount = "exercise_count"                // Number of exercises performed
    case setCount = "set_count"                          // Total sets completed
    case repCount = "rep_count"                          // Total reps performed
    case repsForExercise = "reps_exercise"               // Reps for specific exercise
    case prCount = "pr_count"                            // Number of PRs achieved

    // Time-based metrics
    case workoutDuration = "workout_duration"            // Workout duration (minutes)
    case timeUnderTension = "time_under_tension"         // Total TUT (seconds)

    // Cardio-based metrics (from HealthKit)
    case distance = "distance"                           // Distance covered (km)
    case calories = "calories"                           // Calories burned
    case avgHeartRate = "avg_heart_rate"                 // Average heart rate (bpm)
    case maxHeartRate = "max_heart_rate"                 // Max heart rate reached
    case timeInHRZone = "time_in_hr_zone"               // Time spent in specific HR zone (minutes)
    case elevationGain = "elevation_gain"                // Elevation gained (meters)

    // Intensity metrics
    case avgWeight = "avg_weight"                        // Average weight lifted per set
    case maxWeight = "max_weight"                        // Max weight lifted in workout
    case oneRepMax = "one_rep_max"                       // Estimated 1RM for exercise

    // Variety metrics
    case uniqueExercises = "unique_exercises"            // Number of different exercises
    case muscleGroupsCovered = "muscle_groups_covered"   // Number of muscle groups trained

    // Streak metrics
    case consecutiveDays = "consecutive_days"            // Consecutive workout days

    var displayName: String {
        switch self {
        case .totalVolume: return "Total Volume"
        case .volumeForMuscleGroup: return "Muscle Group Volume"
        case .volumeForExercise: return "Exercise Volume"
        case .workoutCount: return "Workout Count"
        case .exerciseCount: return "Exercise Count"
        case .setCount: return "Set Count"
        case .repCount: return "Rep Count"
        case .repsForExercise: return "Exercise Reps"
        case .prCount: return "PR Count"
        case .workoutDuration: return "Workout Duration"
        case .timeUnderTension: return "Time Under Tension"
        case .distance: return "Distance"
        case .calories: return "Calories Burned"
        case .avgHeartRate: return "Avg Heart Rate"
        case .maxHeartRate: return "Max Heart Rate"
        case .timeInHRZone: return "Time in HR Zone"
        case .elevationGain: return "Elevation Gain"
        case .avgWeight: return "Average Weight"
        case .maxWeight: return "Max Weight"
        case .oneRepMax: return "One Rep Max"
        case .uniqueExercises: return "Unique Exercises"
        case .muscleGroupsCovered: return "Muscle Groups"
        case .consecutiveDays: return "Consecutive Days"
        }
    }

    var unit: String {
        switch self {
        case .totalVolume, .volumeForMuscleGroup, .volumeForExercise, .avgWeight, .maxWeight, .oneRepMax:
            return "kg"
        case .workoutCount, .exerciseCount, .setCount, .repCount, .repsForExercise, .prCount, .uniqueExercises, .muscleGroupsCovered:
            return ""
        case .workoutDuration, .timeUnderTension, .timeInHRZone:
            return "min"
        case .distance:
            return "km"
        case .calories:
            return "kcal"
        case .avgHeartRate, .maxHeartRate:
            return "bpm"
        case .elevationGain:
            return "m"
        case .consecutiveDays:
            return "days"
        }
    }
}

// MARK: - Metric Filter

struct MetricFilter: Codable {
    var exerciseName: String?              // Filter by specific exercise name (fuzzy match)
    var exerciseNames: [String]?           // Filter by multiple exercise names (OR logic)
    var muscleGroups: [String]?            // Filter by muscle groups
    var hrZone: HeartRateZone?            // Filter by heart rate zone
    var minWeight: Double?                 // Minimum weight threshold
    var maxWeight: Double?                 // Maximum weight threshold
    var minReps: Int?                      // Minimum reps threshold
    var maxReps: Int?                      // Maximum reps threshold

    init(
        exerciseName: String? = nil,
        exerciseNames: [String]? = nil,
        muscleGroups: [String]? = nil,
        hrZone: HeartRateZone? = nil,
        minWeight: Double? = nil,
        maxWeight: Double? = nil,
        minReps: Int? = nil,
        maxReps: Int? = nil
    ) {
        self.exerciseName = exerciseName
        self.exerciseNames = exerciseNames
        self.muscleGroups = muscleGroups
        self.hrZone = hrZone
        self.minWeight = minWeight
        self.maxWeight = maxWeight
        self.minReps = minReps
        self.maxReps = maxReps
    }
}

// MARK: - Heart Rate Zones

enum HeartRateZone: Int, Codable {
    case zone1 = 1  // 50-60% max HR (Very light)
    case zone2 = 2  // 60-70% max HR (Light)
    case zone3 = 3  // 70-80% max HR (Moderate)
    case zone4 = 4  // 80-90% max HR (Hard)
    case zone5 = 5  // 90-100% max HR (Maximum)

    var range: ClosedRange<Double> {
        switch self {
        case .zone1: return 0.50...0.60
        case .zone2: return 0.60...0.70
        case .zone3: return 0.70...0.80
        case .zone4: return 0.80...0.90
        case .zone5: return 0.90...1.00
        }
    }

    var displayName: String {
        switch self {
        case .zone1: return "Zone 1 (Very Light)"
        case .zone2: return "Zone 2 (Light)"
        case .zone3: return "Zone 3 (Moderate)"
        case .zone4: return "Zone 4 (Hard)"
        case .zone5: return "Zone 5 (Maximum)"
        }
    }
}

// MARK: - Metric Calculator

struct MetricCalculator {

    // MARK: - Main Calculation Entry Point

    /// Calculate a metric value from a completed workout
    static func calculate(
        metric: MetricType,
        filter: MetricFilter?,
        workout: CompletedWorkout,
        userMaxHR: Int? = nil  // User's max heart rate (for HR zone calculations)
    ) -> Decimal {
        switch metric {
        // Volume-based
        case .totalVolume:
            return calculateTotalVolume(workout: workout, filter: filter)
        case .volumeForMuscleGroup:
            return calculateVolumeForMuscleGroup(workout: workout, filter: filter)
        case .volumeForExercise:
            return calculateVolumeForExercise(workout: workout, filter: filter)

        // Count-based
        case .workoutCount:
            return 1  // Each workout counts as 1
        case .exerciseCount:
            return Decimal(workout.entries.count)
        case .setCount:
            return Decimal(workout.entries.reduce(0) { $0 + $1.sets.count })
        case .repCount:
            return calculateTotalReps(workout: workout, filter: filter)
        case .repsForExercise:
            return calculateRepsForExercise(workout: workout, filter: filter)
        case .prCount:
            return Decimal(workout.detectedPRCount ?? 0)

        // Time-based
        case .workoutDuration:
            return calculateWorkoutDuration(workout: workout)
        case .timeUnderTension:
            return calculateTimeUnderTension(workout: workout, filter: filter)

        // Cardio-based (from HealthKit)
        case .distance:
            // Convert meters to km
            if let distance = workout.matchedHealthKitDistance {
                return Decimal(distance / 1000.0)
            }
            return 0
        case .calories:
            return Decimal(workout.matchedHealthKitCalories ?? 0)
        case .avgHeartRate:
            return Decimal(workout.matchedHealthKitHeartRate ?? 0)
        case .maxHeartRate:
            return Decimal(workout.matchedHealthKitMaxHeartRate ?? 0)
        case .timeInHRZone:
            return calculateTimeInHRZone(workout: workout, filter: filter, userMaxHR: userMaxHR)
        case .elevationGain:
            return Decimal(workout.matchedHealthKitElevationGain ?? 0)

        // Intensity metrics
        case .avgWeight:
            return calculateAverageWeight(workout: workout, filter: filter)
        case .maxWeight:
            return calculateMaxWeight(workout: workout, filter: filter)
        case .oneRepMax:
            return calculateOneRepMax(workout: workout, filter: filter)

        // Variety metrics
        case .uniqueExercises:
            return calculateUniqueExercises(workout: workout, filter: filter)
        case .muscleGroupsCovered:
            return calculateMuscleGroupsCovered(workout: workout, filter: filter)

        // Streak metrics
        case .consecutiveDays:
            return 0  // Requires multiple workouts - handled at repository level
        }
    }

    // MARK: - Volume Calculations

    private static func calculateTotalVolume(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var total: Double = 0

        for entry in workout.entries {
            // Apply filters
            if !matchesFilter(entry: entry, filter: filter) { continue }

            for set in entry.sets {
                // Both weight and reps are non-optional
                total += set.weight * Double(set.reps)
            }
        }

        return Decimal(total)
    }

    private static func calculateVolumeForMuscleGroup(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        // Filter entries by muscle group if specified, then calculate volume
        var total: Double = 0

        for entry in workout.entries {
            // Apply all filters including muscle group
            if !matchesFilter(entry: entry, filter: filter) { continue }

            for set in entry.sets {
                total += set.weight * Double(set.reps)
            }
        }

        return Decimal(total)
    }

    private static func calculateVolumeForExercise(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        return calculateTotalVolume(workout: workout, filter: filter)
    }

    // MARK: - Rep Calculations

    private static func calculateTotalReps(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var total = 0

        for entry in workout.entries {
            if !matchesFilter(entry: entry, filter: filter) { continue }

            for set in entry.sets {
                // reps is non-optional
                total += set.reps
            }
        }

        return Decimal(total)
    }

    private static func calculateRepsForExercise(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        return calculateTotalReps(workout: workout, filter: filter)
    }

    // MARK: - Time Calculations

    private static func calculateWorkoutDuration(workout: CompletedWorkout) -> Decimal {
        guard let startedAt = workout.startedAt else {
            // No start time available, return 0
            return 0
        }
        let duration = workout.date.timeIntervalSince(startedAt)
        return Decimal(duration / 60)  // Convert to minutes
    }

    private static func calculateTimeUnderTension(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        // Estimate TUT: assume 2 seconds per rep
        let totalReps = calculateTotalReps(workout: workout, filter: filter)
        let tutSeconds = Double(truncating: totalReps as NSDecimalNumber) * 2.0
        return Decimal(tutSeconds / 60)  // Convert to minutes
    }

    // MARK: - Heart Rate Calculations

    private static func calculateTimeInHRZone(
        workout: CompletedWorkout,
        filter: MetricFilter?,
        userMaxHR: Int?
    ) -> Decimal {
        guard let hrZone = filter?.hrZone,
              let hrSamples = workout.matchedHealthKitHeartRateSamples else {
            return 0
        }

        // Use HRZoneCalculator for zone boundaries (personalized based on user data)
        let calculator = HRZoneCalculator.shared
        let boundaries = calculator.zoneBoundaries()

        // Find the boundary for the requested zone
        guard let boundary = boundaries.first(where: { $0.zone == hrZone.rawValue }) else {
            return 0
        }

        let lowerBound = Double(boundary.lowerBPM)
        let upperBound = Double(boundary.upperBPM)

        // Count samples in zone (samples are typically every 5-10 seconds)
        // HeartRateSample has a .bpm property
        let samplesInZone = hrSamples.filter { $0.bpm >= lowerBound && $0.bpm <= upperBound }.count

        // Estimate time: assume 5 seconds per sample (conservative estimate)
        let timeInZoneSeconds = Double(samplesInZone) * 5.0
        return Decimal(timeInZoneSeconds / 60)  // Convert to minutes
    }

    // MARK: - Intensity Calculations

    private static func calculateAverageWeight(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var totalWeight: Double = 0
        var count = 0

        for entry in workout.entries {
            if !matchesFilter(entry: entry, filter: filter) { continue }

            for set in entry.sets {
                // set.weight is not optional - it's always a Double
                if set.weight > 0 {
                    totalWeight += set.weight
                    count += 1
                }
            }
        }

        guard count > 0 else { return 0 }
        return Decimal(totalWeight / Double(count))
    }

    private static func calculateMaxWeight(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var maxWeight: Double = 0

        for entry in workout.entries {
            if !matchesFilter(entry: entry, filter: filter) { continue }

            for set in entry.sets {
                // set.weight is not optional - it's always a Double
                maxWeight = max(maxWeight, set.weight)
            }
        }

        return Decimal(maxWeight)
    }

    private static func calculateOneRepMax(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var maxEstimate: Double = 0

        for entry in workout.entries {
            if !matchesFilter(entry: entry, filter: filter) { continue }

            for set in entry.sets {
                // Both weight and reps are non-optional
                guard set.reps > 0, set.weight > 0 else { continue }

                // Brzycki formula: 1RM = weight / (1.0278 - 0.0278 * reps)
                let estimate = set.weight / (1.0278 - 0.0278 * Double(set.reps))
                maxEstimate = max(maxEstimate, estimate)
            }
        }

        return Decimal(maxEstimate)
    }

    // MARK: - Variety Calculations

    private static func calculateUniqueExercises(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var uniqueExercises = Set<String>()

        for entry in workout.entries {
            if !matchesFilter(entry: entry, filter: filter) { continue }
            uniqueExercises.insert(entry.exerciseName.lowercased())
        }

        return Decimal(uniqueExercises.count)
    }

    private static func calculateMuscleGroupsCovered(workout: CompletedWorkout, filter: MetricFilter?) -> Decimal {
        var uniqueMuscleGroups = Set<String>()

        for entry in workout.entries {
            if !matchesFilter(entry: entry, filter: filter) { continue }

            // Add all muscle groups from this entry (normalized to lowercase)
            for muscleGroup in entry.muscleGroups {
                uniqueMuscleGroups.insert(muscleGroup.lowercased())
            }
        }

        return Decimal(uniqueMuscleGroups.count)
    }

    // MARK: - Filter Matching

    private static func matchesFilter(entry: WorkoutEntry, filter: MetricFilter?) -> Bool {
        guard let filter = filter else { return true }

        // Exercise name filter (fuzzy match)
        if let exerciseName = filter.exerciseName {
            let entryName = entry.exerciseName.lowercased()
            let filterName = exerciseName.lowercased()
            if !entryName.contains(filterName) {
                return false
            }
        }

        // Multiple exercise names filter (OR logic)
        if let exerciseNames = filter.exerciseNames, !exerciseNames.isEmpty {
            let entryName = entry.exerciseName.lowercased()
            let matches = exerciseNames.contains { name in
                entryName.contains(name.lowercased())
            }
            if !matches {
                return false
            }
        }

        // Weight range filter
        if let minWeight = filter.minWeight {
            let maxWeightInEntry = entry.sets.map { $0.weight }.max() ?? 0
            if maxWeightInEntry < minWeight {
                return false
            }
        }

        if let maxWeight = filter.maxWeight {
            let minWeightInEntry = entry.sets.map { $0.weight }.min() ?? Double.infinity
            if minWeightInEntry > maxWeight {
                return false
            }
        }

        // Reps range filter
        if let minReps = filter.minReps {
            let maxRepsInEntry = entry.sets.map { $0.reps }.max() ?? 0
            if maxRepsInEntry < minReps {
                return false
            }
        }

        if let maxReps = filter.maxReps {
            let minRepsInEntry = entry.sets.map { $0.reps }.min() ?? Int.max
            if minRepsInEntry > maxReps {
                return false
            }
        }

        // Muscle group filter (OR logic - entry matches if it targets any of the specified muscle groups)
        if let muscleGroups = filter.muscleGroups, !muscleGroups.isEmpty {
            let entryMuscleGroups = Set(entry.muscleGroups.map { $0.lowercased() })
            let filterMuscleGroups = Set(muscleGroups.map { $0.lowercased() })

            // Check if there's any intersection
            if entryMuscleGroups.isDisjoint(with: filterMuscleGroups) {
                return false
            }
        }

        return true
    }
}

// MARK: - Metric Configuration (for Battles/Challenges)

struct MetricConfiguration: Codable {
    let type: MetricType
    let filter: MetricFilter?
    let goalValue: Decimal?  // Target value for challenges

    init(type: MetricType, filter: MetricFilter? = nil, goalValue: Decimal? = nil) {
        self.type = type
        self.filter = filter
        self.goalValue = goalValue
    }

    /// Human-readable description of this metric
    var description: String {
        var desc = type.displayName

        if let filter = filter {
            if let exerciseName = filter.exerciseName {
                desc += " for \(exerciseName)"
            }
            if let exerciseNames = filter.exerciseNames {
                desc += " for \(exerciseNames.joined(separator: ", "))"
            }
            if let hrZone = filter.hrZone {
                desc += " in \(hrZone.displayName)"
            }
        }

        if let goal = goalValue {
            desc += " (Goal: \(goal) \(type.unit))"
        }

        return desc
    }
}
