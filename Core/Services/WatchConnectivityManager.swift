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

    // Gate: true only after connectToWorkoutStore() has been called.
    // activationDidCompleteWith and sessionReachabilityDidChange both fire before
    // connectToWorkoutStore() on cold start. workoutStore is nil at that point, so
    // buildWatchWorkoutState() returns isActive: false — causing the Watch to end
    // its live HKWorkoutSession and save a duplicate HealthKit entry.
    private var isStoreConnected = false

    // Cache the last sent state to avoid redundant sends
    private var lastSentState: WatchWorkoutState?
    private var lastSentHash: Int?

    // Track pending discard to send when watch becomes reachable
    private var hasPendingDiscard: Bool = false

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
        isStoreConnected = true
        AppLogger.success("✅ Connected to workout store (currentWorkout: \(store.currentWorkout != nil ? "active" : "nil"))", category: AppLogger.app)
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
        guard isStoreConnected else { return }
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
    private func sendWorkoutState(_ state: WatchWorkoutState, retryCount: Int = 0) {
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

                guard retryCount < 3 else {
                    AppLogger.error("Giving up on workout state send after 3 retries", category: AppLogger.app)
                    return
                }

                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64((retryCount + 1)) * 1_000_000_000)
                    self?.sendWorkoutState(state, retryCount: retryCount + 1)
                }
            }
        } catch {
            AppLogger.error("Failed to encode workout state: \(error)", category: AppLogger.app)
        }
    }

    // MARK: - Handle Messages from Watch

    /// Handle message received from watch
    private func handleWatchMessage(_ message: [String: Any]) {

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

        guard WatchMessage(rawValue: messageType) != nil, !messageType.hasPrefix("vr_") else { return }

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

        default:
            return
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
                        isManualStart: false,
                        workoutID: workoutStore?.currentWorkout?.id,
                        entryID: entry.id
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
                        isManualStart: false,
                        workoutID: workoutStore?.currentWorkout?.id,
                        entryID: entry.id
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
        Task { @MainActor in
            handleWatchMessage(message)
            replyHandler(["status": "ok"])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleWatchMessage(userInfo)
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

}
