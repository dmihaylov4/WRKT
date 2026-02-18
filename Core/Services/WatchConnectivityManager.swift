//
//  WatchConnectivityManager.swift
//  WRKT (iOS)
//
//  Manages communication between iPhone and Apple Watch
//  Sends workout state to watch and handles actions from watch
//

import Foundation
import WatchConnectivity
import Combine
import OSLog
import UserNotifications
import HealthKit

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    // MARK: - Published State
    @Published private(set) var isWatchConnected: Bool = false
    @Published private(set) var isWatchAppInstalled: Bool = false

    // MARK: - Private Properties
    private var workoutStore: WorkoutStoreV2?
    private var cancellables = Set<AnyCancellable>()
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    // Debouncing to reduce battery drain from rapid updates
    private var sendDebounceTask: Task<Void, Never>?
    private let sendDebounceDelay: TimeInterval = 0.3

    // Cache the last sent state to avoid redundant sends
    private var lastSentState: WatchWorkoutState?
    private var lastSentHash: Int?

    // Track pending discard to send when watch becomes reachable
    private var hasPendingDiscard: Bool = false

    // Virtual run active state (for cleanup when Watch ends)
    private(set) var activeVirtualRunId: UUID?
    private(set) var activeVirtualRunUserId: UUID?

    // Virtual run partner context (for summary screen)
    private(set) var activeVirtualRunPartnerName: String?
    private(set) var lastPartnerSnapshot: VirtualRunSnapshot?

    // Pending virtual run start (queued when Watch is unreachable)
    private var pendingVirtualRunStart: [String: Any]?

    // MARK: - Initialization
    private override init() {
        super.init()
        setupSession()
    }

    // MARK: - Setup
    private func setupSession() {
        guard let session = session else {
            AppLogger.warning("WatchConnectivity not supported on this device", category: AppLogger.app)
            return
        }

        session.delegate = self
        session.activate()
        AppLogger.info("WatchConnectivity session activated", category: AppLogger.app)
    }

    /// Connect to WorkoutStoreV2 and start observing changes
    func connectToWorkoutStore(_ store: WorkoutStoreV2) {
        self.workoutStore = store
        AppLogger.success("✅ Connected to workout store", category: AppLogger.app)
        AppLogger.info("📱 iPhone WatchConnectivity ready - can receive messages from watch", category: AppLogger.app)

        // Listen to workout changes
        store.$currentWorkout
            .receive(on: RunLoop.main)
            .sink { [weak self] workout in
                AppLogger.debug("Workout changed, has workout: \(workout != nil)", category: AppLogger.app)
                self?.sendWorkoutStateToWatch()
            }
            .store(in: &cancellables)

        // Listen to rest timer changes
        RestTimerManager.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                AppLogger.debug("Rest timer state changed: \(state)", category: AppLogger.app)
                self?.sendWorkoutStateToWatch()
            }
            .store(in: &cancellables)

        // Send initial state
        AppLogger.info("Sending initial state to watch", category: AppLogger.app)
        sendWorkoutStateToWatch()

        // Log session status
        if let session = session {
            AppLogger.info("WCSession status: paired=\(session.isPaired), watchAppInstalled=\(session.isWatchAppInstalled), reachable=\(session.isReachable)", category: AppLogger.app)
        }
    }

    // MARK: - Send Data to Watch

    /// Convert current workout state to watch format and send to watch
    /// Debounced to reduce battery drain and avoid redundant sends
    private func sendWorkoutStateToWatch() {
        guard let session = session, session.isReachable else {
            return
        }

        let watchState = buildWatchWorkoutState()

        // Check if this is a major state change (workout started/ended) - send immediately
        let isActiveStateChange = (lastSentState?.isActive != watchState.isActive)
        let exerciseCountChange = (lastSentState?.exercises.count != watchState.exercises.count)

        if isActiveStateChange || exerciseCountChange {
            // Send immediately for major state changes
            AppLogger.info("Major state change detected, sending immediately", category: AppLogger.app)
            lastSentState = watchState
            lastSentHash = watchState.hashValue
            sendWorkoutState(watchState)
            return
        }

        // Cancel any pending send
        sendDebounceTask?.cancel()

        // Debounce the send operation for minor updates
        sendDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(sendDebounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            let currentState = buildWatchWorkoutState()

            // Check if state has actually changed
            let currentHash = currentState.hashValue
            guard currentHash != lastSentHash else {
                AppLogger.debug("Watch state unchanged, skipping send", category: AppLogger.app)
                return
            }

            lastSentState = currentState
            lastSentHash = currentHash
            sendWorkoutState(currentState)
        }
    }

    /// Build WatchWorkoutState from current app state
    private func buildWatchWorkoutState() -> WatchWorkoutState {
        guard let workout = workoutStore?.currentWorkout else {
            return WatchWorkoutState(isActive: false)
        }

        // Convert workout entries to watch format
        let exercises = workout.entries.enumerated().map { index, entry -> WatchExerciseInfo in
            let sets = entry.sets.enumerated().map { setIndex, set -> WatchSetInfo in
                WatchSetInfo(
                    id: "\(entry.id)-\(setIndex)",
                    reps: set.reps,
                    weight: set.weight,
                    tag: set.tag.rawValue,
                    isCompleted: set.isCompleted,
                    trackingMode: set.trackingMode.rawValue,
                    durationSeconds: set.durationSeconds
                )
            }

            return WatchExerciseInfo(
                id: entry.exerciseID,
                entryID: entry.id.uuidString,
                name: entry.exerciseName,
                sets: sets,
                activeSetIndex: entry.activeSetIndex
            )
        }

        // Find active exercise index
        let activeExerciseIndex: Int? = {
            if let activeEntryID = workout.activeEntryID,
               let index = workout.entries.firstIndex(where: { $0.id == activeEntryID }) {
                return index
            }
            return nil
        }()

        // Convert rest timer state
        let restTimer = buildWatchRestTimerInfo()

        return WatchWorkoutState(
            isActive: true,
            exercises: exercises,
            activeExerciseIndex: activeExerciseIndex,
            workoutStartTime: workout.startedAt,
            restTimer: restTimer
        )
    }

    /// Build WatchRestTimerInfo from RestTimerManager state
    private func buildWatchRestTimerInfo() -> WatchRestTimerInfo? {
        let timerManager = RestTimerManager.shared

        switch timerManager.state {
        case .idle:
            return nil

        case .running(let endDate, _, let exerciseName, let originalDuration, _):
            let remaining = max(0, Int(endDate.timeIntervalSinceNow))
            return WatchRestTimerInfo(
                isActive: true,
                remainingSeconds: remaining,
                totalSeconds: Int(originalDuration),
                endDate: endDate,
                exerciseName: exerciseName
            )

        case .paused(let remainingSeconds, _, let exerciseName, let originalDuration, _):
            return WatchRestTimerInfo(
                isActive: false,
                remainingSeconds: Int(remainingSeconds),
                totalSeconds: Int(originalDuration),
                endDate: Date().addingTimeInterval(remainingSeconds),
                exerciseName: exerciseName
            )

        case .completed(_, let exerciseName):
            return WatchRestTimerInfo(
                isActive: false,
                remainingSeconds: 0,
                totalSeconds: 0,
                endDate: Date(),
                exerciseName: exerciseName
            )
        }
    }

    /// Send workout state to watch
    /// Uses efficient JSON encoding and error handling
    private func sendWorkoutState(_ state: WatchWorkoutState) {
        guard let session = session, session.isReachable else {
            AppLogger.debug("Watch not reachable, skipping state update", category: AppLogger.app)
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)

            // Log data size for monitoring
            let dataSize = data.count
            let dataSizeKB = Double(dataSize) / 1024.0
            AppLogger.debug("Sending workout state: \(state.exercises.count) exercises, \(String(format: "%.2f", dataSizeKB)) KB", category: AppLogger.app)

            let message: [String: Any] = [
                "type": "workoutState",
                "data": data
            ]

            session.sendMessage(message, replyHandler: { reply in
                AppLogger.debug("Watch acknowledged state update", category: AppLogger.app)
            }) { error in
                AppLogger.error("Failed to send workout state to watch: \(error.localizedDescription)", category: AppLogger.app)

                // Retry logic for critical state updates
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    self?.sendWorkoutState(state)
                }
            }
        } catch {
            AppLogger.error("Failed to encode workout state: \(error)", category: AppLogger.app)
        }
    }

    // MARK: - Handle Messages from Watch

    /// Handle message received from watch
    private func handleWatchMessage(_ message: [String: Any]) {
        AppLogger.info("📨 Handling watch message: \(message.keys.joined(separator: ", "))", category: AppLogger.app)

        // Check for simple action messages (like "openApp")
        if let action = message["action"] as? String {
            AppLogger.info("🎯 Processing watch action: \(action)", category: AppLogger.app)
            if action == "openApp" {
                handleOpenApp()
                return
            }
        }

        guard let messageType = message["messageType"] as? String else {
            AppLogger.warning("Received watch message without type. Keys: \(message.keys)", category: AppLogger.app)
            return
        }

        AppLogger.info("🎯 Processing watch message type: \(messageType)", category: AppLogger.app)

        switch messageType {
        case WatchMessage.completeSet.rawValue:
            handleCompleteSet(message)

        case WatchMessage.navigateToExercise.rawValue:
            handleNavigateToExercise(message)

        case WatchMessage.requestWorkoutState.rawValue:
            sendWorkoutStateToWatch()

        case WatchMessage.startRestTimer.rawValue:
            handleStartRestTimer(message)

        case WatchMessage.pauseRestTimer.rawValue:
            RestTimerManager.shared.pauseTimer()
            sendWorkoutStateToWatch()

        case WatchMessage.resumeRestTimer.rawValue:
            RestTimerManager.shared.resumeTimer()
            sendWorkoutStateToWatch()

        case WatchMessage.skipRestTimer.rawValue:
            RestTimerManager.shared.skipTimer()
            sendWorkoutStateToWatch()

        case WatchMessage.startSet.rawValue:
            handleStartSet(message)

        case WatchMessage.addAndStartSet.rawValue:
            handleAddAndStartSet(message)

        case WatchMessage.startQuickWorkout.rawValue:
            handleStartQuickWorkout()

        // Virtual Run messages from Watch
        case WatchMessage.vrSnapshot.rawValue:
            handleVirtualRunSnapshot(message)

        case WatchMessage.vrHeartbeat.rawValue:
            handleVirtualRunHeartbeat()

        case WatchMessage.vrRunEnded.rawValue:
            handleVirtualRunEnded(message)

        case WatchMessage.vrWatchConfirmed.rawValue:
            handleVirtualRunWatchConfirmed(message)

        case WatchMessage.vrPause.rawValue:
            handleVirtualRunPause()

        case WatchMessage.vrResume.rawValue:
            handleVirtualRunResume()

        default:
            AppLogger.warning("Unknown watch message type: \(messageType)", category: AppLogger.app)
        }
    }

    /// Handle complete set message from watch
    private func handleCompleteSet(_ message: [String: Any]) {
        guard let payloadData = message["payload"] as? Data else {
            AppLogger.error("Complete set message missing payload", category: AppLogger.app)
            return
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(CompleteSetPayload.self, from: payloadData)

            AppLogger.info("🎯 Processing completeSet: exerciseID=\(payload.exerciseID), entryID=\(payload.entryID), setIndex=\(payload.setIndex)", category: AppLogger.app)

            // Check if workout exists
            guard let workout = workoutStore?.currentWorkout else {
                AppLogger.error("❌ No active workout on iPhone!", category: AppLogger.app)
                return
            }

            AppLogger.info("✅ Found active workout with \(workout.entries.count) exercises", category: AppLogger.app)

            // Find the entry
            guard let entryUUID = UUID(uuidString: payload.entryID),
                  let entryIndex = workout.entries.firstIndex(where: { $0.id == entryUUID }) else {
                AppLogger.error("❌ Could not find entry with ID: \(payload.entryID)", category: AppLogger.app)
                AppLogger.info("Available entries: \(workout.entries.map { $0.id.uuidString }.joined(separator: ", "))", category: AppLogger.app)
                return
            }

            var entry = workout.entries[entryIndex]
            guard entry.sets.indices.contains(payload.setIndex) else {
                AppLogger.error("Set index out of bounds: \(payload.setIndex)", category: AppLogger.app)
                return
            }

            // Mark set as completed
            entry.sets[payload.setIndex].isCompleted = true

            AppLogger.info("📝 About to call updateEntrySets for entryID: \(entry.id.uuidString)", category: AppLogger.app)
            workoutStore?.updateEntrySets(entryID: entry.id, sets: entry.sets)
            AppLogger.info("📝 Called updateEntrySets", category: AppLogger.app)

            AppLogger.success("✅ Completed set from watch: \(entry.exerciseName) set #\(payload.setIndex + 1)", category: AppLogger.app)

            // Trigger haptic feedback
            Haptics.success()

            // Post notification to force UI refresh (in case ExerciseSessionView is open)
            AppLogger.info("📣 Posting WorkoutUpdatedFromWatch notification", category: AppLogger.app)
            NotificationCenter.default.post(
                name: NSNotification.Name("WorkoutUpdatedFromWatch"),
                object: nil,
                userInfo: ["entryID": entry.id.uuidString]
            )

            // Send updated state back to watch
            sendWorkoutStateToWatch()

        } catch {
            AppLogger.error("Failed to decode complete set payload: \(error)", category: AppLogger.app)
        }
    }

    /// Handle navigate to exercise message from watch
    private func handleNavigateToExercise(_ message: [String: Any]) {
        guard let payloadData = message["payload"] as? Data else {
            AppLogger.error("Navigate message missing payload", category: AppLogger.app)
            return
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(NavigateToExercisePayload.self, from: payloadData)

            guard let workout = workoutStore?.currentWorkout,
                  workout.entries.indices.contains(payload.exerciseIndex) else {
                AppLogger.error("Exercise index out of bounds: \(payload.exerciseIndex)", category: AppLogger.app)
                return
            }

            let entry = workout.entries[payload.exerciseIndex]
            workoutStore?.setActiveEntry(entry.id)

            AppLogger.debug("Navigated to exercise from watch: \(entry.exerciseName)", category: AppLogger.app)

        } catch {
            AppLogger.error("Failed to decode navigate payload: \(error)", category: AppLogger.app)
        }
    }

    /// Handle start rest timer message from watch - finds first incomplete set and completes it
    private func handleStartRestTimer(_ message: [String: Any]) {
        guard let payloadData = message["payload"] as? Data else {
            AppLogger.error("Start rest timer message missing payload", category: AppLogger.app)
            return
        }

        do {
            let decoder = JSONDecoder()
            let _ = try decoder.decode(StartRestTimerPayload.self, from: payloadData)

            // Find current workout
            guard let workout = workoutStore?.currentWorkout else {
                AppLogger.error("No active workout to start timer for", category: AppLogger.app)
                return
            }

            // Find active exercise - if no activeEntryID is set, use the first entry
            let entryIndex: Int
            if let activeEntryID = workout.activeEntryID,
               let index = workout.entries.firstIndex(where: { $0.id == activeEntryID }) {
                entryIndex = index
                AppLogger.info("Using active exercise: \(workout.entries[index].exerciseName)", category: AppLogger.app)
            } else if !workout.entries.isEmpty {
                entryIndex = 0
                AppLogger.warning("No active exercise set, using first exercise: \(workout.entries[0].exerciseName)", category: AppLogger.app)
                // Set it as active for future operations
                workoutStore?.setActiveEntry(workout.entries[0].id)
            } else {
                AppLogger.error("No exercises in workout", category: AppLogger.app)
                return
            }

            var entry = workout.entries[entryIndex]

            // Find first incomplete set (top to bottom)
            let firstIncompleteIndex = entry.sets.firstIndex(where: { !$0.isCompleted })

            let setIndexToComplete: Int

            if let incompleteIndex = firstIncompleteIndex {
                // Found an incomplete set - use it
                setIndexToComplete = incompleteIndex
                AppLogger.info("🎯 Completing first incomplete set #\(incompleteIndex + 1) from Watch timer start", category: AppLogger.app)
            } else {
                // All sets are completed - create a new set based on the last one
                AppLogger.info("➕ All sets complete, creating new set from Watch timer start", category: AppLogger.app)

                let lastSet = entry.sets.last ?? SetInput(reps: 10, weight: 0, tag: .working)
                let newSet = SetInput(
                    reps: lastSet.reps,
                    weight: lastSet.weight,
                    tag: .working,
                    autoWeight: false
                )
                entry.sets.append(newSet)
                setIndexToComplete = entry.sets.count - 1

                AppLogger.info("➕ Created new set #\(setIndexToComplete + 1) with \(newSet.weight)kg × \(newSet.reps) reps", category: AppLogger.app)
            }

            // Mark the set as completed (same as "Log Set" button)
            let now = Date()
            entry.sets[setIndexToComplete].completionTime = now
            entry.sets[setIndexToComplete].isCompleted = true

            // Store rest timer duration that will be used
            if let exercise = ExerciseRepository.shared.exercise(byID: entry.exerciseID) {
                let restDuration = RestTimerPreferences.shared.restDuration(for: exercise)
                entry.sets[setIndexToComplete].restAfterSeconds = Int(restDuration)
                AppLogger.info("⏱️ Set restAfterSeconds to \(Int(restDuration))s on set #\(setIndexToComplete + 1)", category: AppLogger.app)
            }

            // Update the entry with the completed set
            workoutStore?.updateEntrySets(entryID: entry.id, sets: entry.sets)

            // Start rest timer if enabled (same as in-app flow)
            let prefs = RestTimerPreferences.shared
            if prefs.isEnabled {
                if let exercise = ExerciseRepository.shared.exercise(byID: entry.exerciseID) {
                    let duration = prefs.restDuration(for: exercise)
                    AppLogger.info("⏱️ Starting rest timer: \(Int(duration))s for \(entry.exerciseName)", category: AppLogger.app)
                    RestTimerManager.shared.startTimer(
                        duration: duration,
                        exerciseID: entry.exerciseID,
                        exerciseName: entry.exerciseName,
                        isManualStart: false  // This is like logging a set, so it appears on the set row
                    )
                }
            }

            // Trigger haptic feedback
            Haptics.success()

            // Post notification to force UI refresh (in case ExerciseSessionView is open)
            NotificationCenter.default.post(
                name: NSNotification.Name("WorkoutUpdatedFromWatch"),
                object: nil,
                userInfo: ["entryID": entry.id.uuidString]
            )

            // Send updated state back to watch
            sendWorkoutStateToWatch()

            AppLogger.success("✅ Completed first incomplete set from watch timer start", category: AppLogger.app)

        } catch {
            AppLogger.error("Failed to decode start rest timer payload: \(error)", category: AppLogger.app)
        }
    }

    /// Handle start set message from watch (complete the set and start rest timer, same as "Log Set")
    private func handleStartSet(_ message: [String: Any]) {
        guard let payloadData = message["payload"] as? Data else {
            AppLogger.error("Start set message missing payload", category: AppLogger.app)
            return
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(StartSetPayload.self, from: payloadData)

            AppLogger.info("🎯 Processing startSet (Log Set): exerciseID=\(payload.exerciseID), entryID=\(payload.entryID), setIndex=\(payload.setIndex)", category: AppLogger.app)

            // Check if workout exists
            guard let workout = workoutStore?.currentWorkout else {
                AppLogger.error("❌ No active workout on iPhone!", category: AppLogger.app)
                return
            }

            AppLogger.info("✅ Found active workout with \(workout.entries.count) exercises", category: AppLogger.app)

            // Find the entry
            guard let entryUUID = UUID(uuidString: payload.entryID),
                  let entryIndex = workout.entries.firstIndex(where: { $0.id == entryUUID }) else {
                AppLogger.error("❌ Could not find entry with ID: \(payload.entryID)", category: AppLogger.app)
                AppLogger.info("Available entries: \(workout.entries.map { $0.id.uuidString }.joined(separator: ", "))", category: AppLogger.app)
                return
            }

            var entry = workout.entries[entryIndex]
            guard entry.sets.indices.contains(payload.setIndex) else {
                AppLogger.error("Set index out of bounds: \(payload.setIndex)", category: AppLogger.app)
                return
            }

            // Set this exercise as active
            workoutStore?.setActiveEntry(entry.id)

            // Mark the set as completed (same as "Log Set" button)
            let now = Date()
            entry.sets[payload.setIndex].completionTime = now
            entry.sets[payload.setIndex].isCompleted = true

            // Store rest timer duration that will be used
            if let exercise = ExerciseRepository.shared.exercise(byID: entry.exerciseID) {
                let restDuration = RestTimerPreferences.shared.restDuration(for: exercise)
                entry.sets[payload.setIndex].restAfterSeconds = Int(restDuration)
                AppLogger.info("⏱️ Set restAfterSeconds to \(Int(restDuration))s", category: AppLogger.app)
            }

            AppLogger.info("📝 About to call updateEntrySets for entryID: \(entry.id.uuidString)", category: AppLogger.app)
            // Update the entry with the completed set
            workoutStore?.updateEntrySets(entryID: entry.id, sets: entry.sets)
            AppLogger.info("📝 Called updateEntrySets", category: AppLogger.app)

            // Start rest timer if enabled (same as in-app flow)
            let prefs = RestTimerPreferences.shared
            if prefs.isEnabled {
                if let exercise = ExerciseRepository.shared.exercise(byID: entry.exerciseID) {
                    let duration = prefs.restDuration(for: exercise)
                    AppLogger.info("⏱️ Starting rest timer: \(Int(duration))s for \(entry.exerciseName)", category: AppLogger.app)
                    RestTimerManager.shared.startTimer(
                        duration: duration,
                        exerciseID: entry.exerciseID,
                        exerciseName: entry.exerciseName,
                        isManualStart: false  // This is like logging a set, not manually starting timer
                    )
                }
            } else {
                AppLogger.info("⏱️ Rest timer disabled in preferences", category: AppLogger.app)
            }

            AppLogger.success("✅ Completed set from watch: \(entry.exerciseName) set #\(payload.setIndex + 1)", category: AppLogger.app)

            // Trigger haptic feedback
            Haptics.success()

            // Post notification to force UI refresh (in case ExerciseSessionView is open)
            AppLogger.info("📣 Posting WorkoutUpdatedFromWatch notification", category: AppLogger.app)
            NotificationCenter.default.post(
                name: NSNotification.Name("WorkoutUpdatedFromWatch"),
                object: nil,
                userInfo: ["entryID": entry.id.uuidString]
            )

            // Send updated state back to watch
            sendWorkoutStateToWatch()

        } catch {
            AppLogger.error("Failed to decode start set payload: \(error)", category: AppLogger.app)
        }
    }

    /// Handle add and start set message from watch
    private func handleAddAndStartSet(_ message: [String: Any]) {
        guard let payloadData = message["payload"] as? Data else {
            AppLogger.error("Add and start set message missing payload", category: AppLogger.app)
            return
        }

        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(AddAndStartSetPayload.self, from: payloadData)

            // Find the entry
            guard let workout = workoutStore?.currentWorkout,
                  let entryUUID = UUID(uuidString: payload.entryID),
                  let entryIndex = workout.entries.firstIndex(where: { $0.id == entryUUID }) else {
                AppLogger.error("Could not find entry with ID: \(payload.entryID)", category: AppLogger.app)
                return
            }

            let entry = workout.entries[entryIndex]
            guard let lastSet = entry.sets.last else {
                AppLogger.error("No sets available to copy from", category: AppLogger.app)
                return
            }

            // Create a new set based on the last one (using SetInput)
            let newSet = SetInput(
                reps: lastSet.reps,
                weight: lastSet.weight,
                tag: lastSet.tag,
                autoWeight: false,
                didSeedFromMemory: false,
                isCompleted: false,
                isGhost: false,
                isAutoGeneratedPlaceholder: false,
                durationSeconds: lastSet.durationSeconds,
                trackingMode: lastSet.trackingMode,
                startTime: nil,
                completionTime: nil,
                restAfterSeconds: nil
            )

            // Add the new set
            var updatedSets = entry.sets
            updatedSets.append(newSet)
            let newSetIndex = updatedSets.count - 1

            // Update sets and set as active in one call
            workoutStore?.updateEntrySetsAndActiveIndex(
                entryID: entry.id,
                sets: updatedSets,
                activeSetIndex: newSetIndex
            )

            // Set this exercise as active
            workoutStore?.setActiveEntry(entry.id)

            AppLogger.success("Added and started new set from watch: \(entry.exerciseName) set #\(newSetIndex + 1)", category: AppLogger.app)

            // Trigger haptic feedback
            Haptics.success()

            // Send updated state back to watch
            sendWorkoutStateToWatch()

        } catch {
            AppLogger.error("Failed to decode add and start set payload: \(error)", category: AppLogger.app)
        }
    }

    /// Handle start quick workout from watch
    private func handleStartQuickWorkout() {
        AppLogger.info("Starting quick workout from watch", category: AppLogger.app)

        // Check if there's already an active workout
        guard workoutStore?.currentWorkout == nil else {
            AppLogger.warning("Cannot start workout - workout already in progress", category: AppLogger.app)
            return
        }

        // Start a new empty workout
        workoutStore?.startWorkoutIfNeeded()

        AppLogger.success("Started quick workout from watch", category: AppLogger.app)

        // Trigger haptic feedback
        Haptics.success()

        // Send updated state back to watch immediately
        sendWorkoutStateToWatch()

        // Post notification to open the app if it's in background
        NotificationCenter.default.post(name: NSNotification.Name("OpenAppFromWatch"), object: nil)
    }

    // MARK: - Watch Workout Session Control

    /// Send message to Watch to start HKWorkoutSession
    func sendStartWatchWorkout() {
        guard let session = session, session.isReachable else {
            AppLogger.warning("⚠️ Watch not reachable, cannot send startWatchWorkout - will sync on next workoutState", category: AppLogger.app)
            return
        }

        let message: [String: Any] = ["type": "startWatchWorkout"]

        session.sendMessage(message, replyHandler: { reply in
            AppLogger.debug("Watch acknowledged startWatchWorkout", category: AppLogger.app)
        }) { error in
            AppLogger.error("Failed to send startWatchWorkout: \(error.localizedDescription)", category: AppLogger.app)
        }

        AppLogger.info("📲 Sent startWatchWorkout to Watch", category: AppLogger.app)
    }

    /// Send message to Watch to end and save HKWorkoutSession
    func sendEndWatchWorkout() {
        guard let session = session, session.isReachable else {
            AppLogger.debug("Watch not reachable, cannot send endWatchWorkout", category: AppLogger.app)
            return
        }

        let message: [String: Any] = ["type": "endWatchWorkout"]

        session.sendMessage(message, replyHandler: { reply in
            AppLogger.debug("Watch acknowledged endWatchWorkout", category: AppLogger.app)
        }) { error in
            AppLogger.error("Failed to send endWatchWorkout: \(error.localizedDescription)", category: AppLogger.app)
        }

        AppLogger.info("📲 Sent endWatchWorkout to Watch", category: AppLogger.app)
    }

    /// Send message to Watch to discard HKWorkoutSession (don't save to HealthKit)
    func sendDiscardWatchWorkout() {
        guard let session = session, session.isReachable else {
            AppLogger.debug("Watch not reachable, queuing discardWatchWorkout for later", category: AppLogger.app)
            hasPendingDiscard = true
            return
        }

        hasPendingDiscard = false
        let message: [String: Any] = ["type": "discardWatchWorkout"]

        session.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.hasPendingDiscard = false
                AppLogger.debug("Watch acknowledged discardWatchWorkout", category: AppLogger.app)
            }
        }) { error in
            AppLogger.error("Failed to send discardWatchWorkout: \(error.localizedDescription)", category: AppLogger.app)
        }

        AppLogger.info("📲 Sent discardWatchWorkout to Watch", category: AppLogger.app)
    }

    // MARK: - Virtual Run Handlers

    /// Reference to virtual run repository (set externally)
    var virtualRunRepository: VirtualRunRepository?

    /// Handle snapshot from Watch → publish to Supabase for partner to receive
    private func handleVirtualRunSnapshot(_ message: [String: Any]) {
        guard let payloadData = message["payload"] as? Data else {
            AppLogger.error("VR snapshot message missing payload", category: AppLogger.virtualRun)
            return
        }

        do {
            let dict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] ?? [:]
            guard let snapshot = VirtualRunSnapshot.fromCompactDict(dict) else {
                AppLogger.error("Failed to decode VR snapshot from compact dict", category: AppLogger.virtualRun)
                return
            }

            AppLogger.debug("Forwarding VR snapshot to Supabase (seq: \(snapshot.seq))", category: AppLogger.virtualRun)

            let publishStart = Date()
            Task {
                do {
                    try await virtualRunRepository?.publishSnapshot(snapshot)

                    // Track publish latency (time from Watch send to Supabase broadcast)
                    let latencyMs = Int(Date().timeIntervalSince(publishStart) * 1000)
                    if latencyMs > 500, let runId = activeVirtualRunId, let userId = activeVirtualRunUserId {
                        VirtualRunTelemetry.shared.logLatency(
                            runId: runId, userId: userId,
                            latencyMs: latencyMs, method: "broadcast"
                        )
                    }
                } catch {
                    AppLogger.error("Failed to publish VR snapshot: \(error.localizedDescription)", category: AppLogger.virtualRun)
                }
            }
        } catch {
            AppLogger.error("Failed to deserialize VR snapshot payload: \(error.localizedDescription)", category: AppLogger.virtualRun)
        }
    }

    private func handleVirtualRunHeartbeat() {
        AppLogger.debug("💓 Received VR heartbeat from Watch", category: AppLogger.app)
    }

    private func handleVirtualRunEnded(_ message: [String: Any]) {
        AppLogger.info("🏁 Watch reported virtual run ended", category: AppLogger.virtualRun)

        Haptics.success()

        // Parse final stats from Watch payload
        var finalDistance: Double = 0
        var finalDuration: Int = 0
        var finalPace: Int?
        var finalHR: Int?

        if let payload = message["payload"] as? Data,
           let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            finalDistance = dict["distance"] as? Double ?? 0
            finalDuration = dict["duration"] as? Int ?? 0
            finalPace = dict["pace"] as? Int
            finalHR = dict["heartRate"] as? Int
            AppLogger.info("Watch final stats: \(String(format: "%.0f", finalDistance))m, \(finalDuration)s", category: AppLogger.app)
        }

        // Telemetry: log run completed
        if let runId = activeVirtualRunId, let userId = activeVirtualRunUserId {
            let durationMin = finalDuration / 60
            let winnerIsMe = finalDistance > (lastPartnerSnapshot?.distanceM ?? 0)
            VirtualRunTelemetry.shared.log(
                .runCompleted(durationMinutes: durationMin, winnerIsMe: winnerIsMe),
                runId: runId,
                userId: userId
            )
        }

        // Complete run via server-side RPC (submit our stats to server)
        if let runId = activeVirtualRunId, let userId = activeVirtualRunUserId {
            Task {
                do {
                    try await virtualRunRepository?.completeRun(
                        runId: runId,
                        userId: userId,
                        distanceM: finalDistance,
                        durationS: finalDuration,
                        avgPaceSecPerKm: finalPace,
                        avgHeartRate: finalHR
                    )
                    AppLogger.success("Completed virtual run via server RPC", category: AppLogger.app)
                } catch {
                    AppLogger.error("Failed to complete virtual run: \(error.localizedDescription)", category: AppLogger.app)
                }
            }
        }

        // Defer summary — wait for partner to finish so we get final stats from server
        if let runId = activeVirtualRunId, let userId = activeVirtualRunUserId {
            VirtualRunSummaryCoordinator.shared.awaitPartner(
                runId: runId,
                currentUserId: userId,
                partnerName: activeVirtualRunPartnerName ?? "Partner",
                myDistance: finalDistance,
                myDuration: finalDuration,
                myPace: finalPace,
                myHR: finalHR
            )
            AppLogger.info("📊 Deferred summary — waiting for partner to finish", category: AppLogger.app)
        }

        // Fire-and-forget route upload (GPS data for map comparison)
        if let runId = activeVirtualRunId, let userId = activeVirtualRunUserId {
            Task {
                await self.uploadVirtualRunRoute(runId: runId, userId: userId)
            }
        }

        // Reset invite coordinator active run tracking so Realtime updates for
        // this old run don't trigger false "Partner Finished" on new runs.
        // The SummaryCoordinator handles partner completion detection independently.
        VirtualRunInviteCoordinator.shared.runEnded()

        // Clear stale application context so Watch doesn't replay VR start on next launch
        clearVirtualRunApplicationContext()

        // Clear active run state
        activeVirtualRunId = nil
        activeVirtualRunUserId = nil
        activeVirtualRunPartnerName = nil
        lastPartnerSnapshot = nil

        // Post notification so any observing view can update
        NotificationCenter.default.post(
            name: NSNotification.Name("VirtualRunEndedFromWatch"),
            object: nil
        )
    }

    /// Upload the virtual run route from HealthKit to Supabase Storage
    /// Retries up to 6 times with 10s delays (60s window) — Watch→iPhone HealthKit sync
    /// can take 30-60 seconds after a workout ends
    private func uploadVirtualRunRoute(runId: UUID, userId: UUID) async {
        let maxRetries = 18
        let retryDelay: UInt64 = 10_000_000_000 // 10 seconds (total: 3 min window)

        for attempt in 1...maxRetries {
            do {
                // Find the most recent running workout (within last 5 minutes)
                let recentWorkout = try await findRecentRunningWorkout()
                guard let workout = recentWorkout else {
                    if attempt < maxRetries {
                        AppLogger.info("Route upload attempt \(attempt)/\(maxRetries): no recent workout found, retrying...", category: AppLogger.virtualRun)
                        try? await Task.sleep(nanoseconds: retryDelay)
                        continue
                    }
                    AppLogger.warning("Route upload: no recent workout found after \(maxRetries) attempts, skipping", category: AppLogger.virtualRun)
                    return
                }

                // Fetch route with heart rate data
                let routePoints = try await HealthKitManager.shared.fetchRouteWithHeartRate(for: workout)
                guard !routePoints.isEmpty else {
                    if attempt < maxRetries {
                        AppLogger.info("Route upload attempt \(attempt)/\(maxRetries): empty route, retrying...", category: AppLogger.virtualRun)
                        try? await Task.sleep(nanoseconds: retryDelay)
                        continue
                    }
                    AppLogger.warning("Route upload: empty route after \(maxRetries) attempts, skipping", category: AppLogger.virtualRun)
                    return
                }

                // Convert to compact format with Douglas-Peucker simplification
                let routeData = VirtualRunRouteData.from(
                    routePoints: routePoints,
                    userId: userId,
                    runId: runId,
                    runStartDate: workout.startDate
                )

                // Upload to Supabase
                try await virtualRunRepository?.uploadRoute(
                    runId: runId,
                    userId: userId,
                    routeData: routeData
                )

                AppLogger.success("Uploaded virtual run route: \(routeData.points.count) points", category: AppLogger.virtualRun)
                return

            } catch {
                if attempt < maxRetries {
                    AppLogger.warning("Route upload attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription), retrying...", category: AppLogger.virtualRun)
                    try? await Task.sleep(nanoseconds: retryDelay)
                } else {
                    AppLogger.error("Route upload failed after \(maxRetries) attempts: \(error.localizedDescription)", category: AppLogger.virtualRun)
                }
            }
        }
    }

    /// Find the most recent running workout from HealthKit (within last 15 minutes)
    private func findRecentRunningWorkout() async throws -> HKWorkout? {
        let store = HealthKitManager.shared.store
        let fiveMinutesAgo = Date().addingTimeInterval(-900)

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForSamples(withStart: fiveMinutesAgo, end: Date(), options: []),
                HKQuery.predicateForWorkouts(with: .running)
            ])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results?.first as? HKWorkout)
            }

            store.execute(query)
        }
    }

    private func handleVirtualRunWatchConfirmed(_ message: [String: Any]) {
        AppLogger.info("Watch user confirmed virtual run — countdown started", category: AppLogger.app)

        // Parse coordinated start time from Watch
        var startTime: Date?
        if let payload = message["payload"] as? Data,
           let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let ts = dict["startTime"] as? TimeInterval {
            startTime = Date(timeIntervalSince1970: ts)
        }

        // Post notification with start time so any observing view can coordinate
        NotificationCenter.default.post(
            name: NSNotification.Name("VirtualRunWatchConfirmed"),
            object: nil,
            userInfo: startTime.map { ["startTime": $0] }
        )
    }

    private func handleVirtualRunPause() {
        AppLogger.info("Watch user paused virtual run", category: AppLogger.app)

        // Relay pause state to partner via next snapshot (isPaused flag)
        // The Watch already sets isPaused=true in its snapshots while paused
        NotificationCenter.default.post(
            name: NSNotification.Name("VirtualRunPausedFromWatch"),
            object: nil
        )
    }

    private func handleVirtualRunResume() {
        AppLogger.info("Watch user resumed virtual run", category: AppLogger.app)

        NotificationCenter.default.post(
            name: NSNotification.Name("VirtualRunResumedFromWatch"),
            object: nil
        )
    }

    /// Send partner snapshot update to Watch
    func sendVirtualRunPartnerUpdate(_ snapshot: VirtualRunSnapshot) {
        // Store for summary screen when run ends
        lastPartnerSnapshot = snapshot

        let dict = snapshot.toCompactDict()
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }

        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "type": WatchMessage.vrPartnerUpdate.rawValue,
            "data": data
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            AppLogger.error("Failed to send VR partner update: \(error.localizedDescription)", category: AppLogger.app)
        }
    }

    /// Notify Watch that a virtual run has started
    func sendVirtualRunStarted(runId: UUID, partnerId: UUID, partnerName: String, myUserId: UUID, myMaxHR: Int? = nil, partnerMaxHR: Int = 190) {
        // Track active run for cleanup when Watch ends
        activeVirtualRunId = runId
        activeVirtualRunUserId = myUserId
        activeVirtualRunPartnerName = partnerName
        lastPartnerSnapshot = nil

        // Telemetry
        VirtualRunTelemetry.shared.log(.runStarted, runId: runId, userId: myUserId)

        let resolvedMaxHR = myMaxHR ?? HRZoneCalculator.shared.maxHR

        let info: [String: Any] = [
            "runId": runId.uuidString,
            "partnerId": partnerId.uuidString,
            "partnerName": partnerName,
            "myUserId": myUserId.uuidString,
            "myMaxHR": resolvedMaxHR,
            "partnerMaxHR": partnerMaxHR
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: info) else { return }

        let message: [String: Any] = [
            "type": WatchMessage.vrRunStarted.rawValue,
            "data": data
        ]

        guard let session = session else { return }

        // Always send via transferUserInfo for guaranteed delivery (survives app not running)
        session.transferUserInfo(message)
        AppLogger.info("Queued VR started via transferUserInfo (guaranteed delivery)", category: AppLogger.app)

        if session.isReachable {
            pendingVirtualRunStart = nil
            session.sendMessage(message, replyHandler: { _ in
                AppLogger.success("Watch acknowledged VR started", category: AppLogger.app)
            }) { [weak self] error in
                AppLogger.error("Failed to send VR started: \(error.localizedDescription)", category: AppLogger.app)
                // Queue for retry on reachability change
                Task { @MainActor in
                    self?.pendingVirtualRunStart = message
                }
            }
        } else {
            // Watch not reachable — queue for retry and also push via application context
            AppLogger.warning("Watch not reachable, queuing VR started for delivery", category: AppLogger.app)
            pendingVirtualRunStart = message
            try? session.updateApplicationContext(message)
        }
    }

    /// Notify Watch that the virtual run has ended
    func sendVirtualRunEnded() {
        guard let session = session, session.isReachable else { return }

        // Telemetry: log run cancelled from iPhone side
        if let runId = activeVirtualRunId, let userId = activeVirtualRunUserId {
            VirtualRunTelemetry.shared.log(
                .runCancelled(reason: "ended_from_iphone"),
                runId: runId,
                userId: userId
            )
        }

        // Clear active run state (Supabase update handled by the caller, e.g. DebugView)
        activeVirtualRunId = nil
        activeVirtualRunUserId = nil
        activeVirtualRunPartnerName = nil
        lastPartnerSnapshot = nil

        // Reset invite coordinator state
        VirtualRunInviteCoordinator.shared.runEnded()

        // Clear stale application context so Watch doesn't replay VR start on next launch
        clearVirtualRunApplicationContext()

        let message: [String: Any] = [
            "type": WatchMessage.vrRunEnded.rawValue
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            AppLogger.error("Failed to send VR ended: \(error.localizedDescription)", category: AppLogger.app)
        }
    }

    /// Clear the application context so stale VR start messages don't replay on Watch launch
    private func clearVirtualRunApplicationContext() {
        guard let session = session else { return }
        // Overwrite with an empty context to clear the stale vrRunStarted message
        try? session.updateApplicationContext(["type": "cleared"])
        AppLogger.info("Cleared VR application context", category: AppLogger.virtualRun)
    }

    /// Notify Watch that the partner finished their run
    func sendVirtualRunPartnerFinished(partnerDistance: Double, partnerDuration: Int = 0, partnerPace: Int? = nil) {
        guard let session = session, session.isReachable else { return }

        var info: [String: Any] = [
            "type": WatchMessage.vrPartnerFinished.rawValue,
            "partnerDistance": partnerDistance,
            "partnerDuration": partnerDuration
        ]
        if let pace = partnerPace {
            info["partnerPace"] = pace
        }

        session.sendMessage(info, replyHandler: nil) { error in
            AppLogger.error("Failed to send VR partner finished: \(error.localizedDescription)", category: AppLogger.app)
        }
    }

    /// Handle open app request from watch
    private func handleOpenApp() {
        AppLogger.info("📱 Sending notification to iPhone to open app", category: AppLogger.app)

        // Send a local notification to iPhone
        // User can tap it to open the app
        sendLocalNotification(
            title: "WRKT",
            body: "Tap to start your workout",
            identifier: "watch-open-app"
        )

        // Trigger haptic on iPhone
        Haptics.light()

        AppLogger.success("✅ Notification sent to iPhone", category: AppLogger.app)
    }

    /// Send local notification to iPhone
    private func sendLocalNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical // Critical alert - plays even on silent/locked
        content.interruptionLevel = .timeSensitive // iOS 15+ - breaks through Focus modes
        content.categoryIdentifier = "WORKOUT_START"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // nil = deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.error("Failed to send notification: \(error.localizedDescription)", category: AppLogger.app)
            } else {
                AppLogger.success("Notification delivered to iPhone", category: AppLogger.app)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                AppLogger.error("Watch session activation failed: \(error.localizedDescription)", category: AppLogger.app)
                return
            }

            switch activationState {
            case .activated:
                AppLogger.success("Watch session activated", category: AppLogger.app)
                isWatchConnected = session.isReachable
                isWatchAppInstalled = session.isWatchAppInstalled
                // Send initial state
                sendWorkoutStateToWatch()

            case .inactive:
                AppLogger.warning("Watch session inactive", category: AppLogger.app)
                isWatchConnected = false

            case .notActivated:
                AppLogger.warning("Watch session not activated", category: AppLogger.app)
                isWatchConnected = false

            @unknown default:
                AppLogger.warning("Unknown watch session state", category: AppLogger.app)
                isWatchConnected = false
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            AppLogger.debug("Watch session became inactive", category: AppLogger.app)
            isWatchConnected = false
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            AppLogger.debug("Watch session deactivated", category: AppLogger.app)
            isWatchConnected = false

            // Reactivate session for new watch
            session.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            AppLogger.debug("Watch reachability changed: \(session.isReachable)", category: AppLogger.app)
            isWatchConnected = session.isReachable

            if session.isReachable {
                // Check for pending discard first - this takes priority
                if hasPendingDiscard {
                    AppLogger.info("📲 Watch became reachable, sending pending discard", category: AppLogger.app)
                    sendDiscardWatchWorkout()
                }

                // Send pending virtual run start if queued
                if let pendingVR = pendingVirtualRunStart {
                    AppLogger.info("📲 Watch became reachable, sending pending VR started", category: AppLogger.app)
                    pendingVirtualRunStart = nil
                    session.sendMessage(pendingVR, replyHandler: nil) { error in
                        AppLogger.error("Failed to send queued VR started: \(error.localizedDescription)", category: AppLogger.app)
                    }
                }

                // Watch became reachable, send current state
                sendWorkoutStateToWatch()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleWatchMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        AppLogger.info("✅ Received message from watch with reply handler: \(message)", category: AppLogger.app)
        Task { @MainActor in
            handleWatchMessage(message)
            replyHandler(["status": "ok"])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        AppLogger.info("Received message data from watch: \(messageData.count) bytes", category: AppLogger.app)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        AppLogger.info("Received message data from watch with reply handler: \(messageData.count) bytes", category: AppLogger.app)
        replyHandler(Data())
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let fileType = metadata["type"] as? String ?? "unknown"
        let fileName = metadata["name"] as? String ?? file.fileURL.lastPathComponent

        guard fileType == "vrLog" else {
            AppLogger.info("Received non-log file transfer: \(fileType)", category: AppLogger.app)
            return
        }

        // Copy file synchronously — WCSession deletes the temp file after this method returns
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent("WatchVRLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destURL)

        do {
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)
            AppLogger.success("Saved watch VR log: \(fileName)", category: AppLogger.app)

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: NSNotification.Name("WatchVRLogReceived"),
                    object: nil,
                    userInfo: ["url": destURL, "name": fileName]
                )
            }
        } catch {
            AppLogger.error("Failed to save watch VR log: \(error.localizedDescription)", category: AppLogger.app)
        }
    }
}
