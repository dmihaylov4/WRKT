import XCTest
@testable import WRKT

/// The migration (spec 7.1) on the file system model: the result, every failure, and a kill or
/// a power loss at every file system call, including a second one during the retry. After any
/// cut the next launch has either no runs_v3 (the history is still runs_v2.json, untouched by
/// the migration) or a complete runs_v3 equal to the source: never a mixture, never a loss.
final class RunsV3MigrationTests: XCTestCase {
    private let layout = V3.layout
    private var staging: URL { RunsV3Migration.stagingURL(V3.storage) }

    private static let v2 = RunsV3BaselineV1.V2State(present: true, size: 1234, modified: V3.start, fileNumber: 77,
                                                     sha256: String(repeating: "a", count: 64), decodable: true)

    private static func source(_ runs: [Run]) -> RunsV3Migration.Source { .init(runs: runs, v2: v2) }

    private static var mixed: [Run] {
        var withMarker = V3.run(1, points: 6, samples: 3, splits: 2)          // route repeats routeWithHR: left out
        withMarker.workoutName = "marker"
        let routeOnly = Run(id: V3.id(2), date: V3.start, distanceKm: 2, durationSec: 600,
                            route: [Coordinate(lat: 1, lon: 2), Coordinate(lat: 3, lon: 4)], workoutType: "Walking")
        var emptyArrays = V3.run(3)
        emptyArrays.splits = []
        emptyArrays.routeWithHR = []
        emptyArrays.hrSamples = []
        let absentArrays = V3.run(4)
        var sameHealthID = V3.run(5)
        sameHealthID.healthKitUUID = absentArrays.healthKitUUID                // duplicate Health ids migrate as they are
        let differentRoute = V3.run(6, points: 4, repeatRoute: false)
        // History order is not date order.
        return [V3.run(9), withMarker, routeOnly, emptyArrays, absentArrays, sameHealthID, differentRoute, V3.run(8)]
    }

    private func freshStorage() -> ModelFileSystem {
        let fs = ModelFileSystem()
        fs.makeDirectories(V3.storage)
        fs.put(Data("v2 bytes".utf8), at: V3.storage.appendingPathComponent("runs_v2.json"))
        fs.settle()
        return fs
    }

    @discardableResult
    private func migrate(_ runs: [Run], on fs: ModelFileSystem, unchanged: Bool = true) throws -> RunsV3Migration.Outcome {
        try RunsV3Migration.migrate(Self.source(runs), storage: V3.storage, environment: V3.environment(fs),
                                    sourceUnchanged: { unchanged })
    }

    /// The history a launch would show on `fs`: nil when runs_v3 is not active.
    private func launch(_ fs: ModelFileSystem, file: StaticString = #filePath, line: UInt = #line) -> [Run]? {
        let store = V3.store(fs)
        switch store.open(isProtectedDataAvailable: true) {
        case .notActive: return nil
        case .active:
            _ = try? store.repair()
            return store.history.map { entry -> Run in
                guard case .loaded(let run) = store.readRun(id: entry.id) else {
                    XCTFail("unreadable \(entry.id)", file: file, line: line)
                    return V3.run(0)
                }
                XCTAssertEqual(entry.summary, RunSummary(run), file: file, line: line)
                return run
            }
        case let other:
            XCTFail("unexpected \(other)", file: file, line: line)
            return nil
        }
    }

    private func assertEqualStoredForm(_ a: [Run], _ b: [Run], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let encoder = RunsV3.makeEncoder()
        XCTAssertEqual(a.map(\.id), b.map(\.id), "\(label): order", file: file, line: line)
        XCTAssertEqual(a.map { try! encoder.encode(StoredRun($0)) }, b.map { try! encoder.encode(StoredRun($0)) },
                       "\(label): stored form", file: file, line: line)
    }

    // MARK: - Results

    func testEveryShapeOfWorkoutMigratesExactly() throws {
        for runs in [Self.mixed, [], [V3.run(1, points: 3)]] {
            let fs = freshStorage()
            let outcome = try migrate(runs, on: fs)
            XCTAssertEqual(outcome.workoutCount, runs.count)
            XCTAssertTrue(outcome.switchDurable)
            let migrated = try XCTUnwrap(launch(fs))
            assertEqualStoredForm(migrated, runs, "\(runs.count) workouts")
            XCTAssertEqual(migrated, runs)
            XCTAssertFalse(fs.exists(staging))
            XCTAssertEqual(fs.names(in: layout.tmp), [])
            XCTAssertEqual(fs.contents(of: V3.storage.appendingPathComponent("runs_v2.json")), Data("v2 bytes".utf8), "runs_v2.json is never written")
            let decoder = RunsV3.makeDecoder()
            let baseline = try decoder.decode(RunsV3BaselineV1.self, from: XCTUnwrap(fs.contents(of: layout.baseline)))
            XCTAssertEqual(baseline.v2, Self.v2)
            XCTAssertEqual(baseline.entries.map(\.id), runs.map(\.id))
            XCTAssertEqual(baseline.entries.map(\.hash), runs.map(StoredRun.normalHash))
            XCTAssertEqual(baseline.entries.map(\.seq), runs.indices.map { Int64(runs.count - $0) })
            let format = try decoder.decode(RunsV3FormatV1.self, from: XCTUnwrap(fs.contents(of: layout.format)))
            XCTAssertEqual(format.migratedFrom, .init(fileName: "runs_v2.json", size: 1234, sha256: Self.v2.sha256!, workoutCount: runs.count))
        }
    }

    /// Real clocks and file dates carry fractions of a second; the files keep whole seconds.
    /// Verification compares as stored (found on the real disk, where the model's whole-second
    /// clock had hidden it).
    func testSubSecondDatesVerify() throws {
        let fs = freshStorage()
        let sources = V3.Sources(now: Date(timeIntervalSince1970: 1_790_000_000.731))
        let v2 = RunsV3BaselineV1.V2State(present: true, size: 10, modified: Date(timeIntervalSince1970: 1_789_000_000.257),
                                          fileNumber: 3, sha256: String(repeating: "b", count: 64), decodable: true)
        _ = try RunsV3Migration.migrate(.init(runs: Self.mixed, v2: v2), storage: V3.storage,
                                        environment: V3.environment(fs, sources), sourceUnchanged: { true })
        XCTAssertEqual(launch(fs), Self.mixed)
    }

    func testTheNormalHashIgnoresOnlyARepeatedOrMissingRoute() {
        var run = V3.run(1, points: 4)
        var stripped = run
        stripped.route = nil
        XCTAssertEqual(StoredRun.normalHash(run), StoredRun.normalHash(stripped), "a 5.4.3 rewrite without the marker compares equal")
        run.route = [Coordinate(lat: 9, lon: 9)]
        XCTAssertNotEqual(StoredRun.normalHash(run), StoredRun.normalHash(stripped), "a different route is a change")
        var renamed = stripped
        renamed.workoutName = "x"
        XCTAssertNotEqual(StoredRun.normalHash(renamed), StoredRun.normalHash(stripped))
    }

    func testAnExistingRunsV3IsNeverMigratedOver() throws {
        let fs = freshStorage()
        V3.seed(fs, [V3.run(1)])
        XCTAssertThrowsError(try migrate([V3.run(2)], on: fs))
        XCTAssertEqual(launch(fs)?.map(\.id), [V3.id(1)])
    }

    func testALeftoverStagingDirectoryIsDisposable() throws {
        let fs = freshStorage()
        fs.put(Data("old".utf8), at: staging.appendingPathComponent("runs/junk.json"))
        try migrate(Self.mixed, on: fs)
        XCTAssertEqual(launch(fs), Self.mixed)
    }

    func testASourceThatChangedBeforeTheSwitchAborts() throws {
        let fs = freshStorage()
        XCTAssertThrowsError(try migrate(Self.mixed, on: fs, unchanged: false)) { error in
            XCTAssertEqual((error as? RunsV3Migration.Failure)?.step, .sourceChanged)
        }
        XCTAssertNil(launch(fs))
        XCTAssertFalse(fs.exists(staging), "only staging is removed")
        XCTAssertTrue(fs.exists(V3.storage.appendingPathComponent("runs_v2.json")))
    }

    /// Disk full, the device locking (EPERM), an I/O error: at every call, the attempt fails,
    /// staging is removed, nothing else changes, and the next attempt succeeds.
    func testAFailureAtEveryCallLeavesTheV2HistoryAndALaterAttemptSucceeds() throws {
        let reference = freshStorage()
        let start = reference.callCount
        try migrate(Self.mixed, on: reference)
        let total = reference.callCount - start
        var failures = 0
        for code in [ENOSPC, EPERM, EIO] {
            for index in 0..<total {
                let fs = freshStorage()
                fs.failCall = (fs.callCount + index, code)
                do {
                    try migrate(Self.mixed, on: fs)
                } catch {
                    failures += 1
                }
                fs.failCall = nil
                if let migrated = launch(fs) {
                    // The failed call was after the switch (the final barrier): still complete.
                    XCTAssertEqual(migrated, Self.mixed, "code \(code) at \(index)")
                    continue
                }
                XCTAssertFalse(fs.exists(staging), "code \(code) at \(index): staging removed")
                try migrate(Self.mixed, on: fs)
                XCTAssertEqual(launch(fs), Self.mixed, "code \(code) at \(index): retry")
            }
        }
        print("migration failures injected: \(failures) of \(3 * total)")
    }

    /// A kill or a power loss at every call, then a fresh launch; when the history is still on
    /// v2, a retry that is itself cut at every call, then a third launch.
    func testEveryCrashPointOfTheMigration() throws {
        let reference = freshStorage()
        let start = reference.callCount
        try migrate(Self.mixed, on: reference)
        let total = reference.callCount - start
        var cases = 0
        var completed = 0
        for cut in 0...total {
            let strategies: [(String, (ModelFileSystem) -> ModelFileSystem)] = [
                ("kill", { $0.afterKill() }),
                ("power durableOnly", { $0.afterPowerLoss(.durableOnly) }),
                ("power random", { $0.afterPowerLoss(.random(UInt64(cut) &* 977 &+ 3)) }),
            ]
            for (name, after) in strategies {
                let fs = freshStorage()
                fs.killAfterCalls = fs.callCount + cut
                _ = try? migrate(Self.mixed, on: fs)
                let survivor = after(fs)
                let label = "\(name) at \(cut)"
                XCTAssertEqual(survivor.contents(of: V3.storage.appendingPathComponent("runs_v2.json")), Data("v2 bytes".utf8), label)
                if let migrated = launch(survivor) {
                    assertEqualStoredForm(migrated, Self.mixed, label)
                    completed += 1
                    cases += 1
                    continue
                }
                // Still on v2: the retry, cut again at a few points, then a clean one.
                for second in [0, 7, 23, 41, total / 2, total - 3] where second >= 0 {
                    let again = survivor.copy()
                    again.killAfterCalls = again.callCount + second
                    _ = try? migrate(Self.mixed, on: again)
                    let third = again.afterPowerLoss(.durableOnly)
                    if let migrated = launch(third) {
                        assertEqualStoredForm(migrated, Self.mixed, "\(label), retry cut at \(second)")
                    } else {
                        try migrate(Self.mixed, on: third)
                        assertEqualStoredForm(try XCTUnwrap(launch(third)), Self.mixed, "\(label), retry cut at \(second), then clean")
                    }
                    cases += 1
                }
                try migrate(Self.mixed, on: survivor)
                assertEqualStoredForm(try XCTUnwrap(launch(survivor)), Self.mixed, "\(label): retry")
                cases += 1
            }
        }
        print("migration crash matrix: \(total) calls, \(cases) cases, \(completed) cut after the switch")
    }
}
