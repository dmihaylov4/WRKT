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
        #expect(m.rule == "Most running distance logged wins."); #expect(m.rewards.map(\.id) == [29,30])
        #expect(model(.init(opponentID: Self.friend.id)).rule == "Most weight lifted in total wins.")
        #expect(CutCompeteFormat.battleTitle(.consistency) == "Workout days")
        #expect(CutCompeteFormat.battleTitle(.workoutCount) == "Workouts")
        #expect(CutCreateBattleLogic.types.map(CutCompeteFormat.battleTitle) == ["Volume lifted", "Workouts", "Workout days", "Records", "Running distance"])
    }
    @Test func buttonAndFootnoteNameTheOpponent() {
        let m = model(.init(opponentID: Self.friend.id, type: .runningDistance))
        #expect(m.sendTitle == "Challenge Fixture")
        #expect(m.footnote == "Starts when Fixture accepts. The winner earns the \(m.rewards[1].name) plate.")
        let none = CutCreateBattleLogic.model(.init(), opponent: nil, creating: false, unit: .kg)
        #expect(none.sendTitle == "Choose who to challenge"); #expect(!none.canSend)
        #expect(none.footnote.hasPrefix("Starts when they accept."))
    }
    @Test func friendsRowPutsAChosenFriendFromAllFirst() {
        let friends = (0..<10).map { CutBattleOpponent(id: UUID(), name: "Fixture \($0)", username: "fixture_\($0)", avatarURL: nil) }
        #expect(CutCreateBattleLogic.picks(friends, selected: nil).map(\.id) == friends.prefix(8).map(\.id))
        #expect(CutCreateBattleLogic.picks(friends, selected: friends[2]).map(\.id) == friends.prefix(8).map(\.id))
        let late = CutCreateBattleLogic.picks(friends, selected: friends[9])
        #expect(late.count == 8); #expect(late.first?.id == friends[9].id); #expect(late.dropFirst().map(\.id) == friends.prefix(7).map(\.id))
        let m = CutCreateBattleLogic.model(.init(opponentID: friends[9].id), opponent: friends[9], friends: friends, creating: false, unit: .kg)
        #expect(m.selectedID == friends[9].id); #expect(m.friendsState == .loaded)
        #expect(CutCreateBattleLogic.model(.init(), opponent: nil, friends: [], friendsLoading: true, creating: false, unit: .kg).friendsState == .loading)
        #expect(CutCreateBattleLogic.model(.init(), opponent: nil, friends: [], friendsError: "Fixture error", creating: false, unit: .kg).friendsState == .failed("Fixture error"))
    }
    @Test func oneNamePerPerson() {
        let alias = CutBattleOpponent(id: UUID(), name: CutCompeteFormat.personName(displayName: nil, username: "fixture_alias"), username: "fixture_alias", avatarURL: nil)
        #expect(alias.name == "fixture_alias"); #expect(alias.initials == "FA"); #expect(alias.shortName == "fixture_alias")
        #expect(CutCompeteFormat.personName(displayName: " Fixture Display ", username: "fixture_alias") == " Fixture Display ")
        for name in [nil, "", "  "] as [String?] { #expect(CutCompeteFormat.personName(displayName: name, username: "fixture_alias") == "fixture_alias") }
        #expect(CutCreateBattleLogic.model(.init(opponentID: alias.id), opponent: alias, creating: false, unit: .kg).sendTitle == "Challenge fixture_alias")
    }
    private func model(_ draft: CutCreateBattleDraft) -> CutCreateBattleModel {
        CutCreateBattleLogic.model(draft, opponent: Self.friend, creating: false, unit: .kg)
    }
}
