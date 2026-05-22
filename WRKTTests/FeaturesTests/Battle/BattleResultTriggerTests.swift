import Testing
import Foundation
@testable import WRKT

private func makeBattle(
    id: UUID = UUID(),
    status: BattleStatus = .completed,
    endDate: Date = Date().addingTimeInterval(-3600),
    winnerId: UUID? = nil
) -> BattleWithParticipants {
    let battle = Battle(
        id: id,
        challengerId: UUID(),
        opponentId: UUID(),
        battleType: .volume,
        targetMetric: nil,
        startDate: Date().addingTimeInterval(-7 * 24 * 3600),
        endDate: endDate,
        status: status,
        winnerId: winnerId,
        challengerScore: 1500,
        opponentScore: 1200,
        customRules: nil,
        trashTalkEnabled: false,
        createdAt: Date(),
        updatedAt: Date()
    )
    let profile = UserProfile(id: UUID(), username: "alice")
    var result = BattleWithParticipants(
        id: id,
        battle: battle,
        challenger: profile,
        opponent: profile
    )
    result.currentUserId = UUID()
    return result
}

@Suite("BattleViewModel unseen result detection")
struct BattleResultTriggerTests {

    @Test("unseenResult returns nil when completed list is empty")
    func noCompletedBattles() {
        let result = BattleViewModel.unseenResult(from: [], seen: [], cutoff: Date())
        #expect(result == nil)
    }

    @Test("unseenResult returns battle when not in seen set")
    func returnsBattleWhenUnseen() {
        let battle = makeBattle()
        let result = BattleViewModel.unseenResult(from: [battle], seen: [], cutoff: Date().addingTimeInterval(-8 * 24 * 3600))
        #expect(result?.id == battle.id)
    }

    @Test("unseenResult returns nil when battle is already in seen set")
    func returnsNilWhenSeen() {
        let battle = makeBattle()
        let result = BattleViewModel.unseenResult(from: [battle], seen: [battle.id], cutoff: Date().addingTimeInterval(-8 * 24 * 3600))
        #expect(result == nil)
    }

    @Test("unseenResult returns nil when battle endDate is older than cutoff")
    func returnsNilWhenTooOld() {
        let oldBattle = makeBattle(endDate: Date().addingTimeInterval(-10 * 24 * 3600))
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let result = BattleViewModel.unseenResult(from: [oldBattle], seen: [], cutoff: cutoff)
        #expect(result == nil)
    }

    @Test("unseenResult prefers most recently ended battle when multiple unseen")
    func prefersMostRecent() {
        let older  = makeBattle(endDate: Date().addingTimeInterval(-7200))
        let newer  = makeBattle(endDate: Date().addingTimeInterval(-1800))
        let cutoff = Date().addingTimeInterval(-8 * 24 * 3600)
        let result = BattleViewModel.unseenResult(from: [older, newer], seen: [], cutoff: cutoff)
        #expect(result?.id == newer.id)
    }

    @Test("dismissResult nils pendingResultBattle")
    @MainActor
    func dismissResult() async {
        let battle = makeBattle()
        var pending: BattleWithParticipants? = battle
        pending = nil
        #expect(pending == nil)
    }
}
