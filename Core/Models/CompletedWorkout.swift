//
//  CompletedWorkout.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 26.10.25.
//

import Foundation

// Heart rate sample for time-series graphing
struct HeartRateSample: Codable, Hashable {
    let timestamp: Date      // When this sample was recorded
    let bpm: Double          // Beats per minute
}

// Heart rate zone summary for social sharing
struct HRZoneSummary: Codable, Hashable, Identifiable {
    var id: Int { zone }
    let zone: Int           // 1-5
    let name: String        // "Light", "Moderate", "Aerobic", "Threshold", "Max"
    let minutes: Double     // Time spent in zone
    let rangeDisplay: String // "120-140 bpm"
    let colorHex: String    // Hex color for display (e.g., "#00FF00")
}

struct CompletedWorkout: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date = .now  // When the workout was completed/ended
    var startedAt: Date?   // When the workout was actually started (optional for backward compatibility)
    var entries: [WorkoutEntry]

    // Custom workout name (optional - if not set, will auto-classify from exercises)
    var workoutName: String?

    // Link to planned workout (if this was completed from a plan)
    var plannedWorkoutID: UUID?

    // Matched HealthKit workout data (if found within ±10 min of completion)
    var matchedHealthKitUUID: UUID?
    var matchedHealthKitCalories: Double?
    var matchedHealthKitHeartRate: Double?           // Average HR
    var matchedHealthKitMaxHeartRate: Double?        // Max HR
    var matchedHealthKitMinHeartRate: Double?        // Min HR
    var matchedHealthKitDuration: Int?               // in seconds
    var matchedHealthKitHeartRateSamples: [HeartRateSample]?  // Time-series for graph
    var matchedHealthKitDistance: Double?            // in meters
    var matchedHealthKitElevationGain: Double?       // in meters

    // PR tracking (populated when workout is saved)
    var detectedPRCount: Int?  // Number of personal records achieved in this workout

    // Cardio-specific data for social sharing
    var cardioSplits: [KilometerSplit]?    // Km splits for display
    var cardioHRZones: [HRZoneSummary]?    // Pre-computed HR zone breakdown
    var cardioWorkoutType: String?          // e.g., "Running", "Cycling"

    // Running dynamics (from Apple Watch sensors)
    var cardioAvgPower: Double?            // Watts
    var cardioAvgCadence: Double?          // Steps per minute
    var cardioAvgStrideLength: Double?     // Meters
    var cardioAvgGroundContactTime: Double? // Milliseconds
    var cardioAvgVerticalOscillation: Double? // Centimeters

    init(id: UUID = UUID(), date: Date = .now, startedAt: Date? = nil, entries: [WorkoutEntry], plannedWorkoutID: UUID? = nil, workoutName: String? = nil) {
        self.id = id
        self.date = date
        self.startedAt = startedAt
        self.entries = entries
        self.plannedWorkoutID = plannedWorkoutID
        self.workoutName = workoutName
    }

    // MARK: - Computed Properties

    /// Determine if this is primarily a cardio workout
    var isCardioWorkout: Bool {
        // If there's a matched HealthKit workout but no strength exercises, it's cardio
        if matchedHealthKitUUID != nil && entries.isEmpty {
            return true
        }
        // If there's matched HealthKit data with calories but few/no strength exercises, it's cardio
        if matchedHealthKitCalories != nil && entries.count < 2 {
            return true
        }
        return false
    }

    /// Get the appropriate icon for this workout type
    var workoutIcon: String {
        isCardioWorkout ? "heart.fill" : "dumbbell.fill"
    }

    /// Get the workout type display name
    var workoutTypeDisplayName: String {
        if isCardioWorkout {
            return cardioWorkoutType ?? "Cardio"
        }
        return "Strength"
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case startedAt
        case entries
        case workoutName
        case plannedWorkoutID
        case matchedHealthKitUUID
        case matchedHealthKitCalories
        case matchedHealthKitHeartRate
        case matchedHealthKitMaxHeartRate
        case matchedHealthKitMinHeartRate
        case matchedHealthKitDuration
        case matchedHealthKitHeartRateSamples
        case matchedHealthKitDistance
        case matchedHealthKitElevationGain
        case detectedPRCount
        case cardioSplits
        case cardioHRZones
        case cardioWorkoutType
        case cardioAvgPower
        case cardioAvgCadence
        case cardioAvgStrideLength
        case cardioAvgGroundContactTime
        case cardioAvgVerticalOscillation
    }

    // Custom decoder to handle missing fields (legacy data)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()

        // Handle legacy data without entries field
        entries = (try? container.decode([WorkoutEntry].self, forKey: .entries)) ?? []

        // Try to decode date, use .now if missing (legacy data without dates)
        date = (try? container.decode(Date.self, forKey: .date)) ?? .now

        // Decode startedAt (optional, for backwards compatibility with old workouts)
        startedAt = try? container.decode(Date.self, forKey: .startedAt)

        // Decode workoutName (optional, for backwards compatibility)
        workoutName = try? container.decode(String.self, forKey: .workoutName)

        // Decode plannedWorkoutID (optional, for backwards compatibility)
        plannedWorkoutID = try? container.decode(UUID.self, forKey: .plannedWorkoutID)

        matchedHealthKitUUID = try? container.decode(UUID.self, forKey: .matchedHealthKitUUID)
        matchedHealthKitCalories = try? container.decode(Double.self, forKey: .matchedHealthKitCalories)
        matchedHealthKitHeartRate = try? container.decode(Double.self, forKey: .matchedHealthKitHeartRate)
        matchedHealthKitMaxHeartRate = try? container.decode(Double.self, forKey: .matchedHealthKitMaxHeartRate)
        matchedHealthKitMinHeartRate = try? container.decode(Double.self, forKey: .matchedHealthKitMinHeartRate)
        matchedHealthKitDuration = try? container.decode(Int.self, forKey: .matchedHealthKitDuration)
        matchedHealthKitHeartRateSamples = try? container.decode([HeartRateSample].self, forKey: .matchedHealthKitHeartRateSamples)
        matchedHealthKitDistance = try? container.decode(Double.self, forKey: .matchedHealthKitDistance)
        matchedHealthKitElevationGain = try? container.decode(Double.self, forKey: .matchedHealthKitElevationGain)
        detectedPRCount = try? container.decode(Int.self, forKey: .detectedPRCount)
        cardioSplits = try? container.decode([KilometerSplit].self, forKey: .cardioSplits)
        cardioHRZones = try? container.decode([HRZoneSummary].self, forKey: .cardioHRZones)
        cardioWorkoutType = try? container.decode(String.self, forKey: .cardioWorkoutType)
        cardioAvgPower = try? container.decode(Double.self, forKey: .cardioAvgPower)
        cardioAvgCadence = try? container.decode(Double.self, forKey: .cardioAvgCadence)
        cardioAvgStrideLength = try? container.decode(Double.self, forKey: .cardioAvgStrideLength)
        cardioAvgGroundContactTime = try? container.decode(Double.self, forKey: .cardioAvgGroundContactTime)
        cardioAvgVerticalOscillation = try? container.decode(Double.self, forKey: .cardioAvgVerticalOscillation)
    }

    // Custom encoder to ensure all fields are properly saved
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(workoutName, forKey: .workoutName)
        try container.encodeIfPresent(plannedWorkoutID, forKey: .plannedWorkoutID)
        try container.encodeIfPresent(matchedHealthKitUUID, forKey: .matchedHealthKitUUID)
        try container.encodeIfPresent(matchedHealthKitCalories, forKey: .matchedHealthKitCalories)
        try container.encodeIfPresent(matchedHealthKitHeartRate, forKey: .matchedHealthKitHeartRate)
        try container.encodeIfPresent(matchedHealthKitMaxHeartRate, forKey: .matchedHealthKitMaxHeartRate)
        try container.encodeIfPresent(matchedHealthKitMinHeartRate, forKey: .matchedHealthKitMinHeartRate)
        try container.encodeIfPresent(matchedHealthKitDuration, forKey: .matchedHealthKitDuration)
        try container.encodeIfPresent(matchedHealthKitHeartRateSamples, forKey: .matchedHealthKitHeartRateSamples)
        try container.encodeIfPresent(matchedHealthKitDistance, forKey: .matchedHealthKitDistance)
        try container.encodeIfPresent(matchedHealthKitElevationGain, forKey: .matchedHealthKitElevationGain)
        try container.encodeIfPresent(detectedPRCount, forKey: .detectedPRCount)
        try container.encodeIfPresent(cardioSplits, forKey: .cardioSplits)
        try container.encodeIfPresent(cardioHRZones, forKey: .cardioHRZones)
        try container.encodeIfPresent(cardioWorkoutType, forKey: .cardioWorkoutType)
        try container.encodeIfPresent(cardioAvgPower, forKey: .cardioAvgPower)
        try container.encodeIfPresent(cardioAvgCadence, forKey: .cardioAvgCadence)
        try container.encodeIfPresent(cardioAvgStrideLength, forKey: .cardioAvgStrideLength)
        try container.encodeIfPresent(cardioAvgGroundContactTime, forKey: .cardioAvgGroundContactTime)
        try container.encodeIfPresent(cardioAvgVerticalOscillation, forKey: .cardioAvgVerticalOscillation)
    }
}

// MARK: - Validation

extension CompletedWorkout {
    /// Validates that the workout meets minimum requirements
    /// Returns tuple: (isValid, warningMessage)
    func validateWorkoutMinimums() -> (isValid: Bool, warning: String?) {
        // Check if workout has any entries
        guard !entries.isEmpty else {
            return (false, "Workout has no exercises")
        }

        // Check if all entries have empty sets
        let totalSets = entries.flatMap { $0.sets }.count
        guard totalSets > 0 else {
            return (false, "Workout has no logged sets")
        }

        // Check if all sets are completed
        let completedSets = entries.flatMap { $0.sets }.filter { $0.isCompleted }
        guard !completedSets.isEmpty else {
            return (false, "No sets were completed")
        }

        // Minimum workout threshold: At least 1 completed set
        // This is lenient - user may have done a quick workout or just testing
        // We'll add smart filtering elsewhere if needed
        return (true, nil)
    }

    /// Check if workout appears to be very short (likely accidental or test)
    var appearsAccidental: Bool {
        let completedSets = entries.flatMap { $0.sets }.filter { $0.isCompleted }

        // Less than 2 completed sets = likely accidental
        if completedSets.count < 2 {
            return true
        }

        // Single exercise with single set = likely accidental
        if entries.count == 1 && completedSets.count == 1 {
            return true
        }

        return false
    }

    /// Get workout duration in seconds (if timing data available)
    /// Uses actual startedAt time if available, otherwise estimates from set timestamps
    var estimatedDuration: TimeInterval? {
        // If we have the actual workout start time, use that with the completion time
        if let startTime = startedAt {
            return date.timeIntervalSince(startTime)
        }

        // Otherwise, estimate from set-level timestamps
        let allSets = entries.flatMap { $0.sets }

        guard let firstStart = allSets.compactMap({ $0.startTime }).min(),
              let lastCompletion = allSets.compactMap({ $0.completionTime }).max() else {
            return nil
        }

        return lastCompletion.timeIntervalSince(firstStart)
    }

    /// Check if workout is suspiciously short (< 2 minutes with timing data)
    var isSuspiciouslyShort: Bool {
        guard let duration = estimatedDuration else { return false }
        return duration < 120 // Less than 2 minutes
    }
}
