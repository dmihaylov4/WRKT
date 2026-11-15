import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutCompeteLogicTests {
    func item(_ incoming: Bool = false) -> CutCompeteItem { .init(id: .battle(UUID()), title: "Fixture Opponent", subtitle: "Volume", incoming: incoming) }
    @Test func sectionsAndLimits() {
        let incoming = (0..<5).map { _ in item(true) }, outgoing = item()
        let active = (0..<7).map { _ in item() }
        let m = CutCompeteLogic.model(pending: incoming + [outgoing], battles: active, challenges: active, available: active,
            completedBattles: active, completedChallenges: active, loading: false, error: nil)
        #expect(m.pending.count == 3); #expect(m.pendingCount == 5); #expect(m.active.count == 10)
        #expect(m.recommended.count == 3); #expect(m.completed.count == 4); #expect(m.summary.count == 4)
    }
    @Test func emptyLoadingAndError() {
        let m = CutCompeteLogic.model(pending: [], battles: [], challenges: [], available: [], completedBattles: [], completedChallenges: [], loading: true, error: "Fixture failure")
        #expect(m.loading); #expect(m.error == "Fixture failure"); #expect(m.active.isEmpty); #expect(m.summary.isEmpty)
    }
    @Test func singleSummaryHidden() {
        let m = CutCompeteLogic.model(pending: [], battles: [item()], challenges: [], available: [], completedBattles: [], completedChallenges: [], loading: false, error: nil)
        #expect(m.summary.isEmpty)
    }
    @Test func failedRefreshRetainsLoadedDataButEmptySuccessClears() {
        let retained: [Int] = CutCompeteLogic.refreshed([1], candidate: [], failed: true)
        #expect(retained == [1])
        let cleared: [Int] = CutCompeteLogic.refreshed([1], candidate: [], failed: false)
        #expect(cleared.isEmpty)
    }
    @Test func battleIdentityAndPending() {
        var f = CutBattleDetailLogicTests.facts; f.status = .pending; f.isOpponent = true
        let row = CutCompeteLogic.battle(f, unit: .kg)
        #expect(row.id == .battle(f.id)); #expect(row.incoming); #expect(row.value == "Invitation"); #expect(row.fraction == nil)
    }
    @Test func challengeRowsPreserveCategoryGoalDescriptionAndReward() {
        var facts = CutChallengeDetailLogicTests.facts
        facts.current = nil; facts.type = .custom; facts.metric = "conditioning_minutes"; facts.goal = 120; facts.participantCount = 0
        facts.reward = .plate(id: 24, name: "Fixture Plate")
        let row = CutCompeteLogic.challenge(facts, unit: .kg, locale: Locale(identifier: "en_US"), now: CutChallengeDetailLogicTests.now, showsDescription: true)
        #expect(row.subtitle == "Custom · Beginner"); #expect(row.trailing == "14 days left · 120 min")
        #expect(row.note == "Fixture description"); #expect(row.value == nil); #expect(row.plateTier == 24); #expect(row.fraction == nil)
    }
    @Test func challengeRowsFormatProgressInTheRequestedUnitAndLocale() {
        var facts = CutChallengeDetailLogicTests.facts
        facts.type = .totalVolume; facts.goal = 10000; facts.current = 1500
        let row = CutCompeteLogic.challenge(facts, unit: .lb, locale: Locale(identifier: "de_DE"), now: CutChallengeDetailLogicTests.now)
        #expect(row.value == "3,3k / 22,0k lb"); #expect(row.progressLabel == "60%"); #expect(row.note == nil)
    }

    @Test func listAndDetailScoreFormattingStayConsistent() {
        for type in [BattleType.volume, .workoutCount, .consistency, .pr, .exercise, .runningDistance] {
            var facts = CutBattleDetailLogicTests.facts; facts.type = type
            for unit in [WeightUnit.kg, .lb] {
                let locale = Locale(identifier: "de_DE")
                let detail = CutBattleDetailLogic.model(facts, unit: unit, locale: locale, now: CutBattleDetailLogicTests.now)
                let row = CutCompeteLogic.battle(facts, unit: unit, locale: locale, now: CutBattleDetailLogicTests.now)
                #expect(row.value == "You \(detail.ownScore) : \(detail.otherScore) \(detail.unit)")
                #expect(row.trailing == detail.time + " · " + detail.lead); #expect(row.fraction == detail.split)
            }
        }
    }

}
