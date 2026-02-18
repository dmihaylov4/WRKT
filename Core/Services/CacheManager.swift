import Foundation
import SwiftData

/// Manages local cache using SwiftData
@MainActor
final class CacheManager {
    static let shared = CacheManager()

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    private init() {
        let schema = Schema([
            CachedPost.self,
            CachedProfile.self,
            CachedNotification.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("Failed to initialize CacheManager: \(error)")
        }
    }

    // MARK: - Posts

    /// Cache a list of posts
    func cachePosts(_ posts: [PostWithAuthor]) {
        for post in posts {
            let cachedPost = CachedPost.from(post)
            modelContext.insert(cachedPost)
        }
        saveContext()
    }

    /// Fetch cached posts (with expired check)
    func fetchCachedPosts(limit: Int = 20, includeExpired: Bool = false) -> [PostWithAuthor] {
        let descriptor = FetchDescriptor<CachedPost>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let cachedPosts = try? modelContext.fetch(descriptor) else {
            return []
        }

        let validPosts = includeExpired ? cachedPosts : cachedPosts.filter { !$0.isExpired }
        return validPosts.prefix(limit).compactMap { $0.toPostWithAuthor() }
    }

    /// Update a cached post (like count, comment count)
    func updateCachedPost(id: UUID, likesCount: Int? = nil, commentsCount: Int? = nil, isLiked: Bool? = nil) {
        do {
            let predicate = #Predicate<CachedPost> { post in
                post.id == id.uuidString
            }
            let descriptor = FetchDescriptor(predicate: predicate)

            let cachedPosts = try modelContext.fetch(descriptor)
            guard let cachedPost = cachedPosts.first else {
                return
            }

            if let likesCount = likesCount {
                cachedPost.likesCount = likesCount
            }
            if let commentsCount = commentsCount {
                cachedPost.commentsCount = commentsCount
            }
            if let isLiked = isLiked {
                cachedPost.isLiked = isLiked
            }

            cachedPost.cachedAt = Date() // Refresh cache timestamp
            try modelContext.save()
        } catch {
            // Don't propagate the error - cache updates are non-critical
        }
    }

    /// Delete a cached post
    func deleteCachedPost(id: UUID) {
        do {
            let predicate = #Predicate<CachedPost> { post in
                post.id == id.uuidString
            }
            let descriptor = FetchDescriptor(predicate: predicate)

            let cachedPosts = try modelContext.fetch(descriptor)

            guard !cachedPosts.isEmpty else {
                return
            }

            for post in cachedPosts {
                modelContext.delete(post)
            }

            try modelContext.save()
        } catch {
            // Don't propagate the error - cache deletion is non-critical
        }
    }

    /// Clear all cached posts
    func clearAllPosts() {
        try? modelContext.delete(model: CachedPost.self)
        saveContext()
    }

    // MARK: - Profiles

    /// Cache a user profile
    func cacheProfile(_ profile: UserProfile) {
        // Check if profile already exists
        let predicate = #Predicate<CachedProfile> { cachedProfile in
            cachedProfile.id == profile.id.uuidString
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        if let existingProfiles = try? modelContext.fetch(descriptor),
           let existingProfile = existingProfiles.first {
            // Update existing
            existingProfile.username = profile.username
            existingProfile.displayName = profile.displayName
            existingProfile.avatarUrl = profile.avatarUrl
            existingProfile.bio = profile.bio
            existingProfile.isPrivate = profile.isPrivate
            existingProfile.updatedAt = profile.updatedAt
            existingProfile.cachedAt = Date()
        } else {
            // Insert new
            let cachedProfile = CachedProfile.from(profile)
            modelContext.insert(cachedProfile)
        }
        saveContext()
    }

    /// Fetch a cached profile by ID
    func fetchCachedProfile(id: UUID, includeExpired: Bool = false) -> UserProfile? {
        let predicate = #Predicate<CachedProfile> { profile in
            profile.id == id.uuidString
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let cachedProfiles = try? modelContext.fetch(descriptor),
              let cachedProfile = cachedProfiles.first else {
            return nil
        }

        // Check if expired
        if !includeExpired && cachedProfile.isExpired {
            return nil
        }

        return cachedProfile.toUserProfile()
    }

    /// Clear all cached profiles
    func clearAllProfiles() {
        try? modelContext.delete(model: CachedProfile.self)
        saveContext()
    }

    // MARK: - Notifications

    /// Cache a list of notifications
    func cacheNotifications(_ notifications: [NotificationWithActor]) {
        for notification in notifications {
            let cachedNotification = CachedNotification.from(notification)
            modelContext.insert(cachedNotification)
        }
        saveContext()
    }

    /// Fetch cached notifications (with expired check)
    func fetchCachedNotifications(userId: UUID, limit: Int = 50, includeExpired: Bool = false) -> [NotificationWithActor] {
        let predicate = #Predicate<CachedNotification> { notification in
            notification.userId == userId.uuidString
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let cachedNotifications = try? modelContext.fetch(descriptor) else {
            return []
        }

        let validNotifications = includeExpired ? cachedNotifications : cachedNotifications.filter { !$0.isExpired }
        return validNotifications.prefix(limit).compactMap { $0.toNotificationWithActor() }
    }

    /// Update a cached notification (mark as read)
    func updateCachedNotification(id: UUID, read: Bool) {
        let predicate = #Predicate<CachedNotification> { notification in
            notification.id == id.uuidString
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let cachedNotifications = try? modelContext.fetch(descriptor),
              let cachedNotification = cachedNotifications.first else {
            return
        }

        cachedNotification.read = read
        cachedNotification.cachedAt = Date()
        saveContext()
    }

    /// Clear all cached notifications
    func clearAllNotifications() {
        try? modelContext.delete(model: CachedNotification.self)
        saveContext()
    }

    // MARK: - Cache Management

    /// Clear all expired cache entries
    func clearExpiredCache() {
        // Clear expired posts
        let postDescriptor = FetchDescriptor<CachedPost>()
        if let posts = try? modelContext.fetch(postDescriptor) {
            for post in posts where post.isExpired {
                modelContext.delete(post)
            }
        }

        // Clear expired profiles
        let profileDescriptor = FetchDescriptor<CachedProfile>()
        if let profiles = try? modelContext.fetch(profileDescriptor) {
            for profile in profiles where profile.isExpired {
                modelContext.delete(profile)
            }
        }

        // Clear expired notifications
        let notificationDescriptor = FetchDescriptor<CachedNotification>()
        if let notifications = try? modelContext.fetch(notificationDescriptor) {
            for notification in notifications where notification.isExpired {
                modelContext.delete(notification)
            }
        }

        saveContext()
    }

    /// Clear all cache
    func clearAllCache() {
        clearAllPosts()
        clearAllProfiles()
        clearAllNotifications()
    }

    /// Get cache statistics
    func getCacheStats() -> (posts: Int, profiles: Int, notifications: Int) {
        let postCount = (try? modelContext.fetchCount(FetchDescriptor<CachedPost>())) ?? 0
        let profileCount = (try? modelContext.fetchCount(FetchDescriptor<CachedProfile>())) ?? 0
        let notificationCount = (try? modelContext.fetchCount(FetchDescriptor<CachedNotification>())) ?? 0
        return (postCount, profileCount, notificationCount)
    }

    // MARK: - Private Helpers

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
        }
    }
}
