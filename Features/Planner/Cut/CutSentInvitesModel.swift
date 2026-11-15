//
//  CutSentInvitesModel.swift
//  WRKT
//
//  Who a program was sent to, with Revoke on invites still waiting. Same data as SentInvitesSheet.
//

import Foundation

struct CutSentInvitesModel: Equatable {
    enum State: Equatable { case loading, empty, loaded }
    struct Row: Equatable, Identifiable {
        var id: UUID
        var name: String
        var initials: String
        var avatarURL: String?
        var status: String
        var canRevoke: Bool
        var revoking: Bool
    }
    var subtitle: String
    var state: State
    var rows: [Row]
}

struct CutSentInviteFacts: Equatable {
    var id: UUID
    var status: ProgramInviteStatus
    var displayName: String?
    var username: String?
    var avatarURL: String?
}

enum CutSentInvitesLogic {
    static func model(programName: String, invites: [CutSentInviteFacts], loading: Bool, revoking: Set<UUID> = []) -> CutSentInvitesModel {
        let rows = invites.map { invite -> CutSentInvitesModel.Row in
            let name = name(displayName: invite.displayName, username: invite.username)
            return .init(id: invite.id, name: name, initials: invite.username == nil && invite.displayName == nil ? "?" : CutCompeteFormat.initials(name.hasPrefix("@") ? String(name.dropFirst()) : name),
                         avatarURL: invite.avatarURL, status: status(invite.status),
                         canRevoke: invite.status == .pending, revoking: revoking.contains(invite.id))
        }
        return .init(subtitle: programName, state: loading ? .loading : rows.isEmpty ? .empty : .loaded, rows: rows)
    }

    /// The legacy sheet named a friend by display name or @username.
    static func name(displayName: String?, username: String?) -> String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        if let username, !username.isEmpty { return "@" + username }
        return "Unknown friend"
    }

    static func status(_ status: ProgramInviteStatus) -> String {
        switch status {
        case .pending: return "Waiting for an answer"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .revoked: return "Revoked"
        case .cancelled: return "Cancelled"
        }
    }

    static let emptyLine = "Nobody has this program yet. Share it to send an invite."
}
