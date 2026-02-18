//
//  FriendsListViewModel.swift
//  WRKT
//
//  ViewModel for managing friends list with search
//

import Foundation

@MainActor
@Observable
final class FriendsListViewModel {
    var friends: [Friend] = []
    var filteredFriends: [Friend] = []
    var searchQuery = ""
    var isLoading = false
    var error: String?

    private let friendshipRepository: FriendshipRepository
    private let authService: SupabaseAuthService

    // Pending removals for undo functionality
    private struct PendingRemoval {
        let friend: Friend
        let task: Task<Void, Never>
    }
    nonisolated(unsafe) private var pendingRemovals: [UUID: PendingRemoval] = [:]
    nonisolated(unsafe) private var friendshipObserver: NSObjectProtocol?

    init(friendshipRepository: FriendshipRepository, authService: SupabaseAuthService) {
        self.friendshipRepository = friendshipRepository
        self.authService = authService
        setupFriendshipObserver()
    }

    private func setupFriendshipObserver() {
        friendshipObserver = NotificationCenter.default.addObserver(
            forName: .friendshipStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.loadFriends()
            }
        }
    }

    func loadFriends() async {
        guard let userId = authService.currentUser?.id else {
            error = "Not authenticated"
            return
        }

        isLoading = true
        error = nil

        do {
            friends = try await friendshipRepository.fetchFriends(userId: userId)
            filterFriends()
            isLoading = false
        } catch {
            self.error = "Failed to load friends: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func removeFriend(_ friend: Friend) {
        // Optimistic UI update - remove from list immediately
        friends.removeAll { $0.id == friend.id }
        filterFriends()
        Haptics.warning()

        // Schedule backend deletion (5 seconds delay for undo window)
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !Task.isCancelled {
                await performRemoval(friend)
            }
        }

        pendingRemovals[friend.id] = PendingRemoval(friend: friend, task: task)
    }

    private func performRemoval(_ friend: Friend) async {
        do {
            try await friendshipRepository.removeFriendship(friendshipId: friend.friendshipId)
            pendingRemovals.removeValue(forKey: friend.id)

            WorkoutToastManager.shared.show(
                message: "Friend removed",
                icon: "checkmark.circle.fill"
            )
        } catch {
            self.error = "Failed to remove friend"
            undoRemove(friend)
            Haptics.error()
        }
    }

    func undoRemove(_ friend: Friend) {
        // Cancel pending removal task
        if let pending = pendingRemovals[friend.id] {
            pending.task.cancel()
            pendingRemovals.removeValue(forKey: friend.id)
        }

        // Restore friend to list (if not already present)
        if !friends.contains(where: { $0.id == friend.id }) {
            friends.append(friend)
            // Sort by friendship date (newest first)
            friends.sort { $0.friendsSince > $1.friendsSince }
            filterFriends()
        }

        Haptics.success()
        WorkoutToastManager.shared.show(
            message: "Friend restored",
            icon: "checkmark.circle.fill"
        )
    }

    func filterFriends() {
        if searchQuery.isEmpty {
            filteredFriends = friends
        } else {
            filteredFriends = friends.filter { friend in
                friend.profile.username.localizedCaseInsensitiveContains(searchQuery) ||
                (friend.profile.displayName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
    }

    deinit {
        // Remove observer
        if let observer = friendshipObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Cancel all pending removal tasks to prevent memory leaks
        for (_, pending) in pendingRemovals {
            pending.task.cancel()
        }
    }
}
