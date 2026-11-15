import Foundation
import Testing
@testable import WRKT

enum CutWeeklyGoalFixtures {
    static let symbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static var midWeek: CutWeeklyGoalFacts {
        CutWeeklyGoalFacts(mvpaDone: 95, mvpaTarget: 150, strengthDaysDone: 2, strengthTarget: 4,
                           minutesLeft: 55, strengthDaysLeft: 2, paceStatus: .onTrack,
                           targetActiveMinutes: 150, targetStrengthDays: 4, anchorWeekday: 2)
    }

    static var cardioDone: CutWeeklyGoalFacts {
        CutWeeklyGoalFacts(mvpaDone: 160, mvpaTarget: 150, strengthDaysDone: 1, strengthTarget: 3,
                           minutesLeft: 0, strengthDaysLeft: 2, paceStatus: .behind,
                           targetActiveMinutes: 150, targetStrengthDays: 3, anchorWeekday: 1)
    }

    static var complete: CutWeeklyGoalFacts {
        CutWeeklyGoalFacts(mvpaDone: 180, mvpaTarget: 150, strengthDaysDone: 3, strengthTarget: 3,
                           minutesLeft: 0, strengthDaysLeft: 0, paceStatus: .ahead,
                           targetActiveMinutes: 150, targetStrengthDays: 3, anchorWeekday: 2)
    }
}

@Suite("Cut weekly goal logic")
struct CutWeeklyGoalLogicTests {
    private typealias F = CutWeeklyGoalFixtures

    @Test func midWeekOffersEveryAction() {
        let model = CutWeeklyGoalLogic.model(F.midWeek, weekdaySymbols: F.symbols)
        #expect(model.title == "Weekly goal")
        #expect(model.startStrength == .init(title: "Start strength workout", subtitle: "2 days remaining"))
        #expect(model.viewCardio == .init(title: "View cardio activity", subtitle: "55 min remaining"))
        #expect(model.syncHealth == .init(title: "Sync from Apple Health", subtitle: "Import runs and exercise minutes"))
        #expect(model.completeLine == nil)
    }

    @Test func cardioDoneHidesTheCardioActions() {
        let model = CutWeeklyGoalLogic.model(F.cardioDone, weekdaySymbols: F.symbols)
        #expect(model.startStrength?.subtitle == "2 days remaining")
        #expect(model.viewCardio == nil)
        #expect(model.syncHealth == nil)
        #expect(model.completeLine == nil)
    }

    @Test func bothTargetsMetShowsTheCompleteLineOnly() {
        let model = CutWeeklyGoalLogic.model(F.complete, weekdaySymbols: F.symbols)
        #expect(model.startStrength == nil)
        #expect(model.viewCardio == nil)
        #expect(model.syncHealth == nil)
        #expect(model.completeLine == "Weekly targets complete")
    }

    @Test func goalNumbersAndPace() {
        let goal = CutWeeklyGoalLogic.model(F.midWeek, weekdaySymbols: F.symbols).goal
        #expect(goal.strengthValue == "2/4")
        #expect(goal.cardioValue == "95/150")
        #expect(goal.strengthFraction == 0.5)
        #expect(abs(goal.cardioFraction - 95.0 / 150.0) < 0.0001)
        #expect(goal.status == "On track")
        #expect(!goal.isSuperWeek)
        #expect(goal.accessibilityLabel.contains("strength 2 of 4 days"))
        // Over the target the arm is full.
        #expect(CutWeeklyGoalLogic.model(F.cardioDone, weekdaySymbols: F.symbols).goal.cardioFraction == 1)
        #expect(CutWeeklyGoalLogic.statusLine(.ahead) == "Ahead of pace")
        #expect(CutWeeklyGoalLogic.statusLine(.behind) == "Behind pace")
    }

    @Test func settingsRows() {
        let rows = CutWeeklyGoalLogic.model(F.midWeek, weekdaySymbols: F.symbols).settings
        #expect(rows.map(\.title) == ["Target active minutes", "Target strength days", "Week starts"])
        #expect(rows.map(\.value) == ["150 min", "4 days", "Monday"])
        #expect(CutWeeklyGoalLogic.weekdayName(1, symbols: F.symbols) == "Sunday")
        #expect(CutWeeklyGoalLogic.weekdayName(8, symbols: F.symbols) == "Sunday")
    }

    @Test func oneDayIsSingular() {
        #expect(CutWeeklyGoalLogic.daysRemaining(1) == "1 day remaining")
    }
}
