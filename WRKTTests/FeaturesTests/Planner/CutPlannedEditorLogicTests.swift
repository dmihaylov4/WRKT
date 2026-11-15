import Foundation
import Testing
@testable import WRKT

enum CutPlannedEditorFixtures {
    static var calendar: Calendar { CutPlanFixtures.calendar }

    static func draft(_ name: String = "Bench Press", id: String = "bench", sets: [(Int, Double)] = [(10, 60), (8, 70), (6, 80)],
                      notes: String? = nil, order: Int = 0) -> CutPlannedExerciseDraft {
        CutPlannedExerciseDraft(exerciseID: id, exerciseName: name,
                                sets: sets.map { CutPlannedSetDraft(reps: $0.0, weightKg: $0.1) }, notes: notes, order: order)
    }

    static var drafts: [CutPlannedExerciseDraft] {
        [draft(order: 0),
         draft("Barbell Row", id: "row", sets: [(8, 70), (8, 70), (8, 70), (8, 70)], notes: "Pause at the chest", order: 1),
         draft("Plank", id: "plank", sets: [], order: 2)]
    }
}

struct CutPlannedEditorLogicTests {
    private typealias F = CutPlannedEditorFixtures

    // MARK: Model

    @Test func newAndExistingTitles() {
        let new = CutPlannedEditorLogic.model(isNew: true, drafts: [], plateaus: [:], unit: .kg)
        #expect(new.title == "Plan workout")
        #expect(!new.canSave)
        #expect(!new.canDelete)
        let edit = CutPlannedEditorLogic.model(isNew: false, drafts: F.drafts, plateaus: [:], unit: .kg)
        #expect(edit.title == "Edit workout")
        #expect(edit.canSave)
        #expect(edit.canDelete)
    }

    @Test func rowsSummaryPlateauAndNote() {
        let model = CutPlannedEditorLogic.model(isNew: false, drafts: F.drafts,
                                                plateaus: ["bench": 3, "row": 2], unit: .kg)
        #expect(model.rows.map(\.name) == ["Bench Press", "Barbell Row", "Plank"])
        #expect(model.rows[0].preview == "3 sets, 6–10 reps, 60–80 kg")
        #expect(model.rows[1].preview == "4 sets, 8 reps, 70 kg")
        #expect(model.rows[2].preview == "No sets")
        #expect(model.rows[0].plateau == "3 sessions without progress")
        #expect(model.rows[1].plateau == nil)
        #expect(model.rows[1].note == "Pause at the chest")
        #expect(model.rows[0].note == nil)
        #expect(CutPlannedEditorLogic.notePreview("   \n") == nil)
    }

    @Test func summaryInPoundsAndWithoutWeight() {
        #expect(CutPlannedEditorLogic.preview([CutPlannedSetDraft(reps: 5, weightKg: 100)], unit: .lb) == "1 set, 5 reps, 220.5 lb")
        #expect(CutPlannedEditorLogic.preview([CutPlannedSetDraft(reps: 12, weightKg: 0), CutPlannedSetDraft(reps: 12, weightKg: 0)], unit: .kg)
                == "2 sets, 12 reps")
        #expect(CutPlannedEditorLogic.namePlaceholder == "Workout name")
    }

    // MARK: Exercises

    @Test func newExerciseStartsWithThreeSetsOfTenAtTheLastWeight() {
        let draft = CutPlannedEditorLogic.newDraft(exerciseID: "squat", name: "Squat", suggestedWeightKg: 100, order: 3)
        #expect(draft.sets.map(\.reps) == [10, 10, 10])
        #expect(draft.sets.map(\.weightKg) == [100, 100, 100])
        #expect(draft.order == 3)
        #expect(draft.progression == .static)
        #expect(CutPlannedEditorLogic.newDraft(exerciseID: "x", name: "X", suggestedWeightKg: nil, order: 0).sets.allSatisfy { $0.weightKg == 0 })
    }

    @Test func removingRenumbers() {
        let drafts = F.drafts
        let byID = CutPlannedEditorLogic.removing(drafts[0].id, from: drafts)
        #expect(byID.map(\.exerciseName) == ["Barbell Row", "Plank"])
        #expect(byID.map(\.order) == [0, 1])
        let byOffset = CutPlannedEditorLogic.removing(atOffsets: IndexSet(integer: 1), from: drafts)
        #expect(byOffset.map(\.exerciseName) == ["Bench Press", "Plank"])
        #expect(byOffset.map(\.order) == [0, 1])
    }

    // MARK: Sets

    @Test func stepsFollowTheLegacyRules() {
        var draft = F.draft(sets: [(1, 0), (10, 60)])
        draft = CutPlannedEditorLogic.apply(.repsDown(0), to: draft, unit: .kg)
        #expect(draft.sets[0].reps == 1)
        draft = CutPlannedEditorLogic.apply(.weightDown(0), to: draft, unit: .kg)
        #expect(draft.sets[0].weightKg == 0)
        draft = CutPlannedEditorLogic.apply(.weightUp(1), to: draft, unit: .kg)
        #expect(draft.sets[1].weightKg == 62.5)
        draft = CutPlannedEditorLogic.apply(.repsUp(1), to: draft, unit: .kg)
        #expect(draft.sets[1].reps == 11)
        let pounds = CutPlannedEditorLogic.apply(.weightUp(0), to: F.draft(sets: [(5, 0)]), unit: .lb)
        #expect(abs(pounds.sets[0].weightKg - 5 / 2.20462) < 0.0001)
        let model = CutPlannedEditorLogic.setsModel(draft, unit: .kg)
        #expect(model.rows.map(\.canDecreaseReps) == [false, true])
        #expect(model.rows.map(\.canDecreaseWeight) == [false, true])
        #expect(model.rows.map(\.weight) == ["0", "62.5"])
        #expect(model.countLine == "2 sets")
        #expect(model.unitLabel == WeightUnit.kg.label)
    }

    @Test func typedValuesAndBadText() {
        var draft = F.draft(sets: [(10, 60)])
        draft = CutPlannedEditorLogic.apply(.typedWeight(0, "72.5"), to: draft, unit: .kg, locale: Locale(identifier: "en_GB"))
        draft = CutPlannedEditorLogic.apply(.typedReps(0, "12"), to: draft, unit: .kg)
        #expect(draft.sets[0].weightKg == 72.5)
        #expect(draft.sets[0].reps == 12)
        let unchanged = CutPlannedEditorLogic.apply(.typedReps(0, "abc"), to: draft, unit: .kg)
        #expect(unchanged == draft)
        let outOfRange = CutPlannedEditorLogic.apply(.repsUp(9), to: draft, unit: .kg)
        #expect(outOfRange == draft)
    }

    @Test func addCopiesTheLastSetAndDeleteRemoves() {
        var draft = F.draft(sets: [(6, 80)])
        draft = CutPlannedEditorLogic.apply(.add, to: draft, unit: .kg)
        #expect(draft.sets.map(\.reps) == [6, 6])
        #expect(draft.sets.map(\.weightKg) == [80, 80])
        #expect(draft.sets[0].id != draft.sets[1].id)
        draft = CutPlannedEditorLogic.apply(.delete(0), to: draft, unit: .kg)
        draft = CutPlannedEditorLogic.apply(.delete(0), to: draft, unit: .kg)
        #expect(draft.sets.isEmpty)
        draft = CutPlannedEditorLogic.apply(.add, to: draft, unit: .kg)
        #expect(draft.sets.map(\.reps) == [10])
        #expect(draft.sets.map(\.weightKg) == [0])
        #expect(CutPlannedEditorLogic.setsModel(draft, unit: .kg).countLine == "1 set")
    }

    @Test func emptyNoteIsNoNote() {
        #expect(CutPlannedEditorLogic.savedNotes("") == nil)
        #expect(CutPlannedEditorLogic.savedNotes("Slow") == "Slow")
    }

    // MARK: Save

    @Test func nameDefaultsToCustomWorkout() {
        #expect(CutPlannedEditorLogic.savedName("") == "Custom Workout")
        #expect(CutPlannedEditorLogic.savedName("Push") == "Push")
        // The legacy editor did not trim: spaces are kept as typed.
        #expect(CutPlannedEditorLogic.savedName("  ") == "  ")
    }

    @Test func movingAPlanWorkoutAsksFirst() {
        let original = CutPlanFixtures.day(13, hour: 0)
        let sameDay = CutPlanFixtures.day(13, hour: 15)
        let later = CutPlanFixtures.day(16)
        #expect(CutPlannedEditorLogic.saveStep(hasSplit: true, original: original, chosen: later, calendar: F.calendar) == .askHowToMove)
        #expect(CutPlannedEditorLogic.saveStep(hasSplit: true, original: original, chosen: sameDay, calendar: F.calendar) == .save)
        #expect(CutPlannedEditorLogic.saveStep(hasSplit: false, original: original, chosen: later, calendar: F.calendar) == .save)
        #expect(CutPlannedEditorLogic.dayOffset(original: original, chosen: later, calendar: F.calendar) == 3)
        #expect(CutPlannedEditorLogic.dayOffset(original: later, chosen: original, calendar: F.calendar) == -3)
    }

    @Test func conflictMessageNamesTheWorkout() {
        let message = CutPlannedEditorLogic.conflictMessage(existingName: "Leg Day", date: CutPlanFixtures.day(13))
        #expect(message.hasPrefix("\"Leg Day\" is already planned for "))
        #expect(message.hasSuffix(". Choose a different date."))
    }

    @Test func targetVolumeIsRepsTimesWeight() {
        #expect(CutPlannedEditorLogic.targetVolume(F.drafts) == 600 + 560 + 480 + 4 * 560)
        #expect(CutPlannedEditorLogic.targetVolume([]) == 0)
    }

    // MARK: Conversion

    @Test func roundTripKeepsIDsTagsNotesAndOrder() {
        var drafts = F.drafts
        drafts[0].sets[0].tag = SetTag.warmup.rawValue
        let exercises = CutPlannedEditorLogic.plannedExercises(drafts)
        #expect(exercises.map(\.order) == [0, 1, 2])
        #expect(exercises[1].notes == "Pause at the chest")
        #expect(exercises[0].ghostSets[0].tag == SetTag.warmup.rawValue)
        #expect(exercises[0].ghostSets[0].id == drafts[0].sets[0].id)
        let back = CutPlannedEditorLogic.drafts(from: Array(exercises.reversed()))
        #expect(back == drafts)
    }
}
