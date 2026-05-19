import Testing
import Foundation
@testable import WRKT

struct ChallengeLeaderboardNotificationTests {

    @Test func messageIncludesActorAndChallengeTitle() {
        let actor = UserProfile(id: UUID(), username: "sam")
        let notification = AppNotification(
            id: UUID(),
            userId: UUID(),
            type: .challengeLeaderboardChange,
            actorId: actor.id,
            targetId: UUID(),
            read: false,
            createdAt: Date(),
            metadata: [
                "position": "3",
                "challenge_title": "30-Day Warrior"
            ]
        )
        let withActor = NotificationWithActor(
            id: notification.id,
            notification: notification,
            actor: actor
        )

        #expect(withActor.message.contains("sam"))
        #expect(withActor.message.contains("30-Day Warrior"))
        #expect(withActor.message.contains("3"))
    }
}
