import XCTest
@testable import WRKT

@MainActor
final class RetiredNotificationTests: XCTestCase {
    private func notification(_ type: NotificationType) -> AppNotification {
        AppNotification(id: UUID(), userId: UUID(), type: type, actorId: UUID(),
                        targetId: UUID(), read: false, createdAt: .now, metadata: nil)
    }

    func testUnknownTypeDoesNotDiscardSupportedNotificationsInBatch() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode([notification(.postLike), notification(.virtualRunInvite)])
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "virtual_run_invite", with: "future_notification")
        let decoded = try JSONDecoder().decode([AppNotification].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.map(\.type), [.postLike, .unknown])
        XCTAssertEqual(decoded.filter { $0.type.isVisible }.count, 1)
    }

    func testHiddenTypesDoNotContributeToUnreadEligibility() {
        XCTAssertFalse(NotificationType.virtualRunInvite.isVisible)
        XCTAssertFalse(NotificationType.unknown.isVisible)
        XCTAssertTrue(NotificationType.postParticipantTag.isVisible)
        XCTAssertTrue(NotificationType.workoutCompleted.isVisible)
    }

    func testCachedRetiredNotificationIsNotPresented() {
        let value = notification(.virtualRunInvite)
        let cached = CachedNotification.from(NotificationWithActor(id: value.id,
            notification: value, actor: UserProfile(id: value.actorId, username: "friend")))
        XCTAssertNil(cached.toNotificationWithActor())
        cached.type = "future_notification"
        XCTAssertNil(cached.toNotificationWithActor())
    }

    func testRetiredAndUnknownPushesCannotNavigate() {
        for type in ["virtual_run_invite", "future_notification"] {
            var payload = PushNotificationService.userInfo(for: notification(.postLike))
            payload["type"] = type
            XCTAssertTrue(NotificationType.shouldIgnoreRemoteNotification(payload))
            XCTAssertNil(PushNotificationService.appNotification(from: payload))
        }
    }

    func testSupportedPushPreservesNavigationPayload() {
        let value = notification(.postLike)
        let payload = PushNotificationService.userInfo(for: value)
        XCTAssertFalse(NotificationType.shouldIgnoreRemoteNotification(payload))
        let decoded = PushNotificationService.appNotification(from: payload)
        XCTAssertEqual(decoded?.id, value.id)
        XCTAssertEqual(decoded?.targetId, value.targetId)
        XCTAssertEqual(decoded?.type, value.type)
    }

    func testLocalNotificationWithoutRemoteTypeIsNotSuppressed() {
        XCTAssertFalse(NotificationType.shouldIgnoreRemoteNotification([:]))
        XCTAssertTrue(NotificationType.shouldIgnoreRemoteNotification(["type": 123]))
    }
}
