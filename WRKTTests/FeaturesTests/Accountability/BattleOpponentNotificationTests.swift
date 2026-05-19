import Testing
import Foundation
@testable import WRKT

struct BattleOpponentNotificationTests {

    @Test func messageWithMetadataShowsScoreDelta() {
        let actor = UserProfile(
            id: UUID(),
            username: "alex"
        )
        let notification = AppNotification(
            id: UUID(),
            userId: UUID(),
            type: .battleOpponentActivity,
            actorId: actor.id,
            targetId: UUID(),
            read: false,
            createdAt: Date(),
            metadata: [
                "score_added": "2450",
                "actor_new_score": "15800",
                "recipient_score": "14200"
            ]
        )
        let withActor = NotificationWithActor(
            id: notification.id,
            notification: notification,
            actor: actor
        )

        #expect(withActor.message.contains("2,450") || withActor.message.contains("2450"))
        #expect(withActor.message.contains("lead"))
    }

    @Test func messageWithoutMetadataFallsBackToGeneric() {
        let actor = UserProfile(id: UUID(), username: "alex")
        let notification = AppNotification(
            id: UUID(),
            userId: UUID(),
            type: .battleOpponentActivity,
            actorId: actor.id,
            targetId: UUID(),
            read: false,
            createdAt: Date(),
            metadata: nil
        )
        let withActor = NotificationWithActor(
            id: notification.id,
            notification: notification,
            actor: actor
        )

        #expect(withActor.message.contains("alex"))
        #expect(withActor.message.contains("workout"))
    }
}
