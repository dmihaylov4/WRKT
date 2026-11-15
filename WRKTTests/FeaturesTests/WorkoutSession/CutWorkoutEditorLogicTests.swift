import Foundation
import Testing
@testable import WRKT

@Suite struct CutWorkoutEditorLogicTests {
    private typealias F = CutWorkoutDetailFixtures

    private func editor(_ workout: CompletedWorkout = F.full, name: String? = nil, entries: [WorkoutEntry]? = nil,
                        unit: WeightUnit = .kg) -> CutWorkoutEditorModel {
        CutWorkoutEditorLogic.editor(workout, name: name ?? workout.workoutName ?? "", entries: entries ?? workout.entries,
                                     unit: unit, now: F.now, calendar: F.calendar, locale: F.locale)
    }

    private static var exercise: Exercise {
        Exercise(id: "bench", name: "Bench Press", force: nil, level: nil, mechanic: nil, equipment: nil,
                 secondaryEquipment: nil, grip: nil, primaryMuscles: ["Chest"], secondaryMuscles: [],
                 tertiaryMuscles: [], instructions: [], images: nil, category: "strength")
    }

    // MARK: Rows

    @Test func previewShowsThreeSetsThenCount() {
        #expect(CutWorkoutEditorLogic.preview(F.squat.sets, unit: .kg) == "8×60kg, 5×80kg, 5×90kg, +1")
        #expect(CutWorkoutEditorLogic.preview(Array(F.squat.sets.prefix(2)), unit: .kg) == "8×60kg, 5×80kg")
        #expect(CutWorkoutEditorLogic.preview([], unit: .kg) == "No sets")
    }

    @Test func previewFollowsUnitAndTrackingMode() {
        #expect(CutWorkoutEditorLogic.preview([F.set(5, 100)], unit: .lb) == "5×220.5lb")
        #expect(CutWorkoutEditorLogic.preview(F.pullUps.sets, unit: .kg) == "12 reps, 10 reps")
        #expect(CutWorkoutEditorLogic.preview([F.set(10, 0)], unit: .kg) == "10 reps")
        #expect(CutWorkoutEditorLogic.preview(F.plank.sets, unit: .kg) == "1:30")
    }

    @Test func rowsKeepEntryOrderAndIDs() {
        let workout = F.full
        let rows = editor(workout).rows
        #expect(rows.map(\.name) == ["Back Squat", "Pull-Up"])
        #expect(rows.map(\.id) == workout.entries.map(\.id))
    }

    // MARK: Edit

    @Test func editorHeaderValues() {
        let model = editor()
        #expect(model.dateLine == "Friday 13 Nov, 18:42")
        #expect(model.isSyncedWithWatch)
        #expect(!editor(F.bare).isSyncedWithWatch)
    }

    @Test func editorDateInAnotherYearShowsYear() {
        var old = F.bare
        old.date = F.end.addingTimeInterval(-400 * 86_400)
        #expect(editor(old).dateLine.contains("2025"))
    }

    @Test func saveOffUntilSomethingChanges() {
        #expect(!editor().canSave)
        #expect(editor(name: "Leg Day").canSave)
        #expect(!editor(name: "  Lower Body ").canSave)
        #expect(editor(entries: [F.squat]).canSave)
        var changed = F.full.entries
        changed[0].sets[0].reps = 9
        #expect(editor(entries: changed).canSave)
    }

    @Test func clearingANameIsAChange() {
        #expect(editor(name: "").canSave)
        // An unnamed workout left unnamed is not.
        #expect(!editor(F.bare, name: "   ").canSave)
    }

    @Test func newHealthWorkoutNeedsAChangeToSave() {
        let fresh = CutWorkoutDetailLogic.workout(from: F.strengthRun())
        #expect(!editor(fresh).canSave)
        #expect(editor(fresh, entries: [F.squat]).canSave)
    }

    @Test func editedKeepsEverythingElse() {
        let original = F.full
        let pullUps = F.pullUps
        let edited = CutWorkoutEditorLogic.edited(original, name: "  Leg Day ", entries: [pullUps])
        #expect(edited.id == original.id)
        #expect(edited.date == original.date)
        #expect(edited.matchedHealthKitUUID == original.matchedHealthKitUUID)
        #expect(edited.matchedHealthKitHeartRateSamples == original.matchedHealthKitHeartRateSamples)
        #expect(edited.workoutName == "Leg Day")
        #expect(edited.entries == [pullUps])
        #expect(CutWorkoutEditorLogic.edited(original, name: " ", entries: []).workoutName == nil)
    }

    @Test func newEntryStartsWithThreeDoneSetsOfTen() {
        let entry = CutWorkoutEditorLogic.newEntry(Self.exercise, suggestedWeightKg: 82.5)
        #expect(entry.exerciseID == "bench")
        #expect(entry.exerciseName == "Bench Press")
        #expect(entry.muscleGroups == ["Chest"])
        #expect(entry.sets.count == 3)
        #expect(entry.sets.allSatisfy { $0.reps == 10 && $0.weight == 82.5 && $0.isCompleted && $0.tag == .working })
        #expect(CutWorkoutEditorLogic.newEntry(Self.exercise, suggestedWeightKg: nil).sets.allSatisfy { $0.weight == 0 })
    }

    // MARK: Log

    @Test func defaultTimesAreAnHourEndingAtEight() {
        let times = CutWorkoutEditorLogic.defaultTimes(for: F.now, calendar: F.calendar)
        #expect(F.calendar.component(.hour, from: times.end) == 20)
        #expect(F.calendar.component(.minute, from: times.end) == 0)
        #expect(times.end.timeIntervalSince(times.start) == 3600)
        #expect(F.calendar.isDate(times.end, inSameDayAs: F.now))
    }

    private func log(entries: [WorkoutEntry] = [F.squat], start: Date = F.end.addingTimeInterval(-3000),
                     end: Date = F.end) -> CutWorkoutLogModel {
        CutWorkoutEditorLogic.log(date: F.now, start: start, end: end, entries: entries, unit: .kg,
                                  now: F.now, calendar: F.calendar, locale: F.locale)
    }

    @Test func logTitleIsTheDay() {
        #expect(log().dayTitle == "Fri 13 Nov")
        let lastYear = CutWorkoutEditorLogic.log(date: F.now.addingTimeInterval(-400 * 86_400), start: F.now, end: F.end,
                                                 entries: [], unit: .kg, now: F.now, calendar: F.calendar, locale: F.locale)
        #expect(lastYear.dayTitle == "9 Oct 2025")
    }

    @Test func logSaveNeedsExercisesAndAFinishAfterTheStart() {
        #expect(log().canSave)
        #expect(log().timeIssue == nil)
        #expect(!log(entries: []).canSave)
        #expect(log(entries: []).timeIssue == nil)
        let backwards = log(start: F.end, end: F.end)
        #expect(!backwards.canSave)
        #expect(backwards.timeIssue == "Finish after the start to save.")
        #expect(!log(start: F.end.addingTimeInterval(60)).canSave)
    }

    @Test func loggedWorkoutMarksSetsDoneAndUsesTimes() {
        var entry = F.squat
        entry.sets[1].isCompleted = false
        let id = UUID()
        let start = F.end.addingTimeInterval(-3000)
        let workout = CutWorkoutEditorLogic.logged(id: id, name: " Legs ", entries: [entry], start: start, end: F.end)
        #expect(workout.id == id)
        #expect(workout.date == F.end)
        #expect(workout.startedAt == start)
        #expect(workout.workoutName == "Legs")
        #expect(workout.plannedWorkoutID == nil)
        #expect(workout.entries[0].sets.allSatisfy { $0.isCompleted })
        #expect(workout.entries[0].sets.map(\.reps) == entry.sets.map(\.reps))
        #expect(CutWorkoutEditorLogic.logged(name: "", entries: [], start: start, end: F.end).workoutName == nil)
    }
}

@Suite struct CutSetEditorLogicTests {
    private typealias F = CutWorkoutDetailFixtures

    private func apply(_ edits: [CutSetEditorEdit], to entry: WorkoutEntry = F.squat, unit: WeightUnit = .kg) -> WorkoutEntry {
        edits.reduce(entry) { CutSetEditorLogic.apply($1, to: $0, unit: unit, locale: F.locale) }
    }

    @Test func modelRowsInTheUsersUnit() {
        let model = CutSetEditorLogic.model(F.squat, unit: .kg)
        #expect(model.exerciseName == "Back Squat")
        #expect(model.countLine == "4 sets")
        #expect(model.unitLabel == "kg")
        #expect(model.rows.map(\.weight) == ["60", "80", "90", "100"])
        #expect(model.rows.map(\.reps) == ["8", "5", "5", "5"])
        #expect(model.rows.map(\.number) == ["1", "2", "3", "4"])
        let pounds = CutSetEditorLogic.model(F.squat, unit: .lb)
        #expect(pounds.unitLabel == "lb")
        #expect(pounds.rows[0].weight == "132.3")
    }

    @Test func weightTextDropsTrailingZero() {
        #expect(CutSetEditorLogic.weightText(62.5, unit: .kg) == "62.5")
        #expect(CutSetEditorLogic.weightText(60, unit: .kg) == "60")
        #expect(CutSetEditorLogic.weightText(0, unit: .kg) == "0")
    }

    @Test func weightStepsByUnitAndStopsAtZero() {
        #expect(apply([.weightUp(0)]).sets[0].weight == 62.5)
        #expect(apply([.weightDown(0)]).sets[0].weight == 57.5)
        let pounds = apply([.weightUp(0)], unit: .lb).sets[0].weight
        #expect(abs(pounds * 2.20462 - (60 * 2.20462 + 5)) < 0.0001)
        let light = WorkoutEntry(exerciseID: "x", exerciseName: "X", muscleGroups: [], sets: [F.set(5, 1)])
        #expect(apply([.weightDown(0)], to: light).sets[0].weight == 0)
        #expect(!CutSetEditorLogic.canDecreaseWeight(0, unit: .kg))
        #expect(CutSetEditorLogic.canDecreaseWeight(0.5, unit: .lb))
    }

    @Test func repsStopAtOne() {
        #expect(apply([.repsUp(1)]).sets[1].reps == 6)
        #expect(apply([.repsDown(1)]).sets[1].reps == 4)
        let one = WorkoutEntry(exerciseID: "x", exerciseName: "X", muscleGroups: [], sets: [F.set(1, 20)])
        #expect(apply([.repsDown(0)], to: one).sets[0].reps == 1)
        #expect(!CutSetEditorLogic.model(one, unit: .kg).rows[0].canDecreaseReps)
    }

    @Test func typedValuesInTheUsersUnit() {
        #expect(apply([.typedWeight(0, "72.5")]).sets[0].weight == 72.5)
        #expect(apply([.typedWeight(0, "72,5")]).sets[0].weight == 72.5)
        let pounds = apply([.typedWeight(0, "225")], unit: .lb).sets[0].weight
        #expect(abs(pounds - 225 / 2.20462) < 0.0001)
        #expect(apply([.typedReps(2, "12")]).sets[2].reps == 12)
    }

    @Test func invalidTypingKeepsTheValue() {
        #expect(apply([.typedWeight(0, "")]).sets[0].weight == 60)
        #expect(apply([.typedWeight(0, "abc")]).sets[0].weight == 60)
        #expect(apply([.typedWeight(0, "-5")]).sets[0].weight == 60)
        #expect(apply([.typedReps(0, "7.5")]).sets[0].reps == 8)
        #expect(apply([.typedReps(0, "")]).sets[0].reps == 8)
    }

    @Test func addCopiesTheLastSetOrStartsAtTen() {
        let added = apply([.add])
        #expect(added.sets.count == 5)
        #expect(added.sets[4].reps == 5)
        #expect(added.sets[4].weight == 100)
        #expect(added.sets[4].isCompleted)
        let empty = WorkoutEntry(exerciseID: "x", exerciseName: "X", muscleGroups: [], sets: [])
        let first = apply([.add], to: empty).sets
        #expect(first.count == 1)
        #expect(first[0].reps == 10 && first[0].weight == 0 && first[0].isCompleted)
    }

    @Test func deleteRemovesOneSetAndIgnoresBadIndexes() {
        let deleted = apply([.delete(0)])
        #expect(deleted.sets.map(\.weight) == [80, 90, 100])
        let squat = F.squat
        #expect(apply([.delete(9), .weightUp(9), .typedReps(-1, "3")], to: squat) == squat)
        #expect(CutSetEditorLogic.model(deleted, unit: .kg).countLine == "3 sets")
    }
}
