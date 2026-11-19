import XCTest
@testable import WRKT

/// The runs file leaves out `route` when it only repeats the points of `routeWithHR`, and
/// decoding gives back exactly the run that was encoded. Files written before, and every other
/// run, read exactly as they did.
@MainActor
final class StoredRunTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "StoredRunTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Fixtures

    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000)

    private static func points(_ count: Int, shift: Double = 0, hr: Bool = true) -> [RoutePoint] {
        (0..<count).map { i in
            RoutePoint(lat: 48.2 + Double(i) * 0.001 + shift, lon: 16.3 + Double(i) * 0.000_7,
                       t: start.addingTimeInterval(Double(i) * 5), hr: hr ? 140 + Double(i) : nil)
        }
    }

    private static func coordinates(_ points: [RoutePoint]) -> [Coordinate] {
        points.map { Coordinate(lat: $0.lat, lon: $0.lon) }
    }

    private static func run(route: [Coordinate]?, routeWithHR: [RoutePoint]?) -> Run {
        Run(date: start, distanceKm: 5.123456789, durationSec: 1800, healthKitUUID: UUID(),
            avgHeartRate: 142.5, route: route, routeWithHR: routeWithHR, workoutType: "Running")
    }

    /// Every combination of the two route fields the file can hold.
    private static var combinations: [(name: String, run: Run, slimmed: Bool)] {
        let p = points(5)
        return [
            ("route only", run(route: coordinates(p), routeWithHR: nil), false),
            ("routeWithHR only", run(route: nil, routeWithHR: p), false),
            ("both equal", run(route: coordinates(p), routeWithHR: p), true),
            ("both equal without heart rate", run(route: coordinates(points(5, hr: false)), routeWithHR: points(5, hr: false)), true),
            ("both different points", run(route: coordinates(points(5, shift: 0.01)), routeWithHR: p), false),
            ("both different lengths", run(route: coordinates(Array(p.prefix(4))), routeWithHR: p), false),
            ("neither", run(route: nil, routeWithHR: nil), false),
            ("both empty", run(route: [], routeWithHR: []), true),
            ("empty route, nil routeWithHR", run(route: [], routeWithHR: nil), false),
            ("nil route, empty routeWithHR", run(route: nil, routeWithHR: []), false),
            ("empty route, points in routeWithHR", run(route: [], routeWithHR: p), false),
            ("points in route, empty routeWithHR", run(route: coordinates(p), routeWithHR: []), false),
            ("negative zero against zero", run(route: [Coordinate(lat: -0.0, lon: 0)],
                                               routeWithHR: [RoutePoint(lat: 0, lon: 0, t: start)]), false),
            ("equal zeros", run(route: [Coordinate(lat: -0.0, lon: 0)],
                                routeWithHR: [RoutePoint(lat: -0.0, lon: 0, t: start)]), true),
        ]
    }

    /// The encoder the runs file was written with before this change.
    private static var previousEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var plainDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func objects(in file: URL) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
    }

    // MARK: - Round trips

    func testEveryCombinationReadsBackEqualAndOnlyRepeatedRoutesAreLeftOut() async throws {
        let cases = Self.combinations
        let storage = WorkoutStorage(directory: directory)
        try await storage.saveRuns(cases.map(\.run))

        let loaded = try await WorkoutStorage(directory: directory).loadRuns()
        let stored = try objects(in: runsFile)
        for (index, item) in cases.enumerated() {
            XCTAssertEqual(loaded[index], item.run, item.name)
            XCTAssertEqual(stored[index]["route"] == nil, item.run.route == nil || item.slimmed, item.name)
            XCTAssertEqual(stored[index]["routeFromRouteWithHR"] as? Bool, item.slimmed ? true : nil, item.name)
            XCTAssertEqual(StoredRun.routeRepeatsRouteWithHR(item.run), item.slimmed, item.name)
        }
    }

    func testStartupValidationDecodesTheSameRuns() async throws {
        let cases = Self.combinations
        let documents = directory.appendingPathComponent("Documents")
        let history = documents.appendingPathComponent("WRKT_Storage")
        let storage = WorkoutStorage(directory: history)
        try await storage.saveRuns(cases.map(\.run))
        try await storage.saveWorkouts([], prIndex: [:])
        try Data().write(to: history.appendingPathComponent(".migrated"))

        let validated = try XCTUnwrap(WorkoutStorage.validateExistingData(applicationSupport: directory, documents: documents))
        XCTAssertEqual(validated.runs?.value, cases.map(\.run))
    }

    // MARK: - Files written before this change

    func testFileInThePreviousFormReadsExactlyAsBefore() async throws {
        let cases = Self.combinations.map(\.run)
        let previous = try Self.previousEncoder.encode(cases)
        try previous.write(to: runsFile)

        let loaded = try await WorkoutStorage(directory: directory).loadRuns()
        XCTAssertEqual(loaded, try Self.plainDecoder.decode([Run].self, from: previous))
        XCTAssertEqual(loaded, cases)
        // A run an older version saved with only routeWithHR keeps route nil: no marker, no rebuild.
        XCTAssertNil(loaded[1].route)
    }

    func testOlderVersionReadingTheNewFileKeepsEveryPointAndOnlyLacksTheRepeatedRoute() async throws {
        let cases = Self.combinations
        try await WorkoutStorage(directory: directory).saveRuns(cases.map(\.run))

        // An older version decodes `Run` directly and ignores the marker.
        let older = try Self.plainDecoder.decode([Run].self, from: Data(contentsOf: runsFile))
        for (index, item) in cases.enumerated() {
            XCTAssertEqual(older[index].routeWithHR, item.run.routeWithHR, item.name)
            XCTAssertEqual(older[index].route, item.slimmed ? nil : item.run.route, item.name)
            XCTAssertEqual(older[index].hasUsableRouteData, item.run.hasUsableRouteData, item.name)
            XCTAssertEqual(older[index].needsHistoricalEnrichment, item.run.needsHistoricalEnrichment, item.name)
        }

        // What it writes back has no marker; this version then reads route as nil, as written.
        try Self.previousEncoder.encode(older).write(to: runsFile)
        let back = try await WorkoutStorage(directory: directory).loadRuns()
        XCTAssertEqual(back, older)
    }

    // MARK: - Unchanged-save logic

    func testLoadingAPreviousFormFileDoesNotRewriteItAndTheNextRealSaveSlimsIt() async throws {
        let p = Self.points(6)
        let repeated = Self.run(route: Self.coordinates(p), routeWithHR: p)
        let other = Self.run(route: nil, routeWithHR: p)
        try Self.previousEncoder.encode([repeated, other]).write(to: runsFile)
        try await WorkoutStorage(directory: directory).saveWorkouts([], prIndex: [:])
        let stamp = try XCTUnwrap(FileStamp(runsFile))

        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        try await store.flushHealthKitChanges()
        XCTAssertEqual(FileStamp(runsFile), stamp, "No rewrite just to slim the file")

        let added = Self.run(route: nil, routeWithHR: nil)
        store.addRun(added)
        try await store.flushHealthKitChanges()
        XCTAssertNotEqual(FileStamp(runsFile), stamp)
        let stored = try objects(in: runsFile)
        XCTAssertEqual(stored.filter { $0["routeFromRouteWithHR"] as? Bool == true }.count, 1)

        let reloaded = WorkoutStoreV2(storage: WorkoutStorage(directory: directory),
                                      defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        try await reloaded.waitForStorage()
        XCTAssertEqual(Set(reloaded.runs), Set(store.runs))
        let newStamp = try XCTUnwrap(FileStamp(runsFile))
        try await reloaded.flushHealthKitChanges()
        XCTAssertEqual(FileStamp(runsFile), newStamp, "The slim file is not rewritten after loading either")
    }

    func testStoredFormComparisonFollowsTheSlimForm() async throws {
        let p = Self.points(4)
        let repeated = Self.run(route: Self.coordinates(p), routeWithHR: p)
        var withoutRoute = repeated
        withoutRoute.route = nil
        var shifted = repeated
        shifted.route = Self.coordinates(Self.points(4, shift: 0.5))
        let storage = WorkoutStorage(directory: directory)

        let identical = await storage.runsEncodeIdentically([(repeated, repeated), (repeated, withoutRoute), (repeated, shifted)])

        XCTAssertEqual(identical, [true, false, false],
                       "A run whose route was dropped by an older version is a different value and is written")
    }

    // MARK: - Cost

    func testRepeatedRouteCheckIsCheapForALongRoute() {
        let p = Self.points(20_000)
        let long = Self.run(route: Self.coordinates(p), routeWithHR: p)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<100 { XCTAssertTrue(StoredRun.routeRepeatsRouteWithHR(long)) }
        }
        // 2 million point comparisons; generous bound for a loaded simulator.
        XCTAssertLessThan(elapsed, .seconds(2))
    }
}
