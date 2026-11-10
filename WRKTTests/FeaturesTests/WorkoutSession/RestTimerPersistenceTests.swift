import XCTest
@testable import WRKT

@MainActor
final class RestTimerPersistenceTests: XCTestCase {
    func testPausedTimerSurvivesRelaunchWithoutCountingDown() throws {
        try withStorage { defaults, storage in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let manager = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false, now: { now })
            manager.startTimer(duration: 90, exerciseID: "plank", exerciseName: "Plank")
            now.addTimeInterval(15)
            manager.pauseTimer()
            let expected = RestTimerState.paused(remainingSeconds: 75, exerciseID: "plank",
                exerciseName: "Plank", originalDuration: 90, wasAdjusted: false)
            XCTAssertEqual(manager.state, expected, "Pause must calculate time from the end date, not a stale UI tick")

            now.addTimeInterval(3600)
            let restored = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false, now: { now })
            XCTAssertEqual(restored.state, expected)
            XCTAssertEqual(restored.ticker.remainingSeconds, 75)
            restored.resumeTimer()
            XCTAssertEqual(restored.state, .running(endDate: now.addingTimeInterval(75), exerciseID: "plank",
                exerciseName: "Plank", originalDuration: 90, wasAdjusted: false))
            restored.stopTimer()
        }
    }

    func testAdjustAndResumeDoNotChangeNextRestPreference() throws {
        try withStorage { defaults, storage in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let manager = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false, now: { now })
            manager.startTimer(duration: 90, exerciseID: "squat", exerciseName: "Squat")
            manager.adjustTime(by: 15)
            manager.pauseTimer()
            manager.resumeTimer()
            let restored = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false, now: { now })
            XCTAssertEqual(restored.ticker.remainingSeconds, 105)
            XCTAssertEqual(restored.getRestDuration(), 90)
            restored.stopTimer()
        }
    }

    func testStoppedTimerDoesNotReturnOnRelaunch() throws {
        try withStorage { defaults, storage in
            let manager = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false)
            manager.startTimer(duration: 90, exerciseID: "squat", exerciseName: "Squat")
            manager.stopTimer()
            let restored = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false)
            XCTAssertEqual(restored.state, .idle)
            XCTAssertEqual(restored.ticker.remainingSeconds, 0)
        }
    }

    func testLegacyRunningTimerMigratesOnceAndCannotOverrideStop() throws {
        try withStorage { defaults, storage in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            defaults.set(now.addingTimeInterval(60), forKey: "rest_timer_end_date")
            defaults.set("squat", forKey: "rest_timer_exercise_id")
            defaults.set("Squat", forKey: "rest_timer_exercise_name")
            defaults.set(90.0, forKey: "rest_timer_duration")
            let manager = RestTimerManager(defaults: defaults, storage: storage,
                observeSystemEvents: false, now: { now })
            XCTAssertEqual(manager.ticker.remainingSeconds, 60)
            XCTAssertFalse(manager.hasBeenAdjusted)
            XCTAssertNil(defaults.object(forKey: "rest_timer_end_date"))
            manager.stopTimer()
            XCTAssertEqual(try storage.load()?.state, .idle)

            // A delayed save from an older session must not undo the committed stop.
            var stale = RestTimerRecord()
            stale.revision = 2
            stale.state = .running(endDate: now.addingTimeInterval(90), exerciseID: "squat",
                exerciseName: "Squat", originalDuration: 90, wasAdjusted: false)
            XCTAssertThrowsError(try storage.save(stale))
            XCTAssertEqual(try storage.load()?.state, .idle)
        }
    }

    func testFailedPauseDoesNotPublishSuccessOrOverwriteCorruptStorage() throws {
        try withStorage { defaults, storage in
            let manager = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false)
            manager.startTimer(duration: 90, exerciseID: "squat", exerciseName: "Squat")
            let previousState = manager.state
            let corrupt = Data("{truncated".utf8)
            try corrupt.write(to: storage.fileURL)
            manager.pauseTimer()
            XCTAssertEqual(manager.state, previousState)
            XCTAssertNotNil(manager.persistenceError)
            XCTAssertEqual(try Data(contentsOf: storage.fileURL), corrupt)
        }
    }

    func testUnsupportedRecordIsPreservedAndDoesNotRestartTimer() throws {
        try withStorage { defaults, storage in
            try FileManager.default.createDirectory(at: storage.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var future = RestTimerRecord()
            future.schemaVersion = 99
            let data = try JSONEncoder().encode(future)
            try data.write(to: storage.fileURL)
            let manager = RestTimerManager(defaults: defaults, storage: storage, observeSystemEvents: false)
            manager.startTimer(duration: 90, exerciseID: "squat", exerciseName: "Squat")
            XCTAssertEqual(manager.state, .idle)
            XCTAssertNotNil(manager.persistenceError)
            XCTAssertEqual(try Data(contentsOf: storage.fileURL), data)
        }
    }

    private func withStorage(_ test: (UserDefaults, RestTimerStorage) throws -> Void) throws {
        let name = "RestTimerPersistenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try test(defaults, RestTimerStorage(fileURL: directory.appendingPathComponent("state.json")))
    }
}
