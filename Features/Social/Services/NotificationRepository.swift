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
            return []
        }

        let visibleNotifications = await filterVisibleNotifications(notifications)
        guard !visibleNotifications.isEmpty else {
            return []
        }

        // Fetch actor profiles with individual caching
        let actorIds = Array(Set(visibleNotifications.map { $0.actorId }))
        let actors = try await fetchProfilesBatched(actorIds)

        // Create lookup dictionary
        let actorMap = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0) })

        // Combine notifications with actors
        let result: [NotificationWithActor] = visibleNotifications.compactMap { notification in
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

        return result
    }

    /// Fetch unread notification count with caching
    /// - Parameter forceRefresh: bypass the client-side cache and always hit the DB.
    ///   Used by the realtime insert path where a new notification just landed and the
    ///   cached count (TTL 2 min) would otherwise be stale.
    func fetchUnreadCount(userId: UUID, forceRefresh: Bool = false) async throws -> Int {
        // Try cache first
        let cacheKey = "notifications:visible-unread:\(userId.uuidString)"
        if !forceRefresh, let cached: Int = cache.get(cacheKey) {
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

        let count = response.filter { $0.type.isVisible }.count

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

    private func filterVisibleNotifications(_ notifications: [AppNotification]) async -> [AppNotification] {
        var visible: [AppNotification] = []

        for notification in notifications where notification.type.isVisible {
            guard notification.type == .programInvite else {
                visible.append(notification)
                continue
            }

            guard let inviteId = notification.targetId else {
                try? await deleteNotification(notificationId: notification.id)
                continue
            }

            guard await isProgramInviteStillActionable(inviteId: inviteId) else {
                try? await deleteNotification(notificationId: notification.id)
                continue
            }

            visible.append(notification)
        }

        return visible
    }

    private func isProgramInviteStillActionable(inviteId: UUID) async -> Bool {
        do {
            let invite: ProgramInviteRow = try await client
                .from("program_invites")
                .select()
                .eq("id", value: inviteId.uuidString.lowercased())
                .single()
                .execute()
                .value

            guard invite.status == .pending else {
                return false
            }

            let program: SharedProgramRow = try await client
                .from("shared_programs")
                .select()
                .eq("id", value: invite.programId.uuidString.lowercased())
                .single()
                .execute()
                .value

            return program.deletedAt == nil
        } catch {
            return false
        }
    }
}

extension Array {
    var empty: Bool {
        isEmpty
    }
}
