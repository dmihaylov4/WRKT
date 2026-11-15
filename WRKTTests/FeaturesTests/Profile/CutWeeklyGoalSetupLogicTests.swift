import Foundation
import Testing
@testable import WRKT

@Suite("Cut weekly goal setup logic")
struct CutWeeklyGoalSetupLogicTests {
    private typealias L = CutWeeklyGoalSetupLogic
    private let symbols = CutWeeklyGoalFixtures.symbols
    private let locale = Locale(identifier: "en_US")

    @Test func minutesModeLines() {
        var draft = CutWeeklyGoalSetupDraft()
        draft.age = AgeDraft(saved: 34)
        draft.targetStrengthDays = 3
        let model = L.model(draft, weekdaySymbols: symbols, locale: locale)
        #expect(model.title == "Weekly goal")
        #expect(model.age == "34")
        #expect(model.activityTitle == "Active minutes (MVPA)")
        #expect(model.activityValue == "150 min")
        #expect(model.activityFooter == "Apple Watch tracks exercise time automatically")
        #expect(model.strengthDays == "3 days")
        #expect(model.weekStartFooter == "Your week will start on Monday")
        #expect(model.weekStartOptions.map(\.value) == Array(1...7))
        #expect(model.weekStartOptions.first?.label == "Sunday")
    }

    @Test func stepsModeLines() {
        var draft = CutWeeklyGoalSetupDraft()
        draft.trackingMode = .steps
        draft.targetDailySteps = 12500
        let model = L.model(draft, weekdaySymbols: symbols, locale: locale)
        #expect(model.activityTitle == "Daily steps")
        #expect(model.activityValue == "12,500")
        #expect(model.activityFooter == "Aim for 10,000 steps per day for good health")
    }

    @Test func steppersKeepTheLegacyBounds() {
        #expect(L.stepped(10, by: -1, in: AgeDraft.range) == nil)
        #expect(L.stepped(100, by: 1, in: AgeDraft.range) == nil)
        #expect(L.stepped(34, by: 1, in: AgeDraft.range) == 35)
        #expect(L.stepped(0, by: -1, in: L.strengthRange) == nil)
        #expect(L.stepped(7, by: 1, in: L.strengthRange) == nil)
        var draft = CutWeeklyGoalSetupDraft()
        draft.targetStrengthDays = 0
        draft.age = AgeDraft(saved: 100)
        let model = L.model(draft, weekdaySymbols: symbols)
        #expect(!model.canDecreaseStrength && model.canIncreaseStrength)
        #expect(model.canDecreaseAge && !model.canIncreaseAge)
        #expect(model.strengthDays == "0 days")
    }

    @Test func slidersSnapToTheLegacySteps() {
        #expect(L.minutesRange == 30...600 && L.minutesStep == 15)
        #expect(L.stepsRange == 1000...30000 && L.stepsStep == 500)
        #expect(L.snapped(152, step: 15, in: L.minutesRange) == 150)
        #expect(L.snapped(10, step: 15, in: L.minutesRange) == 30)
        #expect(L.snapped(31_000, step: 500, in: L.stepsRange) == 30000)
    }

    @Test func savingWritesTheGoal() {
        let goal = WeeklyGoal()
        var draft = CutWeeklyGoalSetupDraft()
        draft.targetMinutes = 210
        draft.targetDailySteps = 8000
        draft.targetStrengthDays = 4
        draft.weekStartDay = 1
        draft.trackingMode = .steps
        let now = Date(timeIntervalSince1970: 1_794_571_200)
        L.apply(draft, to: goal, now: now)
        #expect(goal.isSet)
        #expect(goal.targetActiveMinutes == 210)
        #expect(goal.targetDailySteps == 8000)
        #expect(goal.targetStrengthDays == 4)
        #expect(goal.anchorWeekday == 1)
        #expect(goal.mode == .steps)
        #expect(goal.updatedAt == now)
    }
}
