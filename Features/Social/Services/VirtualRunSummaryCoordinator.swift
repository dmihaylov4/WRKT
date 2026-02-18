//
//  VirtualRunSummaryCoordinator.swift
//  WRKT
//
//  Holds pending virtual run summary data for display after a run ends.
//  Supports deferred summary: waits for partner to finish before showing final stats.
//

import Foundation

@MainActor @Observable
final class VirtualRunSummaryCoordinator {
    static let shared = VirtualRunSummaryCoordinator()

    private(set) var pendingSummary: VirtualRunCompletionData?
    private(set) var isWaitingForPartner = false

    // Stored while waiting for partner
    private var waitingRunId: UUID?
    private var waitingUserId: UUID?
    private var waitingPartnerName: String?
    private var waitingMyStats: (distance: Double, duration: Int, pace: Int?, hr: Int?)?
    private var waitTimeout: Task<Void, Never>?

    /// Show summary immediately (e.g. both finished at the same time)
    func show(_ data: VirtualRunCompletionData) {
        isWaitingForPartner = false
        waitTimeout?.cancel()
        pendingSummary = data
        clearWaiting()
    }

    /// Called when local user ends first — wait for partner to finish
    func awaitPartner(runId: UUID, currentUserId: UUID, partnerName: String, myDistance: Double, myDuration: Int, myPace: Int?, myHR: Int?) {
        waitingRunId = runId
        waitingUserId = currentUserId
        waitingPartnerName = partnerName
        waitingMyStats = (myDistance, myDuration, myPace, myHR)
        isWaitingForPartner = true

        // Poll DB periodically as safety net (in case Realtime update is missed)
        waitTimeout = Task { @MainActor [weak self] in
            let repo = AppDependencies.shared.virtualRunRepository

            // Poll every 5s for up to 5 minutes
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.isWaitingForPartner else { return }

                // Check if run is now completed with both stats
                if let run = try? await repo.fetchRun(byId: runId),
                   run.status == .completed {
                    self.resolveWithServerData(run, currentUserId: currentUserId)
                    return
                }
            }

            // Timeout — show summary with last known data
            guard let self, !Task.isCancelled, self.isWaitingForPartner else { return }
            self.resolveWithLastKnown()
        }
    }

    /// Called when Realtime reports the run is fully completed (both stats present)
    func resolveWithServerData(_ run: VirtualRun, currentUserId: UUID) {
        guard isWaitingForPartner, run.id == waitingRunId else { return }
        guard let my = waitingMyStats else { return }

        let isInviter = (currentUserId == run.inviterId)
        let partnerDistance = isInviter ? (run.inviteeDistanceM ?? 0) : (run.inviterDistanceM ?? 0)
        let partnerDuration = isInviter ? (run.inviteeDurationS ?? 0) : (run.inviterDurationS ?? 0)
        let partnerPace = isInviter ? run.inviteeAvgPaceSecPerKm : run.inviterAvgPaceSecPerKm
        let partnerHR = isInviter ? run.inviteeAvgHeartRate : run.inviterAvgHeartRate

        let completionData = VirtualRunCompletionData(
            runId: run.id,
            partnerName: waitingPartnerName ?? "Partner",
            myDistanceM: my.distance,
            myDurationS: my.duration,
            myPaceSecPerKm: my.pace,
            myAvgHR: my.hr,
            partnerDistanceM: partnerDistance,
            partnerDurationS: partnerDuration,
            partnerPaceSecPerKm: partnerPace,
            partnerAvgHR: partnerHR
        )
        show(completionData)
    }

    func dismiss() {
        pendingSummary = nil
        isWaitingForPartner = false
        clearWaiting()
    }

    private func resolveWithLastKnown() {
        guard let my = waitingMyStats else {
            isWaitingForPartner = false
            return
        }

        // Show summary with our stats only — partner data unavailable after timeout
        let completionData = VirtualRunCompletionData(
            runId: waitingRunId ?? UUID(),
            partnerName: waitingPartnerName ?? "Partner",
            myDistanceM: my.distance,
            myDurationS: my.duration,
            myPaceSecPerKm: my.pace,
            myAvgHR: my.hr,
            partnerDistanceM: 0,
            partnerDurationS: 0,
            partnerPaceSecPerKm: nil,
            partnerAvgHR: nil
        )
        show(completionData)
    }

    private func clearWaiting() {
        waitTimeout?.cancel()
        waitingRunId = nil
        waitingUserId = nil
        waitingPartnerName = nil
        waitingMyStats = nil
    }
}
