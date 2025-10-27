//
//  CompletedWorkoutTests.swift
//  WRKTTests
//
//  Tests for CompletedWorkout model
//

import XCTest
@testable import WRKT

final class CompletedWorkoutTests: WRKTTestCase {

    func testCompletedWorkoutCreation() {
        let date = makeDate(year: 2025, month: 10, day: 26, hour: 15, minute: 0)
        let workout = CompletedWorkout(
            id: UUID(),
            date: date,
            entries: [TestFixtures.benchPressEntry]
        )

        assertDatesEqual(workout.date, date)
        XCTAssertEqual(workout.entries.count, 1)
        XCTAssertNil(workout.plannedWorkoutID)
        XCTAssertNil(workout.matchedHealthKitUUID)
    }

    func testCompletedWorkoutCodable() {
        let workout = TestFixtures.makeCompletedWorkout()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(workout)
            let decoded = try decoder.decode(CompletedWorkout.self, from: data)

            XCTAssertEqual(decoded.id, workout.id)
            assertDatesEqual(decoded.date, workout.date)
            XCTAssertEqual(decoded.entries.count, workout.entries.count)
            XCTAssertEqual(decoded.plannedWorkoutID, workout.plannedWorkoutID)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }

    func testCompletedWorkoutWithPlannedWorkoutID() {
        let plannedID = UUID()
        let workout = CompletedWorkout(
            id: UUID(),
            date: Date(),
            entries: [],
            plannedWorkoutID: plannedID
        )

        XCTAssertEqual(workout.plannedWorkoutID, plannedID)
    }

    func testCompletedWorkoutDecodesLegacyDataWithoutDate() throws {
        // Legacy data without date field
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "entries": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let workout = try decoder.decode(CompletedWorkout.self, from: data)

        XCTAssertEqual(workout.entries.count, 0)
        // Should use .now as fallback
        XCTAssertNotNil(workout.date)
    }

    func testCompletedWorkoutDecodesLegacyDataWithoutID() throws {
        let json = """
        {
            "date": "2025-10-26T12:00:00Z",
            "entries": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let workout = try decoder.decode(CompletedWorkout.self, from: data)

        // Should generate new UUID
        XCTAssertNotNil(workout.id)
        XCTAssertEqual(workout.entries.count, 0)
    }

    func testCompletedWorkoutWithHealthKitData() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "date": "2025-10-26T12:00:00Z",
            "entries": [],
            "matchedHealthKitUUID": "660e8400-e29b-41d4-a716-446655440000",
            "matchedHealthKitCalories": 450.5,
            "matchedHealthKitHeartRate": 145.0,
            "matchedHealthKitMaxHeartRate": 175.0,
            "matchedHealthKitMinHeartRate": 120.0,
            "matchedHealthKitDuration": 3600
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let workout = try decoder.decode(CompletedWorkout.self, from: data)

        XCTAssertNotNil(workout.matchedHealthKitUUID)
        XCTAssertEqual(workout.matchedHealthKitCalories, 450.5)
        XCTAssertEqual(workout.matchedHealthKitHeartRate, 145.0)
        XCTAssertEqual(workout.matchedHealthKitMaxHeartRate, 175.0)
        XCTAssertEqual(workout.matchedHealthKitMinHeartRate, 120.0)
        XCTAssertEqual(workout.matchedHealthKitDuration, 3600)
    }

    func testCompletedWorkoutWithHeartRateSamples() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "date": "2025-10-26T12:00:00Z",
            "entries": [],
            "matchedHealthKitHeartRateSamples": [
                {"timestamp": "2025-10-26T12:00:00Z", "bpm": 120.0},
                {"timestamp": "2025-10-26T12:10:00Z", "bpm": 145.0},
                {"timestamp": "2025-10-26T12:20:00Z", "bpm": 130.0}
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = json.data(using: .utf8)!
        let workout = try decoder.decode(CompletedWorkout.self, from: data)

        XCTAssertNotNil(workout.matchedHealthKitHeartRateSamples)
        XCTAssertEqual(workout.matchedHealthKitHeartRateSamples?.count, 3)
        XCTAssertEqual(workout.matchedHealthKitHeartRateSamples?.first?.bpm, 120.0)
        XCTAssertEqual(workout.matchedHealthKitHeartRateSamples?.last?.bpm, 130.0)
    }

    func testHeartRateSampleCodable() {
        let sample = HeartRateSample(
            timestamp: makeDate(year: 2025, month: 10, day: 26, hour: 12, minute: 0),
            bpm: 145.5
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(sample)
            let decoded = try decoder.decode(HeartRateSample.self, from: data)

            assertDatesEqual(decoded.timestamp, sample.timestamp)
            XCTAssertEqual(decoded.bpm, sample.bpm)
        } catch {
            XCTFail("Codable test failed: \(error)")
        }
    }
}
