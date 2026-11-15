import Foundation
import Testing
@testable import WRKT

/// Fixtures for the Cut Activity, Friend requests, My friends and Find friends screens.
enum CutSocialPeopleFixtures {
    typealias F = CutSocialFixtures

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func person(_ username: String, _ name: String? = nil) -> CutSocialPersonFacts {
        .init(id: UUID(), username: username, displayName: name)
    }

    static func note(_ type: NotificationType, _ message: String, minutesAgo: Double, read: Bool = false, target: Bool = true) -> CutActivityFacts {
        CutActivityFacts(id: UUID(), type: type, actorId: UUID(), actorName: String(message.split(separator: " ").prefix(2).joined(separator: " ")),
                         message: message, targetId: target ? UUID() : nil,
                         createdAt: F.now.addingTimeInterval(-minutesAgo * 60), read: read)
    }

    static var activity: [CutActivityFacts] {
        [
            note(.postLike, "Alex J. liked your workout", minutesAgo: 12),
            note(.postComment, "Maria K. commented on your workout", minutesAgo: 38),
            note(.battleLeadLost, "Alex J. took the lead in your volume battle", minutesAgo: 120),
            note(.friendRequest, "Nina R. sent you a friend request", minutesAgo: 26 * 60, read: true),
            note(.challengeLeaderboardChange, "You moved to 14th in November 100 km", minutesAgo: 30 * 60, read: true),
            note(.programInvite, "Sam P. shared a program with you", minutesAgo: 3 * 1_440, read: true),
            note(.friendAccepted, "Maria K. accepted your friend request", minutesAgo: 9 * 1_440, read: true)
        ]
    }

    static var longActivity: [CutActivityFacts] {
        [note(.commentMention, "Maximiliana Alexandrova-Fitzgerald Montgomery mentioned you in a comment on a very long post about tempo squats",
              minutesAgo: 3)] + activity
    }

    static var incoming: [CutFriendRequestFacts] {
        [
            .init(id: UUID(), person: person("nina", "Nina R.")),
            .init(id: UUID(), person: person("tomk", "Tom K."), needsReconfirmation: true),
            .init(id: UUID(), person: person("quietlifter"))
        ]
    }

    static var outgoing: [CutFriendRequestFacts] {
        [.init(id: UUID(), person: person("jol", "Jo L."))]
    }

    static var friends: [CutFriendFacts] {
        [
            ("maria", "Maria K."), ("alex", "Alex J."), ("samp", "Sam P."), ("elena", "Elena B."), ("rui", nil),
            ("maxi", "Maximiliana Alexandrova-Fitzgerald Montgomery")
        ].enumerated().map { index, pair in
            CutFriendFacts(id: UUID(), person: person(pair.0, pair.1), friendsSince: F.now.addingTimeInterval(-Double(index + 1) * 40 * 86_400))
        }
    }

    static var searchResults: [CutSocialPersonFacts] {
        [person("nina", "Nina R."), person("ninot", "Nino T."), person("anina")]
    }
}

struct CutSocialPeopleLogicTests {
    private typealias P = CutSocialPeopleFixtures
    private typealias F = CutSocialFixtures

    // MARK: Names

    @Test func nameFallsBackToTheHandle() {
        #expect(CutSocialPeopleLogic.name(P.person("nina", "Nina R.")) == "Nina R.")
        #expect(CutSocialPeopleLogic.name(P.person("quiet", "  ")) == "@quiet")
        #expect(CutSocialPeopleLogic.handleLine(P.person("nina", "Nina R.")) == "@nina")
        #expect(CutSocialPeopleLogic.handleLine(P.person("quiet")) == nil)
        #expect(CutSocialPeopleLogic.row(P.person("quiet"), line: nil).initials == "Q")
    }

    // MARK: Activity

    @Test func activityGroupsTodayAndEarlierNewestFirst() {
        let model = CutSocialPeopleLogic.activity(P.activity, isLoading: false, error: nil, now: F.now, calendar: P.calendar, locale: F.locale)
        guard case let .sections(sections) = model.content else { Issue.record("Expected sections"); return }
        #expect(sections.map(\.title) == ["Today", "Earlier"])
        #expect(sections[0].rows.count == 3)
        let allUnread = sections[0].rows.allSatisfy { $0.isUnread }
        #expect(allUnread)
        #expect(sections[1].rows[0].time == "Yesterday")
        #expect(model.hasUnread)
        #expect(model.canClear)
    }

    @Test func activityStates() {
        #expect(CutSocialPeopleLogic.activity(nil, isLoading: false, error: nil, now: F.now).content == .loading)
        #expect(CutSocialPeopleLogic.activity([], isLoading: true, error: nil, now: F.now).content == .loading)
        #expect(CutSocialPeopleLogic.activity([], isLoading: false, error: "Offline", now: F.now).content == .failed("Offline"))
        #expect(CutSocialPeopleLogic.activity([], isLoading: false, error: nil, now: F.now).content == .empty)
        let withError = CutSocialPeopleLogic.activity(P.activity, isLoading: false, error: "Could not delete", now: F.now)
        #expect(withError.inlineError == "Could not delete")
    }

    @Test func retiredNotificationsAreHidden() {
        let hidden = [P.note(.virtualRunInvite, "Old invite", minutesAgo: 5), P.note(.unknown, "Unknown", minutesAgo: 6)]
        #expect(CutSocialPeopleLogic.activity(hidden, isLoading: false, error: nil, now: F.now).content == .empty)
    }

    @Test func destinationsMatchTheLegacyRows() {
        let actor = UUID(), target = UUID()
        #expect(CutSocialPeopleLogic.destination(type: .friendRequest, actorId: actor, targetId: target) == .profile(actor))
        #expect(CutSocialPeopleLogic.destination(type: .postComment, actorId: actor, targetId: target) == .post(target))
        #expect(CutSocialPeopleLogic.destination(type: .postComment, actorId: actor, targetId: nil) == nil)
        #expect(CutSocialPeopleLogic.destination(type: .battleVictory, actorId: actor, targetId: target) == .battle(target))
        #expect(CutSocialPeopleLogic.destination(type: .challengeMilestone, actorId: actor, targetId: target) == .challenge(target))
        #expect(CutSocialPeopleLogic.destination(type: .workoutCompleted, actorId: actor, targetId: nil) == .profile(actor))
        #expect(CutSocialPeopleLogic.destination(type: .workoutCompleted, actorId: actor, targetId: target) == .post(target))
        #expect(CutSocialPeopleLogic.destination(type: .programInvite, actorId: actor, targetId: target) == .programInvite(target))
        #expect(CutSocialPeopleLogic.destination(type: .virtualRunInvite, actorId: actor, targetId: target) == nil)
    }

    @Test func rowsWithoutADestinationDoNotOpen() {
        let model = CutSocialPeopleLogic.activity([P.note(.postLike, "Alex J. liked your workout", minutesAgo: 1, target: false)],
                                                  isLoading: false, error: nil, now: F.now)
        guard case let .sections(sections) = model.content else { Issue.record("Expected sections"); return }
        #expect(sections[0].rows[0].opens == false)
    }

    // MARK: Requests

    @Test func incomingRequestsAcceptOrConfirm() {
        let model = CutSocialPeopleLogic.requests(incoming: P.incoming, outgoing: P.outgoing, tab: .incoming, isLoading: false, error: nil)
        guard case let .rows(rows) = model.content else { Issue.record("Expected rows"); return }
        #expect(rows.map(\.person.name) == ["Nina R.", "Tom K.", "@quietlifter"])
        #expect(rows.map(\.acceptTitle) == ["Accept", "Confirm", "Accept"])
        #expect(rows[0].person.line == "@nina")
        #expect(rows[1].person.line == "Confirm to share friends-only activity again")
        #expect(rows[2].person.line == nil)
        #expect(model.incomingCount == 3 && model.outgoingCount == 1)
    }

    @Test func sentRequestsCanOnlyBeCancelled() {
        let model = CutSocialPeopleLogic.requests(incoming: P.incoming, outgoing: P.outgoing, tab: .outgoing, isLoading: false, error: nil)
        guard case let .rows(rows) = model.content else { Issue.record("Expected rows"); return }
        #expect(rows.map(\.acceptTitle) == [nil])
        #expect(rows[0].person.line == "Request pending")
    }

    @Test func requestStates() {
        #expect(CutSocialPeopleLogic.requests(incoming: nil, outgoing: nil, tab: .incoming, isLoading: true, error: nil).content == .loading)
        #expect(CutSocialPeopleLogic.requests(incoming: [], outgoing: [], tab: .outgoing, isLoading: false, error: nil).content == .empty)
        let failed = CutSocialPeopleLogic.requests(incoming: [], outgoing: [], tab: .incoming, isLoading: false, error: "Failed to load requests")
        #expect(failed.error == "Failed to load requests")
        #expect(failed.content == .empty)
    }

    // MARK: Friends

    @Test func friendsFilterByNameOrHandle() {
        let all = CutSocialPeopleLogic.friends(P.friends, query: "", isLoading: false, error: nil, locale: F.locale)
        guard case let .rows(rows) = all.content else { Issue.record("Expected rows"); return }
        #expect(rows.count == 6)
        #expect(rows[0].line?.hasPrefix("@maria, friends since") == true)
        #expect(rows[4].name == "@rui")
        #expect(rows[4].line?.hasPrefix("Friends since") == true)
        #expect(all.showsSearch)
        let filtered = CutSocialPeopleLogic.friends(P.friends, query: "ALEX", isLoading: false, error: nil)
        guard case let .rows(matches) = filtered.content else { Issue.record("Expected rows"); return }
        #expect(matches.map(\.name) == ["Alex J.", "Maximiliana Alexandrova-Fitzgerald Montgomery"])
        #expect(CutSocialPeopleLogic.friends(P.friends, query: "zz", isLoading: false, error: nil).content == .noResults("zz"))
    }

    @Test func friendsStates() {
        #expect(CutSocialPeopleLogic.friends(nil, query: "", isLoading: false, error: nil).content == .loading)
        #expect(CutSocialPeopleLogic.friends([], query: "", isLoading: true, error: nil).content == .loading)
        let failed = CutSocialPeopleLogic.friends([], query: "", isLoading: false, error: "Failed to load friends")
        #expect(failed.content == .failed("Failed to load friends"))
        #expect(failed.showsSearch == false)
        #expect(CutSocialPeopleLogic.friends([], query: "", isLoading: false, error: nil).content == .empty)
    }

    // MARK: Search

    @Test func searchStates() {
        #expect(CutSocialPeopleLogic.search(query: "", results: [], isSearching: false, error: nil).content == .idle)
        #expect(CutSocialPeopleLogic.search(query: "ni", results: [], isSearching: true, error: nil).content == .searching)
        #expect(CutSocialPeopleLogic.search(query: "ni", results: [], isSearching: false, error: "Search failed").content == .failed("Search failed"))
        #expect(CutSocialPeopleLogic.search(query: "ni", results: [], isSearching: false, error: nil).content == .noResults)
        guard case let .rows(rows) = CutSocialPeopleLogic.search(query: "nin", results: P.searchResults, isSearching: false, error: nil).content
        else { Issue.record("Expected rows"); return }
        #expect(rows.map(\.name) == ["Nina R.", "Nino T.", "@anina"])
        #expect(rows.map(\.line) == ["@nina", "@ninot", nil])
    }
}
