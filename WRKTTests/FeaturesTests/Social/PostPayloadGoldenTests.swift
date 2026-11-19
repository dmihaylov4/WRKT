import XCTest
@testable import WRKT

/// The posts the composer, the year award and the detail share send for workouts that come from
/// run history, encoded exactly as `PostRepository.createPost` hands them to Supabase
/// (`WorkoutPostInsertPayload`: `workout_data`, `workout_data_list`, heart-rate samples, splits,
/// zones, stats). Nothing is sent: the payload is built and compared with goldens recorded
/// before run history moved to summaries. Record with `TEST_RUNNER_VOLIA_RECORD_POST_GOLDENS=1`.
@MainActor
final class PostPayloadGoldenTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "PostPayloadGoldenTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Fixtures (fixed ids, whole-second dates)

    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    /// Wednesday 11 November 2026, 12:00 UTC.
    private static let noon = Date(timeIntervalSince1970: 1_794_398_400)
    private static func at(_ hours: Double) -> Date { noon.addingTimeInterval(hours * 3600) }

    private static func points(_ count: Int, start: Date, hr: (Int) -> Double?) -> [RoutePoint] {
        (0..<count).map { i in
            RoutePoint(lat: 48.2 + Double(i) * 0.0007, lon: 16.37 + Double(i % 7) * 0.0004,
                       t: start.addingTimeInterval(Double(i) * 30), hr: hr(i))
        }
    }

    /// A run with a route carrying heart rate, stored max and min, samples, splits and dynamics.
    static var routeAndHeartRate: Run {
        let route = points(24, start: at(-1), hr: { 128 + Double($0 % 9) * 3.5 })
        return Run(id: id(1), date: at(0), distanceKm: 6.2, durationSec: 2_052, notes: "Easy", healthKitUUID: id(101),
                   avgHeartRate: 142.4, maxHeartRate: 168, minHeartRate: 101,
                   hrSamples: route.map { HeartRateSample(timestamp: $0.t, bpm: $0.hr! + 0.5) }, calories: 412.25,
                   route: route.map { Coordinate(lat: $0.lat, lon: $0.lon) }, routeWithHR: route,
                   splits: (1...6).map { KilometerSplit(number: $0, distanceKm: $0 == 6 ? 0.2 : 1, durationSec: 320 + $0 * 4) },
                   workoutType: "Running", workoutName: "Morning Run", avgRunningPower: 245.5, avgCadence: 168.25,
                   avgStrideLength: 1.12, avgGroundContactTime: 238, avgVerticalOscillation: 8.4)
    }

    /// No stored max or min: both come from the route's heart rate. Some points have none.
    static var routeFallback: Run {
        let route = points(18, start: at(-26), hr: { $0 % 4 == 0 ? nil : 120 + Double($0) * 2 })
        return Run(id: id(2), date: at(-25), distanceKm: 4.05, durationSec: 1_510, healthKitUUID: id(102),
                   avgHeartRate: 139, calories: 300, route: route.map { Coordinate(lat: $0.lat, lon: $0.lon) },
                   routeWithHR: route, splits: [], workoutType: "Running")
    }

    /// Heart-rate samples and stored stats, no route at all.
    static var samplesNoRoute: Run {
        Run(id: id(3), date: at(-49), distanceKm: 8.4, durationSec: 2_700, healthKitUUID: id(103),
            avgHeartRate: 150, maxHeartRate: 171, minHeartRate: 110,
            hrSamples: (0..<12).map { HeartRateSample(timestamp: at(-50).addingTimeInterval(Double($0) * 60), bpm: 110 + Double($0) * 5) },
            calories: 590, splits: (1...8).map { KilometerSplit(number: $0, distanceKm: 1, durationSec: 315 + $0) },
            workoutType: "Running", workoutName: "Treadmill")
    }

    /// An Apple Watch strength session from Health.
    static var strength: Run {
        Run(id: id(4), date: at(-73), distanceKm: 0, durationSec: 2_760, notes: "Upper body.", healthKitUUID: id(104),
            avgHeartRate: 118, maxHeartRate: 151, minHeartRate: 72,
            hrSamples: (0..<20).map { HeartRateSample(timestamp: at(-74).addingTimeInterval(Double($0) * 60), bpm: 100 + Double($0)) },
            calories: 356, workoutType: "Traditional Strength Training", workoutName: "Strength")
    }

    /// A Health workout that a logged workout already covers: the logged one is posted.
    static var matchedRun: Run {
        Run(id: id(5), date: at(-97), distanceKm: 0, durationSec: 3_000, healthKitUUID: id(105), avgHeartRate: 125,
            maxHeartRate: 160, minHeartRate: 80, calories: 400, workoutType: "Functional Strength Training")
    }

    /// No heart rate of any kind.
    static var plain: Run {
        Run(id: id(6), date: at(-121), distanceKm: 2.1, durationSec: 1_500, healthKitUUID: id(106), workoutType: "Walking")
    }

    /// Two runs and a logged workout ending at the same second, to pin the tie order.
    static var tiedRuns: [Run] {
        [Run(id: id(7), date: at(-145), distanceKm: 3, durationSec: 900, healthKitUUID: id(107), workoutType: "Running"),
         Run(id: id(8), date: at(-145), distanceKm: 5, durationSec: 1_500, healthKitUUID: id(108), workoutType: "Cycling")]
    }

    static var logged: [CompletedWorkout] {
        var matched = CompletedWorkout(id: id(201), date: at(-96.5), startedAt: at(-97.5), entries: [], workoutName: "Push Day")
        matched.matchedHealthKitUUID = id(105)
        matched.matchedHealthKitHeartRate = 125
        matched.matchedHealthKitCalories = 400
        let tied = CompletedWorkout(id: id(202), date: at(-145), startedAt: at(-146), entries: [], workoutName: "Legs")
        return [matched, tied]
    }

    static var runs: [Run] {
        [routeAndHeartRate, routeFallback, samplesNoRoute, strength, matchedRun, plain] + tiedRuns
    }

    // MARK: - Encoding and goldens

    private static func payload(_ workouts: [CompletedWorkout]) throws -> String {
        let insert = try WorkoutPostInsertPayload(workouts: workouts, caption: "Golden", images: nil, visibility: .friends,
                                                  userId: id(999))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(insert), as: UTF8.self)
    }

    private static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("PostPayloadGoldens", isDirectory: true)

    private func check(_ name: String, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.goldens.appendingPathComponent("\(name).json")
        if ProcessInfo.processInfo.environment["VOLIA_RECORD_POST_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url)
            return
        }
        let golden = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(json, golden, "\(name) differs from its golden", file: file, line: line)
    }

    private func store(_ runs: [Run]) async throws -> WorkoutStoreV2 {
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts(Self.logged, prIndex: [:])
        try await previous.saveRuns(runs)
        defaults.set(true, forKey: "runs.deduplication.v1")
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        return store
    }

    // MARK: - Harness: how each path builds the workouts it posts

    /// The composer's picker list, completed as it would be posted, and the workouts posted for
    /// a selection from it.
    private func composerPosts(_ store: WorkoutStoreV2, selecting ids: [UUID]) async throws -> (list: [CompletedWorkout], posted: [CompletedWorkout]) {
        let candidates = PostCreationViewModel.pickerCandidates(workouts: Self.logged, runs: store.runSummaries)
        let list = candidates.map(\.completedWorkout)
        var picker: [UUID: CompletedWorkout] = [:]
        for candidate in candidates { if case .run = candidate { picker[candidate.completedWorkout.id] = candidate.completedWorkout } }
        // What the picker shows is the posted workout without samples.
        let completedList = await PostCreationViewModel.workoutsForPosting(list, picker: picker, store: store)
        XCTAssertEqual(list, completedList.map { workout in
            var shown = workout
            if picker[workout.id] != nil { shown.matchedHealthKitHeartRateSamples = nil }
            return shown
        })
        let selected = ids.compactMap { id in list.first { $0.id == id } }
        let posted = await PostCreationViewModel.workoutsForPosting(selected, picker: picker, store: store)
        return (completedList, posted)
    }

    private func yearAwardPost(_ store: WorkoutStoreV2, year: Int) async throws -> CompletedWorkout? {
        await CutYearAwardLogic.socialCandidate(year: year, workouts: Self.logged, runs: store.runSummaries,
                                                calendar: Self.utc)?.completed(in: store)
    }

    /// The detail screens' share: from the workout's live detail handle.
    private func detailShare(_ run: Run, store: WorkoutStoreV2) async throws -> CompletedWorkout {
        try XCTUnwrap(store.runDetail(id: run.id).run).sharedWorkout()
    }
    // END HARNESS

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Tests

    func testComposerPickerListAndPostsMatchTheirGoldens() async throws {
        let store = try await store(Self.runs)
        let everything = Self.runs.map(\.id) + Self.logged.map(\.id)
        let (list, _) = try await composerPosts(store, selecting: [])
        try check("composer-list", try Self.payload(list))
        XCTAssertFalse(list.contains { $0.id == Self.matchedRun.id }, "a run covered by a logged workout is not listed")

        for id in everything where list.contains(where: { $0.id == id }) {
            let (_, posted) = try await composerPosts(store, selecting: [id])
            try check("composer-post-\(id.uuidString.suffix(3))", try Self.payload(posted))
        }
        let (_, pair) = try await composerPosts(store, selecting: [Self.routeAndHeartRate.id, Self.routeFallback.id])
        try check("composer-post-two", try Self.payload(pair))
    }

    func testYearAwardPostMatchesItsGolden() async throws {
        let store = try await store(Self.runs)
        let picked = try await yearAwardPost(store, year: 2026)
        let run = try XCTUnwrap(picked)
        XCTAssertEqual(run.id, Self.routeAndHeartRate.id)
        try check("year-award-run", try Self.payload([run]))

        // A year whose latest workout is a logged one.
        let onlyOlder = try await self.store([Self.matchedRun, Self.plain])
        _ = onlyOlder
        let pickedLogged = try await yearAwardPost(onlyOlder, year: 2026)
        let logged = try XCTUnwrap(pickedLogged)
        try check("year-award-logged", try Self.payload([logged]))
    }

    func testDetailSharePostsMatchTheirGoldens() async throws {
        for run in [Self.routeAndHeartRate, Self.routeFallback, Self.samplesNoRoute, Self.strength, Self.plain] {
            let store = try await store([run])
            let workout = try await detailShare(run, store: store)
            try check("detail-share-\(run.id.uuidString.suffix(3))", try Self.payload([workout]))
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent(".migrated"))
        }
    }
}
