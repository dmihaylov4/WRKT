import Foundation
import SwiftData

/// SwiftData model for caching workout posts locally
@Model
final class CachedPost {
    @Attribute(.unique) var id: String
    var userId: String
    var caption: String?
    var workoutDataJSON: String // Store as JSON string
    var imageUrls: [String]
    var visibility: String
    var likesCount: Int
    var commentsCount: Int
    var isLiked: Bool
    var createdAt: Date
    var updatedAt: Date
    var cachedAt: Date

    // Author info (denormalized for performance)
    var authorUsername: String
    var authorDisplayName: String?
    var authorAvatarUrl: String?

    init(
        id: String,
        userId: String,
        caption: String?,
        workoutDataJSON: String,
        imageUrls: [String],
        visibility: String,
        likesCount: Int,
        commentsCount: Int,
        isLiked: Bool,
        createdAt: Date,
        updatedAt: Date,
        authorUsername: String,
        authorDisplayName: String?,
        authorAvatarUrl: String?
    ) {
        self.id = id
        self.userId = userId
        self.caption = caption
        self.workoutDataJSON = workoutDataJSON
        self.imageUrls = imageUrls
        self.visibility = visibility
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.isLiked = isLiked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cachedAt = Date()
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorAvatarUrl = authorAvatarUrl
    }

    /// Check if cache is expired (5 minutes TTL)
    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > 300 // 5 minutes
    }
}

// MARK: - Conversion Extensions
extension CachedPost {
    /// Convert from PostWithAuthor to CachedPost
    static func from(_ post: PostWithAuthor) -> CachedPost {
        // Encode workout data as JSON string
        let workoutDataJSON: String
        if let data = try? JSONEncoder().encode(post.post.workoutData),
           let jsonString = String(data: data, encoding: .utf8) {
            workoutDataJSON = jsonString
        } else {
            workoutDataJSON = "{}"
        }

        // Convert PostImage array to legacy string URLs for caching
        let imageUrls = post.post.images?.map { $0.storagePath } ?? []

        return CachedPost(
            id: post.id.uuidString,
            userId: post.post.userId.uuidString,
            caption: post.post.caption,
            workoutDataJSON: workoutDataJSON,
            imageUrls: imageUrls,
            visibility: post.post.visibility.rawValue,
            likesCount: post.post.likesCount,
            commentsCount: post.post.commentsCount,
            isLiked: post.isLikedByCurrentUser,
            createdAt: post.post.createdAt,
            updatedAt: post.post.updatedAt,
            authorUsername: post.author.username,
            authorDisplayName: post.author.displayName,
            authorAvatarUrl: post.author.avatarUrl
        )
    }

    /// Convert CachedPost to PostWithAuthor
    func toPostWithAuthor() -> PostWithAuthor? {
        guard let postId = UUID(uuidString: id),
              let userId = UUID(uuidString: self.userId) else {
            return nil
        }

        // Decode workout data from JSON string
        guard let jsonData = workoutDataJSON.data(using: .utf8),
              let workoutData = try? JSONDecoder().decode(CompletedWorkout.self, from: jsonData),
              let postVisibility = PostVisibility(rawValue: visibility) else {
            return nil
        }

        // Convert legacy imageUrls to PostImage format
        let images: [PostImage]? = imageUrls.isEmpty ? nil : imageUrls.map { url in
            PostImage(storagePath: url, isPublic: true)
        }

        let post = WorkoutPost(
            id: postId,
            userId: userId,
            caption: caption,
            workoutData: workoutData,
            images: images,
            visibility: postVisibility,
            likesCount: likesCount,
            commentsCount: commentsCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let author = UserProfile(
            id: userId,
            username: authorUsername,
            displayName: authorDisplayName,
            avatarUrl: authorAvatarUrl,
            bio: nil,
            isPrivate: false,
            autoPostPRs: true,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        return PostWithAuthor(
            id: postId,
            post: post,
            author: author,
            isLikedByCurrentUser: isLiked
        )
    }
}
