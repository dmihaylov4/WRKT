import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutExerciseTimerTests {
    @Test func splitsDurationWithoutRounding() {
        let model = CutExerciseTimerLogic.model(duration: 127, hasOverride: true)
        #expect(model.minutes == 2)
        #expect(model.seconds == 7)
        #expect(model.totalSeconds == 127)
        #expect(model.time == "2:07")
        #expect(model.hasOverride)
    }

    @Test func wheelsKeepExistingNonQuarterRecommendationsAndLongOverrides() {
        #expect(CutExerciseTimerLogic.secondChoices(current: 7) == [0, 7, 15, 30, 45])
        #expect(CutExerciseTimerLogic.secondChoices(current: 30) == [0, 15, 30, 45])
        #expect(CutExerciseTimerLogic.minuteChoices(current: 12) == Array(0...10) + [12])
    }

    @Test func onlyZeroDurationDisablesSave() {
        #expect(!CutExerciseTimerModel(minutes: 0, seconds: 0, hasOverride: false).canSave)
        #expect(CutExerciseTimerModel(minutes: 0, seconds: 15, hasOverride: false).canSave)
        #expect(CutExerciseTimerModel(minutes: 1, seconds: 0, hasOverride: false).canSave)
    }
}
