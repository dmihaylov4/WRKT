import Foundation

struct CutCreateBattleDraft: Equatable {
    var opponentID: UUID? = nil
    var type: BattleType = .volume
    var duration = 7
}
struct CutCreateBattleModel: Equatable {
    /// The friends row under "Against", ending in the All circle.
    var picks: [CutBattleOpponent]
    var selectedID: UUID?
    var friendsState: CutBattleOpponentModel.State
    var canSend: Bool
    var creating: Bool
    /// The one rule line under the type grid.
    var rule: String
    /// The one line above the button: when it starts and what the winner earns.
    var footnote: String
    /// "Challenge Yulia", or a prompt while no opponent is chosen.
    var sendTitle: String
    var rewards: [CutBattleDetailModel.Reward]
}
struct CutBattleOpponent: Equatable, Identifiable {
    var id: UUID
    /// The one name shown: display name, or the username when there is no display name.
    var name: String
    var username: String
    var avatarURL: String?
    var initials: String { CutCompeteFormat.initials(name) }
    var shortName: String { CutCompeteFormat.shortName(name) }
}
struct CutBattleOpponentModel: Equatable {
    enum State: Equatable { case loading, failed(String), empty, noResults, loaded }
    var state: State
    var rows: [CutBattleOpponent]
    var selectedID: UUID?
}
enum CutCreateBattleLogic {
    // Exercise battles require an exercise picker before they can be safely created.
    nonisolated static let types: [BattleType] = [.volume, .workoutCount, .consistency, .pr, .runningDistance]
    nonisolated static let durations = [3, 7, 14, 30]
    /// Friends shown in the row before the All circle.
    nonisolated static let pickLimit = 8
    static func model(_ draft: CutCreateBattleDraft, opponent: CutBattleOpponent?, friends: [CutBattleOpponent] = [], friendsLoading: Bool = false,
                      friendsError: String? = nil, creating: Bool, unit: WeightUnit, locale: Locale = .current) -> CutCreateBattleModel {
        let rewards = CutBattleDetailLogic.rewards(type: draft.type, target: nil, unit: unit, locale: locale)
        let winner = rewards.first { $0.title == "Win" }?.name ?? "Plate"
        let who = opponent?.shortName
        return .init(picks: picks(friends, selected: opponent), selectedID: opponent?.id,
                     friendsState: opponents(friends, query: "", selected: opponent?.id, loading: friendsLoading, error: friendsError).state,
                     canSend: draft.opponentID != nil && opponent?.id == draft.opponentID && types.contains(draft.type) && durations.contains(draft.duration) && !creating,
                     creating: creating, rule: CutCompeteFormat.rule(draft.type),
                     footnote: "Starts when \(who ?? "they") \(who == nil ? "accept" : "accepts"). The winner earns the \(winner) plate.",
                     sendTitle: who.map { "Challenge " + $0 } ?? "Choose who to challenge", rewards: rewards)
    }
    /// The friends row: the chosen opponent first when it would not otherwise show, then friends in order.
    static func picks(_ friends: [CutBattleOpponent], selected: CutBattleOpponent?, limit: Int = pickLimit) -> [CutBattleOpponent] {
        var rows = Array(friends.prefix(limit))
        if let selected, !rows.contains(where: { $0.id == selected.id }) {
            rows.insert(selected, at: 0)
            rows = Array(rows.prefix(limit))
        }
        return rows
    }
    static func opponents(_ friends: [CutBattleOpponent], query: String, selected: UUID?, loading: Bool, error: String?, locale: Locale = .current) -> CutBattleOpponentModel {
        let rows = query.isEmpty ? friends : friends.filter {
            $0.name.range(of: query, options: [.caseInsensitive], locale: locale) != nil || $0.username.range(of: query, options: [.caseInsensitive], locale: locale) != nil
        }
        let state: CutBattleOpponentModel.State = loading ? .loading : error.map { .failed($0) } ?? (friends.isEmpty ? .empty : rows.isEmpty ? .noResults : .loaded)
        return .init(state: state, rows: rows, selectedID: selected)
    }
}
