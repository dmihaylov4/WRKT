import Foundation

/// Notification type
enum NotificationType: String, Codable, Sendable {
    // Social notifications
    case friendRequest = "friend_request"
    case friendAccepted = "friend_accepted"
    case postLike = "post_like"
    case postComment = "post_comment"
    case commentReply = "comment_reply"
    case commentMention = "comment_mention"

    // Battle notifications
    case battleInvite = "battle_invite"
    case battleAccepted = "battle_accepted"
    case battleDeclined = "battle_declined"
    case battleLeadTaken = "battle_lead_taken"
    case battleLeadLost = "battle_lead_lost"
    case battleOpponentActivity = "battle_opponent_activity"
    case battleEndingSoon = "battle_ending_soon"
    case battleCompleted = "battle_completed"
    case battleVictory = "battle_victory"
    case battleDefeat = "battle_defeat"

    // Challenge notifications
    case challengeInvite = "challenge_invite"
    case challengeJoined = "challenge_joined"
    case challengeMilestone = "challenge_milestone"
    case challengeLeaderboardChange = "challenge_leaderboard_change"
    case challengeEndingSoon = "challenge_ending_soon"
    case challengeCompleted = "challenge_completed"
    case challengeNewParticipant = "challenge_new_participant"

    // Virtual run notifications
    case virtualRunInvite = "virtual_run_invite"

    // Workout notifications
    case workoutCompleted = "workout_completed"

    var icon: String {
        switch self {
        // Social
        case .friendRequest: return "person.badge.plus"
        case .friendAccepted: return "person.badge.check"
        case .postLike: return "heart.fill"
        case .postComment: return "bubble.left.fill"
        case .commentReply: return "arrowshape.turn.up.left.fill"
        case .commentMention: return "at"

        // Battle
        case .battleInvite: return "flag.2.crossed.fill"
        case .battleAccepted: return "checkmark.shield.fill"
        case .battleDeclined: return "xmark.shield.fill"
        case .battleLeadTaken: return "arrow.up.circle.fill"
        case .battleLeadLost: return "arrow.down.circle.fill"
        case .battleOpponentActivity: return "figure.run"
        case .battleEndingSoon: return "clock.badge.exclamationmark.fill"
        case .battleCompleted: return "flag.checkered"
        case .battleVictory: return "trophy.fill"
        case .battleDefeat: return "hand.thumbsdown.fill"

        // Challenge
        case .challengeInvite: return "star.circle.fill"
        case .challengeJoined: return "person.2.fill"
        case .challengeMilestone: return "star.fill"
        case .challengeLeaderboardChange: return "chart.line.uptrend.xyaxis"
        case .challengeEndingSoon: return "timer"
        case .challengeCompleted: return "checkmark.seal.fill"
        case .challengeNewParticipant: return "person.badge.plus"

        // Virtual run
        case .virtualRunInvite: return "figure.run.circle.fill"

        // Workout
        case .workoutCompleted: return "figure.strengthtraining.traditional"
        }
    }

    var color: String {
        switch self {
        // Social
        case .friendRequest: return "blue"
        case .friendAccepted: return "green"
        case .postLike: return "red"
        case .postComment: return "purple"
        case .commentReply: return "orange"
        case .commentMention: return "pink"

        // Battle
        case .battleInvite: return "orange"
        case .battleAccepted: return "green"
        case .battleDeclined: return "gray"
        case .battleLeadTaken: return "red"
        case .battleLeadLost: return "yellow"
        case .battleOpponentActivity: return "blue"
        case .battleEndingSoon: return "orange"
        case .battleCompleted: return "purple"
        case .battleVictory: return "gold"
        case .battleDefeat: return "gray"

        // Challenge
        case .challengeInvite: return "purple"
        case .challengeJoined: return "blue"
        case .challengeMilestone: return "gold"
        case .challengeLeaderboardChange: return "orange"
        case .challengeEndingSoon: return "red"
        case .challengeCompleted: return "green"
        case .challengeNewParticipant: return "blue"

        // Virtual run
        case .virtualRunInvite: return "green"

        // Workout
        case .workoutCompleted: return "green"
        }
    }

    var category: NotificationCategory {
        switch self {
        case .friendRequest, .friendAccepted:
            return .social
        case .postLike, .postComment, .commentReply, .commentMention:
            return .engagement
        case .battleInvite, .battleAccepted, .battleDeclined, .battleLeadTaken, .battleLeadLost,
             .battleOpponentActivity, .battleEndingSoon, .battleCompleted, .battleVictory, .battleDefeat:
            return .battle
        case .challengeInvite, .challengeJoined, .challengeMilestone, .challengeLeaderboardChange,
             .challengeEndingSoon, .challengeCompleted, .challengeNewParticipant:
            return .challenge
        case .virtualRunInvite:
            return .social
        case .workoutCompleted:
            return .social
        }
    }
}

/// Notification categories for filtering and preferences
enum NotificationCategory: String, Codable, Sendable {
    case social
    case engagement
    case battle
    case challenge

    var displayName: String {
        switch self {
        case .social: return "Social"
        case .engagement: return "Engagement"
        case .battle: return "Battles"
        case .challenge: return "Challenges"
        }
    }
}

/// Notification from database
struct AppNotification: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let userId: UUID
    let type: NotificationType
    let actorId: UUID
    let targetId: UUID?
    var read: Bool
    let createdAt: Date
    let metadata: [String: String]?  // Additional data (position, milestone %, etc.)

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case actorId = "actor_id"
        case targetId = "target_id"
        case read
        case createdAt = "created_at"
        case metadata
    }
}

/// Notification with actor profile information
struct NotificationWithActor: Identifiable, Sendable {
    let id: UUID
    var notification: AppNotification
    let actor: UserProfile

    var type: NotificationType {
        notification.type
    }

    var read: Bool {
        notification.read
    }

    var createdAt: Date {
        notification.createdAt
    }

    var targetId: UUID? {
        notification.targetId
    }

    var metadata: [String: String]? {
        notification.metadata
    }

    /// Get notification message
    var message: String {
        let actorName = actor.displayName ?? actor.username

        switch notification.type {
        // Social
        case .friendRequest:
            return "\(actorName) sent you a friend request"
        case .friendAccepted:
            return "\(actorName) accepted your friend request"
        case .postLike:
            return "\(actorName) liked your workout"
        case .postComment:
            return "\(actorName) commented on your workout"
        case .commentReply:
            return "\(actorName) replied to your comment"
        case .commentMention:
            return "\(actorName) mentioned you in a comment"

        // Battle
        case .battleInvite:
            return "\(actorName) challenged you to a battle!"
        case .battleAccepted:
            return "\(actorName) accepted your battle challenge!"
        case .battleDeclined:
            return "\(actorName) declined your battle challenge"
        case .battleLeadTaken:
            return "You took the lead in your battle with \(actorName)!"
        case .battleLeadLost:
            return "\(actorName) just took the lead in your battle!"
        case .battleOpponentActivity:
            return "\(actorName) just logged a workout in your battle!"
        case .battleEndingSoon:
            return "Your battle with \(actorName) ends in 24 hours!"
        case .battleCompleted:
            return "Your battle with \(actorName) has ended"
        case .battleVictory:
            return "Victory! You beat \(actorName) in your battle!"
        case .battleDefeat:
            return "\(actorName) won the battle. Challenge them to a rematch!"

        // Challenge
        case .challengeInvite:
            return "\(actorName) invited you to join a challenge"
        case .challengeJoined:
            return "\(actorName) joined your challenge"
        case .challengeMilestone:
            return "You've reached a milestone in your challenge!"
        case .challengeLeaderboardChange:
            return "You moved up to position #\(notification.metadata?["position"] ?? "N/A") in the challenge!"
        case .challengeEndingSoon:
            return "Your challenge ends in 24 hours!"
        case .challengeCompleted:
            return "Challenge completed! Check your final ranking"
        case .challengeNewParticipant:
            return "\(actorName) joined the challenge you're in"

        // Virtual run
        case .virtualRunInvite:
            return "\(actorName) wants to run with you!"

        // Workout
        case .workoutCompleted:
            return "\(actorName) just finished a workout"
        }
    }

    /// Get relative time string
    var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
