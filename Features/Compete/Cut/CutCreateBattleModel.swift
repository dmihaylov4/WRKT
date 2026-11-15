import Foundation

struct CutCreateBattleDraft: Equatable {
    var opponentID: UUID? = nil
    var type: BattleType = .volume
    var duration = 7
}
struct CutCreateBattleModel: Equatable {
    var opponent: String
    var handle: String?
    var canSend: Bool
    var creating: Bool
    var rule: String
    var rewards: [CutBattleDetailModel.Reward]
}
struct CutBattleOpponent: Equatable, Identifiable {
    var id: UUID
    var name: String
    var username: String
    var avatarURL: String?
    var title: String { name == username ? "@" + username : name }
    var handle: String? { name == username ? nil : "@" + username }
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
    static func model(_ draft: CutCreateBattleDraft, opponent: CutBattleOpponent?, creating: Bool, unit: WeightUnit, locale: Locale = .current) -> CutCreateBattleModel {
        .init(opponent: opponent?.name ?? "Choose Opponent", handle: opponent?.handle,
              canSend: draft.opponentID != nil && opponent?.id == draft.opponentID && types.contains(draft.type) && durations.contains(draft.duration) && !creating,
              creating: creating, rule: draft.type.description,
              rewards: CutBattleDetailLogic.rewards(type: draft.type, target: nil, unit: unit, locale: locale))
    }
    static func opponents(_ friends: [CutBattleOpponent], query: String, selected: UUID?, loading: Bool, error: String?, locale: Locale = .current) -> CutBattleOpponentModel {
        let rows = query.isEmpty ? friends : friends.filter {
            $0.name.range(of: query, options: [.caseInsensitive], locale: locale) != nil || $0.username.range(of: query, options: [.caseInsensitive], locale: locale) != nil
        }
        let state: CutBattleOpponentModel.State = loading ? .loading : error.map { .failed($0) } ?? (friends.isEmpty ? .empty : rows.isEmpty ? .noResults : .loaded)
        return .init(state: state, rows: rows, selectedID: selected)
    }
}
