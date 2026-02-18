//
//  VirtualRunTelemetry.swift
//  WRKT
//
//  Lightweight fire-and-forget event logger for virtual run observability.
//  Telemetry must never crash the app — all errors are silently logged.
//

import Foundation
import Supabase

@MainActor
final class VirtualRunTelemetry {
    static let shared = VirtualRunTelemetry()

    private let client: SupabaseClient

    private init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.client = client
    }

    // MARK: - Public API

    /// Log a virtual run event (fire-and-forget)
    func log(_ event: VirtualRunEvent, runId: UUID?, userId: UUID) {
        let (eventType, data) = mapEvent(event)

        Task {
            do {
                let row = EventRow(
                    run_id: runId?.uuidString,
                    user_id: userId.uuidString,
                    event_type: eventType,
                    data: data
                )
                try await client
                    .from("virtual_run_events")
                    .insert(row)
                    .execute()

                AppLogger.debug("VR telemetry: \(eventType)", category: AppLogger.virtualRun)
            } catch {
                // Telemetry must never crash — silently log
                AppLogger.debug("VR telemetry failed: \(error.localizedDescription)", category: AppLogger.virtualRun)
            }
        }
    }

    /// Log snapshot latency measurement
    func logLatency(runId: UUID, userId: UUID, latencyMs: Int, method: String) {
        Task {
            do {
                let row = EventRow(
                    run_id: runId.uuidString,
                    user_id: userId.uuidString,
                    event_type: "snapshot_latency",
                    data: [
                        "latency_ms": .integer(latencyMs),
                        "method": .string(method)
                    ]
                )
                try await client
                    .from("virtual_run_events")
                    .insert(row)
                    .execute()
            } catch {
                AppLogger.debug("VR latency telemetry failed: \(error.localizedDescription)", category: AppLogger.virtualRun)
            }
        }
    }

    // MARK: - Private

    private struct EventRow: Encodable {
        let run_id: String?
        let user_id: String
        let event_type: String
        let data: [String: AnyJSON]
    }

    private func mapEvent(_ event: VirtualRunEvent) -> (String, [String: AnyJSON]) {
        switch event {
        case .inviteSent:
            return ("invite_sent", [:])
        case .inviteAccepted:
            return ("invite_accepted", [:])
        case .inviteDeclined:
            return ("invite_declined", [:])
        case .runStarted:
            return ("run_started", [:])
        case .runCompleted(let durationMinutes, let winnerIsMe):
            return ("run_completed", [
                "duration_minutes": .integer(durationMinutes),
                "winner_is_me": .bool(winnerIsMe)
            ])
        case .runCancelled(let reason):
            return ("run_cancelled", ["reason": .string(reason)])
        case .disconnectOccurred(let durationSeconds):
            return ("disconnect_occurred", ["duration_seconds": .integer(durationSeconds)])
        case .reconnectSucceeded(let attempts):
            return ("reconnect_succeeded", ["attempts": .integer(attempts)])
        }
    }
}
