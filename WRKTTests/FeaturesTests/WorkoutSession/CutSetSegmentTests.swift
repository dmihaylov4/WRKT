import Foundation
import Testing
@testable import WRKT

/// The set segments on the Cut set screen are the control: tap an open set to make it active,
/// tap a logged set to be asked (Edit set, Delete set), and they wrap onto more rows instead of
/// shrinking.
@MainActor
struct CutSetSegmentTests {
    private func sets(done: Int, of total: Int) -> [SetInput] {
        (0..<total).map { index in
            SetInput(reps: 10, weight: 50 + Double(index) * 5, tag: .working, autoWeight: false, isCompleted: index < done)
        }
    }

    // MARK: Tap

    @Test func tappingAnOpenSetMakesItActive() {
        let list = sets(done: 1, of: 4)
        #expect(CutSetLoggingLogic.segmentTap(sets: list, index: 3, activeSetIndex: 1, holdRunning: false) == .activate)
        #expect(CutSetLoggingLogic.segmentTap(sets: list, index: 2, activeSetIndex: 1, holdRunning: false) == .activate)
    }

    @Test func tappingTheActiveSetDoesNothing() {
        let list = sets(done: 1, of: 4)
        #expect(CutSetLoggingLogic.segmentTap(sets: list, index: 1, activeSetIndex: 1, holdRunning: false) == .none)
    }

    @Test func tappingALoggedSetAsksFirst() {
        let list = sets(done: 2, of: 4)
        #expect(CutSetLoggingLogic.segmentTap(sets: list, index: 0, activeSetIndex: 2, holdRunning: false) == .askEditOrDelete)
        // Even when it is still the active index (every set logged, active stays on the last).
        let done = sets(done: 4, of: 4)
        #expect(CutSetLoggingLogic.segmentTap(sets: done, index: 3, activeSetIndex: 3, holdRunning: false) == .askEditOrDelete)
    }

    @Test func aRunningHoldLocksTheSegments() {
        let list = sets(done: 1, of: 3)
        #expect(CutSetLoggingLogic.segmentTap(sets: list, index: 2, activeSetIndex: 1, holdRunning: true) == .none)
        #expect(CutSetLoggingLogic.segmentTap(sets: list, index: 0, activeSetIndex: 1, holdRunning: true) == .none)
    }

    @Test func tappingOutsideTheSetsDoesNothing() {
        #expect(CutSetLoggingLogic.segmentTap(sets: sets(done: 0, of: 2), index: 5, activeSetIndex: 0, holdRunning: false) == .none)
        #expect(CutSetLoggingLogic.segmentTap(sets: [], index: 0, activeSetIndex: 0, holdRunning: false) == .none)
    }

    // MARK: Edit

    @Test func editReopensALoggedSetWithItsValuesAndMakesItActive() {
        var list = sets(done: 3, of: 4)
        list[1].rpe = 8
        let before = list[1]
        let active = CutSetEditing.reopen(&list, at: 1)
        #expect(active == 1)
        #expect(!list[1].isCompleted)
        #expect(list[1].weight == before.weight && list[1].reps == before.reps && list[1].rpe == 8 && list[1].tag == before.tag)
        // The other sets are untouched.
        #expect(list[0].isCompleted && list[2].isCompleted && !list[3].isCompleted)
    }

    @Test func editIgnoresOpenSetsAndBadIndexes() {
        var list = sets(done: 1, of: 3)
        #expect(CutSetEditing.reopen(&list, at: 2) == nil)
        #expect(CutSetEditing.reopen(&list, at: 9) == nil)
        #expect(list == sets(done: 1, of: 3))
    }

    @Test func loggingAReopenedSetMovesOnToTheFirstOpenSet() {
        // Sets 1 to 3 logged, set 2 reopened and logged again: set 4 is next, not the logged set 3.
        var list = sets(done: 3, of: 4)
        #expect(CutSetEditing.activeIndexAfterLogging(sets: list, loggedIndex: 1) == 3)
        // Normal logging still moves to the set after.
        list = sets(done: 2, of: 4)
        #expect(CutSetEditing.activeIndexAfterLogging(sets: list, loggedIndex: 1) == 2)
        // An open set earlier in the list is next when nothing after is open.
        list = sets(done: 4, of: 4)
        list[0].isCompleted = false
        #expect(CutSetEditing.activeIndexAfterLogging(sets: list, loggedIndex: 2) == 0)
        // Everything logged: as before, the set after, or the last one.
        list = sets(done: 4, of: 4)
        #expect(CutSetEditing.activeIndexAfterLogging(sets: list, loggedIndex: 1) == 2)
        #expect(CutSetEditing.activeIndexAfterLogging(sets: list, loggedIndex: 3) == 3)
    }

    // MARK: State and labels

    @Test func segmentStates() {
        let list = sets(done: 1, of: 3)
        #expect(CutSetLoggingLogic.segmentState(sets: list, index: 0, activeSetIndex: 1) == .logged)
        #expect(CutSetLoggingLogic.segmentState(sets: list, index: 1, activeSetIndex: 1) == .current)
        #expect(CutSetLoggingLogic.segmentState(sets: list, index: 2, activeSetIndex: 1) == .upcoming)
        // A logged set that is still the active index reads as logged.
        let done = sets(done: 3, of: 3)
        #expect(CutSetLoggingLogic.segmentState(sets: done, index: 2, activeSetIndex: 2) == .logged)
    }

    @Test func voiceOverSaysNumberStateAndValues() {
        var list = sets(done: 1, of: 3)
        list[0].rpe = 8.5
        list[2].tag = .backoff
        #expect(CutSetLoggingLogic.segmentAccessibilityLabel(list[0], index: 0, state: .logged, mode: .weighted, unit: .kg)
                == "Set 1, logged, 50 kilograms, 10 reps, RPE 8.5")
        #expect(CutSetLoggingLogic.segmentAccessibilityLabel(list[1], index: 1, state: .current, mode: .weighted, unit: .kg)
                == "Set 2, current, 55 kilograms, 10 reps")
        #expect(CutSetLoggingLogic.segmentAccessibilityLabel(list[2], index: 2, state: .upcoming, mode: .weighted, unit: .lb)
                == "Set 3, upcoming, back-off, 132.3 pounds, 10 reps")
        let bodyweight = SetInput(reps: 12, weight: 0, isCompleted: true, trackingMode: .bodyweight)
        #expect(CutSetLoggingLogic.segmentAccessibilityLabel(bodyweight, index: 0, state: .logged, mode: .bodyweight, unit: .kg)
                == "Set 1, logged, 12 reps")
        let timed = SetInput(reps: 0, weight: 0, durationSeconds: 45, trackingMode: .timed)
        #expect(CutSetLoggingLogic.segmentAccessibilityLabel(timed, index: 1, state: .upcoming, mode: .timed, unit: .kg)
                == "Set 2, upcoming, 45 seconds")
    }

    @Test func loggedSetMenuTitleCarriesWhatTheOldRowShowed() {
        var set = SetInput(reps: 8, weight: 80, tag: .warmup, isCompleted: true)
        set.rpe = 7
        #expect(CutSetLoggingLogic.segmentMenuTitle(set, index: 0, mode: .weighted, unit: .kg)
                == "Set 1, warm-up, 80\u{00A0}kg\u{00A0}x\u{00A0}8, RPE 7")
        let plain = SetInput(reps: 6, weight: 85, isCompleted: true)
        #expect(CutSetLoggingLogic.segmentMenuTitle(plain, index: 2, mode: .weighted, unit: .kg)
                == "Set 3, 85\u{00A0}kg\u{00A0}x\u{00A0}6")
    }

    // MARK: Grid

    @Test func fewSetsKeepFourColumnsWithAddSetInTheNextCell() {
        #expect(CutSetLoggingLogic.segmentRows(setCount: 1, columns: 4) == [[.set(0), .addSet, .empty, .empty]])
        #expect(CutSetLoggingLogic.segmentRows(setCount: 3, columns: 4) == [[.set(0), .set(1), .set(2), .addSet]])
    }

    @Test func manySetsWrapOntoMoreRows() {
        #expect(CutSetLoggingLogic.segmentRows(setCount: 4, columns: 4)
                == [[.set(0), .set(1), .set(2), .set(3)], [.addSet, .empty, .empty, .empty]])
        let eight = CutSetLoggingLogic.segmentRows(setCount: 8, columns: 4)
        #expect(eight.count == 3)
        #expect(eight.allSatisfy { $0.count == 4 })
        #expect(eight.flatMap { $0 }.filter { if case .set = $0 { true } else { false } }.count == 8)
        #expect(eight.last?.first == .addSet)
    }

    @Test func noSetsDrawNoSegments() {
        #expect(CutSetLoggingLogic.segmentRows(setCount: 0, columns: 4).isEmpty)
    }

    @Test func accessibilitySizesUseFewerColumns() {
        #expect(CutSetLoggingLogic.segmentColumns(isAccessibilitySize: false) == 4)
        #expect(CutSetLoggingLogic.segmentColumns(isAccessibilitySize: true) == 2)
    }

    /// Add set is the same cell whether or not a rest runs: the grid does not depend on it.
    @Test func addSetIsOneDesignInBothStates() {
        for count in 1...9 {
            let rows = CutSetLoggingLogic.segmentRows(setCount: count, columns: 4)
            #expect(rows.flatMap { $0 }.filter { $0 == .addSet }.count == 1)
        }
    }

    // MARK: RPE menu

    @Test func rpeMenuListsNoRPEThenTheLegacyValues() {
        #expect(CutSetEditing.rpeOptions == [nil, 6, 7, 8, 8.5, 9, 9.5, 10])
        #expect(CutSetEditing.rpeOptions.map(CutSetLoggingLogic.rpeOptionTitle)
                == ["No RPE", "6", "7", "8", "8.5", "9", "9.5", "10"])
    }

    @Test func choosingAnRPEStoresItAndNoRPEClearsIt() {
        var set = SetInput(reps: 6, weight: 85)
        CutSetEditing.setRPE(&set, 8.5)
        #expect(set.rpe == 8.5)
        // Choosing the checked value keeps it (a menu choice is not a toggle).
        CutSetEditing.setRPE(&set, 8.5)
        #expect(set.rpe == 8.5)
        CutSetEditing.setRPE(&set, nil)
        #expect(set.rpe == nil)
    }
}
