import XCTest
@testable import WRKT

/// The merge with an older build's runs_v2.json (spec 8): every rule as a planner case (MRG),
/// then the merge applied to a runs_v3 directory on the file system model and cut at every call
/// by a kill or a power loss, including between the drain and the baseline write, and a second
/// cut while it runs again: the result always equals one uninterrupted merge (INV-11).
final class RunsV3MergeTests: XCTestCase {
    private typealias Entry = RunsV3BaselineV1.Entry

    private static func entries(_ runs: [Run]) -> [Entry] {
        runs.enumerated().map { Entry(id: $0.element.id, hash: StoredRun.normalHash($0.element), seq: Int64(runs.count - $0.offset)) }
    }

    private static func live(_ runs: [Run], unavailable: Set<UUID> = []) -> [UUID: RunsV3Merge.Live] {
        Dictionary(uniqueKeysWithValues: runs.enumerated().map {
            ($0.element.id, RunsV3Merge.Live(seq: Int64(runs.count - $0.offset), unavailable: unavailable.contains($0.element.id),
                                             healthKitUUID: $0.element.healthKitUUID))
        })
    }

    private static func plan(baseline: [Run], v2: [Run], v3: [Run], unavailable: Set<UUID> = [], trashed: Set<UUID> = []) -> RunsV3Merge.Plan {
        let byID = Dictionary(uniqueKeysWithValues: v3.map { ($0.id, $0) })
        return RunsV3Merge.plan(baseline: entries(baseline), v2: v2, live: live(v3, unavailable: unavailable), trashed: trashed) { id in
            unavailable.contains(id) ? nil : byID[id]
        }
    }

    private static var base: [Run] { (1...10).map { V3.run($0, points: $0 % 3 == 0 ? 4 : 0) } }

    private func renamed(_ run: Run, _ name: String) -> Run { var copy = run; copy.workoutName = name; return copy }

    // MARK: - Rules (MRG)

    func testNothingChangedPlansNothing() {
        let plan = Self.plan(baseline: Self.base, v2: Self.base, v3: Self.base)
        XCTAssertFalse(plan.counts.changesHistory)
        XCTAssertEqual(plan.counts, RunsV3Merge.Counts())
    }

    /// MRG-MARKER: 5.4.3 rewrites without the routeFromRouteWithHR marker, so every repeated
    /// route reads back as absent. Not an edit.
    func testARewriteWithoutTheMarkerIsNotAnEdit() {
        let stripped = Self.base.map { run -> Run in
            var copy = run
            if StoredRun.routeRepeatsRouteWithHR(copy) { copy.route = nil }
            return copy
        }
        XCTAssertTrue(stripped.contains { $0.route == nil && $0.routeWithHR != nil })
        let plan = Self.plan(baseline: Self.base, v2: stripped, v3: Self.base)
        XCTAssertFalse(plan.counts.changesHistory)
        // An edit on such a workout keeps v3's rebuilt route.
        var edited = stripped
        edited[2] = renamed(edited[2], "edited by 5.4.3")
        let editPlan = Self.plan(baseline: Self.base, v2: edited, v3: Self.base)
        XCTAssertEqual(editPlan.replaces.count, 1)
        XCTAssertEqual(editPlan.replaces.first?.route, Self.base[2].route, "the route is not lost")
        XCTAssertEqual(editPlan.replaces.first?.workoutName, "edited by 5.4.3")
    }

    /// MRG-ADD and order: the older build's additions go first, in its order.
    func testAdditionsComeFirstInTheOlderBuildsOrder() {
        let v2 = [V3.run(30), V3.run(31)] + Self.base
        let plan = Self.plan(baseline: Self.base, v2: v2, v3: Self.base)
        XCTAssertEqual(plan.adds.map(\.id), [V3.id(30), V3.id(31)])
        XCTAssertEqual(plan.counts.added, 2)
    }

    /// MRG-HKDUP: the older build imported a v3 workout again under a new id.
    func testAReimportUnderANewIdIsDeduplicated() {
        var again = V3.run(40)
        again.id = V3.id(41)
        let v3 = [V3.run(40)] + Self.base
        let plan = Self.plan(baseline: Self.base, v2: [again] + Self.base, v3: v3)
        XCTAssertTrue(plan.adds.isEmpty)
        XCTAssertEqual(plan.counts.deduplicated, 1)
    }

    /// The same Health workout, unreadable in v3: restored from the older build's copy under v3's id.
    func testAHealthDuplicateOfAnUnreadableWorkoutRepairsIt() {
        var again = V3.run(40)
        again.id = V3.id(41)
        again.workoutName = "readable copy"
        let v3 = [V3.run(40)] + Self.base
        let plan = Self.plan(baseline: Self.base, v2: [again] + Self.base, v3: v3, unavailable: [V3.id(40)])
        XCTAssertEqual(plan.replaces.map(\.id), [V3.id(40)])
        XCTAssertEqual(plan.replaces.first?.workoutName, "readable copy")
        XCTAssertEqual(plan.counts.repaired, 1)
    }

    /// MRG-EDIT-V2 and MRG-EDIT-BOTH.
    func testAnEditTakesTheOnlySideThatChanged() {
        var v2 = Self.base
        v2[0] = renamed(v2[0], "old build")
        v2[1] = renamed(v2[1], "old build")
        var v3 = Self.base
        v3[1] = renamed(v3[1], "v3")
        let plan = Self.plan(baseline: Self.base, v2: v2, v3: v3)
        XCTAssertEqual(plan.replaces.map(\.id), [V3.id(1)])
        XCTAssertEqual(plan.counts.replaced, 1)
        XCTAssertEqual(plan.counts.conflicts, 1, "both changed: v3 kept")
    }

    /// MRG-DEL-V2 and the valve.
    func testDeletionsGoToTrashUnlessTheyExceedTheValve() {
        let fewer = Array(Self.base.dropFirst(2))
        let plan = Self.plan(baseline: Self.base, v2: fewer, v3: Self.base)
        XCTAssertEqual(Set(plan.deletes), [V3.id(1), V3.id(2)])
        XCTAssertEqual(plan.counts.trashed, 2)

        let history = (1...40).map { V3.run($0) }
        XCTAssertEqual(RunsV3Merge.valveLimit(baselineCount: 40), 8)
        let eightGone = Self.plan(baseline: history, v2: Array(history.dropFirst(8)), v3: history)
        XCTAssertEqual(eightGone.deletes.count, 8)
        let nineGone = Self.plan(baseline: history, v2: Array(history.dropFirst(9)), v3: history)
        XCTAssertTrue(nineGone.deletes.isEmpty, "over the valve: none applied")
        XCTAssertEqual(nineGone.counts.skippedByValve, 9)
        XCTAssertEqual(RunsV3Merge.valveLimit(baselineCount: 10), 5)
        // A deletion of a workout v3 changed meanwhile is not applied.
        var v3 = Self.base
        v3[0] = renamed(v3[0], "v3")
        XCTAssertEqual(Self.plan(baseline: Self.base, v2: fewer, v3: v3).deletes, [V3.id(2)])
    }

    /// MRG-NO-RESURRECT: a workout v3 deleted stays deleted, edited by the older build or not.
    func testAV3DeletionIsNeverUndone() {
        let v3 = Array(Self.base.dropFirst())
        XCTAssertFalse(Self.plan(baseline: Self.base, v2: Self.base, v3: v3).counts.changesHistory)
        var v2 = Self.base
        v2[0] = renamed(v2[0], "old build")
        let plan = Self.plan(baseline: Self.base, v2: v2, v3: v3)
        XCTAssertFalse(plan.counts.changesHistory)
        XCTAssertEqual(plan.counts.keptDeleted, 1)
    }

    /// An older build re-adding, under the same id, a workout v3 deleted (from an export, say).
    func testAReAddUnderAV3DeletedIdStaysDeleted() {
        let plan = Self.plan(baseline: Self.base, v2: [V3.run(50)] + Self.base, v3: Self.base, trashed: [V3.id(50)])
        XCTAssertTrue(plan.adds.isEmpty)
        XCTAssertEqual(plan.counts.keptDeleted, 1)
    }

    func testAnUnreadableV3WorkoutIsRestoredFromTheOlderBuildsCopy() {
        let plan = Self.plan(baseline: Self.base, v2: Self.base, v3: Self.base, unavailable: [V3.id(3)])
        XCTAssertEqual(plan.replaces.map(\.id), [V3.id(3)])
        XCTAssertEqual(plan.counts.repaired, 1)
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    /// MRG-APPEARED: runs_v2.json with no baseline behind it: additions only, never deletions.
    func testAV2FileWithoutABaselineOnlyAdds() {
        let plan = RunsV3Merge.plan(baseline: [], v2: [V3.run(60)], live: Self.live(Self.base), trashed: []) { _ in nil }
        XCTAssertEqual(plan.adds.map(\.id), [V3.id(60)])
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testTheStampComparesAtWholeSeconds() {
        let state = RunsV3BaselineV1.V2State(present: true, size: 10, modified: Date(timeIntervalSince1970: 1_790_000_000),
                                             fileNumber: 5, sha256: "x", decodable: true)
        XCTAssertTrue(RunsV3Merge.stampMatches(state, size: 10, fileNumber: 5, modified: Date(timeIntervalSince1970: 1_790_000_000.731)))
        XCTAssertFalse(RunsV3Merge.stampMatches(state, size: 10, fileNumber: 6, modified: Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertFalse(RunsV3Merge.stampMatches(state, size: 11, fileNumber: 5, modified: Date(timeIntervalSince1970: 1_790_000_000)))
    }

    // MARK: - Applied on the file system model (INV-11)

    private static let olderV2: [Run] = {
        var v2 = base
        v2.remove(at: 4)                                   // deleted by the older build
        v2[0].workoutName = "edited by the older build"     // edited
        v2.insert(V3.run(70, points: 3), at: 0)            // imported
        var again = V3.run(80)                             // a v3 workout imported again under a new id
        again.id = V3.id(81)
        v2.insert(again, at: 1)
        return v2.map { run in var copy = run; if StoredRun.routeRepeatsRouteWithHR(copy) { copy.route = nil }; return copy }
    }()

    private static let v2State = RunsV3BaselineV1.V2State(present: true, size: 2, modified: V3.start, fileNumber: 9,
                                                          sha256: "changed", decodable: true)

    /// v3 after migration of `base`, plus one v3-only workout (80).
    private func seeded() -> ModelFileSystem {
        let fs = ModelFileSystem()
        V3.seed(fs, [V3.run(80)] + Self.base)
        let baseline = RunsV3BaselineV1(formatVersion: 1, reconciledAt: V3.start,
                                        v2: .init(present: true, size: 1, modified: V3.start, fileNumber: 1, sha256: "migrated", decodable: true),
                                        entries: Self.entries(Self.base))
        fs.put(try! RunsV3.makeEncoder().encode(baseline), at: V3.layout.baseline)
        fs.settle()
        return fs
    }

    /// One merge as the store runs it, on the module: plan, apply in one drain, then the
    /// baseline. Skipped when the baseline already records this runs_v2.json.
    private func merge(on fs: ModelFileSystem) {
        let store = V3.store(fs)
        guard store.open(isProtectedDataAvailable: true) == .active(.writable) else { return }
        _ = try? store.repair()
        guard let baseline = store.readBaseline(), baseline.v2.sha256 != Self.v2State.sha256 else { return }
        let live = store.entries.mapValues { RunsV3Merge.Live(seq: $0.seq, unavailable: $0.unavailable, healthKitUUID: $0.summary.healthKitUUID) }
        let plan = RunsV3Merge.plan(baseline: baseline.entries, v2: Self.olderV2, live: live, trashed: store.deletedIDs()) { id in
            if case .loaded(let run) = store.readRun(id: id) { return run }
            return nil
        }
        var batch: [(id: UUID, operations: [RunsV3Operation])] = []
        for run in plan.replaces { batch.append((run.id, [.replace(run)])) }
        for id in plan.deletes { batch.append((id, [.delete])) }
        var seq = store.nextSeq
        for run in plan.adds.reversed() { batch.append((run.id, [.add(run, seq: seq)])); seq += 1 }
        guard store.drain(batch).isFullyDurable else { return }
        try? store.writeBaseline(RunsV3Merge.baseline(after: Self.olderV2, state: Self.v2State, previous: baseline.entries,
                                                      seqs: store.entries.mapValues(\.seq), now: V3.start))
    }

    private func history(_ fs: ModelFileSystem) -> [String] { V3.state(open(fs.afterKill())) }

    private func open(_ fs: ModelFileSystem) -> RunsV3Store {
        let store = V3.store(fs)
        _ = store.open(isProtectedDataAvailable: true)
        _ = try? store.repair()
        return store
    }

    func testTheMergeResultAndIndependenceFromInterruption() throws {
        let reference = seeded()
        let start = reference.callCount
        merge(on: reference)
        let total = reference.callCount - start
        let expectedStore = open(reference.afterKill())
        let expected = V3.state(expectedStore)
        // The expected history, by rule.
        var ids = expectedStore.history.map(\.id)
        XCTAssertEqual(ids.first, V3.id(70), "the import first")
        XCTAssertFalse(ids.contains(V3.id(81)), "no duplicate of 80")
        XCTAssertFalse(ids.contains(V3.id(5)), "the older build's deletion applied")
        XCTAssertTrue(ids.contains(V3.id(80)), "the v3-only workout kept")
        XCTAssertEqual(expectedStore.entries[V3.id(1)]?.summary.workoutName, "edited by the older build")
        if case .loaded(let three) = expectedStore.readRun(id: V3.id(3)) { XCTAssertEqual(three.route, Self.base[2].route) }
        XCTAssertEqual(expectedStore.readBaseline()?.v2.sha256, Self.v2State.sha256)
        ids.removeAll()

        var cases = 0
        for cut in 0...total {
            for (name, after) in [("kill", { (fs: ModelFileSystem) in fs.afterKill() }),
                                  ("power durableOnly", { $0.afterPowerLoss(.durableOnly) }),
                                  ("power random", { $0.afterPowerLoss(.random(UInt64(cut) &* 131 &+ 5)) })] as [(String, (ModelFileSystem) -> ModelFileSystem)] {
                let fs = seeded()
                fs.killAfterCalls = fs.callCount + cut
                merge(on: fs)
                let survivor = after(fs)
                // A second cut while the merge runs again, then a clean run.
                for second in [0, 5, 17] {
                    let again = survivor.copy()
                    again.killAfterCalls = again.callCount + second
                    merge(on: again)
                    let third = again.afterPowerLoss(.durableOnly)
                    merge(on: third)
                    XCTAssertEqual(history(third), expected, "\(name) at \(cut), second cut at \(second)")
                    cases += 1
                }
                merge(on: survivor)
                XCTAssertEqual(history(survivor), expected, "\(name) at \(cut)")
                // A merge after a completed one changes nothing.
                merge(on: survivor)
                XCTAssertEqual(history(survivor), expected, "\(name) at \(cut): again")
                cases += 1
            }
        }
        print("merge crash matrix: \(total) calls, \(cases) cases")
    }
}
