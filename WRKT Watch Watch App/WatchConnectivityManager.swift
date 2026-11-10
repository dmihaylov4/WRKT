//
//  WatchConnectivityManager.swift
//  WRKT Watch
//
//  Handles communication with iPhone
//  Optimized for battery efficiency and reliability
//

import Foundation
import WatchConnectivity
import Combine
import OSLog
import UserNotifications

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var workoutState: WatchWorkoutState = WatchWorkoutState(isActive: false)
    @Published var isConnected: Bool = false
    @Published var lastSyncDate: Date?
    @Published var connectionError: String?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let logger = Logger(subsystem: "com.wrkt.watch", category: "connectivity")
    private var becomeActiveToken: NSObjectProtocol?

    // Debouncing for navigation events
    private var navigationDebounceTask: Task<Void, Never>?
    private let navigationDebounceDelay: TimeInterval = 0.3

    // Retry mechanism
    private var retryCount = 0
    private let maxRetries = 3
    private var retryTask: Task<Void, Never>?

    // Cache for queued messages when iPhone is unreachable
    private var messageQueue: [(type: WatchMessage, payload: Data?)] = []
    private let maxQueueSize = 10

    private override init() {
        super.init()
        setupSession()

        
        // Automatically request state when app becomes active
        becomeActiveToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSExtensionHostDidBecomeActiveNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestState()
            }
        }
    }

    deinit {
        if let token = becomeActiveToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupSession() {
        guard let session = session else {
            logger.warning("WatchConnectivity not supported")
            return
        }
        session.delegate = self
        session.activate()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["virtual-run-invite"])
        center.removeDeliveredNotifications(withIdentifiers: ["virtual-run-invite"])
        Task {
            let categories = await center.notificationCategories()
            center.setNotificationCategories(Set(categories.filter { $0.identifier != "VIRTUAL_RUN_INVITE" }))
        }
    }

    // MARK: - Send to iPhone

    func requestState() {
        logger.debug("Requesting workout state from iPhone")
        send(type: .requestWorkoutState)
    }

    func completeSet(exerciseID: String, entryID: String, setIndex: Int) {
        let payload = CompleteSetPayload(exerciseID: exerciseID, entryID: entryID, setIndex: setIndex)
        logger.info("Completing set: \(exerciseID) set #\(setIndex)")
        send(type: .completeSet, payload: payload)
    }

    func navigate(to index: Int) {
        // Debounce navigation events to reduce battery drain from rapid TabView swiping
        navigationDebounceTask?.cancel()

        navigationDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(navigationDebounceDelay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            let payload = NavigateToExercisePayload(exerciseIndex: index)
            logger.debug("Navigating to exercise index: \(index)")
            send(type: .navigateToExercise, payload: payload)
        }
    }

    /// Send a simple message without payload (for rest timer controls)
    func send(type: WatchMessage) {
        logger.debug("Sending message: \(type.rawValue)")
        sendMessage(type: type, payload: nil as Data?)
    }

    /// Send a message with dictionary payload
    func send(type: WatchMessage, payload: [String: Any]) {
        logger.debug("Sending message with payload: \(type.rawValue)")
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            sendMessage(type: type, payload: data)
        } else {
            logger.error("Failed to serialize payload for \(type.rawValue)")
        }
    }

    /// Start a specific set (marks it as active/in progress)
    func startSet(exerciseID: String, entryID: String, setIndex: Int) {
        let payload = StartSetPayload(exerciseID: exerciseID, entryID: entryID, setIndex: setIndex)
        logger.info("🎬 Starting set: exerciseID=\(exerciseID), entryID=\(entryID), setIndex=\(setIndex)")
        send(type: .startSet, payload: payload)
    }

    /// Add a new set based on the last one and start it
    func addAndStartSet(exerciseID: String, entryID: String) {
        let payload = AddAndStartSetPayload(exerciseID: exerciseID, entryID: entryID)
        logger.info("➕ Adding and starting new set: exerciseID=\(exerciseID), entryID=\(entryID)")
        send(type: .addAndStartSet, payload: payload)
    }

    // MARK: - Private

    private func sendMessage(type: WatchMessage, payload: Data?) {
        guard let session = session else { return }

        // Check if iPhone is reachable
        guard session.isReachable else {
            logger.warning("iPhone not reachable, queuing message: \(type.rawValue)")
            queueMessage(type: type, payload: payload)
            connectionError = "iPhone not reachable"
            return
        }

        var message: [String: Any] = ["messageType": type.rawValue]
        if let payload = payload {
            message["payload"] = payload
        }

        // Send with error handling and retry logic
        session.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.connectionError = nil
                self?.retryCount = 0
                self?.logger.debug("Message sent successfully: \(type.rawValue)")

                // Process queued messages on success
                self?.processMessageQueue()
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.logger.error("Failed to send message: \(error.localizedDescription)")
                self?.handleSendError(type: type, payload: payload, error: error)
            }
        })
    }

    private func send<T: Encodable>(type: WatchMessage, payload: T) {
        guard let data = try? JSONEncoder().encode(payload) else {
            logger.error("Failed to encode payload for \(type.rawValue)")
            return
        }
        sendMessage(type: type, payload: data)
    }

    // MARK: - Message Queue Management

    private func queueMessage(type: WatchMessage, payload: Data?) {
        if messageQueue.count >= maxQueueSize {
            messageQueue.removeFirst()
        }
        messageQueue.append((type, payload))
    }

    private func processMessageQueue() {
        guard !self.messageQueue.isEmpty else { return }

        logger.info("Processing \(self.messageQueue.count) queued messages")
        let queue = self.messageQueue
        self.messageQueue.removeAll()

        for (type, payload) in queue {
            sendMessage(type: type, payload: payload)
        }
    }

    // MARK: - Error Handling

    private func handleSendError(type: WatchMessage, payload: Data?, error: Error) {
        connectionError = "Communication error"

        guard self.retryCount < self.maxRetries else {
            logger.error("Max retries reached for \(type.rawValue)")
            queueMessage(type: type, payload: payload)
            self.retryCount = 0
            return
        }

        self.retryCount += 1
        let baseDelay = TimeInterval(self.retryCount) * 0.5
        let delay = baseDelay * (0.5 + Double.random(in: 0...0.5)) // Linear backoff with jitter

        logger.info("Retrying message \(type.rawValue) in \(delay)s (attempt \(self.retryCount)/\(self.maxRetries))")

        retryTask?.cancel()
        retryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }
            send(type: type, payload: payload)
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
                logger.error("Session activation failed: \(error.localizedDescription)")
                connectionError = "Activation failed"
                return
            }

            switch activationState {
            case .activated:
                logger.info("Session activated successfully")
                isConnected = session.isReachable

                if isConnected {
                    requestState()
                    processMessageQueue() // Send any queued messages
                }
            case .inactive:
                logger.warning("Session inactive")
                isConnected = false
            case .notActivated:
                logger.warning("Session not activated")
                isConnected = false
            @unknown default:
                logger.warning("Unknown activation state")
                isConnected = false
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            logger.info("Reachability changed: \(isReachable)")
            isConnected = isReachable

            if isConnected {
                connectionError = nil
                requestState()
                processMessageQueue() // Send queued messages when connection restored
            } else {
                connectionError = "iPhone not reachable"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let copy = message
        Task { @MainActor [weak self] in
            self?.handleIncomingMessage(copy)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let copy = message
        Task { @MainActor [weak self] in
            guard let self else { replyHandler(["status": "received"]); return }
            handleIncomingMessage(copy)
            replyHandler(["status": "received"])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let copy = applicationContext
        Task { @MainActor [weak self] in
            guard let self else { return }
            handleIncomingMessage(copy)
        }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {

        guard let type = message["type"] as? String else {
            logger.error("Invalid message format received - no 'type' key. Keys: \(message.keys.joined(separator: ", "))")
            return
        }

        guard ["workoutState", "startWatchWorkout", "endWatchWorkout", "discardWatchWorkout"].contains(type) else { return }
        logger.info("📨 Message type: \(type)")

        switch type {
        case "workoutState":
            guard let data = message["data"] as? Data else {
                logger.error("workoutState message missing data")
                return
            }
            do {
                let state = try JSONDecoder().decode(WatchWorkoutState.self, from: data)
                workoutState = state
                lastSyncDate = Date()
                connectionError = nil
                logger.info("✅ Received workout state: \(state.exercises.count) exercises, active: \(state.isActive)")

                // Auto-start HKWorkoutSession if iPhone has active workout but Watch doesn't.
                if state.isActive && !WatchHealthKitManager.shared.isWorkoutActive {
                    logger.info("📲 iPhone has active workout, auto-starting Watch HKWorkoutSession")
                    Task {
                        do {
                            try await WatchHealthKitManager.shared.startWorkout()
                            logger.info("✅ Auto-started HKWorkoutSession")
                        } catch {
                            logger.error("Failed to auto-start workout: \(error.localizedDescription)")
                        }
                    }
                }

                // Auto-end HKWorkoutSession if iPhone workout ended but Watch still active.
                if !state.isActive && WatchHealthKitManager.shared.isWorkoutActive {
                    logger.info("📲 iPhone workout ended, auto-ending Watch HKWorkoutSession")
                    Task {
                        do {
                            try await WatchHealthKitManager.shared.endWorkout()
                            logger.info("✅ Auto-ended HKWorkoutSession")
                        } catch {
                            logger.error("Failed to auto-end workout: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                logger.error("Failed to decode workout state: \(error.localizedDescription)")
                connectionError = "Data sync error"
            }

        case "startWatchWorkout":
            logger.info("📲 Received startWatchWorkout from iPhone")
            Task {
                do {
                    try await WatchHealthKitManager.shared.startWorkout()
                    logger.info("✅ Started HKWorkoutSession from iPhone trigger")
                } catch {
                    logger.error("Failed to start workout: \(error.localizedDescription)")
                }
            }

        case "endWatchWorkout":
            logger.info("📲 Received endWatchWorkout from iPhone")
            Task {
                do {
                    try await WatchHealthKitManager.shared.endWorkout(discard: false)
                    logger.info("✅ Ended and saved HKWorkoutSession from iPhone trigger")
                } catch {
                    logger.error("Failed to end workout: \(error.localizedDescription)")
                }
            }

        case "discardWatchWorkout":
            logger.info("📲 Received discardWatchWorkout from iPhone")
            Task {
                do {
                    try await WatchHealthKitManager.shared.endWorkout(discard: true)
                    logger.info("🗑️ Discarded HKWorkoutSession from iPhone trigger")
                } catch {
                    logger.error("Failed to discard workout: \(error.localizedDescription)")
                }
            }

        default:
            return
        }
    }

}

// MARK: - transferUserInfo (guaranteed delivery)

extension WatchConnectivityManager {

    /// Handle user info transfers from iPhone (guaranteed delivery, even if app wasn't running)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleIncomingMessage(userInfo)
        }
    }
}
