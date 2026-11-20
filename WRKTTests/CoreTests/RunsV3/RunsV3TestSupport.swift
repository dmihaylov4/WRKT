import Foundation
import XCTest
@testable import WRKT

/// Deterministic fixtures for the runs_v3 tests. Nothing here derives from real user data.
nonisolated enum V3 {
    static let storage = URL(fileURLWithPath: "/model/Documents/WRKT_Storage", isDirectory: true)
    static var layout: RunsV3Layout { RunsV3Layout(storage: storage) }
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    /// A run with whole-second dates (the file's precision), so decode(encode(run)) == run.
    static func run(_ n: Int, distance: Double? = nil, points: Int = 0, samples: Int? = nil, splits: Int? = nil,
                    repeatRoute: Bool = true, name: String? = nil) -> Run {
        let date = start.addingTimeInterval(Double(-n * 3_600))
        let route = (0..<points).map { i in
            RoutePoint(lat: 48.2 + Double(i) * 0.001, lon: 16.3 + Double(n) * 0.01 + Double(i) * 0.0007,
                       t: date.addingTimeInterval(Double(i) * 5), hr: 130 + Double(i % 40))
        }
        return Run(id: id(n), date: date, distanceKm: distance ?? Double(n) + 0.5, durationSec: 600 + n,
                   healthKitUUID: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", n)),
                   avgHeartRate: 140, maxHeartRate: 170, minHeartRate: 90,
                   hrSamples: samples.map { count in (0..<count).map { HeartRateSample(timestamp: date.addingTimeInterval(Double($0)), bpm: 120 + Double($0 % 30)) } },
                   calories: 300, route: points > 0 && repeatRoute ? route.map { Coordinate(lat: $0.lat, lon: $0.lon) } : nil,
                   routeWithHR: points > 0 ? route : nil,
                   splits: splits.map { count in (0..<count).map { KilometerSplit(number: $0 + 1, distanceKm: 1, durationSec: 300) } },
                   workoutType: "Running", workoutName: name)
    }

    /// Counters instead of randomness and wall-clock time.
    final class Sources: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds: TimeInterval
        private var randomValue: UInt16 = 0
        private var tokenValue = 0
        init(now: Date = V3.start) { seconds = now.timeIntervalSince1970 }
        var now: Date { lock.withLock { Date(timeIntervalSince1970: seconds) } }
        func advance(_ interval: TimeInterval) { lock.withLock { seconds += interval } }
        func random() -> UInt16 { lock.withLock { randomValue &+= 1; return randomValue } }
        func token() -> UUID {
            lock.withLock {
                tokenValue += 1
                return UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", tokenValue))!
            }
        }
    }

    static func environment(_ fileSystem: DurableFileSystem, _ sources: Sources = Sources()) -> RunsV3Store.Environment {
        RunsV3Store.Environment(fileSystem: fileSystem, now: { sources.now }, random: { sources.random() },
                                token: { sources.token() }, build: "test (1)")
    }

    static func store(_ fileSystem: DurableFileSystem, _ sources: Sources = Sources()) -> RunsV3Store {
        RunsV3Store(storage: storage, environment: environment(fileSystem, sources))
    }

    /// What a finished migration would leave (a test-only writer; the app has no migration yet):
    /// the directories, format.json, one file per run at revision 1 with `seq = n - i`, and the
    /// index. Everything is made durable.
    static func seed(_ fs: ModelFileSystem, _ runs: [Run], index: Bool = true, format: Bool = true,
                     formatValue: RunsV3FormatV1? = nil) {
        let layout = V3.layout
        fs.makeDirectories(layout.runs)
        fs.makeDirectories(layout.trash)
        fs.makeDirectories(layout.tmp)
        let encoder = RunsV3.makeEncoder()
        var entries: [RunsV3IndexV1.Entry] = []
        for (i, run) in runs.enumerated() {
            let file = RunFileV1(format: 1, id: run.id, rev: 1, seq: Int64(runs.count - i), run: StoredRun(run))
            let data = try! encoder.encode(file)
            fs.put(data, at: layout.runFile(RunsV3FileName(id: run.id, rev: 1)))
            entries.append(.init(id: run.id, rev: 1, seq: Int64(runs.count - i), size: data.count,
                                 sha256: RunsV3Store.sha256(data), summary: RunSummary(run)))
        }
        if format {
            let value = formatValue ?? RunsV3FormatV1(formatVersion: 1, minimumReaderVersion: 1, minimumWriterVersion: 1,
                                                      createdAt: start, createdByBuild: "seed", migratedFrom: nil)
            fs.put(try! encoder.encode(value), at: layout.format)
        }
        if index {
            let value = RunsV3IndexV1(formatVersion: 1, minimumReaderVersion: 1, generation: 1, entries: entries)
            fs.put(try! encoder.encode(value), at: layout.index)
        }
        fs.settle()
    }

    /// Opens (asserting the expected mode) and repairs when writable.
    @discardableResult
    static func open(_ store: RunsV3Store, expect mode: RunsV3Mode = .writable, repair: Bool = true,
                     file: StaticString = #filePath, line: UInt = #line) throws -> RunsV3Store {
        let result = store.open(isProtectedDataAvailable: true)
        XCTAssertEqual(result, .active(mode), file: file, line: line)
        if repair, mode == .writable { try store.repair() }
        return store
    }

    /// The history as the store sees it: ids in order, and each live run read back in full.
    static func history(_ store: RunsV3Store) -> [(id: UUID, run: Run?)] {
        store.history.map { entry in
            if case .loaded(let run) = store.readRun(id: entry.id) { return (entry.id, run) }
            return (entry.id, nil)
        }
    }

    /// The same as `history`, as comparable pairs.
    static func state(_ store: RunsV3Store) -> [String] {
        history(store).map { "\($0.id.uuidString.suffix(4)):\($0.run.map { "\($0.distanceKm)|\($0.workoutName ?? "-")|\($0.routeWithHR?.count ?? -1)" } ?? "unreadable")" }
    }

    static func state(of runs: [Run]) -> [String] {
        runs.map { "\($0.id.uuidString.suffix(4)):\($0.distanceKm)|\($0.workoutName ?? "-")|\($0.routeWithHR?.count ?? -1)" }
    }
}

extension RunsV3Store {
    /// One operation, drained alone.
    @discardableResult
    func drainOne(_ id: UUID, _ operations: RunsV3Operation...) -> RunsV3DrainResult {
        drain([(id, operations)])
    }
}
