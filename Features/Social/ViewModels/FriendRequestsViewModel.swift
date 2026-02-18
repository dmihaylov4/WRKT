//
//  FriendRequestsViewModel.swift
//  WRKT
//
//  ViewModel for managing friend requests (incoming and outgoing)
//

import Foundation

@MainActor
@Observable
final class FriendRequestsViewModel {
    var incomingRequests: [FriendRequest] = []
    var outgoingRequests: [FriendRequest] = []
    var isLoading = false
    var error: String?

    private let friendshipRepository: FriendshipRepository
    private let authService: SupabaseAuthService

    init(friendshipRepository: FriendshipRepository, authService: SupabaseAuthService) {
        self.friendshipRepository = friendshipRepository
        self.authService = authService
    }

    var incomingCount: Int {
        incomingRequests.count
    }

    func loadRequests() async {
        guard let userId = authService.currentUser?.id else {
            error = "Not authenticated"
            return
        }

        isLoading = true
        error = nil

        do {
            let (incoming, outgoing) = try await friendshipRepository.fetchPendingRequests(userId: userId)
            incomingRequests = incoming
            outgoingRequests = outgoing
            isLoading = false
        } catch {
            self.error = "Failed to load requests: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func acceptRequest(_ request: FriendRequest) async {
        do {
            _ = try await friendshipRepository.acceptFriendRequest(friendshipId: request.friendship.id)
            incomingRequests.removeAll { $0.id == request.id }
            Haptics.success()
        } catch {
            self.error = "Failed to accept request: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    func rejectRequest(_ request: FriendRequest) async {
        do {
            try await friendshipRepository.rejectFriendRequest(friendshipId: request.friendship.id)
            incomingRequests.removeAll { $0.id == request.id }
            Haptics.success()
        } catch {
            self.error = "Failed to reject request: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    func cancelRequest(_ request: FriendRequest) async {
        do {
            try await friendshipRepository.rejectFriendRequest(friendshipId: request.friendship.id)
            outgoingRequests.removeAll { $0.id == request.id }
            Haptics.success()
        } catch {
            self.error = "Failed to cancel request: \(error.localizedDescription)"
            Haptics.error()
        }
    }
}
