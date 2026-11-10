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
enum RestTimerState: Codable, Equatable {
    case idle
    case running(endDate: Date, exerciseID: String, exerciseName: String, originalDuration: TimeInterval, wasAdjusted: Bool)
    case paused(remainingSeconds: TimeInterval, exerciseID: String, exerciseName: String, originalDuration: TimeInterval, wasAdjusted: Bool)
    case completed(exerciseID: String, exerciseName: String)
}

/// Publishes the 1 Hz countdown in isolation. Only leaf views that render
/// the countdown observe this object; RestTimerManager itself publishes
/// only state transitions, so @ObservedObject observers of the manager
/// (LiveWorkoutOverlayCard, set rows, grab tab, completion toast) are no
/// longer invalidated every second. See RestTimerFanoutTests.
final class RestTimerTicker: ObservableObject {
    @Published fileprivate(set) var remainingSeconds: TimeInterval = 0
}

/// Single source of truth for rest timer state across the app
class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()

    // MARK: - Published State
    @Published private(set) var state: RestTimerState = .idle
    @Published private(set) var persistenceError: String?
    /// Per-second countdown, isolated so ticks do not invalidate observers
    /// of the manager itself. Read/observe via RestTimerManager.shared.ticker.
    let ticker = RestTimerTicker()
    @Published private(set) var timerStartDate: Date? = nil  // Track when current timer was started
    @Published private(set) var isManuallyStartedTimer: Bool = false  // True if started from widget without logging a set

    // MARK: - Private Properties
    private let defaults: UserDefaults
    private let storage: RestTimerStorage
    private let observesSystemEvents: Bool
    private var record = RestTimerRecord()
    private var didRestore = false
    private let now: () -> Date
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
        static let autoAddSetOnRestTimer = "auto_add_set_on_rest_timer"
    }

    // MARK: - Initialization
    init(
        defaults: UserDefaults = .standard,
        storage: RestTimerStorage = RestTimerStorage(),
        observeSystemEvents: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storage = storage
        self.observesSystemEvents = observeSystemEvents
        self.now = now
        // Legacy mailbox flags have neither workout identity nor a delivery receipt.
        // Clear them on upgrade; replay could mutate a different workout.
        if observeSystemEvents,
           let legacy = UserDefaults(suiteName: "group.com.dmihaylov.trak.shared") {
            for key in ["adjustTime", "pause", "resume", "skip", "stop", "startNextSet", "timestamp"] {
                legacy.removeObject(forKey: "restTimer.command." + key)
            }
        }

        // Restore timer if app was backgrounded
        restoreTimerIfNeeded()

        guard observeSystemEvents else { return }

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
    /// - Parameters:
    ///   - isManualStart: True if started from widget without logging a set, false if started after logging a set in-app
    func startTimer(duration: TimeInterval, exerciseID: String, exerciseName: String,
                    isManualStart: Bool = false, workoutID: UUID? = nil, entryID: UUID? = nil) {
        guard duration.isFinite, duration > 0, duration <= 86_400, !exerciseID.isEmpty else { return }
        let startDate = now()
        let endDate = startDate.addingTimeInterval(duration)
        var next = record
        next.id = UUID()
        next.appliedOperationIDs = nil
        next.state = .running(endDate: endDate, exerciseID: exerciseID, exerciseName: exerciseName,
            originalDuration: duration, wasAdjusted: false)
        next.startedAt = startDate
        next.nextRestDuration = duration
        next.isManualStart = isManualStart
        next.workoutID = workoutID
        next.entryID = entryID
        let previousExerciseID = currentExerciseID
        guard commit(next) else { return }
        if let previousExerciseID { clearPendingSetGeneration(for: previousExerciseID) }
        timer?.cancel()
        clearBackgroundTask()
        ticker.remainingSeconds = duration
        hasTriggeredTenSecondWarning = false

        // Start the timer
        startTimerLoop()

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Stop/cancel the timer
    func stopTimer(operationID: UUID? = nil) {
        let previousExerciseID = currentExerciseID
        var next = record
        next.state = .idle
        next.startedAt = nil
        next.isManualStart = false
        guard commit(next, operationID: operationID) else { return }
        // Clear pending set generation if timer is stopped for current exercise
        if let previousExerciseID {
            clearPendingSetGeneration(for: previousExerciseID)
        }

        timer?.cancel()
        timer = nil
        clearBackgroundTask()

        ticker.remainingSeconds = 0
        timerStartDate = nil  // Clear timer start timestamp
        isManuallyStartedTimer = false  // Clear manual start flag
        hasTriggeredTenSecondWarning = false
    }

    /// Skip the remaining time and mark as completed (generates next set)
    func skipTimer(operationID: UUID? = nil) {
        switch state {
        case .running(_, let id, let name, _, _), .paused(_, let id, let name, _, _):
            completeTimer(exerciseID: id, exerciseName: name, vibrate: true, operationID: operationID)
        case .idle, .completed:
            return
        }
    }

    /// The timer ID is the receipt ID: retrying this completed rest cannot log a second set.
    func startNextSetTimer(using store: WorkoutStoreV2) async throws {
        let source = record
        guard let workoutID = source.workoutID, let entryID = source.entryID else {
            throw StorageError.validationFailed("Open the workout in the app to log the next set.")
        }
        let exerciseID: String
        let exerciseName: String
        switch source.state {
        case .completed(let id, let name):
            (exerciseID, exerciseName) = (id, name)
        case .running(let endDate, let id, let name, _, _) where endDate <= now():
            (exerciseID, exerciseName) = (id, name)
        default:
            throw StorageError.validationFailed("Finish or skip this rest before logging the next set.")
        }
        _ = try await store.logNextSet(workoutID: workoutID, entryID: entryID, exerciseID: exerciseID,
            operationID: source.id, restDuration: source.nextRestDuration)
        let completedDuringSave = record.state == .completed(exerciseID: exerciseID, exerciseName: exerciseName)
        guard record.id == source.id, record.state == source.state || completedDuringSave,
              store.currentWorkout?.id == workoutID,
              store.currentWorkout?.entries.contains(where: { $0.id == entryID }) == true else {
            throw StorageError.validationFailed("The timer or workout changed while the set was saving.")
        }
        startTimer(duration: source.nextRestDuration, exerciseID: exerciseID, exerciseName: exerciseName,
            workoutID: workoutID, entryID: entryID)
        guard record.id != source.id else {
            throw StorageError.validationFailed("The set was saved, but the next rest could not start. Try again.")
        }
        NotificationCenter.default.post(name: .init("WorkoutSetCommitted"), object: nil,
            userInfo: ["exerciseID": exerciseID])
    }

    func perform(_ action: RestTimerAction, timerID: UUID, operationID: UUID,
                 using store: WorkoutStoreV2) async throws {
        do {
            try await store.waitForStorage()
            guard didRestore, record.id == timerID else {
                throw RestTimerIntentError("This timer is no longer current. Open your workout in the app.")
            }
            if record.appliedOperationIDs?.contains(operationID) == true {
                if observesSystemEvents { await LiveActivityManager.shared.waitForUpdates() }
                return
            }
            if case .nextSet = action {
                try await startNextSetTimer(using: store)
            } else {
                let previousRevision = record.revision
                switch action {
                case .adjust(let seconds): adjustTime(by: TimeInterval(seconds), operationID: operationID)
                case .pause: pauseTimer(operationID: operationID)
                case .resume: resumeTimer(operationID: operationID)
                case .skip: skipTimer(operationID: operationID)
                case .stop: stopTimer(operationID: operationID)
                case .nextSet: break
                }
                guard record.revision > previousRevision else {
                    throw RestTimerIntentError("This action could not be applied. Open your workout in the app.")
                }
            }
            if observesSystemEvents { await LiveActivityManager.shared.waitForUpdates() }
        } catch {
            let message: String
            if let error = error as? RestTimerIntentError {
                message = error.localizedDescription
            } else if let storageError = error as? StorageError, case .validationFailed(let reason) = storageError {
                message = reason
            } else {
                message = "The timer could not be updated. Open your workout in the app to try again."
            }
            persistenceError = message
            if observesSystemEvents, record.id == timerID {
                LiveActivityManager.shared.reconcile(record, errorMessage: message)
                await LiveActivityManager.shared.waitForUpdates()
            }
            throw RestTimerIntentError(message)
        }
    }

    /// Get rest duration from user preferences
    /// Adjusting the current countdown does not change the next rest preference.
    func getRestDuration() -> TimeInterval {
        record.nextRestDuration
    }

    /// Pause the timer
    func pauseTimer(operationID: UUID? = nil) {
        guard case .running(let endDate, let exerciseID, let exerciseName, let originalDuration, let wasAdjusted) = state else { return }

        let remaining = max(0, endDate.timeIntervalSince(now()))
        var next = record
        next.state = .paused(remainingSeconds: remaining, exerciseID: exerciseID, exerciseName: exerciseName,
            originalDuration: originalDuration, wasAdjusted: wasAdjusted)
        guard commit(next, operationID: operationID) else { return }
        timer?.cancel()
        timer = nil
        clearBackgroundTask()
        ticker.remainingSeconds = remaining
    }

    /// Resume from paused state
    func resumeTimer(operationID: UUID? = nil) {
        guard case .paused(let remaining, let exerciseID, let exerciseName, let originalDuration, let wasAdjusted) = state else { return }

        let endDate = now().addingTimeInterval(remaining)

        var next = record
        next.state = .running(endDate: endDate, exerciseID: exerciseID, exerciseName: exerciseName,
            originalDuration: originalDuration, wasAdjusted: wasAdjusted)
        guard commit(next, operationID: operationID) else { return }
        ticker.remainingSeconds = remaining

        startTimerLoop()
    }

    /// Adjust this rest without changing the next-rest preference.
    func adjustTime(by seconds: TimeInterval, operationID: UUID? = nil) {
        guard seconds.isFinite else { return }
        var next = record
        let remaining: TimeInterval
        switch state {
        case .running(let endDate, let id, let name, _, _):
            let newEndDate = endDate.addingTimeInterval(seconds)
            remaining = max(0, newEndDate.timeIntervalSince(now()))
            next.state = .running(endDate: newEndDate, exerciseID: id, exerciseName: name,
                originalDuration: remaining, wasAdjusted: true)
        case .paused(let previous, let id, let name, _, _):
            remaining = max(0, previous + seconds)
            next.state = .paused(remainingSeconds: remaining, exerciseID: id, exerciseName: name,
                originalDuration: remaining, wasAdjusted: true)
        case .idle, .completed:
            return
        }
        guard remaining.isFinite, remaining <= 86_400 else { return }
        guard commit(next, operationID: operationID) else { return }
        ticker.remainingSeconds = remaining
        if seconds > 0 && remaining > 10 { hasTriggeredTenSecondWarning = false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Dismiss completed state
    func dismissCompleted() {
        guard case .completed = state else { return }
        state = .idle
        ticker.remainingSeconds = 0
    }

    // MARK: - Private Methods

    private func startTimerLoop() {
        guard observesSystemEvents else { return }
        // Update every 1 second: display is whole seconds; progress bar uses
        // .animation(.linear(duration: 1.0)) to interpolate smoothly between ticks.
        // tolerance: 0.1 lets the OS batch this with other 1-second timers.
        timer = Timer.publish(every: 1.0, tolerance: 0.1, on: .main, in: .common)
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

        let remaining = endDate.timeIntervalSince(now())

        if remaining <= 0 {
            // Timer completed naturally. The next set is only generated if the
            // user's auto-add preference allows it.
            completeTimer(exerciseID: exerciseID, exerciseName: exerciseName, vibrate: true)
        } else {
            ticker.remainingSeconds = remaining

            // Trigger 10-second warning vibration (only once).
            // At 1 Hz the tick lands anywhere in the current second, so we fire on the
            // first tick at or below 10 s rather than requiring a precise window.
            if remaining <= 10 && !hasTriggeredTenSecondWarning {
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

    private func completeTimer(exerciseID: String, exerciseName: String, vibrate: Bool, operationID: UUID? = nil) {
        var next = record
        next.state = .completed(exerciseID: exerciseID, exerciseName: exerciseName)
        guard commit(next, operationID: operationID) else { return }
        timer?.cancel()
        timer = nil
        clearBackgroundTask()
        ticker.remainingSeconds = 0
        hasTriggeredTenSecondWarning = false

        if shouldAutoAddSetOnRestTimer {
            markPendingSetGeneration(for: exerciseID)
        } else {
            clearPendingSetGeneration(for: exerciseID)
        }

        if vibrate && observesSystemEvents {
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

        // Dismiss only this timer presentation; retain completion for relaunch/actions.
        let completedID = record.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.record.id == completedID, case .completed = self.state {
                self.state = .idle
            }
        }
    }

    private func restoreTimerIfNeeded() {
        do {
            if let saved = try storage.load() {
                record = saved
            } else if let endDate = defaults.object(forKey: Keys.timerEndDate) as? Date,
                      let exerciseID = defaults.string(forKey: Keys.timerExerciseID),
                      let exerciseName = defaults.string(forKey: Keys.timerExerciseName),
                      let duration = defaults.object(forKey: Keys.timerDuration) as? Double {
                // Legacy versions persisted running timers only. Never invent a paused state.
                var migrated = RestTimerRecord()
                migrated.state = .running(endDate: endDate, exerciseID: exerciseID,
                    exerciseName: exerciseName, originalDuration: duration, wasAdjusted: false)
                migrated.startedAt = endDate.addingTimeInterval(-duration)
                migrated.nextRestDuration = duration
                migrated.revision = 1
                try storage.save(migrated)
                record = migrated
            } else if defaults.object(forKey: Keys.timerEndDate) != nil
                || defaults.object(forKey: Keys.timerExerciseID) != nil
                || defaults.object(forKey: Keys.timerExerciseName) != nil {
                throw RestTimerStorageError.invalidRecord
            }
            didRestore = true
            clearLegacyTimerKeys()
            persistenceError = nil
            publishRecord()
            timer?.cancel()
            switch state {
            case .running(let endDate, let id, let name, _, _):
                ticker.remainingSeconds = max(0, endDate.timeIntervalSince(now()))
                if ticker.remainingSeconds > 0 {
                    startTimerLoop()
                } else {
                    completeTimer(exerciseID: id, exerciseName: name, vibrate: false)
                }
            case .paused(let remaining, _, _, _, _):
                ticker.remainingSeconds = remaining
            case .idle, .completed:
                ticker.remainingSeconds = 0
            }
        } catch {
            didRestore = false
            reportPersistenceError(error)
        }
    }

    private func commit(_ next: RestTimerRecord, operationID: UUID? = nil) -> Bool {
        guard didRestore else {
            reportPersistenceError(RestTimerStorageError.invalidRecord)
            return false
        }
        do {
            guard record.revision < UInt64.max else { throw RestTimerStorageError.invalidRecord }
            var next = next
            if let operationID {
                next.appliedOperationIDs = (next.appliedOperationIDs ?? []) + [operationID]
            }
            next.revision = record.revision + 1
            try storage.save(next)
            record = next
            persistenceError = nil
            publishRecord()
            return true
        } catch {
            reportPersistenceError(error)
            return false
        }
    }

    private func publishRecord() {
        state = record.state
        timerStartDate = record.startedAt
        isManuallyStartedTimer = record.isManualStart
        if observesSystemEvents {
            LiveActivityManager.shared.reconcile(record)
        }
    }

    private func reportPersistenceError(_ error: Error) {
        persistenceError = "The rest timer could not be saved or restored. Your previous saved timer has been kept. Please reopen the app and try again."
        AppLogger.error("Rest timer persistence failed: \(error)", category: AppLogger.storage)
    }

    func dismissPersistenceError() { persistenceError = nil }

    // MARK: - Background Support

    @objc private func appDidEnterBackground() {
        // State is already committed. This task only supports foreground-style cues
        // during the short background execution window; it cannot prevent suspension.
        beginBackgroundTask()
    }

    @objc private func appWillEnterForeground() {
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

    private func clearLegacyTimerKeys() {
        defaults.removeObject(forKey: Keys.timerEndDate)
        defaults.removeObject(forKey: Keys.timerExerciseID)
        defaults.removeObject(forKey: Keys.timerExerciseName)
        defaults.removeObject(forKey: Keys.timerDuration)
    }

    private var shouldAutoAddSetOnRestTimer: Bool {
        defaults.object(forKey: Keys.autoAddSetOnRestTimer) as? Bool ?? true
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
        let currentDuration = (ticker.remainingSeconds.rounded()).safeInt
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
        var pending = defaults.stringArray(forKey: Keys.pendingSetGeneration) ?? []
        if !pending.contains(exerciseID) {
            pending.append(exerciseID)
            defaults.set(pending, forKey: Keys.pendingSetGeneration)
        }
    }

    /// Check if an exercise has a pending set generation
    func hasPendingSetGeneration(for exerciseID: String) -> Bool {
        let pending = defaults.stringArray(forKey: Keys.pendingSetGeneration) ?? []
        return pending.contains(exerciseID)
    }

    /// Clear pending set generation for an exercise (call after set is generated)
    func clearPendingSetGeneration(for exerciseID: String) {
        var pending = defaults.stringArray(forKey: Keys.pendingSetGeneration) ?? []
        pending.removeAll { $0 == exerciseID }
        defaults.set(pending, forKey: Keys.pendingSetGeneration)
    }

}
