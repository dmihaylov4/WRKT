import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutTrendsLogicTests {
    private typealias F = CutStatsFixtures

    private func model(_ facts: CutTrendsFacts = F.trends) -> CutTrendsModel {
        CutTrendsLogic.model(facts, now: F.now, calendar: F.calendar, locale: F.locale)
    }

    // MARK: Week on week

    @Test func upOnLastWeekIsLime() {
        let change = CutTrendsLogic.change(current: 26_446, previous: 24_487)
        #expect(change.line == "Up 8% on last week")
        #expect(change.isUp)
    }

    @Test func downOnLastWeekIsPlain() {
        let change = CutTrendsLogic.change(current: 18_000, previous: 24_000)
        #expect(change.line == "Down 25% on last week")
        #expect(!change.isUp)
    }

    @Test func levelWhenTheChangeRoundsToZero() {
        #expect(CutTrendsLogic.change(current: 10_040, previous: 10_000) == ("Level with last week", false))
    }

    @Test func noPreviousWeek() {
        #expect(CutTrendsLogic.change(current: 5_000, previous: nil) == ("Nothing logged last week", false))
        #expect(CutTrendsLogic.change(current: 5_000, previous: 0) == ("Nothing logged last week", false))
    }

    @Test func nothingYetThisWeek() {
        #expect(CutTrendsLogic.change(current: 0, previous: 9_000) == ("Nothing logged yet this week", false))
    }

    @Test func heroIsThisWeeksTonnageWithItsChange() throws {
        let hero = try #require(model().hero)
        #expect(hero.label == "Lifted this week")
        #expect(hero.value == "26,446")
        #expect(hero.unit == "kg")
        #expect(hero.change == "Up 8% on last week")
        #expect(hero.changeIsUp)
        #expect(hero.accessibilityLabel == "Lifted this week, 26,446 kilograms. Up 8% on last week")
    }

    @Test func aWeekWithoutTrainingShowsZeroAndSaysSo() throws {
        var facts = F.trends
        facts.weeks.removeLast()
        let hero = try #require(model(facts).hero)
        #expect(hero.value == "0")
        #expect(hero.change == "Nothing logged yet this week")
        #expect(model(facts).stats.map(\.value) == ["0", "0", "0"])
    }

    // MARK: Chart

    @Test func twelveBarsWithThisWeekCurrent() {
        let bars = model().bars
        #expect(bars.count == 12)
        #expect(bars.last?.isCurrent == true)
        #expect(bars.dropLast().allSatisfy { !$0.isCurrent })
        #expect(bars.last?.fraction == 1)
        #expect(abs((bars.first?.fraction ?? 0) - 11_100 / 26_446) < 0.0001)
    }

    @Test func gapsInTheWindowAreEmptyBars() {
        var facts = F.trends
        facts.weeks.remove(at: 5)
        #expect(model(facts).bars[5].fraction == 0)
    }

    @Test func averageLineIsThePersonalAverageOnTheBarScale() throws {
        let model = model()
        let fraction = try #require(model.averageFraction)
        #expect(abs(fraction - 17_200 / 26_446) < 0.0001)
        #expect(model.captionLeading == "12 weeks ago")
        #expect(model.captionTrailing == "Dashed line: your average")
    }

    @Test func averageAboveEveryWeekSetsTheScale() throws {
        var facts = F.trends
        facts.personalAverageKg = 40_000
        let model = model(facts)
        #expect(model.averageFraction == 1)
        #expect(abs((model.bars.last?.fraction ?? 0) - 26_446 / 40_000) < 0.0001)
    }

    @Test func averageHiddenWithOneWeekOrNone() {
        var one = F.trends
        one.weeks = [F.trendWeeks.last!]
        #expect(model(one).averageFraction == nil)
        #expect(model(one).captionTrailing == nil)
        var none = F.trends
        none.personalAverageKg = nil
        #expect(model(none).averageFraction == nil)
    }

    @Test func chartLabelStatesTheTrendInWords() {
        #expect(model().chartAccessibilityLabel
            == "Volume per week over the last 12 weeks, rising, this week 26,446 kilograms, your average 17,200 kilograms")
        #expect(CutTrendsLogic.direction([10, 10, 10, 10, 6, 6, 6, 6]) == "falling")
        #expect(CutTrendsLogic.direction([10, 10, 10, 10.5, 10, 10]) == "steady")
        #expect(CutTrendsLogic.direction([0, 0, 0, 5, 5, 5]) == "rising")
    }

    // MARK: Stat columns

    @Test func statColumnsAreThisWeeksWorkoutsSetsAndReps() {
        let stats = model().stats
        #expect(stats.map(\.value) == ["3", "58", "412"])
        #expect(stats.map(\.label) == ["workouts", "sets", "reps"])
    }

    @Test func singularLabels() {
        var facts = F.trends
        facts.weeks[facts.weeks.count - 1] = .init(weekStart: F.thisMonday, volumeKg: 400, sessions: 1, sets: 1, reps: 1)
        #expect(model(facts).stats.map(\.label) == ["workout", "set", "rep"])
    }

    // MARK: Top lifts

    @Test func topLiftsSumTheWindowAndKeepFive() {
        let lifts = model().lifts
        #expect(lifts.map(\.name) == ["Back Squat", "Bench Press", "Deadlift", "Barbell Row", "Overhead Press"])
        #expect(lifts.map(\.value) == ["6,240 kg", "4,980 kg", "4,400 kg", "3,100 kg", "1,900 kg"])
        #expect(lifts.first?.accessibilityLabel == "Back Squat, 6,240 kilograms over 12 weeks")
    }

    @Test func unknownExerciseFallsBackToItsID() {
        var facts = F.trends
        facts.names = [:]
        #expect(model(facts).lifts.first?.name == "squat")
    }

    // MARK: Unit

    @Test func poundsEverywhere() throws {
        var facts = F.trends
        facts.unit = .lb
        let model = model(facts)
        let hero = try #require(model.hero)
        #expect(hero.value == "58,303")
        #expect(hero.unit == "lb")
        #expect(hero.accessibilityLabel.contains("58,303 pounds"))
        #expect(model.lifts.first?.value == "13,757 lb")
        #expect(model.chartAccessibilityLabel.contains("your average 37,919 pounds"))
        // The week on week change is unit free.
        #expect(hero.change == "Up 8% on last week")
    }

    // MARK: Empty

    @Test func noWorkoutsAtAll() {
        let model = model(CutTrendsFacts())
        #expect(model.hero == nil)
        #expect(model.emptyLine == "Log a workout to see your weekly trends.")
        #expect(model.bars.isEmpty)
        #expect(model.stats.isEmpty)
        #expect(model.lifts.isEmpty)
        #expect(model.title == "Trends")
    }

    @Test func healthOnlyWeeksCountAsNoTraining() {
        let facts = CutTrendsFacts(weeks: [.init(weekStart: F.thisMonday, volumeKg: 0, sessions: 0, sets: 0, reps: 0)])
        #expect(model(facts).hero == nil)
    }
}
