//
//  LiveActivityManager.swift
//  WRKT
//
//  Manages Live Activities for rest timers and workouts
//  Handles starting, updating, and ending live activities
//

import Foundation
import ActivityKit
import SwiftUI
import Combine
/// Manager for Live Activities
/// Coordinates between the app and the Live Activity widget
@MainActor
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    // MARK: - Published State

    @Published private(set) var isActivityActive: Bool = false
    @Published private(set) var activityID: String?

    // MARK: - Private Properties

    private var currentRestTimerActivity: Activity<RestTimerAttributes>?
    private var updateTimer: Timer?

    // MARK: - Initialization

    private init() {
        // Check if there's an active activity on launch
        checkForActiveActivities()
    }

    // MARK: - Rest Timer Activity

    /// Start or update Live Activity for a rest timer
    func startRestTimerActivity(
        exerciseName: String,
        exerciseID: String,
        duration: TimeInterval,
        endDate: Date,
        workoutName: String? = nil
    ) {
        // Check if Live Activities are supported (iOS 16.1+)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            AppLogger.warning("Live Activities not supported or disabled", category: AppLogger.app)
            return
        }

        // If there's already an active activity, just update it with new exercise info
        if let existingActivity = currentRestTimerActivity {
            AppLogger.debug("Updating existing Live Activity for new exercise: \(exerciseName)", category: AppLogger.app)

            // Update attributes to show new exercise
            let attributes = RestTimerAttributes(
                exerciseName: exerciseName,
                originalDuration: Int(duration),
                exerciseID: exerciseID,
                workoutName: workoutName,
                startTime: Date()
            )

            // Note: We can't update attributes of an existing activity, so we need to end and restart
            // But we'll do it smoothly
            Task {
                await existingActivity.end(nil, dismissalPolicy: .immediate)

                // Small delay to avoid flickering
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

                await createNewActivity(
                    exerciseName: exerciseName,
                    exerciseID: exerciseID,
                    duration: duration,
                    endDate: endDate,
                    workoutName: workoutName
                )
            }
            return
        }

        // No existing activity - create new one
        Task {
            await createNewActivity(
                exerciseName: exerciseName,
                exerciseID: exerciseID,
                duration: duration,
                endDate: endDate,
                workoutName: workoutName
            )
        }
    }

    /// Create a new Live Activity
    private func createNewActivity(
        exerciseName: String,
        exerciseID: String,
        duration: TimeInterval,
        endDate: Date,
        workoutName: String?
    ) async {
        let attributes = RestTimerAttributes(
            exerciseName: exerciseName,
            originalDuration: Int(duration),
            exerciseID: exerciseID,
            workoutName: workoutName,
            startTime: Date()
        )

        let contentState = RestTimerAttributes.ContentState(
            remainingSeconds: Int(duration),
            endDate: endDate,
            isPaused: false,
            progress: 1.0,
            wasAdjusted: false,
            lastUpdate: Date()
        )

        do {
            let activity = try Activity<RestTimerAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )

            currentRestTimerActivity = activity
            isActivityActive = true
            activityID = activity.id

            // Schedule the single "Ready" update at completion time
            scheduleCompletionUpdate(endDate: endDate)

            AppLogger.success("Live Activity started for \(exerciseName)", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to start Live Activity: \(error.localizedDescription)", category: AppLogger.app)
        }
    }

    /// Update the rest timer Live Activity with new state
    func updateRestTimer(
        remainingSeconds: Int,
        endDate: Date,
        isPaused: Bool,
        wasAdjusted: Bool
    ) {
        guard let activity = currentRestTimerActivity else {
            AppLogger.warning("No active Live Activity to update", category: AppLogger.app)
            return
        }

        let totalDuration = Double(activity.attributes.originalDuration)
        let progress = totalDuration > 0 ? max(0, min(1, Double(remainingSeconds) / totalDuration)) : 0

        let contentState = RestTimerAttributes.ContentState(
            remainingSeconds: max(0, remainingSeconds),
            endDate: endDate,
            isPaused: isPaused,
            progress: progress,
            wasAdjusted: wasAdjusted,
            lastUpdate: Date()
        )

        Task {
            await activity.update(.init(state: contentState, staleDate: nil))
        }

        // Keep the single completion update in sync with the new end date.
        // remainingSeconds <= 0 covers both the Ready update itself and skip.
        if isPaused || remainingSeconds <= 0 {
            cancelScheduledCompletionUpdate()
        } else {
            scheduleCompletionUpdate(endDate: endDate)
        }
    }

    /// End the rest timer Live Activity
    func endRestTimerActivity(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        cancelScheduledCompletionUpdate()

        guard let activity = currentRestTimerActivity else {
            return
        }

        Task {
            // Show completion state briefly before dismissing
            let finalState = RestTimerAttributes.ContentState(
                remainingSeconds: 0,
                endDate: Date(),
                isPaused: false,
                progress: 0,
                wasAdjusted: activity.content.state.wasAdjusted,
                lastUpdate: Date()
            )

            await activity.update(.init(state: finalState, staleDate: nil))

            // Wait a moment before dismissing
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await activity.end(nil, dismissalPolicy: dismissalPolicy)
        }

        currentRestTimerActivity = nil
        isActivityActive = false
        activityID = nil

        AppLogger.debug("Live Activity ended", category: AppLogger.app)
    }

    // MARK: - Completion Update Scheduling

    /// The widget renders the running countdown itself via Text(timerInterval:)
    /// and ProgressView(timerInterval:), so no per-second pushes are needed.
    /// The one thing ActivityKit cannot do on its own is re-evaluate the
    /// "Ready" branches (endDate <= Date()) when the timer hits zero, so we
    /// schedule exactly one update at endDate. Pause/resume/adjust/skip all
    /// go through updateRestTimer, which reschedules or cancels this.
    private func scheduleCompletionUpdate(endDate: Date) {
        cancelScheduledCompletionUpdate()

        let interval = max(0.1, endDate.timeIntervalSinceNow + 0.25)
        // Timer(timeInterval:) + RunLoop.main.add rather than Timer.scheduledTimer:
        // scheduledTimer auto-adds to .default mode; adding the same instance to
        // .common would fire it twice because .common includes .default.
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self,
                  let activity = self.currentRestTimerActivity else { return }

            let state = activity.content.state

            // A pause that raced the timer means the countdown is no longer
            // ending now; skip and let resume reschedule.
            guard !state.isPaused else { return }

            // Single "Ready" update (0 remaining, not paused).
            self.updateRestTimer(
                remainingSeconds: 0,
                endDate: state.endDate,
                isPaused: false,
                wasAdjusted: state.wasAdjusted
            )
            AppLogger.debug("Rest timer completed - Live Activity flipped to Ready state", category: AppLogger.app)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// Cancels the pending completion update (if any)
    func cancelScheduledCompletionUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Activity Management

    /// Check for any existing active activities on app launch
    private func checkForActiveActivities() {
        let activities = Activity<RestTimerAttributes>.activities
        if let activity = activities.first {
            currentRestTimerActivity = activity
            isActivityActive = true
            activityID = activity.id

            // Re-arm the single completion update if still counting down
            let state = activity.content.state
            if !state.isPaused && state.endDate > Date() {
                scheduleCompletionUpdate(endDate: state.endDate)
            }

            AppLogger.debug("Restored active Live Activity: \(activity.id)", category: AppLogger.app)
        }
    }

    /// Force end all activities (cleanup)
    func endAllActivities() {
        Task {
            for activity in Activity<RestTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        currentRestTimerActivity = nil
        isActivityActive = false
        activityID = nil
        cancelScheduledCompletionUpdate()
    }
}

// MARK: - Convenience Helpers

extension LiveActivityManager {
    /// Check if Live Activities are available on this device
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Get the current activity state (if any)
    var currentActivityState: RestTimerAttributes.ContentState? {
        currentRestTimerActivity?.content.state
    }

    /// Get the current activity attributes (if any)
    var currentActivityAttributes: RestTimerAttributes? {
        currentRestTimerActivity?.attributes
    }
}
