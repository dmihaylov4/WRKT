import XCTest
@testable import WRKT

/// Every crash point (spec 11): a scenario is run once to count its file system calls, then
/// again with a kill, or a power loss, at every call index, followed by a fresh process that
/// opens and repairs. Per workout, the result must equal its state after the last acknowledged
/// batch, or after the batch in progress (INV-17); acknowledged batches are never lost (INV-6);
/// order follows `seq` (INV-7); a second open after repair changes nothing.
final class RunsV3CrashTests: XCTestCase {

    enum Op {
        case add(Run, seq: Int64)
        case rename(String)
        /// Removes the route (detail removed: the old revision goes to trash).
        case strip
        case delete

        var operation: RunsV3Operation {
            switch self {
            case .add(let run, let seq): return .add(run, seq: seq)
            case .rename(let name): return .edit { var run = $0; run.workoutName = name; return run }
            case .strip: return .edit { var run = $0; run.route = nil; run.routeWithHR = nil; return run }
            case .delete: return .delete
            }
        }
    }

    struct Scenario {
        var seed: [Run]
        var batches: [[(UUID, [Op])]]
        /// Drains leave the index stale; one `writeIndexIfStale` follows the last batch.
        var deferIndex = false
    }

    struct Model: Equatable {
        var runs: [UUID: (state: String, seq: Int64)] = [:]
        static func == (a: Model, b: Model) -> Bool {
            a.runs.mapValues(\.state) == b.runs.mapValues(\.state) && a.runs.mapValues(\.seq) == b.runs.mapValues(\.seq)
        }
    }

    static func describe(_ run: Run) -> String {
        "\(run.distanceKm)|\(run.workoutName ?? "-")|\(run.routeWithHR?.count ?? -1)"
    }

    /// The expected state after each batch: index 0 is the seed.
    static func models(_ scenario: Scenario) -> [Model] {
        var current = [UUID: (run: Run, seq: Int64)]()
        for (i, run) in scenario.seed.enumerated() { current[run.id] = (run, Int64(scenario.seed.count - i)) }
        func snapshot() -> Model { Model(runs: current.mapValues { (describe($0.run), $0.seq) }) }
        var result = [snapshot()]
        for batch in scenario.batches {
            for (id, ops) in batch {
                for op in ops {
                    switch op {
                    case .add(let run, let seq): current[id] = (run, seq)
                    case .rename(let name): if var item = current[id] { item.run.workoutName = name; current[id] = item }
                    case .strip: if var item = current[id] { item.run.route = nil; item.run.routeWithHR = nil; current[id] = item }
                    case .delete: current[id] = nil
                    }
                }
            }
            result.append(snapshot())
        }
        return result
    }

    /// Runs the scenario on `fs`; returns the call count after each batch returned.
    @discardableResult
    static func run(_ scenario: Scenario, on fs: ModelFileSystem, checkDurable: Bool = false) -> [Int] {
        let store = V3.store(fs)
        _ = store.open(isProtectedDataAvailable: true)
        _ = try? store.repair()
        var ends: [Int] = []
        for batch in scenario.batches {
            let result = store.drain(batch.map { ($0.0, $0.1.map(\.operation)) }, writeIndex: !scenario.deferIndex)
            if checkDurable { XCTAssertTrue(result.isFullyDurable, "reference run: \(result.failed)") }
            ends.append(fs.callCount)
        }
        if scenario.deferIndex { _ = try? store.writeIndexIfStale() }
        return ends
    }

    /// Opens a fresh process on `fs`, repairs, and returns what it shows.
    static func recover(_ fs: ModelFileSystem, file: StaticString = #filePath, line: UInt = #line) -> (Model, RunsV3Store)? {
        let store = V3.store(fs)
        guard store.open(isProtectedDataAvailable: true) == .active(.writable) else {
            XCTFail("did not open writable", file: file, line: line)
            return nil
        }
        _ = try? store.repair()
        var model = Model()
        var lastSeq = Int64.max
        for entry in store.history {
            XCTAssertLessThan(entry.seq, lastSeq, "order is seq descending", file: file, line: line)
            lastSeq = entry.seq
            guard case .loaded(let run) = store.readRun(id: entry.id) else {
                model.runs[entry.id] = ("unreadable", entry.seq)
                continue
            }
            XCTAssertEqual(RunSummary(run), entry.summary, "INV-15", file: file, line: line)
            model.runs[entry.id] = (describe(run), entry.seq)
        }
        return (model, store)
    }

    /// Per workout: the state after the last acknowledged batch, or after the one in progress.
    static func check(_ observed: Model, models: [Model], acknowledged: Int, label: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        let before = models[acknowledged]
        let after = acknowledged + 1 < models.count ? models[acknowledged + 1] : before
        let ids = Set(before.runs.keys).union(after.runs.keys).union(observed.runs.keys)
        for id in ids {
            let seen = observed.runs[id]
            let ok = [before.runs[id], after.runs[id]].contains { expected in
                expected?.state == seen?.state && expected?.seq == seen?.seq
            }
            if !ok {
                XCTFail("\(label): \(id.uuidString.suffix(4)) is \(seen.map { "\($0.state)@\($0.seq)" } ?? "absent"), "
                        + "expected \(before.runs[id].map { "\($0.state)@\($0.seq)" } ?? "absent") or "
                        + "\(after.runs[id].map { "\($0.state)@\($0.seq)" } ?? "absent")", file: file, line: line)
            }
        }
    }

    static func seeded(_ scenario: Scenario, caseInsensitive: Bool = false) -> ModelFileSystem {
        let fs = ModelFileSystem(caseInsensitive: caseInsensitive)
        V3.seed(fs, scenario.seed)
        return fs
    }

    /// The whole matrix for one scenario: kill and power loss (several strategies) at every
    /// call, and a kill during the recovery after a kill.
    static func exhaust(_ scenario: Scenario, name: String, seeds: [UInt64] = [1, 2, 3],
                        doubleFailures: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let models = models(scenario)
        let reference = seeded(scenario)
        let ends = run(scenario, on: reference, checkDurable: true)
        guard let final = recover(reference.afterKill())?.0 else { return 0 }
        XCTAssertEqual(final, models.last!, "\(name): reference run", file: file, line: line)
        let total = reference.callCount
        var cases = 0
        for cut in 0...total {
            let acknowledged = ends.filter { $0 <= cut }.count
            var strategies: [(String, (ModelFileSystem) -> ModelFileSystem)] = [
                ("kill", { $0.afterKill() }), ("power durableOnly", { $0.afterPowerLoss(.durableOnly) })]
            for seed in seeds { strategies.append(("power random \(seed)", { $0.afterPowerLoss(.random(seed &* 7919 &+ UInt64(cut))) })) }
            for (label, after) in strategies {
                let fs = seeded(scenario)
                fs.killAfterCalls = cut
                run(scenario, on: fs)
                let survivor = after(fs)
                guard let (observed, store) = recover(survivor, file: file, line: line) else { continue }
                check(observed, models: models, acknowledged: acknowledged, label: "\(name) \(label) at \(cut)", file: file, line: line)
                cases += 1
                // Repair is stable: another open finds a valid index and the same history.
                if let (again, _) = recover(survivor.afterKill(), file: file, line: line) {
                    XCTAssertEqual(again, observed, "\(name) \(label) at \(cut): second open", file: file, line: line)
                }
                _ = store
            }
            // Two failures in a row: killed again at every call of the recovery.
            if doubleFailures {
                let fs = seeded(scenario)
                fs.killAfterCalls = cut
                run(scenario, on: fs)
                let firstSurvivor = fs.afterPowerLoss(.durableOnly)
                let probe = firstSurvivor.copy()
                _ = recover(probe)
                for second in 0...probe.callCount {
                    let again = firstSurvivor.copy()
                    again.killAfterCalls = second
                    let recoveringStore = V3.store(again)
                    _ = recoveringStore.open(isProtectedDataAvailable: true)
                    _ = try? recoveringStore.repair()
                    guard let (observed, _) = recover(again.afterPowerLoss(.durableOnly), file: file, line: line) else { continue }
                    check(observed, models: models, acknowledged: acknowledged,
                          label: "\(name) double failure at \(cut)/\(second)", file: file, line: line)
                    cases += 1
                }
            }
        }
        return cases
    }

    private func rename(_ name: String) -> Op { .rename(name) }

    // MARK: - Scenarios

    func testEveryCrashPointOfAnAdd() {
        let scenario = Scenario(seed: [V3.run(1)], batches: [[(V3.id(2), [.add(V3.run(2, points: 3), seq: 2)])]])
        print("add: \(Self.exhaust(scenario, name: "add")) cases")
    }

    func testEveryCrashPointOfAnEdit() {
        let scenario = Scenario(seed: [V3.run(1, points: 3)], batches: [[(V3.id(1), [rename("edited")])]])
        print("edit: \(Self.exhaust(scenario, name: "edit")) cases")
    }

    func testEveryCrashPointOfAnEditThatRemovesDetail() {
        let scenario = Scenario(seed: [V3.run(1, points: 3)], batches: [[(V3.id(1), [.strip])]])
        print("strip: \(Self.exhaust(scenario, name: "strip")) cases")
    }

    func testEveryCrashPointOfADelete() {
        let scenario = Scenario(seed: [V3.run(1), V3.run(2)], batches: [[(V3.id(1), [.delete])]])
        print("delete: \(Self.exhaust(scenario, name: "delete")) cases")
    }

    func testEveryCrashPointOfASequenceOfBatches() {
        let scenario = Scenario(seed: [V3.run(1, points: 2), V3.run(2), V3.run(3)], batches: [
            [(V3.id(4), [.add(V3.run(4), seq: 4)])],
            [(V3.id(1), [rename("one")]), (V3.id(2), [.delete])],
            [(V3.id(4), [rename("four"), .strip]), (V3.id(3), [.delete])],
            [(V3.id(2), [.add(V3.run(2, distance: 22), seq: 5)])],   // the same id again after its delete
            [(V3.id(2), [.delete])],                                  // and deleted a second time
        ])
        print("sequence: \(Self.exhaust(scenario, name: "sequence", seeds: [1, 2])) cases")
    }

    /// The same sequence with the index written once at the end, as the app coalesces it.
    func testEveryCrashPointOfASequenceWithACoalescedIndex() {
        let scenario = Scenario(seed: [V3.run(1, points: 2), V3.run(2), V3.run(3)], batches: [
            [(V3.id(4), [.add(V3.run(4), seq: 4)])],
            [(V3.id(1), [rename("one")]), (V3.id(2), [.delete])],
            [(V3.id(4), [rename("four"), .strip]), (V3.id(3), [.delete])],
            [(V3.id(2), [.add(V3.run(2, distance: 22), seq: 5)])],
        ], deferIndex: true)
        print("coalesced: \(Self.exhaust(scenario, name: "coalesced", seeds: [1, 2])) cases")
    }

    /// Q-MIXED: one drain with several pending operations on several workouts.
    func testEveryCrashPointOfAMixedQueue() {
        let scenario = Scenario(seed: [V3.run(1), V3.run(2), V3.run(3)], batches: [[
            (V3.id(5), [.add(V3.run(5), seq: 4), rename("new")]),
            (V3.id(2), [rename("b")]),
            (V3.id(3), [.delete]),
            (V3.id(1), [rename("a"), .strip]),
        ]])
        print("mixed: \(Self.exhaust(scenario, name: "mixed")) cases")
    }

    /// The index is lost or damaged and rebuilt; crashes during the rebuild's write.
    func testEveryCrashPointOfARebuild() {
        let scenario = Scenario(seed: [V3.run(5), V3.run(1), V3.run(9)], batches: [])
        let models = Self.models(scenario)
        for cut in 0...40 {
            let fs = Self.seeded(scenario)
            fs.remove(V3.layout.index)
            fs.settle()
            fs.killAfterCalls = fs.callCount + cut
            let store = V3.store(fs)
            _ = store.open(isProtectedDataAvailable: true)
            _ = try? store.repair()
            for survivor in [fs.afterKill(), fs.afterPowerLoss(.durableOnly), fs.afterPowerLoss(.random(UInt64(cut)))] {
                guard let (observed, _) = Self.recover(survivor) else { continue }
                Self.check(observed, models: models, acknowledged: 0, label: "rebuild at \(cut)")
            }
        }
    }

    /// INV-16: the same matrix on a case-insensitive volume.
    func testCrashPointsOnACaseInsensitiveVolume() {
        let scenario = Scenario(seed: [V3.run(1)], batches: [[(V3.id(1), [rename("x")]), (V3.id(2), [.add(V3.run(2), seq: 2)])]])
        let models = Self.models(scenario)
        let reference = Self.seeded(scenario, caseInsensitive: true)
        let ends = Self.run(scenario, on: reference, checkDurable: true)
        for cut in 0...reference.callCount {
            let fs = Self.seeded(scenario, caseInsensitive: true)
            fs.killAfterCalls = cut
            Self.run(scenario, on: fs)
            guard let (observed, _) = Self.recover(fs.afterPowerLoss(.durableOnly)) else { continue }
            Self.check(observed, models: models, acknowledged: ends.filter { $0 <= cut }.count, label: "insensitive at \(cut)")
        }
    }

    /// A purge interrupted at every point never loses a live workout or the evidence of a delete.
    func testEveryCrashPointOfAPurge() throws {
        let sources = V3.Sources()
        let base = ModelFileSystem()
        V3.seed(base, [V3.run(1), V3.run(2), V3.run(3)])
        let store = try V3.open(V3.store(base, sources))
        XCTAssertTrue(store.drainOne(V3.id(1), .delete).isFullyDurable)
        XCTAssertTrue(store.drainOne(V3.id(2), .strip()).isFullyDurable)
        base.settle()
        for cut in 0...30 {
            let fs = base.copy()
            let later = V3.Sources(now: sources.now.addingTimeInterval(31 * 24 * 3_600))
            let purging = V3.store(fs, later)
            _ = purging.open(isProtectedDataAvailable: true)
            fs.killAfterCalls = fs.callCount + cut
            _ = try? purging.purgeTrash()
            for survivor in [fs.afterKill(), fs.afterPowerLoss(.random(UInt64(cut)))] {
                guard let (observed, _) = Self.recover(survivor) else { continue }
                XCTAssertEqual(observed.runs.keys.sorted { $0.uuidString < $1.uuidString }, [V3.id(2), V3.id(3)], "purge at \(cut)")
            }
        }
    }

    // MARK: - Random sequences (INV-2 to INV-9, INV-13 to INV-15, INV-17)

    func testRandomSequencesWithRandomKillsAndPowerLosses() {
        var cases = 0
        for seed in UInt64(1)...40 {
            var generator = SplitMix(seed: seed)
            let seedRuns = (1...4).map { V3.run($0, points: generator.next(3)) }
            var live = Set(seedRuns.map(\.id))
            var nextSeq = Int64(seedRuns.count + 1)
            var batches: [[(UUID, [Op])]] = []
            for _ in 0..<6 {
                var batch: [(UUID, [Op])] = []
                for _ in 0...generator.next(3) {
                    let pick = generator.next(10)
                    if pick < 3 || live.isEmpty {
                        let n = 10 + generator.next(6)
                        let id = V3.id(n)
                        guard !batch.contains(where: { $0.0 == id }) else { continue }
                        batch.append((id, [.add(V3.run(n, distance: Double(generator.next(100)), points: generator.next(4)), seq: nextSeq)]))
                        nextSeq += 1
                        live.insert(id)
                    } else {
                        let id = live.sorted { $0.uuidString < $1.uuidString }[generator.next(live.count)]
                        guard !batch.contains(where: { $0.0 == id }) else { continue }
                        switch pick {
                        case 3...5: batch.append((id, [.rename("r\(generator.next(5))")]))
                        case 6: batch.append((id, [.rename("same"), .rename("same")]))
                        case 7: batch.append((id, [.strip]))
                        default: batch.append((id, [.delete])); live.remove(id)
                        }
                    }
                }
                batches.append(batch)
            }
            let scenario = Scenario(seed: seedRuns, batches: batches)
            let models = Self.models(scenario)
            let reference = Self.seeded(scenario)
            let ends = Self.run(scenario, on: reference, checkDurable: true)
            Self.checkImmutability(scenario)
            for _ in 0..<12 {
                let cut = generator.next(reference.callCount + 1)
                let fs = Self.seeded(scenario)
                fs.killAfterCalls = cut
                Self.run(scenario, on: fs)
                let survivor = generator.next(2) == 0 ? fs.afterKill() : fs.afterPowerLoss(.random(generator.next()))
                guard let (observed, _) = Self.recover(survivor) else { continue }
                Self.check(observed, models: models, acknowledged: ends.filter { $0 <= cut }.count, label: "random \(seed) at \(cut)")
                XCTAssertFalse(survivor.readPaths.contains { $0.contains("/runs_v3/tmp/") }, "INV-10")
                cases += 1
            }
        }
        print("random: \(cases) cases")
    }

    /// INV-2: a workout file never changes once it has its name. INV-14: repair never unlinks one.
    static func checkImmutability(_ scenario: Scenario) {
        let fs = seeded(scenario)
        var seen: [String: Data] = [:]
        func record() {
            let present = Set(fs.names(in: V3.layout.runs))
            seen = seen.filter { present.contains($0.key) }   // a name that left runs/ may come back
            for name in present {
                let data = fs.contents(of: V3.layout.runs.appendingPathComponent(name))!
                if let previous = seen[name] { XCTAssertEqual(previous, data, "INV-2: \(name) changed") }
                seen[name] = data
            }
        }
        record()
        let store = V3.store(fs)
        _ = store.open(isProtectedDataAvailable: true)
        fs.clearLog()
        _ = try? store.repair()
        XCTAssertFalse(fs.log.contains { $0.hasPrefix("unlink") && $0.hasSuffix(".json") && !$0.contains(".wrkt-") }, "INV-14")
        record()
        for batch in scenario.batches {
            _ = store.drain(batch.map { ($0.0, $0.1.map(\.operation)) })
            record()
        }
    }
}

private extension RunsV3Operation {
    static func strip() -> RunsV3Operation { RunsV3CrashTests.Op.strip.operation }
}
