import XCTest
@testable import WRKT

/// A process killed during a history write leaves the temporary file behind (Foundation's
/// `<name>.sb-<hex>-<random>`, or the durable writer's `<name>.wrkt-<uuid>.tmp`). The storage
/// removes exactly those, beside its own files, before its first write, and nothing else.
final class HistoryLeftoverCleanupTests: XCTestCase {
    private var root: URL!
    private var directory: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directory = root.appendingPathComponent("WRKT_Storage")
        try fm.createDirectory(at: directory.appendingPathComponent("Backups"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func file(_ name: String, in folder: URL? = nil, size: Int = 3) throws {
        try Data(repeating: 1, count: size).write(to: (folder ?? directory).appendingPathComponent(name))
    }

    private func exists(_ name: String, in folder: URL? = nil) -> Bool {
        var info = stat()
        return lstat((folder ?? directory).appendingPathComponent(name).path, &info) == 0
    }

    private static let historyNames = ["workouts_v2.json", "current_workout_v2.json", "runs_v2.json",
                                       "ignored_healthkit_uuids.json", "discarded_workout_windows.json"]

    func testRemovesLeftoversOfEveryHistoryFileAndKeepsEverythingElse() async throws {
        var leftovers: [String] = []
        for (index, name) in Self.historyNames.enumerated() {
            leftovers.append("\(name).sb-44c8b3bc-Abc12\(index)")
            leftovers.append(DurableFileWriter.temporaryName(for: name))
        }
        for name in leftovers { try file(name, size: 1_000) }

        let token = UUID().uuidString.lowercased()
        let realFiles = ["runs_v2.json", "workouts_v2.json", "custom_exercises.json", ".migrated"]
        let nearMisses = [
            "runs_v2.json.sb-44c8b3bc-Abc12",          // suffix too short
            "runs_v2.json.sb-44C8B3BC-Abc123",         // uppercase hex
            "Runs_v2.json.sb-44c8b3bc-Xyz123",         // different case
            "runs_v2.json.sb-44c8b3bc-Abc123.json",    // longer
            "runs_v2.json.wrkt-\(token.uppercased()).tmp",
            "runs_v2.json.wrkt-\(token).tmp.old",
            "custom_exercises.json.sb-44c8b3bc-Abc123", // written by another store
            "custom_splits.json.wrkt-\(token).tmp",
            "runs_v2.json.backup",
        ]
        for name in realFiles + nearMisses { try file(name) }

        // A leftover name that is a directory, and one that is a symbolic link to a file outside.
        let directoryNamed = "runs_v2.json.sb-44c8b3bc-Dir123"
        try fm.createDirectory(at: directory.appendingPathComponent(directoryNamed), withIntermediateDirectories: false)
        let outside = root.appendingPathComponent("outside.json")
        try Data("keep".utf8).write(to: outside)
        let linkNamed = "runs_v2.json.sb-44c8b3bc-Lnk123"
        try fm.createSymbolicLink(at: directory.appendingPathComponent(linkNamed), withDestinationURL: outside)
        // Leftover names in a subdirectory and outside the storage directory.
        let backups = directory.appendingPathComponent("Backups")
        try file("runs_v2.json.sb-44c8b3bc-Bak123", in: backups)
        try file("runs_backup_2026-11-19T10-00-00Z_x.json", in: backups)
        try file("runs_v2.json.sb-44c8b3bc-Out123", in: root)

        let storage = WorkoutStorage(directory: directory)
        try await storage.saveIgnoredHealthKitUUIDs([UUID()])

        for name in leftovers { XCTAssertFalse(exists(name), name) }
        for name in realFiles + nearMisses + [directoryNamed, linkNamed] { XCTAssertTrue(exists(name), name) }
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
        XCTAssertTrue(exists("runs_v2.json.sb-44c8b3bc-Bak123", in: backups))
        XCTAssertTrue(exists("runs_backup_2026-11-19T10-00-00Z_x.json", in: backups))
        XCTAssertTrue(exists("runs_v2.json.sb-44c8b3bc-Out123", in: root))
        XCTAssertTrue(exists("ignored_healthkit_uuids.json"))
    }

    func testRunsOnlyBeforeTheFirstWriteOfAnInstance() async throws {
        let storage = WorkoutStorage(directory: directory)
        try await storage.saveIgnoredHealthKitUUIDs([])
        try file("runs_v2.json.sb-44c8b3bc-Late12")
        try await storage.saveIgnoredHealthKitUUIDs([UUID()])
        XCTAssertTrue(exists("runs_v2.json.sb-44c8b3bc-Late12"),
                      "after its first write the instance never removes temporary files again")
    }

    func testLoadingDoesNotRemoveAnything() async throws {
        try file("runs_v2.json.sb-44c8b3bc-Load12")
        let storage = WorkoutStorage(directory: directory)
        _ = try await storage.loadRuns()
        XCTAssertTrue(exists("runs_v2.json.sb-44c8b3bc-Load12"))
    }

    func testEveryKindOfHistoryWriteRemovesLeftoversFirst() async throws {
        let writes: [(String, (WorkoutStorage) async throws -> Void)] = [
            ("runs", { try await $0.saveRuns([]) }),
            ("workouts", { try await $0.saveWorkouts([], prIndex: [:]) }),
            ("current", { try await $0.saveCurrentWorkout(TestFixtures.makeCurrentWorkout()) }),
            ("ignored", { try await $0.saveIgnoredHealthKitUUIDs([]) }),
            ("windows", { try await $0.saveDiscardedWorkoutWindows([]) }),
        ]
        for (label, write) in writes {
            try file("runs_v2.json.sb-44c8b3bc-Kind12")
            try await write(WorkoutStorage(directory: directory))
            XCTAssertFalse(exists("runs_v2.json.sb-44c8b3bc-Kind12"), label)
        }
    }
}
