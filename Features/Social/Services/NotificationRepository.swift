import Foundation
import Supabase

/// Repository for managing notifications with query optimization
@MainActor
final class NotificationRepository: BaseRepository<AppNotification>, NotificationRepositoryProtocol {

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        super.init(
            tableName: "notifications",
            logPrefix: "Notifications",
            client: client
        )
    }

    // MARK: - Fetch Notifications

    /// Fetch notifications for a user with actor profiles and caching
    func fetchNotifications(userId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [NotificationWithActor] {
        // Try cache first (only for initial page)
        let cacheKey = QueryCache.notificationsKey(userId: userId.uuidString)
        if offset == 0, let cached: [NotificationWithActor] = cache.get(cacheKey) {
            logSuccess("Cache hit")
            return cached
        }

        // Fetch notifications
        let notifications: [AppNotification] = try await client
            .from("notifications")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        guard !notifications.isEmpty else {
            if offset == 0 {
                cache.set(cacheKey, value: [], ttl: .notifications)
            }
            return []
        }

        // Fetch actor profiles with individual caching
        let actorIds = Array(Set(notifications.map { $0.actorId }))
        let actors = try await fetchProfilesBatched(actorIds)

        // Create lookup dictionary
        let actorMap = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0) })

        // Combine notifications with actors
        let result: [NotificationWithActor] = notifications.compactMap { notification in
            guard let actor = actorMap[notification.actorId] else {
                logWarning("Notification \(notification.id) dropped: actor \(notification.actorId) not found in profiles")
                return nil
            }
            return NotificationWithActor(
                id: notification.id,
                notification: notification,
                actor: actor
            )
        }

        // Cache the result (only for initial page)
        if offset == 0 {
            cache.set(cacheKey, value: result, ttl: .notifications)
        }

        return result
    }

    /// Fetch unread notification count with caching
    func fetchUnreadCount(userId: UUID) async throws -> Int {
        // Try cache first
        let cacheKey = "notifications:unread:\(userId.uuidString)"
        if let cached: Int = cache.get(cacheKey) {
            logSuccess("Cache hit for unread count")
            return cached
        }

        let response: [AppNotification] = try await client
            .from("notifications")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("read", value: false)
            .execute()
            .value

        let count = response.count

        // Cache with short TTL (2 minutes)
        cache.set(cacheKey, value: count, ttl: .notifications)

        return count
    }

    // MARK: - Mark as Read

    /// Mark a notification as read
    func markAsRead(notificationId: UUID) async throws {
        struct UpdateRead: Encodable {
            let read: Bool
        }

        let _: AppNotification = try await client
            .from("notifications")
            .update(UpdateRead(read: true))
            .eq("id", value: notificationId.uuidString)
            .single()
            .execute()
            .value

        // Invalidate notification caches
        cache.invalidateAllNotifications()
    }

    /// Mark all notifications as read for a user
    func markAllAsRead(userId: UUID) async throws {
        struct UpdateRead: Encodable {
            let read: Bool
        }

        let _: [AppNotification] = try await client
            .from("notifications")
            .update(UpdateRead(read: true))
            .eq("user_id", value: userId.uuidString)
            .eq("read", value: false)
            .execute()
            .value

        // Invalidate notification caches
        cache.invalidateAllNotifications()
    }

    // MARK: - Create Notification

    /// Create a notification manually (fallback if triggers don't work)
    func createNotification(userId: UUID, type: NotificationType, actorId: UUID, targetId: UUID?) async throws {
        struct NewNotification: Encodable {
            let user_id: String
            let type: String
            let actor_id: String
            let target_id: String?
            let read: Bool
        }

        // IMPORTANT: Use lowercase UUIDs to match Postgres storage and realtime filters
        let newNotification = NewNotification(
            user_id: userId.uuidString.lowercased(),
            type: type.rawValue,
            actor_id: actorId.uuidString.lowercased(),
            target_id: targetId?.uuidString.lowercased(),
            read: false
        )

        let _: AppNotification = try await client
            .from("notifications")
            .insert(newNotification)
            .select()
            .single()
            .execute()
            .value

        // Invalidate notification caches
        cache.invalidateAllNotifications()

        logSuccess("Created notification: type=\(type.rawValue), userId=\(userId)")
    }

    // MARK: - Delete

    /// Delete a notification
    func deleteNotification(notificationId: UUID) async throws {
        try await client
            .from("notifications")
            .delete()
            .eq("id", value: notificationId.uuidString)
            .execute()

        // Invalidate notification caches
        cache.invalidateAllNotifications()
    }

    /// Delete all notifications for a user
    func deleteAllNotifications(userId: UUID) async throws {
        try await client
            .from("notifications")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()

        // Invalidate notification caches
        cache.invalidateAllNotifications()
    }

    // MARK: - Helper Methods
    // Note: fetchProfilesBatched is inherited from BaseRepository
}

extension Array {
    var empty: Bool {
        isEmpty
    }
}
