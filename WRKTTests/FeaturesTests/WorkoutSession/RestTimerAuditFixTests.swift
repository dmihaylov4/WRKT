//
//  RestTimerAuditFixTests.swift
//  WRKTTests
//
//  Covers audited rest timer bugs that the Live Activity buttons expose:
//  intent storage waits, repeats, adjustments past zero, error routing and
//  the completed state coming back on every foreground.
//

import XCTest
@testable import WRKT

@MainActor
final class RestTimerAuditFixTests: XCTestCase {
    private var suiteName: String!
    private var directory: URL!
    private var defaults: UserDefaults!
    private var storage: RestTimerStorage!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        suiteName = "RestTimerAuditFixTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        storage = RestTimerStorage(fileURL: directory.appendingPathComponent("state.json"))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeManager() -> RestTimerManager {
        RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false, now: { [unowned self] in self.now })
    }

    private func timerID() throws -> UUID {
        try XCTUnwrap(storage.load()).id
    }

    /// A workout store whose history cannot load, so waitForStorage throws.
    private func unloadableStore() throws -> WorkoutStoreV2 {
        let storeDirectory = directory.appendingPathComponent("workouts")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try Data().write(to: storeDirectory.appendingPathComponent(".migrated"))
        try Data("{truncated".utf8).write(to: storeDirectory.appendingPathComponent("current_workout_v2.json"))
        return WorkoutStoreV2(storage: WorkoutStorage(directory: storeDirectory), defaults: defaults)
    }

    private func loadedStore() async throws -> WorkoutStoreV2 {
        let storeDirectory = directory.appendingPathComponent("loaded")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try Data().write(to: storeDirectory.appendingPathComponent(".migrated"))
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: storeDirectory), defaults: defaults)
        try await store.waitForStorage()
        return store
    }

    // MARK: B2

    func testTimerActionsDoNotWaitForWorkoutHistory() async throws {
        let store = try unloadableStore()
        let manager = makeManager()
        manager.startTimer(duration: 60, exerciseID: "squat", exerciseName: "Squat")
        let id = try timerID()

        try await manager.perform(.adjust(15), timerID: id, operationID: UUID(), using: store)
        XCTAssertEqual(manager.state, .running(endDate: now.addingTimeInterval(75), exerciseID: "squat",
            exerciseName: "Squat", originalDuration: 75, wasAdjusted: true))
        try await manager.perform(.pause, timerID: id, operationID: UUID(), using: store)
        try await manager.perform(.stop, timerID: id, operationID: UUID(), using: store)
        XCTAssertEqual(manager.state, .idle)
    }

    func testRepeatedSkipOrStopOnAFinishedTimerSucceeds() async throws {
        let store = try await loadedStore()
        let manager = makeManager()
        manager.startTimer(duration: 60, exerciseID: "squat", exerciseName: "Squat")
        let id = try timerID()

        try await manager.perform(.skip, timerID: id, operationID: UUID(), using: store)
        try await manager.perform(.skip, timerID: id, operationID: UUID(), using: store)
        try await manager.perform(.stop, timerID: id, operationID: UUID(), using: store)
        try await manager.perform(.stop, timerID: id, operationID: UUID(), using: store)
        try await manager.perform(.skip, timerID: id, operationID: UUID(), using: store)
        XCTAssertNil(manager.persistenceError)
    }

    // MARK: B3

    func testAddingTimeAfterTheEndDateCountsFromNow() throws {
        let manager = makeManager()
        manager.startTimer(duration: 30, exerciseID: "row", exerciseName: "Row")
        now.addTimeInterval(40)

        manager.adjustTime(by: 15)

        guard case .running(let end, _, _, _, _) = manager.state else {
            return XCTFail("Expected a running timer, got \(manager.state)")
        }
        XCTAssertEqual(end, now.addingTimeInterval(15))
    }

    func testSubtractingMoreThanWhatIsLeftCompletesTheTimer() throws {
        let manager = makeManager()
        manager.startTimer(duration: 30, exerciseID: "row", exerciseName: "Row")
        now.addTimeInterval(20)

        manager.adjustTime(by: -15)

        XCTAssertEqual(manager.state, .completed(exerciseID: "row", exerciseName: "Row"))
    }

    func testAddingTimeToACompletedRestRestartsIt() throws {
        let manager = makeManager()
        manager.startTimer(duration: 30, exerciseID: "row", exerciseName: "Row")
        manager.skipTimer()

        manager.adjustTime(by: 15)

        XCTAssertEqual(manager.state, .running(endDate: now.addingTimeInterval(15), exerciseID: "row",
            exerciseName: "Row", originalDuration: 15, wasAdjusted: true))
    }

    // MARK: B4

    func testFailedIntentDoesNotRaiseTheInAppAlert() async throws {
        let store = try await loadedStore()
        let manager = makeManager()
        manager.startTimer(duration: 60, exerciseID: "squat", exerciseName: "Squat")

        do {
            try await manager.perform(.pause, timerID: UUID(), operationID: UUID(), using: store)
            XCTFail("A stale timer ID must fail")
        } catch { }

        XCTAssertNil(manager.persistenceError, "Intent errors belong on the activity, not in an app alert")
    }

    // MARK: B5

    func testCompletedRestIsNotShownAgainOnALaterForeground() throws {
        let manager = makeManager()
        manager.startTimer(duration: 90, exerciseID: "plank", exerciseName: "Plank")
        now.addTimeInterval(91)

        // The app comes back after the rest ended in the background.
        let returned = makeManager()
        XCTAssertEqual(returned.state, .completed(exerciseID: "plank", exerciseName: "Plank"))

        // Next foreground a minute later: the finished rest stays dismissed.
        now.addTimeInterval(60)
        let later = makeManager()
        XCTAssertEqual(later.state, .idle)
        XCTAssertEqual(try storage.load()?.state, .completed(exerciseID: "plank", exerciseName: "Plank"),
            "The record stays completed so Log Next Set still works")
    }
}
