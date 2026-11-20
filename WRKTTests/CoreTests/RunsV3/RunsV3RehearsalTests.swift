import Darwin
import XCTest
@testable import WRKT

/// Opt-in, on a real history (`VOLIA_RUNS_FILE`, read only; temporary copies deleted), with
/// `VOLIA_RUNS_V3_REHEARSAL=1`: the rollback rehearsal simulated. Migrate on this build, change
/// the history on runs_v3, act as an older build on runs_v2.json (today's v2 path standing in for
/// a pre-Stage-2 build; separately 5.4.3's behaviour: a rewrite without the marker, an import,
/// a delete, an edit, and the last 14 days imported again under new ids), return to runs_v3 and
/// merge. Reports the history against what it should be. Also measures the export's memory.
@MainActor
final class RunsV3RehearsalTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3Rehearsal-" + UUID().uuidString)
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

    private func store(_ directory: URL, _ defaults: UserDefaults, gate: Bool) async throws -> WorkoutStoreV2 {
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory, availableCapacity: { _ in 50_000_000_000 }),
                                   defaults: defaults, protectedDataAvailable: { true }, migrationGate: { gate },
                                   isHealthImportRunning: { false })
        store.migrationDelay = .seconds(3600)
        store.mergeDelay = .seconds(3600)
        try await store.waitForStorage()
        return store
    }

    private static func newWorkout(_ n: Int, daysAgo: Double) -> Run {
        var run = V3.run(n, points: 300, samples: 60, splits: 3, name: "workout \(n)")
        run.id = UUID()
        run.healthKitUUID = UUID()
        run.date = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - daysAgo * 86_400).rounded(.down))
        return run
    }

    private func encoded(_ store: WorkoutStoreV2) async throws -> [Data] {
        let encoder = RunsV3.makeEncoder()
        var result: [Data] = []
        for summary in store.runSummaries {
            guard case .loaded(let run) = try await store.loadRun(id: summary.id) else { result.append(Data("unreadable".utf8)); continue }
            result.append(try encoder.encode(StoredRun(StoredRun.normalForm(run))))
        }
        return result
    }

    func testTheRollbackRehearsal() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty,
              ProcessInfo.processInfo.environment["VOLIA_RUNS_V3_REHEARSAL"] == "1" else {
            throw XCTSkip("Set VOLIA_RUNS_FILE and VOLIA_RUNS_V3_REHEARSAL=1 to run")
        }
        var real: [Run] = []
        try autoreleasepool {
            real = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).map(\.run)
        }
        let markerCount = real.filter(StoredRun.routeRepeatsRouteWithHR).count

        for scenario in ["pre-Stage-2 build", "5.4.3"] {
            let suite = "RunsV3Rehearsal." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(true, forKey: "runs.deduplication.v1")
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = root.appendingPathComponent("\(scenario)/WRKT_Storage")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent(".migrated"))
            try await WorkoutStorage(directory: directory).saveRuns(real)
            let runsFile = directory.appendingPathComponent("runs_v2.json")

            // 1. Migrate on this build.
            let v3 = try await store(directory, defaults, gate: true)
            let migration = await v3.migrateRunHistoryIfAllowed()
            XCTAssertEqual(migration, .migrated)

            // 2. On runs_v3: two new workouts (within 14 days), a delete, an edit.
            let a1 = Self.newWorkout(900_001, daysAgo: 3)
            let a2 = Self.newWorkout(900_002, daysAgo: 1)
            v3.addRun(a1)
            v3.addRun(a2)
            let deletedOnV3 = real[5].id
            let editedOnV3 = real[6].id
            v3.removeRun(withId: deletedOnV3)
            v3.editRun(RunEdit(id: editedOnV3, light: { $0.workoutName = "edited on v3" }))
            try await v3.flushHealthKitChanges()

            // 3. The older build, on runs_v2.json.
            let b1 = Self.newWorkout(900_010, daysAgo: 0.5)
            let deletedOnOld = real[10].id
            let editedOnOld = real[11].id
            var a1Again = a1
            a1Again.id = UUID()
            var a2Again = a2
            a2Again.id = UUID()
            if scenario == "pre-Stage-2 build" {
                let aside = directory.deletingLastPathComponent().appendingPathComponent("runs_v3.aside")
                try FileManager.default.moveItem(at: directory.appendingPathComponent("runs_v3"), to: aside)
                let old = try await store(directory, defaults, gate: false)
                XCTAssertFalse(old.isOnPerWorkoutHistory)
                old.addRun(a1Again)   // syncRecentWorkouts: the last 14 days again, new ids
                old.addRun(a2Again)
                old.addRun(b1)
                old.removeRun(withId: deletedOnOld)
                old.editRun(RunEdit(id: editedOnOld, light: { $0.workoutName = "edited on the older build" }))
                try await old.flushHealthKitChanges()
                try FileManager.default.moveItem(at: aside, to: directory.appendingPathComponent("runs_v3"))
            } else {
                var runs = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: runsFile)).map(\.run)
                runs.insert(contentsOf: [b1, a2Again, a1Again], at: 0)
                runs.removeAll { $0.id == deletedOnOld }
                if let i = runs.firstIndex(where: { $0.id == editedOnOld }) { runs[i].workoutName = "edited on the older build" }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                encoder.dateEncodingStrategy = .iso8601
                let asWritten = runs.map { run -> Run in
                    var copy = run
                    if StoredRun.routeRepeatsRouteWithHR(copy) { copy.route = nil }   // 5.4.3 drops the marker
                    return copy
                }
                try encoder.encode(asWritten).write(to: runsFile, options: .atomic)
            }

            // 4. Back on runs_v3: the merge.
            let back = try await store(directory, defaults, gate: false)
            XCTAssertTrue(back.isOnPerWorkoutHistory)
            var record: RunHistoryMergeRecord?
            let base = Self.heap()
            let start = DispatchTime.now().uptimeNanoseconds
            let peak = try await Self.peak { record = await back.mergeOlderBuildChangesIfNeeded() }
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            let after = try await store(directory, defaults, gate: false)

            // What it should be.
            var expected = real.filter { $0.id != deletedOnV3 && $0.id != deletedOnOld }
            if let i = expected.firstIndex(where: { $0.id == editedOnV3 }) { expected[i].workoutName = "edited on v3" }
            if let i = expected.firstIndex(where: { $0.id == editedOnOld }) { expected[i].workoutName = "edited on the older build" }
            expected = [b1, a2, a1] + expected
            let expectedEncoded = try expected.map { try RunsV3.makeEncoder().encode(StoredRun(StoredRun.normalForm($0))) }
            let actualEncoded = try await encoded(after)
            let orderMatches = after.runSummaries.map(\.id) == expected.map(\.id)
            let mismatches = zip(actualEncoded, expectedEncoded).filter { $0 != $1 }.count + abs(actualEncoded.count - expectedEncoded.count)
            let duplicates = after.runSummaries.count - Set(after.runSummaries.compactMap(\.healthKitUUID)).count
                - after.runSummaries.filter { $0.healthKitUUID == nil }.count
            print("""
            rehearsal [\(scenario)]: merge \(record?.outcome ?? "none") \(record?.counts.map { "\($0)" } ?? ""); \
            expected \(expected.count) workouts, got \(after.runSummaries.count); order \(orderMatches ? "matches" : "differs"); \
            stored-form mismatches \(mismatches); Health duplicates \(duplicates); \
            v3 delete resurrected \(after.runSummary(id: deletedOnV3) != nil); \
            re-imported copies present \(after.runSummary(id: a1Again.id) != nil || after.runSummary(id: a2Again.id) != nil); \
            marker workouts \(markerCount), replaced \(record?.counts?.replaced ?? -1); \
            merge \(String(format: "%.2f", seconds)) s, peak heap +\(Self.mb(max(0, peak - base)))
            """)
            XCTAssertEqual(record?.outcome, "merged")
            XCTAssertEqual(record?.counts?.replaced, 1, "only the older build's one edit; the marker-free rewrite is not an edit")
            XCTAssertEqual(record?.counts?.added, 1)
            XCTAssertEqual(record?.counts?.deduplicated, 2)
            XCTAssertEqual(record?.counts?.trashed, 1)
            XCTAssertTrue(orderMatches)
            XCTAssertEqual(mismatches, 0)
            XCTAssertEqual(duplicates, 0)
            // A launch after: nothing more.
            let again = try await store(directory, defaults, gate: false)
            let next = await again.mergeOlderBuildChangesIfNeeded()
            XCTAssertEqual(next?.outcome, "unchanged: runs_v2.json as recorded")

            // The export of this history, with and without routes: memory stays flat.
            for routes in [true, false] {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                var bundle = ExportBundle(version: ExportBundle.currentVersion, appVersion: "test", exportedAt: .now,
                                          completedWorkouts: [], earnedPlates: [])
                bundle.runsWithoutDetail = !routes
                let url = root.appendingPathComponent("export-\(routes).json")
                let exportBase = Self.heap()
                let exportStart = DispatchTime.now().uptimeNanoseconds
                let exportPeak = try await Self.peak {
                    try await DataPortabilityService.writeStreaming(head: try encoder.encode(bundle), to: url, encoder: encoder) { emit in
                        _ = try await again.exportRuns { run in try emit(StoredRun(routes ? run : ExportBundle.withoutDetail(run))) }
                    }
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                let decoded = try RunsV3.makeDecoder().decode(ExportBundle.self, from: Data(contentsOf: url))
                print("export [\(scenario), routes \(routes)]: \(decoded.runs?.count ?? 0) workouts, file \(Self.mb(size)), "
                      + String(format: "%.1f s", Double(DispatchTime.now().uptimeNanoseconds - exportStart) / 1e9)
                      + ", peak heap +\(Self.mb(max(0, exportPeak - exportBase)))")
                XCTAssertEqual(decoded.runs?.map(\.run.id), after.runSummaries.map(\.id))
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
