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

    @Test func oneSetPutsAddSetInTheNextCell() {
        #expect(CutSetLoggingLogic.segmentRows(setCount: 1, columns: 4) == [[.set(0), .addSet, .empty, .empty]])
    }

    @Test func fourSetsFillTheRowSoAddSetStartsTheNext() {
        #expect(CutSetLoggingLogic.segmentRows(setCount: 4, columns: 4).last == [.addSet, .empty, .empty, .empty])
    }

    @Test func noSetsDrawNoSegments() {
        #expect(CutSetLoggingLogic.segmentRows(setCount: 0, columns: 4).isEmpty)
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
                        let rows = CutSetLoggingLogic.segmentRows(setCount: count, columns: 4)
                        let bar = CutSetLoggingLogic.bar(sets: list, activeSetIndex: min(done, max(0, count - 1)),
                                                         restSeconds: 90, nextExerciseName: next,
                                                         holdRunning: false, isResting: isResting)
                        #expect(rows.flatMap { $0 }.contains(.addSet) || bar == .addSet,
                                "count \(count), done \(done), resting \(isResting), next \(next ?? "none")")
                    }
                }
            }
        }
    }
}
