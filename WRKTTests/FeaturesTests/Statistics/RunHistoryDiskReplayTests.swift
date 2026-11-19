import CryptoKit
import SwiftData
import XCTest
@testable import WRKT

/// A scripted sequence of the Health writers' changes (imports, updates, a Health heart-rate
/// refetch, route queue passes, a batch from a full resync, a failed write and its retry, a
/// delete), flushed as the anchor commit does after each. After every step the runs file must
/// hold exactly the bytes recorded before the writers moved to the edit API, and a step that
/// wrote nothing then must write nothing now. Record with `TEST_RUNNER_VOLIA_RECORD_DISK_REPLAY=1`.
@MainActor
final class RunHistoryDiskReplayTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var container: ModelContainer!
    private var store: WorkoutStoreV2!

    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "RunHistoryDiskReplayTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        container = try ModelContainer(for: RouteFetchTask.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        store = nil
    }

    // MARK: - Fixtures

    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    /// Sub-second, as HealthKit reports dates: the file keeps whole seconds.
    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000.25)

    private static func points(_ count: Int) -> [RoutePoint] {
        (0..<count).map { i in
            RoutePoint(lat: 48.2 + Double(i) * 0.001, lon: 16.3 + Double(i) * 0.001,
                       t: start.addingTimeInterval(Double(i) * 5 + 0.37), hr: 140 + Double(i))
        }
    }

    private static var routed: Run {
        let route = points(5)
        return Run(id: id(1), date: start.addingTimeInterval(1800), distanceKm: 5.123456789, durationSec: 1800,
                   healthKitUUID: id(101), avgHeartRate: 142.33333333333334, maxHeartRate: 144.5, minHeartRate: 139.5,
                   hrSamples: (0..<6).map { HeartRateSample(timestamp: start.addingTimeInterval(Double($0) * 4.2 + 0.613), bpm: 139.5 + Double($0)) },
                   calories: 312.7, route: route.map { Coordinate(lat: $0.lat, lon: $0.lon) }, routeWithHR: route,
                   splits: [KilometerSplit(number: 1, distanceKm: 1, durationSec: 352)], workoutType: "Running",
                   avgRunningPower: 251.1, avgCadence: 171.25, avgStrideLength: 1.12, avgGroundContactTime: 241.5,
                   avgVerticalOscillation: 8.4)
    }

    private static var routeless: Run {
        Run(id: id(2), date: start.addingTimeInterval(-86_400), distanceKm: 3.2, durationSec: 1_400,
            healthKitUUID: id(102), avgHeartRate: 131, calories: 210, workoutType: "Walking")
    }

    private static var strength: Run {
        Run(id: id(3), date: start.addingTimeInterval(-2 * 86_400), distanceKm: 0, durationSec: 2_700,
            healthKitUUID: id(103), avgHeartRate: 0, calories: 300, workoutType: "Traditional Strength Training")
    }

    private static var imported: Run {
        Run(id: id(4), date: start.addingTimeInterval(3_600), distanceKm: 8.8, durationSec: 2_900,
            healthKitUUID: id(104), avgHeartRate: 150, calories: 640, workoutType: "Running", workoutName: "Long")
    }

    /// What a HealthKit read of the routeless walk returns once its route has arrived.
    private static var walkEnrichment: HealthKitManager.DetailedRunEnrichment {
        let route = points(7)
        return .init(distanceKm: 3.2, durationSec: 1_400, calories: 210, workoutType: "Walking", workoutName: nil,
                     route: route.map { Coordinate(lat: $0.lat, lon: $0.lon) }, routeWithHR: route,
                     splits: [KilometerSplit(number: 1, distanceKm: 1, durationSec: 430)], avgHeartRate: 131.5,
                     maxHeartRate: 150, minHeartRate: 120,
                     hrSamples: [HeartRateSample(timestamp: start.addingTimeInterval(0.5), bpm: 125)],
                     avgRunningPower: nil, avgCadence: nil, avgStrideLength: nil, avgGroundContactTime: nil,
                     avgVerticalOscillation: nil)
    }

    // MARK: - Harness: the writers' operations

    private func importUpdate(distanceKm: Double) {
        guard var run = store.runs.first(where: { $0.id == Self.routed.id }) else { return XCTFail("missing") }
        run.distanceKm = distanceKm
        run.calories = 320
        store.updateRun(run)
    }

    private func strengthHeartRateRefetch() {
        guard var run = store.runs.first(where: { $0.id == Self.strength.id }) else { return XCTFail("missing") }
        run.avgHeartRate = 118
        run.maxHeartRate = 151
        run.minHeartRate = 72
        run.hrSamples = (0..<4).map { HeartRateSample(timestamp: Self.start.addingTimeInterval(Double($0) * 60 + 0.25), bpm: 100 + Double($0)) }
        store.updateRun(run)
    }

    private func resyncBatch() {
        var updates: [Run] = []
        for id in [Self.routed.id, Self.imported.id] {
            guard var run = store.runs.first(where: { $0.id == id }) else { return XCTFail("missing") }
            run.workoutName = "Renamed \(id.uuidString.suffix(1))"
            run.durationSec += 1
            updates.append(run)
        }
        store.batchUpdateRuns(updates)
    }
    // END HARNESS

    // MARK: - Recording

    private struct Step: Codable, Equatable {
        var name: String
        /// SHA-256 of the runs file after the step, nil when the file was not written.
        var written: String?
        var flushFailed: Bool
    }

    private var steps: [Step] = []
    private var lastStamp: FileStamp?

    private func record(_ name: String, flushFailed: Bool = false) throws {
        let stamp = FileStamp(runsFile)
        let wrote = stamp != lastStamp
        lastStamp = stamp
        var hash: String?
        if wrote, let data = try? Data(contentsOf: runsFile) {
            hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        steps.append(Step(name: name, written: hash, flushFailed: flushFailed))
    }

    private func flush(_ name: String) async throws {
        try await store.flushHealthKitChanges()
        try record(name)
    }

    private static let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("RunHistoryDiskReplay.json")

    func testScriptedWritesLeaveTheRecordedBytes() async throws {
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts([], prIndex: [:])
        try await previous.saveRuns([Self.routed, Self.routeless, Self.strength])
        defaults.set(true, forKey: "runs.deduplication.v1")
        store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        let manager = HealthKitManager()
        manager.modelContext = container.mainContext
        manager.workoutStore = store
        lastStamp = FileStamp(runsFile)

        try await flush("load")

        store.addRun(Self.imported)
        try await flush("import new")

        store.addRun(Self.imported)
        try await flush("import duplicate")

        importUpdate(distanceKm: 5.2)
        try await flush("import update")

        importUpdate(distanceKm: 5.2)
        try await flush("import update unchanged")

        strengthHeartRateRefetch()
        try await flush("strength heart rate")

        let walkTask = RouteFetchTask(workoutUUID: Self.routeless.healthKitUUID!.uuidString,
                                      workoutDate: Self.routeless.date, allowAutoPost: false)
        container.mainContext.insert(walkTask)
        try container.mainContext.save()
        _ = await manager.processRouteFetchQueue { _ in Self.walkEnrichment }
        XCTAssertEqual(walkTask.status, "completed")
        try record("route queue new route")

        let again = RouteFetchTask(workoutUUID: Self.routeless.healthKitUUID!.uuidString,
                                   workoutDate: Self.routeless.date, allowAutoPost: false)
        container.mainContext.insert(again)
        try container.mainContext.save()
        _ = await manager.processRouteFetchQueue { _ in Self.walkEnrichment }
        try record("route queue nothing new")

        resyncBatch()
        try await flush("resync batch")

        // A failed write: the runs file's path is blocked, the change stays unsaved.
        let aside = directory.appendingPathComponent("aside.json")
        try FileManager.default.moveItem(at: runsFile, to: aside)
        try FileManager.default.createDirectory(at: runsFile, withIntermediateDirectories: false)
        importUpdate(distanceKm: 5.3)
        var failed = false
        do { try await store.flushHealthKitChanges() } catch { failed = true }
        XCTAssertTrue(failed, "a blocked write must be reported")
        try FileManager.default.removeItem(at: runsFile)
        try FileManager.default.moveItem(at: aside, to: runsFile)
        lastStamp = FileStamp(runsFile)
        try record("failed write", flushFailed: failed)
        try await flush("retry after failure")

        store.removeRun(withId: Self.strength.id)
        try await flush("delete")

        store.removeRun(withId: Self.strength.id)
        try await flush("delete missing")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["VOLIA_RECORD_DISK_REPLAY"] == "1" {
            try encoder.encode(steps).write(to: Self.golden)
            return
        }
        let recorded = try JSONDecoder().decode([Step].self, from: Data(contentsOf: Self.golden))
        XCTAssertEqual(steps.count, recorded.count)
        for (now, then) in zip(steps, recorded) {
            XCTAssertEqual(now, then, "step \(then.name)")
        }
    }
}
