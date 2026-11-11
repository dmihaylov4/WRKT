import XCTest
@testable import WRKT

@MainActor
final class HomeRefreshCoalescingTests: XCTestCase {
    func testBurstFetchesOnceAndPublishesCards() async throws {
        let delay = HomeRefreshTestDelay()
        let fetch = HomeRefreshTestFetch()
        let model = try await makeModel(delay: delay, fetch: fetch)
        let requests = (0..<20).map { _ in Task { await model.refresh() } }

        await waitUntil { delay.calls == 20 && delay.pendingCount == 1 }
        XCTAssertEqual(fetch.calls, 0)
        delay.fire()
        for request in requests { await request.value }

        XCTAssertEqual(fetch.calls, 1)
        XCTAssertEqual(model.carouselCards.first?.id, "friendActivity")
        XCTAssertEqual(fetch.maximumConcurrent, 1)
    }

    func testRequestsDuringFetchProduceOnlyOneTrailingFetch() async throws {
        let delay = HomeRefreshTestDelay()
        let fetch = HomeRefreshTestFetch()
        fetch.suspended = true
        let model = try await makeModel(delay: delay, fetch: fetch)
        let first = Task { await model.refresh(userInitiated: true) }
        await waitUntil { fetch.pendingCount == 1 }

        let trailing = (0..<20).map { _ in Task { await model.refresh() } }
        await waitUntil { delay.calls == 20 && delay.pendingCount == 1 }
        delay.fire()
        await Task.yield()
        XCTAssertEqual(fetch.calls, 1)
        fetch.completeNext()
        await waitUntil { fetch.calls == 2 && fetch.pendingCount == 1 }
        XCTAssertTrue(model.carouselCards.isEmpty, "The stale first result must not be published")
        fetch.completeNext()
        await first.value
        for request in trailing { await request.value }

        XCTAssertEqual(fetch.calls, 2)
        XCTAssertEqual(fetch.maximumConcurrent, 1)
        XCTAssertEqual(model.carouselCards.first?.id, "friendActivity")
    }

    func testUserInitiatedRefreshHasNoDebounce() async throws {
        let delay = HomeRefreshTestDelay()
        let fetch = HomeRefreshTestFetch()
        let model = try await makeModel(delay: delay, fetch: fetch)

        await model.refresh(userInitiated: true)

        XCTAssertEqual(delay.calls, 0)
        XCTAssertEqual(fetch.calls, 1)
    }

    func testUserInitiatedRefreshFlushesPendingAutomaticRequest() async throws {
        let delay = HomeRefreshTestDelay()
        let fetch = HomeRefreshTestFetch()
        let model = try await makeModel(delay: delay, fetch: fetch)
        let automatic = Task { await model.refresh() }
        await waitUntil { delay.pendingCount == 1 }

        await model.refresh(userInitiated: true)
        await automatic.value
        await waitUntil { delay.pendingCount == 0 }

        XCTAssertEqual(fetch.calls, 1)
    }

    func testImmediateRequestDuringFetchDoesNotWaitForDebounceOrOverlap() async throws {
        let delay = HomeRefreshTestDelay()
        let fetch = HomeRefreshTestFetch()
        fetch.suspended = true
        let model = try await makeModel(delay: delay, fetch: fetch)
        let first = Task { await model.refresh(userInitiated: true) }
        await waitUntil { fetch.pendingCount == 1 }
        var immediateRequested = false
        var automaticRequested = false
        let immediate = Task {
            immediateRequested = true
            await model.refresh(userInitiated: true)
        }
        await waitUntil { immediateRequested }
        let automatic = Task {
            automaticRequested = true
            await model.refresh()
        }
        await waitUntil { automaticRequested }
        XCTAssertEqual(fetch.calls, 1)
        fetch.completeNext()
        await waitUntil { fetch.calls == 2 && fetch.pendingCount == 1 }
        fetch.completeNext()
        await first.value
        await immediate.value
        await automatic.value

        XCTAssertEqual(delay.calls, 0)
        XCTAssertEqual(fetch.calls, 2)
        XCTAssertEqual(fetch.maximumConcurrent, 1)
    }

    func testLaterChangeAndWeeklyGoalBothRefreshThroughTheSameEntryPoint() async throws {
        let delay = HomeRefreshTestDelay()
        let fetch = HomeRefreshTestFetch()
        let model = try await makeModel(delay: delay, fetch: fetch)
        await model.refresh(userInitiated: true)
        let later = Task { await model.refresh() }
        await waitUntil { delay.pendingCount == 1 }
        XCTAssertEqual(fetch.calls, 1)
        delay.fire()
        await later.value
        XCTAssertEqual(fetch.calls, 2)

        model.setWeeklyGoal(nil)
        let accompanyingChange = Task { await model.refresh() }
        await waitUntil { delay.calls == 3 && delay.pendingCount == 1 }
        delay.fire()
        await accompanyingChange.value
        XCTAssertEqual(fetch.calls, 3)
    }

    private func makeModel(delay: HomeRefreshTestDelay, fetch: HomeRefreshTestFetch) async throws -> HomeViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HomeRefreshCoalescingTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        return HomeViewModel(workoutStore: store, plannerStore: .shared,
                             friendActivityLoader: { await fetch.load() },
                             refreshDelay: { try await delay.wait() })
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected scheduler state was not reached")
    }
}

@MainActor
private final class HomeRefreshTestDelay {
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var calls = 0
    var pendingCount: Int { continuations.count }

    func wait() async throws {
        let id = UUID()
        calls += 1
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuations[id] = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.continuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func fire() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class HomeRefreshTestFetch {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    private var concurrent = 0
    private(set) var maximumConcurrent = 0
    var suspended = false
    var pendingCount: Int { continuations.count }

    func load() async -> FriendActivitySummary? {
        calls += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        if suspended {
            await withCheckedContinuation { continuations.append($0) }
        }
        return FriendActivitySummary(activities: [], userWorkedOutToday: false)
    }

    func completeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
