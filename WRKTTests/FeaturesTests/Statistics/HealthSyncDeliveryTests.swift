import XCTest
@testable import WRKT

@MainActor
final class HealthSyncDeliveryTests: XCTestCase {
    private var directory: URL!
    private var marker: URL { directory.appendingPathComponent("pending") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAcknowledgementFollowsDurableHandoffAndRelaunchDrainsOnce() async throws {
        let delivery = HealthSyncDelivery(fileURL: marker)
        var acknowledgements = 0
        try delivery.receive {
            acknowledgements += 1
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        }
        XCTAssertEqual(acknowledgements, 1)
        let relaunched = HealthSyncDelivery(fileURL: marker)
        var syncs = 0
        let first = try await relaunched.drain { syncs += 1; return true }
        let second = try await relaunched.drain { syncs += 1; return true }
        XCTAssertTrue(first && second)
        XCTAssertEqual(syncs, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testFailedOrUnavailableSyncRetainsDurableRetry() async throws {
        let delivery = HealthSyncDelivery(fileURL: marker)
        try delivery.receive { }
        let failed = try await delivery.drain { false }
        XCTAssertFalse(failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let relaunched = HealthSyncDelivery(fileURL: marker)
        let retried = try await relaunched.drain { true }
        XCTAssertTrue(retried)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testNewDeliveryDuringSyncIsNotClearedByOlderPassAndWorkersCoalesce() async throws {
        let delivery = HealthSyncDelivery(fileURL: marker)
        var acknowledgements = 0
        try delivery.receive { acknowledgements += 1 }
        var resumeSync: CheckedContinuation<Void, Never>?
        var syncs = 0
        let first = Task { try await delivery.drain {
            syncs += 1
            if syncs == 1 { await withCheckedContinuation { resumeSync = $0 } }
            return true
        } }
        while resumeSync == nil { await Task.yield() }
        try delivery.receive { acknowledgements += 1 }
        let second = Task { try await delivery.drain {
            XCTFail("Concurrent drains must share the worker")
            return true
        } }
        await Task.yield()
        resumeSync?.resume()
        let outcomes = try await (first.value, second.value)
        XCTAssertTrue(outcomes.0 && outcomes.1)
        XCTAssertEqual(acknowledgements, 2)
        XCTAssertEqual(syncs, 2)
    }

    func testCancellationPreservesMarkerEvenIfQueryIgnoresCancellation() async throws {
        let delivery = HealthSyncDelivery(fileURL: marker)
        try delivery.receive { }
        var resumeSync: CheckedContinuation<Void, Never>?
        let task = Task { try await delivery.drain {
            await withCheckedContinuation { resumeSync = $0 }
            return true
        } }
        while resumeSync == nil { await Task.yield() }
        delivery.cancel()
        resumeSync?.resume()
        do {
            _ = try await task.value
            XCTFail("Cancellation must retain the pending generation")
        } catch is CancellationError { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let retried = try await delivery.drain { true }
        XCTAssertTrue(retried)
    }

    func testContinuousDeliveriesAreBoundedAndRetainTheLastGeneration() async throws {
        let delivery = HealthSyncDelivery(fileURL: marker)
        try delivery.receive { }
        var syncs = 0
        let drained = try await delivery.drain {
            syncs += 1
            try! delivery.receive { }
            return true
        }
        XCTAssertFalse(drained)
        XCTAssertEqual(syncs, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testFailedHandoffDoesNotClaimDurableAcknowledgement() throws {
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        var acknowledged = false
        XCTAssertThrowsError(try HealthSyncDelivery(fileURL: marker).receive { acknowledged = true })
        XCTAssertFalse(acknowledged)
    }

    func testBackgroundCompletionOnlyReportsTheFirstOutcome() {
        for first in [false, true] {
            var outcomes: [Bool] = []
            let completion = HealthSyncTaskCompletion { outcomes.append($0) }
            XCTAssertFalse(completion.isFinished)
            completion.finish(success: first)
            completion.finish(success: !first)
            XCTAssertEqual(outcomes, [first])
            XCTAssertTrue(completion.isFinished)
        }
    }
}
