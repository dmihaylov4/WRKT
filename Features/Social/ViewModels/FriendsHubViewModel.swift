//
//  FriendsHubViewModel.swift
//  WRKT
//
//  ViewModel for the redesigned Friends Hub with activity tracking
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class FriendsHubViewModel {
    var activeFriends: [ActiveFriend] = []
    var isLoading = false
    var error: String?

    private let friendshipRepository: FriendshipRepository
    private let postRepository: PostRepository
    private let authService: SupabaseAuthService

    init(
        friendshipRepository: FriendshipRepository,
        postRepository: PostRepository,
        authService: SupabaseAuthService
    ) {
        self.friendshipRepository = friendshipRepository
        self.postRepository = postRepository
        self.authService = authService
    }

    /// Load friends with their recent workout activity
    func loadFriends() async {
        guard let currentUserId = authService.currentUser?.id else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            // Fetch all friends
            let friends = try await friendshipRepository.fetchFriends(userId: currentUserId)

            // For each friend, fetch their most recent workout post
            var activeFriendsData: [ActiveFriend] = []

            for friend in friends {
                var lastWorkoutDate: Date?
                var recentWorkoutCount = 0

                do {
                    // Fetch recent posts for this friend (last 7 days worth, limit 10)
                    let posts = try await postRepository.fetchUserPosts(userId: friend.id, limit: 10, offset: 0)

                    // Get the most recent post date
                    if let mostRecent = posts.first {
                        lastWorkoutDate = mostRecent.createdAt
                    }

                    // Count posts from last 7 days
                    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                    recentWorkoutCount = posts.filter { $0.createdAt >= weekAgo }.count
                } catch {
                    // If we can't fetch posts, that's ok - continue without workout data
                    AppLogger.warning("Could not fetch posts for friend \(friend.id): \(error.localizedDescription)", category: AppLogger.app)
                }

                let activeFriend = ActiveFriend(
                    from: friend,
                    lastWorkoutDate: lastWorkoutDate,
                    recentWorkoutCount: recentWorkoutCount
                )
                activeFriendsData.append(activeFriend)
            }

            // Sort: active friends first (by most recent workout), then inactive friends
            activeFriends = activeFriendsData.sorted { friend1, friend2 in
                // Active friends come first
                if friend1.isActive != friend2.isActive {
                    return friend1.isActive
                }
                // Then sort by last workout date (most recent first)
                if let date1 = friend1.lastWorkoutDate, let date2 = friend2.lastWorkoutDate {
                    return date1 > date2
                }
                // Friends with workout dates come before those without
                if friend1.lastWorkoutDate != nil && friend2.lastWorkoutDate == nil {
                    return true
                }
                return false
            }

            isLoading = false
        } catch {
            self.error = "Failed to load friends: \(error.localizedDescription)"
            isLoading = false
            AppLogger.error("Failed to load friends for hub", error: error, category: AppLogger.app)
        }
    }

    /// Get only active friends (worked out in last 24h)
    var recentlyActiveFriends: [ActiveFriend] {
        activeFriends.filter { $0.isActive }
    }

    /// Get friends who worked out in last 7 days but not 24h
    var weeklyActiveFriends: [ActiveFriend] {
        activeFriends.filter { $0.isRecentlyActive && !$0.isActive }
    }

    /// Get inactive friends
    var inactiveFriends: [ActiveFriend] {
        activeFriends.filter { !$0.isRecentlyActive }
    }

    /// Refresh the friends data
    func refresh() async {
        await loadFriends()
    }
}
