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

    private var fallbackTimer: Timer?
    private var isPolling = false
    private var isListening = false

    private init() {}

    // MARK: - Realtime + Fallback Poll

    /// Start listening for invites via Realtime with a 30s fallback poll.
    /// Also re-subscribes to the broadcast channel if waiting for acceptance
    /// (the channel is killed when iOS suspends WebSockets on background).
    func startListening() {
        guard !isListening else { return }
        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }
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
        } else if isInActiveRun, let runId = activeRunId {
            // Re-subscribe live partner snapshot channel for an active run.
            // The snapshot channel is NOT unsubscribed on background (stopListening keeps it),
            // but the underlying WebSocket is killed ~5s after suspend. Force-resubscribe to
            // get a fresh connection with the same onUpdate handler.
            let myId = userId
            Task {
                let repo = AppDependencies.shared.virtualRunRepository
                let _ = await repo.subscribeToSnapshots(runId: runId, onUpdate: { snapshot in
                    guard snapshot.userId != myId else { return }
                    Task { @MainActor in
                        WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                    }
                })
                AppLogger.info("[VR] Re-subscribed to live partner data after app foreground (runId: \(runId))", category: AppLogger.app)
            }
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
            }
            // Clear pending invite if it was cancelled
            if run.id == pendingInvite?.id {
                pendingInvite = nil
                inviterProfile = nil
            }
            // Reset active run state on completion
            if run.status == .completed, isInActiveRun, run.id == activeRunId {
                isInActiveRun = false
                activeRunId = nil
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
                    // Forward invitee's snapshots to inviter's Watch
                    guard snapshot.userId != myId else { return }
                    Task { @MainActor in
                        WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
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
                }
            })
        }

        // Fetch partner's maxHR for Watch HR zone display
        var partnerMaxHR = 190
        if let partnerProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: partnerId) {
            partnerMaxHR = partnerProfile.maxHR
        }

        // Notify Watch to start the virtual run
        WatchConnectivityManager.shared.sendVirtualRunStarted(
            runId: run.id,
            partnerId: partnerId,
            partnerName: partnerName,
            myUserId: myUserId,
            partnerMaxHR: partnerMaxHR
        )

        AppLogger.success("Entered active run (id: \(run.id))", category: AppLogger.app)
        Haptics.success()

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

    // MARK: - Run Ended

    /// Called when the virtual run ends (from any source) to reset state
    func runEnded() {
        isInActiveRun = false
        activeRunId = nil
        didSendPartnerFinished = false
        isWaitingForAcceptance = false
        sentInviteId = nil
        sentInvitePartnerId = nil
        sentInvitePartnerName = nil
    }
}
