//
//  PostDetailViewModel.swift
//  WRKT
//
//  ViewModel for detailed view of a workout post with comments
//

import Foundation

@MainActor
@Observable
final class PostDetailViewModel {
    var post: PostWithAuthor
    var comments: [PostComment] = []  // Changed to PostComment (now includes author and replies)
    var commentText = ""
    var isLoadingComments = false
    var isPostingComment = false
    var isRefreshingCardioData = false
    var error: String?

    // NEW: Reply functionality
    var replyingTo: PostComment? = nil

    // NEW: Mention autocomplete
    var mentionSuggestions: [UserProfile] = []

    private let postRepository: PostRepository
    private let authService: SupabaseAuthService

    init(
        post: PostWithAuthor,
        postRepository: PostRepository,
        authService: SupabaseAuthService
    ) {
        self.post = post
        self.postRepository = postRepository
        self.authService = authService
    }

    func loadComments() async {
        guard !isLoadingComments else { return }

        isLoadingComments = true
        error = nil

        do {
            
           
            comments = try await postRepository.fetchCommentsWithReplies(postID: post.post.id)
           
            isLoadingComments = false
        } catch {
            
            self.error = error.localizedDescription
            isLoadingComments = false
        }
    }

    func postComment() async {
      

        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            
            return
        }

        guard !isPostingComment else {
            
            return
        }

       
        guard let currentUser = authService.currentUser,
              let currentProfile = currentUser.profile else {
            
            return
        }

        
        isPostingComment = true
        error = nil

        do {
            // Parse mentions from comment text
            let mentionedUsernames = postRepository.parseMentions(from: commentText)
            var mentionedUserIDs: [UUID] = []
            

            // Resolve usernames to user IDs
            for username in mentionedUsernames {
                if let users = try? await postRepository.searchUsersByUsername(query: username, limit: 1),
                   let user = users.first {
                    mentionedUserIDs.append(user.id)
                }
            }

            // Post comment with optional parent and mentions
            
            let newComment = try await postRepository.postComment(
                postID: post.post.id,
                content: commentText.trimmingCharacters(in: .whitespacesAndNewlines),
                parentCommentID: replyingTo?.id,
                mentionedUserIDs: mentionedUserIDs
            )
            

            // Reload comments to get updated structure
            
            await loadComments()

            // Update comment count
            var updatedPost = post.post
            updatedPost.commentsCount += 1
            post = PostWithAuthor(
                id: post.id,
                post: updatedPost,
                author: post.author,
                isLikedByCurrentUser: post.isLikedByCurrentUser
            )

            commentText = ""
            replyingTo = nil
            mentionSuggestions = []
            isPostingComment = false
            
            Haptics.success()
        } catch {
            
            self.error = error.localizedDescription
            isPostingComment = false
            Haptics.error()
        }
    }

    func deleteComment(_ comment: PostComment) async {
        do {
            try await postRepository.deleteComment(commentId: comment.id)

            // Reload comments to reflect deletion
            await loadComments()

            // Update comment count
            var updatedPost = post.post
            updatedPost.commentsCount = max(0, updatedPost.commentsCount - 1)
            post = PostWithAuthor(
                id: post.id,
                post: updatedPost,
                author: post.author,
                isLikedByCurrentUser: post.isLikedByCurrentUser
            )

            Haptics.success()
        } catch {
            self.error = "Failed to delete comment"
            Haptics.error()
        }
    }

    // NEW: Detect @mention typing and show autocomplete
    func detectMentionQuery(in text: String) {
        // Find last @ symbol
        if let lastAtIndex = text.lastIndex(of: "@") {
            let queryStart = text.index(after: lastAtIndex)
            let query = String(text[queryStart...])

            // Only show autocomplete if query doesn't contain spaces and isn't empty
            if !query.contains(" ") && !query.isEmpty {
                Task {
                    await searchUsers(query: query)
                }
            } else {
                mentionSuggestions = []
            }
        } else {
            mentionSuggestions = []
        }
    }

    // NEW: Search users for mention autocomplete
    private func searchUsers(query: String) async {
        do {
            mentionSuggestions = try await postRepository.searchUsersByUsername(query: query, limit: 10)
        } catch {
            
            mentionSuggestions = []
        }
    }

    // NEW: Insert selected mention into comment text
    func insertMention(_ user: UserProfile) {
        if let lastAtIndex = commentText.lastIndex(of: "@") {
            let beforeAt = commentText[..<lastAtIndex]
            commentText = "\(beforeAt)@\(user.username) "
        }
        mentionSuggestions = []
    }

    // NEW: Start replying to a comment
    func startReply(to comment: PostComment) {
        replyingTo = comment
    }

    // NEW: Cancel reply
    func cancelReply() {
        replyingTo = nil
    }

    func toggleLike() async {
        guard let currentUserId = authService.currentUser?.id else { return }

        // Optimistic update
        let newIsLiked = !post.isLikedByCurrentUser
        var updatedPost = post.post

        if newIsLiked {
            updatedPost.likesCount += 1
        } else {
            updatedPost.likesCount = max(0, updatedPost.likesCount - 1)
        }

        post = PostWithAuthor(
            id: post.id,
            post: updatedPost,
            author: post.author,
            isLikedByCurrentUser: newIsLiked
        )

        // Perform actual API call
        do {
            if post.isLikedByCurrentUser {
                try await postRepository.likePost(post.post.id)
                Haptics.success()
            } else {
                try await postRepository.unlikePost(post.post.id)
                Haptics.light()
            }
        } catch {
            // Revert on error
            let revertedIsLiked = !newIsLiked
            var revertedPost = post.post

            if revertedIsLiked {
                revertedPost.likesCount += 1
            } else {
                revertedPost.likesCount = max(0, revertedPost.likesCount - 1)
            }

            post = PostWithAuthor(
                id: post.id,
                post: revertedPost,
                author: post.author,
                isLikedByCurrentUser: revertedIsLiked
            )

            self.error = "Failed to update like"
            Haptics.error()
        }
    }

    // MARK: - Cardio Data Refresh

    /// Check if the current user can refresh cardio data for this post
    var canRefreshCardioData: Bool {
        guard let currentUserId = authService.currentUser?.id else { return false }
        // Only the post author can refresh (they have HealthKit access)
        guard post.post.userId == currentUserId else { return false }
        // Must have a HealthKit UUID to refresh from
        return post.post.workoutData.matchedHealthKitUUID != nil
    }

    /// Refresh cardio splits and HR zones from HealthKit
    func refreshCardioData() async {
        guard canRefreshCardioData else { return }
        guard let healthKitUUID = post.post.workoutData.matchedHealthKitUUID else { return }

        isRefreshingCardioData = true

        let totalDuration = post.post.workoutData.matchedHealthKitDuration ?? 0
        let (splits, hrZones) = await HealthKitManager.shared.fetchCardioDataByHealthKitUUID(healthKitUUID, totalDuration: totalDuration)

        // Update the local post with fresh data
        var updatedWorkout = post.post.workoutData
        if let splits = splits {
            updatedWorkout.cardioSplits = splits
        }
        if let hrZones = hrZones {
            updatedWorkout.cardioHRZones = hrZones
        }

        // Create updated post with the new workout data
        let updatedPostData = WorkoutPost(
            id: post.post.id,
            userId: post.post.userId,
            caption: post.post.caption,
            workoutData: updatedWorkout,
            images: post.post.images,
            visibility: post.post.visibility,
            likesCount: post.post.likesCount,
            commentsCount: post.post.commentsCount,
            createdAt: post.post.createdAt,
            updatedAt: post.post.updatedAt
        )

        post = PostWithAuthor(
            id: post.id,
            post: updatedPostData,
            author: post.author,
            isLikedByCurrentUser: post.isLikedByCurrentUser
        )

        isRefreshingCardioData = false

        if splits != nil || hrZones != nil {
            Haptics.success()
        }
    }
}
