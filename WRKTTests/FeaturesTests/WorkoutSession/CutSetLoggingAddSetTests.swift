import Foundation
import Testing
@testable import WRKT

/// Where "Add set" appears on the Cut set screen, and that it stays one tap away in every state.
@MainActor
struct CutSetLoggingAddSetTests {
    private func sets(done: Int, of total: Int) -> [SetInput] {
        (0..<total).map { index in
            SetInput(reps: 6, weight: 85, tag: .working, autoWeight: false, isCompleted: index < done)
        }
    }

    // MARK: Placement

    @Test(arguments: [false, true])
    func oneSetLeavesThreeFreeColumns(isResting: Bool) {
        #expect(CutSetLoggingLogic.addSetPlacement(setCount: 1, isResting: isResting) == .freeColumns(columns: 4, span: 3))
    }

    @Test(arguments: [false, true])
    func fourSetsFillTheRowSoAddSetGoesUnder(isResting: Bool) {
        #expect(CutSetLoggingLogic.addSetPlacement(setCount: 4, isResting: isResting) == .underRow(columns: 4))
    }

    @Test(arguments: [false, true])
    func fiveSetsWidenTheGridAndAddSetGoesUnder(isResting: Bool) {
        #expect(CutSetLoggingLogic.addSetPlacement(setCount: 5, isResting: isResting) == .underRow(columns: 5))
    }

    @Test func restingDoesNotMoveAddSet() {
        for count in 0...8 {
            #expect(CutSetLoggingLogic.addSetPlacement(setCount: count, isResting: true)
                    == CutSetLoggingLogic.addSetPlacement(setCount: count, isResting: false))
        }
    }

    @Test func noSetsDrawNoSegments() {
        #expect(CutSetLoggingLogic.addSetPlacement(setCount: 0, isResting: false) == .none)
    }

    // MARK: Bottom pill

    @Test func restingWithEverySetLoggedHidesTheDuplicatePill() {
        let done = sets(done: 4, of: 4)
        #expect(CutSetLoggingLogic.bar(sets: done, activeSetIndex: 3, restSeconds: 90, nextExerciseName: nil,
                                       holdRunning: false, isResting: true) == .hidden)
        // Not resting keeps the Add set pill as before.
        #expect(CutSetLoggingLogic.bar(sets: done, activeSetIndex: 3, restSeconds: 90, nextExerciseName: nil,
                                       holdRunning: false, isResting: false) == .addSet)
    }

    @Test func restingKeepsTheOtherPills() {
        let open = sets(done: 2, of: 4)
        #expect(CutSetLoggingLogic.bar(sets: open, activeSetIndex: 2, restSeconds: 90, nextExerciseName: nil,
                                       holdRunning: false, isResting: true) == .logSet(restLine: "Rest 1:30 starts after"))
        let done = sets(done: 4, of: 4)
        #expect(CutSetLoggingLogic.bar(sets: done, activeSetIndex: 3, restSeconds: 90, nextExerciseName: "Row",
                                       holdRunning: false, isResting: true) == .nextExercise(name: "Row"))
        #expect(CutSetLoggingLogic.bar(sets: [], activeSetIndex: 0, restSeconds: 90, nextExerciseName: nil,
                                       holdRunning: false, isResting: true) == .addSet)
    }

    /// Every state offers adding a set with one tap: in the segments, or on the pill when there
    /// are no segments.
    @Test func addSetIsAlwaysOneTapAway() {
        for count in [0, 1, 4, 5] {
            for done in Set([0, count / 2, count]) {
                for isResting in [false, true] {
                    for next in [nil, "Row"] as [String?] {
                        let list = sets(done: done, of: count)
                        let placement = CutSetLoggingLogic.addSetPlacement(setCount: count, isResting: isResting)
                        let bar = CutSetLoggingLogic.bar(sets: list, activeSetIndex: min(done, max(0, count - 1)),
                                                         restSeconds: 90, nextExerciseName: next,
                                                         holdRunning: false, isResting: isResting)
                        #expect(placement != .none || bar == .addSet,
                                "count \(count), done \(done), resting \(isResting), next \(next ?? "none")")
                    }
                }
            }
        }
    }
}
