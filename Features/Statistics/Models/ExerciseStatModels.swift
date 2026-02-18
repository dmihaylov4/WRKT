//
//  ExerciseStatModels.swift
//  WRKT
//
//  Comprehensive exercise statistics models
//

import Foundation

// MARK: - Main Exercise Statistics Container

struct ExerciseStatistics: Identifiable {
    let id = UUID()
    let exerciseID: String
    let exerciseName: String
    let trackingMode: TrackingMode

    // Personal Records
    let personalRecords: PersonalRecords

    // Volume & Performance
    let volumeStats: VolumeStatistics

    // Consistency & Frequency
    let frequencyStats: FrequencyStatistics

    // Time-based metrics
    let timeStats: TimeStatistics

    // Historical data
    let history: ExerciseHistory

    // Progress tracking
    let progressData: ProgressData
}

// MARK: - Personal Records

struct PersonalRecords {
    let bestE1RM: PRRecord?              // Best estimated 1RM (weighted only)
    let heaviestWeight: PRRecord?        // Heaviest single weight lifted
    let mostReps: PRRecord?              // Most reps in a single set
    let bestVolume: PRRecord?            // Best volume in a single workout
    let longestHold: PRRecord?           // Longest hold duration (timed only)
    let mostRepsBodyweight: PRRecord?    // Most reps (bodyweight only)
}

struct PRRecord: Identifiable {
    let id = UUID()
    let value: Double               // The PR value (weight, reps, duration, etc.)
    let secondaryValue: Double?     // Optional secondary value (e.g., reps at that weight)
    let date: Date                  // When this PR was achieved
    let workoutID: UUID             // Link to the workout
    let displayText: String         // Formatted display text
    let setCount: Int?              // Number of sets performed (for bodyweight PRs)
}

// MARK: - Volume Statistics

struct VolumeStatistics {
    let totalVolume: Double                 // All-time total volume (reps × weight)
    let averageVolumePerSession: Double     // Average volume per workout
    let totalSets: Int                      // All-time total sets
    let totalReps: Int                      // All-time total reps
    let totalWorkTime: TimeInterval         // Total time under tension (for timed exercises)
    let volumeByWeek: [WeeklyVolume]        // Weekly breakdown
    let averageWeight: Double               // Average weight used (weighted only)
    let weightDistribution: [WeightBucket]  // Distribution of weights used
}

struct WeeklyVolume: Identifiable {
    let id = UUID()
    let weekStart: Date
    let volume: Double
    let sessions: Int
    let sets: Int
}

struct WeightBucket: Identifiable {
    let id = UUID()
    let weight: Double          // Weight value
    let frequency: Int          // How many times used
    let percentage: Double      // Percentage of total sets
}

// MARK: - Frequency Statistics

struct FrequencyStatistics {
    let totalTimesPerformed: Int        // Total number of workouts with this exercise
    let firstPerformed: Date?           // First time ever performed
    let lastPerformed: Date?            // Most recent performance
    let averagePerWeek: Double          // Average frequency per week
    let longestStreak: Int              // Longest streak of consecutive weeks
    let currentStreak: Int              // Current streak of consecutive weeks
    let daysSinceLastPerformed: Int?    // Days since last performance
}

// MARK: - Time Statistics

struct TimeStatistics {
    let averageRestBetweenSets: TimeInterval?   // Average rest time
    let minRestTime: TimeInterval?              // Minimum rest observed
    let maxRestTime: TimeInterval?              // Maximum rest observed
    let averageWorkDuration: TimeInterval?      // Average time per set (for timed)
    let totalTimeUnderTension: TimeInterval     // Total TUT (for timed exercises)
}

// MARK: - Exercise History

struct ExerciseHistory {
    let recentWorkouts: [ExerciseWorkoutEntry]   // Last 4 workouts
    let allWorkouts: [ExerciseWorkoutEntry]      // Complete history
}

struct ExerciseWorkoutEntry: Identifiable {
    let id = UUID()
    let workoutID: UUID
    let date: Date
    let sets: [SetPerformance]
    let totalVolume: Double
    let averageRest: TimeInterval?
    let isPR: Bool                  // Was a PR set during this workout?
    let prType: String?             // Type of PR (weight, reps, volume, etc.)
}

struct SetPerformance: Identifiable {
    let id = UUID()
    let setNumber: Int
    let reps: Int
    let weight: Double
    let durationSeconds: Int
    let restAfter: TimeInterval?
    let tag: SetTag
    let trackingMode: TrackingMode
    let isPR: Bool

    var displayValue: String {
        switch trackingMode {
        case .weighted:
            let formattedWeight = weight.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", weight)
                : String(format: "%.1f", weight)
            return "\(reps) × \(formattedWeight) kg"
        case .timed:
            return formatDuration(durationSeconds)
        case .bodyweight:
            return "\(reps) reps"
        case .distance:
            return "Distance" // Future implementation
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Progress Data

struct ProgressData {
    let weightProgression: [ProgressPoint]      // Weight over time
    let volumeProgression: [ProgressPoint]      // Volume over time
    let e1rmProgression: [ProgressPoint]        // E1RM over time (weighted only)
    let frequencyTrend: [FrequencyPoint]        // Times performed per week
    let trendDirection: TrendDirection          // Overall trend
    let volumeChangePercent: Double?            // % change in last 4 weeks
    let weightChangePercent: Double?            // % change in average weight
}

struct ProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct FrequencyPoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let count: Int
}

enum TrendDirection {
    case improving      // Increasing volume/weight/reps
    case stable         // Maintaining performance
    case declining      // Decreasing performance
    case insufficient   // Not enough data to determine
}

// MARK: - Helper Extensions

extension ExerciseStatistics {
    /// Check if there's sufficient data for meaningful statistics
    var hasSufficientData: Bool {
        return frequencyStats.totalTimesPerformed >= 2
    }

    /// Check if this exercise has any PR records
    var hasPRs: Bool {
        return personalRecords.bestE1RM != nil ||
               personalRecords.heaviestWeight != nil ||
               personalRecords.mostReps != nil ||
               personalRecords.bestVolume != nil ||
               personalRecords.longestHold != nil ||
               personalRecords.mostRepsBodyweight != nil
    }

    /// Get the most impressive PR for display
    var featuredPR: PRRecord? {
        // Prioritize based on tracking mode
        switch trackingMode {
        case .weighted:
            return personalRecords.bestE1RM ?? personalRecords.heaviestWeight
        case .timed:
            return personalRecords.longestHold
        case .bodyweight:
            return personalRecords.mostRepsBodyweight ?? personalRecords.mostReps
        case .distance:
            return nil // Future implementation
        }
    }
}

extension TrendDirection {
    var displayText: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        case .insufficient: return "Insufficient Data"
        }
    }

    var iconName: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        case .insufficient: return "questionmark"
        }
    }

    var color: String {
        switch self {
        case .improving: return "positive"
        case .stable: return "secondary"
        case .declining: return "negative"
        case .insufficient: return "secondary"
        }
    }
}

// MARK: - Empty States

extension ExerciseStatistics {
    /// Create an empty statistics object for exercises with no history
    static func empty(exerciseID: String, exerciseName: String, trackingMode: TrackingMode) -> ExerciseStatistics {
        return ExerciseStatistics(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            trackingMode: trackingMode,
            personalRecords: PersonalRecords(
                bestE1RM: nil,
                heaviestWeight: nil,
                mostReps: nil,
                bestVolume: nil,
                longestHold: nil,
                mostRepsBodyweight: nil
            ),
            volumeStats: VolumeStatistics(
                totalVolume: 0,
                averageVolumePerSession: 0,
                totalSets: 0,
                totalReps: 0,
                totalWorkTime: 0,
                volumeByWeek: [],
                averageWeight: 0,
                weightDistribution: []
            ),
            frequencyStats: FrequencyStatistics(
                totalTimesPerformed: 0,
                firstPerformed: nil,
                lastPerformed: nil,
                averagePerWeek: 0,
                longestStreak: 0,
                currentStreak: 0,
                daysSinceLastPerformed: nil
            ),
            timeStats: TimeStatistics(
                averageRestBetweenSets: nil,
                minRestTime: nil,
                maxRestTime: nil,
                averageWorkDuration: nil,
                totalTimeUnderTension: 0
            ),
            history: ExerciseHistory(
                recentWorkouts: [],
                allWorkouts: []
            ),
            progressData: ProgressData(
                weightProgression: [],
                volumeProgression: [],
                e1rmProgression: [],
                frequencyTrend: [],
                trendDirection: .insufficient,
                volumeChangePercent: nil,
                weightChangePercent: nil
            )
        )
    }
}
