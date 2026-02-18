//
//  VirtualRunManager.swift
//  WRKT Watch
//
//  Manages virtual run state on Apple Watch:
//  partner stats, interpolation, haptics, GPS smoothing, and battery optimization
//

import Foundation
import WatchKit
import OSLog

// MARK: - Virtual Run Phase

enum VirtualRunPhase: Equatable {
    case idle
    case pendingConfirmation
    case countdown(Int)
    case active
    case paused
}

struct PendingRunInfo {
    let runId: UUID
    let myUserId: UUID
    let partner: PartnerStats
    let myMaxHR: Int
}

@Observable
@MainActor
class VirtualRunManager {
    static let shared = VirtualRunManager()
    private let logger = Logger(subsystem: "com.wrkt.watch", category: "virtualrun")

    // MARK: - State

    private(set) var phase: VirtualRunPhase = .idle
    private(set) var pendingRunInfo: PendingRunInfo?
    private(set) var isInVirtualRun = false
    private(set) var currentRunId: UUID?
    private(set) var myStats: VirtualRunSnapshot?
    private(set) var partnerStats: PartnerStats?
    private(set) var myMaxHR: Int = 190

    /// Whether the Watch should show virtual run UI (confirmation, countdown, active, or paused run)
    var showVirtualRunUI: Bool {
        phase != .idle
    }

    // Connection health
    private(set) var connectionHealth = ConnectionHealth()
    private var heartbeatTimer: Timer?
    private var interpolationTimer: Timer?
    private var statsPublishTimer: Timer?
    private var batteryTimer: Timer?
    private var countdownTimer: Timer?
    private var confirmationTimeoutTimer: Timer?
    private(set) var runStartTime: Date?

    // Pause tracking
    private(set) var pausedElapsedBeforePause: TimeInterval = 0
    private var pauseStartTime: Date?

    // Extended disconnect tracking
    private(set) var disconnectStartTime: Date?
    private(set) var showDisconnectPrompt = false

    // Partner finished state
    private(set) var showPartnerFinished = false
    private(set) var partnerFinalDistance: Double = 0
    private(set) var partnerFinalDuration: Int = 0
    private(set) var partnerFinalPace: Int?

    // Km milestone tracking for haptics
    private var lastKmMilestone: Int = 0

    // Lead tracking (with debounce)
    private var lastLeader: UUID?
    private var lastHapticTime: Date = .distantPast
    private var myUserId: UUID?

    // Sequence number for ordering
    private var localSeq: Int = 0

    // GPS Kalman filter for smoothing
    private var kalmanFilter = KalmanFilter()

    // Battery optimization
    private var isLowBatteryMode = false

    // Reconnection
    let reconnectionManager = ReconnectionManager()

    // MARK: - Confirmation & Countdown

    /// Called when iPhone sends a virtual run invite — shows confirmation screen on Watch
    func setPendingRun(runId: UUID, myUserId: UUID, partner: PartnerStats, myMaxHR: Int) {
        pendingRunInfo = PendingRunInfo(runId: runId, myUserId: myUserId, partner: partner, myMaxHR: myMaxHR)
        partnerStats = partner
        phase = .pendingConfirmation
        WKInterfaceDevice.current().play(.notification)
        startConfirmationTimeout()
    }

    /// User confirmed — start 3-2-1 countdown
    func confirmRun() {
        guard pendingRunInfo != nil else { return }
        cancelConfirmationTimeout()
        WatchConnectivityManager.shared.cancelVirtualRunNotification()
        phase = .countdown(3)
        WKInterfaceDevice.current().play(.click)
        startCountdown()

        // Notify iPhone that Watch user confirmed — include coordinated start time
        let startTime = Date().addingTimeInterval(3.0)
        WatchConnectivityManager.shared.sendMessage(
            type: .watchConfirmed,
            payload: ["startTime": startTime.timeIntervalSince1970]
        )
    }

    /// User declined — notify iPhone and reset
    func declineRun() {
        cancelConfirmationTimeout()
        WatchConnectivityManager.shared.cancelVirtualRunNotification()
        pendingRunInfo = nil
        partnerStats = nil
        phase = .idle
        WatchConnectivityManager.shared.sendMessage(
            type: .runEnded,
            payload: [String: String]()
        )
    }

    /// Auto-decline if user doesn't respond within 60 seconds
    private func startConfirmationTimeout() {
        cancelConfirmationTimeout()
        let timer = Timer(timeInterval: 60.0, repeats: false) { [weak self] _ in
            guard let self, self.phase == .pendingConfirmation else { return }
            self.logger.info("Confirmation timed out — auto-declining")
            self.declineRun()
        }
        RunLoop.main.add(timer, forMode: .common)
        confirmationTimeoutTimer = timer
    }

    private func cancelConfirmationTimeout() {
        confirmationTimeoutTimer?.invalidate()
        confirmationTimeoutTimer = nil
    }

    private func startCountdown() {
        var remaining = 3
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            remaining -= 1
            if remaining > 0 {
                self.phase = .countdown(remaining)
                WKInterfaceDevice.current().play(.click)
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                self.finishCountdownAndStart()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func finishCountdownAndStart() {
        guard let info = pendingRunInfo else { return }
        pendingRunInfo = nil

        // Start HealthKit running workout
        Task {
            do {
                try await WatchHealthKitManager.shared.startRunningWorkout()
                logger.info("Started running workout for virtual run")
            } catch {
                logger.error("Failed to start running workout: \(error.localizedDescription)")
            }
        }

        startVirtualRun(runId: info.runId, myUserId: info.myUserId, partner: info.partner, myMaxHR: info.myMaxHR)
    }

    // MARK: - Lifecycle

    func startVirtualRun(runId: UUID, myUserId: UUID, partner: PartnerStats, myMaxHR: Int = 190) {
        self.currentRunId = runId
        self.myUserId = myUserId
        self.partnerStats = partner
        self.myMaxHR = myMaxHR
        self.isInVirtualRun = true
        self.phase = .active
        self.localSeq = 0
        self.lastLeader = nil
        self.runStartTime = Date()
        self.lastKmMilestone = 0

        VirtualRunFileLogger.shared.startSession()
        VirtualRunFileLogger.shared.log(category: .phase, message: "Virtual run started", data: [
            "runId": runId.uuidString,
            "myUserId": myUserId.uuidString,
            "partner": partner.displayName,
            "myMaxHR": myMaxHR
        ])

        startTimers()
        WKInterfaceDevice.current().play(.start)
    }

    func endVirtualRun() {
        VirtualRunFileLogger.shared.log(category: .phase, message: "Virtual run ending")

        countdownTimer?.invalidate()
        countdownTimer = nil
        cancelConfirmationTimeout()
        pendingRunInfo = nil
        phase = .idle
        stopTimers()
        reconnectionManager.reset()
        isInVirtualRun = false
        currentRunId = nil
        myStats = nil
        partnerStats = nil
        runStartTime = nil
        lastKmMilestone = 0
        pausedElapsedBeforePause = 0
        pauseStartTime = nil
        disconnectStartTime = nil
        showDisconnectPrompt = false
        showPartnerFinished = false
        kalmanFilter.reset()
        clearPersistedState()

        VirtualRunFileLogger.shared.endSession()

        // Auto-transfer log file to iPhone
        WatchConnectivityManager.shared.transferLogFile()

        WKInterfaceDevice.current().play(.stop)
    }

    /// End run from Watch — notify iPhone, save HealthKit workout, and stop locally
    func requestEndRun() {
        // Include final stats so iPhone can write the Supabase summary
        var payload: [String: Any] = [:]
        if let stats = myStats {
            payload["distance"] = stats.distanceM
            payload["duration"] = stats.durationS
            if let pace = stats.currentPaceSecPerKm { payload["pace"] = pace }
            if let hr = stats.heartRate { payload["heartRate"] = hr }
        }
        WatchConnectivityManager.shared.sendMessage(
            type: .runEnded,
            payload: payload
        )
        endVirtualRun()

        // Save HealthKit running workout
        Task {
            do {
                try await WatchHealthKitManager.shared.endWorkout(discard: false)
                logger.info("Saved running workout after Watch-initiated end")
            } catch {
                logger.error("Failed to end running workout: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Pause / Resume

    func pauseRun() {
        guard phase == .active else { return }
        phase = .paused
        pauseStartTime = Date()

        // Stop snapshot publishing and interpolation (heartbeat keeps running)
        statsPublishTimer?.invalidate()
        statsPublishTimer = nil
        interpolationTimer?.invalidate()
        interpolationTimer = nil

        // Pause HealthKit workout
        Task {
            do {
                try await WatchHealthKitManager.shared.pauseWorkout()
                logger.info("Paused HK workout for virtual run")
            } catch {
                logger.error("Failed to pause HK workout: \(error.localizedDescription)")
            }
        }

        // Notify iPhone
        WatchConnectivityManager.shared.sendMessage(
            type: .pause,
            payload: [String: String]()
        )

        VirtualRunFileLogger.shared.log(category: .phase, message: "Run paused")
        WKInterfaceDevice.current().play(.click)
    }

    func resumeRun() {
        guard phase == .paused else { return }
        phase = .active

        // Track accumulated paused time
        if let pauseStart = pauseStartTime {
            pausedElapsedBeforePause += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil

        // Restart snapshot publishing and interpolation
        // Interpolation now driven by TimelineView in VirtualRunView

        let pubTimer = Timer(timeInterval: publishInterval, repeats: true) { [weak self] _ in
            self?.publishCurrentStats()
        }
        RunLoop.main.add(pubTimer, forMode: .common)
        statsPublishTimer = pubTimer

        // Resume HealthKit workout
        Task {
            do {
                try await WatchHealthKitManager.shared.resumeWorkout()
                logger.info("Resumed HK workout for virtual run")
            } catch {
                logger.error("Failed to resume HK workout: \(error.localizedDescription)")
            }
        }

        // Notify iPhone
        WatchConnectivityManager.shared.sendMessage(
            type: .resume,
            payload: [String: String]()
        )

        VirtualRunFileLogger.shared.log(category: .phase, message: "Run resumed")
        WKInterfaceDevice.current().play(.start)
    }

    /// Dismiss disconnect prompt and reset timer (user chose "Keep Waiting")
    func dismissDisconnectPrompt() {
        showDisconnectPrompt = false
        disconnectStartTime = nil
    }

    // MARK: - Partner Finished

    func handlePartnerFinished(distance: Double, duration: Int, pace: Int?) {
        partnerFinalDistance = distance
        partnerFinalDuration = duration
        partnerFinalPace = pace
        showPartnerFinished = true
        showDisconnectPrompt = false
        disconnectStartTime = nil
        WKInterfaceDevice.current().play(.notification)
        VirtualRunAudioCues.shared.announcePartnerFinished()
        VirtualRunFileLogger.shared.log(category: .phase, message: "Partner finished", data: [
            "distance": distance, "duration": duration
        ])
    }

    func dismissPartnerFinished() {
        showPartnerFinished = false
    }

    // MARK: - Timers

    private func startTimers() {
        let hbTimer = Timer(timeInterval: VirtualRunConstants.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
            self?.checkExtendedDisconnect()
        }
        RunLoop.main.add(hbTimer, forMode: .common)
        heartbeatTimer = hbTimer

        // Interpolation now driven by TimelineView in VirtualRunView

        // Publish stats to partner at regular intervals
        let pubTimer = Timer(timeInterval: publishInterval, repeats: true) { [weak self] _ in
            self?.publishCurrentStats()
        }
        RunLoop.main.add(pubTimer, forMode: .common)
        statsPublishTimer = pubTimer

        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        checkBatteryLevel()

        // Check battery periodically (every 60s) during long runs
        let batTimer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkBatteryLevel()
        }
        RunLoop.main.add(batTimer, forMode: .common)
        batteryTimer = batTimer
    }

    private func stopTimers() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        interpolationTimer?.invalidate()
        interpolationTimer = nil
        statsPublishTimer?.invalidate()
        statsPublishTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    /// Read from HealthKit and publish stats to partner
    private func publishCurrentStats() {
        guard phase == .active else { return }

        let healthManager = WatchHealthKitManager.shared

        // Get duration from run start time, subtracting paused time
        let totalElapsed = runStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let duration = Int(totalElapsed - pausedElapsedBeforePause)

        // Heart rate from HealthKit (already in bpm)
        let heartRate = healthManager.heartRate > 0 ? Int(healthManager.heartRate) : nil

        // Distance from HealthKit (meters)
        var currentDistance = healthManager.distance

        // Calculate pace (sec/km) if we have enough distance (50m min to avoid GPS drift noise)
        // Cap at 30:00/km (1800 sec/km) — anything higher is not useful
        let pace: Int? = {
            guard duration > 10, currentDistance > 50 else { return nil }
            let raw = Int((Double(duration) / currentDistance) * 1000)
            return raw > 1800 ? nil : raw
        }()

        VirtualRunFileLogger.shared.log(category: .snapshotOut, message: "Publishing stats", data: [
            "distance": currentDistance,
            "duration": duration,
            "pace": pace as Any,
            "heartRate": heartRate as Any
        ])

        let loc = WatchHealthKitManager.shared.lastLocation
        updateMyStats(
            distance: currentDistance,
            duration: duration,
            pace: pace,
            heartRate: heartRate,
            lat: loc?.coordinate.latitude,
            lon: loc?.coordinate.longitude
        )

        // Check for km milestones and play haptic
        let currentKm = Int(currentDistance / 1000)
        if currentKm > lastKmMilestone {
            lastKmMilestone = currentKm
            // Play success haptic for km milestone
            WKInterfaceDevice.current().play(.success)
            VirtualRunAudioCues.shared.announceKilometer(currentKm)
        }
    }

    private func sendHeartbeat() {
        connectionHealth.lastHeartbeatSent = Date()
        WatchConnectivityManager.shared.sendMessage(
            type: .heartbeat,
            payload: [String: String]()
        )
    }

    private func checkBatteryLevel() {
        let level = WKInterfaceDevice.current().batteryLevel
        isLowBatteryMode = level < VirtualRunConstants.lowBatteryThreshold && level > 0
    }

    /// Monitor partner connection for extended disconnect (3+ minutes)
    private func checkExtendedDisconnect() {
        guard let partner = partnerStats else { return }

        if partner.connectionStatus == .disconnected {
            if disconnectStartTime == nil {
                disconnectStartTime = Date()
            } else if let start = disconnectStartTime,
                      Date().timeIntervalSince(start) > VirtualRunConstants.extendedDisconnectTimeout {
                if !showDisconnectPrompt {
                    showDisconnectPrompt = true
                    VirtualRunFileLogger.shared.log(category: .phase, message: "Extended disconnect detected", data: [
                        "disconnectedSeconds": Int(Date().timeIntervalSince(start))
                    ])
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        } else {
            // Partner reconnected or is paused — reset tracking
            if disconnectStartTime != nil {
                disconnectStartTime = nil
                showDisconnectPrompt = false
            }
        }
    }

    // MARK: - Stats Updates

    func updateMyStats(
        distance: Double,
        duration: Int,
        pace: Int?,
        heartRate: Int?,
        lat: Double?,
        lon: Double?
    ) {
        guard let runId = currentRunId, let userId = myUserId else { return }

        // Apply GPS smoothing
        if let lat = lat, let lon = lon {
            _ = kalmanFilter.process(lat: lat, lon: lon, accuracy: 10)
        }

        localSeq += 1

        myStats = VirtualRunSnapshot(
            virtualRunId: runId,
            userId: userId,
            distanceM: distance,
            durationS: duration,
            currentPaceSecPerKm: pace,
            heartRate: heartRate,
            calories: nil,
            latitude: lat,
            longitude: lon,
            seq: localSeq,
            clientRecordedAt: Date(),
            serverReceivedAt: nil,
            isPaused: phase == .paused
        )

        // Forward snapshot to iPhone for Supabase sync
        if let stats = myStats {
            let compact = stats.toCompactDict()
            WatchConnectivityManager.shared.sendMessage(
                type: .snapshot,
                payload: compact
            )
        }

        // Persist state for crash recovery
        persistState()
    }

    func receivePartnerUpdate(_ snapshot: VirtualRunSnapshot) {
        guard let partner = partnerStats else { return }

        VirtualRunFileLogger.shared.log(category: .snapshotIn, message: "Partner update received", data: [
            "seq": snapshot.seq,
            "distance": snapshot.distanceM,
            "duration": snapshot.durationS,
            "heartRate": snapshot.heartRate as Any,
            "pace": snapshot.currentPaceSecPerKm as Any
        ])

        let wasUpdated = partner.update(from: snapshot)

        if wasUpdated {
            connectionHealth.lastHeartbeatReceived = Date()
            connectionHealth.consecutiveFailures = 0
            checkLeadChange()
        }
    }

    func receiveHeartbeat() {
        connectionHealth.lastHeartbeatReceived = Date()
    }

    // MARK: - Lead Change & Haptics

    private func checkLeadChange() {
        guard let myStats = myStats else {
            logger.debug("checkLeadChange: myStats is nil, skipping")
            return
        }
        guard let partner = partnerStats else {
            logger.debug("checkLeadChange: partnerStats is nil, skipping")
            return
        }
        guard let myUserId = myUserId else {
            logger.debug("checkLeadChange: myUserId is nil, skipping")
            return
        }

        let myDistance = myStats.distanceM
        let partnerDistance = partner.rawDistanceM
        let difference = abs(myDistance - partnerDistance)

        guard difference > VirtualRunConstants.leadChangeThreshold else {
            logger.debug("checkLeadChange: difference \(String(format: "%.1f", difference))m below threshold \(VirtualRunConstants.leadChangeThreshold)m")
            return
        }
        guard Date().timeIntervalSince(lastHapticTime) > VirtualRunConstants.leadChangeDebounce else {
            logger.debug("checkLeadChange: debounce active, \(String(format: "%.1f", Date().timeIntervalSince(self.lastHapticTime)))s since last haptic")
            return
        }

        let currentLeader: UUID? = myDistance > partnerDistance ? myUserId : partner.userId

        logger.info("checkLeadChange: me=\(String(format: "%.1f", myDistance))m partner=\(String(format: "%.1f", partnerDistance))m diff=\(String(format: "%.1f", difference))m leader=\(currentLeader == myUserId ? "me" : "partner")")

        if currentLeader != lastLeader {
            let newLeaderStr = currentLeader == myUserId ? "me" : "partner"
            VirtualRunFileLogger.shared.log(category: .phase, message: "Lead changed", data: [
                "newLeader": newLeaderStr,
                "myDistance": myDistance,
                "partnerDistance": partnerDistance
            ])
            if currentLeader == myUserId {
                logger.info("checkLeadChange: I took the lead — playing success haptic")
                WKInterfaceDevice.current().play(.success)
                VirtualRunAudioCues.shared.announceLeadChange(isLeading: true)
            } else {
                logger.info("checkLeadChange: partner took the lead — playing failure haptic")
                WKInterfaceDevice.current().play(.failure)
                VirtualRunAudioCues.shared.announceLeadChange(isLeading: false)
            }
            lastLeader = currentLeader
            lastHapticTime = Date()
        }
    }

    // MARK: - Publish Interval (battery-aware)

    var publishInterval: TimeInterval {
        isLowBatteryMode
            ? VirtualRunConstants.lowBatteryPublishInterval
            : VirtualRunConstants.snapshotPublishInterval
    }

    // MARK: - State Persistence

    private static let stateKey = "virtual_run_state"

    func persistState() {
        guard let runId = currentRunId,
              let partner = partnerStats,
              let myStats = myStats else { return }

        let state = VirtualRunState(
            runId: runId,
            partnerId: partner.userId,
            partnerName: partner.displayName,
            myLastDistance: myStats.distanceM,
            myLastDuration: myStats.durationS,
            startedAt: Date(),
            lastSeq: localSeq
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    func restoreStateIfNeeded() -> VirtualRunState? {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(VirtualRunState.self, from: data) else {
            return nil
        }
        return state
    }

    func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
    }
}

// MARK: - Kalman Filter for GPS Smoothing

class KalmanFilter {
    private var lat: Double = 0
    private var lon: Double = 0
    private var variance: Double = -1

    private let minAccuracy: Double = 1
    private let processNoise: Double = VirtualRunConstants.gpsKalmanProcessNoise

    func process(lat: Double, lon: Double, accuracy: Double) -> (lat: Double, lon: Double) {
        let accuracy = max(accuracy, minAccuracy)

        if variance < 0 {
            self.lat = lat
            self.lon = lon
            variance = accuracy * accuracy
        } else {
            // Predict
            variance += processNoise

            // Update
            let k = variance / (variance + accuracy * accuracy)
            self.lat += k * (lat - self.lat)
            self.lon += k * (lon - self.lon)
            variance = (1 - k) * variance
        }

        return (self.lat, self.lon)
    }

    func reset() {
        variance = -1
    }
}

// MARK: - Reconnection Manager

class ReconnectionManager {
    private var retryCount = 0
    private var retryTask: Task<Void, Never>?

    func scheduleReconnect(action: @escaping () async -> Bool) {
        retryTask?.cancel()

        guard retryCount < VirtualRunConstants.reconnectMaxAttempts else { return }

        let delay = min(
            pow(2.0, Double(retryCount)) * VirtualRunConstants.reconnectBaseDelay,
            VirtualRunConstants.reconnectMaxDelay
        )

        retryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let success = await action()
            if success {
                retryCount = 0
            } else {
                retryCount += 1
                scheduleReconnect(action: action)
            }
        }
    }

    func reset() {
        retryTask?.cancel()
        retryCount = 0
    }
}
