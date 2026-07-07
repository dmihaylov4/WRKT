// WRKTTests/FeaturesTests/RestTimerFanoutTests.swift
//
// Diagnostic tests for the rest timer invalidation fanout.
//
// RestTimerManager publishes remainingSeconds every second while a timer runs.
// Because ObservableObject invalidates ALL object-level observers on any
// @Published change, every view holding @ObservedObject RestTimerManager.shared
// (LiveWorkoutOverlayCard, TimedSetRow, BodyweightSetRow, LiveWorkoutGrabTab,
// RestTimerCompletionToast x2) re-runs its body once per second for the entire
// rest period, even though most of them only care about state transitions.
//
// EVIDENCE TEST: `perSecondTicksInvalidateAllObjectObservers` currently
// documents the defect (per-tick objectWillChange fanout). The fix will move
// per-second countdown delivery to a dedicated ticker object, at which point
// that test gets inverted into a regression guard (invalidations <= 1).

import Testing
import Combine
import Foundation
@testable import WRKT

// Serialized: both tests drive the RestTimerManager.shared singleton, so
// parallel execution would cancel each other's timers.
@Suite(.serialized)
@MainActor
struct RestTimerFanoutTests {

    /// Measures how often object-level observers are invalidated during a
    /// plain countdown with no state transitions. Today: once per second.
    /// Target after fix: zero (countdown moves to a dedicated ticker).
    @Test func perSecondTicksInvalidateAllObjectObservers() async throws {
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

        // Wait long enough for at least 3 timer ticks (1 Hz with 0.1 tolerance).
        try await Task.sleep(for: .seconds(3.5))

        let remainingObserved = manager.remainingSeconds
        manager.stopTimer()
        cancellables.removeAll()

        // Sanity: no state transitions happened during the window, so every
        // invalidation counted was caused purely by the per-second countdown.
        #expect(stateChanges <= 1, "state should only change on stopTimer, saw \(stateChanges) changes")
        #expect(remainingObserved > 0 && remainingObserved < 30,
                "remaining should have counted down from 30, was \(remainingObserved)")

        // DEFECT EVIDENCE (invert to `invalidations <= 1` once the ticker
        // split lands): every @ObservedObject view re-renders per second.
        #expect(invalidations >= 2,
                "measured \(invalidations) object-level invalidations in 3.5s of plain countdown")
    }

    /// Completion must transition state (this is what drives the toast,
    /// auto-set generation, and the Watch sync). Must keep passing after fix.
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
