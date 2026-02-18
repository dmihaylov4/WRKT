//
//  WorkoutStorageTests.swift
//  WRKTTests
//
//  Tests for WorkoutStorage actor
//
//  Note: These tests use a real WorkoutStorage instance but with isolated test data.
//  Consider creating a protocol-based storage interface for true unit testing.
//

import XCTest
@testable import WRKT

final class WorkoutStorageTests: WRKTTestCase {

    // MARK: - Storage Metadata Tests

    func testStorageMetadataCreation() {
        let metadata = StorageMetadata(
            version: 1,
            lastModified: Date(),
            itemCount: 5
        )

        XCTAssertEqual(metadata.version, 1)
        XCTAssertEqual(metadata.itemCount, 5)
    }

    func testStorageMetadataCodable() {
        let metadata = StorageMetadata(
            version: StorageMetadata.currentVersion,
            lastModified: Date(),
            itemCount: 10
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(metadata)
            let decoded = try decoder.decode(StorageMetadata.self, from: data)

            XCTAssertEqual(decoded.version, metadata.version)
            XCTAssertEqual(decoded.itemCount, metadata.itemCount)
            assertDatesEqual(decoded.lastModified, metadata.lastModified)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }

    // MARK: - WorkoutStorageContainer Tests

    func testWorkoutStorageContainerCreation() {
        let workouts = [TestFixtures.makeCompletedWorkout()]
        let prIndex = ["bench-press": TestFixtures.samplePR]

        let container = WorkoutStorageContainer(
            workouts: workouts,
            prIndex: prIndex
        )

        XCTAssertEqual(container.workouts.count, 1)
        XCTAssertEqual(container.prIndex.count, 1)
        XCTAssertEqual(container.metadata.itemCount, 1)
        XCTAssertEqual(container.metadata.version, StorageMetadata.currentVersion)
    }

    func testWorkoutStorageContainerCodable() {
        let workouts = [
            TestFixtures.makeCompletedWorkout(),
            TestFixtures.makeCompletedWorkout()
        ]
        let prIndex = [
            "bench-press": TestFixtures.samplePR,
            "squat": TestFixtures.samplePR
        ]

        let container = WorkoutStorageContainer(
            workouts: workouts,
            prIndex: prIndex
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(container)
            let decoded = try decoder.decode(WorkoutStorageContainer.self, from: data)

            // Verify basic properties
            XCTAssertEqual(decoded.workouts.count, container.workouts.count)
            XCTAssertEqual(decoded.prIndex.count, container.prIndex.count)
            XCTAssertEqual(decoded.metadata.version, container.metadata.version)
            XCTAssertEqual(decoded.metadata.itemCount, container.metadata.itemCount)

            // Verify PR index keys
            XCTAssertEqual(Set(decoded.prIndex.keys), Set(container.prIndex.keys))

            // Verify workouts have same IDs
            let decodedIDs = Set(decoded.workouts.map { $0.id })
            let originalIDs = Set(container.workouts.map { $0.id })
            XCTAssertEqual(decodedIDs, originalIDs)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }

    // MARK: - PR Data Structure Tests

    func testLastSetV2Creation() {
        let lastSet = LastSetV2(
            date: Date(),
            reps: 8,
            weightKg: 100.0
        )

        XCTAssertEqual(lastSet.reps, 8)
        XCTAssertEqual(lastSet.weightKg, 100.0)
    }

    func testLastSetV2Codable() {
        let lastSet = LastSetV2(
            date: makeDate(year: 2025, month: 10, day: 26),
            reps: 10,
            weightKg: 85.5
        )

        assertCodable(lastSet)
    }

    func testExercisePRsV2Creation() {
        var pr = ExercisePRsV2()
        pr.bestPerReps = [5: 100.0, 8: 85.0, 10: 75.0]
        pr.bestE1RM = 116.0
        pr.lastWorking = LastSetV2(date: Date(), reps: 8, weightKg: 85.0)
        pr.allTimeBest = 100.0
        pr.firstRecorded = Date()

        XCTAssertEqual(pr.bestPerReps.count, 3)
        XCTAssertEqual(pr.bestPerReps[5], 100.0)
        XCTAssertEqual(pr.bestPerReps[8], 85.0)
        XCTAssertEqual(pr.bestE1RM, 116.0)
        XCTAssertNotNil(pr.lastWorking)
        XCTAssertEqual(pr.allTimeBest, 100.0)
        XCTAssertNotNil(pr.firstRecorded)
    }

    func testExercisePRsV2Codable() {
        let pr = TestFixtures.samplePR

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(pr)
            let decoded = try decoder.decode(ExercisePRsV2.self, from: data)

            // Compare fields individually to handle date tolerance and dictionary ordering
            XCTAssertEqual(decoded.bestPerReps, pr.bestPerReps)
            XCTAssertEqual(decoded.bestE1RM, pr.bestE1RM)
            XCTAssertEqual(decoded.allTimeBest, pr.allTimeBest)

            // Compare dates with tolerance
            if let decodedLastWorking = decoded.lastWorking, let prLastWorking = pr.lastWorking {
                XCTAssertEqual(decodedLastWorking.reps, prLastWorking.reps)
                XCTAssertEqual(decodedLastWorking.weightKg, prLastWorking.weightKg)
                assertDatesEqual(decodedLastWorking.date, prLastWorking.date)
            } else {
                XCTAssertEqual(decoded.lastWorking == nil, pr.lastWorking == nil)
            }

            assertDatesEqual(decoded.firstRecorded, pr.firstRecorded)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }

    func testExercisePRsV2DefaultValues() {
        let pr = ExercisePRsV2()

        XCTAssertTrue(pr.bestPerReps.isEmpty)
        XCTAssertNil(pr.bestE1RM)
        XCTAssertNil(pr.lastWorking)
        XCTAssertNil(pr.allTimeBest)
        XCTAssertNil(pr.firstRecorded)
    }

    // MARK: - StorageError Tests

    func testStorageErrorDescriptions() {
        let fileNotFoundError = StorageError.fileNotFound("/path/to/file")
        XCTAssertTrue(fileNotFoundError.errorDescription?.contains("/path/to/file") ?? false)

        let encodingError = StorageError.encodingFailed("TestType", underlying: NSError(domain: "test", code: 1))
        XCTAssertTrue(encodingError.errorDescription?.contains("TestType") ?? false)

        let decodingError = StorageError.decodingFailed("TestType", underlying: NSError(domain: "test", code: 1))
        XCTAssertTrue(decodingError.errorDescription?.contains("TestType") ?? false)

        let validationError = StorageError.validationFailed("Invalid data")
        XCTAssertTrue(validationError.errorDescription?.contains("Invalid data") ?? false)
    }

    // MARK: - Integration Tests
    // Note: These test the actual singleton instance, so they may have side effects
    // In production, consider creating a protocol-based storage interface for dependency injection

    func testLoadWorkoutsWhenEmpty() async {
        let storage = WorkoutStorage.shared

        // This will either load existing data or return empty
        // We can't guarantee the state without a testable storage instance
        let result = await assertAsyncNoThrow(try await storage.loadWorkouts())

        XCTAssertNotNil(result)
        // Don't assert on count since we can't control the singleton state
    }

    func testCurrentWorkoutLifecycle() async {
        // Note: This test uses the real singleton and may affect other tests
        // Consider implementing a protocol-based storage for true isolation

        let storage = WorkoutStorage.shared
        let testWorkout = TestFixtures.makeCurrentWorkout()

        // Save
        do {
            try await storage.saveCurrentWorkout(testWorkout)
        } catch {
            XCTFail("Failed to save workout: \(error)")
            return
        }

        // Load
        do {
            let loaded = try await storage.loadCurrentWorkout()
            XCTAssertNotNil(loaded)
            XCTAssertEqual(loaded?.entries.count, testWorkout.entries.count)
        } catch {
            XCTFail("Failed to load workout: \(error)")
            return
        }

        // Delete
        do {
            try await storage.deleteCurrentWorkout()
        } catch {
            XCTFail("Failed to delete workout: \(error)")
            return
        }

        // Verify deleted
        do {
            let afterDelete = try await storage.loadCurrentWorkout()
            XCTAssertNil(afterDelete)
        } catch {
            XCTFail("Failed to verify deletion: \(error)")
        }
    }

    func testSaveAndLoadCurrentWorkoutNil() async {
        let storage = WorkoutStorage.shared

        // Save nil (delete)
        do {
            try await storage.saveCurrentWorkout(nil)
        } catch {
            XCTFail("Failed to save nil workout: \(error)")
            return
        }

        // Load should return nil
        do {
            let loaded = try await storage.loadCurrentWorkout()
            XCTAssertNil(loaded, "Expected nil after saving nil workout")
        } catch {
            XCTFail("Failed to load after saving nil: \(error)")
        }
    }

    func testValidateStorageBasic() async {
        let storage = WorkoutStorage.shared

        // Validation should either succeed or fail gracefully
        // We can't assert the result without knowing the storage state
        let result = await assertAsyncNoThrow(try await storage.validateStorage())

        // Just verify it returns a boolean
        XCTAssertNotNil(result)
    }

    func testGetStorageStats() async {
        let storage = WorkoutStorage.shared

        let stats = await storage.getStorageStats()

        // Verify stats dictionary has expected keys
        XCTAssertTrue(stats.keys.contains("hasCurrentWorkout"))
    }
}
