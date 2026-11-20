import Foundation
import Testing
@testable import WRKT

struct CutStartSheetLogicTests {
    @Test func titleIsSentenceCase() {
        #expect(CutStartSheetLogic.title("Start Workout") == "Start a workout")
        #expect(CutStartSheetLogic.title("Add Exercise") == "Add exercise")
        #expect(CutStartSheetLogic.title("") == "Start a workout")
    }

    @Test func choicesKeepTheLegacyOrder() {
        let model = CutStartSheetLogic.model(legacyTitle: "Start Workout", plan: nil)
        #expect(model.choices == [.upperBody, .lowerBody, .custom])
        #expect(model.plan == nil)
        #expect(model.choices.map(CutStartSheetLogic.choiceTitle) == ["Upper body", "Lower body", "Custom"])
    }

    @Test func planLineCountsExercises() {
        #expect(CutStartSheetLogic.planLine(.init(name: "Upper Body", exerciseCount: 6)) == "Today's plan, 6 exercises")
        #expect(CutStartSheetLogic.planLine(.init(name: "Upper Body", exerciseCount: 1)) == "Today's plan, 1 exercise")
        #expect(CutStartSheetLogic.planLine(.init(name: "Upper Body", exerciseCount: 0)) == "Today's plan")
    }
}

struct CutSetLoggingLogicTests {
    @Test func setLineCountsOnlyWhileSetsFollow() {
        #expect(CutSetLoggingLogic.setLine(setIndex: 2, setCount: 4) == "Set 3 of 4")
        #expect(CutSetLoggingLogic.setLine(setIndex: 0, setCount: 3) == "Set 1 of 3")
        // The last set: nothing planned beyond it.
        #expect(CutSetLoggingLogic.setLine(setIndex: 1, setCount: 2) == "Set 2")
        #expect(CutSetLoggingLogic.setLine(setIndex: 9, setCount: 4) == "Set 4")
        #expect(CutSetLoggingLogic.setLine(setIndex: 0, setCount: 0) == "No sets yet")
        let open = [SetInput(reps: 5, weight: 80, isCompleted: true), SetInput(reps: 5, weight: 80)]
        #expect(CutSetLoggingLogic.entryLine(sets: open, activeSetIndex: 1) == "Set 2")
        let done = open.map { set -> SetInput in var copy = set; copy.isCompleted = true; return copy }
        #expect(CutSetLoggingLogic.entryLine(sets: done, activeSetIndex: 1) == "2 sets logged")
        #expect(CutSetLoggingLogic.entryLine(sets: [], activeSetIndex: 0) == "No sets yet")
        #expect(CutSetLoggingLogic.bar(sets: [], activeSetIndex: 0, restSeconds: 90, nextExerciseName: nil, holdRunning: false) == .addSet)
    }

    @Test func restingLineNamesTheFollowingSetOrTheCount() {
        let mid = [SetInput(reps: 8, weight: 80, isCompleted: true), SetInput(reps: 6, weight: 85, isCompleted: true),
                   SetInput(reps: 6, weight: 85), SetInput(reps: 6, weight: 85)]
        #expect(CutSetLoggingLogic.restingLine(exerciseName: "Bench Press", sets: mid, activeSetIndex: 2)
                == "Bench Press, set 3 of 4")
        let one = [SetInput(reps: 10, weight: 27.5, isCompleted: true)]
        #expect(CutSetLoggingLogic.restingLine(exerciseName: "Dumbbell Curl", sets: one, activeSetIndex: 0)
                == "Dumbbell Curl, 1 set logged")
        let three = (0..<3).map { _ in SetInput(reps: 10, weight: 27.5, isCompleted: true) }
        #expect(CutSetLoggingLogic.restingLine(exerciseName: "Dumbbell Curl", sets: three, activeSetIndex: 2)
                == "Dumbbell Curl, 3 sets logged")
        let lastOpen = [SetInput(reps: 10, weight: 27.5, isCompleted: true), SetInput(reps: 10, weight: 27.5)]
        #expect(CutSetLoggingLogic.restingLine(exerciseName: "Dumbbell Curl", sets: lastOpen, activeSetIndex: 1)
                == "Dumbbell Curl, set 2")
    }

    @Test func pillToneAndLine() {
        #expect(CutSetLoggingLogic.pillTone(isResting: false) == .filled)
        #expect(CutSetLoggingLogic.pillTone(isResting: true) == .outline)
        let log = CutSetLoggingBar.logSet(restLine: "Rest 2:00 starts after")
        #expect(CutSetLoggingLogic.pillLine(log, isResting: false) == "Rest 2:00 starts after")
        #expect(CutSetLoggingLogic.pillLine(log, isResting: true) == nil)
        #expect(CutSetLoggingLogic.pillLine(.logSet(restLine: nil), isResting: false) == nil)
        #expect(CutSetLoggingLogic.pillLine(.nextExercise(name: "Row"), isResting: true) == "Row")
        #expect(CutSetLoggingLogic.pillLine(.addSet, isResting: false) == nil)
        #expect(CutSetLoggingLogic.pillLine(.hidden, isResting: false) == nil)
    }

    @Test func nextSetSupportLeadsWithTheSetType() {
        #expect(CutSetLoggingLogic.nextSetSupport(tag: .working, supportLine: "Target 87.5 kg x 6, PR 100 kg")
                == "Working set. Target 87.5 kg x 6, PR 100 kg")
        #expect(CutSetLoggingLogic.nextSetSupport(tag: .warmup, supportLine: nil) == "Warm-up set.")
        #expect(CutSetLoggingLogic.nextSetSupport(tag: .backoff, supportLine: "") == "Back-off set.")
    }

    @Test func segmentLabelSaysNextWhileResting() {
        let open = SetInput(reps: 6, weight: 85)
        #expect(CutSetLoggingLogic.segmentLabel(open, index: 2, isActive: true, mode: .weighted, unit: .kg) == "Now")
        #expect(CutSetLoggingLogic.segmentLabel(open, index: 2, isActive: true, mode: .weighted, unit: .kg, isResting: true) == "Next")
        #expect(CutSetLoggingLogic.segmentLabel(open, index: 3, isActive: false, mode: .weighted, unit: .kg, isResting: true) == "Set 4")
        let done = SetInput(reps: 6, weight: 85, isCompleted: true)
        #expect(CutSetLoggingLogic.segmentLabel(done, index: 1, isActive: false, mode: .weighted, unit: .kg) == "85 x 6")
    }

    @Test func restLine() {
        #expect(CutSetLoggingLogic.restLine(seconds: 120) == "Rest 2:00 starts after")
        #expect(CutSetLoggingLogic.restLine(seconds: nil) == nil)
    }

    @Test func barLeadsOnAfterTheLastSet() {
        let open = [SetInput(reps: 5, weight: 80, isCompleted: true), SetInput(reps: 5, weight: 80)]
        let done = open.map { set -> SetInput in var copy = set; copy.isCompleted = true; return copy }
        #expect(CutSetLoggingLogic.bar(sets: open, activeSetIndex: 1, restSeconds: 90, nextExerciseName: nil, holdRunning: false)
                == .logSet(restLine: "Rest 1:30 starts after"))
        #expect(CutSetLoggingLogic.bar(sets: done, activeSetIndex: 1, restSeconds: 90, nextExerciseName: "Row", holdRunning: false)
                == .nextExercise(name: "Row"))
        // Done lives in the top bar, so with nothing else open the pill offers another set.
        #expect(CutSetLoggingLogic.bar(sets: done, activeSetIndex: 1, restSeconds: 90, nextExerciseName: nil, holdRunning: false) == .addSet)
        #expect(CutSetLoggingLogic.bar(sets: open, activeSetIndex: 1, restSeconds: 90, nextExerciseName: nil, holdRunning: true) == .hidden)
        #expect(CutSetLoggingLogic.bar(sets: open, activeSetIndex: 1, restSeconds: nil, nextExerciseName: nil, holdRunning: false)
                == .logSet(restLine: nil))
    }

    @Test func barHasNoLogButtonOnAGhostSet() {
        let sets = [SetInput(reps: 5, weight: 80, isCompleted: true), SetInput(reps: 5, weight: 80, isGhost: true)]
        #expect(CutSetLoggingLogic.bar(sets: sets, activeSetIndex: 1, restSeconds: 90, nextExerciseName: "Row", holdRunning: false) == .hidden)
    }

    @Test func entryLineCarriesTheRecord() {
        let one = [SetInput(reps: 20, weight: 30)]
        #expect(CutSetLoggingLogic.entryLine(sets: one, activeSetIndex: 0, pr: "PR 93\u{00A0}kg") == "Set 1, PR 93\u{00A0}kg")
        let four = (0..<4).map { SetInput(reps: 6, weight: 85, isCompleted: $0 < 2) }
        #expect(CutSetLoggingLogic.entryLine(sets: four, activeSetIndex: 2, pr: "PR 93 kg") == "Set 3 of 4, PR 93 kg")
        // No record: as before.
        #expect(CutSetLoggingLogic.entryLine(sets: four, activeSetIndex: 2, pr: nil) == "Set 3 of 4")
        #expect(CutSetLoggingLogic.entryLine(sets: four, activeSetIndex: 2, pr: "") == "Set 3 of 4")
    }

    @Test func supportSplitsTheRecordFromTheTarget() {
        let weighted = CutSetLoggingLogic.support(mode: .weighted, unit: .kg, progression: (87.5, 6), bestE1RMKg: 100,
                                                  prReps: nil, lastReps: nil)
        #expect(weighted.detail == "Target 87.5\u{00A0}kg\u{00A0}x\u{00A0}6")
        #expect(weighted.pr == "PR 100\u{00A0}kg")
        let recordOnly = CutSetLoggingLogic.support(mode: .weighted, unit: .kg, progression: nil, bestE1RMKg: 93,
                                                    prReps: nil, lastReps: nil)
        #expect(recordOnly == CutExerciseSupport(detail: nil, pr: "PR 93\u{00A0}kg"))
        let pounds = CutSetLoggingLogic.support(mode: .weighted, unit: .lb, progression: nil, bestE1RMKg: 100,
                                                prReps: nil, lastReps: nil)
        #expect(pounds.pr == "PR 220\u{00A0}lb")
        // Bodyweight keeps its record and last set on the grey line.
        let bodyweight = CutSetLoggingLogic.support(mode: .bodyweight, unit: .kg, progression: nil, bestE1RMKg: nil,
                                                    prReps: 15, lastReps: 12)
        #expect(bodyweight == CutExerciseSupport(detail: "Record 15 reps, last 12 reps", pr: nil))
        #expect(CutSetLoggingLogic.support(mode: .timed, unit: .kg, progression: nil, bestE1RMKg: 100,
                                           prReps: nil, lastReps: nil) == .none)
        // The resting state still reads both on one line.
        #expect(weighted.line == "Target 87.5\u{00A0}kg\u{00A0}x\u{00A0}6, PR 100\u{00A0}kg")
        #expect(CutExerciseSupport.none.line == nil)
    }

    @Test func restTipJoinsTheLineOverThePill() {
        let log = CutSetLoggingBar.logSet(restLine: "Rest 1:45 starts after")
        #expect(CutSetLoggingLogic.pillLine(log, isResting: false, tip: .pump)
                == "Rest 1:45 starts after. 1\u{00A0}min is enough for high\u{2011}rep sets.")
        #expect(CutSetLoggingLogic.pillLine(log, isResting: false, tip: .strength)
                == "Rest 1:45 starts after. Strength sets do better with 4\u{00A0}min.")
        #expect(CutSetLoggingLogic.pillLine(log, isResting: false, tip: nil) == "Rest 1:45 starts after")
        // Rest timer off: the tip alone.
        #expect(CutSetLoggingLogic.pillLine(.logSet(restLine: nil), isResting: false, tip: .pump) == "1 min rest for high-rep sets")
        // Elsewhere the tip stays an advice row.
        #expect(CutSetLoggingLogic.pillLine(log, isResting: true, tip: .pump) == nil)
        #expect(CutSetLoggingLogic.pillLine(.nextExercise(name: "Row"), isResting: false, tip: .pump) == "Row")
        #expect(CutSetLoggingLogic.tipJoinsPillLine(log, isResting: false))
        #expect(!CutSetLoggingLogic.tipJoinsPillLine(log, isResting: true))
        #expect(!CutSetLoggingLogic.tipJoinsPillLine(.addSet, isResting: false))
        #expect(!CutSetLoggingLogic.tipJoinsPillLine(.nextExercise(name: "Row"), isResting: false))
    }

    @Test func rpePill() {
        #expect(CutSetLoggingLogic.rpePillTitle(nil) == "RPE")
        #expect(CutSetLoggingLogic.rpePillTitle(8) == "RPE 8")
        #expect(CutSetLoggingLogic.rpePillTitle(8.5) == "RPE 8.5")
        #expect(CutSetLoggingLogic.rpeAccessibilityValue(nil) == "Not set")
        #expect(CutSetLoggingLogic.rpeAccessibilityValue(9.5) == "9.5")
        #expect(CutSetLoggingLogic.showsRPE(mode: .weighted, set: SetInput(reps: 6, weight: 85)))
        #expect(!CutSetLoggingLogic.showsRPE(mode: .weighted, set: SetInput(reps: 6, weight: 85, isCompleted: true)))
        #expect(!CutSetLoggingLogic.showsRPE(mode: .weighted, set: SetInput(reps: 6, weight: 85, tag: .warmup)))
        #expect(!CutSetLoggingLogic.showsRPE(mode: .bodyweight, set: SetInput(reps: 6, weight: 0)))
        #expect(!CutSetLoggingLogic.showsRPE(mode: .weighted, set: nil))
    }

    @Test func rpeValuesFitOneRowThenWrap() {
        // 342 pt inside the gutters: seven 44 pt cells.
        #expect(CutSetLoggingLogic.rpeColumns(count: 7, widestValue: 40, width: 342, spacing: 6) == 7)
        // Too wide for seven: two rows of four.
        #expect(CutSetLoggingLogic.rpeColumns(count: 7, widestValue: 60, width: 342, spacing: 6) == 4)
        #expect(CutSetLoggingLogic.rpeColumns(count: 7, widestValue: 100, width: 342, spacing: 6) == 3)
        #expect(CutSetLoggingLogic.rpeColumns(count: 7, widestValue: 1000, width: 342, spacing: 6) == 1)
        #expect(CutSetLoggingLogic.rpeColumns(count: 0, widestValue: 40, width: 342, spacing: 6) == 1)
    }

    @Test func supportLine() {
        #expect(CutSetLoggingLogic.supportLine(mode: .weighted, unit: .kg, progression: (87.5, 6), bestE1RMKg: 100,
                                               prReps: nil, lastReps: nil) == "Target 87.5\u{00A0}kg\u{00A0}x\u{00A0}6, PR 100\u{00A0}kg")
        #expect(CutSetLoggingLogic.supportLine(mode: .bodyweight, unit: .kg, progression: nil, bestE1RMKg: nil,
                                               prReps: 15, lastReps: 12) == "Record 15 reps, last 12 reps")
        #expect(CutSetLoggingLogic.supportLine(mode: .timed, unit: .kg, progression: nil, bestE1RMKg: nil,
                                               prReps: nil, lastReps: nil) == nil)
    }

    @Test func nextExerciseWrapsAndSkipsFinished() {
        let finished = WorkoutEntry(exerciseID: "a", exerciseName: "A", muscleGroups: [], sets: [SetInput(reps: 5, weight: 0, isCompleted: true)])
        let open = WorkoutEntry(exerciseID: "b", exerciseName: "B", muscleGroups: [], sets: [SetInput(reps: 5, weight: 0)])
        let current = WorkoutEntry(exerciseID: "c", exerciseName: "C", muscleGroups: [], sets: [SetInput(reps: 5, weight: 0)])
        #expect(CutSetLoggingLogic.nextExercise(in: [finished, open, current], after: current.id)?.id == open.id)
        #expect(CutSetLoggingLogic.nextExercise(in: [finished, current], after: current.id) == nil)
    }

    @Test func clockDropsSecondsFromAnHour() {
        #expect(CutSetLoggingLogic.clock(45) == "0:45")
        #expect(CutSetLoggingLogic.clock(3725) == "1:02")
    }
}

struct CutSetEditingTests {
    @Test func weightedStepsMirrorTheLegacyRow() {
        var set = SetInput(reps: 6, weight: 85, autoWeight: true, isAutoGeneratedPlaceholder: true)
        CutSetEditing.stepWeight(&set, by: 2.5, unit: .kg)
        #expect(set.weight == 87.5 && !set.autoWeight && !set.isAutoGeneratedPlaceholder)
        CutSetEditing.stepWeight(&set, by: -100, unit: .kg)
        #expect(set.weight == 0)
        CutSetEditing.decrementReps(&set, mode: .weighted)
        #expect(set.reps == 5)
        set.reps = 1
        CutSetEditing.decrementReps(&set, mode: .weighted)
        #expect(set.reps == 1)
        #expect(!CutSetEditing.canDecrementReps(set))
    }

    @Test func bodyweightRepsKeepAutoWeight() {
        var set = SetInput(reps: 10, weight: 0, autoWeight: true)
        CutSetEditing.incrementReps(&set, mode: .bodyweight)
        #expect(set.reps == 11 && set.autoWeight)
    }

    @Test func poundsConvertBackToKilograms() {
        var set = SetInput(reps: 5, weight: 0)
        CutSetEditing.setWeight(&set, displayValue: 220.462, unit: .lb)
        #expect(abs(set.weight - 100) < 0.001)
        #expect(CutSetEditing.weightStep(unit: .lb, weightStepKg: 2.5) == 5)
        #expect(CutSetEditing.weightStep(unit: .lb, weightStepKg: 1.0) == 2.5)
    }

    @Test func durationSteps() {
        var set = SetInput(reps: 0, weight: 0, durationSeconds: 10)
        #expect(!CutSetEditing.canStepDuration(set, by: -15))
        #expect(CutSetEditing.canStepDuration(set, by: -5))
        CutSetEditing.stepDuration(&set, by: 15)
        #expect(set.durationSeconds == 25)
    }

    @Test func rpeToggles() {
        var set = SetInput(reps: 5, weight: 80)
        CutSetEditing.toggleRPE(&set, 8)
        #expect(set.rpe == 8)
        CutSetEditing.toggleRPE(&set, 8)
        #expect(set.rpe == nil)
    }

    @Test func prepareSeedsLikeTheLegacyRows() {
        var weighted = SetInput(reps: 0, weight: 0, autoWeight: true)
        CutSetEditing.prepare(&weighted, mode: .weighted, defaultDurationSeconds: nil, lastWorkingSet: (8, 60),
                              suggestedWeightKg: { _ in 61.2 }, unit: .kg, weightStep: 2.5)
        #expect(weighted.reps == 8 && weighted.weight == 60 && weighted.didSeedFromMemory)

        var bodyweight = SetInput(reps: 0, weight: 0)
        CutSetEditing.prepare(&bodyweight, mode: .bodyweight, defaultDurationSeconds: nil, lastWorkingSet: nil,
                              suggestedWeightKg: { _ in nil }, unit: .kg, weightStep: 2.5)
        #expect(bodyweight.trackingMode == .bodyweight && bodyweight.reps == 10 && bodyweight.weight == 0)

        var timed = SetInput(reps: 0, weight: 0)
        CutSetEditing.prepare(&timed, mode: .timed, defaultDurationSeconds: 30, lastWorkingSet: nil,
                              suggestedWeightKg: { _ in nil }, unit: .kg, weightStep: 2.5)
        #expect(timed.trackingMode == .timed && timed.durationSeconds == 30)
    }

    @Test func activationRules() {
        let pending = SetInput(reps: 5, weight: 0)
        let done = SetInput(reps: 5, weight: 0, isCompleted: true)
        #expect(!CutSetEditing.canActivate(pending, isActive: true, mode: .weighted))
        #expect(CutSetEditing.canActivate(pending, isActive: true, mode: .bodyweight))
        #expect(!CutSetEditing.canActivate(done, isActive: false, mode: .timed))
    }

    @Test func restZoneAdvice() {
        #expect(CutSetEditing.restZone(reps: 3, currentRestSeconds: 90, tag: .working, isGhost: false, isActive: true,
                                       strengthDismissCount: 0, pumpDismissCount: 0) == .strength)
        #expect(CutSetEditing.restZone(reps: 15, currentRestSeconds: 180, tag: .working, isGhost: false, isActive: true,
                                       strengthDismissCount: 0, pumpDismissCount: 3) == nil)
        #expect(CutSetEditing.restZone(reps: 8, currentRestSeconds: 90, tag: .working, isGhost: false, isActive: true,
                                       strengthDismissCount: 0, pumpDismissCount: 0) == nil)
    }
}

struct CutWinLogicTests {
    @Test func workoutWinShowsDoneXPRecordAndStats() {
        let model = CutWinFixtures.withRecordAndPlate
        #expect(model.hero == "Done.")
        #expect(model.xp == "+240\u{00A0}XP")
        #expect(model.levelLine == "Level 14, 420 to go")
        #expect(model.recordLine == "New record")
        #expect(model.stats.map(\.label) == ["Duration", "kg volume", "Sets"])
        #expect(model.stats.first?.value == "52:08")
        #expect(model.stats.last?.value == "18")
        #expect(model.rows.first?.kind == .plate)
        #expect(model.rows.first?.value == "20\u{00A0}kg, Bumper")
        #expect(model.showsShare)
        #expect(model.xpItems.map(\.title) == ["Strength Day", "Pr"])
    }

    @Test func plainWinHasNoRecordOrPlate() {
        let model = CutWinFixtures.plain
        #expect(model.recordLine == nil)
        #expect(!model.rows.contains { $0.kind == .plate })
    }

    @Test func rewardOnlyWinHasNoStatsOrShare() {
        let model = CutWinLogic.model(summary: .voliaSkinUnlocked(), workout: nil, unit: .kg)
        #expect(model.hero == "New reward.")
        #expect(model.stats.isEmpty && !model.showsShare && model.xp == nil)
        #expect(model.rows.map(\.kind) == [.skin])
    }

    @Test func recordLineAndDuration() {
        #expect(CutWinLogic.recordLine(prCount: 0) == nil)
        #expect(CutWinLogic.recordLine(prCount: 3) == "3 new records")
        #expect(CutWinLogic.duration(3725) == "1:02")
    }
}

struct CutRestLogicTests {
    @Test func nextIndexFindsTheNextOpenSet() {
        let sets = [SetInput(reps: 8, weight: 80, isCompleted: true), SetInput(reps: 6, weight: 85), SetInput(reps: 6, weight: 85)]
        #expect(CutRestLogic.nextIndex(sets: sets, activeSetIndex: 1) == 1)
        #expect(CutRestLogic.nextIndex(sets: sets, activeSetIndex: 0) == 1)
        // Wraps to an open set before the active one.
        let wrap = [SetInput(reps: 6, weight: 85), SetInput(reps: 6, weight: 85, isCompleted: true)]
        #expect(CutRestLogic.nextIndex(sets: wrap, activeSetIndex: 1) == 0)
        let done = [SetInput(reps: 8, weight: 80, isCompleted: true)]
        #expect(CutRestLogic.nextIndex(sets: done, activeSetIndex: 0) == nil)
        #expect(CutRestLogic.lastLoggedIndex(sets: sets) == 0)
        #expect(CutRestLogic.lastLoggedIndex(sets: [SetInput(reps: 6, weight: 85)]) == nil)
    }

    @Test func valueIsOneLine() {
        #expect(CutRestLogic.value(SetInput(reps: 6, weight: 85), mode: .weighted, unit: .kg) == "85\u{00A0}kg\u{00A0}x\u{00A0}6")
        #expect(CutRestLogic.value(SetInput(reps: 6, weight: 0), mode: .weighted, unit: .kg) == "6\u{00A0}reps")
        #expect(CutRestLogic.value(SetInput(reps: 12, weight: 0), mode: .bodyweight, unit: .kg) == "12\u{00A0}reps")
        #expect(CutRestLogic.value(SetInput(reps: 0, weight: 0, durationSeconds: 45), mode: .timed, unit: .kg) == "0:45")
    }

    @Test func remainingFractionIsClamped() {
        #expect(CutRestLogic.remainingFraction(seconds: 60, total: 120) == 0.5)
        #expect(CutRestLogic.remainingFraction(seconds: 200, total: 120) == 1)
        #expect(CutRestLogic.remainingFraction(seconds: -5, total: 120) == 0)
        #expect(CutRestLogic.remainingFraction(seconds: 60, total: 0) == 0)
    }
}

struct CutLiveOverviewLogicTests {
    private func entry(_ name: String, done: Int, of count: Int, superset: UUID? = nil, order: Int? = nil) -> WorkoutEntry {
        var entry = WorkoutEntry(exerciseID: name, exerciseName: name, muscleGroups: [],
                                 sets: (0..<count).map { SetInput(reps: 6, weight: 85, isCompleted: $0 < done) })
        entry.supersetGroupID = superset
        entry.orderInSuperset = order
        return entry
    }

    @Test func heroFollowsTheLegacyRules() {
        let finished = entry("A", done: 2, of: 2)
        let started = entry("B", done: 1, of: 3)
        let fresh = entry("C", done: 0, of: 3)
        #expect(CutLiveOverviewLogic.heroEntry(entries: [finished, fresh, started], activeEntryID: nil)?.id == started.id)
        #expect(CutLiveOverviewLogic.heroEntry(entries: [finished, fresh, started], activeEntryID: fresh.id)?.id == fresh.id)
        #expect(CutLiveOverviewLogic.heroEntry(entries: [finished, fresh], activeEntryID: finished.id)?.id == fresh.id)
        #expect(CutLiveOverviewLogic.heroEntry(entries: [finished], activeEntryID: nil) == nil)
    }

    @Test func modelSegmentsSectionsAndFinish() {
        let finished = entry("A", done: 2, of: 2)
        let started = entry("B", done: 1, of: 3)
        let fresh = entry("C", done: 0, of: 3)
        let model = CutLiveOverviewLogic.model(title: "Live workout", startDate: .now, entries: [finished, started, fresh],
                                               activeEntryID: nil, unit: .kg)
        #expect(model.segments == [.done, .current, .toDo])
        #expect(model.now?.id == started.id)
        #expect(model.now?.line == "Set 2 of 3")
        #expect(model.sections.map(\.title) == ["Up next", "Completed"])
        #expect(!model.canFinish)
        // Grouping follows the device locale.
        #expect(model.summaryLine == "3 sets, \(CutLiveOverviewLogic.grouped(1530))\u{00A0}kg so far")

        let done = CutLiveOverviewLogic.model(title: "Live workout", startDate: .now, entries: [finished],
                                              activeEntryID: nil, unit: .kg)
        #expect(done.canFinish && done.allDone && done.now == nil)
    }

    /// Adding an exercise is offered once, at the end of Up next, even when nothing is up next
    /// (the Train hero's resting state no longer carries it).
    @Test func addExerciseEndsUpNextInEveryState() {
        let finished = entry("A", done: 2, of: 2)
        let started = entry("B", done: 1, of: 3)
        let fresh = entry("C", done: 0, of: 3)
        for entries in [[finished, started, fresh], [finished, started], [finished], [fresh]] {
            let model = CutLiveOverviewLogic.model(title: "Live workout", startDate: .now, entries: entries,
                                                   activeEntryID: nil, unit: .kg)
            let carriers = model.sections.filter(\.endsWithAddExercise)
            #expect(carriers.map(\.title) == ["Up next"], "\(entries.map(\.exerciseName))")
            // Before Completed, after In progress.
            let titles = model.sections.map(\.title)
            if let completed = titles.firstIndex(of: "Completed") {
                #expect(titles.firstIndex(of: "Up next")! < completed)
            }
        }
    }

    @Test func supersetPartnersStayWithTheHero() {
        let group = UUID()
        let first = entry("A", done: 1, of: 3, superset: group, order: 0)
        let second = entry("B", done: 0, of: 3, superset: group, order: 1)
        let other = entry("C", done: 0, of: 3)
        let model = CutLiveOverviewLogic.model(title: "Live workout", startDate: .now, entries: [first, second, other],
                                               activeEntryID: nil, unit: .kg)
        #expect(model.now?.id == first.id)
        #expect(model.nowPartners.map(\.id) == [second.id])
        #expect(model.sections.flatMap(\.rows).map(\.id) == [other.id])
        #expect(model.nowPartners.first?.line.hasPrefix("Superset") == true)
    }

    @Test func rowLines() {
        #expect(CutLiveOverviewLogic.row(entry("A", done: 0, of: 3), unit: .kg).line == "3 sets, 85\u{00A0}kg\u{00A0}x\u{00A0}6")
        #expect(CutLiveOverviewLogic.row(entry("A", done: 1, of: 3), unit: .kg).line == "1 of 3 sets done")
        #expect(CutLiveOverviewLogic.summaryLine(entries: [entry("A", done: 0, of: 3)], unit: .kg) == "No sets logged yet")
    }
}
