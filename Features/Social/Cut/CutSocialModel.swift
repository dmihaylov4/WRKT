//
//  CutSocialModel.swift
//  WRKT
//
//  The Social tab in the Cut language as plain values: the header, the feed with its posts
//  and arena, and the Friends pane. Every format and decision is a pure function of facts the
//  host reads from the existing Social stores, so each state can be tested and rendered
//  without the network.
//

import Foundation

// MARK: - Facts (what the host reads)

/// One post as the host reads it from `PostWithAuthor`. Plain values only.
struct CutSocialPostFacts: Equatable {
    struct Person: Equatable {
        var id: UUID
        var name: String
        var avatarURL: String?
    }

    enum Kind: Equatable {
        /// One app or Health strength session.
        case strength(name: String, volumeKg: Double, sets: Int, durationSeconds: Double?)
        /// One cardio session; distance in metres, zero when the activity has none.
        case cardio(name: String, distanceMeters: Double, durationSeconds: Int?, calories: Double?, averageHeartRate: Double?)
        /// Several workouts in one post.
        case multi(count: Int, cardioCount: Int, volumeKg: Double, sets: Int, durationSeconds: Double?)
        case weekly(weekStart: Date, strengthDone: Int, strengthTarget: Int, activeMinutesDone: Int, activeMinutesTarget: Int, streak: Int)
        case battle(won: Bool, myName: String?, myScore: Double, opponentName: String, opponentScore: Double, unit: String)
    }

    enum Visibility: Equatable { case everyone, friends, onlyMe }

    var id: UUID
    var author: Person
    /// The partner on a post shared by two people, if they are still on it.
    var partner: Person?
    var createdAt: Date
    var caption: String?
    var visibility: Visibility = .everyone
    var kind: Kind
    var likes: Int = 0
    var comments: Int = 0
    var isLiked = false
    var isOwn = false
    var canRemoveMe = false
}

/// One active battle or challenge for the arena strip.
enum CutSocialArenaFacts: Equatable {
    case battle(id: UUID, opponentName: String, userScore: Double, opponentScore: Double, unit: String)
    case challenge(id: UUID, title: String, percent: Int)
}

/// One friend for the Friends pane.
struct CutSocialFriendFacts: Equatable {
    var id: UUID
    var name: String
    var avatarURL: String?
    var lastWorkout: Date?
    var workoutsThisWeek: Int = 0
}

// MARK: - Display values

struct CutSocialStat: Equatable, Hashable {
    var value: String
    var label: String
    /// The winning side of a battle result.
    var isHighlighted = false
}

struct CutSocialPostRow: Equatable, Identifiable {
    struct Person: Equatable {
        var id: UUID
        var name: String
        var initials: String
        var avatarURL: String?
    }

    enum Action: Hashable {
        case edit, delete, removeMe, likes, report
    }

    var id: UUID
    var author: Person
    var partner: Person?
    /// "Sam P." or "Sam P. and Nina R."
    var names: String
    /// The one line under the name: "42 min. ago", plus the partner or "only you" when it matters.
    var timeLine: String
    var caption: String?
    var title: String
    var stats: [CutSocialStat]
    var likes: Int
    var comments: Int
    var isLiked: Bool
    /// Items in the more menu, in order. Share is always there.
    var menu: [Action]
    var showsMedia: Bool
}

struct CutSocialArenaItem: Equatable, Identifiable {
    enum Target: Hashable {
        case battle(UUID)
        case challenge(UUID)
    }

    var target: Target
    var label: String
    var value: String
    /// The lime share of the bar: your part of the battle, or the challenge progress.
    var fraction: Double
    var isLeading: Bool

    var id: Target { target }
}

struct CutSocialFeedModel: Equatable {
    enum Content: Equatable {
        case loading
        case failed(title: String, message: String, canRetry: Bool)
        case empty
        case posts([CutSocialPostRow])
    }

    var content: Content
    var newPosts: Int = 0
    var arena: [CutSocialArenaItem] = []
    /// Offline: the number of queued actions; nil when online.
    var offlineQueue: Int?
    /// An error while posts are already showing (refresh or next page).
    var inlineError: String?
    var isLoadingMore = false
    var reachedEnd = false
}

struct CutSocialHeaderModel: Equatable {
    var notifications: Int = 0
    var friendRequests: Int = 0
    var avatarURL: String?
    var initials: String?
    var showsProfile = true
}

struct CutSocialFriendsModel: Equatable {
    struct Row: Equatable, Identifiable {
        var id: UUID
        var name: String
        var initials: String
        var avatarURL: String?
        var line: String
    }

    var requests: Int
    var activeNow: [Row]
    /// Nil until the friends list has loaded.
    var friendsCount: Int?
}

// MARK: - Logic

enum CutSocialLogic {
    // MARK: Feed state

    /// What the feed shows. Mirrors FeedView: skeletons while the first page loads, the error
    /// only when nothing is loaded, the empty state only after a load finished with no posts.
    static func content(
        hasViewModel: Bool,
        isLoading: Bool,
        error: (title: String, message: String, canRetry: Bool)?,
        rows: [CutSocialPostRow]
    ) -> CutSocialFeedModel.Content {
        guard hasViewModel else { return .loading }
        if rows.isEmpty {
            if isLoading { return .loading }
            if let error { return .failed(title: error.title, message: error.message, canRetry: error.canRetry) }
            return .empty
        }
        return .posts(rows)
    }

    /// The error shown above posts that are already on screen.
    static func inlineError(message: String?, postCount: Int) -> String? {
        postCount > 0 ? message : nil
    }

    static func newPostsLabel(_ count: Int) -> String {
        count == 1 ? "1 new post" : "\(count) new posts"
    }

    static func offlineLine(queued: Int) -> String {
        switch queued {
        case ..<1: "Showing saved posts"
        case 1: "1 action waiting to sync"
        default: "\(queued) actions waiting to sync"
        }
    }

    // MARK: Posts

    static func row(_ facts: CutSocialPostFacts, now: Date, weightUnit: WeightUnit = .kg, locale: Locale = .current) -> CutSocialPostRow {
        let author = person(facts.author)
        let partner = facts.partner.map(person)
        let names = partner.map { "\(author.name) and \($0.name)" } ?? author.name
        let (title, stats) = summary(facts.kind, isOwn: facts.isOwn, authorName: facts.author.name, weightUnit: weightUnit, locale: locale)
        return CutSocialPostRow(
            id: facts.id,
            author: author,
            partner: partner,
            names: names,
            timeLine: timeLine(createdAt: facts.createdAt, now: now, visibility: facts.visibility, locale: locale),
            caption: cleanCaption(facts.caption),
            title: title,
            stats: stats,
            likes: facts.likes,
            comments: facts.comments,
            isLiked: facts.isLiked,
            menu: menu(for: facts),
            showsMedia: showsMedia(facts.kind)
        )
    }

    static func person(_ person: CutSocialPostFacts.Person) -> CutSocialPostRow.Person {
        .init(id: person.id, name: person.name, initials: initials(person.name), avatarURL: person.avatarURL)
    }

    /// Up to two initials: "Maria K." -> "MK", "sam" -> "S".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" })
        return words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    static func cleanCaption(_ caption: String?) -> String? {
        guard let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func timeLine(createdAt: Date, now: Date, visibility: CutSocialPostFacts.Visibility, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        let relative = now.timeIntervalSince(createdAt) < 60 ? "Just now" : formatter.localizedString(for: createdAt, relativeTo: now)
        return visibility == .onlyMe ? "\(relative), only you" : relative
    }

    /// The more menu: own posts can be edited and deleted, a partner can leave a shared post,
    /// anyone can see who liked it, and other people's posts can be reported.
    static func menu(for facts: CutSocialPostFacts) -> [CutSocialPostRow.Action] {
        var actions: [CutSocialPostRow.Action] = []
        if facts.isOwn { actions += [.edit, .delete] }
        if facts.canRemoveMe { actions.append(.removeMe) }
        if facts.likes > 0 { actions.append(.likes) }
        if !facts.isOwn { actions.append(.report) }
        return actions
    }

    static func menuLabel(_ action: CutSocialPostRow.Action) -> String {
        switch action {
        case .edit: "Edit post"
        case .delete: "Delete post"
        case .removeMe: "Remove me from post"
        case .likes: "See likes"
        case .report: "Report post"
        }
    }

    static func isDestructive(_ action: CutSocialPostRow.Action) -> Bool {
        action == .delete || action == .removeMe || action == .report
    }

    /// Weekly progress and battle results carry no photos or maps.
    static func showsMedia(_ kind: CutSocialPostFacts.Kind) -> Bool {
        switch kind {
        case .weekly, .battle: false
        default: true
        }
    }

    static func likeAccessibility(likes: Int, isLiked: Bool) -> String {
        let count = likes == 1 ? "1 like" : "\(likes) likes"
        return isLiked ? "Unlike, \(count)" : "Like, \(count)"
    }

    static func commentAccessibility(_ comments: Int) -> String {
        comments == 1 ? "Comments, 1 comment" : "Comments, \(comments) comments"
    }

    // MARK: Summaries

    /// The condensed title and up to three stat columns for a post.
    static func summary(
        _ kind: CutSocialPostFacts.Kind,
        isOwn: Bool,
        authorName: String,
        weightUnit: WeightUnit,
        locale: Locale
    ) -> (String, [CutSocialStat]) {
        switch kind {
        case let .strength(name, volumeKg, sets, duration):
            return (name, strengthStats(volumeKg: volumeKg, sets: sets, duration: duration, weightUnit: weightUnit, locale: locale))

        case let .cardio(name, distance, duration, calories, heartRate):
            var stats: [CutSocialStat] = []
            if distance > 0 {
                stats.append(.init(value: distanceKm(distance), label: "km"))
                if let duration { stats.append(.init(value: clock(Double(duration)), label: "time")) }
                if let duration, duration > 0 {
                    stats.append(.init(value: pace(secondsPerKm: Double(duration) / (distance / 1000)), label: "/km"))
                }
            } else {
                if let duration { stats.append(.init(value: clock(Double(duration)), label: "time")) }
                if let calories, calories > 0 { stats.append(.init(value: grouped(calories, locale: locale), label: "kcal")) }
                if let heartRate, heartRate > 0 { stats.append(.init(value: "\(Int(heartRate.rounded()))", label: "avg bpm")) }
            }
            return (name, stats)

        case let .multi(count, cardioCount, volumeKg, sets, duration):
            let title = cardioCount == 0 ? "\(count) workouts" : (cardioCount == count ? "\(count) sessions" : "Strength and cardio")
            var stats: [CutSocialStat] = []
            if volumeKg > 0 { stats.append(volumeStat(volumeKg, weightUnit: weightUnit, locale: locale)) }
            if cardioCount == 0, sets > 0 {
                stats.append(.init(value: "\(sets)", label: sets == 1 ? "set" : "sets"))
            } else {
                stats.append(.init(value: "\(count)", label: "workouts"))
            }
            if let duration { stats.append(.init(value: clock(duration), label: "duration")) }
            return (title, Array(stats.prefix(3)))

        case let .weekly(weekStart, strengthDone, strengthTarget, minutesDone, minutesTarget, streak):
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return ("Week of \(formatter.string(from: weekStart))", [
                .init(value: "\(strengthDone)/\(strengthTarget)", label: "strength days"),
                .init(value: "\(minutesDone)/\(minutesTarget)", label: "active min"),
                .init(value: "\(streak)", label: "week streak")
            ])

        case let .battle(won, myName, myScore, opponentName, opponentScore, unit):
            let poster = isOwn ? "You" : firstName(myName ?? authorName)
            let title = won ? "\(poster) won" : "\(poster) lost"
            return (title, [
                .init(value: score(myScore, unit: unit, weightUnit: weightUnit, locale: locale),
                      label: isOwn ? "You" : firstName(myName ?? authorName), isHighlighted: won),
                .init(value: score(opponentScore, unit: unit, weightUnit: weightUnit, locale: locale),
                      label: firstName(opponentName), isHighlighted: !won)
            ])
        }
    }

    static func strengthStats(volumeKg: Double, sets: Int, duration: Double?, weightUnit: WeightUnit, locale: Locale) -> [CutSocialStat] {
        var stats: [CutSocialStat] = []
        if volumeKg > 0 { stats.append(volumeStat(volumeKg, weightUnit: weightUnit, locale: locale)) }
        if sets > 0 { stats.append(.init(value: "\(sets)", label: sets == 1 ? "set" : "sets")) }
        if let duration, duration > 0 { stats.append(.init(value: clock(duration), label: "duration")) }
        return stats
    }

    static func volumeStat(_ kg: Double, weightUnit: WeightUnit, locale: Locale) -> CutSocialStat {
        .init(value: grouped(weightUnit.displayValue(kg), locale: locale), label: weightUnit.label)
    }

    /// Whole number with grouping: 9840 -> "9,840".
    static func grouped(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }

    /// Kilometres: two decimals under 10 km, one above ("6.24", "12.4").
    static func distanceKm(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: km >= 10 ? "%.1f" : "%.2f", km)
    }

    /// "52:10" under an hour, "1:05" (h:mm) from an hour: seconds are dropped once hours show.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%d:%02d", hours, minutes) }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    static func pace(secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// A battle score in its unit; weight follows the preferred unit.
    static func score(_ value: Double, unit: String, weightUnit: WeightUnit, locale: Locale) -> String {
        switch unit {
        case "kg": "\(grouped(weightUnit.displayValue(value), locale: locale)) \(weightUnit.label)"
        case "km": "\(String(format: "%.1f", value)) km"
        default: "\(grouped(value, locale: locale)) \(unit)"
        }
    }

    // MARK: Arena

    static func arenaItem(_ facts: CutSocialArenaFacts, weightUnit: WeightUnit = .kg, locale: Locale = .current) -> CutSocialArenaItem {
        switch facts {
        case let .battle(id, opponent, mine, theirs, unit):
            let total = mine + theirs
            let difference = mine - theirs
            let sign = difference > 0 ? "+" : (difference < 0 ? "-" : "")
            let magnitude = score(abs(difference), unit: unit, weightUnit: weightUnit, locale: locale)
            return CutSocialArenaItem(
                target: .battle(id),
                label: "Battle with \(firstName(opponent))",
                value: difference == 0 ? "Level" : "\(sign)\(magnitude)",
                fraction: total > 0 ? mine / total : 0.5,
                isLeading: difference > 0
            )
        case let .challenge(id, title, percent):
            let clamped = min(max(percent, 0), 100)
            return CutSocialArenaItem(
                target: .challenge(id),
                label: title,
                value: "\(clamped)%",
                fraction: Double(clamped) / 100,
                isLeading: false
            )
        }
    }

    // MARK: Friends

    static func friends(_ friends: [CutSocialFriendFacts]?, requests: Int, now: Date, locale: Locale = .current) -> CutSocialFriendsModel {
        let active = (friends ?? [])
            .filter { friend in
                guard let last = friend.lastWorkout else { return false }
                return now.timeIntervalSince(last) < 24 * 3600
            }
            .sorted { ($0.lastWorkout ?? .distantPast) > ($1.lastWorkout ?? .distantPast) }
            .prefix(5)
            .map { friend in
                CutSocialFriendsModel.Row(
                    id: friend.id,
                    name: friend.name,
                    initials: initials(friend.name),
                    avatarURL: friend.avatarURL,
                    line: friendLine(friend, now: now, locale: locale)
                )
            }
        return CutSocialFriendsModel(requests: max(0, requests), activeNow: Array(active), friendsCount: friends?.count)
    }

    static func friendLine(_ friend: CutSocialFriendFacts, now: Date, locale: Locale) -> String {
        guard let last = friend.lastWorkout else { return "Recently active" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        let when = "Trained \(formatter.localizedString(for: last, relativeTo: now))"
        return friend.workoutsThisWeek > 1 ? "\(when), \(friend.workoutsThisWeek) this week" : when
    }

    /// What the share button and menu item send: the legacy post card's text.
    static let shareText = "Check out this workout on WRKT!"

    static func badge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}
