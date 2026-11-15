//
//  CutSocialPeopleModel.swift
//  WRKT
//
//  The pushed Social lists in the Cut language as plain values: Activity (notifications),
//  Friend requests, My friends and Find friends. Every format and decision is a pure function
//  of facts the host reads from the existing view models, so each state can be tested and
//  rendered without the network.
//

import Foundation

// MARK: - Shared

/// One person on a list row: the name on top, at most one supporting line.
struct CutSocialPersonFacts: Equatable {
    var id: UUID
    var username: String
    var displayName: String?
    var avatarURL: String?
    var bio: String? = nil
}

struct CutSocialPersonRow: Equatable, Identifiable {
    /// The row's own id (friendship, request or profile).
    var id: UUID
    /// The profile it opens.
    var profileId: UUID
    var name: String
    var line: String?
    var initials: String
    var avatarURL: String?
    var bio: String? = nil
}

enum CutSocialPeopleLogic {
    /// The display name when there is one, else the handle.
    static func name(_ person: CutSocialPersonFacts) -> String {
        if let name = person.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return "@\(person.username)"
    }

    /// The handle under a display name; nothing when the name already is the handle.
    static func handleLine(_ person: CutSocialPersonFacts) -> String? {
        name(person).hasPrefix("@") ? nil : "@\(person.username)"
    }

    static func row(_ person: CutSocialPersonFacts, id: UUID? = nil, line: String?) -> CutSocialPersonRow {
        CutSocialPersonRow(
            id: id ?? person.id,
            profileId: person.id,
            name: name(person),
            line: line,
            initials: CutSocialLogic.initials(person.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? person.username),
            avatarURL: person.avatarURL
        )
    }

    // MARK: Activity

    enum ActivityDestination: Equatable, Hashable {
        case profile(UUID)
        case post(UUID)
        case battle(UUID)
        case challenge(UUID)
        case programInvite(UUID)
        case missing(String)
    }

    /// Where a notification leads, as the legacy row's NavigationLink. Nil when the target is
    /// missing (the legacy row opened a bare "not found" screen) or the type shows nothing.
    static func destination(type: NotificationType, actorId: UUID, targetId: UUID?) -> ActivityDestination? {
        switch type {
        case .friendRequest, .friendAccepted:
            return .profile(actorId)
        case .postLike, .postComment, .commentReply, .commentMention, .postParticipantTag:
            return targetId.map(ActivityDestination.post) ?? .missing("Post not found")
        case .battleInvite, .battleAccepted, .battleDeclined, .battleLeadTaken, .battleLeadLost,
             .battleOpponentActivity, .battleEndingSoon, .battleCompleted, .battleVictory, .battleDefeat:
            return targetId.map(ActivityDestination.battle) ?? .missing("Battle not found")
        case .challengeInvite, .challengeJoined, .challengeMilestone, .challengeLeaderboardChange,
             .challengeEndingSoon, .challengeCompleted, .challengeNewParticipant:
            return targetId.map(ActivityDestination.challenge) ?? .missing("Challenge not found")
        case .workoutCompleted:
            return targetId.map(ActivityDestination.post) ?? .profile(actorId)
        case .programInvite:
            return targetId.map(ActivityDestination.programInvite) ?? .missing("Program invite not found")
        case .virtualRunInvite, .unknown:
            return nil
        }
    }

    static func activity(
        _ items: [CutActivityFacts]?,
        isLoading: Bool,
        error: String?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> CutActivityModel {
        guard let items else { return CutActivityModel(content: .loading) }
        let visible = items.filter { $0.type.isVisible }
        guard !visible.isEmpty else {
            if isLoading { return CutActivityModel(content: .loading) }
            if let error { return CutActivityModel(content: .failed(error)) }
            return CutActivityModel(content: .empty)
        }
        let rows = visible.sorted { $0.createdAt > $1.createdAt }.map { item in
            CutActivityModel.Row(
                id: item.id,
                initials: CutSocialLogic.initials(item.actorName),
                avatarURL: item.actorAvatarURL,
                message: item.message,
                time: activityTime(item.createdAt, now: now, calendar: calendar, locale: locale),
                isUnread: !item.read,
                opens: destination(type: item.type, actorId: item.actorId, targetId: item.targetId) != nil
            )
        }
        let todayIDs = Set(visible.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }.map(\.id))
        let isToday: (CutActivityModel.Row) -> Bool = { todayIDs.contains($0.id) }
        var sections: [CutActivityModel.Section] = []
        let today = rows.filter(isToday)
        let earlier = rows.filter { !isToday($0) }
        if !today.isEmpty { sections.append(.init(title: "Today", rows: today)) }
        if !earlier.isEmpty { sections.append(.init(title: "Earlier", rows: earlier)) }
        return CutActivityModel(
            content: .sections(sections),
            inlineError: error,
            hasUnread: visible.contains { !$0.read },
            canClear: true
        )
    }

    /// "12 min. ago" today, "Yesterday", the weekday within a week, else "12 Oct".
    static func activityTime(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return CutPostDetailLogic.commentTime(date, now: now, locale: locale)
        }
        return CutCardioLogic.dayLabel(date, now: now, calendar: calendar, locale: locale)
    }

    // MARK: Friend requests

    static func requests(
        incoming: [CutFriendRequestFacts]?,
        outgoing: [CutFriendRequestFacts]?,
        tab: CutFriendRequestsModel.Tab,
        isLoading: Bool,
        error: String?
    ) -> CutFriendRequestsModel {
        let loaded = incoming != nil && !isLoading
        let rows: [CutFriendRequestsModel.Row] = {
            switch tab {
            case .incoming:
                return (incoming ?? []).map { request in
                    .init(person: row(request.person, id: request.id,
                                      line: request.needsReconfirmation ? [handleLine(request.person), "Confirm this friendship to share friends-only activity again."].compactMap { $0 }.joined(separator: "\n") : handleLine(request.person)),
                          acceptTitle: request.needsReconfirmation ? "Confirm" : "Accept")
                }
            case .outgoing:
                return (outgoing ?? []).map { request in
                    .init(person: row(request.person, id: request.id,
                                      line: [handleLine(request.person), request.statusText ?? (request.needsReconfirmation ? "Waiting for friendship confirmation" : "Request pending")].compactMap { $0 }.joined(separator: "\n")),
                          acceptTitle: nil)
                }
            }
        }()
        let content: CutFriendRequestsModel.Content = !loaded ? .loading : (rows.isEmpty ? .empty : .rows(rows))
        return CutFriendRequestsModel(tab: tab, incomingCount: incoming?.count ?? 0, outgoingCount: outgoing?.count ?? 0,
                                      content: content, error: error)
    }

    static func requestTab(afterHorizontalDrag x: Double, vertical y: Double, current: CutFriendRequestsModel.Tab) -> CutFriendRequestsModel.Tab {
        guard abs(x) > 40, abs(x) > abs(y) * 2 else { return current }
        return x < 0 ? .outgoing : .incoming
    }

    static func requestsEmptyLine(_ tab: CutFriendRequestsModel.Tab) -> String {
        tab == .incoming ? "No one is waiting on you." : "You have no requests waiting."
    }

    // MARK: Friends

    static func friends(_ friends: [CutFriendFacts]?, query: String, isLoading: Bool, error: String?,
                        locale: Locale = .current) -> CutFriendsListModel {
        guard let friends, !(isLoading && friends.isEmpty) else { return CutFriendsListModel(content: .loading, showsSearch: false) }
        if let error, friends.isEmpty { return CutFriendsListModel(content: .failed(error), showsSearch: false) }
        guard !friends.isEmpty else { return CutFriendsListModel(content: .empty, showsSearch: false) }
        let search = query
        let matching = search.isEmpty ? friends : friends.filter {
            $0.person.username.localizedCaseInsensitiveContains(search)
                || ($0.person.displayName?.localizedCaseInsensitiveContains(search) ?? false)
        }
        guard !matching.isEmpty else { return CutFriendsListModel(content: .noResults(search), showsSearch: true, inlineError: error) }
        let rows = matching.map { friend in
            row(friend.person, id: friend.id, line: friendLine(friend, locale: locale))
        }
        return CutFriendsListModel(content: .rows(rows), showsSearch: true, count: friends.count, inlineError: error)
    }

    /// "@maria, friends since Oct 2025", or the date alone when the name is the handle.
    static func friendLine(_ friend: CutFriendFacts, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        let since = formatter.string(from: friend.friendsSince)
        if let handle = handleLine(friend.person) { return "\(handle), friends since \(since)" }
        return "Friends since \(since)"
    }

    // MARK: Search

    static func search(query: String, results: [CutSocialPersonFacts], isSearching: Bool, error: String?) -> CutUserSearchModel {
        if isSearching { return CutUserSearchModel(content: .searching) }
        if let error { return CutUserSearchModel(content: .failed(error)) }
        if query.isEmpty { return CutUserSearchModel(content: .idle) }
        if results.isEmpty { return CutUserSearchModel(content: .noResults) }
        return CutUserSearchModel(content: .rows(results.map { person in
            var value = row(person, line: handleLine(person))
            value.bio = person.bio
            return value
        }))
    }
}

// MARK: - Activity

struct CutActivityFacts: Equatable {
    var id: UUID
    var type: NotificationType
    var actorId: UUID
    var actorName: String
    var actorAvatarURL: String?
    var message: String
    var targetId: UUID?
    var createdAt: Date
    var read: Bool
}

struct CutActivityModel: Equatable {
    struct Row: Equatable, Identifiable {
        var id: UUID
        var initials: String
        var avatarURL: String?
        var message: String
        var time: String
        var isUnread: Bool
        /// Has somewhere to go: shows a chevron and opens on tap.
        var opens: Bool
    }

    struct Section: Equatable, Identifiable {
        var title: String
        var rows: [Row]
        var id: String { title }
    }

    enum Content: Equatable {
        case loading
        case failed(String)
        case empty
        case sections([Section])
    }

    var content: Content
    /// A failed refresh, mark or delete while notifications are showing.
    var inlineError: String?
    var hasUnread = false
    var canClear = false
}

// MARK: - Friend requests

struct CutFriendRequestFacts: Equatable {
    var id: UUID
    var person: CutSocialPersonFacts
    var needsReconfirmation = false
    var statusText: String? = nil
}

struct CutFriendRequestsModel: Equatable {
    enum Tab: String, CaseIterable, Hashable {
        case incoming = "Requests"
        case outgoing = "Sent"
    }

    struct Row: Equatable, Identifiable {
        var person: CutSocialPersonRow
        /// "Accept" or "Confirm" on a request to you; nil on one you sent.
        var acceptTitle: String?
        var id: UUID { person.id }
    }

    enum Content: Equatable {
        case loading
        case empty
        case rows([Row])
    }

    var tab: Tab
    var incomingCount: Int
    var outgoingCount: Int
    var content: Content
    var error: String?
}

// MARK: - Friends

struct CutFriendFacts: Equatable {
    /// The friend's id as FriendsListViewModel keys it.
    var id: UUID
    var person: CutSocialPersonFacts
    var friendsSince: Date
}

struct CutFriendsListModel: Equatable {
    enum Content: Equatable {
        case loading
        case failed(String)
        case empty
        case noResults(String)
        case rows([CutSocialPersonRow])
    }

    var content: Content
    var showsSearch: Bool
    var count: Int = 0
    var inlineError: String? = nil
}

// MARK: - Search

struct CutUserSearchModel: Equatable {
    enum Content: Equatable {
        case idle
        case searching
        case failed(String)
        case noResults
        case rows([CutSocialPersonRow])
    }

    var content: Content
}
