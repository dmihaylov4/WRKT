// WRKTTests/FeaturesTests/RestTimerFanoutTests.swift
//
// Regression tests for the rest timer invalidation fanout.
//
// RestTimerManager must only publish STATE TRANSITIONS through
// objectWillChange (start, pause, resume, adjust, complete, stop). The
// per-second countdown is delivered exclusively through
// RestTimerManager.shared.ticker so that only leaf countdown views
// re-render each second. Views holding @ObservedObject
// RestTimerManager.shared (LiveWorkoutOverlayCard, TimedSetRow,
// BodyweightSetRow, LiveWorkoutGrabTab) must NOT be invalidated by
// countdown ticks.

import Testing
import Combine
import Foundation
@testable import WRKT

// Serialized: all tests drive the RestTimerManager.shared singleton, so
// parallel execution would cancel each other's timers.
@Suite(.serialized)
@MainActor
struct RestTimerFanoutTests {

    /// Object-level observers must not be invalidated by the countdown.
    /// Before the ticker split this measured one invalidation per second.
    @Test func perSecondTicksDoNotInvalidateObjectObservers() async throws {
        let manager = RestTimerManager.shared
        manager.stopTimer()

        var cancellables = Set<AnyCancellable>()
        var invalidations = 0
        var stateChanges = 0

        manager.startTimer(duration: 30, exerciseID: "diag-ex", exerciseName: "Diagnostic")

        // Subscribe AFTER start so we only count tick-driven invalidations,
        // not the start transition itself.
        manager.objectWillChange
            .sink { _ in invalidations += 1 }
            .store(in: &cancellables)
        manager.$state
            .dropFirst()
            .sink { _ in stateChanges += 1 }
            .store(in: &cancellables)

        // Wait long enough for at least 3 timer ticks (1 Hz, 0.1 tolerance).
        try await Task.sleep(for: .seconds(3.5))

        // Capture BEFORE stopTimer: stopping publishes state and other
        // properties, which is legitimate objectWillChange traffic.
        let tickInvalidations = invalidations
        let tickStateChanges = stateChanges

        manager.stopTimer()
        cancellables.removeAll()

        #expect(tickStateChanges == 0,
                "no state transitions expected during a plain countdown, saw \(tickStateChanges)")
        #expect(tickInvalidations == 0,
                "object-level observers were invalidated \(tickInvalidations) times during a plain countdown; ticks must go through the ticker only")
    }

    /// The countdown itself must still be delivered at 1 Hz via the ticker
    /// so leaf countdown views keep updating every second.
    @Test func tickerPublishesCountdownEverySecond() async throws {
        let manager = RestTimerManager.shared
        manager.stopTimer()

        var cancellables = Set<AnyCancellable>()
        var ticks = 0

        manager.startTimer(duration: 30, exerciseID: "diag-ex", exerciseName: "Diagnostic")

        manager.ticker.$remainingSeconds
            .dropFirst()
            .sink { _ in ticks += 1 }
            .store(in: &cancellables)

        try await Task.sleep(for: .seconds(3.5))

        let observedRemaining = manager.ticker.remainingSeconds
        manager.stopTimer()
        cancellables.removeAll()

        #expect(ticks >= 2, "expected at least 2 countdown ticks in 3.5s, saw \(ticks)")
        #expect(observedRemaining > 0 && observedRemaining < 30,
                "remaining should have counted down from 30, was \(observedRemaining)")
    }

    /// Completion must transition state: this drives the completion toast,
    /// auto-set generation, and the Watch sync.
    @Test func completionStillTransitionsState() async throws {
        let manager = RestTimerManager.shared
        manager.stopTimer()

        manager.startTimer(duration: 1, exerciseID: "diag-ex", exerciseName: "Diagnostic")
        try await Task.sleep(for: .seconds(2.5))

        let completed: Bool
        if case .completed = manager.state { completed = true } else { completed = false }
        manager.dismissCompleted()
        manager.stopTimer()

        #expect(completed, "timer should transition to .completed after expiry, state was \(manager.state)")
    }
}
