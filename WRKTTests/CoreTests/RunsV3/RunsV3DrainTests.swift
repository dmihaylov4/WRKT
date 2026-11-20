import XCTest
@testable import WRKT

/// Writing (spec 3): add, edit as a new revision, delete to trash, the barrier, the index,
/// retirement, purge and wipe.
final class RunsV3DrainTests: XCTestCase {
    private let layout = V3.layout

    private func seeded(_ runs: [Run], _ sources: V3.Sources = V3.Sources()) throws -> (ModelFileSystem, RunsV3Store) {
        let fs = ModelFileSystem()
        V3.seed(fs, runs)
        let store = try V3.open(V3.store(fs, sources))
        return (fs, store)
    }

    private func reopened(_ fs: ModelFileSystem) throws -> RunsV3Store { try V3.open(V3.store(fs), repair: false) }

    private func rename(_ name: String) -> (Run) -> Run { { var run = $0; run.workoutName = name; return run } }

    func testAddWritesOneFileThroughTmpThenTheBarrierThenTheIndex() throws {
        let (fs, store) = try seeded([V3.run(1)])
        fs.clearLog()
        let result = store.drainOne(V3.id(2), .add(V3.run(2), seq: store.nextSeq))
        XCTAssertTrue(result.isFullyDurable)
        XCTAssertEqual(result.durable, [V3.id(2)])
        XCTAssertTrue(result.indexWritten)
        // The first new id of a process lists trash once, for revisions an older index may name.
        let log = fs.log.drop { $0.hasPrefix("list") }
        let calls = log.map { $0.split(separator: " ").first.map(String.init) ?? "" }
        let expected = ["createExclusive", "setProtection", "write", "fsync", "close", "renameExclusive"]
        XCTAssertEqual(Array(calls.prefix(6)), expected)
        let barrier = try XCTUnwrap(calls.firstIndex(of: "F_FULLFSYNC"))
        XCTAssertEqual(Array(calls[6..<barrier]), ["fsyncDirectory", "fsyncDirectory"], "runs/ and tmp/")
        XCTAssertGreaterThan(try XCTUnwrap(calls.lastIndex(of: "rename")), barrier, "the index comes after the barrier")
        XCTAssertTrue(log.first?.hasSuffix(".tmp") == true, "the temporary file is in tmp/")
        XCTAssertEqual(try reopened(fs).history.map(\.id), [V3.id(2), V3.id(1)])
    }

    func testEditWritesANewRevisionAndRetiresTheOldOne() throws {
        let (fs, store) = try seeded([V3.run(1, points: 4)])
        XCTAssertTrue(store.drainOne(V3.id(1), .edit(rename("Morning"))).isFullyDurable)
        XCTAssertEqual(fs.names(in: layout.runs), [RunsV3FileName(id: V3.id(1), rev: 2).string])
        XCTAssertEqual(fs.names(in: layout.trash), [], "an edit that removed no detail unlinks the old revision")
        let back = try reopened(fs)
        XCTAssertEqual(back.history.first?.summary.workoutName, "Morning")
        XCTAssertEqual(back.report.indexState, .valid)
    }

    func testAnEditThatRemovesDetailKeepsThePreviousRevisionInTrash() throws {
        let (fs, store) = try seeded([V3.run(1, points: 4, samples: 3)])
        let strip: (Run) -> Run = { var run = $0; run.routeWithHR = nil; run.route = nil; return run }
        XCTAssertTrue(store.drainOne(V3.id(1), .edit(strip)).isFullyDurable)
        let trashed = fs.names(in: layout.trash).compactMap(RunsV3TrashName.parse)
        XCTAssertEqual(trashed.map(\.reason), [.superseded])
        XCTAssertEqual(trashed.first?.rev, 1)
    }

    /// INV-8: an edit that changes nothing creates, moves and writes nothing.
    func testANoOpEditWritesNothing() throws {
        let (fs, store) = try seeded([V3.run(1, points: 3)])
        _ = store.drainOne(V3.id(1), .edit(rename("x")))
        fs.clearLog()
        let result = store.drainOne(V3.id(1), .edit(rename("x")), .edit { $0 })
        XCTAssertTrue(result.isFullyDurable)
        XCTAssertFalse(result.indexWritten)
        XCTAssertFalse(fs.log.contains { $0.hasPrefix("createExclusive") || $0.hasPrefix("rename") || $0.hasPrefix("F_FULLFSYNC") },
                       "\(fs.log)")
    }

    /// INV-9: every revision moves to trash, the live one last.
    func testDeleteMovesEveryRevisionLowestFirst() throws {
        let fs = ModelFileSystem()
        V3.seed(fs, [V3.run(1)])
        let encoder = RunsV3.makeEncoder()
        fs.put(try encoder.encode(RunFileV1(format: 1, id: V3.id(1), rev: 3, seq: 1, run: StoredRun(V3.run(1, distance: 9)))),
               at: layout.runFile(RunsV3FileName(id: V3.id(1), rev: 3)))
        let store = try V3.open(V3.store(fs), repair: false)
        fs.clearLog()
        XCTAssertTrue(store.drainOne(V3.id(1), .delete).isFullyDurable)
        let moves = fs.log.filter { $0.hasPrefix("renameExclusive") }.compactMap { RunsV3TrashName.parse(String($0.dropFirst("renameExclusive ".count))) }
        XCTAssertEqual(moves.map(\.rev), [1, 3])
        XCTAssertEqual(fs.names(in: layout.runs), [])
        XCTAssertEqual(try reopened(fs).history.count, 0)
    }

    func testDeletingTheSameIdTwiceAfterAReAddSucceeds() throws {
        let (fs, store) = try seeded([V3.run(1)])
        XCTAssertTrue(store.drainOne(V3.id(1), .delete).isFullyDurable)
        XCTAssertTrue(store.drainOne(V3.id(1), .add(V3.run(1), seq: 5)).isFullyDurable)
        XCTAssertTrue(store.drainOne(V3.id(1), .delete).isFullyDurable)
        XCTAssertEqual(fs.names(in: layout.trash).count, 2)
        XCTAssertEqual(try reopened(fs).history.count, 0)
    }

    func testATrashNameCollisionIsRetried() throws {
        let sources = V3.Sources()
        let (fs, store) = try seeded([V3.run(1)], sources)
        // The next trash name the store will pick already exists.
        let ms = Int64(sources.now.timeIntervalSince1970 * 1000)
        fs.put(Data(), at: layout.trash.appendingPathComponent(
            RunsV3TrashName(id: V3.id(1), rev: 1, reason: .deleted, milliseconds: ms, random: "0001").string))
        XCTAssertTrue(store.drainOne(V3.id(1), .delete).isFullyDurable)
        XCTAssertEqual(fs.names(in: layout.runs), [])
    }

    func testEditsOfAGoneWorkoutAreDroppedAndADeleteIsNeverUndone() throws {
        let (fs, store) = try seeded([V3.run(1)])
        XCTAssertTrue(store.drain([(V3.id(1), [.delete, .edit(rename("late")), .replace(V3.run(1))])]).isFullyDurable)
        XCTAssertTrue(store.drainOne(V3.id(9), .edit(rename("never")), .replace(V3.run(9))).isFullyDurable)
        XCTAssertEqual(try reopened(fs).history.count, 0)
    }

    func testEditThenDeleteInOneDrainDeletes() throws {
        let (fs, store) = try seeded([V3.run(1)])
        XCTAssertTrue(store.drain([(V3.id(1), [.edit(rename("a")), .delete])]).isFullyDurable)
        XCTAssertEqual(fs.names(in: layout.runs), [])
    }

    func testAddThenEditInOneDrainWritesOneRevision() throws {
        let (fs, store) = try seeded([])
        XCTAssertTrue(store.drain([(V3.id(4), [.add(V3.run(4), seq: 1), .edit(rename("b"))])]).isFullyDurable)
        XCTAssertEqual(fs.names(in: layout.runs), [RunsV3FileName(id: V3.id(4), rev: 1).string])
        XCTAssertEqual(try reopened(fs).history.first?.summary.workoutName, "b")
    }

    /// INV-7: new workouts go first; edits keep the position.
    func testOrderIsSeqDescendingAndEditsKeepPositions() throws {
        let (fs, store) = try seeded([V3.run(5), V3.run(1), V3.run(9)])
        _ = store.drainOne(V3.id(2), .add(V3.run(2), seq: store.nextSeq))
        _ = store.drainOne(V3.id(1), .edit(rename("kept place")))
        let order = try reopened(fs).history.map(\.id)
        XCTAssertEqual(order, [V3.id(2), V3.id(5), V3.id(1), V3.id(9)])
        XCTAssertEqual(Set(try reopened(fs).history.map(\.seq)).count, 4)
    }

    func testATransientWriteFailureLeavesTheOldStateAndCanBeRetried() throws {
        for code in [ENOSPC, EIO, EPERM] {
            let (fs, store) = try seeded([V3.run(1)])
            fs.failNext = ("write", nil, code)   // the data write of the new revision
            let result = store.drainOne(V3.id(1), .edit(rename("retry")))
            XCTAssertNotNil(result.failed[V3.id(1)], "\(code)")
            XCTAssertFalse(result.isFullyDurable)
            XCTAssertEqual(try reopened(fs.copy()).history.first?.summary.workoutName, nil)
            XCTAssertTrue(store.drainOne(V3.id(1), .edit(rename("retry"))).isFullyDurable)
            XCTAssertEqual(try reopened(fs).history.first?.summary.workoutName, "retry")
            XCTAssertEqual(fs.names(in: layout.tmp), [], "a failed write removes its temporary file")
        }
    }

    func testAReadFailureOfTheStoredRunIsTransient() throws {
        let (fs, store) = try seeded([V3.run(1)])
        fs.protectedDataUnavailable = true
        let result = store.drainOne(V3.id(1), .edit(rename("later")))
        XCTAssertNotNil(result.failed[V3.id(1)])
        XCTAssertTrue(result.dropped.isEmpty)
        fs.protectedDataUnavailable = false
        XCTAssertTrue(store.drainOne(V3.id(1), .edit(rename("later"))).isFullyDurable)
    }

    /// A failed barrier: the write is on disk but not durable. Its operation is not submitted
    /// again; the next drain's barrier makes it durable.
    func testAFailedBarrierWaitsAndTheNextDrainCompletesIt() throws {
        let (fs, store) = try seeded([V3.run(1)])
        fs.failNext = ("F_FULLFSYNC", nil, EIO)
        let first = store.drainOne(V3.id(1), .edit(rename("w")))
        XCTAssertNotNil(first.barrierError)
        XCTAssertEqual(first.awaitingBarrier, [V3.id(1)])
        XCTAssertTrue(first.durable.isEmpty)
        XCTAssertFalse(first.indexWritten, "no index before the barrier")
        let second = store.drain([])
        XCTAssertEqual(second.durable, [V3.id(1)])
        XCTAssertTrue(second.isFullyDurable)
        XCTAssertEqual(try reopened(fs).history.first?.summary.workoutName, "w")
    }

    func testAFailedIndexWriteIsRepairedFromTheFiles() throws {
        let (fs, store) = try seeded([V3.run(1)])
        let result = store.drainOne(V3.id(2), .add(V3.run(2), seq: 2))
        XCTAssertTrue(result.isFullyDurable)
        // Only the index is written with a replacing rename: fail that one.
        fs.failNext = ("rename", nil, ENOSPC)
        let failing = store.drainOne(V3.id(3), .add(V3.run(3), seq: 3))
        XCTAssertEqual(failing.durable, [V3.id(3)], "durability does not depend on the index")
        XCTAssertNotNil(failing.indexError)
        let back = try reopened(fs)
        XCTAssertEqual(back.report.indexState, .stale)
        XCTAssertEqual(back.history.map(\.id), [V3.id(3), V3.id(2), V3.id(1)])
    }

    /// Q-MIXED: several pending operations on several workouts in one drain.
    func testAMixedQueue() throws {
        let (fs, store) = try seeded([V3.run(1), V3.run(2), V3.run(3)])
        let result = store.drain([
            (V3.id(4), [.add(V3.run(4), seq: 4), .edit(rename("A"))]),
            (V3.id(2), [.edit(rename("B"))]),
            (V3.id(3), [.delete]),
            (V3.id(1), [.edit(rename("C")), .edit(rename("C2"))]),
        ])
        XCTAssertTrue(result.isFullyDurable)
        XCTAssertEqual(result.durable, [V3.id(1), V3.id(2), V3.id(3), V3.id(4)])
        let back = try reopened(fs)
        XCTAssertEqual(back.history.map(\.id), [V3.id(4), V3.id(1), V3.id(2)])
        XCTAssertEqual(back.history.map(\.summary.workoutName), ["A", "C2", "B"])
    }

    // MARK: - Purge (spec 3.6)

    func testPurgeRemovesOldTrashButKeepsDeletionEvidenceTheIndexStillNeeds() throws {
        let sources = V3.Sources()
        let (fs, store) = try seeded([V3.run(1), V3.run(2)], sources)
        XCTAssertTrue(store.drainOne(V3.id(1), .delete).isFullyDurable)
        // Simulate a delete whose index write never happened: the on-disk index still lists 2.
        let index = try XCTUnwrap(fs.contents(of: layout.index))
        XCTAssertTrue(store.drainOne(V3.id(2), .delete).isFullyDurable)
        fs.put(index, at: layout.index)
        sources.advance(31 * 24 * 3_600)
        XCTAssertEqual(try store.purgeTrash(), 1)
        let left = fs.names(in: layout.trash).compactMap(RunsV3TrashName.parse)
        XCTAssertEqual(left.map(\.id), [V3.id(2)], "INV-5: the evidence for index-listed 2 stays")
        XCTAssertEqual(try reopened(fs).history.count, 0)
    }

    func testPurgeKeepsRecentTrashAndRespectsTheCap() throws {
        let sources = V3.Sources()
        let (fs, store) = try seeded([V3.run(1)], sources)
        for n in 0..<3 {
            fs.put(Data(count: 80 * 1024 * 1024), at: layout.trash.appendingPathComponent(
                RunsV3TrashName(id: V3.id(50 + n), rev: 1, reason: .superseded,
                                milliseconds: Int64(sources.now.timeIntervalSince1970 * 1000) + Int64(n), random: "0000").string))
        }
        sources.advance(3_600)
        XCTAssertEqual(try store.purgeTrash(), 1, "240 MB of superseded files: the oldest goes, leaving 160 MB")
        XCTAssertEqual(fs.names(in: layout.trash).count, 2)
    }

    // MARK: - Wipe (spec 3.8)

    func testWipeDeactivatesWithOneRenameThenRemoves() throws {
        let (fs, _) = try seeded([V3.run(1)])
        fs.clearLog()
        try RunsV3Store.wipe(storage: V3.storage, fileSystem: fs, now: V3.start)
        XCTAssertEqual(fs.log.map { String($0.split(separator: " ")[0]) }, ["stat", "renameExclusive", "fsyncDirectory", "F_FULLFSYNC", "removeTree"])
        XCTAssertEqual(V3.store(fs).open(isProtectedDataAvailable: true), .notActive)
    }

    func testAWipeKilledAfterTheRenameLeavesNoHistoryAndRepairIsNotNeeded() throws {
        for kill in 0...4 {
            let (fs, _) = try seeded([V3.run(1)])
            fs.killAfterCalls = fs.callCount + kill
            XCTAssertThrowsError(try RunsV3Store.wipe(storage: V3.storage, fileSystem: fs, now: V3.start))
            let after = fs.afterKill()
            let result = V3.store(after).open(isProtectedDataAvailable: true)
            XCTAssertTrue(kill <= 1 ? result == .active(.writable) : result == .notActive, "kill \(kill): \(result)")
        }
    }
}
