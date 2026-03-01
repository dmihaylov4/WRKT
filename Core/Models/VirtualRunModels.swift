//
//  VirtualRunModels.swift
//  WRKT
//
//  iOS-only models for the Virtual Running Together feature.
//  Shared types (VirtualRunConstants, VirtualRunSnapshot, PartnerStats,
//  ConnectionHealth, VirtualRunState, VirtualRunMessageType) live in
//  Shared/VirtualRunSharedModels.swift so the Watch target can use them too.
//

import Foundation

// MARK: - Virtual Run (Supabase row)

struct VirtualRun: Codable, Identifiable, Sendable {
    let id: UUID
    let inviterId: UUID
    let inviteeId: UUID
    var status: VirtualRunStatus
    var startedAt: Date?
    var endedAt: Date?
    let createdAt: Date

    // Summary (populated on completion)
    var inviterDistanceM: Double?
    var inviterDurationS: Int?
    var inviterAvgPaceSecPerKm: Int?
    var inviterAvgHeartRate: Int?
    var inviteeDistanceM: Double?
    var inviteeDurationS: Int?
    var inviteeAvgPaceSecPerKm: Int?
    var inviteeAvgHeartRate: Int?
    var winnerId: UUID?

    // Route upload flags
    var inviterRouteUploaded: Bool?
    var inviteeRouteUploaded: Bool?

    // Invite expiration (pending invites auto-cancel after this time)
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case inviterId = "inviter_id"
        case inviteeId = "invitee_id"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case inviterDistanceM = "inviter_distance_m"
        case inviterDurationS = "inviter_duration_s"
        case inviterAvgPaceSecPerKm = "inviter_avg_pace_sec_per_km"
        case inviterAvgHeartRate = "inviter_avg_heart_rate"
        case inviteeDistanceM = "invitee_distance_m"
        case inviteeDurationS = "invitee_duration_s"
        case inviteeAvgPaceSecPerKm = "invitee_avg_pace_sec_per_km"
        case inviteeAvgHeartRate = "invitee_avg_heart_rate"
        case winnerId = "winner_id"
        case inviterRouteUploaded = "inviter_route_uploaded"
        case inviteeRouteUploaded = "invitee_route_uploaded"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        inviterId = try container.decode(UUID.self, forKey: .inviterId)
        inviteeId = try container.decode(UUID.self, forKey: .inviteeId)
        status = try container.decode(VirtualRunStatus.self, forKey: .status)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        inviterDistanceM = try container.decodeIfPresent(Double.self, forKey: .inviterDistanceM)
        inviterDurationS = try container.decodeIfPresent(Int.self, forKey: .inviterDurationS)
        inviterAvgPaceSecPerKm = try container.decodeIfPresent(Int.self, forKey: .inviterAvgPaceSecPerKm)
        inviterAvgHeartRate = try container.decodeIfPresent(Int.self, forKey: .inviterAvgHeartRate)
        inviteeDistanceM = try container.decodeIfPresent(Double.self, forKey: .inviteeDistanceM)
        inviteeDurationS = try container.decodeIfPresent(Int.self, forKey: .inviteeDurationS)
        inviteeAvgPaceSecPerKm = try container.decodeIfPresent(Int.self, forKey: .inviteeAvgPaceSecPerKm)
        inviteeAvgHeartRate = try container.decodeIfPresent(Int.self, forKey: .inviteeAvgHeartRate)
        winnerId = try container.decodeIfPresent(UUID.self, forKey: .winnerId)
        inviterRouteUploaded = try container.decodeIfPresent(Bool.self, forKey: .inviterRouteUploaded)
        inviteeRouteUploaded = try container.decodeIfPresent(Bool.self, forKey: .inviteeRouteUploaded)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

enum VirtualRunStatus: String, Codable, Sendable {
    case pending
    case active
    case completed
    case cancelled
}

// MARK: - Run Summary

struct RunSummary: Codable, Sendable {
    let inviterDistanceM: Double
    let inviterDurationS: Int
    let inviterAvgPaceSecPerKm: Int?
    let inviterAvgHeartRate: Int?
    let inviteeDistanceM: Double
    let inviteeDurationS: Int
    let inviteeAvgPaceSecPerKm: Int?
    let inviteeAvgHeartRate: Int?
    let winnerId: UUID?
}

// MARK: - Virtual Run Completion (for summary screen)

struct VirtualRunCompletionData {
    let runId: UUID
    let partnerName: String

    // My stats (from Watch payload)
    let myDistanceM: Double
    let myDurationS: Int
    let myPaceSecPerKm: Int?
    let myAvgHR: Int?

    // Partner stats (from last known snapshot)
    let partnerDistanceM: Double
    let partnerDurationS: Int
    let partnerPaceSecPerKm: Int?
    let partnerAvgHR: Int?
}

// MARK: - Errors

enum VirtualRunError: LocalizedError {
    case alreadyInActiveRun
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .alreadyInActiveRun: return "You're already in an active virtual run"
        case .notAuthenticated: return "Not authenticated"
        }
    }
}

// MARK: - Analytics Events

enum VirtualRunEvent {
    case inviteSent
    case inviteAccepted
    case inviteDeclined
    case runStarted
    case runCompleted(durationMinutes: Int, winnerIsMe: Bool)
    case runCancelled(reason: String)
    case disconnectOccurred(durationSeconds: Int)
    case reconnectSucceeded(attempts: Int)
}
