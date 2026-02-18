//
//  ActiveFriend.swift
//  WRKT
//
//  Model for friends with recent activity data
//

import Foundation

/// Represents a friend with their recent workout activity
struct ActiveFriend: Identifiable, Sendable {
    let id: UUID
    let profile: UserProfile
    let friendshipId: UUID
    var lastWorkoutDate: Date?
    var recentWorkoutCount: Int
    var mutedNotifications: Bool

    /// Whether this friend has worked out in the last 24 hours
    var isActive: Bool {
        guard let lastWorkout = lastWorkoutDate else { return false }
        return Calendar.current.dateComponents([.hour], from: lastWorkout, to: Date()).hour ?? 25 < 24
    }

    /// Whether this friend has worked out in the last 7 days
    var isRecentlyActive: Bool {
        guard let lastWorkout = lastWorkoutDate else { return false }
        return Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day ?? 8 < 7
    }

    /// Formatted time since last workout
    var lastWorkoutText: String? {
        guard let lastWorkout = lastWorkoutDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastWorkout, relativeTo: Date())
    }

    init(
        id: UUID,
        profile: UserProfile,
        friendshipId: UUID,
        lastWorkoutDate: Date? = nil,
        recentWorkoutCount: Int = 0,
        mutedNotifications: Bool = false
    ) {
        self.id = id
        self.profile = profile
        self.friendshipId = friendshipId
        self.lastWorkoutDate = lastWorkoutDate
        self.recentWorkoutCount = recentWorkoutCount
        self.mutedNotifications = mutedNotifications
    }

    /// Create from a Friend model
    init(from friend: Friend, lastWorkoutDate: Date? = nil, recentWorkoutCount: Int = 0) {
        self.id = friend.id
        self.profile = friend.profile
        self.friendshipId = friend.friendshipId
        self.lastWorkoutDate = lastWorkoutDate
        self.recentWorkoutCount = recentWorkoutCount
        self.mutedNotifications = friend.mutedNotifications
    }
}
