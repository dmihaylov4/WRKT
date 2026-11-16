import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutBalanceLogicTests {
    private typealias F = CutStatsFixtures

    private func model(_ facts: CutBalanceFacts = F.balance) -> CutBalanceModel {
        CutBalanceLogic.model(facts, now: F.now, calendar: F.calendar, locale: F.locale)
    }

    private func pushPull(push: Double, pull: Double) -> CutBalanceFacts.PushPull {
        // The stored ratio, as StatsAggregator writes it.
        .init(push: push, pull: pull, horizontalPush: push, verticalPush: 0, horizontalPull: pull, verticalPull: 0,
              ratio: push > 0 ? pull / push : (pull > 0 ? 999 : 0))
    }

    // MARK: Push and pull

    @Test func splitIsTwoPercentagesThatAddUp() throws {
        let split = try #require(model().split)
        #expect(split.push == "47%")
        #expect(split.pull == "53%")
        #expect(abs(split.pushFraction - 0.47) < 0.0001)
        #expect(split.verdict == "Balanced. Keep pull at or above push.")
        #expect(split.accessibilityLabel == "Push 47%, pull 53%. Balanced. Keep pull at or above push.")
    }

    @Test(arguments: [
        (100.0, 50.0, "Push heavy. Add more pulling."),
        (100.0, 90.0, "Slightly push heavy. Add a little pulling."),
        (100.0, 100.0, "Balanced. Keep pull at or above push."),
        (100.0, 149.0, "Balanced. Keep pull at or above push."),
        (100.0, 150.0, "Slightly pull heavy. Add a little pushing."),
        (100.0, 250.0, "Pull heavy. Add more pushing."),
        (100.0, 0.0, "Only push work logged. Add some pulling."),
        (0.0, 100.0, "Only pull work logged. Add some pushing.")
    ])
    func verdictFollowsTheLegacyRatioBands(push: Double, pull: Double, verdict: String) throws {
        var facts = F.balance
        facts.pushPull = pushPull(push: push, pull: pull)
        #expect(try #require(model(facts).split).verdict == verdict)
    }

    @Test func bandEdgesMatchLegacy() {
        #expect(CutBalanceLogic.verdict(ratio: 0.79) == "Push heavy. Add more pulling.")
        #expect(CutBalanceLogic.verdict(ratio: 0.8) == "Slightly push heavy. Add a little pulling.")
        #expect(CutBalanceLogic.verdict(ratio: 1.0) == "Balanced. Keep pull at or above push.")
        #expect(CutBalanceLogic.verdict(ratio: 1.5) == "Slightly pull heavy. Add a little pushing.")
        #expect(CutBalanceLogic.verdict(ratio: 2.0) == "Pull heavy. Add more pushing.")
        #expect(CutBalanceLogic.verdict(ratio: 9.99) == "Pull heavy. Add more pushing.")
        #expect(CutBalanceLogic.verdict(ratio: 10) == "Only pull work logged. Add some pushing.")
    }

    @Test func oneSidedSplitIsAWholeBar() throws {
        var facts = F.balance
        facts.pushPull = pushPull(push: 1_000, pull: 0)
        let split = try #require(model(facts).split)
        #expect(split.push == "100%")
        #expect(split.pull == "0%")
        #expect(split.pushFraction == 1)
    }

    @Test func noPushOrPullHidesTheSplit() {
        var facts = F.balance
        facts.pushPull = pushPull(push: 0, pull: 0)
        #expect(model(facts).split == nil)
        facts.pushPull = nil
        #expect(model(facts).split == nil)
    }

    // MARK: Last trained

    @Test func relativeDayWording() {
        #expect(CutBalanceLogic.relativeDays(0) == "Today")
        #expect(CutBalanceLogic.relativeDays(1) == "Yesterday")
        #expect(CutBalanceLogic.relativeDays(2) == "2 days ago")
        #expect(CutBalanceLogic.relativeDays(9) == "9 days ago")
    }

    @Test func stalenessThresholdIsTheAggregatorsSevenDayWindow() {
        #expect(CutBalanceLogic.staleAfterDays == 7)
        #expect(CutBalanceLogic.tone(days: 0) == .today)
        #expect(CutBalanceLogic.tone(days: 1) == .recent)
        #expect(CutBalanceLogic.tone(days: 7) == .recent)
        #expect(CutBalanceLogic.tone(days: 8) == .stale)
    }

    @Test func musclesNewestFirstWithTones() {
        let rows = model().muscles
        #expect(rows.map(\.name) == ["Back", "Chest", "Hamstrings", "Quadriceps", "Shoulders", "Calves"])
        #expect(rows.map(\.value) == ["Today", "Today", "2 days ago", "2 days ago", "5 days ago", "9 days ago"])
        #expect(rows.map(\.tone) == [.today, .today, .recent, .recent, .recent, .stale])
    }

    @Test func calendarDaysNotHours() {
        // Late last night is "Yesterday" at noon, though under 24 hours ago.
        var facts = F.balance
        facts.muscles = [.init(name: "Back", lastTrained: F.daysAgo(1, hour: 23))]
        #expect(model(facts).muscles.first?.value == "Yesterday")
    }

    // MARK: Movements

    @Test func movementsLargestFirstWithBarsOnTheLargest() {
        let movements = model().movements
        #expect(movements.map(\.title) == ["Horizontal push", "Vertical pull", "Squat", "Horizontal pull", "Vertical push", "Hinge"])
        #expect(movements.map(\.value) == ["3,300 kg", "2,900 kg", "2,600 kg", "2,400 kg", "1,400 kg", "1,150 kg"])
        #expect(movements.first?.fraction == 1)
        #expect(abs((movements.last?.fraction ?? 0) - 1_150.0 / 3_300.0) < 0.0001)
        #expect(movements.first?.accessibilityLabel == "Horizontal push, 3,300 kilograms")
    }

    @Test func movementsWithoutWorkAreLeftOut() {
        var facts = F.balance
        facts.patterns = .init(squat: 0, hinge: 0)
        #expect(!model(facts).movements.contains { $0.title == "Squat" || $0.title == "Hinge" })
    }

    @Test func poundsInMovements() {
        var facts = F.balance
        facts.unit = .lb
        let movements = model(facts).movements
        #expect(movements.first?.value == "7,275 lb")
        #expect(movements.first?.accessibilityLabel == "Horizontal push, 7,275 pounds")
        // Shares are unit free.
        #expect(model(facts).split?.push == "47%")
    }

    // MARK: Empty

    @Test func noWorkoutsAtAll() {
        let model = model(CutBalanceFacts())
        #expect(model.split == nil)
        #expect(model.muscles.isEmpty)
        #expect(model.movements.isEmpty)
        #expect(model.emptyLine == "Log a workout to see how your training is spread.")
        #expect(model.title == "Balance")
    }

    @Test func anyDataHidesTheEmptyLine() {
        var facts = CutBalanceFacts()
        facts.muscles = [.init(name: "Back", lastTrained: F.daysAgo(3))]
        #expect(model(facts).emptyLine == nil)
    }
}
