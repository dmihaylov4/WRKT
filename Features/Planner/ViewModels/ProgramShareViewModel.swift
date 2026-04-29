//
//  ProgramShareViewModel.swift
//  WRKT
//
//  Coordinates sending a program snapshot to one or more friends.
//

import Foundation
import Observation

@Observable
@MainActor
final class ProgramShareViewModel {
    private let repo: ProgramSharingRepositoryInterface
    private let plannerStore: PlannerStoreInterface

    var selectedFriends: [UserProfile] = []
    var descriptionText = ""
    var isSending = false
    var errorMessage: String?
    var lastResult: ProgramSharingRepository.SendResult?

    init(
        repo: ProgramSharingRepositoryInterface,
        plannerStore: PlannerStoreInterface
    ) {
        self.repo = repo
        self.plannerStore = plannerStore
    }

    func toggleFriend(_ friend: UserProfile) {
        if let index = selectedFriends.firstIndex(where: { $0.id == friend.id }) {
            selectedFriends.remove(at: index)
        } else {
            selectedFriends.append(friend)
        }
    }

    func send(
        split: WorkoutSplit,
        currentUserID: UUID,
        currentUsername: String?,
        currentDisplayName: String?
    ) async -> Bool {
        guard !selectedFriends.isEmpty else {
            errorMessage = "Choose at least one friend."
            return false
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let result = try await repo.send(
                split: split,
                description: descriptionText.nilIfBlank,
                to: selectedFriends.map(\.id),
                currentUserID: currentUserID,
                currentUsername: currentUsername,
                currentDisplayName: currentDisplayName
            )

            split.lastSharedProgramID = result.program.id
            try plannerStore.saveContext()
            lastResult = result
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
