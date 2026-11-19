import XCTest
import Combine
@testable import WRKT

/// The store keeps one summary per run, in the runs' order, updated in the same mutation, and
/// publishes exactly as often as when only the runs were published.
@MainActor
final class RunSummaryStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "RunSummaryStoreTests." + UUID().uuidString
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
        (0..<count).map { RoutePoint(lat: 48.2 + Double($0) * 0.001, lon: 16.3, t: start.addingTimeInterval(Double($0)), hr: 140 + Double($0)) }
    }

    /// Dates deliberately not in order: history order is not date order.
    private static func history() -> [Run] {
        [
            Run(date: start.addingTimeInterval(-86_400), distanceKm: 5, durationSec: 1800, healthKitUUID: UUID(),
                avgHeartRate: 150, routeWithHR: points(4), splits: [], workoutType: "Running"),
            Run(date: start, distanceKm: 0, durationSec: 2700, healthKitUUID: UUID(), avgHeartRate: 110,
                hrSamples: [HeartRateSample(timestamp: start, bpm: 110)], workoutType: "Traditional Strength Training"),
            Run(date: start.addingTimeInterval(-3 * 86_400), distanceKm: 2, durationSec: 1500, healthKitUUID: UUID(),
                workoutType: "Walking"),
            Run(date: start.addingTimeInterval(-2 * 86_400), distanceKm: 0, durationSec: 0, healthKitUUID: UUID(),
                workoutType: "Elliptical")
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

    private func assertInStep(_ store: WorkoutStoreV2, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(store.runSummaries, store.fullRunsForTesting.map(RunSummary.init), file: file, line: line)
        XCTAssertEqual(store.runSummaries.map(\.id), store.fullRunsForTesting.map(\.id), file: file, line: line)
    }

    func testSummariesFollowEveryMutationInOrder() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        XCTAssertEqual(store.runSummaries.map(\.id), runs.map(\.id), "history order, not date order")
        assertInStep(store)

        let added = Run(date: Self.start.addingTimeInterval(-10 * 86_400), distanceKm: 8, durationSec: 2400,
                        healthKitUUID: UUID(), workoutType: "Cycling")
        store.addRun(added)
        XCTAssertEqual(store.runSummaries.first?.id, added.id, "new runs go first, whatever their date")
        assertInStep(store)

        store.addRun(Run(distanceKm: 1, durationSec: 60, healthKitUUID: added.healthKitUUID))
        XCTAssertEqual(store.runSummaries.count, 5, "a duplicate Health id is not added")
        assertInStep(store)

        var enriched = runs[2]
        enriched.routeWithHR = Self.points(3)
        enriched.route = enriched.routeWithHR?.map { Coordinate(lat: $0.lat, lon: $0.lon) }
        enriched.splits = [KilometerSplit(number: 1, distanceKm: 1, durationSec: 600)]
        store.editRun(.replacing(with: enriched))
        XCTAssertEqual(store.runSummary(id: enriched.id)?.routeWithHRPointCount, 3)
        XCTAssertEqual(store.runSummary(id: enriched.id)?.splitCount, 1)
        assertInStep(store)

        var renamed = runs[0]
        renamed.workoutName = "Long run"
        var heavier = runs[1]
        heavier.hrSamples = nil
        store.editRuns([renamed, heavier, Run(distanceKm: 1, durationSec: 60)].map(RunEdit.replacing(with:)))
        XCTAssertEqual(store.runSummary(id: renamed.id)?.workoutName, "Long run")
        XCTAssertNil(store.runSummary(id: heavier.id)?.heartRateSampleCount)
        assertInStep(store)

        store.removeRun(withId: runs[1].id)
        XCTAssertNil(store.runSummary(id: runs[1].id))
        assertInStep(store)

        let removed = [store.runSummaries[0].id, store.runSummaries[2].id]
        removed.forEach(store.removeRun(withId:))
        assertInStep(store)
        XCTAssertEqual(store.runSummaries.map(\.id), [runs[0].id, runs[3].id])

        store.clearAllRuns()
        XCTAssertTrue(store.runSummaries.isEmpty)
        assertInStep(store)
    }

    func testDeduplicationKeepsSummariesInStep() async throws {
        let runs = Self.history()
        var copy = runs[0]
        copy.id = UUID()
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts([], prIndex: [:])
        try await previous.saveRuns(runs + [copy])
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        XCTAssertEqual(store.runSummaries.map(\.id), runs.map(\.id))
        assertInStep(store)
    }

    func testLookupsAndFiltersMatchTheRuns() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        XCTAssertEqual(store.validRunSummaries.map(\.id), store.fullRunsForTesting.filter(LegacyRunHelpers.isValidRun).map(\.id))
        XCTAssertEqual(store.validRunSummaries.map(\.id), [runs[0].id, runs[2].id])
        let day = Self.start
        XCTAssertEqual(store.runSummaries(on: day).map(\.id), store.fullRunsForTesting.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.map(\.id))
        for run in runs {
            XCTAssertEqual(store.runSummary(id: run.id), RunSummary(run))
            XCTAssertEqual(store.runSummary(healthKitUUID: run.healthKitUUID!), RunSummary(run))
        }
        XCTAssertNil(store.runSummary(id: UUID()))
        XCTAssertNil(store.runSummary(healthKitUUID: UUID()))
    }

    /// One change notification per mutation that changes the runs, none for one that does not:
    /// the cadence the runs had when they were published themselves.
    func testPublishesOncePerChange() async throws {
        let runs = Self.history()
        let store = try await relaunch(runs: runs)
        var count = 0
        let cancellable = store.objectWillChange.sink { count += 1 }
        defer { cancellable.cancel() }

        func expect(_ expected: Int, _ name: String, _ change: () -> Void) {
            count = 0
            change()
            XCTAssertEqual(count, expected, name)
        }
        let added = Run(distanceKm: 3, durationSec: 900, healthKitUUID: UUID())
        expect(1, "add") { store.addRun(added) }
        expect(0, "duplicate add") { store.addRun(Run(distanceKm: 1, durationSec: 1, healthKitUUID: added.healthKitUUID)) }
        expect(0, "unchanged update") { store.editRun(.replacing(with: runs[0])) }
        var changed = runs[0]
        changed.notes = "x"
        expect(1, "update") { store.editRun(.replacing(with: changed)) }
        expect(0, "unchanged batch") { store.editRuns([.replacing(with: changed)]) }
        var other = runs[1]
        other.notes = "y"
        expect(1, "batch") { store.editRuns([.replacing(with: changed), .replacing(with: other)]) }
        expect(0, "remove missing") { store.removeRun(withId: UUID()) }
        expect(1, "remove") { store.removeRun(withId: runs[2].id) }
        expect(1, "clear") { store.clearAllRuns() }
        expect(0, "clear empty") { store.clearAllRuns() }
    }
}
