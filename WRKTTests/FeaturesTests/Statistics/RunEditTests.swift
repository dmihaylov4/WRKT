import XCTest
@testable import WRKT

/// The Health writers' edits do exactly what the old whole-run writes did, and, applied by id,
/// keep a change that landed while a writer was waiting for HealthKit.
@MainActor
final class RunEditTests: XCTestCase {

    // MARK: - The previous writers, kept as the reference (HealthKitManager on e207255)

    private static func legacyEnrichment(_ enrichment: HealthKitManager.DetailedRunEnrichment, to run: Run) -> Run {
        var updated = run
        updated.distanceKm = enrichment.distanceKm
        updated.durationSec = enrichment.durationSec
        updated.calories = enrichment.calories
        updated.workoutType = enrichment.workoutType
        updated.workoutName = enrichment.workoutName
        if let splits = enrichment.splits { updated.splits = splits }
        if let avgHeartRate = enrichment.avgHeartRate { updated.avgHeartRate = avgHeartRate }
        if let maxHeartRate = enrichment.maxHeartRate { updated.maxHeartRate = maxHeartRate }
        if let minHeartRate = enrichment.minHeartRate { updated.minHeartRate = minHeartRate }
        if let hrSamples = enrichment.hrSamples, !hrSamples.isEmpty { updated.hrSamples = hrSamples }
        if let value = enrichment.avgRunningPower { updated.avgRunningPower = value }
        if let value = enrichment.avgCadence { updated.avgCadence = value }
        if let value = enrichment.avgStrideLength { updated.avgStrideLength = value }
        if let value = enrichment.avgGroundContactTime { updated.avgGroundContactTime = value }
        if let value = enrichment.avgVerticalOscillation { updated.avgVerticalOscillation = value }
        if let route = enrichment.route, !route.isEmpty { updated.route = route }
        if let routeWithHR = enrichment.routeWithHR, !routeWithHR.isEmpty {
            updated.routeWithHR = routeWithHR
            updated.route = routeWithHR.map { Coordinate(lat: $0.lat, lon: $0.lon) }
        }
        return updated
    }

    /// The full resync's update of an existing run.
    private static func legacyResync(_ existing: Run, date: Date, km: Double, sec: Int, kcal: Double?, type: String,
                                     name: String?, fetchedHR: Double?) -> Run {
        var updated = existing
        updated.date = date
        updated.distanceKm = km
        updated.durationSec = sec
        updated.calories = kcal
        updated.workoutType = type
        updated.workoutName = name
        if updated.avgHeartRate == nil || updated.avgHeartRate == 0 { updated.avgHeartRate = fetchedHR }
        return updated
    }

    /// An import's update of an existing run; `strength` is the result of the samples read.
    private static func legacyImportUpdate(_ existing: Run, km: Double, sec: Int, kcal: Double?, type: String, name: String?,
                                           strength: (samples: [HeartRateSample], avg: Double, max: Double, min: Double)??,
                                           fetchedHR: Double?) -> Run {
        var updated = existing
        updated.distanceKm = km
        updated.durationSec = sec
        updated.calories = kcal
        updated.workoutType = type
        updated.workoutName = name
        if updated.avgHeartRate == nil || updated.avgHeartRate == 0 {
            if let strength {
                if let (samples, avg, max, min) = strength, avg > 0 {
                    updated.avgHeartRate = avg
                    updated.maxHeartRate = max
                    updated.minHeartRate = min
                    updated.hrSamples = samples
                }
            } else {
                updated.avgHeartRate = fetchedHR
            }
        }
        return updated
    }

    // MARK: - Fixtures

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000)

    private static func maybe<T>(_ g: inout Generator, _ make: () -> T) -> T? { Bool.random(using: &g) ? make() : nil }

    private static func array<T>(_ g: inout Generator, _ make: (Int) -> T) -> [T]? {
        switch Int.random(in: 0..<3, using: &g) {
        case 0: return nil
        case 1: return []
        default: return (0..<Int.random(in: 1..<5, using: &g)).map(make)
        }
    }

    private static func points(_ g: inout Generator) -> [RoutePoint]? {
        let shift = Double.random(in: 0..<1, using: &g)
        let withHR = Bool.random(using: &g)
        return array(&g) { i in RoutePoint(lat: 48 + Double(i) * 0.001 + shift, lon: 16, t: start.addingTimeInterval(Double(i)),
                                           hr: withHR && i.isMultiple(of: 2) ? 140 + Double(i) : nil) }
    }

    private static func run(_ g: inout Generator) -> Run {
        let route = points(&g)
        let otherRoute = points(&g)?.map { Coordinate(lat: $0.lat, lon: $0.lon) }
        let plain = Bool.random(using: &g) ? route?.map { Coordinate(lat: $0.lat, lon: $0.lon) } : otherRoute
        let average: Double? = Bool.random(using: &g) ? (Bool.random(using: &g) ? 0 : 140) : nil
        let distance = Double.random(in: 0..<20, using: &g)
        let duration = Int.random(in: 0..<9000, using: &g)
        let max = maybe(&g) { 170.0 }
        let min = maybe(&g) { 90.0 }
        let samples = array(&g) { HeartRateSample(timestamp: start.addingTimeInterval(Double($0)), bpm: 120 + Double($0)) }
        let calories = maybe(&g) { 300.0 }
        let splits = array(&g) { KilometerSplit(number: $0 + 1, distanceKm: 1, durationSec: 300 + $0) }
        let type = ["Running", "Walking", "Traditional Strength Training"][Int.random(in: 0..<3, using: &g)]
        let name = maybe(&g) { "Named" }
        let power = maybe(&g) { 250.0 }
        let cadence = maybe(&g) { 170.0 }
        return Run(date: start, distanceKm: distance, durationSec: duration, healthKitUUID: UUID(), avgHeartRate: average,
                   maxHeartRate: max, minHeartRate: min, hrSamples: samples, calories: calories, route: plain,
                   routeWithHR: route, splits: splits, workoutType: type, workoutName: name,
                   avgRunningPower: power, avgCadence: cadence)
    }

    private static func enrichment(_ g: inout Generator) -> HealthKitManager.DetailedRunEnrichment {
        let distance = Double.random(in: 0..<20, using: &g)
        let duration = Int.random(in: 0..<9000, using: &g)
        let calories = maybe(&g) { 410.0 }
        let name = maybe(&g) { "Read" }
        let route = points(&g)?.map { Coordinate(lat: $0.lat + 1, lon: $0.lon) }
        let routeWithHR = points(&g)
        let splits = array(&g) { KilometerSplit(number: $0 + 1, distanceKm: 1, durationSec: 280 + $0) }
        let average = maybe(&g) { 151.0 }
        let max = maybe(&g) { 180.0 }
        let min = maybe(&g) { 95.0 }
        let samples = array(&g) { HeartRateSample(timestamp: start.addingTimeInterval(Double($0) + 0.5), bpm: 130) }
        let power = maybe(&g) { 260.0 }
        let cadence = maybe(&g) { 175.0 }
        let stride = maybe(&g) { 1.1 }
        let contact = maybe(&g) { 240.0 }
        let oscillation = maybe(&g) { 8.0 }
        return .init(distanceKm: distance, durationSec: duration, calories: calories, workoutType: "Running",
                     workoutName: name, route: route, routeWithHR: routeWithHR, splits: splits,
                     avgHeartRate: average, maxHeartRate: max, minHeartRate: min, hrSamples: samples,
                     avgRunningPower: power, avgCadence: cadence, avgStrideLength: stride,
                     avgGroundContactTime: contact, avgVerticalOscillation: oscillation)
    }

    // MARK: - Equivalence

    func testEnrichmentEditEqualsTheOldEnrichmentOnRandomRunsAndReads() {
        var g = Generator(state: 42)
        for _ in 0..<3_000 {
            let run = Self.run(&g)
            let read = Self.enrichment(&g)
            XCTAssertEqual(RunEdit.enrichment(read, id: run.id).applied(to: run), Self.legacyEnrichment(read, to: run))
        }
    }

    func testResyncUpdateEqualsTheOldOne() {
        var g = Generator(state: 7)
        for _ in 0..<1_000 {
            let existing = Self.run(&g)
            let date = Self.start.addingTimeInterval(Double(Int.random(in: 0..<100, using: &g)))
            let fetched: Double? = Bool.random(using: &g) ? 133 : nil
            var update = HealthKitManager.HealthImportUpdate(id: existing.id, date: date, distanceKm: 3.3, durationSec: 999,
                                                             calories: Bool.random(using: &g) ? 120 : nil,
                                                             workoutType: "Walking", workoutName: nil)
            if existing.avgHeartRate == nil || existing.avgHeartRate == 0 { update.avgHeartRate = .some(fetched) }
            XCTAssertEqual(update.edit.applied(to: existing),
                           Self.legacyResync(existing, date: date, km: 3.3, sec: 999, kcal: update.calories, type: "Walking",
                                             name: nil, fetchedHR: fetched))
        }
    }

    func testImportUpdateEqualsTheOldOne() {
        var g = Generator(state: 9)
        let samples = [HeartRateSample(timestamp: Self.start, bpm: 111)]
        for _ in 0..<1_000 {
            let existing = Self.run(&g)
            let isStrength = Bool.random(using: &g)
            let read: (samples: [HeartRateSample], avg: Double, max: Double, min: Double)? =
                [nil, (samples, 0, 150, 80), (samples, 121, 150, 80), ([], 121, 150, 80)][Int.random(in: 0..<4, using: &g)]
            let fetched: Double? = Bool.random(using: &g) ? 133 : nil
            var update = HealthKitManager.HealthImportUpdate(id: existing.id, date: nil, distanceKm: 4.4, durationSec: 1_234,
                                                             calories: 222, workoutType: "Running", workoutName: "Read")
            // As importWorkoutIdempotent fills it.
            if existing.avgHeartRate == nil || existing.avgHeartRate == 0 {
                if isStrength {
                    if let (s, avg, max, min) = read, avg > 0 {
                        update.avgHeartRate = .some(avg); update.maxHeartRate = max; update.minHeartRate = min; update.hrSamples = s
                    }
                } else {
                    update.avgHeartRate = .some(fetched)
                }
            }
            XCTAssertEqual(update.edit.applied(to: existing),
                           Self.legacyImportUpdate(existing, km: 4.4, sec: 1_234, kcal: 222, type: "Running", name: "Read",
                                                   strength: isStrength ? .some(read) : nil, fetchedHR: fetched))
        }
    }

    // MARK: - The accepted change: no stale write-back

    /// A writer reads a run, waits for HealthKit, and meanwhile the route queue stores the
    /// run's route. Writing back the copy it read (the old manual refresh and import update)
    /// lost that route; the edit by id keeps both changes.
    func testAnEditThatOverlapsAnotherChangeLosesNothing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RunEditTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let walk = Run(date: Self.start, distanceKm: 3, durationSec: 1_500, healthKitUUID: UUID(), avgHeartRate: 0,
                       workoutType: "Walking")
        let storage = WorkoutStorage(directory: directory)
        try await storage.saveWorkouts([], prIndex: [:])
        try await storage.saveRuns([walk])
        defaults.set(true, forKey: "runs.deduplication.v1")
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()

        // The writer starts: it reads what it needs (the summary) and goes to HealthKit.
        let staleCopy = try XCTUnwrap(store.runSummary(id: walk.id))
        // Meanwhile the route queue stores the route.
        let route = (0..<5).map { RoutePoint(lat: 48 + Double($0) * 0.001, lon: 16, t: Self.start, hr: 120) }
        store.editRun(RunEdit(id: walk.id, route: .some(route.map { Coordinate(lat: $0.lat, lon: $0.lon) }),
                              routeWithHR: .some(route)))
        // The writer comes back with heart rate and the totals HealthKit reports.
        var update = HealthKitManager.HealthImportUpdate(id: staleCopy.id, date: nil, distanceKm: 3.1, durationSec: 1_510,
                                                         calories: 180, workoutType: "Walking", workoutName: nil)
        update.avgHeartRate = .some(122)
        XCTAssertTrue(store.editRun(update.edit))
        try await store.flushHealthKitChanges()

        // Both changes are in memory and on disk.
        let reloaded = try await WorkoutStorage(directory: directory).loadRuns()
        for run in [try XCTUnwrap(store.runDetail(id: walk.id).run), try XCTUnwrap(reloaded.first)] {
            XCTAssertEqual(run.routeWithHR?.count, 5, "the route stored meanwhile is kept")
            XCTAssertEqual(run.avgHeartRate, 122)
            XCTAssertEqual(run.distanceKm, 3.1)
        }

        // What the old write-back did with the same interleaving: the route is gone.
        var oldWriteBack = walk
        oldWriteBack.distanceKm = 3.1
        oldWriteBack.avgHeartRate = 122
        XCTAssertNil(oldWriteBack.routeWithHR)
    }

    func testEditsOfAGoneWorkoutAreDroppedAndUnchangedEditsWriteNothing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RunEditTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let run = Run(date: Self.start, distanceKm: 3, durationSec: 1_500, healthKitUUID: UUID())
        let storage = WorkoutStorage(directory: directory)
        try await storage.saveWorkouts([], prIndex: [:])
        try await storage.saveRuns([run])
        defaults.set(true, forKey: "runs.deduplication.v1")
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        let runsFile = directory.appendingPathComponent("runs_v2.json")
        let stamp = FileStamp(runsFile)

        XCTAssertFalse(store.editRun(RunEdit(id: UUID(), light: { $0.distanceKm = 9 })), "no such workout")
        XCTAssertFalse(store.editRun(RunEdit(id: run.id, light: { $0.distanceKm = 3 })), "nothing changes")
        XCTAssertTrue(store.editRuns([]).isEmpty)
        let none = await store.editRunsIfStoredFormChanges([RunEdit(id: run.id, light: { $0.date = Self.start.addingTimeInterval(0.4) })])
        XCTAssertTrue(none.isEmpty, "a change below the file's precision is not written")
        try await store.flushHealthKitChanges()
        XCTAssertEqual(FileStamp(runsFile), stamp)
    }
}
