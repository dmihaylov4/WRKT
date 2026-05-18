//
//  FeedViewModel.swift
//  WRKT
//
//  ViewModel for social feed with pagination, realtime updates, and offline support
//

import Foundation
import CoreLocation

@MainActor
@Observable
final class FeedViewModel {
    var posts: [PostWithAuthor] = []
    var isLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var hasMorePages = true
    var error: UserFriendlyError?
    var newPostsAvailable = 0 // Count of new posts available to load

    private let postRepository: PostRepository
    private let authService: SupabaseAuthService
    private let realtimeService: RealtimeService
    private let networkMonitor = NetworkMonitor.shared
    private let offlineQueue = OfflineQueueManager.shared
    private let retryManager = RetryManager.shared
    private let errorHandler = ErrorHandler.shared
    private let imageUploadService = ImageUploadService()
    private var cursor: String? = nil // Composite cursor: created_at|id
    private let pageSize = 20
    private var realtimeChannelId: String?
    private struct PendingDeletion {
        let post: PostWithAuthor
        let originalIndex: Int
        let task: Task<Void, Never>
    }
    @ObservationIgnored private var pendingDeletions: [UUID: PendingDeletion] = [:]
    @ObservationIgnored private var backfillTasks: Set<UUID> = []

    var isOnline: Bool {
        networkMonitor.isConnected
    }

    var queuedActionCount: Int {
        offlineQueue.queueCount
    }

    init(postRepository: PostRepository, authService: SupabaseAuthService, realtimeService: RealtimeService) {
        self.postRepository = postRepository
        self.authService = authService
        self.realtimeService = realtimeService

        NotificationCenter.default.addObserver(
            forName: .postCommentCountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let postId = notification.userInfo?["postId"] as? UUID,
                  let count = notification.userInfo?["count"] as? Int,
                  let index = self.posts.firstIndex(where: { $0.post.id == postId }) else { return }
            var updatedWorkoutPost = self.posts[index].post
            updatedWorkoutPost.commentsCount = count
            let existing = self.posts[index]
            self.posts[index] = PostWithAuthor(
                id: existing.id,
                post: updatedWorkoutPost,
                author: existing.author,
                isLikedByCurrentUser: existing.isLikedByCurrentUser
            )
        }
    }

    deinit {
        // Don't create async tasks in deinit as they create retain cycles
        // cleanup() will be called from the view's onDisappear
        for (_, pendingDeletion) in pendingDeletions {
            pendingDeletion.task.cancel()
        }
    }

    func loadInitialFeed() async {
        guard !isLoading, !isRefreshing else {
            return
        }
        guard let currentUserId = authService.currentUser?.id else {
            return
        }

        isLoading = true
        error = nil
        cursor = nil

        // Use retry manager for automatic retry
        let result = await retryManager.fetchWithRetry {
            try await self.postRepository.fetchFeed(userId: currentUserId, limit: self.pageSize, cursor: nil)
        }

        switch result {
        case .success(let feedResult):
            posts = feedResult.posts
            hasMorePages = feedResult.hasMore
            cursor = feedResult.nextCursor

            error = nil
            isLoading = false

        case .failure(let err, let attempts):
            let userError = errorHandler.handleError(err, context: .feed)
            errorHandler.logError(userError, context: .feed)
            self.error = userError
            isLoading = false
            Haptics.error()
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }
        guard let currentUserId = authService.currentUser?.id else {
            return
        }

        isRefreshing = true
        error = nil
        cursor = nil
        newPostsAvailable = 0 // Reset new posts counter

        // Use quick retry for manual refresh (user initiated)
        let result = await retryManager.fetchWithRetry(config: .quick) {
            try await self.postRepository.fetchFeed(userId: currentUserId, limit: self.pageSize, cursor: nil)
        }

        switch result {
        case .success(let feedResult):
            posts = feedResult.posts
            hasMorePages = feedResult.hasMore
            cursor = feedResult.nextCursor

            error = nil
            isRefreshing = false
            Haptics.success()

        case .failure(let err, let attempts):
            let userError = errorHandler.handleError(err, context: .feed)
            errorHandler.logError(userError, context: .feed)
            self.error = userError
            isRefreshing = false
            Haptics.error()
        }
    }

    /// Prefetch next page when user scrolls to 80% of current content
    func loadMoreIfNeeded(currentPost: PostWithAuthor) async {
        guard !isLoadingMore, !isLoading, hasMorePages else { return }

        // Calculate threshold index (80% of posts)
        let thresholdIndex = (Double(posts.count) * 0.8).safeInt

        if let currentIndex = posts.firstIndex(where: { $0.id == currentPost.id }),
           currentIndex >= thresholdIndex {
            await loadMore()
        }
    }

    private func loadMore() async {
        guard let currentUserId = authService.currentUser?.id else { return }
        guard let cursor = cursor else {
            return
        }

        isLoadingMore = true

        do {
            let result = try await postRepository.fetchFeed(
                userId: currentUserId,
                limit: pageSize,
                cursor: cursor
            )

            posts.append(contentsOf: result.posts)
            hasMorePages = result.hasMore
            self.cursor = result.nextCursor

            isLoadingMore = false
        } catch {
            self.error = errorHandler.handleError(error, context: .feed)
            isLoadingMore = false
        }
    }

    private var likingInFlight: Set<UUID> = []

    func toggleLike(for post: PostWithAuthor) async {
        guard !likingInFlight.contains(post.id) else { return }
        guard let currentUserId = authService.currentUser?.id else { return }
        likingInFlight.insert(post.id)
        defer { likingInFlight.remove(post.id) }

        // Optimistic update
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            let currentPost = posts[index]
            let newLikesCount = currentPost.isLikedByCurrentUser
                ? max(0, currentPost.post.likesCount - 1)
                : currentPost.post.likesCount + 1

            var updatedWorkoutPost = currentPost.post
            updatedWorkoutPost.likesCount = newLikesCount

            var updatedPost = currentPost
            updatedPost = PostWithAuthor(
                id: currentPost.id,
                post: updatedWorkoutPost,
                author: currentPost.author,
                isLikedByCurrentUser: !currentPost.isLikedByCurrentUser
            )

            posts[index] = updatedPost

            // Perform actual API call (or queue if offline)
            do {
                if updatedPost.isLikedByCurrentUser {
                    try await postRepository.likePost(post.post.id)
                    Haptics.success()
                } else {
                    try await postRepository.unlikePost(post.post.id)
                    Haptics.light()
                }
            } catch {
                print("❌ [Feed] Like error: \(error)")

                // Revert on error
                let revertedPost = posts[index]
                let revertedLikesCount = revertedPost.isLikedByCurrentUser
                    ? max(0, revertedPost.post.likesCount - 1)
                    : revertedPost.post.likesCount + 1

                var revertedWorkoutPost = revertedPost.post
                revertedWorkoutPost.likesCount = revertedLikesCount

                posts[index] = PostWithAuthor(
                    id: revertedPost.id,
                    post: revertedWorkoutPost,
                    author: revertedPost.author,
                    isLikedByCurrentUser: !revertedPost.isLikedByCurrentUser
                )

                self.error = UserFriendlyError(
                    title: "Like Failed",
                    message: "Failed to update like",
                    suggestion: "Try again",
                    isRetryable: true
                )
                Haptics.error()
            }
        }
    }

    func deletePost(_ post: PostWithAuthor) async {
        // Store the post and its index for undo
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let deletedPost = posts[index]

        // Optimistically remove from UI
        posts.remove(at: index)
        Haptics.warning()

        let deleteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }

                try await self.postRepository.deletePost(post.post.id)
                self.pendingDeletions.removeValue(forKey: post.id)
            } catch is CancellationError {
                // Undo cancelled the pending delete.
            } catch {
                guard let self else { return }

                self.pendingDeletions.removeValue(forKey: post.id)
                self.restorePostInFeed(deletedPost, at: index)
                self.error = UserFriendlyError(
                    title: "Delete Failed",
                    message: "Failed to delete post",
                    suggestion: "Try again",
                    isRetryable: true,
                    originalError: error
                )
                Haptics.error()
            }
        }

        pendingDeletions[post.id] = PendingDeletion(
            post: deletedPost,
            originalIndex: index,
            task: deleteTask
        )

        AppNotificationManager.shared.showPostDeleted {
            self.undoDeletePost(post.id)
        }
    }

    /// Restore deleted post (undo operation)
    private func undoDeletePost(_ postId: UUID) {
        guard let pendingDeletion = pendingDeletions.removeValue(forKey: postId) else { return }

        pendingDeletion.task.cancel()
        restorePostInFeed(pendingDeletion.post, at: pendingDeletion.originalIndex)
        Haptics.soft()
    }

    private func restorePostInFeed(_ post: PostWithAuthor, at index: Int) {
        guard !posts.contains(where: { $0.id == post.id }) else { return }

        if index <= posts.count {
            posts.insert(post, at: index)
        } else {
            posts.append(post)
        }
    }

    func updatePost(_ post: PostWithAuthor, caption: String?, visibility: PostVisibility) async {
        // Capture the values we need before the async call
        let postId = post.post.id
        let originalPostId = post.id
        let captionValue = caption
        let visibilityValue = visibility

        do {
            try await postRepository.updatePost(postId, caption: captionValue, visibility: visibilityValue)

            // Update the post in the local feed using the index we find
            if let index = posts.firstIndex(where: { $0.id == originalPostId }) {
                var updatedWorkoutPost = posts[index].post
                updatedWorkoutPost.caption = captionValue
                updatedWorkoutPost.visibility = visibilityValue
                updatedWorkoutPost.updatedAt = Date()

                posts[index] = PostWithAuthor(
                    id: posts[index].id,
                    post: updatedWorkoutPost,
                    author: posts[index].author,
                    isLikedByCurrentUser: posts[index].isLikedByCurrentUser
                )
            }

            Haptics.success()
        } catch {
            self.error = UserFriendlyError(
                title: "Update Failed",
                message: "Failed to update post",
                suggestion: "Try again",
                isRetryable: true,
                originalError: error
            )
            Haptics.error()
        }
    }

    func backfillRouteMap(for post: PostWithAuthor) async -> Bool {
        guard let currentUserId = authService.currentUser?.id,
              post.post.userId == currentUserId,
              post.post.workoutData.isCardioWorkout,
              let healthKitUUID = post.post.workoutData.matchedHealthKitUUID else {
            return false
        }

        guard !backfillTasks.contains(post.post.id) else {
            return false
        }

        backfillTasks.insert(post.post.id)
        defer { backfillTasks.remove(post.post.id) }

        guard let hkWorkout = try? await HealthKitManager.shared.fetchWorkoutByUUID(healthKitUUID).first else {
            return false
        }

        let routePoints = try? await HealthKitManager.shared.fetchRouteWithHeartRate(for: hkWorkout)
        let coordinates: [CLLocationCoordinate2D]
        let hrValues: [Double]?

        if let points = routePoints, points.count > 1 {
            coordinates = points.map { $0.coordinate }
            hrValues = points.compactMap { $0.hr }.isEmpty ? nil : points.map { $0.hr ?? .nan }
        } else if let locations = try? await HealthKitManager.shared.fetchRoute(for: hkWorkout),
                  locations.count > 1 {
            coordinates = locations.map { $0.coordinate }
            hrValues = nil
        } else {
            return false
        }

        guard let snapshot = try? await MapSnapshotService.shared.generateRouteSnapshot(
            coordinates: coordinates,
            hrValues: hrValues
        ) else {
            return false
        }

        guard let uploadedImages = try? await imageUploadService.uploadWorkoutImages(
            images: [snapshot],
            userId: currentUserId,
            isPublic: [true]
        ), !uploadedImages.isEmpty else {
            return false
        }

        let allImages = (post.post.images ?? []) + uploadedImages

        do {
            try await postRepository.updatePostImages(post.post.id, images: allImages)
        } catch {
            return false
        }

        if let index = posts.firstIndex(where: { $0.post.id == post.post.id }) {
            var updatedWorkoutPost = posts[index].post
            updatedWorkoutPost.images = allImages
            updatedWorkoutPost.updatedAt = Date()

            posts[index] = PostWithAuthor(
                id: posts[index].id,
                post: updatedWorkoutPost,
                author: posts[index].author,
                isLikedByCurrentUser: posts[index].isLikedByCurrentUser
            )
        }

        return true
    }

    // MARK: - Offline Support

    /// Sync queued actions when back online
    func syncQueuedActions() async {
        guard let currentUserId = authService.currentUser?.id else { return }

        let dependencies = AppDependencies.shared
        await offlineQueue.syncQueue(dependencies: dependencies)

        // Refresh feed after sync
        if offlineQueue.queueCount == 0 {
            await refresh()
        }
    }

    // MARK: - Realtime Updates

    /// Subscribe to realtime updates for new posts
    func subscribeToRealtimeUpdates() async {
        guard let currentUserId = authService.currentUser?.id else {
            return
        }

        do {
            // Subscribe to new posts
            let channelId = try await realtimeService.subscribeToNewPosts(userId: currentUserId) { [weak self] newPost in
                guard let self = self else { return }
                // FIXED: Use weak self inside Task to avoid retain cycle
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.handleNewPost(newPost)
                }
            }

            realtimeChannelId = channelId
        } catch {
        }
    }

    /// Handle a new post received via realtime
    private func handleNewPost(_ newPost: WorkoutPost) async {
        // Don't show our own posts as new (they're already in the feed)
        guard newPost.userId != authService.currentUser?.id else {
            return
        }

        // Increment counter for banner
        newPostsAvailable += 1

        Haptics.light()
    }

    /// Load the new posts that are available
    func loadNewPosts() async {
        guard newPostsAvailable > 0 else { return }

        newPostsAvailable = 0

        // Simply refresh the feed
        await refresh()
    }

    /// Cleanup realtime subscriptions
    func cleanup() async {
        if let channelId = realtimeChannelId {
            await realtimeService.unsubscribe(channelId: channelId)
            realtimeChannelId = nil
        }
    }
}
