//
//  CutProgramShareModel.swift
//  WRKT
//
//  The share sheet: friends as a row of avatars with multi-select, an optional note and one send
//  button. Sending goes through ProgramShareViewModel exactly as the legacy sheet did.
//

import Foundation

struct CutProgramShareModel: Equatable {
    struct Pick: Equatable, Identifiable {
        var friend: CutBattleOpponent
        var isSelected: Bool
        var id: UUID { friend.id }
    }
    var title: String
    var subtitle: String
    var picks: [Pick]
    var friendsState: CutBattleOpponentModel.State
    var selectedCount: Int
    var sendTitle: String
    var canSend: Bool
    var sending: Bool
    var error: String?
}

struct CutProgramFriendsModel: Equatable {
    struct Row: Equatable, Identifiable {
        var friend: CutBattleOpponent
        var isSelected: Bool
        var id: UUID { friend.id }
    }
    var state: CutBattleOpponentModel.State
    var rows: [Row]
    var selectedCount: Int
}

enum CutProgramShareLogic {
    /// Friends shown in the row before the All circle: four, so All stays on screen.
    nonisolated static let pickLimit = 4

    static func model(programName: String, friends: [CutBattleOpponent], selected: [CutBattleOpponent], loading: Bool,
                      loadError: String?, sending: Bool, sendError: String?) -> CutProgramShareModel {
        let ids = Set(selected.map(\.id))
        let count = selected.count
        return .init(
            title: "Share \(programName)",
            subtitle: "Friends get a copy. Yours does not change.",
            picks: picks(friends, selected: selected).map { .init(friend: $0, isSelected: ids.contains($0.id)) },
            friendsState: CutCreateBattleLogic.opponents(friends, query: "", selected: nil, loading: loading, error: loadError).state,
            selectedCount: count,
            sendTitle: sendTitle(count),
            canSend: count > 0 && !sending,
            sending: sending,
            error: sendError
        )
    }

    static func sendTitle(_ count: Int) -> String {
        switch count {
        case 0: return "Choose friends"
        case 1: return "Send to 1 friend"
        default: return "Send to \(count) friends"
        }
    }

    /// The avatar row: chosen friends that would not otherwise show come first, then friends in order.
    static func picks(_ friends: [CutBattleOpponent], selected: [CutBattleOpponent], limit: Int = pickLimit) -> [CutBattleOpponent] {
        let head = Array(friends.prefix(limit))
        let missing = selected.filter { pick in !head.contains { $0.id == pick.id } }
        return Array((missing + head).prefix(max(limit, missing.count)))
    }

    static func friends(_ friends: [CutBattleOpponent], query: String, selected: [CutBattleOpponent], loading: Bool, error: String?) -> CutProgramFriendsModel {
        let base = CutCreateBattleLogic.opponents(friends, query: query, selected: nil, loading: loading, error: error)
        let ids = Set(selected.map(\.id))
        return .init(state: base.state, rows: base.rows.map { .init(friend: $0, isSelected: ids.contains($0.id)) }, selectedCount: selected.count)
    }

    /// The legacy result message.
    static func resultMessage(sent: Int, failed: Int) -> String {
        let base = "Shared with \(sent) \(sent == 1 ? "friend" : "friends")."
        return failed == 0 ? base : base + " \(failed) failed."
    }
}
