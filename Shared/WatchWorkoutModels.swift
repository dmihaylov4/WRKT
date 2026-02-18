//
//  WatchWorkoutModels.swift
//  WRKT
//
//  Shared models for communication between iOS and watchOS apps
//  These are lightweight versions optimized for Watch Connectivity
//

import Foundation

// MARK: - Watch Workout State

/// Complete workout state sent to Apple Watch
struct WatchWorkoutState: Codable, Hashable {
    var isActive: Bool
    var exercises: [WatchExerciseInfo]
    var activeExerciseIndex: Int?
    var workoutStartTime: Date?
    var restTimer: WatchRestTimerInfo?

    init(
        isActive: Bool = false,
        exercises: [WatchExerciseInfo] = [],
        activeExerciseIndex: Int? = nil,
        workoutStartTime: Date? = nil,
        restTimer: WatchRestTimerInfo? = nil
    ) {
        self.isActive = isActive
        self.exercises = exercises
        self.activeExerciseIndex = activeExerciseIndex
        self.workoutStartTime = workoutStartTime
        self.restTimer = restTimer
    }

    /// Check if there's an active workout
    var hasActiveWorkout: Bool {
        isActive && !exercises.isEmpty
    }

    /// Get the currently active exercise
    var activeExercise: WatchExerciseInfo? {
        guard let index = activeExerciseIndex, exercises.indices.contains(index) else {
            return nil
        }
        return exercises[index]
    }
}

// MARK: - Watch Exercise Info

/// Exercise information optimized for watch display
struct WatchExerciseInfo: Codable, Hashable, Identifiable {
    var id: String  // exerciseID
    var entryID: String  // WorkoutEntry UUID
    var name: String
    var sets: [WatchSetInfo]
    var activeSetIndex: Int

    /// Total number of sets
    var totalSets: Int {
        sets.count
    }

    /// Number of completed sets
    var completedSets: Int {
        sets.filter { $0.isCompleted }.count
    }

    /// Current set (based on activeSetIndex)
    var currentSet: WatchSetInfo? {
        guard sets.indices.contains(activeSetIndex) else { return nil }
        return sets[activeSetIndex]
    }

    /// Next incomplete set
    var nextIncompleteSet: (index: Int, set: WatchSetInfo)? {
        guard let index = sets.firstIndex(where: { !$0.isCompleted }) else {
            return nil
        }
        return (index, sets[index])
    }

    /// Check if all sets are completed
    var isCompleted: Bool {
        !sets.isEmpty && sets.allSatisfy { $0.isCompleted }
    }

    /// Progress fraction (0.0 to 1.0)
    var progress: Double {
        guard !sets.isEmpty else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }
}

// MARK: - Watch Set Info

/// Set information optimized for watch display
struct WatchSetInfo: Codable, Hashable, Identifiable {
    var id: String  // Use index as ID for simplicity
    var reps: Int
    var weight: Double
    var tag: String  // "warmup", "working", "backoff"
    var isCompleted: Bool
    var trackingMode: String  // "weighted", "bodyweight", "timed"
    var durationSeconds: Int  // For timed exercises

    /// Display text for the set (e.g., "10 × 50 kg" or "12 reps" or "45s")
    var displayText: String {
        switch trackingMode {
        case "weighted":
            let formattedWeight = weight.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", weight)
                : String(format: "%.1f", weight)
            return "\(reps) × \(formattedWeight) kg"
        case "bodyweight":
            return "\(reps) reps"
        case "timed":
            return formatDuration(durationSeconds)
        default:
            return "\(reps) × \(weight) kg"
        }
    }

    /// Short display for set tag
    var tagDisplay: String {
        switch tag {
        case "warmup": return "WU"
        case "working": return "WK"
        case "backoff": return "BO"
        default: return ""
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

// MARK: - Watch Rest Timer Info

/// Rest timer state for watch display
struct WatchRestTimerInfo: Codable, Hashable {
    var isActive: Bool
    var remainingSeconds: Int
    var totalSeconds: Int
    var endDate: Date
    var exerciseName: String?

    /// Progress fraction (0.0 to 1.0)
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, Double(remainingSeconds) / Double(totalSeconds)))
    }

    /// Check if timer has finished
    var isFinished: Bool {
        remainingSeconds <= 0
    }

    /// Display text for remaining time
    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Watch Messages

/// Messages sent from watch to iPhone
enum WatchMessage: String, Codable {
    case completeSet = "completeSet"
    case navigateToExercise = "navigateToExercise"
    case requestWorkoutState = "requestWorkoutState"
    case startRestTimer = "startRestTimer"
    case pauseRestTimer = "pauseRestTimer"
    case resumeRestTimer = "resumeRestTimer"
    case skipRestTimer = "skipRestTimer"
    case startSet = "startSet"
    case addAndStartSet = "addAndStartSet"
    case startQuickWorkout = "startQuickWorkout"
    case startWatchWorkout = "startWatchWorkout"    // iOS → Watch: Start HKWorkoutSession
    case endWatchWorkout = "endWatchWorkout"        // iOS → Watch: End & save HKWorkoutSession
    case discardWatchWorkout = "discardWatchWorkout" // iOS → Watch: Discard HKWorkoutSession (don't save)

    // Virtual Run messages
    case vrSnapshot = "vr_snapshot"              // Watch → iOS: My latest stats
    case vrHeartbeat = "vr_heartbeat"            // Bidirectional: Keep-alive
    case vrPartnerUpdate = "vr_partner"          // iOS → Watch: Partner's latest stats
    case vrRunStarted = "vr_started"             // iOS → Watch: Run accepted, start tracking
    case vrRunEnded = "vr_ended"                 // Bidirectional: Run completed
    case vrPartnerFinished = "vr_partner_finished" // iOS → Watch: Partner ended their run
    case vrWatchConfirmed = "vr_watch_confirmed"   // Watch → iOS: User confirmed, countdown started
    case vrPause = "vr_pause"                    // Watch → iOS: User paused the run
    case vrResume = "vr_resume"                  // Watch → iOS: User resumed the run
}

/// Payload for completing a set
struct CompleteSetPayload: Codable {
    var exerciseID: String
    var entryID: String
    var setIndex: Int
}

/// Payload for navigating to an exercise
struct NavigateToExercisePayload: Codable {
    var exerciseIndex: Int
}

/// Payload for starting rest timer
struct StartRestTimerPayload: Codable {
    var durationSeconds: Int
    var exerciseName: String?
}

/// Payload for starting a set (marks it as in progress)
struct StartSetPayload: Codable {
    var exerciseID: String
    var entryID: String
    var setIndex: Int
}

/// Payload for adding a new set based on the last one
struct AddAndStartSetPayload: Codable {
    var exerciseID: String
    var entryID: String
}
