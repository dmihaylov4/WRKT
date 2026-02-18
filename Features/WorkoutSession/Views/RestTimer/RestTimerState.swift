//
//  RestTimerState.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 20.10.25.
//

import Foundation
import SwiftUI
import Combine
import ActivityKit
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
    @Published private(set) var timerStartDate: Date? = nil  // Track when current timer was started
    @Published private(set) var isManuallyStartedTimer: Bool = false  // True if started from widget without logging a set

    // MARK: - Private Properties
    private var timer: AnyCancellable?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var hasTriggeredTenSecondWarning = false
    private var commandObserverTimer: AnyCancellable?
    private var lastCommandTimestamp: TimeInterval

    // Store last exercise info for widget commands
    private var lastExerciseID: String?
    private var lastExerciseName: String?

    // UserDefaults keys for background persistence
    private enum Keys {
        static let timerEndDate = "rest_timer_end_date"
        static let timerExerciseID = "rest_timer_exercise_id"
        static let timerExerciseName = "rest_timer_exercise_name"
        static let timerDuration = "rest_timer_duration"
        static let pendingSetGeneration = "pending_set_generation_exercises"
    }

    // App Group for sharing data with Widget Extension
    private let appGroupIdentifier = "group.com.dmihaylov.trak.shared"

    // Command keys (must match RestTimerAppIntents.swift)
    private enum CommandKey {
        static let adjustTime = "restTimer.command.adjustTime"
        static let pause = "restTimer.command.pause"
        static let resume = "restTimer.command.resume"
        static let skip = "restTimer.command.skip"
        static let stop = "restTimer.command.stop"
        static let startNextSet = "restTimer.command.startNextSet"
        static let timestamp = "restTimer.command.timestamp"
    }

    // MARK: - Initialization
    private init() {
        // Initialize lastCommandTimestamp from UserDefaults to avoid processing stale commands
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            self.lastCommandTimestamp = sharedDefaults.double(forKey: CommandKey.timestamp)

            // Clean up any leftover command flags from previous session
            sharedDefaults.removeObject(forKey: CommandKey.stop)
            sharedDefaults.removeObject(forKey: CommandKey.skip)
            sharedDefaults.removeObject(forKey: CommandKey.pause)
            sharedDefaults.removeObject(forKey: CommandKey.resume)
            sharedDefaults.removeObject(forKey: CommandKey.adjustTime)
            sharedDefaults.removeObject(forKey: CommandKey.startNextSet)

            
        } else {
            self.lastCommandTimestamp = 0
            
        }

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

        // Start observing commands from Widget Extension
        startObservingWidgetCommands()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        commandObserverTimer?.cancel()
    }

    // MARK: - Public API

    /// Start a new rest timer
    /// - Parameters:
    ///   - isManualStart: True if started from widget without logging a set, false if started after logging a set in-app
    func startTimer(duration: TimeInterval, exerciseID: String, exerciseName: String, isManualStart: Bool = false) {
        // Cancel any existing timer
        stopTimer()

        // Store exercise info for widget commands
        lastExerciseID = exerciseID
        lastExerciseName = exerciseName

        let endDate = Date().addingTimeInterval(duration)
        let startDate = Date()

        // Save to UserDefaults for background persistence
        UserDefaults.standard.set(endDate, forKey: Keys.timerEndDate)
        UserDefaults.standard.set(exerciseID, forKey: Keys.timerExerciseID)
        UserDefaults.standard.set(exerciseName, forKey: Keys.timerExerciseName)
        UserDefaults.standard.set(duration, forKey: Keys.timerDuration)

        // Update state
        state = .running(endDate: endDate, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: duration, wasAdjusted: false)
        remainingSeconds = duration
        timerStartDate = startDate  // Track when this timer was started
        isManuallyStartedTimer = isManualStart  // Track if this was started from widget
        hasTriggeredTenSecondWarning = false

        // Start Live Activity
        Task { @MainActor in
            LiveActivityManager.shared.startRestTimerActivity(
                exerciseName: exerciseName,
                exerciseID: exerciseID,
                duration: duration,
                endDate: endDate
            )
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
        clearBackgroundTask()
        clearUserDefaults()

        // End Live Activity
        Task { @MainActor in
            LiveActivityManager.shared.endRestTimerActivity(dismissalPolicy: .immediate)
        }

        state = .idle
        remainingSeconds = 0
        timerStartDate = nil  // Clear timer start timestamp
        isManuallyStartedTimer = false  // Clear manual start flag
        hasTriggeredTenSecondWarning = false
    }

    /// Skip the remaining time and mark as completed (generates next set)
    func skipTimer() {
        guard case .running(_, let exerciseID, let exerciseName, _, _) = state else { return }

        // Store exercise info before clearing state
        lastExerciseID = exerciseID
        lastExerciseName = exerciseName

        // Complete the timer early - this will generate the next set
        timer?.cancel()
        timer = nil
        clearBackgroundTask()
        clearUserDefaults()

        // Mark as completed so new set gets generated
        state = .completed(exerciseID: exerciseID, exerciseName: exerciseName)
        remainingSeconds = 0
        hasTriggeredTenSecondWarning = false

        // Mark that this exercise needs a new set generated
        markPendingSetGeneration(for: exerciseID)

        // IMPORTANT: Stop LiveActivityManager's auto-update loop BEFORE updating to "Ready" state
        // Otherwise the loop will recalculate remaining time and overwrite our update
        Task { @MainActor in
            LiveActivityManager.shared.stopUpdateLoop()

            // Update Live Activity to show "Ready" state (0 time remaining, not paused)
            LiveActivityManager.shared.updateRestTimer(
                remainingSeconds: 0,
                endDate: Date(),
                isPaused: false,
                wasAdjusted: false
            )
        }

        // Auto-dismiss completed state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if case .completed = self.state {
                self.state = .idle
            }
        }

        // Haptic feedback for completion
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Start a new rest timer for the next set (called from widget)
    func startNextSetTimer() {
        // Get exercise info from current state
        let exerciseInfo: (id: String, name: String)?

        switch state {
        case .completed(let exerciseID, let exerciseName):
            exerciseInfo = (exerciseID, exerciseName)
        case .running(_, let exerciseID, let exerciseName, _, _):
            // If timer is running, skip it first
            skipTimer()
            exerciseInfo = (exerciseID, exerciseName)
        case .paused(_, let exerciseID, let exerciseName, _, _):
            exerciseInfo = (exerciseID, exerciseName)
        case .idle:
            // Use last stored exercise info as fallback
            if let lastExerciseID = lastExerciseID, let lastExerciseName = lastExerciseName {
                exerciseInfo = (lastExerciseID, lastExerciseName)
                
            } else {
                exerciseInfo = nil
            }
        }

        // If we don't have exercise info, can't start timer
        guard let (exerciseID, exerciseName) = exerciseInfo else {
            
            return
        }

       

        // Post notification to trigger immediate set generation AND log it as completed
        // This ensures the set is created and logged BEFORE the timer starts showing in UI
        NotificationCenter.default.post(
            name: NSNotification.Name("GeneratePendingSetBeforeTimer"),
            object: nil,
            userInfo: [
                "exerciseID": exerciseID,
                "shouldLogSet": true  // Mark the generated set as completed immediately
            ]
        )

        // Small delay to allow set generation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            // Get rest duration from preferences
            let restDuration = self.getRestDuration()

            // Start new rest timer (NOT marked as manual - this is like logging a set from the app)
            // The widget "Start Next Set" button logs a set AND starts a timer, just like in-app
            self.startTimer(duration: restDuration, exerciseID: exerciseID, exerciseName: exerciseName, isManualStart: false)

            

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Get rest duration from user preferences
    /// Reads the last used timer duration for the current exercise from UserDefaults
    private func getRestDuration() -> TimeInterval {
        // Try to read the last used timer duration (stored when timer was started)
        // This will be the exercise-specific duration that was used
        let defaults = UserDefaults.standard
        let storedDuration = defaults.double(forKey: Keys.timerDuration)

        // If we have a stored duration, use it (this preserves exercise-specific settings)
        if storedDuration > 0 {
            return storedDuration
        }

        // Fall back to default if no stored duration
        return 90 // Default 90 seconds
    }

    /// Pause the timer
    func pauseTimer() {
        guard case .running(_, let exerciseID, let exerciseName, let originalDuration, let wasAdjusted) = state else { return }

        timer?.cancel()
        timer = nil

        state = .paused(remainingSeconds: remainingSeconds, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: originalDuration, wasAdjusted: wasAdjusted)

        // Update Live Activity to paused state
        Task { @MainActor in
            LiveActivityManager.shared.updateRestTimer(
                remainingSeconds: Int(remainingSeconds),
                endDate: Date().addingTimeInterval(remainingSeconds),
                isPaused: true,
                wasAdjusted: wasAdjusted
            )
        }
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

        // Update Live Activity to running state
        Task { @MainActor in
            LiveActivityManager.shared.updateRestTimer(
                remainingSeconds: Int(remaining),
                endDate: endDate,
                isPaused: false,
                wasAdjusted: wasAdjusted
            )
        }

        startTimerLoop()
    }

    /// Add or subtract time from running timer
    func adjustTime(by seconds: TimeInterval) {
        guard case .running(let endDate, let exerciseID, let exerciseName, let originalDuration, _) = state else { return }

        let newEndDate = endDate.addingTimeInterval(seconds)
        let newRemaining = max(0, remainingSeconds + seconds)

        // Reset warning flag if we added time
        if seconds > 0 && newRemaining > 10 {
            hasTriggeredTenSecondWarning = false
        }

        // Update state - set wasAdjusted to true and update originalDuration to new total
        // This ensures progress bar works correctly after adjustments
        state = .running(endDate: newEndDate, exerciseID: exerciseID, exerciseName: exerciseName, originalDuration: newRemaining, wasAdjusted: true)
        remainingSeconds = newRemaining

        // Update UserDefaults
        UserDefaults.standard.set(newEndDate, forKey: Keys.timerEndDate)
        UserDefaults.standard.set(newRemaining, forKey: Keys.timerDuration)

        // Update Live Activity
        Task { @MainActor in
            LiveActivityManager.shared.updateRestTimer(
                remainingSeconds: Int(newRemaining),
                endDate: newEndDate,
                isPaused: false,
                wasAdjusted: true
            )
        }

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
        // Store exercise info before clearing state
        lastExerciseID = exerciseID
        lastExerciseName = exerciseName

        timer?.cancel()
        timer = nil
        clearBackgroundTask()
        clearUserDefaults()

        state = .completed(exerciseID: exerciseID, exerciseName: exerciseName)
        remainingSeconds = 0
        hasTriggeredTenSecondWarning = false

        // Mark that this exercise needs a new set generated
        markPendingSetGeneration(for: exerciseID)

        // Note: LiveActivityManager's auto-update loop will stop itself when remaining <= 0
        // See LiveActivityManager.startUpdateLoop() - it checks and stops when timer reaches 0

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

        // Restore last exercise info
        lastExerciseID = exerciseID
        lastExerciseName = exerciseName

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
        // IMPORTANT: Check for pending widget commands BEFORE restoring timer
        // This prevents race condition where timer gets restored before skip command is processed
        checkForWidgetCommands()

        // Restore timer state (if not already cleared by widget command)
        restoreTimerIfNeeded()
        clearBackgroundTask()
    }

    private func beginBackgroundTask() {
        // Don't create a new task if one already exists
        guard backgroundTask == .invalid else {
            AppLogger.debug("Background task already active, skipping", category: AppLogger.app)
            return
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            AppLogger.warning("Background task expired, cleaning up", category: AppLogger.app)
            self?.clearBackgroundTask()
        }

        // Verify task was successfully allocated
        if backgroundTask == .invalid {
            AppLogger.error("Failed to allocate background task", category: AppLogger.app)
        } else {
            AppLogger.debug("Background task started: \(backgroundTask.rawValue)", category: AppLogger.app)
        }
    }

    private func clearBackgroundTask() {
        guard backgroundTask != .invalid else { return }

        AppLogger.debug("Ending background task: \(backgroundTask.rawValue)", category: AppLogger.app)
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }


    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.timerEndDate)
        UserDefaults.standard.removeObject(forKey: Keys.timerExerciseID)
        UserDefaults.standard.removeObject(forKey: Keys.timerExerciseName)
        // Don't clear Keys.timerDuration - keep it so the next timer can reuse the exercise-specific duration
        // This allows "Log Next Set" from widget to use the correct rest time for the exercise
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
        let currentDuration = (remainingSeconds.rounded()).safeInt
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

    // MARK: - Widget Extension Command Observation

    /// Start observing commands from Widget Extension
    private func startObservingWidgetCommands() {
        // Check for commands every 0.5 seconds
        commandObserverTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForWidgetCommands()
            }
    }

    /// Check for and process commands from Widget Extension
    private func checkForWidgetCommands() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            
            return
        }

        // Check if there's a new command based on timestamp
        let currentTimestamp = sharedDefaults.double(forKey: CommandKey.timestamp)
        guard currentTimestamp > lastCommandTimestamp else {
            return // No new commands
        }

       
        lastCommandTimestamp = currentTimestamp

        // Process commands in priority order
        if sharedDefaults.bool(forKey: CommandKey.stop) {
            
            sharedDefaults.removeObject(forKey: CommandKey.stop)
            stopTimer()
            return
        }

        if sharedDefaults.bool(forKey: CommandKey.skip) {
           
            sharedDefaults.removeObject(forKey: CommandKey.skip)
            skipTimer()
            return
        }

        if sharedDefaults.bool(forKey: CommandKey.startNextSet) {
           
            sharedDefaults.removeObject(forKey: CommandKey.startNextSet)
            startNextSetTimer()
            return
        }

        if sharedDefaults.bool(forKey: CommandKey.pause) {
            
            sharedDefaults.removeObject(forKey: CommandKey.pause)
            pauseTimer()
            return
        }

        if sharedDefaults.bool(forKey: CommandKey.resume) {
            
            sharedDefaults.removeObject(forKey: CommandKey.resume)
            resumeTimer()
            return
        }

        if let seconds = sharedDefaults.object(forKey: CommandKey.adjustTime) as? Int {
            
            sharedDefaults.removeObject(forKey: CommandKey.adjustTime)
            adjustTime(by: TimeInterval(seconds))
            return
        }

       
    }
}
