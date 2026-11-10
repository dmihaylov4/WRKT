import Foundation

/// Presents local feedback. Persistent notifications are created by database events.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

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
    func showChallengeMilestoneToast(milestone: Int, title: String) async {
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
