import Foundation

/// Friendship status
enum FriendshipStatus: String, Codable, Sendable {
    case pending = "pending"
    case accepted = "accepted"
    case blocked = "blocked"
}

/// Friendship relationship between two users
struct Friendship: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let friendId: UUID
    var status: FriendshipStatus
    let createdAt: Date
    var updatedAt: Date
    var mutedNotifications: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case friendId = "friend_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mutedNotifications = "muted_notifications"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        friendId = try container.decode(UUID.self, forKey: .friendId)
        status = try container.decode(FriendshipStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Default to false for backward compatibility if the column doesn't exist yet
        mutedNotifications = try container.decodeIfPresent(Bool.self, forKey: .mutedNotifications) ?? false
    }
}

/// Friend request with user profile information
struct FriendRequest: Identifiable, Sendable {
    let id: UUID
    let friendship: Friendship
    let profile: UserProfile
    let isIncoming: Bool // true if someone sent you a request, false if you sent it

    var statusText: String {
        switch friendship.status {
        case .pending:
            return isIncoming ? "Wants to be friends" : "Request pending"
        case .accepted:
            return "Friends"
        case .blocked:
            return "Blocked"
        }
    }
}

/// Friend with profile information
struct Friend: Identifiable, Sendable {
    let id: UUID
    let profile: UserProfile
    let friendshipId: UUID
    let friendsSince: Date
    var mutedNotifications: Bool

    var friendsSinceText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Friends since \(friendsSince.formatted(date: .abbreviated, time: .omitted))"
    }

    init(id: UUID, profile: UserProfile, friendshipId: UUID, friendsSince: Date, mutedNotifications: Bool = false) {
        self.id = id
        self.profile = profile
        self.friendshipId = friendshipId
        self.friendsSince = friendsSince
        self.mutedNotifications = mutedNotifications
    }
}
