import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutExerciseCreateTests {
    @Test func validatesTrimmedNameWithoutAddingDuplicateRestrictions() {
        #expect(CutCreateExerciseLogic.validationMessage(name: " \n ") != nil)
        #expect(CutCreateExerciseLogic.validationMessage(name: "Barbell Bench Press") == nil)
        #expect(CutCreateExerciseLogic.exercise(form: .init(), id: "new") == nil)
    }

    @Test func defaultsAndEditingPreserveSelections() {
        #expect(CutCreateExerciseLogic.model(preselectedMuscle: "", editing: nil).muscle == "Chest")
        #expect(CutCreateExerciseLogic.model(preselectedMuscle: "Quads", editing: nil).muscle == "Quads")
        let form = CutCreateExerciseLogic.model(preselectedMuscle: "Back", editing: CutExerciseFixtures.exercises[0])
        #expect(form.isEditing)
        #expect(form.name == "Barbell Bench Press")
        #expect(form.muscle == "Chest")
        #expect(form.equipment == .barbell)
        #expect(form.movement == .push)
        #expect(form.actionTitle == "Save")
    }

    @Test func savedExerciseUsesSameCustomFieldsAndTrimsName() throws {
        var form = CutCreateExerciseModel(name: "  My Lift \n", muscle: "Quads", equipment: .barbell, movement: .squat)
        form.mechanic = "isolation"
        let exercise = try #require(CutCreateExerciseLogic.exercise(form: form, id: "custom_fixed"))
        #expect(exercise.id == "custom_fixed")
        #expect(exercise.name == "My Lift")
        #expect(exercise.primaryMuscles == ["Quads"])
        #expect(exercise.subregionTags == ["Quads"])
        #expect(exercise.category == "quads")
        #expect(exercise.force == "push")
        #expect(exercise.equipment == "Barbell")
        #expect(exercise.mechanic == "isolation")
        #expect(exercise.isCustom)
        #expect(exercise.instructions.isEmpty)
    }

    @Test func equipmentAndMovementSerializationMatchLegacy() {
        #expect(CutCreateExerciseLogic.equipment(.bodyweight) == nil)
        #expect(CutCreateExerciseLogic.equipment(.all) == nil)
        #expect(CutCreateExerciseLogic.equipment(.ezBar) == "EZ Bar")
        #expect(CutCreateExerciseLogic.equipment(.pullupbar) == "Pullup Bar")
        #expect(CutCreateExerciseLogic.force(.hinge) == "pull")
        #expect(CutCreateExerciseLogic.force(.core) == nil)
        #expect(CutCreateExerciseLogic.muscles.count == 14)
    }
}
