//
//  VirtualRunRepository.swift
//  WRKT
//
//  Repository for managing virtual runs with live sync via Supabase Realtime
//

import Foundation
import Supabase

// Defined at file scope to avoid inheriting @MainActor isolation
private struct CompleteVirtualRunParams: @preconcurrency Encodable, Sendable {
    let p_run_id: String
    let p_user_id: String
    let p_distance_m: Double
    let p_duration_s: Int
    let p_avg_pace_sec_per_km: Int?
    let p_avg_heart_rate: Int?
}

/// Repository for managing virtual run invites, lifecycle, and live snapshot sync
@MainActor
final class VirtualRunRepository: BaseRepository<VirtualRun> {

    private var realtimeChannel: RealtimeChannelV2?
    private var observationToken: Any?

    // Broadcast channel for low-latency live sync
    private var broadcastChannel: RealtimeChannelV2?
    private var broadcastObservationToken: Any?
    private var readyObservationToken: Any?

    /// True once subscribeToSnapshots has established the broadcast channel.
    /// Used by VirtualRunInviteCoordinator to skip re-subscribing when already set up.
    var isSubscribedToSnapshots: Bool { broadcastChannel != nil }

    // Timestamp-throttled DB persist (no timer — piggybacks on publishSnapshot cadence)
    private var lastDBPersistDate: Date = .distantPast

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        super.init(
            tableName: "virtual_runs",
            logPrefix: "VirtualRun",
            client: client
        )
    }

    // MARK: - Invite Management

    /// Send a virtual run invite to a friend
    func sendInvite(to userId: UUID, from currentUserId: UUID) async throws -> VirtualRun {
        // Guard: check for existing active run
        if let _ = try await fetchActiveRun(for: currentUserId) {
            throw VirtualRunError.alreadyInActiveRun
        }

        logInfo("Sending virtual run invite to \(userId)")

        struct NewVirtualRun: Encodable {
            let inviter_id: String
            let invitee_id: String
            let status: String
        }

        let data = NewVirtualRun(
            inviter_id: currentUserId.uuidString,
            invitee_id: userId.uuidString,
            status: "pending"
        )

        let run: VirtualRun = try await client
            .from("virtual_runs")
            .insert(data)
            .select()
            .single()
            .execute()
            .value

        logSuccess("Created virtual run invite: \(run.id)")

        // Telemetry
        VirtualRunTelemetry.shared.log(.inviteSent, runId: run.id, userId: currentUserId)

        // Send push notification to invitee (fire-and-forget)
        Task { await self.sendInvitePush(to: userId, from: currentUserId, runId: run.id) }

        return run
    }

    /// Accept a pending virtual run invite
    func acceptInvite(_ runId: UUID) async throws -> VirtualRun {
        guard let userId = try? await client.auth.session.user.id else {
            throw VirtualRunError.notAuthenticated
        }
        // Guard: check for existing active run
        if let _ = try await fetchActiveRun(for: userId) {
            throw VirtualRunError.alreadyInActiveRun
        }

        logInfo("Accepting virtual run invite: \(runId)")

        struct AcceptUpdate: Encodable {
            let status: String
            let started_at: String
        }

        let data = AcceptUpdate(
            status: "active",
            started_at: ISO8601DateFormatter().string(from: Date())
        )

        let run: VirtualRun = try await client
            .from("virtual_runs")
            .update(data)
            .eq("id", value: runId.uuidString)
            .select()
            .single()
            .execute()
            .value

        logSuccess("Accepted virtual run: \(run.id)")

        // Telemetry
        if let userId = try? await client.auth.session.user.id {
            VirtualRunTelemetry.shared.log(.inviteAccepted, runId: runId, userId: userId)
        }

        return run
    }

    /// Decline a pending virtual run invite
    func declineInvite(_ runId: UUID) async throws {
        logInfo("Declining virtual run invite: \(runId)")

        struct StatusUpdate: Encodable {
            let status: String
        }

        try await client
            .from("virtual_runs")
            .update(StatusUpdate(status: "cancelled"))
            .eq("id", value: runId.uuidString)
            .execute()

        logSuccess("Declined virtual run: \(runId)")

        // Telemetry
        if let userId = try? await client.auth.session.user.id {
            VirtualRunTelemetry.shared.log(.inviteDeclined, runId: runId, userId: userId)
        }
    }

    /// Fetch pending invites for the current user
    func fetchPendingInvites(for userId: UUID) async throws -> [VirtualRun] {
        logInfo("Fetching pending invites for \(userId)")

        let runs: [VirtualRun] = try await client
            .from("virtual_runs")
            .select()
            .eq("invitee_id", value: userId.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value

        logSuccess("Fetched \(runs.count) pending invites")
        return runs
    }

    /// Fetch the currently active virtual run for a user (if any)
    func fetchActiveRun(for userId: UUID) async throws -> VirtualRun? {
        logInfo("Fetching active run for \(userId)")

        let runs: [VirtualRun] = try await client
            .from("virtual_runs")
            .select()
            .eq("status", value: "active")
            .or("inviter_id.eq.\(userId.uuidString),invitee_id.eq.\(userId.uuidString)")
            .limit(1)
            .execute()
            .value

        if let run = runs.first {
            logSuccess("Found active run: \(run.id)")
        } else {
            logInfo("No active run found")
        }

        return runs.first
    }

    /// Fetch a specific virtual run by ID
    func fetchRun(byId runId: UUID) async throws -> VirtualRun? {
        let runs: [VirtualRun] = try await client
            .from("virtual_runs")
            .select()
            .eq("id", value: runId.uuidString)
            .limit(1)
            .execute()
            .value

        return runs.first
    }

    // MARK: - Run Lifecycle

    #if DEBUG
    /// End a virtual run and record the summary (debug only — production uses completeRun RPC)
    func endRun(_ runId: UUID, summary: RunSummary) async throws {
        logInfo("Ending virtual run: \(runId)")

        struct EndUpdate: Encodable {
            let status: String
            let ended_at: String
            let inviter_distance_m: Double
            let inviter_duration_s: Int
            let inviter_avg_pace_sec_per_km: Int?
            let inviter_avg_heart_rate: Int?
            let invitee_distance_m: Double
            let invitee_duration_s: Int
            let invitee_avg_pace_sec_per_km: Int?
            let invitee_avg_heart_rate: Int?
            let winner_id: String?
        }

        let data = EndUpdate(
            status: "completed",
            ended_at: ISO8601DateFormatter().string(from: Date()),
            inviter_distance_m: summary.inviterDistanceM,
            inviter_duration_s: summary.inviterDurationS,
            inviter_avg_pace_sec_per_km: summary.inviterAvgPaceSecPerKm,
            inviter_avg_heart_rate: summary.inviterAvgHeartRate,
            invitee_distance_m: summary.inviteeDistanceM,
            invitee_duration_s: summary.inviteeDurationS,
            invitee_avg_pace_sec_per_km: summary.inviteeAvgPaceSecPerKm,
            invitee_avg_heart_rate: summary.inviteeAvgHeartRate,
            winner_id: summary.winnerId?.uuidString
        )

        try await client
            .from("virtual_runs")
            .update(data)
            .eq("id", value: runId.uuidString)
            .execute()

        logSuccess("Ended virtual run: \(runId)")
    }
    #endif

    /// Fetch completed virtual runs for history
    func fetchCompletedRuns(for userId: UUID, limit: Int = 20) async throws -> [VirtualRun] {
        logInfo("Fetching completed runs for \(userId)")

        let runs: [VirtualRun] = try await client
            .from("virtual_runs")
            .select()
            .eq("status", value: "completed")
            .or("inviter_id.eq.\(userId.uuidString),invitee_id.eq.\(userId.uuidString)")
            .order("ended_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        logSuccess("Fetched \(runs.count) completed runs")
        return runs
    }

    // MARK: - Live Sync

    /// Publish a snapshot via Broadcast (~50ms latency).
    /// Also persists to DB at most every 30s — no timer needed, piggybacks on the
    /// existing 2s publish cadence. The DB write feeds the partner's CDC channel
    /// during brief disconnects and the Gap-5 reconnection catch-up path.
    func publishSnapshot(_ snapshot: VirtualRunSnapshot) async throws {
        var snapshotToSend = snapshot
        snapshotToSend.serverReceivedAt = Date()
        snapshotToSend.latitude = nil    // Strip location — not needed for partner sync
        snapshotToSend.longitude = nil   // Route is recorded locally via HealthKit

        // Primary: Broadcast for low-latency live sync (~50ms)
        if let channel = broadcastChannel {
            let compactDict = snapshotToSend.toCompactDict()
            let jsonObject = Self.toJSONObject(compactDict)
            await channel.broadcast(event: "snapshot", message: jsonObject)
        } else {
            logWarning("publishSnapshot: broadcastChannel is nil — seq \(snapshot.seq) not broadcast to partner")
        }

        // Secondary: DB upsert at most every 30s for CDC fallback + crash recovery.
        // No Timer object — fires only when we're already publishing a snapshot.
        if Date().timeIntervalSince(lastDBPersistDate) >= 30 {
            lastDBPersistDate = Date()
            Task {
                do {
                    try await client
                        .from("virtual_run_snapshots")
                        .upsert(snapshotToSend, onConflict: "virtual_run_id,user_id")
                        .execute()
                } catch {
                    logError("Failed to persist snapshot to DB: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Convert [String: Any] to JSONObject ([String: AnyJSON]) for Supabase broadcast
    nonisolated private static func toJSONObject(_ dict: [String: Any]) -> [String: AnyJSON] {
        var result: [String: AnyJSON] = [:]
        for (key, value) in dict {
            switch value {
            case let v as String: result[key] = .string(v)
            case let v as Int: result[key] = .integer(v)
            case let v as Double: result[key] = .double(v)
            case let v as Bool: result[key] = .bool(v)
            default: break
            }
        }
        return result
    }

    /// Convert JSONObject ([String: AnyJSON]) to [String: Any] for compact dict decoding
    nonisolated private static func fromJSONObject(_ jsonObj: [String: AnyJSON]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in jsonObj {
            switch value {
            case .string(let v): result[key] = v
            case .integer(let v): result[key] = v
            case .double(let v): result[key] = v
            case .bool(let v): result[key] = v
            default: break
            }
        }
        return result
    }

    /// Subscribe to snapshot updates via Broadcast (primary) with CDC fallback.
    /// CDC fires when the partner writes their periodic DB persist, covering brief
    /// disconnects and app relaunch catch-up via fetchLatestSnapshot.
    ///
    /// - Parameters:
    ///   - onReady: Optional — inviter passes this to detect the invitee's "ready" signal
    ///              (published via publishReadySignal after accepting). Replaces Supabase CDC
    ///              for the critical "acceptance detected" event.
    ///   - onUpdate: Called for every partner snapshot received on the broadcast channel.
    func subscribeToSnapshots(
        runId: UUID,
        onReady: (() -> Void)? = nil,
        onUpdate: @escaping (VirtualRunSnapshot) -> Void
    ) async -> String {
        let channelId = "virtual_run_\(runId.uuidString)"
        logInfo("Subscribing to snapshots for run: \(runId)")

        // Unsubscribe if already listening
        if let existing = realtimeChannel {
            await existing.unsubscribe()
            realtimeChannel = nil
            observationToken = nil
        }
        if let existing = broadcastChannel {
            await existing.unsubscribe()
            broadcastChannel = nil
            broadcastObservationToken = nil
        }
        readyObservationToken = nil
        lastDBPersistDate = .distantPast

        // --- Broadcast channel (primary, ~50ms) ---
        let bChannel = await client.channel("\(channelId)_broadcast")

        // "ready" signal: invitee publishes this immediately after accepting.
        // Inviter listens here so it detects acceptance via fast Broadcast (~50ms)
        // instead of waiting for Supabase CDC (unreliable, 0-30s).
        if let onReady {
            readyObservationToken = await bChannel.onBroadcast(event: "ready") { _ in
                onReady()
            }
        }

        let bToken = await bChannel.onBroadcast(event: "snapshot") { jsonMessage in
            // jsonMessage is JSONObject ([String: AnyJSON]) — convert to [String: Any] for compact dict
            let dict = Self.fromJSONObject(jsonMessage)
            if let snapshot = VirtualRunSnapshot.fromCompactDict(dict) {
                onUpdate(snapshot)
            }
        }

        broadcastObservationToken = bToken
        await bChannel.subscribe()
        broadcastChannel = bChannel

        // --- CDC channel (fallback: fires on partner's periodic DB writes) ---
        let cdcChannel = await client.channel("\(channelId)_cdc")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let cdcToken = await cdcChannel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "virtual_run_snapshots",
            filter: "virtual_run_id=eq.\(runId.uuidString)",
            callback: { action in
                switch action {
                case .insert(let insertAction):
                    if let snapshot = try? insertAction.decodeRecord(
                        as: VirtualRunSnapshot.self,
                        decoder: decoder
                    ) {
                        onUpdate(snapshot)
                    }
                case .update(let updateAction):
                    if let snapshot = try? updateAction.decodeRecord(
                        as: VirtualRunSnapshot.self,
                        decoder: decoder
                    ) {
                        onUpdate(snapshot)
                    }
                default:
                    break
                }
            }
        )

        observationToken = cdcToken
        await cdcChannel.subscribe()
        realtimeChannel = cdcChannel

        logSuccess("Subscribed to snapshots (broadcast + CDC): \(channelId)")
        return channelId
    }

    /// Fetch latest snapshot from DB (for reconnection catch-up)
    func fetchLatestSnapshot(runId: UUID, partnerUserId: UUID) async throws -> VirtualRunSnapshot? {
        let snapshots: [VirtualRunSnapshot] = try await client
            .from("virtual_run_snapshots")
            .select()
            .eq("virtual_run_id", value: runId.uuidString)
            .eq("user_id", value: partnerUserId.uuidString)
            .limit(1)
            .execute()
            .value

        return snapshots.first
    }

    /// Unsubscribe from snapshot updates
    func unsubscribeFromSnapshots() async {
        if let channel = broadcastChannel {
            logInfo("Unsubscribing from broadcast channel")
            await channel.unsubscribe()
            broadcastChannel = nil
            broadcastObservationToken = nil
            readyObservationToken = nil
        }
        if let channel = realtimeChannel {
            logInfo("Unsubscribing from CDC channel")
            await channel.unsubscribe()
            realtimeChannel = nil
            observationToken = nil
        }
        lastDBPersistDate = .distantPast
    }

    /// Publish a "ready" signal on the broadcast channel.
    /// Invitee calls this immediately after accepting so the inviter detects acceptance
    /// via fast Broadcast (~50ms) rather than Supabase CDC (unreliable, 0-30s delay).
    /// Requires subscribeToSnapshots to have been called first to establish broadcastChannel.
    func publishReadySignal(runId: UUID) async {
        guard let channel = broadcastChannel else {
            logWarning("publishReadySignal: broadcastChannel is nil — inviter may not detect acceptance immediately")
            return
        }
        await channel.broadcast(event: "ready", message: ["v": AnyJSON.integer(1)])
        logSuccess("Published ready signal for run: \(runId)")
    }

    // MARK: - Server-Side Run Completion

    /// Complete a virtual run via server-side RPC (determines winner server-side)
    func completeRun(
        runId: UUID,
        userId: UUID,
        distanceM: Double,
        durationS: Int,
        avgPaceSecPerKm: Int?,
        avgHeartRate: Int?
    ) async throws {
        logInfo("Completing virtual run via RPC: \(runId)")

        let params = CompleteVirtualRunParams(
            p_run_id: runId.uuidString,
            p_user_id: userId.uuidString,
            p_distance_m: distanceM,
            p_duration_s: durationS,
            p_avg_pace_sec_per_km: avgPaceSecPerKm,
            p_avg_heart_rate: avgHeartRate
        )

        try await client.rpc("complete_virtual_run", params: params).execute()

        logSuccess("Completed virtual run via RPC: \(runId)")
    }

    // MARK: - Virtual Run Realtime (Invite Detection)

    private var inviteChannel: RealtimeChannelV2?
    private var inviteObservationToken: Any?

    /// Subscribe to virtual_runs changes relevant to this user (invites + status changes)
    func subscribeToVirtualRunChanges(
        userId: UUID,
        onInviteReceived: @escaping (VirtualRun) -> Void,
        onRunStatusChanged: @escaping (VirtualRun) -> Void
    ) async -> String {
        let channelId = "virtual_runs_\(userId.uuidString)"
        logInfo("Subscribing to virtual_runs changes for user: \(userId)")

        // Unsubscribe existing
        if let existing = inviteChannel {
            await existing.unsubscribe()
            inviteChannel = nil
            inviteObservationToken = nil
        }

        let channel = await client.channel(channelId)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Listen for changes where user is invitee (new invites)
        let token1 = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "virtual_runs",
            filter: "invitee_id=eq.\(userId.uuidString)",
            callback: { action in
                switch action {
                case .insert(let a):
                    if let run = try? a.decodeRecord(as: VirtualRun.self, decoder: decoder),
                       run.status == .pending {
                        onInviteReceived(run)
                    }
                case .update(let a):
                    if let run = try? a.decodeRecord(as: VirtualRun.self, decoder: decoder) {
                        onRunStatusChanged(run)
                    }
                default: break
                }
            }
        )

        // Also listen for changes where user is inviter (to detect acceptance)
        let token2 = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "virtual_runs",
            filter: "inviter_id=eq.\(userId.uuidString)",
            callback: { action in
                if case .update(let a) = action,
                   let run = try? a.decodeRecord(as: VirtualRun.self, decoder: decoder) {
                    onRunStatusChanged(run)
                }
            }
        )

        inviteObservationToken = (token1, token2)  // Keep both alive
        await channel.subscribe()
        inviteChannel = channel

        logSuccess("Subscribed to virtual_runs channel: \(channelId)")
        return channelId
    }

    /// Unsubscribe from virtual run changes
    func unsubscribeFromVirtualRunChanges() async {
        if let channel = inviteChannel {
            logInfo("Unsubscribing from virtual_runs channel")
            await channel.unsubscribe()
            inviteChannel = nil
            inviteObservationToken = nil
        }
    }

    // MARK: - Route Upload/Download

    private static let routeBucketName = "virtual-run-routes"

    /// Upload route JSON to Supabase Storage and set the route_uploaded flag
    func uploadRoute(runId: UUID, userId: UUID, routeData: VirtualRunRouteData) async throws {
        logInfo("Uploading route for run \(runId), user \(userId)")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(routeData)

        // Use lowercased UUIDs — Supabase RLS compares against auth.uid()::text which is lowercase
        let filePath = "\(runId.uuidString.lowercased())/\(userId.uuidString.lowercased()).json"

        try await client.storage
            .from(Self.routeBucketName)
            .upload(
                path: filePath,
                file: jsonData,
                options: FileOptions(contentType: "application/json", upsert: true)
            )

        // Determine which flag to set based on user role
        let run = try await fetchRun(byId: runId)
        let isInviter = run?.inviterId == userId

        struct RouteFlag: Encodable {
            let inviter_route_uploaded: Bool?
            let invitee_route_uploaded: Bool?
        }

        let flag = RouteFlag(
            inviter_route_uploaded: isInviter ? true : nil,
            invitee_route_uploaded: isInviter ? nil : true
        )

        try await client
            .from("virtual_runs")
            .update(flag)
            .eq("id", value: runId.uuidString)
            .execute()

        logSuccess("Uploaded route for run \(runId)")
    }

    /// Download a user's route JSON from Supabase Storage
    /// Throws on network/decode errors. Returns nil only if this is expected to be retried by caller.
    func downloadRoute(runId: UUID, userId: UUID) async throws -> VirtualRunRouteData? {
        logInfo("Downloading route for run \(runId), user \(userId)")

        // Use lowercased UUIDs to match upload path and Supabase RLS
        let filePath = "\(runId.uuidString.lowercased())/\(userId.uuidString.lowercased()).json"

        let data = try await client.storage
            .from(Self.routeBucketName)
            .download(path: filePath)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let routeData = try decoder.decode(VirtualRunRouteData.self, from: data)

        logSuccess("Downloaded route for run \(runId), user \(userId): \(routeData.points.count) points")
        return routeData
    }

    /// Check whether both runners have uploaded their routes
    func checkRoutesReady(runId: UUID) async throws -> (inviterReady: Bool, inviteeReady: Bool) {
        let run = try await fetchRun(byId: runId)
        return (
            inviterReady: run?.inviterRouteUploaded == true,
            inviteeReady: run?.inviteeRouteUploaded == true
        )
    }

    // MARK: - Push Notifications

    /// Send a push notification to the invitee about a new virtual run invite
    private func sendInvitePush(to inviteeId: UUID, from inviterId: UUID, runId: UUID) async {
        // Fetch inviter display name
        let name: String
        if let profile = try? await SupabaseAuthService.shared.fetchProfile(userId: inviterId) {
            name = profile.displayName ?? profile.username
        } else {
            name = "Someone"
        }

        struct PushPayload: Encodable {
            let user_id: String
            let title: String
            let body: String
            let data: [String: String]
            let sound: String
        }

        let payload = PushPayload(
            user_id: inviteeId.uuidString,
            title: "Virtual Run Invite",
            body: "\(name) wants to run with you!",
            data: [
                "type": "virtual_run_invite",
                "run_id": runId.uuidString,
                "actor_id": inviterId.uuidString
            ],
            sound: "default"
        )

        do {
            try await client.functions.invoke("send-push", options: .init(body: payload))
            logSuccess("Sent invite push to \(inviteeId)")
        } catch {
            logError("Failed to send invite push: \(error.localizedDescription)")
        }
    }
}
