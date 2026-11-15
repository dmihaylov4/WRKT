import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutProgramsLogicTests {
    static func program(_ name: String, active: Bool = false, days: [Int?] = [6, nil, 6, nil, 6, nil, nil], creator: String? = nil, shared: Bool = false) -> CutProgramFacts {
        .init(id: UUID(), name: name, isActive: active, days: days, creatorName: creator, hasBeenShared: shared)
    }

    @Test func activeProgramShowsOnlyInTheTopCard() {
        let active = Self.program("Fixture Full Body", active: true, shared: true)
        let saved = Self.program("Fixture Upper Lower", days: [5, 6, nil, 5, 6, nil, nil])
        let model = CutProgramsLogic.model(library: [saved, active], invites: [])
        #expect(model.active?.id == active.id)
        #expect(model.active?.line == "3 training days a week, 18 exercises")
        #expect(model.active?.showsSentInvites == true)
        #expect(model.saved.map(\.id) == [saved.id])
        #expect(model.saved[0].line == "4 training days a week, 22 exercises")
        #expect(!model.saved[0].showsSentInvites)
        #expect(model.prompt == nil)
    }

    @Test func noActiveProgramShowsTheCalmPrompt() {
        let model = CutProgramsLogic.model(library: [Self.program("Fixture Saved")], invites: [])
        #expect(model.active == nil)
        #expect(model.prompt?.title == "Start a program")
        #expect(model.saved.count == 1)
        let empty = CutProgramsLogic.model(library: [], invites: [])
        #expect(empty.saved.isEmpty); #expect(empty.invites.isEmpty); #expect(empty.prompt != nil)
        #expect(CutProgramsLogic.model(library: [], invites: [], loading: true).loading)
    }

    @Test func linesNameCreatorsAndNonWeeklyCycles() {
        #expect(CutProgramsLogic.line(Self.program("A", days: [4, 4, 4, nil], creator: "Fixture Coach")) == "3 training days, 12 exercises, by Fixture Coach")
        #expect(CutProgramsLogic.line(Self.program("A", days: [1, nil, nil, nil, nil, nil, nil])) == "1 training day a week, 1 exercise")
        #expect(CutProgramsLogic.creatorName(displayName: "Fixture Coach", username: "coach") == "Fixture Coach")
        #expect(CutProgramsLogic.creatorName(displayName: nil, username: "fixture_coach") == "@fixture_coach")
        #expect(CutProgramsLogic.creatorName(displayName: " ", username: nil) == nil)
    }

    @Test func invitesNameTheSender() {
        let invite = CutProgramInviteFacts(id: UUID(), programName: "Fixture PPL", senderDisplayName: "Fixture Friend", senderUsername: "friend")
        let model = CutProgramsLogic.model(library: [], invites: [invite])
        #expect(model.invites[0].line == "Sent by Fixture Friend")
        #expect(model.invites[0].initials == "FF")
        #expect(model.invites[0].spoken == "Fixture PPL, sent by Fixture Friend")
        let anonymous = CutProgramsLogic.invite(.init(id: UUID(), programName: "X", senderDisplayName: nil, senderUsername: nil))
        #expect(anonymous.line == "Sent by a friend"); #expect(anonymous.initials == "?")
        #expect(CutProgramsLogic.invite(.init(id: UUID(), programName: "X", senderDisplayName: nil, senderUsername: "fixture_mate")).line == "Sent by fixture_mate")
    }

    @Test func clearPlanWording() {
        #expect(CutProgramsLogic.clearTitle == "Clear plan?")
        #expect(CutProgramsLogic.clearMessage.contains("stops the program"))
    }
}

@MainActor
@Suite struct CutProgramShareLogicTests {
    static let friends = (0..<10).map { CutBattleOpponent(id: UUID(), name: "Fixture \($0)", username: "fixture_\($0)", avatarURL: nil) }

    @Test func sendNeedsAFriendAndNamesTheCount() {
        let none = CutProgramShareLogic.model(programName: "Full Body", friends: Self.friends, selected: [], loading: false, loadError: nil, sending: false, sendError: nil)
        #expect(none.title == "Share Full Body")
        #expect(none.subtitle == "Friends get a copy. Yours does not change.")
        #expect(!none.canSend); #expect(none.sendTitle == "Choose friends")
        let one = CutProgramShareLogic.model(programName: "X", friends: Self.friends, selected: [Self.friends[0]], loading: false, loadError: nil, sending: false, sendError: nil)
        #expect(one.canSend); #expect(one.sendTitle == "Send to 1 friend")
        #expect(one.picks.filter(\.isSelected).map(\.id) == [Self.friends[0].id])
        let two = CutProgramShareLogic.model(programName: "X", friends: Self.friends, selected: Array(Self.friends.prefix(2)), loading: false, loadError: nil, sending: true, sendError: nil)
        #expect(!two.canSend); #expect(two.sending); #expect(two.sendTitle == "Send to 2 friends")
        let failed = CutProgramShareLogic.model(programName: "X", friends: [], selected: [], loading: false, loadError: "Fixture error", sending: false, sendError: "Fixture send error")
        #expect(failed.friendsState == .failed("Fixture error")); #expect(failed.error == "Fixture send error")
        #expect(CutProgramShareLogic.model(programName: "X", friends: [], selected: [], loading: true, loadError: nil, sending: false, sendError: nil).friendsState == .loading)
        #expect(CutProgramShareLogic.model(programName: "X", friends: [], selected: [], loading: false, loadError: nil, sending: false, sendError: nil).friendsState == .empty)
    }

    @Test func rowPutsFriendsChosenFromAllFirst() {
        #expect(CutProgramShareLogic.picks(Self.friends, selected: []).map(\.id) == Self.friends.prefix(4).map(\.id))
        #expect(CutProgramShareLogic.picks(Self.friends, selected: [Self.friends[1]]).map(\.id) == Self.friends.prefix(4).map(\.id))
        let late = CutProgramShareLogic.picks(Self.friends, selected: [Self.friends[9], Self.friends[8]])
        #expect(late.count == 4)
        #expect(CutProgramShareLogic.picks(Self.friends, selected: Array(Self.friends.suffix(5))).count == 5)
        #expect(Array(late.prefix(2)).map(\.id) == [Self.friends[9].id, Self.friends[8].id])
    }

    @Test func allFriendsMultiSelectAndSearch() {
        let model = CutProgramShareLogic.friends(Self.friends, query: "fixture 1", selected: [Self.friends[1], Self.friends[3]], loading: false, error: nil)
        #expect(model.rows.map(\.id) == [Self.friends[1].id])
        #expect(model.rows[0].isSelected); #expect(model.selectedCount == 2)
        #expect(CutProgramShareLogic.friends(Self.friends, query: "absent", selected: [], loading: false, error: nil).state == .noResults)
    }

    @Test func resultMessageMatchesLegacy() {
        #expect(CutProgramShareLogic.resultMessage(sent: 1, failed: 0) == "Shared with 1 friend.")
        #expect(CutProgramShareLogic.resultMessage(sent: 2, failed: 1) == "Shared with 2 friends. 1 failed.")
    }
}

@MainActor
@Suite struct CutSentInvitesLogicTests {
    @Test func rowsStatusesAndRevoke() {
        let pending = CutSentInviteFacts(id: UUID(), status: .pending, displayName: "Fixture Friend", username: "friend", avatarURL: nil)
        let accepted = CutSentInviteFacts(id: UUID(), status: .accepted, displayName: nil, username: "fixture_mate", avatarURL: nil)
        let unknown = CutSentInviteFacts(id: UUID(), status: .revoked, displayName: nil, username: nil, avatarURL: nil)
        let model = CutSentInvitesLogic.model(programName: "Full Body", invites: [pending, accepted, unknown], loading: false, revoking: [pending.id])
        #expect(model.state == .loaded); #expect(model.subtitle == "Full Body")
        #expect(model.rows.map(\.name) == ["Fixture Friend", "@fixture_mate", "Unknown friend"])
        #expect(model.rows.map(\.canRevoke) == [true, false, false])
        #expect(model.rows[0].revoking)
        #expect(model.rows.map(\.status) == ["Waiting for an answer", "Accepted", "Revoked"])
        #expect(model.rows[2].initials == "?"); #expect(model.rows[1].initials == "FM")
        #expect(CutSentInvitesLogic.status(.declined) == "Declined"); #expect(CutSentInvitesLogic.status(.cancelled) == "Cancelled")
        #expect(CutSentInvitesLogic.model(programName: "X", invites: [], loading: true).state == .loading)
        #expect(CutSentInvitesLogic.model(programName: "X", invites: [], loading: false).state == .empty)
    }
}

@MainActor
@Suite struct CutProgramPreviewLogicTests {
    static func facts(status: ProgramInviteStatus? = .pending, imported: Bool = false, loaded: Bool = true, error: String? = nil, availability: String? = nil) -> CutProgramPreviewFacts {
        .init(loaded: loaded, inviteStatus: status, hasProgram: status == .pending, programName: "Fixture PPL", note: "Try this for eight weeks.",
              senderDisplayName: "Fixture Friend", senderUsername: "friend", senderAvatarURL: nil,
              blocks: status == .pending ? [
                .init(id: UUID(), name: "Push", isRest: false, exerciseNames: ["A", "B", "C", "D"]),
                .init(id: UUID(), name: "Pull", isRest: false, exerciseNames: ["E"]),
                .init(id: UUID(), name: "Rest", isRest: true, exerciseNames: [])
              ] : nil,
              imported: imported, acting: false, availability: availability, error: error)
    }

    @Test func pendingInviteShowsDaysAndActions() {
        let model = CutProgramPreviewLogic.model(Self.facts())
        #expect(model.phase == .invite)
        #expect(model.sender?.name == "Fixture Friend"); #expect(model.sender?.initials == "FF")
        #expect(model.title == "Fixture PPL")
        #expect(model.line == "2 training days, 5 exercises")
        #expect(model.note == "Try this for eight weeks.")
        #expect(model.days.map(\.title) == ["Day 1, Push", "Day 2, Pull", "Day 3, Rest"])
        #expect(model.days.map(\.count) == ["4 exercises", "1 exercise", nil])
        #expect(model.days[0].line == "A, B, C and 1 more")
        #expect(model.days[2].isRest); #expect(model.days[2].line == nil)
        #expect(model.hint != nil)
    }

    @Test func phases() {
        #expect(CutProgramPreviewLogic.model(Self.facts(loaded: false)).phase == .loading)
        #expect(CutProgramPreviewLogic.model(Self.facts(imported: true)).phase == .saved)
        let declined = CutProgramPreviewLogic.model(Self.facts(status: .declined, availability: "This invite was declined."))
        #expect(declined.phase == .unavailable("This invite was declined."))
        #expect(declined.days.isEmpty); #expect(declined.line == nil); #expect(declined.error == nil)
        #expect(declined.title == "Invite unavailable")
        let failed = CutProgramPreviewLogic.model(Self.facts(status: nil, error: "Fixture network error"))
        #expect(failed.phase == .unavailable("Fixture network error"))
        let fallback = CutProgramPreviewLogic.model(Self.facts(status: .accepted))
        #expect(fallback.phase == .unavailable(CutProgramPreviewLogic.unavailableFallback))
        // An action error on a live invite shows above the buttons.
        #expect(CutProgramPreviewLogic.model(Self.facts(error: "Fixture accept error")).error == "Fixture accept error")
    }

    @Test func daySheetLines() {
        let sheet = CutProgramPreviewLogic.daySheet(title: "Day 1, Push", exercises: [(id: UUID(), name: "Fixture Press", sets: 3, reps: 8, weight: nil)], unit: .kg)
        #expect(sheet.rows.map(\.line) == ["3 sets, 8 reps"])
    }
}

@MainActor
@Suite struct CutExerciseEditLogicTests {
    @Test func setupRangesAndWeightMatchTheLegacySheet() {
        var model = CutExerciseEditLogic.model(name: "Fixture", sets: 12, reps: 0, weight: nil, context: .setup, unitLabel: "kg", weightStep: 2.5)
        #expect(model.sets == 10); #expect(model.reps == 1)
        #expect(model.setsRange == 1...10); #expect(model.repsRange == 1...30)
        #expect(model.subtitle == nil)
        CutExerciseEditLogic.stepSets(&model, by: 1); #expect(model.sets == 10); #expect(!model.canRaiseSets)
        CutExerciseEditLogic.stepReps(&model, by: -1); #expect(model.reps == 1); #expect(!model.canLowerReps)
        #expect(CutExerciseEditLogic.savedWeight(model) == nil)
        model.weight = 0
        #expect(CutExerciseEditLogic.savedWeight(model) == 0)
    }

    @Test func inviteRangesAndZeroWeightClears() {
        var model = CutExerciseEditLogic.model(name: "Fixture", sets: 15, reps: 60, weight: 2.5, context: .invite, unitLabel: "kg", weightStep: 2.5)
        #expect(model.sets == 15); #expect(model.reps == 60)
        #expect(model.setsRange == 1...20); #expect(model.repsRange == 1...100)
        #expect(model.subtitle == "Changes apply to your copy.")
        CutExerciseEditLogic.stepWeight(&model, up: false); #expect(model.weight == 0)
        CutExerciseEditLogic.stepWeight(&model, up: false); #expect(model.weight == 0)
        #expect(CutExerciseEditLogic.savedWeight(model) == nil)
        CutExerciseEditLogic.stepWeight(&model, up: true); CutExerciseEditLogic.stepWeight(&model, up: true)
        #expect(model.weight == 5); #expect(CutExerciseEditLogic.savedWeight(model) == 5)
        #expect(model.setsLine == "15 sets"); #expect(model.repsLine == "60 reps")
        #expect(CutExerciseEditLogic.model(name: "X", sets: 1, reps: 1, weight: nil, context: .invite, unitLabel: "lb", weightStep: 0).weightStep == 2.5)
    }
}
