import XCTest
@testable import WRKT

@MainActor
final class LegacyHistoryUpgradeTests: XCTestCase {
    private var root: URL!
    private var support: URL { root.appendingPathComponent("Application Support") }
    private var documents: URL { root.appendingPathComponent("Documents") }
    private var directory: URL { documents.appendingPathComponent("WRKT_Storage") }
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: support.appendingPathComponent("WRKT"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testMissingMigrationFlagCannotOverwriteExistingHistoryWithLegacyData() async throws {
        let storage = WorkoutStorage(directory: directory)
        let workout = TestFixtures.makeCompletedWorkout()
        try await storage.saveWorkouts([workout], prIndex: [:])
        try await storage.saveRuns([])
        try encoder.encode([TestFixtures.makeCompletedWorkout()]).write(to: documents.appendingPathComponent("workouts.json"))
        try await storage.migrateFromLegacyStorage(applicationSupport: support, documents: documents)
        let saved = try await storage.loadWorkouts()
        XCTAssertEqual(saved.workouts.map(\.id), [workout.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents.appendingPathComponent("workouts.json").path))
    }

    func testUnreadableLegacyHistoryAbortsBeforeWritingNewFilesOrMigrationFlag() async throws {
        let storage = WorkoutStorage(directory: directory)
        let source = documents.appendingPathComponent("workouts.json")
        let corrupt = Data("{broken legacy history".utf8)
        try corrupt.write(to: source)
        do {
            try await storage.migrateFromLegacyStorage(applicationSupport: support, documents: documents)
            XCTFail("Unreadable history must never be treated as an empty successful import")
        } catch { }
        for name in ["workouts_v2.json", "runs_v2.json", ".migrated"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        }
        XCTAssertEqual(try Data(contentsOf: source), corrupt)
    }

    func testLegacyWorkoutAndRunImportPreservesIDsAndSourcesAndCanReplay() async throws {
        let storage = WorkoutStorage(directory: directory)
        let workout = TestFixtures.makeCompletedWorkout()
        let run = Run(date: .now, distanceKm: 5, durationSec: 1800, healthKitUUID: UUID())
        let workoutFile = documents.appendingPathComponent("workouts.json")
        let runFile = support.appendingPathComponent("WRKT/runs.json")
        try encoder.encode([workout]).write(to: workoutFile)
        try encoder.encode([run]).write(to: runFile)
        try WorkoutStorage.validateExistingData(applicationSupport: support, documents: documents)
        try await storage.migrateFromLegacyStorage(applicationSupport: support, documents: documents)
        try await storage.migrateFromLegacyStorage(applicationSupport: support, documents: documents)
        let saved = try await storage.loadWorkouts()
        let runs = try await storage.loadRuns()
        XCTAssertEqual(saved.workouts.map(\.id), [workout.id])
        XCTAssertEqual(runs.map(\.id), [run.id])
        XCTAssertEqual(runs.first?.healthKitUUID, run.healthKitUUID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workoutFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runFile.path))
    }

    func testOldActiveWorkoutWithoutReceiptsLoadsAndPartialMigrationIsPreserved() async throws {
        let storage = WorkoutStorage(directory: directory)
        let workout = CurrentWorkout(entries: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(workout)) as? [String: Any])
        object.removeValue(forKey: "setLogReceipts")
        let file = directory.appendingPathComponent("current_workout_v2.json")
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: file)
        let decoded = try await storage.loadCurrentWorkout()
        XCTAssertEqual(decoded?.id, workout.id)
        XCTAssertEqual(decoded?.setLogReceipts, [])
        do {
            try await storage.migrateFromLegacyStorage(applicationSupport: support, documents: documents)
            XCTFail("An ambiguous partial import needs recovery, not a reset")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".migrated").path))
    }

    func testMalformedSavedFieldsStopHistoryLoadingWithoutChangingTheFile() async throws {
        let storage = WorkoutStorage(directory: directory)
        let workout = TestFixtures.makeCompletedWorkout()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(workout)) as? [String: Any])
        let file = directory.appendingPathComponent("workouts_v2.json")
        for field in ["id", "date", "entries", "matchedHealthKitUUID", "cardioSplits"] {
            var damaged = original
            damaged[field] = "invalid saved value"
            let bytes = try JSONSerialization.data(withJSONObject: [
                "metadata": ["version": 1, "lastModified": "2026-01-01T00:00:00Z", "itemCount": 1],
                "workouts": [damaged], "prIndex": [:]
            ])
            try bytes.write(to: file)
            do {
                _ = try await storage.loadWorkouts()
                XCTFail("Malformed \(field) must not become empty history or a new identity")
            } catch { }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testMalformedActiveWorkoutAndNestedSetStopLoadingWithoutDroppingExercises() async throws {
        let storage = WorkoutStorage(directory: directory)
        let file = directory.appendingPathComponent("current_workout_v2.json")
        let workout = CurrentWorkout(entries: TestFixtures.makeCompletedWorkout().entries)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(workout)) as? [String: Any])
        for field in ["entries", "activeEntryID", "setDuration", "setCompletion"] {
            var damaged = original
            if field.hasPrefix("set") {
                var entries = try XCTUnwrap(damaged["entries"] as? [[String: Any]])
                var sets = try XCTUnwrap(entries[0]["sets"] as? [[String: Any]])
                sets[0][field == "setDuration" ? "durationSeconds" : "isCompleted"] = "invalid saved value"
                entries[0]["sets"] = sets
                damaged["entries"] = entries
            } else {
                damaged[field] = "invalid saved value"
            }
            let bytes = try JSONSerialization.data(withJSONObject: damaged)
            try bytes.write(to: file)
            do {
                _ = try await storage.loadCurrentWorkout()
                XCTFail("Malformed \(field) must stop loading instead of discarding saved data")
            } catch { }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testOlderSetsWithoutOptionalFieldsStillPreserveRepsAndWeight() throws {
        let bytes = Data(#"{"reps":8,"weight":42.5}"#.utf8)
        let set = try JSONDecoder().decode(SetInput.self, from: bytes)
        XCTAssertEqual(set.reps, 8)
        XCTAssertEqual(set.weight, 42.5)
        XCTAssertEqual(set.durationSeconds, 0)
        XCTAssertEqual(set.trackingMode, .weighted)
        XCTAssertFalse(set.isCompleted)
    }
}
