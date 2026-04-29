//
//  ProgramInviteViewModel.swift
//  WRKT
//
//  Loads and applies actions for a single program invite preview.
//

import Foundation
import Observation

@Observable
@MainActor
final class ProgramInviteViewModel {
    private let repo: ProgramSharingRepositoryInterface
    private let plannerStore: PlannerStoreInterface
    private let profileRepo: ProfileRepositoryProtocol?

    var invite: ProgramInviteRow?
    var program: SharedProgramRow?
    var senderProfile: UserProfile?
    var previewSplit: WorkoutSplit?
    var importedSplit: WorkoutSplit?
    var isLoading = false
    var isActing = false
    var availabilityMessage: String?
    var errorMessage: String?
    var successMessage: String?

    var isActionable: Bool {
        invite?.status == .pending && program != nil
    }

    init(
        repo: ProgramSharingRepositoryInterface,
        plannerStore: PlannerStoreInterface,
        profileRepo: ProfileRepositoryProtocol?
    ) {
        self.repo = repo
        self.plannerStore = plannerStore
        self.profileRepo = profileRepo
    }

    func load(inviteID: UUID) async {
        isLoading = true
        errorMessage = nil
        availabilityMessage = nil
        defer { isLoading = false }

        do {
            let invite = try await repo.fetchInvite(id: inviteID)
            let senderProfile = try await profileRepo?.fetchProfile(userId: invite.senderUserId)

            self.invite = invite
            self.senderProfile = senderProfile

            guard invite.status == .pending else {
                self.program = nil
                availabilityMessage = message(for: invite.status)
                return
            }

            do {
                let program = try await repo.fetchProgram(id: invite.programId)
                self.program = program
                self.previewSplit = split(from: program)
            } catch ProgramSharingError.programUnavailable {
                self.program = nil
                self.previewSplit = nil
                availabilityMessage = "This program is no longer available."
            } catch {
                throw error
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptInvite() async -> Bool {
        guard let invite else {
            errorMessage = "Invite not found."
            return false
        }
        guard isActionable else {
            errorMessage = "This invite is no longer active."
            return false
        }

        isActing = true
        errorMessage = nil
        defer { isActing = false }

        do {
            let acceptedInvite = try await repo.accept(inviteId: invite.id)
            let program = try await repo.fetchProgram(id: acceptedInvite.programId)
            let split = previewSplit ?? split(from: program)

            try plannerStore.insert(split)
            self.invite = acceptedInvite
            self.program = program
            self.importedSplit = split
            self.successMessage = "Program added to your library."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func declineInvite() async -> Bool {
        guard let invite else {
            errorMessage = "Invite not found."
            return false
        }
        guard invite.status == .pending else {
            errorMessage = "This invite is no longer active."
            return false
        }

        isActing = true
        errorMessage = nil
        defer { isActing = false }

        do {
            self.invite = try await repo.decline(inviteId: invite.id)
            self.successMessage = "Invite declined."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func activateImportedProgram() -> Bool {
        guard let importedSplit else {
            errorMessage = "Program not found."
            return false
        }

        isActing = true
        errorMessage = nil
        defer { isActing = false }

        do {
            try plannerStore.activate(
                importedSplit,
                customization: defaultActivationCustomization(for: importedSplit)
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dropBlock(id sourceID: UUID, on targetID: UUID) {
        guard
            let previewSplit,
            let sourceIndex = previewSplit.planBlocks.firstIndex(where: { $0.id == sourceID }),
            let targetIndex = previewSplit.planBlocks.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else { return }

        let sourceBlock = previewSplit.planBlocks[sourceIndex]
        let targetBlock = previewSplit.planBlocks[targetIndex]
        let sourceSnapshot = snapshot(from: sourceBlock)
        let targetSnapshot = snapshot(from: targetBlock)

        if targetBlock.isRestDay && !sourceBlock.isRestDay {
            apply(sourceSnapshot, to: targetBlock)
            apply(.rest, to: sourceBlock)
        } else {
            apply(targetSnapshot, to: sourceBlock)
            apply(sourceSnapshot, to: targetBlock)
        }
    }

    private struct BlockSnapshot {
        let dayName: String
        let exercises: [PlanBlockExercise]
        let isRestDay: Bool

        static var rest: BlockSnapshot {
            BlockSnapshot(dayName: "Rest", exercises: [], isRestDay: true)
        }
    }

    private func snapshot(from block: PlanBlock) -> BlockSnapshot {
        BlockSnapshot(
            dayName: block.dayName,
            exercises: block.exercises
                .sorted(by: { $0.order < $1.order })
                .map(cloneExercise),
            isRestDay: block.isRestDay
        )
    }

    private func apply(_ snapshot: BlockSnapshot, to block: PlanBlock) {
        block.dayName = snapshot.dayName
        block.exercises = snapshot.exercises
        block.isRestDay = snapshot.isRestDay
    }

    private func cloneExercise(_ exercise: PlanBlockExercise) -> PlanBlockExercise {
        PlanBlockExercise(
            exerciseID: exercise.exerciseID,
            exerciseName: exercise.exerciseName,
            sets: exercise.sets,
            reps: exercise.reps,
            startingWeight: exercise.startingWeight,
            progressionStrategy: exercise.progressionStrategy,
            order: exercise.order
        )
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

    private func message(for status: ProgramInviteStatus) -> String {
        switch status {
        case .pending:
            return "This invite is ready to add."
        case .accepted:
            return "This invite has already been added to your library."
        case .declined:
            return "This invite was declined."
        case .revoked, .cancelled:
            return "This invite was cancelled by the sender."
        }
    }

    private func split(from program: SharedProgramRow) -> WorkoutSplit {
        ProgramSerializer.fromStructure(
            program.structure,
            name: program.name,
            reschedulePolicy: ReschedulePolicy(rawValue: program.reschedulePolicy) ?? .strict,
            creator: .init(
                userID: program.structure.creator?.userID ?? program.creatorUserId.uuidString,
                username: program.structure.creator?.username ?? senderProfile?.username,
                displayName: program.structure.creator?.displayName ?? senderProfile?.displayName
            ),
            description: program.description,
            originProgramID: program.id
        )
    }
}
