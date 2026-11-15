import Foundation
import Testing
@testable import WRKT

enum CutProfileFixtures {
    static let now = Date(timeIntervalSince1970: 1_794_960_000)
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    static var profile: CutProfileFacts {
        .init(name: "Alex Sample", username: "alex_sample", bio: "Strength and trail running.", isOwn: false,
              friendship: .friends, friendCount: 8, profileStreak: 3, localStreak: 5,
              posts: [.init(id: UUID(), workoutDate: now.addingTimeInterval(-3600), createdAt: now,
                            title: "Upper Body", caption: "A good session.", icon: "dumbbell", exercises: 4, sets: 12)],
              viewerWorkoutDates: [now, now.addingTimeInterval(-3600)])
    }
    static func model(_ facts: CutProfileFacts?) -> CutProfileModel {
        CutProfileLogic.model(facts, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
    }
}

struct CutProfileLogicTests {
    private typealias F = CutProfileFixtures
    @Test func initialLoadingAndErrors() {
        #expect(F.model(nil).state == .loading)
        #expect(CutProfileLogic.model(nil, error: "Profile not found", now: F.now).state == .failed("Profile not found"))
        #expect(CutProfileLogic.model(nil, error: "Old failure", isLoading: true, now: F.now).state == .loading)
    }
    @Test func ownProfileShowsEditingAndLocalStatsWithoutComparisons() {
        var facts = F.profile; facts.isOwn = true
        let model = F.model(facts)
        #expect(model.actions == [.edit])
        #expect(model.comparison == nil && model.accountability.isEmpty)
        #expect(model.ownStats.map(\.value) == ["1", "8", "5"])
        #expect(model.metadata[1].value == "3 weeks")
    }
    @Test func friendshipActionsMatchEveryLegacyState() {
        var facts = F.profile
        facts.friendship = .none; #expect(F.model(facts).actions == [.add])
        facts.friendship = .pendingSent; #expect(F.model(facts).actions == [.cancel])
        facts.friendship = .pendingReceived; #expect(F.model(facts).actions == [.accept, .decline])
        facts.friendship = .friends; #expect(F.model(facts).actions == [.mute, .remove])
        facts.isMuted = true; #expect(F.model(facts).actions == [.unmute, .remove])
    }
    @Test func privateAndBlockedProfilesPreserveExistingVisibilityRules() {
        var facts = F.profile
        facts.isPrivate = true; facts.isBlocked = true; facts.friendship = .none
        let model = F.model(facts)
        #expect(model.actions == [.add])
        #expect(model.posts.count == 1 && model.comparison != nil)
        facts.posts = []
        #expect(F.model(facts).posts.isEmpty)
    }
    @Test func nameAndHandleFallback() {
        var facts = F.profile
        #expect(F.model(facts).handle == "@alex_sample")
        facts.name = ""
        #expect(F.model(facts).name == "@alex_sample")
        #expect(F.model(facts).handle == nil)
        facts.name = nil; #expect(F.model(facts).initials == "AS")
    }
    @Test func emptyAndLoadingPostsStayDistinct() {
        var facts = F.profile; facts.posts = []
        #expect(!F.model(facts).isLoadingPosts)
        #expect(F.model(facts).metadata[0].value == "No recent sessions")
        facts.isLoadingPosts = true
        #expect(F.model(facts).isLoadingPosts)
    }
    @Test func pendingBattleAppearsOnlyForAnotherProfile() {
        var facts = F.profile
        facts.battle = .init(type: "Volume", days: 7, start: F.now)
        #expect(F.model(facts).battle?.rows.map(\.value).prefix(2) == ["Volume", "7 days"])
        facts.isOwn = true; #expect(F.model(facts).battle == nil)
    }
    @Test func weeklyCountsUseMondayAndExcludeTheNextWeek() {
        let start = F.calendar.startOfWeek(for: F.now, anchorWeekday: 2)
        let end = F.calendar.date(byAdding: .day, value: 7, to: start)!
        #expect(CutProfileLogic.weeklyCount([start.addingTimeInterval(-1), start, end.addingTimeInterval(-1), end], now: F.now, calendar: F.calendar) == 2)
    }
    @Test func activeDaysPreserveRollingCutoffAndDeduplicateDates() {
        let cutoff = F.calendar.date(byAdding: .day, value: -13, to: F.now)!
        #expect(CutProfileLogic.activeDays([cutoff.addingTimeInterval(-1), cutoff, F.now, F.now], now: F.now, calendar: F.calendar) == 2)
    }
    @Test func comparisonAndAccountabilityKeepAllValues() {
        let model = F.model(F.profile)
        #expect(model.comparison?.yourWeek == 2 && model.comparison?.friendWeek == 1)
        #expect(model.comparison?.rows.count == 5)
        #expect(model.accountability.count == 4)
        #expect(model.comparison?.callout == "One more session extends the lead.")
    }
    @Test func comparisonCopyCoversTiesAndBothLeaders() {
        #expect(CutProfileLogic.comparisonMessage(name: "Alex", yours: 0, theirs: 0).contains("Neither"))
        #expect(CutProfileLogic.comparisonMessage(name: "Alex", yours: 2, theirs: 2).contains("tied"))
        #expect(CutProfileLogic.callout(name: "Alex", yours: 0, theirs: 1) == "One session ties Alex.")
        #expect(CutProfileLogic.callout(name: "Alex", yours: 1, theirs: 4) == "You need 3 sessions to catch Alex.")
        #expect(CutProfileLogic.callout(name: "Alex", yours: 4, theirs: 1) == "You’ve built a 3-session lead.")
        #expect(CutProfileLogic.streak(0) == "No streak yet")
        #expect(CutProfileLogic.streak(1) == "1 week")
    }
    @Test func postStatsKeepCardioFallbacksAndHourFormatting() {
        var post = F.profile.posts[0]
        #expect(CutProfileLogic.postStats(post) == "4 exercises · 12 sets")
        post.isCardio = true; post.distanceMeters = 10000; post.durationSeconds = 3661
        #expect(CutProfileLogic.postStats(post) == "10.00 km · 1:01 · 6:06/km")
        post.durationSeconds = nil; post.estimatedDuration = 600; post.firstSplitPace = 305
        #expect(CutProfileLogic.postStats(post) == "10.00 km · 10:00 · 5:05/km")
        post.distanceMeters = nil; #expect(CutProfileLogic.postStats(post) == "10:00")
    }
}
