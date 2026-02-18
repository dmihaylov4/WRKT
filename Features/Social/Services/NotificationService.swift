import Foundation
import Supabase

/// Central service for managing all app notifications (battles, challenges, social)
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let client: SupabaseClient
    private let repository: NotificationRepository

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.client = client
        self.repository = NotificationRepository(client: client)
    }

    // MARK: - Battle Notifications

    /// Create battle invite notification (fallback if trigger fails)
    func createBattleInviteNotification(
        battleId: UUID,
        challengerId: UUID,
        opponentId: UUID,
        battleType: BattleType,
        duration: Int
    ) async throws {
        try await repository.createNotification(
            userId: opponentId,
            type: .battleInvite,
            actorId: challengerId,
            targetId: battleId
        )

        AppLogger.success("Battle invite notification created", category: AppLogger.notifications)
    }

    /// Create battle opponent activity notification (manual trigger from app)
    func createBattleOpponentActivityNotification(
        battleId: UUID,
        actorId: UUID,
        recipientId: UUID
    ) async throws {
        // Check if battle is active first
        let battle: Battle = try await client
            .from("battles")
            .select()
            .eq("id", value: battleId.uuidString)
            .single()
            .execute()
            .value

        guard battle.status == .active else {
            AppLogger.warning("Battle not active, skipping opponent activity notification", category: AppLogger.notifications)
            return
        }

        try await repository.createNotification(
            userId: recipientId,
            type: .battleOpponentActivity,
            actorId: actorId,
            targetId: battleId
        )

        AppLogger.success("Battle opponent activity notification created", category: AppLogger.notifications)
    }

    // MARK: - Challenge Notifications

    /// Create challenge milestone notification (manual trigger for immediate feedback)
    func createChallengeMilestoneNotification(
        challengeId: UUID,
        userId: UUID,
        milestone: Int,
        progress: Decimal,
        goal: Decimal,
        challengeTitle: String
    ) async throws {
        struct NotificationCreate: Encodable {
            let user_id: String
            let type: String
            let actor_id: String
            let target_id: String
            let read: Bool
            let metadata: [String: String]
        }

        let notification = NotificationCreate(
            user_id: userId.uuidString.lowercased(),
            type: NotificationType.challengeMilestone.rawValue,
            actor_id: userId.uuidString.lowercased(),  // Self-notification
            target_id: challengeId.uuidString.lowercased(),
            read: false,
            metadata: [
                "milestone": "\(milestone)",
                "progress": progress.description,
                "goal": goal.description,
                "challenge_title": challengeTitle
            ]
        )

        let _: AppNotification = try await client
            .from("notifications")
            .insert(notification)
            .select()
            .single()
            .execute()
            .value

        AppLogger.success("Challenge milestone (\(milestone)%) notification created", category: AppLogger.notifications)

        // Show in-app toast for immediate feedback
        await showChallengeMilestoneToast(milestone: milestone, title: challengeTitle)
    }

    /// Create challenge new participant notification for other participants
    func createChallengeNewParticipantNotification(
        challengeId: UUID,
        newParticipantId: UUID,
        challengeTitle: String,
        existingParticipantIds: [UUID]
    ) async throws {
        // Don't notify the participant who just joined
        let recipientsToNotify = existingParticipantIds.filter { $0 != newParticipantId }

        // Batch create notifications for all existing participants
        struct NotificationCreate: Encodable {
            let user_id: String
            let type: String
            let actor_id: String
            let target_id: String
            let read: Bool
            let metadata: [String: String]
        }

        let notifications = recipientsToNotify.map { recipientId in
            NotificationCreate(
                user_id: recipientId.uuidString.lowercased(),
                type: NotificationType.challengeNewParticipant.rawValue,
                actor_id: newParticipantId.uuidString.lowercased(),
                target_id: challengeId.uuidString.lowercased(),
                read: false,
                metadata: ["challenge_title": challengeTitle]
            )
        }

        if !notifications.isEmpty {
            let _: [AppNotification] = try await client
                .from("notifications")
                .insert(notifications)
                .select()
                .execute()
                .value

            AppLogger.success("Challenge new participant notifications created for \(notifications.count) users", category: AppLogger.notifications)
        }
    }

    // MARK: - Scheduled Notifications (for future implementation)

    /// Schedule battle ending soon notification (to be called by cron job or local scheduler)
    func scheduleBattleEndingSoonNotification(
        battleId: UUID,
        challengerId: UUID,
        opponentId: UUID,
        hoursRemaining: Int
    ) async throws {
        struct NotificationCreate: Encodable {
            let user_id: String
            let type: String
            let actor_id: String
            let target_id: String
            let read: Bool
            let metadata: [String: String]
        }

        let notifications = [
            NotificationCreate(
                user_id: challengerId.uuidString.lowercased(),
                type: NotificationType.battleEndingSoon.rawValue,
                actor_id: opponentId.uuidString.lowercased(),
                target_id: battleId.uuidString.lowercased(),
                read: false,
                metadata: ["hours_remaining": "\(hoursRemaining)"]
            ),
            NotificationCreate(
                user_id: opponentId.uuidString.lowercased(),
                type: NotificationType.battleEndingSoon.rawValue,
                actor_id: challengerId.uuidString.lowercased(),
                target_id: battleId.uuidString.lowercased(),
                read: false,
                metadata: ["hours_remaining": "\(hoursRemaining)"]
            )
        ]

        let _: [AppNotification] = try await client
            .from("notifications")
            .insert(notifications)
            .select()
            .execute()
            .value

        AppLogger.success("Battle ending soon notifications created", category: AppLogger.notifications)
    }

    /// Schedule challenge ending soon notification (to be called by cron job or local scheduler)
    func scheduleChallengeEndingSoonNotification(
        challengeId: UUID,
        participantIds: [UUID],
        hoursRemaining: Int,
        challengeTitle: String
    ) async throws {
        struct NotificationCreate: Encodable {
            let user_id: String
            let type: String
            let actor_id: String
            let target_id: String
            let read: Bool
            let metadata: [String: String]
        }

        let notifications = participantIds.map { participantId in
            NotificationCreate(
                user_id: participantId.uuidString.lowercased(),
                type: NotificationType.challengeEndingSoon.rawValue,
                actor_id: participantId.uuidString.lowercased(),  // Self-notification
                target_id: challengeId.uuidString.lowercased(),
                read: false,
                metadata: [
                    "hours_remaining": "\(hoursRemaining)",
                    "challenge_title": challengeTitle
                ]
            )
        }

        if !notifications.isEmpty {
            let _: [AppNotification] = try await client
                .from("notifications")
                .insert(notifications)
                .select()
                .execute()
                .value

            AppLogger.success("Challenge ending soon notifications created for \(notifications.count) participants", category: AppLogger.notifications)
        }
    }

    // MARK: - In-App Toast Notifications

    /// Show immediate in-app toast for battle lead taken
    func showBattleLeadTakenToast(opponentName: String, yourScore: String? = nil, opponentScore: String? = nil) async {
        var message = "You're ahead of \(opponentName)!"
        if let yourScore = yourScore, let opponentScore = opponentScore {
            message = "\(yourScore) vs \(opponentScore) - You're winning!"
        }

        AppNotificationManager.shared.show(
            ToastNotification(
                type: .success,
                title: "You took the lead!",
                message: message,
                icon: "arrow.up.circle.fill",
                duration: 4.0
            )
        )
    }

    /// Show immediate in-app toast for battle lead lost
    func showBattleLeadLostToast(opponentName: String, yourScore: String? = nil, opponentScore: String? = nil) async {
        var message = "\(opponentName) just took the lead!"
        if let yourScore = yourScore, let opponentScore = opponentScore {
            message = "\(opponentScore) vs \(yourScore) - Time to step up!"
        }

        AppNotificationManager.shared.show(
            ToastNotification(
                type: .warning,
                title: "Lead Lost",
                message: message,
                icon: "arrow.down.circle.fill",
                duration: 4.0
            )
        )
    }

    /// Show immediate in-app toast for challenge milestone
    private func showChallengeMilestoneToast(milestone: Int, title: String) async {
        AppNotificationManager.shared.show(
            ToastNotification(
                type: .success,
                title: "\(milestone)% Complete!",
                message: "Keep crushing \"\(title)\"!",
                icon: "star.fill",
                duration: 4.0
            )
        )
    }

    /// Show battle invite received toast
    func showBattleInviteToast(challengerName: String, battleType: String, challengerId: UUID, battleId: UUID? = nil) async {
        AppNotificationManager.shared.show(
            ToastNotification(
                type: .info,
                title: "Battle Challenge!",
                message: "\(challengerName) challenged you to a \(battleType) battle!",
                icon: "flag.2.crossed.fill",
                duration: 5.0,
                onTap: {
                    // Create a temporary notification object for navigation
                    // Note: This is a simplified notification - in production you'd fetch the full notification from DB
                    let tempNotification = AppNotification(
                        id: UUID(),
                        userId: UUID(), // Will be filled by the navigation handler
                        type: .battleInvite,
                        actorId: challengerId,
                        targetId: battleId,
                        read: false,
                        createdAt: Date(),
                        metadata: nil
                    )

                    // Navigate using existing notification system
                    NotificationCenter.default.post(
                        name: Notification.Name("NavigateToNotification"),
                        object: tempNotification
                    )
                }
            )
        )
    }

    /// Show challenge invite received toast
    func showChallengeInviteToast(inviterName: String, challengeTitle: String) async {
        AppNotificationManager.shared.show(
            ToastNotification(
                type: .info,
                title: "Challenge Invite",
                message: "\(inviterName) invited you to \"\(challengeTitle)\"",
                icon: "star.circle.fill",
                duration: 5.0
            )
        )
    }
}
