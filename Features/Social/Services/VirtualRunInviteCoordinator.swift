//
//  VirtualRunInviteCoordinator.swift
//  WRKT
//
//  Manages Realtime subscription for pending virtual run invites and
//  coordinating the accept/decline flow with Watch and Supabase.
//
//  Reliability architecture:
//  - Invite delivery:  Supabase Realtime CDC (primary) + 30s fallback poll
//  - Acceptance detection: Broadcast "ready" signal (primary, ~50ms) + Realtime CDC + 30s poll
//
//  How the "ready" signal works:
//  1. Inviter sends invite → immediately subscribes to the broadcast channel (trackSentInvite)
//  2. Invitee accepts REST API → subscribes to broadcast channel → publishes "ready" event
//  3. Inviter receives "ready" on the already-open channel → enterActiveRun() immediately
//
//  This removes the dependency on Supabase CDC for the critical "both phones enter the run"
//  coordination step, eliminating the 0-30s startup gap where the invitee's snapshots
//  were silently dropped because the inviter hadn't subscribed yet.
//

import Foundation
import Combine

@MainActor
@Observable
final class VirtualRunInviteCoordinator {
    static let shared = VirtualRunInviteCoordinator()

    // Invitee state (incoming invites)
    private(set) var pendingInvite: VirtualRun?
    private(set) var inviterProfile: UserProfile?
    private(set) var isAccepting = false

    // Inviter state (sent invite waiting for acceptance)
    private(set) var sentInviteId: UUID?
    private(set) var sentInvitePartnerId: UUID?
    private(set) var sentInvitePartnerName: String?
    private(set) var isWaitingForAcceptance = false

    // Active run state
    private(set) var isInActiveRun = false
    private(set) var activeRunId: UUID?
    private var didSendPartnerFinished = false
    private(set) var activeRunPartnerName: String?

    // Live snapshots for the active run card
    private(set) var myRunSnapshot: VirtualRunSnapshot?
    private(set) var partnerRunSnapshot: VirtualRunSnapshot?

    // Flow phase — drives VirtualRunFlowStatusCard
    private(set) var flowPhase: VirtualRunFlowPhase = .idle
    private(set) var retryAction: (@MainActor @Sendable () async -> Void)?

    private var fallbackTimer: Timer?
    private var snapshotPollTimer: Timer?
    private var lastPartnerSnapshotTime: Date = .distantPast
    private var isPolling = false
    private var isListening = false

    // Audio cue tracking
    private var lastAnnouncedKm = 0
    private var lastAnnouncedLeader: String? = nil   // "me" | "partner"
    private var lastLeadChangeTime: Date = .distantPast

    private init() {}

    // MARK: - Flow Phase Control

    /// Set phase to sendingInvite when a REST invite call begins.
    func beginSendingInvite() {
        flowPhase = .sendingInvite
        retryAction = nil
    }

    /// Set failed state with optional retry closure.
    func setFailed(_ error: VirtualRunFlowError, retry: (@MainActor @Sendable () async -> Void)? = nil) {
        flowPhase = .failed(error)
        retryAction = retry
    }

    /// Dismiss the flow card (X button / Dismiss button).
    func dismissFlowCard() {
        flowPhase = .idle
        retryAction = nil
    }

    /// Called by WatchConnectivityManager when iOS receives vr_watch_confirmed.
    /// Shows "Get ready!" for 2 s then transitions to the live stats card.
    func onWatchConfirmed() {
        flowPhase = .watchReady
        Task {
            try? await Task.sleep(for: .seconds(2))
            if flowPhase == .watchReady {
                flowPhase = .activeRun(partnerName: activeRunPartnerName ?? "Partner")
            }
        }
    }

    /// Cancel a pending sent invite (REST + state reset). Best-effort.
    func cancelSentInvite() async {
        guard let inviteId = sentInviteId else { flowPhase = .idle; return }
        do {
            // There is no separate cancel endpoint — declineInvite cancels the pending invite row.
            try await AppDependencies.shared.virtualRunRepository.declineInvite(inviteId)
        } catch { /* best-effort */ }
        sentInviteId = nil
        sentInvitePartnerName = nil
        sentInvitePartnerId = nil
        isWaitingForAcceptance = false
        flowPhase = .idle
    }

    // MARK: - DB Catch-Up Poll (backup when Supabase WebSocket is dead)

    /// Starts a 10-second DB poll that fetches the latest partner snapshot and forwards
    /// it to the Watch. Only fires when no broadcast update has arrived in 8+ seconds,
    /// so it doesn't run at all when the WebSocket is healthy.
    private func startSnapshotPoll(runId: UUID, partnerId: UUID) {
        stopSnapshotPoll()
        let capturedRunId = runId
        let capturedPartnerId = partnerId
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isInActiveRun else { return }
                // Only hit DB when broadcast has been silent for 5+ seconds.
                // DB is now written every 3s (down from 10s), so the DB is always fresh.
                // 5s silence threshold + 5s poll interval = at most 10s latency when broadcast is dead.
                guard Date().timeIntervalSince(self.lastPartnerSnapshotTime) > 5.0 else { return }
                guard let snapshot = try? await AppDependencies.shared.virtualRunRepository
                    .fetchLatestSnapshot(runId: capturedRunId, partnerUserId: capturedPartnerId)
                else { return }
                AppLogger.info("[VR] Catch-up: forwarding DB snapshot seq=\(snapshot.seq) to Watch", category: AppLogger.virtualRun)
                WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                self.updatePartnerSnapshot(snapshot)
            }
        }
        timer.tolerance = 2.0
        RunLoop.main.add(timer, forMode: .common)
        snapshotPollTimer = timer
    }

    private func stopSnapshotPoll() {
        snapshotPollTimer?.invalidate()
        snapshotPollTimer = nil
    }

    /// Called by WatchConnectivityManager with each snapshot the Watch sends.
    /// Exposes the user's own live stats to the active run card.
    func updateMySnapshot(_ snapshot: VirtualRunSnapshot) {
        guard isInActiveRun else { return }
        myRunSnapshot = snapshot

        let currentKm = Int(snapshot.distanceM / 1000)
        if currentKm > lastAnnouncedKm {
            lastAnnouncedKm = currentKm
            iPhoneVirtualRunAudioCues.shared.announceKilometer(currentKm)
        }

        checkLeadChangeAndAnnounce()
    }

    /// Called when a partner snapshot arrives via the Supabase broadcast channel or DB catch-up.
    /// Exposes partner live stats to the active run card.
    func updatePartnerSnapshot(_ snapshot: VirtualRunSnapshot) {
        guard isInActiveRun else { return }
        partnerRunSnapshot = snapshot
        lastPartnerSnapshotTime = Date()
        checkLeadChangeAndAnnounce()
    }

    // MARK: - Realtime + Fallback Poll

    /// Start listening for invites via Realtime with a 30s fallback poll.
    /// Also re-subscribes to the broadcast channel if waiting for acceptance
    /// (the channel is killed when iOS suspends WebSockets on background).
    func startListening() {
        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }

        // During an active run, always re-subscribe the broadcast channel when called.
        // Background execution modes keep the app alive but the Supabase Realtime WebSocket
        // can drop and reconnect — after reconnect, the channel enters "subscribing" state
        // and broadcast() silently drops messages until the channel re-joins. Force a fresh
        // subscription here so the channel is definitely in "subscribed" state on foreground.
        // subscribeToSnapshots() handles its own cleanup before re-subscribing, so calling
        // this even when isListening=true (background mode: stopListening was skipped) is safe.
        if isInActiveRun, let runId = activeRunId {
            let myId = userId
            Task {
                let repo = AppDependencies.shared.virtualRunRepository
                let _ = await repo.subscribeToSnapshots(runId: runId, onUpdate: { snapshot in
                    guard snapshot.userId != myId else { return }
                    Task { @MainActor in
                        WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                        VirtualRunInviteCoordinator.shared.updatePartnerSnapshot(snapshot)
                    }
                })
                AppLogger.info("[VR] Re-subscribed to live partner data on foreground (runId: \(runId))", category: AppLogger.app)
            }
        }

        guard !isListening else { return }
        isListening = true

        let repo = AppDependencies.shared.virtualRunRepository

        // Subscribe to Realtime CDC changes on virtual_runs
        Task {
            let _ = await repo.subscribeToVirtualRunChanges(
                userId: userId,
                onInviteReceived: { [weak self] run in
                    Task { @MainActor [weak self] in
                        self?.handleInviteReceived(run)
                    }
                },
                onRunStatusChanged: { [weak self] run in
                    Task { @MainActor [weak self] in
                        self?.handleRunStatusChanged(run, userId: userId)
                    }
                }
            )
        }

        // Re-subscribe to broadcast channel if we were waiting for acceptance.
        // iOS terminates WebSockets ~5s after the app suspends, so after a background
        // + foreground cycle the broadcast channel must be re-established.
        if isWaitingForAcceptance,
           let runId = sentInviteId,
           let partnerId = sentInvitePartnerId,
           let partnerName = sentInvitePartnerName {
            subscribeEarlyAsInviter(runId: runId, partnerId: partnerId, partnerName: partnerName, myUserId: userId)
        }

        // Poll immediately to catch anything missed while offline
        pollOnce()

        // 30s fallback poll — safety net for all edge cases.
        // tolerance: 3.0 lets the OS batch this with other 30-second timers.
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollOnce()
            }
        }
        timer.tolerance = 3.0
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    /// Stop listening (Realtime + fallback timer + broadcast channel if waiting).
    func stopListening() {
        isListening = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        Task {
            await AppDependencies.shared.virtualRunRepository.unsubscribeFromVirtualRunChanges()
            // Unsubscribe broadcast channel if waiting for acceptance (not during an active run).
            // Will be re-subscribed when app foregrounds via startListening().
            if !isInActiveRun {
                await AppDependencies.shared.virtualRunRepository.unsubscribeFromSnapshots()
            }
        }
    }

    // MARK: - Realtime Handlers

    private func handleInviteReceived(_ run: VirtualRun) {
        guard !isInActiveRun else { return }
        guard run.id != pendingInvite?.id else { return }

        // Skip expired invites
        if let expiresAt = run.expiresAt, expiresAt < Date() { return }

        pendingInvite = run
        Haptics.success()

        // Fetch inviter profile
        Task {
            inviterProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: run.inviterId)
        }
    }

    private func handleRunStatusChanged(_ run: VirtualRun, userId: UUID) {
        switch run.status {
        case .active:
            // CDC fallback: if the Broadcast "ready" signal was missed, CDC still triggers here.
            // enterActiveRun() is idempotent — if already in the run, it returns immediately.
            if isWaitingForAcceptance, run.id == sentInviteId {
                let partnerId = sentInvitePartnerId ?? run.inviteeId
                let partnerName = sentInvitePartnerName ?? "Partner"
                Task {
                    await enterActiveRun(run: run, partnerId: partnerId, partnerName: partnerName, myUserId: userId)
                }
            }

            // Detect partner finished (their stats saved but status still active)
            if isInActiveRun, run.id == activeRunId, !didSendPartnerFinished {
                let isInviter = (userId == run.inviterId)
                let partnerHasStats = isInviter
                    ? (run.inviteeDurationS != nil)
                    : (run.inviterDurationS != nil)

                if partnerHasStats {
                    didSendPartnerFinished = true
                    iPhoneVirtualRunAudioCues.shared.announcePartnerFinished()
                    let partnerDistance = isInviter ? (run.inviteeDistanceM ?? 0) : (run.inviterDistanceM ?? 0)
                    let partnerDuration = isInviter ? (run.inviteeDurationS ?? 0) : (run.inviterDurationS ?? 0)
                    let partnerPace = isInviter ? run.inviteeAvgPaceSecPerKm : run.inviterAvgPaceSecPerKm
                    WatchConnectivityManager.shared.sendVirtualRunPartnerFinished(
                        partnerDistance: partnerDistance,
                        partnerDuration: partnerDuration,
                        partnerPace: partnerPace
                    )
                }
            }
        case .cancelled, .completed:
            if run.status == .completed, isInActiveRun, run.id == activeRunId {
                // Send partner-finished to Watch if not already sent from .active handler
                if !didSendPartnerFinished {
                    iPhoneVirtualRunAudioCues.shared.announcePartnerFinished()
                    let isInviter = (userId == run.inviterId)
                    let partnerDistance = isInviter ? (run.inviteeDistanceM ?? 0) : (run.inviterDistanceM ?? 0)
                    let partnerDuration = isInviter ? (run.inviteeDurationS ?? 0) : (run.inviterDurationS ?? 0)
                    let partnerPace = isInviter ? run.inviteeAvgPaceSecPerKm : run.inviterAvgPaceSecPerKm
                    WatchConnectivityManager.shared.sendVirtualRunPartnerFinished(
                        partnerDistance: partnerDistance,
                        partnerDuration: partnerDuration,
                        partnerPace: partnerPace
                    )
                }

                // If we were waiting for partner to finish, resolve the summary now
                if VirtualRunSummaryCoordinator.shared.isWaitingForPartner {
                    VirtualRunSummaryCoordinator.shared.resolveWithServerData(run, currentUserId: userId)
                }
            }
            if isWaitingForAcceptance, run.id == sentInviteId {
                isWaitingForAcceptance = false
                sentInviteId = nil
                sentInvitePartnerId = nil
                sentInvitePartnerName = nil
                flowPhase = .idle
            }
            // Clear pending invite if it was cancelled
            if run.id == pendingInvite?.id {
                pendingInvite = nil
                inviterProfile = nil
            }
            // Full cleanup on completion — clears flowPhase, snapshots, timers, etc.
            // runEnded() handles unsubscribeFromSnapshots() and stopSnapshotPoll() internally.
            if run.status == .completed, isInActiveRun, run.id == activeRunId {
                runEnded()
            }
        case .pending:
            break
        }
    }

    /// Clear pending invite if it has expired (called from poll cycle)
    private func clearExpiredPendingInvite() {
        guard let invite = pendingInvite,
              let expiresAt = invite.expiresAt,
              expiresAt < Date() else { return }
        pendingInvite = nil
        inviterProfile = nil
    }

    // MARK: - Fallback Poll

    private func pollOnce() {
        guard !isPolling else { return }
        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }

        // Clear any expired pending invite before polling
        clearExpiredPendingInvite()

        // Skip the network round-trip if neither branch has work to do.
        guard !isInActiveRun || isWaitingForAcceptance else { return }

        isPolling = true
        Task {
            defer { isPolling = false }

            let repo = AppDependencies.shared.virtualRunRepository

            // 1. Check for incoming invites (invitee side)
            if !isInActiveRun {
                do {
                    let invites = try await repo.fetchPendingInvites(for: userId)
                    let validInvite = invites.first(where: { invite in
                        guard let expiresAt = invite.expiresAt else { return true }
                        return expiresAt > Date()
                    })
                    if let invite = validInvite {
                        if invite.id != pendingInvite?.id {
                            pendingInvite = invite
                            inviterProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: invite.inviterId)
                            Haptics.success()
                        }
                    } else if pendingInvite != nil {
                        pendingInvite = nil
                        inviterProfile = nil
                    }
                } catch {
                    // Silently fail — will retry on next poll
                }
            }

            // 2. Check if a sent invite was accepted (inviter side — CDC/Broadcast fallback)
            if isWaitingForAcceptance, let inviteId = sentInviteId {
                do {
                    if let run = try await repo.fetchRun(byId: inviteId) {
                        switch run.status {
                        case .active:
                            let partnerId = sentInvitePartnerId ?? run.inviteeId
                            let partnerName = sentInvitePartnerName ?? "Partner"
                            await enterActiveRun(run: run, partnerId: partnerId, partnerName: partnerName, myUserId: userId)
                        case .cancelled, .completed:
                            isWaitingForAcceptance = false
                            sentInviteId = nil
                            sentInvitePartnerId = nil
                            sentInvitePartnerName = nil
                        case .pending:
                            break
                        }
                    }
                } catch {
                    // Silently fail — will retry on next poll
                }
            }
        }
    }

    // MARK: - Inviter: Track Sent Invites

    /// Called after successfully sending an invite.
    /// Immediately subscribes to the broadcast channel so the inviter is ready to
    /// receive the invitee's "ready" signal and snapshots without any startup gap.
    func trackSentInvite(runId: UUID, partnerId: UUID, partnerName: String) {
        sentInviteId = runId
        sentInvitePartnerId = partnerId
        sentInvitePartnerName = partnerName
        isWaitingForAcceptance = true
        flowPhase = .waitingForPartner(partnerName: partnerName)

        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }
        subscribeEarlyAsInviter(runId: runId, partnerId: partnerId, partnerName: partnerName, myUserId: userId)
    }

    /// Subscribes to the broadcast channel immediately after the invite is sent.
    /// Sets up handlers for both the "ready" signal and live snapshots so there is
    /// zero gap between acceptance and data flowing to the inviter's Watch.
    private func subscribeEarlyAsInviter(runId: UUID, partnerId: UUID, partnerName: String, myUserId: UUID) {
        let myId = myUserId
        let capturedPartnerId = partnerId
        let capturedPartnerName = partnerName

        Task {
            let repo = AppDependencies.shared.virtualRunRepository
            let _ = await repo.subscribeToSnapshots(
                runId: runId,
                onReady: { [weak self] in
                    // Invitee published "ready" — enter the run immediately via Broadcast
                    Task { @MainActor [weak self] in
                        guard let self, self.isWaitingForAcceptance else { return }
                        if let run = try? await AppDependencies.shared.virtualRunRepository.fetchRun(byId: runId) {
                            await self.enterActiveRun(
                                run: run,
                                partnerId: capturedPartnerId,
                                partnerName: capturedPartnerName,
                                myUserId: myId
                            )
                        }
                    }
                },
                onUpdate: { snapshot in
                    // Forward invitee's snapshots to inviter's Watch + update card
                    guard snapshot.userId != myId else { return }
                    Task { @MainActor in
                        WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                        VirtualRunInviteCoordinator.shared.updatePartnerSnapshot(snapshot)
                    }
                }
            )
        }
    }

    // MARK: - Shared: Enter Active Run

    /// Unified entry point for both inviter and invitee to enter an active virtual run.
    /// Idempotent — safe to call from the "ready" signal, Realtime CDC, and 30s poll simultaneously.
    private func enterActiveRun(run: VirtualRun, partnerId: UUID, partnerName: String, myUserId: UUID) async {
        // Idempotency guard — Broadcast "ready", Realtime CDC, and 30s poll may all fire.
        // First caller wins; subsequent calls are no-ops.
        guard !isInActiveRun else { return }

        isWaitingForAcceptance = false
        isInActiveRun = true
        iPhoneVirtualRunAudioCues.shared.startSession()
        LocationManager.shared.startVirtualRunBackgroundSession()
        activeRunId = run.id
        didSendPartnerFinished = false

        let repo = AppDependencies.shared.virtualRunRepository
        let myId = myUserId

        // Subscribe to snapshots only if not already done.
        // Inviter subscribes early in subscribeEarlyAsInviter() so the snapshot
        // handler is already in place. Invitee always subscribes here (in acceptInvite).
        if !repo.isSubscribedToSnapshots {
            let _ = await repo.subscribeToSnapshots(runId: run.id, onUpdate: { snapshot in
                guard snapshot.userId != myId else { return }
                Task { @MainActor in
                    WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                    VirtualRunInviteCoordinator.shared.updatePartnerSnapshot(snapshot)
                }
            })
        }

        // Fetch partner's maxHR and my resting HR for Watch HR zone display
        var partnerMaxHR = 190
        if let partnerProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: partnerId) {
            partnerMaxHR = partnerProfile.maxHR
        }

        let myRestingHR: Int
        if let rhr = try? await HealthKitManager.shared.fetchAverageRestingHeartRate() {
            myRestingHR = Int(rhr)
            HRZoneCalculator.shared.setRestingHR(rhr)
        } else {
            myRestingHR = 0
        }

        // Notify Watch to start the virtual run
        WatchConnectivityManager.shared.sendVirtualRunStarted(
            runId: run.id,
            partnerId: partnerId,
            partnerName: partnerName,
            myUserId: myUserId,
            myRestingHR: myRestingHR,
            partnerMaxHR: partnerMaxHR
        )
        flowPhase = .syncingWithWatch(partnerName: partnerName)

        AppLogger.success("Entered active run (id: \(run.id))", category: AppLogger.app)
        Haptics.success()

        // Save partner name for the active run card before clearing inviter tracking
        activeRunPartnerName = partnerName

        // Start DB catch-up poll — fallback when Supabase WebSocket dies (e.g. iPhone backgrounded)
        lastPartnerSnapshotTime = .distantPast
        startSnapshotPoll(runId: run.id, partnerId: partnerId)

        // Clear inviter tracking
        sentInviteId = nil
        sentInvitePartnerId = nil
        sentInvitePartnerName = nil
    }

    // MARK: - Invitee: Accept / Decline

    func acceptInvite() {
        guard let invite = pendingInvite else { return }
        guard let myUserId = SupabaseAuthService.shared.currentUser?.id else { return }

        isAccepting = true
        flowPhase = .connecting
        Task {
            defer { isAccepting = false }
            do {
                let repo = AppDependencies.shared.virtualRunRepository
                let run = try await repo.acceptInvite(invite.id)

                // Subscribe to snapshots so we receive the inviter's data once their Watch starts
                let myId = myUserId
                let _ = await repo.subscribeToSnapshots(runId: run.id, onUpdate: { snapshot in
                    guard snapshot.userId != myId else { return }
                    Task { @MainActor in
                        WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                        VirtualRunInviteCoordinator.shared.updatePartnerSnapshot(snapshot)
                    }
                })

                // Publish "ready" on the broadcast channel.
                // The inviter is already subscribed (did so when they sent the invite), so
                // they receive this signal in ~50ms and enter the run immediately —
                // no waiting for Supabase CDC or the 30s fallback poll.
                await repo.publishReadySignal(runId: run.id)

                // Enter the run (Watch start, partner profile fetch, etc.)
                let partnerName = inviterProfile?.displayName ?? inviterProfile?.username ?? "Partner"
                await enterActiveRun(
                    run: run,
                    partnerId: invite.inviterId,
                    partnerName: partnerName,
                    myUserId: myUserId
                )

                // Clear the banner
                pendingInvite = nil
                inviterProfile = nil

            } catch {
                AppLogger.error("Failed to accept virtual run invite: \(error.localizedDescription)", category: AppLogger.app)
                setFailed(.acceptFailed, retry: {
                    VirtualRunInviteCoordinator.shared.acceptInvite()
                })
            }
        }
    }

    func declineInvite() {
        guard let invite = pendingInvite else { return }

        Task {
            do {
                let repo = AppDependencies.shared.virtualRunRepository
                try await repo.declineInvite(invite.id)
            } catch {
                AppLogger.error("Failed to decline virtual run invite: \(error.localizedDescription)", category: AppLogger.app)
            }
        }

        // Clear banner immediately
        pendingInvite = nil
        inviterProfile = nil
    }

    // MARK: - Audio Cue Helpers

    private func checkLeadChangeAndAnnounce() {
        guard let mySnap = myRunSnapshot, let partnerSnap = partnerRunSnapshot else { return }
        let myDistance = mySnap.distanceM
        let partnerDistance = partnerSnap.distanceM
        let difference = abs(myDistance - partnerDistance)
        guard difference > VirtualRunConstants.leadChangeThreshold else { return }
        guard Date().timeIntervalSince(lastLeadChangeTime) > VirtualRunConstants.leadChangeDebounce else { return }

        let currentLeader = myDistance > partnerDistance ? "me" : "partner"
        guard currentLeader != lastAnnouncedLeader else { return }
        lastAnnouncedLeader = currentLeader
        lastLeadChangeTime = Date()
        iPhoneVirtualRunAudioCues.shared.announceLeadChange(isLeading: currentLeader == "me")
    }

    // MARK: - Run Ended

    /// Called when the virtual run ends (from any source) to reset all state.
    func runEnded() {
        iPhoneVirtualRunAudioCues.shared.endSession()
        LocationManager.shared.stopVirtualRunBackgroundSession()
        lastAnnouncedKm = 0
        lastAnnouncedLeader = nil
        lastLeadChangeTime = .distantPast
        stopSnapshotPoll()
        isInActiveRun = false
        activeRunId = nil
        didSendPartnerFinished = false
        isWaitingForAcceptance = false
        sentInviteId = nil
        sentInvitePartnerId = nil
        sentInvitePartnerName = nil
        activeRunPartnerName = nil
        myRunSnapshot = nil
        partnerRunSnapshot = nil
        lastPartnerSnapshotTime = .distantPast
        flowPhase = .idle
        retryAction = nil
        // Unsubscribe snapshot channel so no phantom updates arrive for a future run.
        // Snapshot-specific channel only — invite CDC is managed by stopListening().
        Task { await AppDependencies.shared.virtualRunRepository.unsubscribeFromSnapshots() }
    }
}
