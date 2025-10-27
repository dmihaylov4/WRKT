//
//  RestTimerState.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 20.10.25.
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

/// Timer state
enum RestTimerState: Equatable {
    case idle
    case running(endDate: Date, exerciseID: String, exerciseName: String, originalDuration: TimeInterval, wasAdjusted: Bool)
    case paused(remainingSeconds: TimeInterval, exerciseID: String, exerciseName: String, originalDuration: TimeInterval, wasAdjusted: Bool)
    case completed(exerciseID: String, exerciseName: String)
}

/// Single source of truth for rest timer state across the app
class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()

    // MARK: - Published State
    @Published private(set) var state: RestTimerState = .idle
    @Published private(set) var remainingSeconds: TimeInterval = 0

    // MARK: - Private Properties
    private var timer: AnyCancellable?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var hasTriggeredTenSecondWarning = false

    // UserDefaults keys for background persistence
    private enum Keys {
        static let timerEndDate = "rest_timer_end_date"
        static let timerExerciseID = "rest_timer_exercise_id"
        static let timerExerciseName = "rest_timer_exercise_name"
        static let timerDuration = "rest_timer_duration"
        static let pendingSetGeneration = "pending_set_generation_exercises"
    }

    // MARK: - Initialization
    private init() {
        // Restore timer if app was backgrounded
        restoreTimerIfNeeded()

        // Listen for app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Start a new rest timer
    func startTimer(duration: TimeInterval, exerciseID: String, exerciseName: String) {
        // Cancel any existing timer
        stopTimer()

        let endDate = Date().addingTimeInterval(duration)

        // Save to UserDefaults for background persistence
        UserDefaults.standard.set(endDate, forKey: Keys.timerEndDate)
        UserDefaults.standard.set(exerciseID, forKey: Keys.timerExerciseID)
        UserDefaults.standard.set(exerciseName, forKey: Keys.timerExerciseName)
        UserDefaults.standard.set(duration, forKey: Keys.timerDuration)

        // Update state
        state = .running(endDate: endDate, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: duration, wasAdjusted: false)
        remainingSeconds = duration
        hasTriggeredTenSecondWarning = false

        // Schedule completion notification
        scheduleCompletionNotification(endDate: endDate, exerciseName: exerciseName)

        // Schedule 10-second warning notification
        if duration > 10 {
            scheduleTenSecondWarning(endDate: endDate, exerciseName: exerciseName)
        }

        // Start the timer
        startTimerLoop()

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Stop/cancel the timer
    func stopTimer() {
        // Clear pending set generation if timer is stopped for current exercise
        if let exerciseID = currentExerciseID {
            clearPendingSetGeneration(for: exerciseID)
        }

        timer?.cancel()
        timer = nil
        cancelAllNotifications()
        clearBackgroundTask()
        clearUserDefaults()

        state = .idle
        remainingSeconds = 0
        hasTriggeredTenSecondWarning = false
    }

    /// Skip the remaining time and cancel (without generating next set)
    func skipTimer() {
        guard case .running(_, let exerciseID, _, _, _) = state else { return }

        // Don't complete - just cancel and go to idle
        // This prevents the ExerciseSessionView observer from generating a new set
        timer?.cancel()
        timer = nil
        cancelAllNotifications()
        clearBackgroundTask()
        clearUserDefaults()

        // Clear any pending set generation flag for this exercise
        clearPendingSetGeneration(for: exerciseID)

        state = .idle
        remainingSeconds = 0
        hasTriggeredTenSecondWarning = false

        // Haptic feedback for cancellation
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Pause the timer
    func pauseTimer() {
        guard case .running(_, let exerciseID, let exerciseName, let originalDuration, let wasAdjusted) = state else { return }

        timer?.cancel()
        timer = nil
        cancelAllNotifications()

        state = .paused(remainingSeconds: remainingSeconds, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: originalDuration, wasAdjusted: wasAdjusted)
    }

    /// Resume from paused state
    func resumeTimer() {
        guard case .paused(let remaining, let exerciseID, let exerciseName, let originalDuration, let wasAdjusted) = state else { return }

        let endDate = Date().addingTimeInterval(remaining)

        // Save to UserDefaults
        UserDefaults.standard.set(endDate, forKey: Keys.timerEndDate)
        UserDefaults.standard.set(exerciseID, forKey: Keys.timerExerciseID)
        UserDefaults.standard.set(exerciseName, forKey: Keys.timerExerciseName)
        UserDefaults.standard.set(remaining, forKey: Keys.timerDuration)

        state = .running(endDate: endDate, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: originalDuration, wasAdjusted: wasAdjusted)
        remainingSeconds = remaining

        // Schedule completion notification
        scheduleCompletionNotification(endDate: endDate, exerciseName: exerciseName)

        // Schedule 10-second warning if we still have time
        if remaining > 10 {
            scheduleTenSecondWarning(endDate: endDate, exerciseName: exerciseName)
            hasTriggeredTenSecondWarning = false
        }

        startTimerLoop()
    }

    /// Add or subtract time from running timer
    func adjustTime(by seconds: TimeInterval) {
        guard case .running(let endDate, let exerciseID, let exerciseName, let originalDuration, _) = state else { return }

        let newEndDate = endDate.addingTimeInterval(seconds)
        let newRemaining = max(0, remainingSeconds + seconds)

        // Cancel old notifications and schedule new ones
        cancelAllNotifications()
        scheduleCompletionNotification(endDate: newEndDate, exerciseName: exerciseName)

        if newRemaining > 10 {
            scheduleTenSecondWarning(endDate: newEndDate, exerciseName: exerciseName)
            hasTriggeredTenSecondWarning = false
        }

        // Update state - set wasAdjusted to true and update originalDuration to new total
        // This ensures progress bar works correctly after adjustments
        state = .running(endDate: newEndDate, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: newRemaining, wasAdjusted: true)
        remainingSeconds = newRemaining

        // Update UserDefaults
        UserDefaults.standard.set(newEndDate, forKey: Keys.timerEndDate)
        UserDefaults.standard.set(newRemaining, forKey: Keys.timerDuration)

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Dismiss completed state
    func dismissCompleted() {
        guard case .completed = state else { return }
        state = .idle
        remainingSeconds = 0
    }

    // MARK: - Private Methods

    private func startTimerLoop() {
        // Update every 0.1 seconds for smooth countdown
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTimer()
            }
    }

    private func updateTimer() {
        guard case .running(let endDate, let exerciseID, let exerciseName, _, _) = state else {
            timer?.cancel()
            return
        }

        let remaining = endDate.timeIntervalSinceNow

        if remaining <= 0 {
            // Timer completed naturally - generate next set
            completeTimer(exerciseID: exerciseID, exerciseName: exerciseName, vibrate: true)
        } else {
            remainingSeconds = remaining

            // Trigger 10-second warning vibration (only once)
            if remaining <= 10 && remaining > 9.5 && !hasTriggeredTenSecondWarning {
                hasTriggeredTenSecondWarning = true
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                // Double tap pattern
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    generator.impactOccurred()
                }
            }
        }
    }

    private func completeTimer(exerciseID: String, exerciseName: String, vibrate: Bool) {
        timer?.cancel()
        timer = nil
        clearBackgroundTask()
        clearUserDefaults()
        cancelAllNotifications()

        state = .completed(exerciseID: exerciseID, exerciseName: exerciseName)
        remainingSeconds = 0
        hasTriggeredTenSecondWarning = false

        // Mark that this exercise needs a new set generated
        markPendingSetGeneration(for: exerciseID)

        if vibrate {
            // Strong haptic pattern for completion - triple pulse
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()

            // First pulse
            generator.notificationOccurred(.success)

            // Second pulse
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                generator.notificationOccurred(.success)
            }

            // Third pulse
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                generator.notificationOccurred(.success)
            }
        }

        // Auto-dismiss completed state after 3 seconds to show workout timer again
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if case .completed = self.state {
                self.state = .idle
            }
        }
    }

    private func restoreTimerIfNeeded() {
        guard let endDate = UserDefaults.standard.object(forKey: Keys.timerEndDate) as? Date,
              let exerciseID = UserDefaults.standard.string(forKey: Keys.timerExerciseID),
              let exerciseName = UserDefaults.standard.string(forKey: Keys.timerExerciseName),
              let originalDuration = UserDefaults.standard.object(forKey: Keys.timerDuration) as? TimeInterval else {
            return
        }

        let remaining = endDate.timeIntervalSinceNow

        if remaining > 0 {
            // Timer is still running
            // Assume it might have been adjusted if remaining != originalDuration
            let wasAdjusted = abs(remaining - originalDuration) > 1.0
            state = .running(endDate: endDate, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: originalDuration, wasAdjusted: wasAdjusted)
            remainingSeconds = remaining
            startTimerLoop()
        } else {
            // Timer completed while in background (natural completion - generate next set)
            completeTimer(exerciseID: exerciseID, exerciseName: exerciseName, vibrate: false)
        }
    }

    // MARK: - Background Support

    @objc private func appDidEnterBackground() {
        // Save state to UserDefaults (already done in startTimer)
        // Request background task to keep timer accurate
        beginBackgroundTask()
    }

    @objc private func appWillEnterForeground() {
        // Restore timer state
        restoreTimerIfNeeded()
        clearBackgroundTask()
    }

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.clearBackgroundTask()
        }
    }

    private func clearBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - Notifications

    private func scheduleCompletionNotification(endDate: Date, exerciseName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Rest Complete"
        content.body = "Time to start your next set of \(exerciseName)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(0.1, endDate.timeIntervalSinceNow),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "rest_timer_completion",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleTenSecondWarning(endDate: Date, exerciseName: String) {
        let content = UNMutableNotificationContent()
        content.title = "10 Seconds Remaining"
        content.body = "\(exerciseName) rest timer"
        content.sound = .default

        let warningTime = max(0.1, endDate.timeIntervalSinceNow - 10)

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: warningTime,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "rest_timer_warning",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func cancelAllNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["rest_timer_completion", "rest_timer_warning"]
        )
    }

    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.timerEndDate)
        UserDefaults.standard.removeObject(forKey: Keys.timerExerciseID)
        UserDefaults.standard.removeObject(forKey: Keys.timerExerciseName)
        UserDefaults.standard.removeObject(forKey: Keys.timerDuration)
    }
}

// MARK: - Helpers

extension RestTimerManager {
    var isActive: Bool {
        if case .idle = state {
            return false
        }
        return true
    }

    var isRunning: Bool {
        if case .running = state {
            return true
        }
        return false
    }

    var isCompleted: Bool {
        if case .completed = state {
            return true
        }
        return false
    }

    var currentExerciseID: String? {
        switch state {
        case .idle:
            return nil
        case .running(_, let id, _, _, _), .paused(_, let id, _, _, _), .completed(let id, _):
            return id
        }
    }

    var currentExerciseName: String? {
        switch state {
        case .idle:
            return nil
        case .running(_, _, let name, _, _), .paused(_, _, let name, _, _), .completed(_, let name):
            return name
        }
    }

    func isTimerFor(exerciseID: String) -> Bool {
        currentExerciseID == exerciseID
    }

    /// Check if timer has been adjusted from its original duration
    var hasBeenAdjusted: Bool {
        switch state {
        case .running(_, _, _, _, let wasAdjusted):
            return wasAdjusted
        case .paused(_, _, _, _, let wasAdjusted):
            return wasAdjusted
        default:
            return false
        }
    }

    /// Save current timer duration as default for this exercise
    func saveAsDefaultForCurrentExercise() {
        guard let exerciseID = currentExerciseID else { return }
        let currentDuration = Int(remainingSeconds.rounded())
        RestTimerPreferences.shared.setRestDuration(currentDuration, for: exerciseID)
    }

    /// Check if current timer is using a custom override
    var isUsingCustomTimer: Bool {
        guard let exerciseID = currentExerciseID else { return false }
        return RestTimerPreferences.shared.hasOverride(for: exerciseID)
    }

    // MARK: - Pending Set Generation Tracking

    /// Mark that an exercise needs a new set generated after timer completion
    private func markPendingSetGeneration(for exerciseID: String) {
        var pending = UserDefaults.standard.stringArray(forKey: Keys.pendingSetGeneration) ?? []
        if !pending.contains(exerciseID) {
            pending.append(exerciseID)
            UserDefaults.standard.set(pending, forKey: Keys.pendingSetGeneration)
        }
    }

    /// Check if an exercise has a pending set generation
    func hasPendingSetGeneration(for exerciseID: String) -> Bool {
        let pending = UserDefaults.standard.stringArray(forKey: Keys.pendingSetGeneration) ?? []
        return pending.contains(exerciseID)
    }

    /// Clear pending set generation for an exercise (call after set is generated)
    func clearPendingSetGeneration(for exerciseID: String) {
        var pending = UserDefaults.standard.stringArray(forKey: Keys.pendingSetGeneration) ?? []
        pending.removeAll { $0 == exerciseID }
        UserDefaults.standard.set(pending, forKey: Keys.pendingSetGeneration)
    }
}
