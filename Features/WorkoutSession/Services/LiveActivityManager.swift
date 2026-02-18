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
    private nonisolated func createNewActivity(
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

            await MainActor.run {
                self.currentRestTimerActivity = activity
                self.isActivityActive = true
                self.activityID = activity.id

                // Start auto-update loop
                self.startUpdateLoop()
            }

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
    }

    /// End the rest timer Live Activity
    func endRestTimerActivity(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        stopUpdateLoop()

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

    // MARK: - Auto-Update Loop

    /// Starts a timer that automatically updates the Live Activity every second
    private func startUpdateLoop() {
        stopUpdateLoop()

        // Update every second while timer is running
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let activity = self.currentRestTimerActivity else { return }

            let state = activity.content.state

            // Don't update if paused
            guard !state.isPaused else { return }

            let remaining = max(0, (state.endDate.timeIntervalSinceNow).safeInt)

            // Update countdown (even if 0 - to show "Ready" state)
            self.updateRestTimer(
                remainingSeconds: remaining,
                endDate: state.endDate,
                isPaused: false,
                wasAdjusted: state.wasAdjusted
            )

            // If timer completed, stop the update loop but KEEP the activity alive
            if remaining <= 0 {
                self.stopUpdateLoop()
                AppLogger.debug("Rest timer completed - keeping Live Activity alive in 'Ready' state", category: AppLogger.app)
            }
        }

        // Ensure timer runs even when app is in background
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        } else {
            AppLogger.error("Update timer is nil, cannot add to runloop", category: AppLogger.app)
        }
    }

    /// Stops the auto-update timer
    func stopUpdateLoop() {
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

            // Resume update loop if activity is still running
            if activity.content.state.remainingSeconds > 0 {
                startUpdateLoop()
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
        stopUpdateLoop()
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
