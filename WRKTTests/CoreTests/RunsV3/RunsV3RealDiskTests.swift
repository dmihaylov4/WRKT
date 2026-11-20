import XCTest
@testable import WRKT

/// The store on the real file system (POSIX seam) in a temporary directory: a smoke test that
/// always runs, plus two opt-in runs.
///
/// - `VOLIA_RUNS_FILE=/path/to/runs_v2.json`: every workout of a real history goes through the
///   per-workout format and back with equal values. The file is read, never written or copied;
///   the temporary directory is deleted; only counts are printed.
/// - `VOLIA_RUNS_V3_PERF=1`: timings for spec section 10, on synthetic histories of 1,000 and
///   10,000 workouts (plus the largest real workout when `VOLIA_RUNS_FILE` is set).
final class RunsV3RealDiskTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3RealDisk-" + UUID().uuidString)
            .appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func store() -> RunsV3Store {
        RunsV3Store(storage: directory, environment: .init(fileSystem: POSIXDurableFileSystem(), now: { Date() },
                                                            random: { UInt16.random(in: 0...UInt16.max) },
                                                            token: { UUID() }, build: "test"))
    }

    /// A test-only stand-in for the migration: the directories, format.json, one file per run
    /// at revision 1 and the index, written directly.
    private func seed(_ runs: [Run], index: Bool = true) throws {
        let layout = RunsV3Layout(storage: directory)
        let fm = FileManager.default
        for url in [layout.runs, layout.trash, layout.tmp] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        let encoder = RunsV3.makeEncoder()
        var entries: [RunsV3IndexV1.Entry] = []
        entries.reserveCapacity(runs.count)
        for (i, run) in runs.enumerated() {
            let seq = Int64(runs.count - i)
            let data = try encoder.encode(RunFileV1(format: 1, id: run.id, rev: 1, seq: seq, run: StoredRun(run)))
            try data.write(to: layout.runFile(RunsV3FileName(id: run.id, rev: 1)))
            if index {
                entries.append(.init(id: run.id, rev: 1, seq: seq, size: data.count, sha256: RunsV3Store.sha256(data),
                                     summary: RunSummary(run)))
            }
        }
        try encoder.encode(RunsV3FormatV1(formatVersion: 1, minimumReaderVersion: 1, minimumWriterVersion: 1,
                                          createdAt: Date(), createdByBuild: "seed", migratedFrom: nil)).write(to: layout.format)
        if index {
            try encoder.encode(RunsV3IndexV1(formatVersion: 1, minimumReaderVersion: 1, generation: 1, entries: entries))
                .write(to: layout.index)
        }
    }

    func testTheRealFileSystemRoundTrip() throws {
        let runs = [V3.run(1, points: 50, samples: 10, splits: 3), V3.run(2), V3.run(3, points: 5, repeatRoute: false)]
        try seed(runs)
        let opened = store()
        XCTAssertEqual(opened.open(isProtectedDataAvailable: true), .active(.writable))
        try opened.repair()
        XCTAssertTrue(opened.drainOne(V3.id(4), .add(V3.run(4, points: 8), seq: opened.nextSeq)).isFullyDurable)
        XCTAssertTrue(opened.drainOne(V3.id(1), .edit { var run = $0; run.workoutName = "real"; return run }).isFullyDurable)
        XCTAssertTrue(opened.drainOne(V3.id(2), .delete).isFullyDurable)
        let back = store()
        XCTAssertEqual(back.open(isProtectedDataAvailable: true), .active(.writable))
        XCTAssertEqual(back.report.indexState, .valid)
        XCTAssertEqual(back.history.map(\.id), [V3.id(4), V3.id(1), V3.id(3)])
        guard case .loaded(let edited) = back.readRun(id: V3.id(1)) else { return XCTFail("not loaded") }
        var expected = runs[0]
        expected.workoutName = "real"
        XCTAssertEqual(edited, expected)
        try RunsV3Store.wipe(storage: directory, fileSystem: POSIXDurableFileSystem(), now: Date())
        XCTAssertEqual(store().open(isProtectedDataAvailable: true), .notActive)
    }

    func testEveryRealWorkoutRoundTripsThroughTheFormat() throws {
        guard let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty else {
            throw XCTSkip("Set VOLIA_RUNS_FILE to run against a real history file")
        }
        let decoder = RunsV3.makeDecoder()
        let runs = try decoder.decode([StoredRun].self, from: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).map(\.run)
        try seed(runs)
        let opened = store()
        XCTAssertEqual(opened.open(isProtectedDataAvailable: true), .active(.writable))
        XCTAssertEqual(opened.history.map(\.id), runs.map(\.id), "history order")
        var mismatches = 0
        var bytes = 0
        for run in runs {
            guard case .loaded(let back) = opened.readRun(id: run.id) else { mismatches += 1; continue }
            if back != run { mismatches += 1 }
            if opened.entries[run.id]?.summary != RunSummary(run) { mismatches += 1 }
            bytes += opened.entries[run.id]?.size ?? 0
        }
        // Rebuild without the index: the same history and order.
        try FileManager.default.removeItem(at: RunsV3Layout(storage: directory).index)
        let rebuilt = store()
        _ = rebuilt.open(isProtectedDataAvailable: true)
        XCTAssertEqual(rebuilt.history.map(\.id), runs.map(\.id))
        XCTAssertEqual(rebuilt.history.map(\.summary), runs.map(RunSummary.init))
        print("Real history through runs_v3: \(runs.count) workouts, \(mismatches) mismatches, \(bytes) bytes of workout files")
        XCTAssertEqual(mismatches, 0)
    }

    // MARK: - Performance (reported, not gating)

    private func measure(_ label: String, repeat count: Int = 5, _ body: () throws -> Void) rethrows {
        var times: [Double] = []
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        print(String(format: "runs_v3 perf: %@: median %.1f ms (of %d)", label, times.sorted()[times.count / 2], count))
    }

    /// A history shaped like the owner's: about 26 percent strength (no arrays), the rest walks
    /// and runs, one in eight with a route of a few hundred points.
    private func syntheticHistory(_ count: Int) -> [Run] {
        (0..<count).map { n in
            let routed = n % 8 == 0
            var run = V3.run(100_000 + n, points: routed ? 300 + n % 400 : 0, samples: n % 4 == 0 ? 0 : 60)
            run.id = UUID()
            return run
        }
    }

    func testPerformanceOfTheStoreOnTheRealFileSystem() throws {
        guard ProcessInfo.processInfo.environment["VOLIA_RUNS_V3_PERF"] == "1" else {
            throw XCTSkip("Set VOLIA_RUNS_V3_PERF=1 to measure")
        }
        for count in [1_000, 10_000] {
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let runs = syntheticHistory(count)
            try seed(runs)
            measure("\(count): launch read (listing, index decode, validation)") {
                let opened = store()
                XCTAssertEqual(opened.open(isProtectedDataAvailable: true), .active(.writable))
                XCTAssertEqual(opened.history.count, count)
            }
            let opened = store()
            _ = opened.open(isProtectedDataAvailable: true)
            try opened.repair()
            var next = 0
            measure("\(count): one add (file, barrier, index)") {
                next += 1
                var run = V3.run(900_000 + next, points: 400, samples: 60)
                run.id = UUID()
                XCTAssertTrue(opened.drainOne(run.id, .add(run, seq: opened.nextSeq)).isFullyDurable)
            }
            measure("\(count): one edit") {
                next += 1
                let name = "edit \(next)"
                XCTAssertTrue(opened.drainOne(runs[8].id, .edit { var run = $0; run.workoutName = name; return run }).isFullyDurable)
            }
            measure("\(count): a batch of 20 edits") {
                next += 1
                let name = "batch \(next)"
                let batch = (0..<20).map { (runs[$0 * 3].id, [RunsV3Operation.edit { var run = $0; run.workoutName = name; return run }]) }
                XCTAssertTrue(opened.drain(batch).isFullyDurable)
            }
            try measure("\(count): rebuild without the index (open and repair)", repeat: 3) {
                try? FileManager.default.removeItem(at: RunsV3Layout(storage: directory).index)
                let rebuilding = store()
                _ = rebuilding.open(isProtectedDataAvailable: true)
                try rebuilding.repair()
            }
        }
        if let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty {
            let runs = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).map(\.run)
            let encoder = RunsV3.makeEncoder()
            let largest = try XCTUnwrap(runs.max { (try! encoder.encode(StoredRun($0)).count) < (try! encoder.encode(StoredRun($1)).count) })
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try seed([largest])
            let opened = store()
            _ = opened.open(isProtectedDataAvailable: true)
            let size = opened.entries[largest.id]?.size ?? 0
            measure("on-demand load of the largest real workout (\(size) bytes)", repeat: 7) {
                guard case .loaded = opened.readRun(id: largest.id) else { return XCTFail("not loaded") }
            }
        }
    }
}
