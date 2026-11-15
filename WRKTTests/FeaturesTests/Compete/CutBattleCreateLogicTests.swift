import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutBattleCreateLogicTests {
    static let friend = CutBattleOpponent(id: UUID(), name: "Fixture Opponent", username: "fixture_opponent", avatarURL: nil)
    @Test func defaultsAndMissingOpponent() {
        let draft = CutCreateBattleDraft()
        #expect(draft.type == .volume); #expect(draft.duration == 7)
        #expect(!model(draft).canSend)
    }
    @Test(arguments: CutCreateBattleLogic.types) func supportedTypesCanSend(_ type: BattleType) {
        #expect(model(.init(opponentID: Self.friend.id, type: type)).canSend)
    }
    @Test(arguments: CutCreateBattleLogic.durations) func supportedDurationsCanSend(_ days: Int) {
        #expect(model(.init(opponentID: Self.friend.id, duration: days)).canSend)
    }
    @Test func unsafeValuesAndCreatingAreDisabled() {
        #expect(!model(.init(opponentID: Self.friend.id, type: .exercise)).canSend)
        #expect(!model(.init(opponentID: Self.friend.id, duration: 0)).canSend)
        #expect(!model(.init(opponentID: UUID())).canSend)
        #expect(!CutCreateBattleLogic.model(.init(opponentID: Self.friend.id), opponent: Self.friend, creating: true, unit: .kg).canSend)
    }
    @Test func opponentSearchMatchesBothNamesAndPreservesOrder() {
        let second = CutBattleOpponent(id: UUID(), name: "Training Fixture", username: "second", avatarURL: nil)
        let m = CutCreateBattleLogic.opponents([Self.friend, second], query: "FIXTURE", selected: second.id, loading: false, error: nil)
        #expect(m.rows.map(\.id) == [Self.friend.id, second.id]); #expect(m.selectedID == second.id)
        #expect(CutCreateBattleLogic.opponents([second], query: "SECOND", selected: nil, loading: false, error: nil).rows == [second])
    }
    @Test func opponentStates() {
        func model(_ friends: [CutBattleOpponent] = [], query: String = "", loading: Bool = false, error: String? = nil) -> CutBattleOpponentModel {
            CutCreateBattleLogic.opponents(friends, query: query, selected: nil, loading: loading, error: error)
        }
        #expect(model(loading: true).state == .loading); #expect(model(error: "Fixture error").state == .failed("Fixture error"))
        #expect(model().state == .empty); #expect(model([Self.friend], query: "absent").state == .noResults)
        #expect(model([Self.friend]).state == .loaded)
    }
    @Test func selectedRuleAndRewardsChangeTogether() {
        let m = model(.init(opponentID: Self.friend.id, type: .runningDistance))
        #expect(m.rule == BattleType.runningDistance.description); #expect(m.rewards.map(\.id) == [29,30])
        #expect(m.handle == "@fixture_opponent")
        #expect(CutCompeteFormat.battleTitle(.consistency) == "Workout days")
        #expect(CutCompeteFormat.battleTitle(.workoutCount) == "Workout Count")
    }
    @Test func missingDisplayNameDoesNotRepeatTheHandle() {
        let alias = CutBattleOpponent(id: UUID(), name: "fixture_alias", username: "fixture_alias", avatarURL: nil)
        #expect(alias.title == "@fixture_alias"); #expect(alias.handle == nil)
        #expect(CutCompeteFormat.personName(displayName: " Fixture Display ", username: "fixture_alias") == " Fixture Display ")
        for name in [nil, "", "  "] as [String?] { #expect(CutCompeteFormat.personName(displayName: name, username: "fixture_alias") == "fixture_alias") }
        #expect(CutCreateBattleLogic.model(.init(opponentID: alias.id), opponent: alias, creating: false, unit: .kg).handle == nil)
    }
    private func model(_ draft: CutCreateBattleDraft) -> CutCreateBattleModel {
        CutCreateBattleLogic.model(draft, opponent: Self.friend, creating: false, unit: .kg)
    }
}
