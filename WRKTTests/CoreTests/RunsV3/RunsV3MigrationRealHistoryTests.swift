import Darwin
import XCTest
@testable import WRKT

/// Opt-in: migrates a real history in a temporary directory and reports time, memory and sizes,
/// compares the migrated history with the source, relaunches, and runs a scripted day of use on
/// the migrated copy and on a v2 copy. Set `VOLIA_RUNS_FILE` (read only, never copied outside the
/// temporary directory, which is deleted) and `VOLIA_RUNS_V3_MIGRATION=1`. Counts only.
@MainActor
final class RunsV3MigrationRealHistoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3MigrationReal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private static func heap() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    private static func peak(during body: () async throws -> Void) async rethrows -> Int {
        final class Sampler: @unchecked Sendable { let lock = NSLock(); var highest = 0; var running = true }
        let sampler = Sampler()
        let thread = Thread {
            while sampler.lock.withLock({ sampler.running }) {
                let now = Self.heap()
                sampler.lock.withLock { sampler.highest = max(sampler.highest, now) }
                usleep(500)
            }
        }
        thread.start()
        try await body()
        sampler.lock.withLock { sampler.running = false }
        return sampler.lock.withLock { sampler.highest }
    }

    private static func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    private static func elapsed(_ start: UInt64) -> String { String(format: "%.0f ms", Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6) }

    private static func directorySize(_ url: URL) -> Int {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return walker.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
    }

    private func makeStore(_ directory: URL, _ defaults: UserDefaults, gate: Bool) -> WorkoutStoreV2 {
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory, availableCapacity: { _ in 50_000_000_000 }),
                                   defaults: defaults, protectedDataAvailable: { true }, migrationGate: { gate },
                                   isHealthImportRunning: { false })
        store.migrationDelay = .seconds(3600)
        return store
    }

    private func stored(_ store: WorkoutStoreV2) async throws -> [Data] {
        let encoder = RunsV3.makeEncoder()
        var result: [Data] = []
        for summary in store.runSummaries {
            guard case .loaded(let run) = try await store.loadRun(id: summary.id) else { throw XCTSkip("unreadable \(summary.id)") }
            result.append(try encoder.encode(StoredRun(run)))
        }
        return result
    }

    /// A day of use: an import, an enrichment, an edit, a delete; then a relaunch.
    private func dayOfUse(_ store: WorkoutStoreV2, ids: [UUID]) async throws {
        var imported = V3.run(990_100, points: 1_200, samples: 400, splits: 8, name: "Day of use")
        imported.id = UUID(uuidString: "99999999-0000-0000-0000-000000000001")!
        imported.healthKitUUID = UUID(uuidString: "99999999-0000-0000-0000-000000000002")!
        store.addRun(imported)
        try await store.flushHealthKitChanges()
        let route = (0..<500).map { RoutePoint(lat: 48 + Double($0) * 0.0001, lon: 16, t: V3.start.addingTimeInterval(Double($0)), hr: 140) }
        _ = await store.editRunsIfStoredFormChanges([RunEdit(id: ids[3], light: { $0.workoutName = "Enriched" },
                                                             route: .some(route.map { Coordinate(lat: $0.lat, lon: $0.lon) }),
                                                             routeWithHR: .some(route),
                                                             splits: .some([KilometerSplit(number: 1, distanceKm: 1, durationSec: 300)]))])
        try await store.flushHealthKitChanges()
        store.editRun(RunEdit(id: ids[10], light: { $0.calories = 123 }))
        store.removeRun(withId: ids[20])
        try await store.flushHealthKitChanges()
    }

    func testMigratingTheRealHistory() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty,
              ProcessInfo.processInfo.environment["VOLIA_RUNS_V3_MIGRATION"] == "1" else {
            throw XCTSkip("Set VOLIA_RUNS_FILE and VOLIA_RUNS_V3_MIGRATION=1 to run")
        }
        let suite = "RunsV3MigrationReal." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "runs.deduplication.v1")
        defer { defaults.removePersistentDomain(forName: suite) }
        let v3Dir = root.appendingPathComponent("a/WRKT_Storage")
        let v2Dir = root.appendingPathComponent("b/WRKT_Storage")
        var source: [Run] = []
        for directory in [v3Dir, v2Dir] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent(".migrated"))
        }
        try autoreleasepool {
            source = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).map(\.run)
        }
        for directory in [v3Dir, v2Dir] { try await WorkoutStorage(directory: directory).saveRuns(source) }
        let v2Size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: v3Dir.appendingPathComponent("runs_v2.json").path)[.size] as? Int)

        // Migrate.
        let store = makeStore(v3Dir, defaults, gate: true)
        try await store.waitForStorage()
        let base = Self.heap()
        var result: RunHistoryMigrationResult = .notAllowed
        var duration = ""
        let peak = try await Self.peak {
            let start = DispatchTime.now().uptimeNanoseconds
            result = await store.migrateRunHistoryIfAllowed()
            duration = Self.elapsed(start)
        }
        XCTAssertEqual(result, .migrated)
        let v3Size = Self.directorySize(v3Dir.appendingPathComponent("runs_v3"))
        let workoutBytes = Self.directorySize(v3Dir.appendingPathComponent("runs_v3/runs"))

        // Compare: every workout in stored form, the order, every summary.
        let relaunchStart = DispatchTime.now().uptimeNanoseconds
        let relaunched = makeStore(v3Dir, defaults, gate: false)
        try await relaunched.waitForStorage()
        let relaunchTime = Self.elapsed(relaunchStart)
        XCTAssertTrue(relaunched.isOnPerWorkoutHistory)
        XCTAssertEqual(relaunched.runSummaries.map(\.id), source.map(\.id), "order")
        XCTAssertEqual(relaunched.runSummaries, source.map(RunSummary.init), "summaries")
        let encoder = RunsV3.makeEncoder()
        let migrated = try await stored(relaunched)
        let expected = try source.map { try encoder.encode(StoredRun($0)) }
        let mismatches = zip(migrated, expected).filter { $0 != $1 }.count + abs(migrated.count - expected.count)
        XCTAssertEqual(mismatches, 0)
        XCTAssertEqual(try Data(contentsOf: v3Dir.appendingPathComponent("runs_v2.json")),
                       try Data(contentsOf: v2Dir.appendingPathComponent("runs_v2.json")), "runs_v2.json untouched")

        // A day of use on both copies, then a relaunch, then the same history.
        let ids = source.map(\.id)
        try await dayOfUse(relaunched, ids: ids)
        let v2Store = makeStore(v2Dir, defaults, gate: false)
        try await v2Store.waitForStorage()
        try await dayOfUse(v2Store, ids: ids)
        let v3After = makeStore(v3Dir, defaults, gate: false)
        try await v3After.waitForStorage()
        let v2After = makeStore(v2Dir, defaults, gate: false)
        try await v2After.waitForStorage()
        XCTAssertEqual(v3After.runSummaries.map(\.id), v2After.runSummaries.map(\.id))
        XCTAssertEqual(v3After.runSummaries, v2After.runSummaries)
        let v3Day = try await stored(v3After)
        let v2Day = try await stored(v2After)
        let dayMismatches = zip(v3Day, v2Day).filter { $0 != $1 }.count + abs(v3Day.count - v2Day.count)
        XCTAssertEqual(dayMismatches, 0)

        print("""
        runs_v3 real migration: \(source.count) workouts from a \(Self.mb(v2Size)) runs_v2.json; migration \(duration); \
        peak heap during it +\(Self.mb(max(0, peak - base))); workout files \(Self.mb(workoutBytes)); runs_v3 total \(Self.mb(v3Size)); \
        stored-form mismatches \(mismatches); relaunch to history ready \(relaunchTime); \
        day of use: \(v3After.runSummaries.count) workouts on both paths, \(dayMismatches) mismatches
        """)
    }
}
