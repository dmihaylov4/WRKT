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
}
