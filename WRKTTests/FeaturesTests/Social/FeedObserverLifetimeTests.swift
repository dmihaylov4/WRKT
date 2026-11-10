import XCTest
@testable import WRKT

private final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens = Set<ObjectIdentifier>()
    private var callbacks = 0

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tokens.count
    }

    var callbackCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callbacks
    }

    override func addObserver(forName name: NSNotification.Name?, object obj: Any?,
                              queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        let token = super.addObserver(forName: name, object: obj, queue: queue) { [weak self] notification in
            if let self {
                self.lock.lock()
                self.callbacks += 1
                self.lock.unlock()
            }
            block(notification)
        }
        lock.lock()
        tokens.insert(ObjectIdentifier(token as AnyObject))
        lock.unlock()
        return token
    }

    override func removeObserver(_ observer: Any) {
        lock.lock()
        tokens.remove(ObjectIdentifier(observer as AnyObject))
        lock.unlock()
        super.removeObserver(observer)
    }
}

@MainActor
final class FeedObserverLifetimeTests: XCTestCase {
    private func makeModel(center: NotificationCenter) -> FeedViewModel {
        FeedViewModel(postRepository: PostRepository(), authService: .shared,
                      realtimeService: RealtimeService(client: SupabaseClientWrapper.shared.client),
                      notificationCenter: center)
    }

    func testRepeatedCleanupAndReleaseDoNotAccumulateObserverCallbacks() async {
        let center = CountingNotificationCenter()
        for index in 1...20 {
            var model: FeedViewModel? = makeModel(center: center)
            weak var released = model
            XCTAssertEqual(center.activeCount, 1)
            center.post(name: .postCommentCountDidChange, object: nil)
            XCTAssertEqual(center.callbackCount, index)
            await model?.cleanup()
            await model?.cleanup()
            model = nil
            XCTAssertNil(released)
            XCTAssertEqual(center.activeCount, 0)
            center.post(name: .postCommentCountDidChange, object: nil)
            XCTAssertEqual(center.callbackCount, index)
        }
    }

    func testReleaseWithoutExplicitCleanupAlsoUnregistersObserver() {
        let center = CountingNotificationCenter()
        for _ in 0..<20 {
            var model: FeedViewModel? = makeModel(center: center)
            weak var released = model
            XCTAssertEqual(center.activeCount, 1)
            model = nil
            XCTAssertNil(released)
            XCTAssertEqual(center.activeCount, 0)
            center.post(name: .postCommentCountDidChange, object: nil)
        }
        XCTAssertEqual(center.callbackCount, 0)
    }
}
