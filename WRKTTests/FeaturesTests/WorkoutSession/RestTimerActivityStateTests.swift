import XCTest
@testable import WRKT

final class RestTimerActivityStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testExpiredAndExactlyFinishedTimersHaveNoCountdownInterval() {
        XCTAssertNil(state(endingAfter: -1).countdownInterval(at: now))
        XCTAssertNil(state(endingAfter: 0).countdownInterval(at: now))
    }

    func testRunningTimerUsesTheSameCapturedTimeForItsLowerBound() throws {
        let interval = try XCTUnwrap(state(endingAfter: 0.001).countdownInterval(at: now))
        XCTAssertEqual(interval.lowerBound, now)
        XCTAssertEqual(interval.upperBound, now.addingTimeInterval(0.001))
    }

    func testPausedTimerNeverUsesARunningCountdown() {
        var paused = state(endingAfter: 30)
        paused.isPaused = true
        XCTAssertNil(paused.countdownInterval(at: now))
    }

    private func state(endingAfter seconds: TimeInterval) -> RestTimerAttributes.ContentState {
        .init(
            remainingSeconds: max(0, Int(seconds)),
            endDate: now.addingTimeInterval(seconds),
            isPaused: false,
            progress: 0.5,
            wasAdjusted: false,
            lastUpdate: now
        )
    }
}
