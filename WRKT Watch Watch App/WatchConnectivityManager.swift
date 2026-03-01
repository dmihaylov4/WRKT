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

    // Dedup: track the last VR run ID we processed to avoid double-handling
    // Persisted in UserDefaults so it survives app restarts (prevents stale applicationContext replay)
    private var lastProcessedVRRunId: UUID? {
        get { UserDefaults.standard.string(forKey: "lastProcessedVRRunId").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "lastProcessedVRRunId") }
    }

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
        requestNotificationPermission()
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

    /// Critical message types that must never be evicted from the queue
    private static let criticalMessageTypes: Set<String> = [
        WatchMessage.vrRunEnded.rawValue,
        WatchMessage.vrPause.rawValue,
        WatchMessage.vrResume.rawValue,
        WatchMessage.vrWatchConfirmed.rawValue
    ]

    private func queueMessage(type: WatchMessage, payload: Data?) {
        if messageQueue.count >= maxQueueSize {
            // Find the first non-critical message to evict
            if let evictIndex = messageQueue.firstIndex(where: { !Self.criticalMessageTypes.contains($0.type.rawValue) }) {
                logger.warning("Message queue full, dropping non-critical message: \(self.messageQueue[evictIndex].type.rawValue)")
                messageQueue.remove(at: evictIndex)
            } else {
                // All messages are critical — drop oldest anyway to prevent unbounded growth
                logger.warning("Message queue full of critical messages, dropping oldest")
                messageQueue.removeFirst()
            }
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

                // Check for pending virtual run start delivered via application context
                let ctx = session.receivedApplicationContext
                if ctx["type"] as? String == WatchMessage.vrRunStarted.rawValue {
                    logger.info("📨 Found pending VR start in application context")
                    handleIncomingMessage(ctx)
                }

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
            VirtualRunFileLogger.shared.log(category: .connectivity, message: "Reachability changed", data: [
                "isReachable": isReachable
            ])
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
            guard let self else { return }
            logger.info("Received message from iPhone with reply handler")
            handleIncomingMessage(copy)
            replyHandler(["status": "received"])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let copy = applicationContext
        Task { @MainActor [weak self] in
            guard let self else { return }
            logger.info("📨 Received application context with keys: \(copy.keys.joined(separator: ", "))")
            handleIncomingMessage(copy)
        }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        logger.info("📨 Received message with keys: \(message.keys.joined(separator: ", "))")

        guard let type = message["type"] as? String else {
            logger.error("Invalid message format received - no 'type' key. Keys: \(message.keys.joined(separator: ", "))")
            return
        }

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
                // Skip if a virtual run is pending or active — VR manages its own HK session
                // and auto-starting an indoor strength workout here would block startRunningWorkout().
                if state.isActive && !WatchHealthKitManager.shared.isWorkoutActive
                    && VirtualRunManager.shared.phase == .idle {
                    logger.info("📲 iPhone has active workout, auto-starting Watch HKWorkoutSession")
                    Task {
                        do {
                            try await WatchHealthKitManager.shared.startWorkout()
                            logger.info("✅ Auto-started HKWorkoutSession")
                        } catch {
                            logger.error("Failed to auto-start workout: \(error.localizedDescription)")
                        }
                    }
                } else if state.isActive && VirtualRunManager.shared.phase != .idle {
                    logger.info("⏸ Skipping auto-start: virtual run is in progress")
                }

                // Auto-end HKWorkoutSession if iPhone workout ended but Watch still active.
                // Skip during VR — the VR's own end flow handles HK cleanup.
                if !state.isActive && WatchHealthKitManager.shared.isWorkoutActive
                    && VirtualRunManager.shared.phase == .idle {
                    logger.info("📲 iPhone workout ended, auto-ending Watch HKWorkoutSession")
                    Task {
                        do {
                            try await WatchHealthKitManager.shared.endWorkout()
                            logger.info("✅ Auto-ended HKWorkoutSession")
                        } catch {
                            logger.error("Failed to auto-end workout: \(error.localizedDescription)")
                        }
                    }
                } else if !state.isActive && VirtualRunManager.shared.phase != .idle {
                    logger.info("⏸ Skipping auto-end: virtual run is in progress")
                }
            } catch {
                logger.error("Failed to decode workout state: \(error.localizedDescription)")
                connectionError = "Data sync error"
            }

        case "startWatchWorkout":
            logger.info("📲 Received startWatchWorkout from iPhone")
            guard VirtualRunManager.shared.phase == .idle else {
                logger.info("⏸ Skipping startWatchWorkout: virtual run is in progress")
                break
            }
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
            guard VirtualRunManager.shared.phase == .idle else {
                logger.info("⏸ Skipping endWatchWorkout: virtual run is in progress")
                break
            }
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
            guard VirtualRunManager.shared.phase == .idle else {
                logger.info("⏸ Skipping discardWatchWorkout: virtual run is in progress")
                break
            }
            Task {
                do {
                    try await WatchHealthKitManager.shared.endWorkout(discard: true)
                    logger.info("🗑️ Discarded HKWorkoutSession from iPhone trigger")
                } catch {
                    logger.error("Failed to discard workout: \(error.localizedDescription)")
                }
            }

        // Virtual Run messages from iPhone
        case WatchMessage.vrPartnerUpdate.rawValue:
            handleVirtualRunPartnerUpdate(message)

        case WatchMessage.vrRunStarted.rawValue:
            handleVirtualRunStarted(message)

        case WatchMessage.vrRunEnded.rawValue:
            handleVirtualRunEnded()

        case WatchMessage.vrPartnerFinished.rawValue:
            handleVirtualRunPartnerFinished(message)

        case WatchMessage.vrHeartbeat.rawValue:
            Task { @MainActor in
                VirtualRunManager.shared.receiveHeartbeat()
            }

        default:
            logger.warning("Unknown message type: \(type)")
        }
    }

    // MARK: - Virtual Run Handlers

    private func handleVirtualRunPartnerUpdate(_ message: [String: Any]) {
        guard let data = message["data"] as? Data else {
            logger.error("VR partner update missing data")
            VirtualRunFileLogger.shared.log(category: .error, message: "VR partner update missing data")
            return
        }

        do {
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let snapshot = VirtualRunSnapshot.fromCompactDict(dict) else {
                logger.error("Failed to decode VR partner snapshot")
                VirtualRunFileLogger.shared.log(category: .error, message: "Failed to decode VR partner snapshot")
                return
            }

            logger.debug("📡 Received partner update (seq: \(snapshot.seq))")
            VirtualRunFileLogger.shared.log(category: .partner, message: "Partner update received via WC", data: [
                "seq": snapshot.seq,
                "distance": snapshot.distanceM,
                "heartRate": snapshot.heartRate as Any
            ])
            Task { @MainActor in
                VirtualRunManager.shared.receivePartnerUpdate(snapshot)
            }
        } catch {
            logger.error("Failed to deserialize VR partner data: \(error.localizedDescription)")
            VirtualRunFileLogger.shared.log(category: .error, message: "Failed to deserialize VR partner data: \(error.localizedDescription)")
        }
    }

    private func handleVirtualRunStarted(_ message: [String: Any]) {
        guard let data = message["data"] as? Data else {
            logger.error("VR started message missing data")
            VirtualRunFileLogger.shared.log(category: .error, message: "VR started message missing data")
            return
        }

        do {
            guard let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("VR started message not a dictionary")
                return
            }

            guard let runIdStr = info["runId"] as? String, let runId = UUID(uuidString: runIdStr),
                  let partnerIdStr = info["partnerId"] as? String, let partnerId = UUID(uuidString: partnerIdStr),
                  let partnerName = info["partnerName"] as? String,
                  let myUserIdStr = info["myUserId"] as? String, let myUserId = UUID(uuidString: myUserIdStr) else {
                logger.error("VR started message missing fields")
                return
            }

            // Dedup: skip if we already processed this run (both sendMessage and transferUserInfo may deliver)
            if lastProcessedVRRunId == runId {
                logger.info("⏭️ Already processed VR start for run \(runIdStr), skipping duplicate")
                return
            }
            lastProcessedVRRunId = runId

            let myMaxHR = info["myMaxHR"] as? Int ?? 190
            let partnerMaxHR = info["partnerMaxHR"] as? Int ?? 190

            logger.info("🏃 Virtual run started with \(partnerName), myMaxHR=\(myMaxHR), partnerMaxHR=\(partnerMaxHR)")
            VirtualRunFileLogger.shared.log(category: .connectivity, message: "VR started received", data: [
                "runId": runIdStr,
                "partner": partnerName,
                "myMaxHR": myMaxHR,
                "partnerMaxHR": partnerMaxHR
            ])

            let partner = PartnerStats(userId: partnerId, displayName: partnerName, maxHR: partnerMaxHR)

            // Show confirmation screen on Watch — user must tap Go to start
            Task { @MainActor in
                VirtualRunManager.shared.setPendingRun(
                    runId: runId,
                    myUserId: myUserId,
                    partner: partner,
                    myMaxHR: myMaxHR
                )

                // Schedule a time-sensitive notification to bring the app to foreground
                self.scheduleVirtualRunNotification(partnerName: partnerName)
            }
        } catch {
            logger.error("Failed to decode VR started: \(error.localizedDescription)")
        }
    }

    private func handleVirtualRunEnded() {
        logger.info("🏁 Virtual run ended by iPhone")
        VirtualRunFileLogger.shared.log(category: .connectivity, message: "VR ended by iPhone")
        lastProcessedVRRunId = nil
        cancelVirtualRunNotification()
        Task { @MainActor in
            VirtualRunManager.shared.endVirtualRun()

            // End the HealthKit workout and save it
            do {
                try await WatchHealthKitManager.shared.endWorkout(discard: false)
                logger.info("✅ Ended and saved running workout")
            } catch {
                logger.error("Failed to end running workout: \(error.localizedDescription)")
            }
        }
    }

    private func handleVirtualRunPartnerFinished(_ message: [String: Any]) {
        let distance = message["partnerDistance"] as? Double ?? 0
        let duration = message["partnerDuration"] as? Int ?? 0
        let pace = message["partnerPace"] as? Int
        logger.info("🏁 Partner finished at \(String(format: "%.0f", distance))m")
        Task { @MainActor in
            VirtualRunManager.shared.handlePartnerFinished(distance: distance, duration: duration, pace: pace)
        }
    }

    // MARK: - Local Notifications

    // Notification category & action identifiers
    static let vrCategoryId = "VIRTUAL_RUN_INVITE"
    private static let vrStartActionId = "VR_START_ACTION"
    private static let vrNotificationId = "virtual-run-invite"

    private func requestNotificationPermission() {
        // Register actionable notification category
        let startAction = UNNotificationAction(
            identifier: Self.vrStartActionId,
            title: "Start Run",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.vrCategoryId,
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Set ourselves as delegate to handle notification taps
        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor [weak self] in
                if let error = error {
                    self?.logger.error("Watch notification permission error: \(error.localizedDescription)")
                } else {
                    self?.logger.info("Watch notification permission granted: \(granted)")
                }
            }
        }
    }

    /// Schedule a time-sensitive local notification for a virtual run invite
    private func scheduleVirtualRunNotification(partnerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Virtual Run"
        content.body = "\(partnerName) wants to run with you!"
        content.sound = .default
        content.categoryIdentifier = Self.vrCategoryId
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.vrNotificationId,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error = error {
                    self?.logger.error("Failed to schedule VR notification: \(error.localizedDescription)")
                } else {
                    self?.logger.info("Scheduled time-sensitive VR invite notification for \(partnerName)")
                }
            }
        }
    }

    /// Cancel any pending virtual run notification (user already responded or run ended)
    func cancelVirtualRunNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.vrNotificationId]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.vrNotificationId]
        )
    }

    /// Send a message with WatchMessage type (for virtual run snapshots/heartbeats)
    func sendMessage(type: VirtualRunMessageType, payload: [String: Any]) {
        let messageType: WatchMessage
        switch type {
        case .snapshot: messageType = .vrSnapshot
        case .heartbeat: messageType = .vrHeartbeat
        case .partnerUpdate: messageType = .vrPartnerUpdate
        case .runStarted: messageType = .vrRunStarted
        case .runEnded: messageType = .vrRunEnded
        case .partnerFinished: messageType = .vrPartnerFinished
        case .watchConfirmed: messageType = .vrWatchConfirmed
        case .pause: messageType = .vrPause
        case .resume: messageType = .vrResume
        }
        VirtualRunFileLogger.shared.log(category: .connectivity, message: "Sending VR message", data: [
            "type": messageType.rawValue,
            "payloadKeys": Array(payload.keys).joined(separator: ",")
        ])
        send(type: messageType, payload: payload)
    }

    // MARK: - Guaranteed Delivery (transferUserInfo)

    /// Send runEnded via transferUserInfo for guaranteed delivery (survives Watch app termination)
    func sendRunEndedGuaranteed(payload: [String: Any]) {
        guard let session = session else { return }

        var message: [String: Any] = ["messageType": WatchMessage.vrRunEnded.rawValue]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            message["payload"] = data
        }

        session.transferUserInfo(message)
        logger.info("📨 Queued runEnded via transferUserInfo (guaranteed delivery)")
        VirtualRunFileLogger.shared.log(category: .connectivity, message: "Sent runEnded via transferUserInfo")
    }

    // MARK: - Log File Transfer

    /// Transfer the current VR log file to iPhone via WCSession file transfer
    func transferLogFile() {
        guard let session = session else {
            logger.warning("No WCSession available for log transfer")
            return
        }
        guard let logURL = VirtualRunFileLogger.shared.currentLogFileURL,
              FileManager.default.fileExists(atPath: logURL.path) else {
            // No active session — try transferring the most recent log
            if let mostRecent = VirtualRunFileLogger.shared.allLogFiles.first,
               FileManager.default.fileExists(atPath: mostRecent.path) {
                session.transferFile(mostRecent, metadata: ["type": "vrLog", "name": mostRecent.lastPathComponent])
                logger.info("Transferring most recent log: \(mostRecent.lastPathComponent)")
                return
            }
            logger.warning("No log file available for transfer")
            return
        }
        session.transferFile(logURL, metadata: ["type": "vrLog", "name": logURL.lastPathComponent])
        logger.info("Transferring current log: \(logURL.lastPathComponent)")
    }

    func sendMessage<T: Encodable>(type: VirtualRunMessageType, payload: T) {
        guard let data = try? JSONEncoder().encode(payload) else {
            logger.error("Failed to encode VR payload")
            return
        }
        let messageType: WatchMessage
        switch type {
        case .snapshot: messageType = .vrSnapshot
        case .heartbeat: messageType = .vrHeartbeat
        case .partnerUpdate: messageType = .vrPartnerUpdate
        case .runStarted: messageType = .vrRunStarted
        case .runEnded: messageType = .vrRunEnded
        case .partnerFinished: messageType = .vrPartnerFinished
        case .watchConfirmed: messageType = .vrWatchConfirmed
        case .pause: messageType = .vrPause
        case .resume: messageType = .vrResume
        }
        sendMessage(type: messageType, payload: data)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WatchConnectivityManager: UNUserNotificationCenterDelegate {

    /// Show notifications even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap or "Start Run" action
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.content.categoryIdentifier == Self.vrCategoryId else {
            completionHandler()
            return
        }

        Task { @MainActor in
            let actionId = response.actionIdentifier

            if actionId == Self.vrStartActionId {
                // User tapped "Start Run" action — auto-confirm the run
                VirtualRunManager.shared.confirmRun()
            }
            // Default tap (UNNotificationDefaultActionIdentifier) just opens the app
            // which will show the pending confirmation screen via showVirtualRunUI
        }

        completionHandler()
    }
}

// MARK: - transferUserInfo (guaranteed delivery)

extension WatchConnectivityManager {

    /// Handle user info transfers from iPhone (guaranteed delivery, even if app wasn't running)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            logger.info("📨 Received transferUserInfo with keys: \(userInfo.keys.joined(separator: ", "))")
            handleIncomingMessage(userInfo)
        }
    }
}
