import Foundation
import Supabase

/// Repository for managing friendships with query optimization
@MainActor
final class FriendshipRepository: BaseRepository<Friendship>, FriendshipRepositoryProtocol {

    private let notificationRepository: NotificationRepository

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.notificationRepository = NotificationRepository(client: client)
        super.init(
            tableName: "friendships",
            logPrefix: "Friendship",
            client: client
        )
    }

    // MARK: - Send Friend Request

    /// Send a friend request to another user
    func sendFriendRequest(to userId: UUID, from currentUserId: UUID) async throws -> Friendship {
        logInfo("Sending friend request from \(currentUserId) to \(userId)")

        // Check if friendship already exists
        let existing: [Friendship] = try await client
            .from("friendships")
            .select()
            .or("and(user_id.eq.\(currentUserId),friend_id.eq.\(userId)),and(user_id.eq.\(userId),friend_id.eq.\(currentUserId))")
            .execute()
            .value

        if let existingFriendship = existing.first {
            logWarning("Friendship already exists with status: \(existingFriendship.status)")
            throw SupabaseError.serverError("Friend request already exists")
        }

        // Create new friendship request
        struct NewFriendship: Encodable {
            let user_id: String
            let friend_id: String
            let status: String
        }

        let newFriendshipData = NewFriendship(
            user_id: currentUserId.uuidString,
            friend_id: userId.uuidString,
            status: "pending"
        )

        let newFriendship: Friendship = try await client
            .from("friendships")
            .insert(newFriendshipData)
            .select()
            .single()
            .execute()
            .value

        // Notification is created automatically by database trigger (SECURITY DEFINER)
        // No need to create it manually here
        logInfo("🔔 Notification will be created by database trigger for friend request")

        // Invalidate friendship caches
        cache.invalidate(QueryCache.friendsListKey(userId: currentUserId.uuidString))
        cache.invalidate(QueryCache.friendsListKey(userId: userId.uuidString))
        invalidateFriendRequestsCache(userId: currentUserId, friendId: userId)

        logSuccess("Friend request sent: \(newFriendship.id)")
        return newFriendship
    }

    // MARK: - Accept Friend Request

    /// Accept a pending friend request
    func acceptFriendRequest(friendshipId: UUID) async throws -> Friendship {
        logSuccess("Accepting friend request: \(friendshipId)")

        struct UpdateStatus: Encodable {
            let status: String
        }

        let updated: Friendship = try await client
            .from("friendships")
            .update(UpdateStatus(status: "accepted"))
            .eq("id", value: friendshipId.uuidString)
            .single()
            .execute()
            .value

        // Notification is created automatically by database trigger (SECURITY DEFINER)
        // No need to create it manually here
        logInfo("🔔 Notification will be created by database trigger for accepted friend request")

        // Invalidate all friendship-related caches
        cache.invalidateAllFriendsLists()
        invalidateFriendshipStatusCache(userId: updated.userId, friendId: updated.friendId)
        invalidateFriendRequestsCache(userId: updated.userId, friendId: updated.friendId)

        logSuccess("Friend request accepted")
        return updated
    }

    // MARK: - Reject Friend Request

    /// Reject a pending friend request (deletes it)
    func rejectFriendRequest(friendshipId: UUID) async throws {
        logError("Rejecting friend request: \(friendshipId)")

        // Fetch the friendship before deleting to invalidate caches
        let friendships: [Friendship] = try await client
            .from("friendships")
            .select()
            .eq("id", value: friendshipId.uuidString)
            .execute()
            .value

        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString)
            .execute()

        // Invalidate friendship caches
        cache.invalidateAllFriendsLists()

        if let friendship = friendships.first {
            invalidateFriendshipStatusCache(userId: friendship.userId, friendId: friendship.friendId)
            invalidateFriendRequestsCache(userId: friendship.userId, friendId: friendship.friendId)
        }

        logSuccess("Friend request rejected")
    }

    // MARK: - Remove Friend

    /// Remove a friend (deletes the friendship)
    func removeFriendship(friendshipId: UUID) async throws {
        logInfo("Removing friendship: \(friendshipId)", emoji: "🗑️")

        // Fetch the friendship before deleting to invalidate caches
        let friendships: [Friendship] = try await client
            .from("friendships")
            .select()
            .eq("id", value: friendshipId.uuidString)
            .execute()
            .value

        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString)
            .execute()

        // Invalidate friendship caches
        cache.invalidateAllFriendsLists()

        if let friendship = friendships.first {
            invalidateFriendshipStatusCache(userId: friendship.userId, friendId: friendship.friendId)
        }

        logSuccess("Friend removed")
    }

    // MARK: - Fetch Friends

    /// Fetch all accepted friends for a user with caching
    func fetchFriends(userId: UUID) async throws -> [Friend] {

        // Try cache first
        let cacheKey = QueryCache.friendsListKey(userId: userId.uuidString)
        if let cached: [Friend] = cache.get(cacheKey) {
            logSuccess("Cache hit for friends list")
            return cached
        }

        // Fetch all accepted friendships where user is either sender or receiver
        let friendships: [Friendship] = try await client
            .from("friendships")
            .select()
            .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
            .eq("status", value: "accepted")
            .execute()
            .value


        // Extract friend user IDs
        let friendIds = friendships.map { friendship in
            friendship.userId == userId ? friendship.friendId : friendship.userId
        }

        guard !friendIds.isEmpty else {
            logSuccess("No friends found")
            cache.set(cacheKey, value: [], ttl: .friendsList)
            return []
        }

        // Fetch profiles with batched caching
        let profiles = try await fetchProfilesBatched(friendIds)

        logSuccess("Fetched \(profiles.count) friend profiles")

        // Combine friendships with profiles
        let friends = friendships.compactMap { friendship -> Friend? in
            let friendUserId = friendship.userId == userId ? friendship.friendId : friendship.userId
            guard let profile = profiles.first(where: { $0.id == friendUserId }) else {
                return nil
            }

            return Friend(
                id: profile.id,
                profile: profile,
                friendshipId: friendship.id,
                friendsSince: friendship.createdAt,
                mutedNotifications: friendship.mutedNotifications
            )
        }

        // Cache the result
        cache.set(cacheKey, value: friends, ttl: .friendsList)

        return friends
    }

    // MARK: - Fetch Pending Requests

    /// Fetch pending friend requests (both incoming and outgoing) with caching
    func fetchPendingRequests(userId: UUID) async throws -> (incoming: [FriendRequest], outgoing: [FriendRequest]) {

        // Try cache first
        let cacheKey = "friendRequests:\(userId.uuidString)"
        if let cached: (incoming: [FriendRequest], outgoing: [FriendRequest]) = cache.get(cacheKey) {
            logSuccess("Cache hit for friend requests")
            return cached
        }

        // Fetch all pending friendships
        let friendships: [Friendship] = try await client
            .from("friendships")
            .select()
            .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
            .eq("status", value: "pending")
            .execute()
            .value


        // Separate incoming and outgoing
        let incoming = friendships.filter { $0.friendId == userId }
        let outgoing = friendships.filter { $0.userId == userId }

        // Fetch profiles with batched caching
        let incomingUserIds = incoming.map { $0.userId }
        let incomingProfiles = try await fetchProfilesBatched(incomingUserIds)

        let outgoingUserIds = outgoing.map { $0.friendId }
        let outgoingProfiles = try await fetchProfilesBatched(outgoingUserIds)

        // Build FriendRequest objects
        let incomingRequests = incoming.compactMap { friendship -> FriendRequest? in
            guard let profile = incomingProfiles.first(where: { $0.id == friendship.userId }) else {
                return nil
            }
            return FriendRequest(
                id: friendship.id,
                friendship: friendship,
                profile: profile,
                isIncoming: true
            )
        }

        let outgoingRequests = outgoing.compactMap { friendship -> FriendRequest? in
            guard let profile = outgoingProfiles.first(where: { $0.id == friendship.friendId }) else {
                return nil
            }
            return FriendRequest(
                id: friendship.id,
                friendship: friendship,
                profile: profile,
                isIncoming: false
            )
        }

        let result = (incoming: incomingRequests, outgoing: outgoingRequests)

        // Cache the result
        cache.set(cacheKey, value: result, ttl: .friendsList)

        logSuccess("Incoming: \(incomingRequests.count), Outgoing: \(outgoingRequests.count)")
        return result
    }

    // MARK: - Check Friendship Status

    /// Check the friendship status between two users with caching
    func checkFriendshipStatus(userId: UUID, friendId: UUID) async throws -> Friendship? {
        // Try cache first
        let cacheKey = "friendshipStatus:\(userId.uuidString):\(friendId.uuidString)"
        if let cached: Friendship? = cache.get(cacheKey) {
            logSuccess("Cache hit for friendship status")
            return cached
        }

        let friendships: [Friendship] = try await client
            .from("friendships")
            .select()
            .or("and(user_id.eq.\(userId.uuidString),friend_id.eq.\(friendId.uuidString)),and(user_id.eq.\(friendId.uuidString),friend_id.eq.\(userId.uuidString))")
            .execute()
            .value

        let friendship = friendships.first

        // Cache the result
        cache.set(cacheKey, value: friendship, ttl: .friendsList)

        return friendship
    }

    // MARK: - Toggle Mute Notifications

    /// Toggle muted notifications for a friendship
    func toggleMuteNotifications(friendshipId: UUID, muted: Bool) async throws {
        logInfo("Toggling mute notifications for friendship: \(friendshipId) to \(muted)", emoji: "🔔")

        struct UpdateMuted: Encodable {
            let muted_notifications: Bool
        }

        try await client
            .from("friendships")
            .update(UpdateMuted(muted_notifications: muted))
            .eq("id", value: friendshipId.uuidString)
            .execute()

        // Invalidate friendship caches
        cache.invalidateAllFriendsLists()

        logSuccess("Mute notifications set to \(muted) for friendship \(friendshipId)")
    }

    // MARK: - Get Pending Request Count

    /// Get count of pending friend requests for a user
    func getPendingRequestCount(userId: UUID) async throws -> Int {
        logInfo("Getting pending request count for user: \(userId)", emoji: "🔢")

        let requests: [Friendship] = try await client
            .from("friendships")
            .select()
            .eq("friend_id", value: userId.uuidString)
            .eq("status", value: "pending")
            .execute()
            .value

        logSuccess("Found \(requests.count) pending requests")
        return requests.count
    }

    // MARK: - Helper Methods

    /// Invalidate friendship status cache for both directions
    private func invalidateFriendshipStatusCache(userId: UUID, friendId: UUID) {
        // Invalidate both directional cache keys
        cache.invalidate("friendshipStatus:\(userId.uuidString):\(friendId.uuidString)")
        cache.invalidate("friendshipStatus:\(friendId.uuidString):\(userId.uuidString)")

        logInfo("Invalidated friendship status cache for \(userId) <-> \(friendId)")
    }

    /// Invalidate friend requests cache for both users
    private func invalidateFriendRequestsCache(userId: UUID, friendId: UUID) {
        // Invalidate friend requests cache for both users
        cache.invalidate("friendRequests:\(userId.uuidString)")
        cache.invalidate("friendRequests:\(friendId.uuidString)")

        logInfo("Invalidated friend requests cache for \(userId) <-> \(friendId)")
    }

    // Note: fetchProfilesBatched is inherited from BaseRepository
}
