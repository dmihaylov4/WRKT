import Foundation
import SwiftData

/// SwiftData model for caching notifications locally
@Model
final class CachedNotification {
    @Attribute(.unique) var id: String
    var userId: String
    var type: String
    var actorId: String
    var targetId: String?
    var read: Bool
    var createdAt: Date
    var cachedAt: Date
    var metadata: [String: String]?

    // Actor info (denormalized for performance)
    var actorUsername: String
    var actorDisplayName: String?
    var actorAvatarUrl: String?

    init(
        id: String,
        userId: String,
        type: String,
        actorId: String,
        targetId: String?,
        read: Bool,
        createdAt: Date,
        actorUsername: String,
        actorDisplayName: String?,
        actorAvatarUrl: String?,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.actorId = actorId
        self.targetId = targetId
        self.read = read
        self.createdAt = createdAt
        self.cachedAt = Date()
        self.actorUsername = actorUsername
        self.actorDisplayName = actorDisplayName
        self.actorAvatarUrl = actorAvatarUrl
        self.metadata = metadata
    }

    /// Check if cache is expired (10 minutes TTL for notifications)
    var isExpired: Bool {
        Date().timeIntervalSince(cachedAt) > 600 // 10 minutes
    }
}

// MARK: - Conversion Extensions
extension CachedNotification {
    /// Convert from NotificationWithActor to CachedNotification
    static func from(_ notification: NotificationWithActor) -> CachedNotification {
        CachedNotification(
            id: notification.id.uuidString,
            userId: notification.notification.userId.uuidString,
            type: notification.type.rawValue,
            actorId: notification.notification.actorId.uuidString,
            targetId: notification.notification.targetId?.uuidString,
            read: notification.read,
            createdAt: notification.createdAt,
            actorUsername: notification.actor.username,
            actorDisplayName: notification.actor.displayName,
            actorAvatarUrl: notification.actor.avatarUrl,
            metadata: notification.notification.metadata
        )
    }

    /// Convert CachedNotification to NotificationWithActor
    func toNotificationWithActor() -> NotificationWithActor? {
        guard let notificationId = UUID(uuidString: id),
              let userId = UUID(uuidString: userId),
              let actorId = UUID(uuidString: actorId),
              let notificationType = NotificationType(rawValue: type) else {
            return nil
        }

        let targetUUID = targetId.flatMap { UUID(uuidString: $0) }

        let actor = UserProfile(
            id: actorId,
            username: actorUsername,
            displayName: actorDisplayName,
            avatarUrl: actorAvatarUrl
        )

        let appNotification = AppNotification(
            id: notificationId,
            userId: userId,
            type: notificationType,
            actorId: actorId,
            targetId: targetUUID,
            read: read,
            createdAt: createdAt,
            metadata: metadata
        )

        return NotificationWithActor(
            id: notificationId,
            notification: appNotification,
            actor: actor
        )
    }
}
