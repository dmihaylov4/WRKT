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
        #expect(CutStartSheetLogic.planLine(.init(name: "Upper Body", exerciseCount: 6)) == "6 exercises")
        #expect(CutStartSheetLogic.planLine(.init(name: "Upper Body", exerciseCount: 1)) == "1 exercise")
        #expect(CutStartSheetLogic.planLine(.init(name: "Upper Body", exerciseCount: 0)) == nil)
    }
}
