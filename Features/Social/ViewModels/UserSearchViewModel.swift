//
//  UserSearchViewModel.swift
//  WRKT
//
//  ViewModel for user search with debouncing
//

import Foundation

@MainActor
@Observable
final class UserSearchViewModel {
    var searchQuery = ""
    var searchResults: [UserProfile] = []
    var isSearching = false
    var error: String?

    private let authService: SupabaseAuthService
    private let friendshipRepository: FriendshipRepository
    private var searchTask: Task<Void, Never>?

    init(authService: SupabaseAuthService, friendshipRepository: FriendshipRepository) {
        self.authService = authService
        self.friendshipRepository = friendshipRepository
    }

    func performSearch() {
        // Cancel previous search task
        searchTask?.cancel()

        // Reset if query is empty
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        // Debounce search by 500ms
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            guard !Task.isCancelled else { return }

            await executeSearch()
        }
    }

    private func executeSearch() async {
        isSearching = true
        error = nil

        do {
            let results = try await authService.searchUsers(query: searchQuery)

            // Filter out current user from results
            if let currentUserId = authService.currentUser?.id {
                searchResults = results.filter { $0.id != currentUserId }
            } else {
                searchResults = results
            }

            isSearching = false
        } catch {
            self.error = "Search failed: \(error.localizedDescription)"
            searchResults = []
            isSearching = false
        }
    }
}
