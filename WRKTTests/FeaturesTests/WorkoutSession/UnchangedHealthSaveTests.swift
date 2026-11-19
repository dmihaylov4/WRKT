import XCTest
@testable import WRKT

/// A Health flush must not rewrite or back up run history that has not changed, and must
/// still write every change before the Health anchor is allowed to advance.
@MainActor
final class UnchangedHealthSaveTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }
    private var ignoredFile: URL { directory.appendingPathComponent("ignored_healthkit_uuids.json") }
    private var backups: URL { directory.appendingPathComponent("Backups") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "UnchangedHealthSaveTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeRun(_ distanceKm: Double = 5) -> Run {
        Run(date: .now, distanceKm: distanceKm, durationSec: 1800, healthKitUUID: UUID())
    }

    /// Writes history the way a previous launch left it, then opens a store on a fresh storage
    /// instance, as a relaunch does.
    private func relaunch(runs: [Run], ignored: Set<UUID> = []) async throws -> (WorkoutStoreV2, WorkoutStorage) {
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts([], prIndex: [:])
        try await previous.saveRuns(runs)
        try await previous.saveIgnoredHealthKitUUIDs(ignored)
        let storage = WorkoutStorage(directory: directory)
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()
        return (store, storage)
    }

    private func backupCount(_ prefix: String) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.count
    }

    // MARK: - Skipping unchanged saves

    func testFlushAfterLoadWithNoChangesWritesNothing() async throws {
        let (store, _) = try await relaunch(runs: [makeRun(), makeRun()], ignored: [UUID()])
        let runsStamp = try XCTUnwrap(FileStamp(runsFile))
        let ignoredStamp = try XCTUnwrap(FileStamp(ignoredFile))

        try await store.flushHealthKitChanges()
        try await store.flushHealthKitChanges()

        XCTAssertEqual(FileStamp(runsFile), runsStamp, "Unchanged runs were rewritten")
        XCTAssertEqual(FileStamp(ignoredFile), ignoredStamp, "Unchanged ignored UUIDs were rewritten")
        XCTAssertEqual(backupCount("runs_backup_"), 0, "Unchanged runs were backed up")
    }

    func testImportThenFlushWrites() async throws {
        let existing = makeRun()
        let (store, storage) = try await relaunch(runs: [existing])
        let stamp = FileStamp(runsFile)

        let imported = makeRun(10)
        store.addRun(imported)
        try await store.flushHealthKitChanges()

        XCTAssertNotEqual(FileStamp(runsFile), stamp)
        let durable = try await storage.loadRuns()
        XCTAssertEqual(Set(durable.map(\.id)), [existing.id, imported.id])
        // The previous file was kept as a restore point before it was replaced.
        XCTAssertEqual(backupCount("runs_backup_"), 1)
    }

    func testRepeatedFlushAfterOneImportWritesOnce() async throws {
        let (store, _) = try await relaunch(runs: [makeRun()])
        store.addRun(makeRun(10))
        try await store.flushHealthKitChanges()
        let stamp = FileStamp(runsFile)

        try await store.flushHealthKitChanges()

        XCTAssertEqual(FileStamp(runsFile), stamp)
    }

    func testDeletionThenFlushWrites() async throws {
        let kept = makeRun()
        let deleted = makeRun(8)
        let (store, storage) = try await relaunch(runs: [kept, deleted])
        try await store.flushHealthKitChanges()

        store.removeRun(withId: deleted.id)
        try await store.flushHealthKitChanges()

        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.map(\.id), [kept.id])
    }

    func testChangedRunThenFlushWrites() async throws {
        var run = makeRun()
        let (store, storage) = try await relaunch(runs: [run])
        try await store.flushHealthKitChanges()

        run.avgHeartRate = 151
        store.updateRun(run)
        try await store.flushHealthKitChanges()

        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.avgHeartRate, 151)
    }

    func testBatchUpdatedRunThenFlushWrites() async throws {
        var run = makeRun()
        let (store, storage) = try await relaunch(runs: [run])
        try await store.flushHealthKitChanges()

        run.calories = 420
        store.batchUpdateRuns([run])
        try await store.flushHealthKitChanges()

        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.first?.calories, 420)
    }

    func testFailedWriteIsReportedAndTheNextFlushWritesAgain() async throws {
        let (store, storage) = try await relaunch(runs: [makeRun()])
        let run = makeRun(12)

        // A directory in place of the file makes every run write fail.
        try FileManager.default.removeItem(at: runsFile)
        try FileManager.default.createDirectory(at: runsFile, withIntermediateDirectories: false)
        store.addRun(run)
        do {
            try await store.flushHealthKitChanges()
            XCTFail("A failed run write must fail the flush")
        } catch { }
        // No further change in memory: the failure alone must keep the state unsaved.
        do {
            try await store.flushHealthKitChanges()
            XCTFail("The second flush must write again and report the failure again")
        } catch { }

        try FileManager.default.removeItem(at: runsFile)
        try await store.flushHealthKitChanges()
        let durable = try await storage.loadRuns()
        XCTAssertTrue(durable.contains { $0.id == run.id })
    }

    func testFileReplacedOutsideTheStoreIsRewritten() async throws {
        let run = makeRun()
        let (store, storage) = try await relaunch(runs: [run])
        try await store.flushHealthKitChanges()

        // Anything that changes the file behind the store's back voids the clean state.
        try Data("[]".utf8).write(to: runsFile, options: .atomic)
        try await store.flushHealthKitChanges()

        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.map(\.id), [run.id])
    }

    func testDeduplicationAppliedDuringLoadIsSaved() async throws {
        let uuid = UUID()
        let first = Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: uuid)
        let duplicate = Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: uuid)
        let (store, storage) = try await relaunch(runs: [first, duplicate])

        try await store.flushHealthKitChanges()

        XCTAssertEqual(store.runs.map(\.id), [first.id])
        let durable = try await storage.loadRuns()
        XCTAssertEqual(durable.map(\.id), [first.id])
    }

    // MARK: - Ignored HealthKit UUIDs

    func testIgnoredUUIDChangesAreSaved() async throws {
        let kept = UUID()
        let (store, storage) = try await relaunch(runs: [makeRun()], ignored: [kept])

        let added = UUID()
        store.addIgnoredHealthKitUUID(added)
        try await store.flushHealthKitChanges()
        let afterAdd = try await storage.loadIgnoredHealthKitUUIDs()
        XCTAssertEqual(afterAdd, [kept, added])

        store.removeIgnoredHealthKitUUID(kept)
        try await store.flushHealthKitChanges()
        let afterRemove = try await storage.loadIgnoredHealthKitUUIDs()
        XCTAssertEqual(afterRemove, [added])
    }

    func testDeletedIgnoredFileIsRewrittenByTheNextFlush() async throws {
        let ignored = UUID()
        let (store, storage) = try await relaunch(runs: [makeRun()], ignored: [ignored])

        // A data reset deletes this file without telling the store.
        try FileManager.default.removeItem(at: ignoredFile)
        try await store.flushHealthKitChanges()

        let durable = try await storage.loadIgnoredHealthKitUUIDs()
        XCTAssertEqual(durable, [ignored])
    }

    // MARK: - Backup throttle across launches

    /// A previous launch whose first save backed up the runs file it replaced. That file was
    /// written an hour earlier, and a copy keeps its dates, as on a real device.
    private func backUpOnce() async throws {
        try Data("[]".utf8).write(to: runsFile)
        let anHourAgo = Date.now.addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.creationDate: anHourAgo, .modificationDate: anHourAgo],
                                              ofItemAtPath: runsFile.path)
        try await WorkoutStorage(directory: directory).saveRuns([makeRun()])
    }

    /// Renames the only runs backup as if it had been made `offset` seconds from now.
    @discardableResult
    private func redateBackup(by offset: TimeInterval) throws -> String {
        let old = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: backups.path)
            .first { $0.hasPrefix("runs_backup_") })
        let timestamp = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(offset))
            .replacingOccurrences(of: ":", with: "-")
        let new = "runs_backup_\(timestamp)_\(UUID().uuidString).json"
        try FileManager.default.moveItem(at: backups.appendingPathComponent(old),
                                         to: backups.appendingPathComponent(new))
        return new
    }

    func testRelaunchWithinTheBackupWindowDoesNotBackUpAgain() async throws {
        try await backUpOnce()
        XCTAssertEqual(backupCount("runs_backup_"), 1)

        let relaunched = WorkoutStorage(directory: directory)
        try await relaunched.saveRuns([makeRun()])

        XCTAssertEqual(backupCount("runs_backup_"), 1)
    }

    func testChangeAfterTheBackupWindowBacksUpBeforeReplacing() async throws {
        try await backUpOnce()
        let backup = try redateBackup(by: -301)
        let replaced = try Data(contentsOf: runsFile)

        let relaunched = WorkoutStorage(directory: directory)
        try await relaunched.saveRuns([makeRun()])

        XCTAssertEqual(backupCount("runs_backup_"), 2)
        let newest = try FileManager.default.contentsOfDirectory(atPath: backups.path)
            .filter { $0 != backup && $0.hasPrefix("runs_backup_") }
        let newestData = try Data(contentsOf: backups.appendingPathComponent(try XCTUnwrap(newest.first)))
        XCTAssertEqual(newestData, replaced)
    }

    func testBackupDatedInTheFutureDoesNotSuppressBackups() async throws {
        try await backUpOnce()
        try redateBackup(by: 86_400)

        let relaunched = WorkoutStorage(directory: directory)
        try await relaunched.saveRuns([makeRun()])

        XCTAssertEqual(backupCount("runs_backup_"), 2)
    }

    func testWorkoutsRelaunchWithinTheBackupWindowDoesNotBackUpAgain() async throws {
        try Data("{}".utf8).write(to: directory.appendingPathComponent("workouts_v2.json"))
        // The first save of a process backs up the file it replaces.
        try await WorkoutStorage(directory: directory).saveWorkouts([TestFixtures.makeCompletedWorkout()], prIndex: [:])
        XCTAssertEqual(backupCount("workouts_backup_"), 1)

        let relaunched = WorkoutStorage(directory: directory)
        try await relaunched.saveWorkouts([TestFixtures.makeCompletedWorkout()], prIndex: [:])

        XCTAssertEqual(backupCount("workouts_backup_"), 1)
    }
}
