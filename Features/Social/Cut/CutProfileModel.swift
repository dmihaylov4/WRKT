import Foundation

struct CutProfileFacts: Equatable {
    enum Friendship: Equatable { case none, friends, pendingSent, pendingReceived }
    struct Post: Equatable, Identifiable {
        var id: UUID
        var workoutDate: Date
        var createdAt: Date
        var title: String
        var caption: String?
        var icon: String
        var isCardio = false
        var exercises = 0
        var sets = 0
        var distanceMeters: Double?
        var durationSeconds: Int?
        var estimatedDuration: Double?
        var firstSplitPace: Int?
    }
    struct Battle: Equatable {
        var type: String
        var days: Int
        var start: Date
    }
    var name: String?
    var username: String
    var bio: String?
    var avatarURL: String?
    var isOwn = false
    var isPrivate = false
    var isBlocked = false
    var friendship: Friendship = .none
    var isMuted = false
    var isLoadingFriendship = false
    var isUploadingAvatar = false
    var friendCount = 0
    var profileStreak = 0
    var localStreak = 0
    var posts: [Post] = []
    var isLoadingPosts = false
    var viewerWorkoutDates: [Date] = []
    var battle: Battle?
    var barbellWeightKg: Double = 20
}

struct CutProfileModel: Equatable {
    enum State: Equatable { case loading, failed(String), loaded }
    enum Action: Equatable { case edit, add, cancel, accept, decline, mute, unmute, remove }
    struct Row: Equatable { var label: String; var value: String }
    struct Post: Equatable, Identifiable {
        var id: UUID
        var title: String
        var date: String
        var caption: String?
        var icon: String
        var stats: String
    }
    struct Comparison: Equatable {
        struct Bar: Equatable, Identifiable {
            enum Role: Equatable, Hashable { case viewer, friend }
            var id: Role
            var label: String
            var value: Int
            var fraction: Double
        }
        var title: String
        var message: String
        var callout: String
        var rows: [Row]
        var bars: [Bar]
    }
    struct Battle: Equatable { var challenger: String; var rows: [Row] }
    var state: State = .loading
    var name = ""
    var handle: String?
    var initials = ""
    var bio: String?
    var avatarURL: String?
    var isOwn = false
    var isUploadingAvatar = false
    var actions: [Action] = []
    var friendshipTitle = ""
    var friendshipHelp = ""
    var isLoadingFriendship = false
    var metadata: [Row] = []
    var ownStats: [CutStatColumn] = []
    var comparison: Comparison?
    var accountability: [Row] = []
    var battle: Battle?
    var posts: [Post] = []
    var isLoadingPosts = false
    var loadedWeight: String?
}

enum CutProfileLogic {
    static func model(_ facts: CutProfileFacts?, error: String? = nil, isLoading: Bool = false,
                      now: Date, calendar: Calendar = .current, locale: Locale = .current) -> CutProfileModel {
        if let error, !isLoading { return .init(state: .failed(error)) }
        guard let facts else { return .init() }
        let name = facts.name.flatMap { $0.isEmpty ? nil : $0 } ?? facts.username
        let dates = facts.posts.map(\.workoutDate)
        let week = weeklyCount(dates, now: now, calendar: calendar)
        let yours = weeklyCount(facts.viewerWorkoutDates, now: now, calendar: calendar)
        let active = activeDays(dates, now: now, calendar: calendar)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        let lastActive = dates.max().map { formatter.localizedString(for: $0, relativeTo: now) }
        var model = CutProfileModel(state: .loaded, name: facts.name.flatMap { $0.isEmpty ? nil : $0 } ?? "@\(facts.username)",
                                    handle: facts.name?.isEmpty == false ? "@\(facts.username)" : nil,
                                    initials: CutSocialLogic.initials(name), bio: facts.bio, avatarURL: facts.avatarURL,
                                    isOwn: facts.isOwn, isUploadingAvatar: facts.isUploadingAvatar,
                                    actions: actions(facts), isLoadingFriendship: facts.isLoadingFriendship)
        model.metadata = [.init(label: "Last Active", value: lastActive ?? "No recent sessions"),
                          .init(label: "Streak", value: streak(facts.profileStreak))]
        if facts.isOwn {
            model.ownStats = [.init(value: "\(facts.posts.count)", label: "Recent Posts"),
                              .init(value: "\(facts.friendCount)", label: "Friends"),
                              .init(value: "\(facts.localStreak)", label: "Streak")]
        } else {
            model.loadedWeight = "\(Int(facts.barbellWeightKg))kg loaded"
            model.metadata.append(.init(label: "This week", value: week == 0 ? "No workouts yet" : "\(week) workout\(week == 1 ? "" : "s")"))
            model.comparison = .init(title: "You vs \(name)", message: comparisonMessage(name: name, yours: yours, theirs: week),
                                     callout: callout(name: name, yours: yours, theirs: week),
                                     rows: [.init(label: "You this week", value: "\(yours) session\(yours == 1 ? "" : "s")"),
                                            .init(label: "\(name) this week", value: "\(week) session\(week == 1 ? "" : "s")"),
                                            .init(label: "You 14d", value: "\(activeDays(facts.viewerWorkoutDates, now: now, calendar: calendar)) active days"),
                                            .init(label: "\(name) 14d", value: "\(active) active days"),
                                            .init(label: "Streak", value: streak(facts.profileStreak))], bars: [
                                                .init(id: .viewer, label: "You", value: yours, fraction: Double(yours) / Double(max(yours, week, 1))),
                                                .init(id: .friend, label: name, value: week, fraction: Double(week) / Double(max(yours, week, 1)))])
            model.accountability = [.init(label: "This Week", value: "\(week) shared session\(week == 1 ? "" : "s")"),
                                    .init(label: "Last Active", value: lastActive ?? "No activity"),
                                    .init(label: "Last 14 Days", value: "\(active) active day\(active == 1 ? "" : "s")"),
                                    .init(label: "Recent Posts", value: "\(facts.posts.count)")]
            switch facts.friendship {
            case .none: model.friendshipTitle = "Next Move"; model.friendshipHelp = "Add them first, then use this page to compare momentum and push each other."
            case .friends: model.friendshipTitle = "Next Move"; model.friendshipHelp = "Use the friend menu to manage this friendship."
            case .pendingSent: model.friendshipTitle = "Waiting On Them"; model.friendshipHelp = "They need to accept before this page becomes useful for accountability."
            case .pendingReceived: model.friendshipTitle = "Open The Loop"; model.friendshipHelp = "Accept to unlock head-to-head pressure and live accountability actions."
            }
            if let battle = facts.battle {
                model.battle = .init(challenger: "\(name) challenged you", rows: [
                    .init(label: "Type", value: battle.type), .init(label: "Duration", value: "\(battle.days) days"),
                    .init(label: "Starts", value: battle.start.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)))])
            }
        }
        model.posts = facts.posts.map { post in
            .init(id: post.id, title: post.title, date: post.createdAt.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)),
                  caption: post.caption, icon: post.icon, stats: postStats(post))
        }
        model.isLoadingPosts = facts.isLoadingPosts
        return model
    }

    static func actions(_ facts: CutProfileFacts) -> [CutProfileModel.Action] {
        if facts.isOwn { return [.edit] }
        // The existing view model maps blocked to none. Privacy and blocking do not add new actions here.
        switch facts.friendship {
        case .none: return [.add]
        case .friends: return [facts.isMuted ? .unmute : .mute, .remove]
        case .pendingSent: return [.cancel]
        case .pendingReceived: return [.accept, .decline]
        }
    }
    static func weeklyCount(_ dates: [Date], now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfWeek(for: now, anchorWeekday: 2)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        return dates.filter { $0 >= start && $0 < end }.count
    }
    static func activeDays(_ dates: [Date], now: Date, calendar: Calendar) -> Int {
        // Preserve the legacy rolling cutoff, including its time of day.
        let cutoff = calendar.date(byAdding: .day, value: -13, to: now) ?? now
        return Set(dates.filter { $0 >= cutoff }.map { calendar.startOfDay(for: $0) }).count
    }
    static func streak(_ value: Int) -> String { value == 0 ? "No streak yet" : "\(value) week\(value == 1 ? "" : "s")" }
    static func comparisonMessage(name: String, yours: Int, theirs: Int) -> String {
        if yours == theirs { return yours == 0 ? "Neither of you has logged a session this week yet." : "You’re tied. The next session puts someone in front." }
        let delta = abs(yours - theirs)
        return yours > theirs ? (delta == 1 ? "You’re ahead by one session." : "You’re ahead by \(delta) sessions.")
            : (delta == 1 ? "\(name) is ahead by one session." : "\(name) is ahead by \(delta) sessions.")
    }
    static func callout(name: String, yours: Int, theirs: Int) -> String {
        if yours == theirs { return yours == 0 ? "Neither of you has started this week." : "Next session breaks the tie." }
        let delta = abs(yours - theirs)
        return yours > theirs ? (delta == 1 ? "One more session extends the lead." : "You’ve built a \(delta)-session lead.")
            : (delta == 1 ? "One session ties \(name)." : "You need \(delta) sessions to catch \(name).")
    }
    static func postStats(_ post: CutProfileFacts.Post) -> String {
        guard post.isCardio else { return "\(post.exercises) exercises · \(post.sets) sets" }
        var parts: [String] = []
        if let distance = post.distanceMeters, distance > 0 { parts.append(String(format: "%.2f km", distance / 1000)) }
        if let duration = post.durationSeconds, duration > 0 { parts.append(CutSocialLogic.clock(Double(duration))) }
        else if let estimated = post.estimatedDuration, estimated > 0 { parts.append(CutSocialLogic.clock(Double(Int(estimated)))) }
        if let distance = post.distanceMeters, distance > 0 {
            let pace = post.durationSeconds.flatMap { $0 > 0 ? Double($0) / (distance / 1000) : nil }
                ?? post.firstSplitPace.flatMap { $0 > 0 ? Double($0) : nil }
            if let pace { parts.append(String(format: "%d:%02d/km", Int(pace) / 60, Int(pace) % 60)) }
        }
        return parts.joined(separator: " · ")
    }
}
