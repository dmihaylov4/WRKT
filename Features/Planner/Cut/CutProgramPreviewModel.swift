//
//  CutProgramPreviewModel.swift
//  WRKT
//
//  A program a friend sent: who sent it, its days, and Start, Save for later or Decline.
//  The actions are ProgramInviteViewModel's: accept (save), accept then activate (start), decline.
//

import Foundation

struct CutProgramPreviewFacts: Equatable {
    struct Block: Equatable {
        var id: UUID
        var name: String
        var isRest: Bool
        var exerciseNames: [String]
    }
    var loaded: Bool
    var inviteStatus: ProgramInviteStatus?
    var hasProgram: Bool
    var programName: String?
    var note: String?
    var senderDisplayName: String?
    var senderUsername: String?
    var senderAvatarURL: String?
    /// The preview copy's days, nil when the program could not be read.
    var blocks: [Block]?
    /// The invite has been accepted here and the copy is in the library.
    var imported: Bool
    var acting: Bool
    var availability: String?
    var error: String?
}

struct CutProgramPreviewModel: Equatable {
    enum Phase: Equatable {
        case loading
        /// Pending: Start this program, Save for later, Decline.
        case invite
        /// Saved to the library: Start this program, Done.
        case saved
        case unavailable(String)
    }
    struct Sender: Equatable {
        var name: String
        var initials: String
        var avatarURL: String?
    }
    struct Day: Equatable, Identifiable {
        var id: UUID
        var title: String
        var count: String?
        var line: String?
        var isRest: Bool
    }
    var phase: Phase
    var sender: Sender?
    var title: String
    var line: String?
    var note: String?
    var days: [Day]
    var hint: String?
    var acting: Bool
    var error: String?
}

enum CutProgramPreviewLogic {
    static let unavailableFallback = "This program invite is no longer available."

    static func model(_ facts: CutProgramPreviewFacts) -> CutProgramPreviewModel {
        let sender: CutProgramPreviewModel.Sender? = (facts.senderDisplayName != nil || facts.senderUsername != nil) ? {
            let name = CutProgramsLogic.senderName(displayName: facts.senderDisplayName, username: facts.senderUsername)
            return .init(name: name, initials: CutCompeteFormat.initials(name), avatarURL: facts.senderAvatarURL)
        }() : nil
        let phase: CutProgramPreviewModel.Phase
        if facts.imported {
            phase = .saved
        } else if !facts.loaded {
            phase = .loading
        } else if facts.inviteStatus == .pending, facts.hasProgram, facts.blocks != nil {
            phase = .invite
        } else {
            phase = .unavailable(facts.availability ?? facts.error ?? unavailableFallback)
        }
        let blocks = facts.blocks ?? []
        let showsDays: Bool = {
            switch phase {
            case .invite, .saved: return true
            case .loading, .unavailable: return false
            }
        }()
        let training = blocks.filter { !$0.isRest }
        let exercises = training.reduce(0) { $0 + $1.exerciseNames.count }
        return .init(
            phase: phase,
            sender: sender,
            title: { if case .unavailable = phase { return "Invite unavailable" }; return facts.programName ?? "Program" }(),
            line: showsDays ? "\(training.count) training \(training.count == 1 ? "day" : "days"), \(exercises) \(exercises == 1 ? "exercise" : "exercises")" : nil,
            note: showsDays ? facts.note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } : nil,
            days: showsDays ? blocks.enumerated().map { index, block in day(block, index: index) } : [],
            hint: showsDays ? "Tap a day to change it. Drag a day to move it." : nil,
            acting: facts.acting,
            // An unavailable invite already says why; other errors show above the buttons.
            error: showsDays ? facts.error : nil
        )
    }

    static func day(_ block: CutProgramPreviewFacts.Block, index: Int) -> CutProgramPreviewModel.Day {
        let count = block.exerciseNames.count
        return .init(id: block.id, title: "Day \(index + 1), \(block.isRest ? "Rest" : block.name)",
                     count: block.isRest ? nil : "\(count) \(count == 1 ? "exercise" : "exercises")",
                     line: block.isRest ? nil : CutPlanSetupLogic.exerciseSummary(block.exerciseNames),
                     isRest: block.isRest)
    }

    /// The day sheet for one block: its exercises with sets, reps and weight.
    struct DaySheet: Equatable {
        struct Row: Equatable, Identifiable {
            var id: UUID
            var name: String
            var line: String
        }
        var title: String
        var rows: [Row]
    }

    static func daySheet(title: String, exercises: [(id: UUID, name: String, sets: Int, reps: Int, weight: Double?)], unit: WeightUnit) -> DaySheet {
        .init(title: title, rows: exercises.map {
            .init(id: $0.id, name: $0.name, line: CutPlanSetupLogic.exerciseLine(sets: $0.sets, reps: $0.reps, weight: $0.weight, unit: unit))
        })
    }
}
