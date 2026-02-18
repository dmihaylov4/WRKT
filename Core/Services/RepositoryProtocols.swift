import Foundation

// MARK: - Post Repository Protocol

/// Protocol for post-related database operations
@MainActor protocol PostRepositoryProtocol {
    /// Create a new workout post
    func createPost(
        workout: CompletedWorkout,
        caption: String?,
        images: [PostImage]?,
        visibility: PostVisibility,
        userId: UUID
    ) async throws -> WorkoutPost

    /// Fetch paginated feed for current user
    func fetchFeed(userId: UUID, limit: Int, cursor: String?) async throws -> (posts: [PostWithAuthor], hasMore: Bool)

    /// Fetch posts for a specific user
    func fetchUserPosts(userId: UUID, limit: Int, offset: Int) async throws -> [WorkoutPost]

    /// Delete a post
    func deletePost(_ postId: UUID) async throws

    /// Update a post's caption and visibility
    func updatePost(_ postId: UUID, caption: String?, visibility: PostVisibility) async throws

    /// Like a post
    func likePost(_ postId: UUID) async throws

    /// Unlike a post
    func unlikePost(_ postId: UUID) async throws

    /// Fetch users who liked a post
    func fetchPostLikes(postId: UUID) async throws -> [UserProfile]

    /// Add a comment to a post
    func addComment(postId: UUID, content: String) async throws -> PostComment

    /// Fetch comments for a post
    func fetchComments(postId: UUID) async throws -> [CommentWithAuthor]

    /// Delete a comment
    func deleteComment(commentId: UUID) async throws
}

// MARK: - Friendship Repository Protocol

/// Protocol for friendship-related database operations
@MainActor protocol FriendshipRepositoryProtocol {
    /// Send a friend request to another user
    func sendFriendRequest(to userId: UUID, from currentUserId: UUID) async throws -> Friendship

    /// Accept a pending friend request
    func acceptFriendRequest(friendshipId: UUID) async throws -> Friendship

    /// Reject a pending friend request
    func rejectFriendRequest(friendshipId: UUID) async throws

    /// Remove an existing friendship
    func removeFriendship(friendshipId: UUID) async throws

    /// Fetch all friends for a user
    func fetchFriends(userId: UUID) async throws -> [Friend]

    /// Fetch pending friend requests (incoming and outgoing)
    func fetchPendingRequests(userId: UUID) async throws -> (incoming: [FriendRequest], outgoing: [FriendRequest])

    /// Check friendship status between two users
    func checkFriendshipStatus(userId: UUID, friendId: UUID) async throws -> Friendship?

    /// Get count of pending friend requests
    func getPendingRequestCount(userId: UUID) async throws -> Int
}

// MARK: - Notification Repository Protocol

/// Protocol for notification-related database operations
@MainActor protocol NotificationRepositoryProtocol {
    /// Fetch notifications for a user
    func fetchNotifications(userId: UUID, limit: Int, offset: Int) async throws -> [NotificationWithActor]

    /// Fetch unread notification count
    func fetchUnreadCount(userId: UUID) async throws -> Int

    /// Mark a notification as read
    func markAsRead(notificationId: UUID) async throws

    /// Mark all notifications as read for a user
    func markAllAsRead(userId: UUID) async throws

    /// Delete a notification
    func deleteNotification(notificationId: UUID) async throws
}

// MARK: - Profile Repository Protocol

/// Protocol for profile-related database operations
@MainActor protocol ProfileRepositoryProtocol {
    /// Fetch a user profile by ID
    func fetchProfile(userId: UUID) async throws -> UserProfile?

    /// Update a user's profile
    func updateProfile(userId: UUID, displayName: String?, bio: String?, avatarUrl: String?) async throws -> UserProfile

    /// Update privacy setting
    func updatePrivacy(userId: UUID, isPrivate: Bool) async throws

    /// Search users by username
    func searchUsers(query: String, limit: Int, excludePrivate: Bool) async throws -> [UserProfile]

    /// Fetch multiple profiles by IDs
    func fetchProfilesBatched(_ userIds: [UUID]) async throws -> [UserProfile]
}

// MARK: - Image Upload Protocol

/// Protocol for image upload operations
@MainActor protocol ImageUploadServiceProtocol {
    /// Upload an image to Supabase Storage
    func uploadImage(_ imageData: Data, bucket: String, path: String) async throws -> String

    /// Delete an image from Supabase Storage
    func deleteImage(bucket: String, path: String) async throws
}
