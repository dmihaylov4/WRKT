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

struct CompletedWorkout: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date = .now
    var entries: [WorkoutEntry]

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

    init(id: UUID = UUID(), date: Date = .now, entries: [WorkoutEntry], plannedWorkoutID: UUID? = nil) {
        self.id = id
        self.date = date
        self.entries = entries
        self.plannedWorkoutID = plannedWorkoutID
    }

    // Custom decoder to handle missing dates (legacy data)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        entries = try container.decode([WorkoutEntry].self, forKey: .entries)

        // Try to decode date, use .now if missing (legacy data without dates)
        date = (try? container.decode(Date.self, forKey: .date)) ?? .now

        // Decode plannedWorkoutID (optional, for backwards compatibility)
        plannedWorkoutID = try? container.decode(UUID.self, forKey: .plannedWorkoutID)

        matchedHealthKitUUID = try? container.decode(UUID.self, forKey: .matchedHealthKitUUID)
        matchedHealthKitCalories = try? container.decode(Double.self, forKey: .matchedHealthKitCalories)
        matchedHealthKitHeartRate = try? container.decode(Double.self, forKey: .matchedHealthKitHeartRate)
        matchedHealthKitMaxHeartRate = try? container.decode(Double.self, forKey: .matchedHealthKitMaxHeartRate)
        matchedHealthKitMinHeartRate = try? container.decode(Double.self, forKey: .matchedHealthKitMinHeartRate)
        matchedHealthKitDuration = try? container.decode(Int.self, forKey: .matchedHealthKitDuration)
        matchedHealthKitHeartRateSamples = try? container.decode([HeartRateSample].self, forKey: .matchedHealthKitHeartRateSamples)
    }
}
