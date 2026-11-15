import Foundation
import Testing
@testable import WRKT

enum CutPlanWeekFixtures {
    static var calendar: Calendar { CutPlanFixtures.calendar }
    static let locale = Locale(identifier: "en_GB")
    /// Monday 9 November 2026: the current week.
    static var thisWeek: Date { CutPlanFixtures.day(9) }

    static func progress(_ strength: Int = 2, of strengthTarget: Int = 4, cardio: Int = 95, of cardioTarget: Int = 150,
                         week: Date = thisWeek) -> CutPlanWeekInput.Progress {
        .init(weekStart: week, strengthDone: strength, strengthTarget: strengthTarget,
              cardioMinutes: cardio, cardioTarget: cardioTarget)
    }

    static func model(_ input: CutPlanWeekInput) -> CutPlanWeekModel {
        CutPlanWeekLogic.model(input, calendar: calendar, locale: locale)
    }

    static func input(streak: Int = 6, progress: CutPlanWeekInput.Progress? = progress(), frozen: Bool = false,
                      push: Double = 0, pull: Double = 0) -> CutPlanWeekInput {
        CutPlanWeekInput(streak: streak, progress: progress, isFrozen: frozen, currentWeekStart: thisWeek,
                         pushVolume: push, pullVolume: pull)
    }
}

struct CutPlanWeekLogicTests {
    private typealias F = CutPlanWeekFixtures

    // MARK: Goal

    @Test func weekInProgress() {
        let goal = try! #require(F.model(F.input()).goal)
        #expect(goal.weekLabel == "This week")
        #expect(goal.strengthValue == "2/4")
        #expect(goal.cardioValue == "95/150")
        #expect(goal.strengthFraction == 0.5)
        #expect(abs(goal.cardioFraction - 95.0 / 150.0) < 0.0001)
        #expect(goal.status == nil)
        #expect(!goal.isSuperWeek)
        #expect(goal.accessibilityLabel == "Weekly goal: strength 2 of 4 days, cardio 95 of 150 minutes")
    }

    @Test func superWeekWhenBothGoalsAreMet() {
        let goal = F.model(F.input(progress: F.progress(4, cardio: 150))).goal!
        #expect(goal.status == "Super week: both goals met")
        #expect(goal.isSuperWeek)
        #expect(goal.accessibilityLabel.hasSuffix(". Super week: both goals met"))
    }

    @Test func overGoalClampsTheMarkButKeepsTheNumbers() {
        let goal = F.model(F.input(progress: F.progress(6, cardio: 240))).goal!
        #expect(goal.strengthValue == "6/4")
        #expect(goal.cardioValue == "240/150")
        #expect(goal.strengthFraction == 1)
        #expect(goal.cardioFraction == 1)
        #expect(goal.isSuperWeek)
    }

    @Test func oneGoalMetNamesTheOther() {
        #expect(F.model(F.input(progress: F.progress(4, cardio: 20))).goal?.status
                == "Strength goal met. Finish the cardio minutes for a super week.")
        #expect(F.model(F.input(progress: F.progress(1, cardio: 150))).goal?.status
                == "Cardio goal met. Finish the strength days for a super week.")
    }

    @Test func frozenWeekCountsAsDone() {
        let goal = F.model(F.input(progress: F.progress(1, cardio: 20), frozen: true)).goal!
        #expect(goal.status == "Freeze protected")
        #expect(goal.strengthValue == "4/4")
        #expect(goal.cardioValue == "150/150")
        #expect(goal.strengthFraction == 1)
        #expect(!goal.isSuperWeek)
    }

    @Test func superWeekWinsOverFreeze() {
        #expect(F.model(F.input(progress: F.progress(4, cardio: 150), frozen: true)).goal?.isSuperWeek == true)
    }

    @Test func zeroTargets() {
        // No cardio target counts as met, as before; nothing fills an arm without a target.
        let noCardio = F.model(F.input(progress: F.progress(1, of: 3, cardio: 0, of: 0))).goal!
        #expect(noCardio.cardioFraction == 0)
        #expect(noCardio.cardioValue == "0/0")
        #expect(noCardio.status == "Cardio goal met. Finish the strength days for a super week.")
        let none = F.model(F.input(progress: F.progress(0, of: 0, cardio: 0, of: 0))).goal!
        #expect(none.strengthFraction == 0)
        #expect(none.isSuperWeek)
        #expect(CutPlanWeekLogic.fraction(3, of: 0) == 0)
        #expect(CutPlanWeekLogic.fraction(-2, of: 4) == 0)
    }

    @Test func oneDayTargetReadsInTheSingular() {
        #expect(F.model(F.input(progress: F.progress(0, of: 1))).goal?.accessibilityLabel
                    .hasPrefix("Weekly goal: strength 0 of 1 day,") == true)
    }

    @Test func otherWeeksShowTheirDays() {
        let past = CutPlanFixtures.day(2)
        #expect(F.model(F.input(progress: F.progress(week: past))).goal?.weekLabel == "2 to 8 Nov")
        let crossing = CutPlanFixtures.day(30)
        #expect(F.model(F.input(progress: F.progress(week: crossing))).goal?.weekLabel == "30 Nov to 6 Dec")
        let noCurrent = CutPlanWeekLogic.weekLabel(F.thisWeek, currentWeekStart: nil, calendar: F.calendar, locale: F.locale)
        #expect(noCurrent == "9 to 15 Nov")
    }

    // MARK: Streak and empty

    @Test func streakRunsToTwelveWeeks() {
        let streak = F.model(F.input(streak: 6)).streak!
        #expect(streak.value == "6")
        #expect(streak.label == "week goal streak")
        #expect(streak.filledSegments == 6)
        #expect(streak.totalSegments == 12)
        #expect(streak.milestoneLine == "Next milestone: 12 weeks")
        #expect(F.model(F.input(streak: 20)).streak?.filledSegments == 12)
        #expect(F.model(F.input(streak: 0)).streak == nil)
    }

    @Test func emptyOnlyWithoutGoalAndStreak() {
        #expect(F.model(F.input(streak: 0, progress: nil)).showsEmpty)
        #expect(!F.model(F.input(streak: 3, progress: nil)).showsEmpty)
        #expect(!F.model(F.input(streak: 0)).showsEmpty)
        #expect(F.model(F.input(streak: 3, progress: nil)).goal == nil)
    }

    // MARK: Push and pull

    @Test func balanceMessages() {
        #expect(CutPlanWeekLogic.balanceMessage(push: 0, pull: 0) == nil)
        #expect(CutPlanWeekLogic.balanceMessage(push: 1000, pull: 1000) == nil)
        #expect(CutPlanWeekLogic.balanceMessage(push: 1000, pull: 2000) == nil)
        // The ratio is pull over push: more pulling than pushing is pull-heavy.
        #expect(CutPlanWeekLogic.balanceMessage(push: 1000, pull: 2500)
                == "This week's plan is pull-heavy (ratio 2.5). Consider balancing with push work.")
        #expect(CutPlanWeekLogic.balanceMessage(push: 1000, pull: 400)
                == "This week's plan is push-heavy (ratio 0.4). Consider adding a row or pull variation.")
        #expect(CutPlanWeekLogic.balanceMessage(push: 0, pull: 500)
                == "This week's plan is pull-heavy (no push work). Consider balancing with push work.")
        #expect(CutPlanWeekLogic.balanceMessage(push: 500, pull: 0)
                == "This week's plan is push-heavy (ratio 0.0). Consider adding a row or pull variation.")
        #expect(F.model(F.input(push: 1000, pull: 300)).balanceMessage != nil)
    }
}
