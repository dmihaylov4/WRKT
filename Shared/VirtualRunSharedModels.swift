//
//  VirtualRunSharedModels.swift
//  WRKT
//
//  Shared models for virtual run communication between iOS and watchOS
//  This file must be included in both the iOS and Watch app targets
//

import Foundation

// MARK: - Performance Constants

enum VirtualRunConstants {
    // Sync intervals
    static let snapshotPublishInterval: TimeInterval = 3.0
    static let uiInterpolationInterval: TimeInterval = 0.1
    static let watchForwardInterval: TimeInterval = 0.5

    // Connection health
    static let heartbeatInterval: TimeInterval = 3.0
    static let heartbeatTimeout: TimeInterval = 6.0
    static let staleDataThreshold: TimeInterval = 8.0
    static let disconnectThreshold: TimeInterval = 15.0

    // Extended disconnect auto-end
    static let extendedDisconnectTimeout: TimeInterval = 180 // 3 minutes

    // Reconnection (exponential backoff)
    static let reconnectBaseDelay: TimeInterval = 1.0
    static let reconnectMaxDelay: TimeInterval = 30.0
    static let reconnectMaxAttempts: Int = 10

    // Haptics
    static let leadChangeThreshold: Double = 10.0
    static let leadChangeDebounce: TimeInterval = 5.0

    // GPS smoothing
    static let gpsKalmanProcessNoise: Double = 0.008
    static let gpsMinAccuracyMeters: Double = 50.0

    // Battery optimization
    static let lowBatteryThreshold: Float = 0.20
    static let lowBatteryPublishInterval: TimeInterval = 5.0
}

// MARK: - Snapshot (for sync)

struct VirtualRunSnapshot: Codable, Sendable {
    let virtualRunId: UUID
    let userId: UUID
    var distanceM: Double
    var durationS: Int
    var currentPaceSecPerKm: Int?
    var heartRate: Int?
    var calories: Int?
    var latitude: Double?
    var longitude: Double?
    var seq: Int
    var clientRecordedAt: Date
    var serverReceivedAt: Date?
    var isPaused: Bool?

    enum CodingKeys: String, CodingKey {
        case virtualRunId = "virtual_run_id"
        case userId = "user_id"
        case distanceM = "distance_m"
        case durationS = "duration_s"
        case currentPaceSecPerKm = "current_pace_sec_per_km"
        case heartRate = "heart_rate"
        case calories
        case latitude
        case longitude
        case seq
        case clientRecordedAt = "client_recorded_at"
        case serverReceivedAt = "server_received_at"
        case isPaused = "is_paused"
    }

    // Compact encoding for WatchConnectivity (smaller payloads)
    func toCompactDict() -> [String: Any] {
        var dict: [String: Any] = [
            "r": virtualRunId.uuidString,
            "u": userId.uuidString,
            "d": distanceM,
            "t": durationS,
            "s": seq,
            "c": clientRecordedAt.timeIntervalSince1970
        ]
        if let p = currentPaceSecPerKm { dict["p"] = p }
        if let h = heartRate { dict["h"] = h }
        if let cal = calories { dict["k"] = cal }
        if let lat = latitude { dict["la"] = lat }
        if let lon = longitude { dict["lo"] = lon }
        if isPaused == true { dict["pa"] = true }
        return dict
    }

    static func fromCompactDict(_ dict: [String: Any]) -> VirtualRunSnapshot? {
        guard let r = dict["r"] as? String, let runId = UUID(uuidString: r),
              let u = dict["u"] as? String, let userId = UUID(uuidString: u),
              let d = dict["d"] as? Double,
              let t = dict["t"] as? Int,
              let s = dict["s"] as? Int,
              let c = dict["c"] as? TimeInterval else { return nil }

        return VirtualRunSnapshot(
            virtualRunId: runId,
            userId: userId,
            distanceM: d,
            durationS: t,
            currentPaceSecPerKm: dict["p"] as? Int,
            heartRate: dict["h"] as? Int,
            calories: dict["k"] as? Int,
            latitude: dict["la"] as? Double,
            longitude: dict["lo"] as? Double,
            seq: s,
            clientRecordedAt: Date(timeIntervalSince1970: c),
            serverReceivedAt: nil,
            isPaused: dict["pa"] as? Bool
        )
    }
}

// MARK: - Partner Stats (display model with interpolation)

@Observable
class PartnerStats {
    let userId: UUID
    let displayName: String
    let avatarUrl: String?
    let maxHR: Int

    // Raw stats from last snapshot
    private(set) var rawDistanceM: Double = 0
    private(set) var rawDurationS: Int = 0
    private(set) var currentPaceSecPerKm: Int?
    private(set) var heartRate: Int?
    private(set) var lastReceivedAt: Date = Date()
    private(set) var lastSeq: Int = 0

    // Pause state
    private(set) var isPaused: Bool = false

    // Interpolated values for smooth display
    var displayDistanceM: Double = 0
    var displayDurationS: Int = 0

    // Connection health
    var dataAge: TimeInterval {
        Date().timeIntervalSince(lastReceivedAt)
    }

    var isStale: Bool {
        // Don't mark as stale if partner is paused (heartbeats still arrive)
        if isPaused { return false }
        return dataAge > VirtualRunConstants.staleDataThreshold
    }

    var isDisconnected: Bool {
        // Don't mark as disconnected if partner is paused (heartbeats still arrive)
        if isPaused { return false }
        return dataAge > VirtualRunConstants.disconnectThreshold
    }

    var connectionStatus: ConnectionStatus {
        if isPaused { return .paused }
        if isDisconnected { return .disconnected }
        if isStale { return .stale }
        return .connected
    }

    enum ConnectionStatus {
        case connected
        case stale
        case disconnected
        case paused
    }

    init(userId: UUID, displayName: String, avatarUrl: String? = nil, maxHR: Int = 190) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.maxHR = maxHR
    }

    /// Update with new snapshot, returns true if this was a newer snapshot
    @discardableResult
    func update(from snapshot: VirtualRunSnapshot) -> Bool {
        guard snapshot.seq > lastSeq else { return false }

        rawDistanceM = snapshot.distanceM
        rawDurationS = snapshot.durationS
        currentPaceSecPerKm = snapshot.currentPaceSecPerKm
        heartRate = snapshot.heartRate
        isPaused = snapshot.isPaused ?? false
        lastReceivedAt = Date()
        lastSeq = snapshot.seq

        return true
    }

    /// Call on each display refresh for interpolation
    func interpolate() {
        guard !isDisconnected, !isPaused else { return }

        if let pace = currentPaceSecPerKm, pace > 0 {
            let secondsSinceUpdate = dataAge
            let metersPerSecond = 1000.0 / Double(pace)
            let estimatedProgress = metersPerSecond * secondsSinceUpdate
            displayDistanceM = rawDistanceM + min(estimatedProgress, 50)
        } else {
            displayDistanceM = rawDistanceM
        }

        displayDurationS = rawDurationS + Int(dataAge)
    }
}

// MARK: - Connection Health

struct ConnectionHealth {
    var lastHeartbeatSent: Date = .distantPast
    var lastHeartbeatReceived: Date = .distantPast
    var consecutiveFailures: Int = 0

    var isHealthy: Bool {
        Date().timeIntervalSince(lastHeartbeatReceived) < VirtualRunConstants.heartbeatTimeout
    }
}

// MARK: - State Persistence (crash recovery)

struct VirtualRunState: Codable {
    let runId: UUID
    let partnerId: UUID
    let partnerName: String
    let myLastDistance: Double
    let myLastDuration: Int
    let startedAt: Date
    let lastSeq: Int
}

// MARK: - WatchConnectivity Message Types

enum VirtualRunMessageType: String, Codable, Sendable {
    case snapshot = "vr_snapshot"
    case heartbeat = "vr_heartbeat"
    case partnerUpdate = "vr_partner"
    case runStarted = "vr_started"
    case runEnded = "vr_ended"
    case partnerFinished = "vr_partner_finished"
    case watchConfirmed = "vr_watch_confirmed"
    case pause = "vr_pause"
    case resume = "vr_resume"
}
