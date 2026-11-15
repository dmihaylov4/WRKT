//
//  CutProgramsModel.swift
//  WRKT
//
//  The Cut Programs screen: the active program as one lime card, programs friends sent,
//  and the saved library. Same data as ProgramLibraryView.
//

import Foundation

/// Plain facts about one saved program, read from a WorkoutSplit by the host.
struct CutProgramFacts: Equatable, Identifiable {
    var id: UUID
    var name: String
    var isActive: Bool
    /// One entry per day in the cycle: nil for a rest day, otherwise its exercise count.
    var days: [Int?]
    var creatorName: String?
    var hasBeenShared: Bool
}

/// A pending program invite, as ProgramLibraryViewModel lists it.
struct CutProgramInviteFacts: Equatable, Identifiable {
    var id: UUID
    var programName: String
    var senderDisplayName: String?
    var senderUsername: String?
}

struct CutProgramsModel: Equatable {
    struct Program: Equatable, Identifiable {
        var id: UUID
        var name: String
        var line: String
        /// Sent invites appear in the more menu once the program has been shared.
        var showsSentInvites: Bool
    }
    struct Invite: Equatable, Identifiable {
        var id: UUID
        var programName: String
        var initials: String
        var line: String
        var spoken: String
    }
    var active: Program?
    var invites: [Invite]
    var saved: [Program]
    var loading: Bool
    /// Shown in place of the active card when no program is running.
    var prompt: (title: String, line: String)? {
        active == nil ? ("Start a program", "Pick a split and your training days.") : nil
    }
}

enum CutProgramsLogic {
    static func model(library: [CutProgramFacts], invites: [CutProgramInviteFacts], loading: Bool = false) -> CutProgramsModel {
        let active = library.first(where: \.isActive)
        return .init(
            active: active.map(program),
            invites: invites.map(invite),
            // The active program shows only in the top card.
            saved: library.filter { $0.id != active?.id }.map(program),
            loading: loading
        )
    }

    static func program(_ facts: CutProgramFacts) -> CutProgramsModel.Program {
        .init(id: facts.id, name: facts.name, line: line(facts), showsSentInvites: facts.hasBeenShared)
    }

    /// "3 training days a week, 18 exercises, by Yulia". A cycle that is not a week drops "a week".
    static func line(_ facts: CutProgramFacts) -> String {
        let training = facts.days.compactMap { $0 }.count
        let exercises = facts.days.compactMap { $0 }.reduce(0, +)
        var text = "\(training) training \(training == 1 ? "day" : "days")"
        if facts.days.count == 7 { text += " a week" }
        text += ", \(exercises) \(exercises == 1 ? "exercise" : "exercises")"
        if let creator = facts.creatorName, !creator.isEmpty { text += ", by \(creator)" }
        return text
    }

    /// The creator line the legacy row showed: display name, or @username.
    static func creatorName(displayName: String?, username: String?) -> String? {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        if let username, !username.isEmpty { return "@" + username }
        return nil
    }

    static func senderName(displayName: String?, username: String?) -> String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return "a friend"
    }

    static func invite(_ facts: CutProgramInviteFacts) -> CutProgramsModel.Invite {
        let sender = senderName(displayName: facts.senderDisplayName, username: facts.senderUsername)
        return .init(id: facts.id, programName: facts.programName,
                     initials: sender == "a friend" ? "?" : CutCompeteFormat.initials(sender),
                     line: "Sent by \(sender)", spoken: "\(facts.programName), sent by \(sender)")
    }

    /// The clear plan confirmation. deleteAllPlannedWorkouts also stops the active program.
    static let clearTitle = "Clear plan?"
    static let clearButton = "Clear plan"
    static let clearMessage = "This removes every planned workout from the calendar and stops the program. Your saved programs stay."
}
