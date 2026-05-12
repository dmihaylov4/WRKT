import Foundation
import Supabase

struct WorkoutPostInsertPayload: Encodable {
    let user_id: String
    let caption: String?
    let workout_data: CompletedWorkout
    let workout_data_list: [CompletedWorkout]?
    let images: [PostImage]?
    let visibility: String

    init(
        workouts: [CompletedWorkout],
        caption: String?,
        images: [PostImage]?,
        visibility: PostVisibility,
        userId: UUID
    ) throws {
        guard let firstWorkout = workouts.first else {
            throw SupabaseError.serverError("Cannot create workout post without workouts")
        }

        self.user_id = userId.uuidString
        self.caption = caption
        self.workout_data = firstWorkout
        self.workout_data_list = workouts.count > 1 ? workouts : nil
        self.images = images
        self.visibility = visibility.rawValue
    }
}

private struct FeedCursor {
    let createdAt: Date
    let id: UUID

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let createdAt = ISO8601DateFormatter().date(from: parts[0]),
              let id = UUID(uuidString: parts[1]) else { return nil }
        self.createdAt = createdAt
        self.id = id
    }

    init(post: WorkoutPost) {
        self.createdAt = post.createdAt
        self.id = post.id
    }

    var rawValue: String {
        "\(createdAt.ISO8601Format())|\(id.uuidString)"
    }
}

/// Repository for managing workout posts with query optimization and offline support
@MainActor
final class PostRepository: BaseRepository<WorkoutPost>, PostRepositoryProtocol {
    private let swiftDataCache = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let offlineQueue = OfflineQueueManager.shared

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        super.init(
            tableName: "workout_posts",
            logPrefix: "Post",
            client: client
        )
    }

    // MARK: - Create Post

    /// Create a new workout post with privacy-aware images
    func createPost(
        workout: CompletedWorkout,
        caption: String?,
        images: [PostImage]?,
        visibility: PostVisibility,
        userId: UUID
    ) async throws -> WorkoutPost {
        try await createPost(
            workouts: [workout],
            caption: caption,
            images: images,
            visibility: visibility,
            userId: userId
        )
    }

    /// Create a new workout post from one or more workouts.
    func createPost(
        workouts: [CompletedWorkout],
        caption: String?,
        images: [PostImage]?,
        visibility: PostVisibility,
        userId: UUID
    ) async throws -> WorkoutPost {
        logInfo("Creating post for user: \(userId), workouts: \(workouts.count)", emoji: "📝")

        let newPostData = try WorkoutPostInsertPayload(
            workouts: workouts,
            caption: caption,
            images: images,
            visibility: visibility,
            userId: userId
        )

        let newPost: WorkoutPost = try await client
            .from(tableName)
            .insert(newPostData)
            .select()
            .single()
            .execute()
            .value

        cache.invalidateAllFeeds()

        logSuccess("Post created: \(newPost.id)")
        return newPost
    }

    // MARK: - Fetch Feed

    /// Fetch paginated feed for current user using cursor-based pagination with caching
    /// - Parameters:
    ///   - userId: Current user ID
    ///   - limit: Number of posts to fetch (default 20)
    ///   - cursor: Optional composite cursor (`created_at|id`) for stable pagination
    /// - Returns: Array of posts with author information, `hasMore`, and next cursor
    func fetchFeed(userId: UUID, limit: Int = 20, cursor: String? = nil) async throws -> (posts: [PostWithAuthor], hasMore: Bool, nextCursor: String?) {
        logInfo("Fetching feed for user: \(userId), limit: \(limit), cursor: \(cursor ?? "none")")

        // If offline and no cursor (initial page), return SwiftData cache
        if !networkMonitor.isConnected && cursor == nil {
            logInfo("Offline - returning SwiftData cached feed")
            let cachedPosts = swiftDataCache.fetchCachedPosts(limit: limit, includeExpired: true)
            let nextCursor = cachedPosts.last.map { FeedCursor(post: $0.post).rawValue }
            return (cachedPosts, false, nextCursor) // hasMore=false when offline
        }

        // Try in-memory cache first (only for initial page)
        let cacheKey = QueryCache.feedKey(userId: userId.uuidString, cursor: cursor)
        if let cached: (posts: [PostWithAuthor], hasMore: Bool, nextCursor: String?) = cache.get(cacheKey) {
            logSuccess("Cache hit for feed")
            return cached
        }

        // Cutoff date to avoid very old/corrupted posts (30 days)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let parsedCursor = cursor.flatMap(FeedCursor.init(rawValue:))

        // Single feed query. RLS is responsible for visibility/friend filtering.
        var feedQuery = client
            .from("workout_posts")
            .select()
            .gte("created_at", value: cutoffDate.ISO8601Format())

        if let parsedCursor {
            let cursorDate = parsedCursor.createdAt.ISO8601Format()
            feedQuery = feedQuery.or(
                "created_at.lt.\(cursorDate),and(created_at.eq.\(cursorDate),id.lt.\(parsedCursor.id.uuidString))"
            )
        }

        let fetchedPosts: [WorkoutPost] = (try? await feedQuery
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(limit + 1)
            .execute()
            .value) ?? []
        logInfo("Fetched \(fetchedPosts.count) posts from merged feed query")

        // Log warning for posts with empty workout data (legacy data issue)
        let postsWithEmptyData = fetchedPosts.filter { $0.workoutData.entries.isEmpty }
        if !postsWithEmptyData.isEmpty {
            logWarning("Found \(postsWithEmptyData.count) posts with empty workout data (legacy format)")
        }

        let hasMore = fetchedPosts.count > limit
        let posts = Array(fetchedPosts.prefix(limit))
        let nextCursor = posts.last.map { FeedCursor(post: $0).rawValue }

        logInfo("Total posts in page: \(posts.count), hasMore: \(hasMore)")

        guard !posts.isEmpty else {
            let emptyResult: (posts: [PostWithAuthor], hasMore: Bool, nextCursor: String?) = ([], false, nil)
            cache.set(cacheKey, value: emptyResult, ttl: .feedPosts)
            return emptyResult
        }

        // Fetch author profiles in parallel (with individual profile caching)
        let authorIds = Array(Set(posts.map { $0.userId }))
        let profiles = try await fetchProfilesBatched(authorIds)

        // Check which posts are liked by current user
        let postIds = posts.map { $0.id.uuidString }
        let likes: [PostLike] = try await client
            .from("post_likes")
            .select()
            .eq("user_id", value: userId.uuidString)
            .in("post_id", values: postIds)
            .execute()
            .value

        let likedPostIds = Set(likes.map { $0.postId })

        // Combine posts with authors
        let postsWithAuthors = posts.compactMap { post -> PostWithAuthor? in
            guard let author = profiles.first(where: { $0.id == post.userId }) else {
                return nil
            }

            return PostWithAuthor(
                id: post.id,
                post: post,
                author: author,
                isLikedByCurrentUser: likedPostIds.contains(post.id)
            )
        }

        // Cache the result (in-memory)
        let result = (postsWithAuthors, hasMore, nextCursor)
        cache.set(cacheKey, value: result, ttl: .feedPosts)

        // Cache in SwiftData for offline support (only initial page)
        if cursor == nil {
            swiftDataCache.cachePosts(postsWithAuthors)
        }

        logSuccess("Fetched \(postsWithAuthors.count) posts with authors, hasMore: \(hasMore)")
        return result
    }

    /// Legacy method for backward compatibility (uses offset-based pagination)
    @available(*, deprecated, message: "Use fetchFeed(userId:limit:cursor:) instead for better performance")
    func fetchFeed(userId: UUID, limit: Int = 20, offset: Int = 0) async throws -> [PostWithAuthor] {
        let result = try await fetchFeed(userId: userId, limit: limit, cursor: nil)
        return result.posts
    }

    // MARK: - Fetch User Posts

    /// Fetch posts for a specific user
    func fetchUserPosts(userId: UUID, limit: Int = 20, offset: Int = 0) async throws -> [WorkoutPost] {
        logInfo("Fetching posts for user: \(userId)")

        let posts: [WorkoutPost] = try await client
            .from("workout_posts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        logSuccess("Found \(posts.count) user posts")
        return posts
    }

    // MARK: - Delete Post

    /// Delete a post (with offline queue support)
    func deletePost(_ postId: UUID) async throws {
        // Capture value immediately to avoid concurrency issues
        let postIdValue = postId.uuidString

        logInfo("Deleting post: \(postIdValue)")

        // Delete from local cache (run in separate task to avoid blocking)
        Task { @MainActor [postId] in
            swiftDataCache.deleteCachedPost(id: postId)
        }

        // If offline, queue the action
        if !networkMonitor.isConnected {
            logInfo("Offline - queueing delete action")
            let action = QueuedAction(
                type: .deletePost,
                data: ["postId": postIdValue]
            )
            offlineQueue.enqueue(action)
            return
        }

        try await client
            .from("workout_posts")
            .delete()
            .eq("id", value: postIdValue)
            .execute()

        // Invalidate caches
        cache.invalidatePost(postIdValue)
        cache.invalidateAllFeeds()

        logSuccess("Post deleted")
    }

    // MARK: - Update Post

    /// Update a post's caption and visibility (with offline queue support)
    nonisolated func updatePost(_ postId: UUID, caption: String?, visibility: PostVisibility) async throws {
        // Capture values immediately in a non-isolated context
        let captionValue = caption
        let visibilityValue = visibility.rawValue
        let postIdValue = postId.uuidString

        logInfo("Updating post: \(postIdValue)")

        // Check network status on MainActor
        let isOffline = await !networkMonitor.isConnected

        // If offline, queue the action
        if isOffline {
            logInfo("Offline - queueing update action")
            let action = QueuedAction(
                type: .updatePost,
                data: [
                    "postId": postIdValue,
                    "caption": captionValue ?? "",
                    "visibility": visibilityValue
                ]
            )
            await offlineQueue.enqueue(action)
            return
        }

        struct UpdatePost: Encodable {
            let caption: String?
            let visibility: String
            let updated_at: String
        }

        let updateData = UpdatePost(
            caption: captionValue,
            visibility: visibilityValue,
            updated_at: Date().ISO8601Format()
        )

        try await client
            .from("workout_posts")
            .update(updateData)
            .eq("id", value: postIdValue)
            .execute()

        // Invalidate caches on MainActor
        await MainActor.run {
            cache.invalidatePost(postIdValue)
            cache.invalidateAllFeeds()
        }

        // Also update local cache if it exists (run in separate task to avoid blocking)
        Task { @MainActor [postId] in
            swiftDataCache.deleteCachedPost(id: postId) // Will be re-cached on next fetch
        }

        logSuccess("Post updated")
    }

    // MARK: - Fetch Own Post by HealthKit UUID

    /// Returns the current user's existing post for a given HealthKit workout UUID, or nil if none exists.
    func fetchOwnPost(forHealthKitUUID hkUUID: UUID, userId: UUID) async throws -> WorkoutPost? {
        let posts: [WorkoutPost] = try await client
            .from(tableName)
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("workout_data->>matchedHealthKitUUID", value: hkUUID.uuidString)
            .limit(1)
            .execute()
            .value
        return posts.first
    }

    // MARK: - Update Post Images

    /// Update a post's images (e.g., after lazy map backfill)
    func updatePostImages(_ postId: UUID, images: [PostImage]) async throws {
        struct UpdateImages: Encodable {
            let images: [PostImage]
            let updated_at: String
        }
        try await client
            .from(tableName)
            .update(UpdateImages(images: images, updated_at: Date().ISO8601Format()))
            .eq("id", value: postId.uuidString)
            .execute()

        // Invalidate caches so feed reflects the new images
        cache.invalidatePost(postId.uuidString)
        cache.invalidateAllFeeds()

        logSuccess("Post images updated: \(postId)")
    }

    // MARK: - Like Post

    /// Like a post (with offline queue support)
    func likePost(_ postId: UUID) async throws {
        guard let userId = SupabaseAuthService.shared.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        logInfo("Liking post: \(postId)")

        // Update local cache immediately (optimistic update - run in separate task)
        Task { @MainActor in
            swiftDataCache.updateCachedPost(id: postId, likesCount: nil, isLiked: true)
        }

        // If offline, queue the action
        if !networkMonitor.isConnected {
            logInfo("Offline - queueing like action")
            let action = QueuedAction(
                type: .likePost,
                data: ["postId": postId.uuidString]
            )
            offlineQueue.enqueue(action)
            return
        }

        // Check if already liked
        let existing: [PostLike] = try await client
            .from("post_likes")
            .select()
            .eq("post_id", value: postId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        if !existing.isEmpty {
            logWarning("Post already liked")
            return
        }

        // Create like
        struct NewLike: Encodable {
            let post_id: String
            let user_id: String
        }

        try await client
            .from("post_likes")
            .upsert(NewLike(post_id: postId.uuidString, user_id: userId.uuidString), onConflict: "post_id,user_id")
            .execute()

        // Invalidate caches
        cache.invalidate(QueryCache.postLikesKey(postId: postId.uuidString))
        cache.invalidateAllFeeds()

        logSuccess("Post liked")
    }

    // MARK: - Unlike Post

    /// Unlike a post (with offline queue support)
    func unlikePost(_ postId: UUID) async throws {
        guard let userId = SupabaseAuthService.shared.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        logInfo("Unliking post: \(postId)")

        // Update local cache immediately (optimistic update - run in separate task)
        Task { @MainActor in
            swiftDataCache.updateCachedPost(id: postId, likesCount: nil, isLiked: false)
        }

        // If offline, queue the action
        if !networkMonitor.isConnected {
            logInfo("Offline - queueing unlike action")
            let action = QueuedAction(
                type: .unlikePost,
                data: ["postId": postId.uuidString]
            )
            offlineQueue.enqueue(action)
            return
        }

        try await client
            .from("post_likes")
            .delete()
            .eq("post_id", value: postId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()

        // Invalidate caches
        cache.invalidate(QueryCache.postLikesKey(postId: postId.uuidString))
        cache.invalidateAllFeeds()

        logSuccess("Post unliked")
    }

    // MARK: - Fetch Likes

    /// Fetch users who liked a post with caching
    func fetchPostLikes(postId: UUID) async throws -> [UserProfile] {
        logInfo("Fetching likes for post: \(postId)")

        // Try cache first
        let cacheKey = QueryCache.postLikesKey(postId: postId.uuidString)
        if let cached: [UserProfile] = cache.get(cacheKey) {
            logSuccess("Cache hit for post likes")
            return cached
        }

        let likes: [PostLike] = try await client
            .from("post_likes")
            .select()
            .eq("post_id", value: postId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        guard !likes.isEmpty else {
            cache.set(cacheKey, value: [], ttl: .postDetails)
            return []
        }

        let userIds = likes.map { $0.userId }
        let profiles = try await fetchProfilesBatched(userIds)

        // Cache the result
        cache.set(cacheKey, value: profiles, ttl: .postDetails)

        logSuccess("Found \(profiles.count) users who liked")
        return profiles
    }

    // MARK: - Add Comment

    /// Add a comment to a post (with offline queue support)
    func addComment(postId: UUID, content: String) async throws -> PostComment {
        guard let userId = SupabaseAuthService.shared.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        // Block links in comments
        if containsLink(content) {
            throw SupabaseError.serverError("Links are not allowed in comments")
        }

        logInfo("Adding comment to post: \(postId)")

        // If offline, queue the action
        if !networkMonitor.isConnected {
            logInfo("Offline - queueing comment action")
            let action = QueuedAction(
                type: .addComment,
                data: [
                    "postId": postId.uuidString,
                    "content": content
                ]
            )
            offlineQueue.enqueue(action)

            // Return temporary comment for UI
            return PostComment(
                id: UUID(),
                postId: postId,
                userId: userId,
                content: content,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        struct NewComment: Encodable {
            let post_id: String
            let user_id: String
            let content: String
        }

        let comment: PostComment = try await client
            .from("post_comments")
            .insert(NewComment(
                post_id: postId.uuidString,
                user_id: userId.uuidString,
                content: content
            ))
            .select()
            .single()
            .execute()
            .value

        // Invalidate post cache (comment count changed)
        cache.invalidate(QueryCache.postDetailsKey(postId: postId.uuidString))

        logSuccess("Comment added: \(comment.id)")
        return comment
    }

    // MARK: - Fetch Comments

    /// Fetch comments for a post with caching
    func fetchComments(postId: UUID) async throws -> [CommentWithAuthor] {
        logInfo("Fetching comments for post: \(postId)")

        // Try cache first
        let cacheKey = "comments:\(postId.uuidString)"
        if let cached: [CommentWithAuthor] = cache.get(cacheKey) {
            logSuccess("Cache hit for comments")
            return cached
        }

        let comments: [PostComment] = try await client
            .from("post_comments")
            .select()
            .eq("post_id", value: postId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value

        guard !comments.isEmpty else {
            cache.set(cacheKey, value: [], ttl: .postDetails)
            return []
        }

        let userIds = Array(Set(comments.map { $0.userId }))
        let profiles = try await fetchProfilesBatched(userIds)

        let commentsWithAuthors = comments.compactMap { comment -> CommentWithAuthor? in
            guard let author = profiles.first(where: { $0.id == comment.userId }) else {
                return nil
            }
            return CommentWithAuthor(id: comment.id, comment: comment, author: author)
        }

        // Cache the result
        cache.set(cacheKey, value: commentsWithAuthors, ttl: .postDetails)

        logSuccess("Found \(commentsWithAuthors.count) comments")
        return commentsWithAuthors
    }

    // MARK: - Delete Comment

    /// Delete a comment
    func deleteComment(commentId: UUID) async throws {
        logInfo("Deleting comment: \(commentId)")

        try await client
            .from("post_comments")
            .delete()
            .eq("id", value: commentId.uuidString)
            .execute()

        // Invalidate caches (including feed so pull-to-refresh fetches fresh counts)
        cache.invalidatePrefix("comments:")
        cache.invalidateAllFeeds()

        logSuccess("Comment deleted")
    }

    // MARK: - Nested Comments & Mentions

    /// Fetch comments with nested replies (1 level deep)
    func fetchCommentsWithReplies(postID: UUID) async throws -> [PostComment] {
        logInfo("Fetching comments with replies for post: \(postID)")

        // First fetch top-level comments (parent_comment_id IS NULL)
        let topLevelComments: [PostComment] = try await client
            .from("post_comments")
            .select()
            .eq("post_id", value: postID.uuidString)
            .filter("parent_comment_id", operator: "is", value: "null")
            .order("created_at", ascending: true)
            .execute()
            .value


        guard !topLevelComments.isEmpty else {
            return []
        }

        // Fetch all replies for these comments
        let commentIds = topLevelComments.map { $0.id.uuidString }
        let replies: [PostComment] = try await client
            .from("post_comments")
            .select()
            .in("parent_comment_id", values: commentIds)
            .order("created_at", ascending: true)
            .execute()
            .value


        // Fetch author profiles for all comments
        let allCommentIds = topLevelComments.map { $0.id } + replies.map { $0.id }
        let allUserIds = Array(Set((topLevelComments + replies).map { $0.userId }))
        let profiles = try await fetchProfilesBatched(allUserIds)

        // Group replies by parent comment ID
        var repliesByParent: [UUID: [PostComment]] = [:]
        for reply in replies {
            guard let parentID = reply.parentCommentID else { continue }
            if repliesByParent[parentID] == nil {
                repliesByParent[parentID] = []
            }
            // Attach author to reply
            var replyWithAuthor = reply
            replyWithAuthor.author = profiles.first(where: { $0.id == reply.userId })
            repliesByParent[parentID]?.append(replyWithAuthor)
        }

        // Attach replies and authors to top-level comments
        let commentsWithReplies = topLevelComments.map { comment -> PostComment in
            var mutableComment = comment
            mutableComment.author = profiles.first(where: { $0.id == comment.userId })
            mutableComment.replies = repliesByParent[comment.id] ?? []
            return mutableComment
        }

        logSuccess("Found \(commentsWithReplies.count) top-level comments with \(replies.count) total replies")
        return commentsWithReplies
    }

    /// Post a comment with optional parent for replies and mentions
    func postComment(
        postID: UUID,
        content: String,
        parentCommentID: UUID? = nil,
        mentionedUserIDs: [UUID] = []
    ) async throws -> PostComment {
        guard let userId = SupabaseAuthService.shared.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        // Block links in comments and replies
        if containsLink(content) {
            throw SupabaseError.serverError("Links are not allowed in comments")
        }

        logInfo("Posting comment to post: \(postID), parent: \(parentCommentID?.uuidString ?? "none"), mentions: \(mentionedUserIDs.count)")

        // Create comment
        struct NewComment: Encodable {
            let post_id: String
            let user_id: String
            let content: String
            let parent_comment_id: String?
        }

        let comment: PostComment = try await client
            .from("post_comments")
            .insert(NewComment(
                post_id: postID.uuidString,
                user_id: userId.uuidString,
                content: content,
                parent_comment_id: parentCommentID?.uuidString
            ))
            .select()
            .single()
            .execute()
            .value

        // Save mentions if any
        if !mentionedUserIDs.isEmpty {
            try await saveMentions(commentID: comment.id, mentionedUserIDs: mentionedUserIDs)
        }

        // Invalidate caches (including feed so pull-to-refresh fetches fresh counts)
        cache.invalidate(QueryCache.postDetailsKey(postId: postID.uuidString))
        cache.invalidatePrefix("comments:")
        cache.invalidateAllFeeds()

        logSuccess("Comment posted: \(comment.id)")
        return comment
    }

    /// Save comment mentions
    private func saveMentions(commentID: UUID, mentionedUserIDs: [UUID]) async throws {
        struct NewMention: Encodable {
            let comment_id: String
            let mentioned_user_id: String
        }

        let mentions = mentionedUserIDs.map { userID in
            NewMention(comment_id: commentID.uuidString, mentioned_user_id: userID.uuidString)
        }

        try await client
            .from("comment_mentions")
            .insert(mentions)
            .execute()

        logInfo("Saved \(mentions.count) mention(s)")
    }

    /// Parse @mentions from comment text
    func parseMentions(from text: String) -> [String] {
        let pattern = "@([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    /// Search users by username for autocomplete
    func searchUsersByUsername(query: String, limit: Int = 10) async throws -> [UserProfile] {
        logInfo("Searching users by username: \(query)")

        let profiles: [UserProfile] = try await client
            .from("profiles")
            .select()
            .ilike("username", value: "%\(query)%")
            .limit(limit)
            .execute()
            .value

        logSuccess("Found \(profiles.count) matching users")
        return profiles
    }

    // MARK: - Helper Methods
    // Note: fetchProfilesBatched is inherited from BaseRepository

    /// Check if text contains a URL/link
    private func containsLink(_ text: String) -> Bool {
        // Patterns to detect URLs
        let patterns = [
            // http(s) URLs
            "https?://[^\\s]+",
            // www. URLs
            "www\\.[^\\s]+",
            // Common TLDs with domain pattern (e.g., example.com, site.io)
            "[a-zA-Z0-9-]+\\.(com|org|net|io|co|app|dev|ai|xyz|info|me|tv|cc)[^\\s]*"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }

        return false
    }
}
