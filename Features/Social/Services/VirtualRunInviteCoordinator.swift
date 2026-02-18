//
//  VirtualRunInviteCoordinator.swift
//  WRKT
//
//  Manages Realtime subscription for pending virtual run invites and
//  coordinating the accept/decline flow with Watch and Supabase.
//  Uses Realtime as primary mechanism with a 30s fallback poll as safety net.
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

    /// Start listening for invites via Realtime with a 30s fallback poll
    func startListening() {
        guard !isListening else { return }
        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }
        isListening = true

        let repo = AppDependencies.shared.virtualRunRepository

        // Subscribe to Realtime changes on virtual_runs
        Task {
            let _ = await repo.subscribeToVirtualRunChanges(
                userId: userId,
                onInviteReceived: { [weak self] run in
                    Task { @MainActor in
                        self?.handleInviteReceived(run)
                    }
                },
                onRunStatusChanged: { [weak self] run in
                    Task { @MainActor in
                        self?.handleRunStatusChanged(run, userId: userId)
                    }
                }
            )
        }

        // Poll immediately to catch anything missed while offline
        pollOnce()

        // Start 30s fallback poll as safety net (e.g. after app background/foreground)
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollOnce()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    /// Stop listening (Realtime + fallback timer)
    func stopListening() {
        isListening = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        Task {
            await AppDependencies.shared.virtualRunRepository.unsubscribeFromVirtualRunChanges()
        }
    }

    // MARK: - Realtime Handlers

    private func handleInviteReceived(_ run: VirtualRun) {
        guard !isInActiveRun else { return }
        guard run.id != pendingInvite?.id else { return }

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
            // If we're waiting for acceptance as inviter, start the run
            if isWaitingForAcceptance, run.id == sentInviteId {
                Task {
                    await startRunAsInviter(run: run, userId: userId)
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

    // MARK: - Fallback Poll

    private func pollOnce() {
        guard !isPolling else { return }
        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }

        isPolling = true
        Task {
            defer { isPolling = false }

            let repo = AppDependencies.shared.virtualRunRepository

            // 1. Check for incoming invites (invitee side)
            if !isInActiveRun {
                do {
                    let invites = try await repo.fetchPendingInvites(for: userId)
                    if let invite = invites.first {
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

            // 2. Check if a sent invite was accepted (inviter side)
            if isWaitingForAcceptance, let inviteId = sentInviteId {
                do {
                    if let run = try await repo.fetchRun(byId: inviteId) {
                        switch run.status {
                        case .active:
                            // Invite was accepted — start the run on inviter side
                            await startRunAsInviter(run: run, userId: userId)
                        case .cancelled, .completed:
                            // Invite was declined or already ended — stop waiting
                            isWaitingForAcceptance = false
                            sentInviteId = nil
                            sentInvitePartnerId = nil
                            sentInvitePartnerName = nil
                        case .pending:
                            break // Still waiting
                        }
                    }
                } catch {
                    // Silently fail — will retry on next poll
                }
            }
        }
    }

    // MARK: - Inviter: Track Sent Invites

    /// Called after successfully sending an invite — starts polling for acceptance
    func trackSentInvite(runId: UUID, partnerId: UUID, partnerName: String) {
        sentInviteId = runId
        sentInvitePartnerId = partnerId
        sentInvitePartnerName = partnerName
        isWaitingForAcceptance = true
    }

    private func startRunAsInviter(run: VirtualRun, userId: UUID) async {
        isWaitingForAcceptance = false
        isInActiveRun = true
        activeRunId = run.id
        didSendPartnerFinished = false

        let repo = AppDependencies.shared.virtualRunRepository
        let partnerId = sentInvitePartnerId ?? run.inviteeId
        let partnerName = sentInvitePartnerName ?? "Partner"

        // Subscribe to Realtime snapshots — only forward partner's, not our own
        let myId = userId
        let _ = await repo.subscribeToSnapshots(runId: run.id) { snapshot in
            guard snapshot.userId != myId else { return }
            Task { @MainActor in
                WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
            }
        }

        // Fetch partner profile for maxHR
        var partnerMaxHR = 190
        if let partnerProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: partnerId) {
            partnerMaxHR = partnerProfile.maxHR
        }

        // Notify Watch to start the virtual run
        WatchConnectivityManager.shared.sendVirtualRunStarted(
            runId: run.id,
            partnerId: partnerId,
            partnerName: partnerName,
            myUserId: userId,
            partnerMaxHR: partnerMaxHR
        )

        AppLogger.success("Inviter run started — notified Watch", category: AppLogger.app)
        Haptics.success()

        // Clear sent invite tracking
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

                isInActiveRun = true
                activeRunId = run.id
                didSendPartnerFinished = false

                // Subscribe to Realtime snapshots — only forward partner's, not our own
                let _ = await repo.subscribeToSnapshots(runId: run.id) { snapshot in
                    guard snapshot.userId != myUserId else { return }
                    Task { @MainActor in
                        WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)
                    }
                }

                // Fetch inviter's profile for maxHR
                var partnerMaxHR = 190
                if let partnerProfile = try? await SupabaseAuthService.shared.fetchProfile(userId: invite.inviterId) {
                    partnerMaxHR = partnerProfile.maxHR
                }

                // Notify Watch to start the virtual run
                WatchConnectivityManager.shared.sendVirtualRunStarted(
                    runId: run.id,
                    partnerId: invite.inviterId,
                    partnerName: inviterProfile?.displayName ?? inviterProfile?.username ?? "Partner",
                    myUserId: myUserId,
                    partnerMaxHR: partnerMaxHR
                )

                // Clear the banner
                pendingInvite = nil
                inviterProfile = nil

                AppLogger.success("Invitee accepted — notified Watch", category: AppLogger.app)
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
