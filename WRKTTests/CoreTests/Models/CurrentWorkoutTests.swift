//
//  CurrentWorkoutTests.swift
//  WRKTTests
//
//  Tests for CurrentWorkout model
//

import XCTest
@testable import WRKT

final class CurrentWorkoutTests: WRKTTestCase {

    func testCurrentWorkoutCreation() {
        let startDate = makeDate(year: 2025, month: 10, day: 26, hour: 14, minute: 30)
        let workout = CurrentWorkout(
            id: UUID(),
            startedAt: startDate,
            entries: [TestFixtures.benchPressEntry],
            plannedWorkoutID: nil
        )

        assertDatesEqual(workout.startedAt, startDate)
        XCTAssertEqual(workout.entries.count, 1)
        XCTAssertNil(workout.plannedWorkoutID)
    }

    func testCurrentWorkoutWithPlannedWorkoutID() {
        let plannedID = UUID()
        let workout = CurrentWorkout(
            id: UUID(),
            startedAt: Date(),
            entries: [],
            plannedWorkoutID: plannedID
        )

        XCTAssertEqual(workout.plannedWorkoutID, plannedID)
    }

    func testCurrentWorkoutCodable() {
        let workout = TestFixtures.makeCurrentWorkout()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(workout)
            let decoded = try decoder.decode(CurrentWorkout.self, from: data)

            XCTAssertEqual(decoded.id, workout.id)
            assertDatesEqual(decoded.startedAt, workout.startedAt)
            XCTAssertEqual(decoded.entries.count, workout.entries.count)
            XCTAssertEqual(decoded.plannedWorkoutID, workout.plannedWorkoutID)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }

    func testCurrentWorkoutCodableWithPlannedWorkoutID() {
        let plannedID = UUID()
        let workout = CurrentWorkout(
            id: UUID(),
            startedAt: Date(),
            entries: [TestFixtures.benchPressEntry, TestFixtures.squatEntry],
            plannedWorkoutID: plannedID
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(workout)
            let decoded = try decoder.decode(CurrentWorkout.self, from: data)

            XCTAssertEqual(decoded.id, workout.id)
            assertDatesEqual(decoded.startedAt, workout.startedAt)
            XCTAssertEqual(decoded.entries.count, workout.entries.count)
            XCTAssertEqual(decoded.plannedWorkoutID, plannedID)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }

    func testCurrentWorkoutEmptyEntries() {
        let workout = CurrentWorkout(
            id: UUID(),
            startedAt: Date(),
            entries: [],
            plannedWorkoutID: nil
        )

        XCTAssertEqual(workout.entries.count, 0)
    }

    func testCurrentWorkoutMultipleEntries() {
        let workout = CurrentWorkout(
            id: UUID(),
            startedAt: Date(),
            entries: [
                TestFixtures.benchPressEntry,
                TestFixtures.squatEntry,
                WorkoutEntry(
                    id: UUID(),
                    exerciseID: "test-3",
                    exerciseName: "Test 3",
                    muscleGroups: [],
                    sets: []
                )
            ],
            plannedWorkoutID: nil
        )

        XCTAssertEqual(workout.entries.count, 3)
    }
}
