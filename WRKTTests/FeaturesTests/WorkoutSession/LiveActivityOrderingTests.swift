import XCTest
@testable import WRKT

@MainActor
final class LiveActivityOrderingTests: XCTestCase {
    func testStopDuringReplacementCannotCreateLateActivity() async {
        let backend = ActivityBackend()
        let manager = LiveActivityManager(client: backend.client)
        let first = runningRecord(revision: 1)
        manager.reconcile(first)
        await manager.waitForUpdates()

        let ending = expectation(description: "Previous activity is ending")
        backend.beforeSuspendedEnd = { ending.fulfill() }
        let replacement = runningRecord(revision: 2)
        manager.reconcile(replacement)
        await fulfillment(of: [ending], timeout: 2)

        var stopped = replacement
        stopped.revision = 3
        stopped.state = .idle
        manager.reconcile(stopped)
        backend.resumeEnd?.resume()
        await manager.waitForUpdates()
        XCTAssertTrue(backend.active.isEmpty)
        XCTAssertEqual(backend.requestedTimerIDs, [first.id])
    }

    func testOlderRevisionCannotOverridePausedOrStoppedState() async {
        let backend = ActivityBackend()
        let manager = LiveActivityManager(client: backend.client)
        let running = runningRecord(revision: 1)
        manager.reconcile(running)
        await manager.waitForUpdates()
        var paused = running
        paused.revision = 2
        paused.state = .paused(remainingSeconds: 45, exerciseID: "plank", exerciseName: "Plank",
            originalDuration: 90, wasAdjusted: false)
        manager.reconcile(paused)
        await manager.waitForUpdates()
        manager.reconcile(running)
        await manager.waitForUpdates()
        XCTAssertEqual(backend.states.first?.value.isPaused, true)
        XCTAssertEqual(backend.states.first?.value.remainingSeconds, 45)

        var stopped = paused
        stopped.revision = 3
        stopped.state = .idle
        manager.reconcile(stopped)
        await manager.waitForUpdates()
        manager.reconcile(paused)
        await manager.waitForUpdates()
        XCTAssertTrue(backend.active.isEmpty)
        XCTAssertEqual(backend.requestedTimerIDs, [running.id])
    }

    func testRestorationRemovesUnboundLegacyActivityAndDoesNotRecreateCompletion() async {
        let backend = ActivityBackend()
        backend.active = [.init(id: "legacy", timerID: nil)]
        let manager = LiveActivityManager(client: backend.client)
        var completed = runningRecord(revision: 1)
        completed.state = .completed(exerciseID: "plank", exerciseName: "Plank")
        manager.reconcile(completed)
        await manager.waitForUpdates()
        XCTAssertTrue(backend.active.isEmpty)
        XCTAssertTrue(backend.requestedTimerIDs.isEmpty)

        backend.enabled = false
        manager.reconcile(runningRecord(revision: 2))
        await manager.waitForUpdates()
        XCTAssertTrue(backend.requestedTimerIDs.isEmpty)
    }

    private func runningRecord(revision: UInt64) -> RestTimerRecord {
        var record = RestTimerRecord()
        record.revision = revision
        record.startedAt = .now
        record.state = .running(endDate: Date().addingTimeInterval(90), exerciseID: "plank",
            exerciseName: "Plank", originalDuration: 90, wasAdjusted: false)
        return record
    }
}

@MainActor
private final class ActivityBackend {
    var active: [RestTimerActivityClient.Reference] = []
    var states: [String: RestTimerAttributes.ContentState] = [:]
    var requestedTimerIDs: [UUID] = []
    var enabled = true
    var beforeSuspendedEnd: (() -> Void)?
    var resumeEnd: CheckedContinuation<Void, Never>?

    var client: RestTimerActivityClient {
        RestTimerActivityClient(
            activities: { self.active },
            areEnabled: { self.enabled },
            request: { attributes, state in
                let id = UUID().uuidString
                self.active.append(.init(id: id, timerID: attributes.timerID))
                self.states[id] = state
                if let timerID = attributes.timerID { self.requestedTimerIDs.append(timerID) }
            },
            update: { id, state in self.states[id] = state },
            end: { id in
                if let beforeEnd = self.beforeSuspendedEnd {
                    self.beforeSuspendedEnd = nil
                    await withCheckedContinuation { continuation in
                        self.resumeEnd = continuation
                        beforeEnd()
                    }
                }
                self.active.removeAll { $0.id == id }
                self.states.removeValue(forKey: id)
            }
        )
    }
}
