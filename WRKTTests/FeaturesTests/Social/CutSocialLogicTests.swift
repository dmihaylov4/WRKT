import Foundation
import Testing
@testable import WRKT

/// Shared fixtures for the Cut Social logic and capture tests. Times are relative to `now`.
enum CutSocialFixtures {
    static let locale = Locale(identifier: "en_US")
    /// Friday 13 November 2026, 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_794_571_200)

    static func person(_ name: String) -> CutSocialPostFacts.Person {
        .init(id: UUID(), name: name)
    }

    static func strength(
        _ name: String = "Lower Body",
        author: String = "Maria K.",
        caption: String? = "Legs done. Hamstrings are filing a complaint.",
        minutesAgo: Double = 42,
        likes: Int = 12,
        comments: Int = 4,
        isOwn: Bool = false
    ) -> CutSocialPostFacts {
        CutSocialPostFacts(
            id: UUID(), author: person(author), createdAt: now.addingTimeInterval(-minutesAgo * 60),
            caption: caption, kind: .strength(name: name, volumeKg: 9_840, sets: 24, durationSeconds: 3_130),
            likes: likes, comments: comments, isOwn: isOwn
        )
    }

    static func cardio(author: String = "Alex J.", hoursAgo: Double = 2) -> CutSocialPostFacts {
        CutSocialPostFacts(
            id: UUID(), author: person(author), createdAt: now.addingTimeInterval(-hoursAgo * 3600),
            kind: .cardio(name: "Morning Run", distanceMeters: 8_400, durationSeconds: 2_642, calories: 610, averageHeartRate: 151),
            likes: 8, comments: 1, isLiked: true
        )
    }

    static func weekly() -> CutSocialPostFacts {
        CutSocialPostFacts(
            id: UUID(), author: person("Dimitar M."), createdAt: now.addingTimeInterval(-26 * 3600),
            kind: .weekly(weekStart: now.addingTimeInterval(-4 * 86_400), strengthDone: 4, strengthTarget: 4,
                          activeMinutesDone: 168, activeMinutesTarget: 150, streak: 6),
            likes: 21, comments: 6, isOwn: true
        )
    }

    static func battle() -> CutSocialPostFacts {
        CutSocialPostFacts(
            id: UUID(), author: person("Alex J."), createdAt: now.addingTimeInterval(-3 * 86_400),
            kind: .battle(won: false, myName: "Alex J.", myScore: 22_480, opponentName: "Dimitar M.", opponentScore: 24_100, unit: "kg"),
            likes: 9, comments: 2
        )
    }

    static func shared() -> CutSocialPostFacts {
        CutSocialPostFacts(
            id: UUID(), author: person("Sam P."), partner: person("Nina R."), createdAt: now.addingTimeInterval(-20 * 3600),
            caption: "Pull day with Nina.", kind: .strength(name: "Pull Day", volumeKg: 7_210, sets: 22, durationSeconds: 2_790),
            likes: 15, comments: 3, canRemoveMe: true
        )
    }

    static func longPost() -> CutSocialPostFacts {
        CutSocialPostFacts(
            id: UUID(), author: person("Maximiliana Alexandrova-Fitzgerald Montgomery"), createdAt: now.addingTimeInterval(-5 * 60),
            caption: String(repeating: "Tempo squats, paused bench and a very long walk home afterwards because the bus never came. ", count: 3),
            visibility: .onlyMe,
            kind: .strength(name: "Posterior Chain and Single Leg Strength Accessories", volumeKg: 124_350, sets: 38, durationSeconds: 5_520),
            likes: 1_204, comments: 318
        )
    }

    static func rows(_ facts: [CutSocialPostFacts]) -> [CutSocialPostRow] {
        facts.map { CutSocialLogic.row($0, now: now, weightUnit: .kg, locale: locale) }
    }

    static var arena: [CutSocialArenaItem] {
        [
            CutSocialLogic.arenaItem(.battle(id: UUID(), opponentName: "Alex Johnson", userScore: 18_420, opponentScore: 17_180, unit: "kg"), locale: locale),
            CutSocialLogic.arenaItem(.challenge(id: UUID(), title: "November 100 km", percent: 68), locale: locale),
            CutSocialLogic.arenaItem(.battle(id: UUID(), opponentName: "Sam Park", userScore: 14.2, opponentScore: 18.4, unit: "km"), locale: locale)
        ]
    }

    static var friendFacts: [CutSocialFriendFacts] {
        [
            .init(id: UUID(), name: "Maria K.", lastWorkout: now.addingTimeInterval(-42 * 60), workoutsThisWeek: 4),
            .init(id: UUID(), name: "Alex J.", lastWorkout: now.addingTimeInterval(-2 * 3600), workoutsThisWeek: 1),
            .init(id: UUID(), name: "Sam P.", lastWorkout: now.addingTimeInterval(-20 * 3600), workoutsThisWeek: 3),
            .init(id: UUID(), name: "Nina R.", lastWorkout: now.addingTimeInterval(-3 * 86_400)),
            .init(id: UUID(), name: "Quiet Friend")
        ]
    }
}

struct CutSocialLogicTests {
    private typealias F = CutSocialFixtures

    // MARK: Feed state

    @Test func feedIsLoadingUntilTheViewModelExists() {
        #expect(CutSocialLogic.content(hasViewModel: false, isLoading: false, error: nil, rows: []) == .loading)
        #expect(CutSocialLogic.content(hasViewModel: true, isLoading: true, error: nil, rows: []) == .loading)
    }

    @Test func errorShowsOnlyWhenNothingIsLoaded() {
        let error = (title: "Connection Error", message: "Check your connection.", canRetry: true)
        #expect(CutSocialLogic.content(hasViewModel: true, isLoading: false, error: error, rows: [])
                == .failed(title: "Connection Error", message: "Check your connection.", canRetry: true))
        let rows = F.rows([F.strength()])
        #expect(CutSocialLogic.content(hasViewModel: true, isLoading: false, error: error, rows: rows) == .posts(rows))
        #expect(CutSocialLogic.inlineError(message: "Oops", postCount: 1) == "Oops")
        #expect(CutSocialLogic.inlineError(message: "Oops", postCount: 0) == nil)
    }

    @Test func emptyOnlyAfterALoadFinished() {
        #expect(CutSocialLogic.content(hasViewModel: true, isLoading: false, error: nil, rows: []) == .empty)
    }

    @Test func newPostsAndOfflineCopy() {
        #expect(CutSocialLogic.newPostsLabel(1) == "1 new post")
        #expect(CutSocialLogic.newPostsLabel(3) == "3 new posts")
        #expect(CutSocialLogic.offlineLine(queued: 0) == "Showing saved posts")
        #expect(CutSocialLogic.offlineLine(queued: 1) == "1 action waiting to sync")
        #expect(CutSocialLogic.offlineLine(queued: 4) == "4 actions waiting to sync")
    }

    // MARK: Posts

    @Test func strengthPostShowsVolumeSetsAndDuration() {
        let row = F.rows([F.strength()])[0]
        #expect(row.title == "Lower Body")
        #expect(row.stats.map(\.value) == ["9,840", "24", "52:10"])
        #expect(row.stats.map(\.label) == ["kg", "sets", "duration"])
        #expect(row.author.initials == "MK")
        #expect(row.names == "Maria K.")
        #expect(row.caption == "Legs done. Hamstrings are filing a complaint.")
        #expect(row.showsMedia)
    }

    @Test func volumeFollowsThePreferredUnit() {
        let row = CutSocialLogic.row(F.strength(), now: F.now, weightUnit: .lb, locale: F.locale)
        #expect(row.stats[0] == CutSocialStat(value: "21,693", label: "lb"))
    }

    @Test func cardioPostShowsDistanceTimeAndPace() {
        let row = F.rows([F.cardio()])[0]
        #expect(row.title == "Morning Run")
        #expect(row.stats.map(\.value) == ["8.40", "44:02", "5:15"])
        #expect(row.stats.map(\.label) == ["km", "time", "/km"])
        #expect(row.isLiked)
    }

    @Test func cardioWithoutDistanceShowsTimeCaloriesAndHeartRate() {
        var facts = F.cardio()
        facts.kind = .cardio(name: "Yoga", distanceMeters: 0, durationSeconds: 3_900, calories: 210, averageHeartRate: 98.4)
        let row = F.rows([facts])[0]
        #expect(row.stats.map(\.value) == ["1:05", "210", "98"])
        #expect(row.stats.map(\.label) == ["time", "kcal", "avg bpm"])
    }

    @Test func clockDropsSecondsFromAnHour() {
        #expect(CutSocialLogic.clock(3_130) == "52:10")
        #expect(CutSocialLogic.clock(3_600) == "1:00")
        #expect(CutSocialLogic.clock(5_520) == "1:32")
        #expect(CutSocialLogic.clock(-4) == "0:00")
    }

    @Test func distanceAndPaceFormats() {
        #expect(CutSocialLogic.distanceKm(6_240) == "6.24")
        #expect(CutSocialLogic.distanceKm(12_440) == "12.4")
        #expect(CutSocialLogic.pace(secondsPerKm: 314.5) == "5:15")
        #expect(CutSocialLogic.pace(secondsPerKm: .infinity) == "--")
    }

    @Test func weeklyPostShowsGoalStreakAndWeek() {
        let row = F.rows([F.weekly()])[0]
        #expect(row.title == "Week of Nov 9")
        #expect(row.stats.map(\.value) == ["4/4", "168/150", "6"])
        #expect(!row.showsMedia)
    }

    @Test func battlePostHighlightsTheWinner() {
        let row = F.rows([F.battle()])[0]
        #expect(row.title == "Alex lost")
        #expect(row.stats.map(\.value) == ["22,480 kg", "24,100 kg"])
        #expect(row.stats.map(\.label) == ["Alex", "Dimitar"])
        #expect(row.stats.map(\.isHighlighted) == [false, true])
        #expect(!row.showsMedia)

        var own = F.battle()
        own.isOwn = true
        own.kind = .battle(won: true, myName: "Dimitar M.", myScore: 24_100, opponentName: "Alex J.", opponentScore: 22_480, unit: "kg")
        #expect(F.rows([own])[0].title == "You won")
    }

    @Test func multiWorkoutPostSummarisesAll() {
        var facts = F.strength()
        facts.kind = .multi(count: 3, cardioCount: 0, volumeKg: 12_000, sets: 40, durationSeconds: 7_200)
        #expect(F.rows([facts])[0].title == "3 workouts")
        #expect(F.rows([facts])[0].stats.map(\.value) == ["12,000", "40", "2:00"])
        facts.kind = .multi(count: 2, cardioCount: 1, volumeKg: 5_000, sets: 12, durationSeconds: nil)
        #expect(F.rows([facts])[0].title == "Strength and cardio")
        #expect(F.rows([facts])[0].stats.map(\.label) == ["kg", "workouts"])
    }

    @Test func sharedPostNamesBothPeople() {
        let row = F.rows([F.shared()])[0]
        #expect(row.names == "Sam P. and Nina R.")
        #expect(row.partner?.initials == "NR")
        #expect(row.menu == [.removeMe, .likes, .report])
    }

    @Test func menuDependsOnOwnershipAndLikes() {
        var own = F.strength(isOwn: true)
        #expect(CutSocialLogic.menu(for: own) == [.edit, .delete, .likes])
        own.likes = 0
        #expect(CutSocialLogic.menu(for: own) == [.edit, .delete])
        #expect(CutSocialLogic.menu(for: F.strength()) == [.likes, .report])
        #expect(CutSocialLogic.isDestructive(.delete) && CutSocialLogic.isDestructive(.report))
        #expect(!CutSocialLogic.isDestructive(.edit))
    }

    @Test func timeLineMentionsPrivatePostsOnly() {
        let row = F.rows([F.longPost()])[0]
        #expect(row.timeLine.hasSuffix(", only you"))
        #expect(!F.rows([F.strength()])[0].timeLine.contains("only you"))
        let fresh = CutSocialLogic.timeLine(createdAt: F.now.addingTimeInterval(-10), now: F.now, visibility: .everyone, locale: F.locale)
        #expect(fresh == "Just now")
    }

    @Test func captionsAreTrimmedAndBlankOnesDropped() {
        #expect(CutSocialLogic.cleanCaption("  hi \n") == "hi")
        #expect(CutSocialLogic.cleanCaption("   ") == nil)
        #expect(CutSocialLogic.cleanCaption(nil) == nil)
    }

    @Test func initials() {
        #expect(CutSocialLogic.initials("Maria K.") == "MK")
        #expect(CutSocialLogic.initials("sam") == "S")
        #expect(CutSocialLogic.initials("john_doe") == "JD")
        #expect(CutSocialLogic.initials("") == "")
    }

    @Test func accessibilityLabelsCarryCounts() {
        #expect(CutSocialLogic.likeAccessibility(likes: 1, isLiked: false) == "Like, 1 like")
        #expect(CutSocialLogic.likeAccessibility(likes: 12, isLiked: true) == "Unlike, 12 likes")
        #expect(CutSocialLogic.commentAccessibility(4) == "Comments, 4 comments")
    }

    // MARK: Arena

    @Test func battleArenaShowsTheLeadAndYourShare() {
        let item = F.arena[0]
        #expect(item.label == "Battle with Alex")
        #expect(item.value == "+1,240 kg")
        #expect(item.isLeading)
        #expect(abs(item.fraction - 18_420.0 / 35_600.0) < 0.0001)

        let behind = F.arena[2]
        #expect(behind.value == "-4.2 km")
        #expect(!behind.isLeading)

        let level = CutSocialLogic.arenaItem(.battle(id: UUID(), opponentName: "A", userScore: 0, opponentScore: 0, unit: "workouts"))
        #expect(level.value == "Level")
        #expect(level.fraction == 0.5)
    }

    @Test func challengeArenaClampsProgress() {
        #expect(F.arena[1].value == "68%")
        #expect(CutSocialLogic.arenaItem(.challenge(id: UUID(), title: "T", percent: 140)).fraction == 1)
        #expect(CutSocialLogic.arenaItem(.challenge(id: UUID(), title: "T", percent: -3)).value == "0%")
    }

    // MARK: Friends

    @Test func activeNowIsTheLastDayNewestFirst() {
        let model = CutSocialLogic.friends(F.friendFacts, requests: 2, now: F.now, locale: F.locale)
        #expect(model.activeNow.map(\.name) == ["Maria K.", "Alex J.", "Sam P."])
        #expect(model.activeNow[0].line.hasPrefix("Trained"))
        #expect(model.activeNow[0].line.hasSuffix(", 4 this week"))
        #expect(!model.activeNow[1].line.contains("this week"))
        #expect(model.friendsCount == 5)
        #expect(model.requests == 2)
    }

    @Test func friendsCountIsUnknownUntilLoaded() {
        let model = CutSocialLogic.friends(nil, requests: -1, now: F.now)
        #expect(model.friendsCount == nil)
        #expect(model.activeNow.isEmpty)
        #expect(model.requests == 0)
    }

    @Test func badges() {
        #expect(CutSocialLogic.badge(0) == nil)
        #expect(CutSocialLogic.badge(7) == "7")
        #expect(CutSocialLogic.badge(140) == "99+")
    }
}
