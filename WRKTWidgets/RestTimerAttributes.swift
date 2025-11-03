//
//  RestTimerAttributes.swift
//  WRKT
//
//  Activity Attributes for Rest Timer Live Activity
//  Defines the data model for the live activity
//

import Foundation
import ActivityKit

/// Attributes for Rest Timer Live Activity
/// This defines both static data (doesn't change) and dynamic content state (updates frequently)
struct RestTimerAttributes: ActivityAttributes {

    /// Dynamic content that updates during the live activity
    public struct ContentState: Codable, Hashable {
        /// Remaining seconds in the timer
        var remainingSeconds: Int

        /// Absolute end date of the timer
        var endDate: Date

        /// Whether the timer is currently paused
        var isPaused: Bool

        /// Progress from 0.0 (complete) to 1.0 (just started)
        var progress: Double

        /// Whether the timer duration was adjusted by the user
        var wasAdjusted: Bool

        /// Last update timestamp (helps with synchronization)
        var lastUpdate: Date
    }

    // MARK: - Static Attributes (Don't Change During Activity)

    /// Name of the exercise this rest period is for
    var exerciseName: String

    /// Original duration in seconds when timer started
    var originalDuration: Int

    /// Unique identifier for the exercise
    var exerciseID: String

    /// Optional workout name for context
    var workoutName: String?

    /// Start time of the timer
    var startTime: Date
}
