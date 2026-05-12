//
//  ProgramLibraryViewModel.swift
//  WRKT
//
//  State holder for program library data and pending invite actions.
//

import Foundation
import Observation

@Observable
@MainActor
final class ProgramLibraryViewModel {
    struct PendingInviteDisplay: Identifiable, Sendable {
        let id: UUID
        let programId: UUID
        let senderId: UUID
        let senderUsername: String?
        let senderDisplayName: String?
        let programName: String
        let createdAt: Date
    }

    private(set) var library: [WorkoutSplit] = []
    private(set) var activeSplit: WorkoutSplit?
    private(set) var pendingInvites: [PendingInviteDisplay] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let repo: ProgramSharingRepositoryInterface
    private let plannerStore: PlannerStoreInterface
    private let currentUserID: UUID
    private let realtime: RealtimeService?
    private let profileRepo: ProfileRepositoryProtocol?
    private var channelId: String?

    init(
        repo: ProgramSharingRepositoryInterface,
        plannerStore: PlannerStoreInterface,
        currentUserID: UUID,
        realtime: RealtimeService? = nil,
        profileRepo: ProfileRepositoryProtocol? = nil
    ) {
        self.repo = repo
        self.plannerStore = plannerStore
        self.currentUserID = currentUserID
        self.realtime = realtime
        self.profileRepo = profileRepo
    }

    func refreshLibrary() {
        do {
            library = try plannerStore.splitLibrary()
            activeSplit = library.first(where: { $0.isActive })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPendingInvites() async {
        guard let profileRepo else { return }

        do {
            let rows = try await repo.fetchPendingInvites(for: currentUserID)
            var displays: [PendingInviteDisplay] = []
            for row in rows {
                let profile = try? await profileRepo.fetchProfile(userId: row.senderUserId)
                guard let program = try? await repo.fetchProgram(id: row.programId) else {
                    continue
                }
                displays.append(
                    PendingInviteDisplay(
                        id: row.id,
                        programId: row.programId,
                        senderId: row.senderUserId,
                        senderUsername: profile?.username,
                        senderDisplayName: profile?.displayName,
                        programName: program.name,
                        createdAt: row.createdAt
                    )
                )
            }
            pendingInvites = displays
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRealtime() async {
        guard let realtime else { return }

        do {
            channelId = try await realtime.subscribeToProgramInvites(
                userId: currentUserID,
                onInsert: { [weak self] _ in
                    Task { await self?.refreshPendingInvites() }
                },
                onUpdate: { [weak self] _ in
                    Task { await self?.refreshPendingInvites() }
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptInvite(
        inviteId: UUID,
        senderUsername: String?,
        senderDisplayName: String?
    ) async throws {
        let acceptedInvite = try await repo.accept(inviteId: inviteId)
        let program = try await repo.fetchProgram(id: acceptedInvite.programId)

        let split = ProgramSerializer.fromStructure(
            program.structure,
            name: program.name,
            reschedulePolicy: ReschedulePolicy(rawValue: program.reschedulePolicy) ?? .strict,
            creator: .init(
                userID: program.structure.creator?.userID ?? program.creatorUserId.uuidString,
                username: program.structure.creator?.username ?? senderUsername,
                displayName: program.structure.creator?.displayName ?? senderDisplayName
            ),
            description: program.description,
            originProgramID: program.id
        )

        try plannerStore.insert(split)
        refreshLibrary()
        await refreshPendingInvites()
    }

    func activate(_ split: WorkoutSplit) {
        do {
            try plannerStore.activate(
                split,
                customization: defaultActivationCustomization(for: split)
            )
            refreshLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllPlannedWorkouts() {
        do {
            try plannerStore.deleteAllPlannedWorkouts()
            refreshLibrary()
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pendingInvite(id: UUID) -> PendingInviteDisplay? {
        pendingInvites.first(where: { $0.id == id })
    }

    private func defaultActivationCustomization(for split: WorkoutSplit) -> ActivationCustomization {
        ActivationCustomization(
            startDate: Calendar.current.startOfDay(for: .now),
            restDayOverrides: Dictionary(uniqueKeysWithValues: split.planBlocks.map { ($0.id, $0.isRestDay) }),
            startingWeights: Dictionary(
                uniqueKeysWithValues: split.planBlocks
                    .flatMap(\.exercises)
                    .compactMap { exercise in
                        guard let weight = exercise.startingWeight else { return nil }
                        return (exercise.id, weight)
                    }
            )
        )
    }
}
