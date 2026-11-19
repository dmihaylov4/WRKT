import XCTest
import Observation
@testable import WRKT

/// One shared, observable handle per workout: loaded at once from memory, updated by every
/// change to that workout and only that workout, keeping its last run after a removal.
@MainActor
final class RunDetailTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "RunDetailTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000)

    private static func points(_ count: Int) -> [RoutePoint] {
        (0..<count).map { RoutePoint(lat: 48.2 + Double($0) * 0.001, lon: 16.3, t: start.addingTimeInterval(Double($0)), hr: 140) }
    }

    private static func history() -> [Run] {
        [
            Run(date: start, distanceKm: 5, durationSec: 1800, healthKitUUID: UUID(), avgHeartRate: 150,
                routeWithHR: points(5), workoutType: "Running"),
            Run(date: start.addingTimeInterval(-86_400), distanceKm: 2, durationSec: 1500, healthKitUUID: UUID(),
                workoutType: "Walking")
        ]
    }

    private func relaunch(runs: [Run]) async throws -> WorkoutStoreV2 {
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts([], prIndex: [:])
        try await previous.saveRuns(runs)
        defaults.set(true, forKey: "runs.deduplication.v1")
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        return store
    }

    /// Whether reading `read` registers a change when `change` runs.
    private func observes(_ read: @escaping () -> Void, during change: () -> Void) -> Bool {
        var fired = false
        withObservationTracking(read) { fired = true }
        change()
        return fired
    }

    func testHandleIsLoadedAtOnceFromMemory() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        let detail = store.runDetail(id: runs[0].id)
        XCTAssertEqual(detail.phase, .loaded(runs[0]))
        XCTAssertEqual(detail.run, runs[0])
        XCTAssertEqual(detail.lastLoaded, runs[0])
        XCTAssertFalse(detail.isLoading)
    }

    func testUnknownWorkoutIsRemovedWithNothingToShow() async throws {
        let store = try await relaunch(runs: Self.history())
        let detail = store.runDetail(id: UUID())
        XCTAssertEqual(detail.phase, .unavailable(.removed))
        XCTAssertNil(detail.run)
        XCTAssertNil(detail.lastLoaded)
    }

    func testOtherPhases() {
        let loading = RunDetail(id: UUID(), phase: .loading)
        XCTAssertTrue(loading.isLoading)
        XCTAssertNil(loading.run)
        let run = Self.history()[0]
        let unreadable = RunDetail(id: run.id, phase: .loaded(run))
        unreadable.setUnavailable(.unreadable)
        XCTAssertNil(unreadable.run, "an unreadable workout shows no detail, even if it held one")
        XCTAssertEqual(unreadable.lastLoaded, run)
    }

    func testOneSharedInstancePerIdWhileHeld() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        let first = store.runDetail(id: runs[0].id)
        XCTAssertTrue(store.runDetail(id: runs[0].id) === first)
        XCTAssertFalse(store.runDetail(id: runs[1].id) === first)

        weak var released: RunDetail?
        do {
            let temporary = store.runDetail(id: runs[1].id)
            released = temporary
        }
        XCTAssertNil(released, "the store does not keep a handle alive")
        let holder = RunDetailHolder()
        XCTAssertTrue(holder.detail(for: runs[0].id, in: store) === first)
        XCTAssertTrue(holder.detail(for: runs[0].id, in: store) === first)
    }

    func testEditAddAndRemoveUpdateTheHandle() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        let detail = store.runDetail(id: runs[1].id)

        var enriched = runs[1]
        enriched.routeWithHR = Self.points(3)
        enriched.splits = [KilometerSplit(number: 1, distanceKm: 1, durationSec: 600)]
        store.updateRun(enriched)
        XCTAssertEqual(detail.run, enriched)

        var renamed = enriched
        renamed.workoutName = "Evening walk"
        store.batchUpdateRuns([renamed])
        XCTAssertEqual(detail.run, renamed)

        store.removeRun(withId: runs[1].id)
        XCTAssertEqual(detail.phase, .unavailable(.removed))
        XCTAssertEqual(detail.run, renamed, "an open screen keeps showing the last run")

        let pending = Run(distanceKm: 3, durationSec: 900, healthKitUUID: UUID())
        let waiting = store.runDetail(id: pending.id)
        XCTAssertEqual(waiting.phase, .unavailable(.removed))
        store.addRun(pending)
        XCTAssertEqual(waiting.phase, .loaded(pending))

        let first = store.runDetail(id: runs[0].id)
        store.deleteRuns(at: IndexSet([store.runSummaries.firstIndex { $0.id == runs[0].id }!]))
        XCTAssertEqual(first.phase, .unavailable(.removed))
        XCTAssertEqual(first.run, runs[0])

        store.clearAllRuns()
        XCTAssertEqual(waiting.phase, .unavailable(.removed))
        XCTAssertEqual(waiting.run, pending)
    }

    /// A screen re-renders for a change to its own workout, not for changes to others.
    func testObserversSeeOnlyTheirOwnWorkout() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        let detail = store.runDetail(id: runs[0].id)

        var other = runs[1]
        other.notes = "other"
        XCTAssertFalse(observes({ _ = detail.phase }, during: { store.updateRun(other) }))
        XCTAssertFalse(observes({ _ = detail.phase }, during: { store.addRun(Run(distanceKm: 1, durationSec: 60)) }))
        XCTAssertFalse(observes({ _ = detail.phase }, during: { store.updateRun(runs[0]) }), "an unchanged run is no change")

        var own = runs[0]
        own.notes = "own"
        XCTAssertTrue(observes({ _ = detail.phase }, during: { store.updateRun(own) }))
        XCTAssertTrue(observes({ _ = detail.revision }, during: { store.removeRun(withId: own.id) }))
    }

    func testLoadRunAndLoadRuns() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        guard case .loaded(let run) = try await store.loadRun(id: runs[0].id) else { return XCTFail("expected a run") }
        XCTAssertEqual(run, runs[0])
        guard case .removed = try await store.loadRun(id: UUID()) else { return XCTFail("expected removed") }

        let missing = UUID()
        let results = try await store.loadRuns(ids: [runs[1].id, missing])
        XCTAssertEqual(results.count, 2)
        guard case .loaded(let second) = results[runs[1].id] else { return XCTFail("expected a run") }
        XCTAssertEqual(second, runs[1])
        guard case .removed = results[missing] else { return XCTFail("expected removed") }
    }

    func testLoadRunHonoursCancellation() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        let one = Task { try await store.loadRun(id: runs[0].id) }
        one.cancel()
        do {
            _ = try await one.value
            XCTFail("a cancelled load must throw")
        } catch is CancellationError {}
        let many = Task { try await store.loadRuns(ids: [runs[0].id]) }
        many.cancel()
        do {
            _ = try await many.value
            XCTFail("a cancelled load must throw")
        } catch is CancellationError {}
    }

    func testLoadRunThrowsWhenHistoryCannotLoad() async throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("runs_v2.json"))
        try await WorkoutStorage(directory: directory).saveWorkouts([], prIndex: [:])
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        do {
            _ = try await store.loadRun(id: UUID())
            XCTFail("an unloaded history must not answer")
        } catch is CancellationError {
            XCTFail("not a cancellation")
        } catch {}
    }
}
