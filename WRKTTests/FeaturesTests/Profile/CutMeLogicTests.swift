import Foundation
import Testing
@testable import WRKT

/// Shared fixtures for the Cut Me logic and capture tests. Dates are relative to `now`.
enum CutMeFixtures {
    static let locale = Locale(identifier: "en_GB")
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Friday 13 November 2026, 12:00 UTC. Its week runs Monday 9 to Sunday 15 November.
    static let now = Date(timeIntervalSince1970: 1_794_571_200)
    /// Monday 9 November 2026, 00:00 UTC.
    static let thisMonday = Date(timeIntervalSince1970: 1_794_182_400)

    static func monday(weeksAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -7 * weeksAgo, to: thisMonday)!
    }

    static func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    static func progress(
        level: Int = 14, xp: Int = 2_340, prev: Int = 2_000, next: Int = 2_750,
        weekly: Int = 6, weeklyLongest: Int = 11, superStreak: Int = 2,
        daily: Int = 4, dailyLongest: Int = 9, weeklyFrozen: Bool = false
    ) -> CutMeFacts.Progress {
        CutMeFacts.Progress(level: level, xp: xp, prevLevelXP: prev, nextLevelXP: next,
                            dailyStreak: daily, dailyStreakLongest: dailyLongest, dailyFrozen: false,
                            weeklyStreak: weekly, weeklyStreakLongest: weeklyLongest, weeklyFrozen: weeklyFrozen,
                            superStreak: superStreak)
    }

    /// Twelve weeks of tonnage, rising, this week the biggest.
    static var weeks: [CutMeFacts.Week] {
        [14_200, 15_800, 12_100, 17_900, 19_400, 16_000, 20_300, 18_100, 21_700, 22_400, 23_000, 24_860]
            .enumerated().map { CutMeFacts.Week(weekStart: monday(weeksAgo: 11 - $0.offset), volumeKg: $0.element) }
    }

    static var muscles: [CutMeFacts.Muscle] {
        [
            CutMeFacts.Muscle(name: "Back", lastTrained: daysAgo(6)),
            CutMeFacts.Muscle(name: "Chest", lastTrained: daysAgo(2)),
            CutMeFacts.Muscle(name: "Hamstrings", lastTrained: daysAgo(3)),
            CutMeFacts.Muscle(name: "Quadriceps", lastTrained: daysAgo(0)),
            CutMeFacts.Muscle(name: "Biceps", lastTrained: daysAgo(9))
        ]
    }

    /// A trained user with a weekly goal, a plan and statistics.
    static var full: CutMeFacts {
        var facts = CutMeFacts()
        facts.progress = progress()
        facts.goalIsSet = true
        facts.goalProgress = CutMeFacts.GoalProgress(strengthDone: 2, strengthTarget: 4, minutesDone: 95, minutesTarget: 150)
        facts.freeze = CutMeFacts.Freeze(canActivate: true, reason: nil)
        facts.adherence = [
            CutMeFacts.Adherence(planned: 4, completed: 4, missed: 0),
            CutMeFacts.Adherence(planned: 4, completed: 3, missed: 1),
            CutMeFacts.Adherence(planned: 4, completed: 4, missed: 0),
            CutMeFacts.Adherence(planned: 4, completed: 3, missed: 0)
        ]
        facts.weeks = weeks
        facts.latestWeekChange = 8.2
        facts.pushVolume = 5_600
        facts.pullVolume = 4_400
        facts.muscles = muscles
        facts.prCount = 31
        facts.milestoneCount = 12
        return facts
    }

    /// A brand-new user: level 1, nothing logged, no goal.
    static var fresh: CutMeFacts {
        var facts = CutMeFacts()
        facts.progress = progress(level: 1, xp: 0, prev: 0, next: 150, weekly: 0, weeklyLongest: 0, superStreak: 0,
                                  daily: 0, dailyLongest: 0)
        facts.freeze = CutMeFacts.Freeze(canActivate: false, reason: "Need 3+ day streak to freeze")
        return facts
    }

    /// Big numbers everywhere.
    static var large: CutMeFacts {
        var facts = full
        facts.progress = progress(level: 128, xp: 1_294_310, prev: 1_290_000, next: 1_296_450,
                                  weekly: 104, weeklyLongest: 156, superStreak: 88)
        facts.goalProgress = CutMeFacts.GoalProgress(strengthDone: 7, strengthTarget: 7, minutesDone: 1_240, minutesTarget: 1_050)
        facts.weeks = weeks.map { CutMeFacts.Week(weekStart: $0.weekStart, volumeKg: $0.volumeKg * 48) }
        facts.prCount = 1_204
        facts.milestoneCount = 386
        facts.freeze = CutMeFacts.Freeze(canActivate: false, reason: "Available next month")
        return facts
    }

    static func model(_ facts: CutMeFacts) -> CutMeModel {
        CutMeLogic.model(facts, now: now, calendar: calendar, locale: locale)
    }
}

@MainActor
@Suite("Cut Me logic")
struct CutMeLogicTests {
    private typealias F = CutMeFixtures

    // MARK: Level

    @Test func titleIsTheLevelOrMeWithoutProgress() {
        #expect(F.model(F.full).title == "Level 14")
        var none = F.full
        none.progress = nil
        let model = F.model(none)
        #expect(model.title == "Me")
        #expect(model.hero == nil)
        #expect(model.emptyLine != nil)
        #expect(model.freeze == nil)
        #expect(model.streakStats.isEmpty)
    }

    @Test func levelWindowMatchesTheLegacyCard() {
        // Step for level 14 is 100 + 50 * 13 = 750; prev 2000 already matches next - step.
        let window = CutMeLogic.levelWindow(level: 14, xp: 2_340, prevLevelXP: 2_000, nextLevelXP: 2_750)
        #expect(window.done == 340)
        #expect(window.total == 750)
        // A stale prev is widened to the level step, never narrower.
        let widened = CutMeLogic.levelWindow(level: 3, xp: 500, prevLevelXP: 0, nextLevelXP: 600)
        #expect(widened.total == 200)
        #expect(widened.done == 100)
        // XP below the window clamps to zero; an empty window still has a total of one.
        #expect(CutMeLogic.levelWindow(level: 1, xp: 0, prevLevelXP: 50, nextLevelXP: 50).done == 0)
        #expect(CutMeLogic.levelWindow(level: 1, xp: 0, prevLevelXP: 50, nextLevelXP: 50).total >= 1)
    }

    @Test func heroShowsXPAndTheStreak() throws {
        let hero = try #require(F.model(F.full).hero)
        #expect(hero.xp == "340")
        #expect(hero.xpTotal == "/750 XP")
        #expect(abs(hero.fraction - 340.0 / 750.0) < 0.0001)
        #expect(hero.line == "6 week streak")
        #expect(hero.lineIsActive)
    }

    @Test func streakIsDailyWithoutAGoal() throws {
        var facts = F.full
        facts.goalIsSet = false
        let model = F.model(facts)
        #expect(try #require(model.hero).line == "4 day streak")
        #expect(model.streakStats.map(\.value) == ["9"])
        #expect(model.streakStats.first?.unit == "days")
        #expect(model.goal == .setUp)
        #expect(!model.canShareWeek)
    }

    @Test func freshUserHasQuietLinesOnly() throws {
        let model = F.model(F.fresh)
        let hero = try #require(model.hero)
        #expect(model.title == "Level 1")
        #expect(hero.xp == "0")
        // Level 1 steps 100 XP; the legacy card shows the same window.
        #expect(hero.xpTotal == "/100 XP")
        #expect(hero.line == "No streak yet")
        #expect(!hero.lineIsActive)
        #expect(model.streakStats.isEmpty)
        #expect(model.goal == .setUp)
        #expect(model.adherence == nil)
        #expect(model.trends == .empty(line: "Log a workout to see your weekly tonnage."))
        #expect(model.balance == nil)
        #expect(model.prCount == nil)
        #expect(model.milestoneCount == nil)
        #expect(model.freeze?.line == "Need 3+ day streak to freeze")
        #expect(model.freeze?.canActivate == false)
    }

    @Test func largeNumbersAreGrouped() throws {
        let model = F.model(F.large)
        let hero = try #require(model.hero)
        #expect(model.title == "Level 128")
        #expect(hero.xp == "4,310")
        #expect(hero.xpTotal == "/6,450 XP")
        #expect(model.prCount == "1,204")
        guard case .data(let value, _, _, _) = model.trends else { Issue.record("no trends"); return }
        #expect(value == "1,193,280")
        guard case .progress(let rows) = model.goal else { Issue.record("no goal rows"); return }
        #expect(rows.map(\.value) == ["7 of 7", "1,240 of 1,050"])
        #expect(rows.allSatisfy { $0.isMet })
    }

    // MARK: Goal and freeze

    @Test func goalRowsAndShare() {
        let model = F.model(F.full)
        guard case .progress(let rows) = model.goal else { Issue.record("no goal rows"); return }
        #expect(rows.map(\.title) == ["Strength days", "Active minutes"])
        #expect(rows.map(\.value) == ["2 of 4", "95 of 150"])
        #expect(rows.allSatisfy { !$0.isMet })
        #expect(model.canShareWeek)
        #expect(model.streakStats.map(\.label) == ["Super streak", "Longest streak"])
        #expect(model.streakStats.map(\.value) == ["2", "11"])
    }

    @Test func goalSetWithoutProgressYetOffersSetUpLikeTheLegacyCard() {
        var facts = F.full
        facts.goalProgress = nil
        #expect(F.model(facts).goal == .setUp)
        #expect(!F.model(facts).canShareWeek)
    }

    @Test func freezeStates() {
        let p = F.progress()
        let ready = CutMeLogic.freezeRow(p, freeze: .init(canActivate: true, reason: nil), goalSet: true)
        #expect(ready?.value == "Ready")
        #expect(ready?.canActivate == true)
        #expect(ready?.alertMessage.contains("6-week streak") == true)

        let blocked = CutMeLogic.freezeRow(p, freeze: .init(canActivate: false, reason: "Available next month"), goalSet: true)
        #expect(blocked?.value == nil)
        #expect(blocked?.line == "Available next month")
        #expect(blocked?.canActivate == false)

        let active = CutMeLogic.freezeRow(F.progress(weeklyFrozen: true), freeze: .init(canActivate: false, reason: "Freeze already active"), goalSet: true)
        #expect(active?.value == "Active")
        #expect(active?.line == nil)

        let daily = CutMeLogic.freezeRow(p, freeze: .init(canActivate: true, reason: nil), goalSet: false)
        #expect(daily?.alertMessage.contains("4-day streak") == true)
        #expect(CutMeLogic.freezeRow(p, freeze: nil, goalSet: true) == nil)
    }

    // MARK: Plan adherence

    @Test func adherenceThisWeekWithRollingRate() throws {
        let adherence = try #require(F.model(F.full).adherence)
        #expect(adherence.hero == "3 of 4")
        #expect(adherence.line == "1 left this week, 88% over 4 weeks")
        #expect(adherence.segments == CutMeModel.Segments(total: 4, filled: 3))
    }

    @Test func adherenceAfterTheWeekEndsShowsMissed() throws {
        let weeks = [CutMeFacts.Adherence(planned: 3, completed: 2, missed: 1)]
        let ended = try #require(CutMeLogic.adherence(weeks, currentWeekEnded: true, locale: F.locale))
        #expect(ended.line == "1 missed this week, 67% over 4 weeks")
        let open = try #require(CutMeLogic.adherence([CutMeFacts.Adherence(planned: 3, completed: 3, missed: 0)],
                                                      currentWeekEnded: false, locale: F.locale))
        #expect(open.line == "100% over 4 weeks")
    }

    @Test func adherenceHiddenWithoutAPlanAndRollingWhenThisWeekIsEmpty() throws {
        #expect(CutMeLogic.adherence([], currentWeekEnded: false, locale: F.locale) == nil)
        #expect(CutMeLogic.adherence([.init(planned: 0, completed: 0, missed: 0)], currentWeekEnded: false, locale: F.locale) == nil)
        let rolling = try #require(CutMeLogic.adherence(
            [.init(planned: 4, completed: 3, missed: 1), .init(planned: 0, completed: 0, missed: 0)],
            currentWeekEnded: false, locale: F.locale))
        #expect(rolling.hero == "3 of 4")
        #expect(rolling.line == "Planned sessions over 4 weeks")
        #expect(rolling.segments == nil)
        // Too many sessions for segments.
        let big = try #require(CutMeLogic.adherence([.init(planned: 9, completed: 4, missed: 0)], currentWeekEnded: false, locale: F.locale))
        #expect(big.segments == nil)
    }

    // MARK: Trends

    @Test func trendsHeroIsThisWeekWithTwelveBars() {
        guard case .data(let value, let unit, let line, let bars) = F.model(F.full).trends else {
            Issue.record("no trends"); return
        }
        #expect(value == "24,860")
        #expect(unit == "kg")
        #expect(line == "This week, up 8% on the week before")
        #expect(bars.count == 12)
        #expect(bars.last?.isHighlighted == true)
        #expect(bars.last?.fraction == 1)
        #expect(bars.filter(\.isHighlighted).count == 1)
    }

    @Test func trendsFromAnOlderWeekKeepTheSlotsUpToNow() {
        let weeks = [CutMeFacts.Week(weekStart: F.monday(weeksAgo: 3), volumeKg: 10_000),
                     CutMeFacts.Week(weekStart: F.monday(weeksAgo: 5), volumeKg: 5_000)]
        let trends = CutMeLogic.trends(weeks, change: -12.4, unit: .kg, now: F.now, calendar: F.calendar, locale: F.locale)
        guard case .data(let value, _, let line, let bars) = trends else { Issue.record("no trends"); return }
        #expect(value == "10,000")
        #expect(line == "Week of 19 Oct, down 12% on the week before")
        #expect(bars.count == 12)
        // The last slot is this week (empty); the hero week is three back.
        #expect(bars[11].fraction == 0)
        #expect(bars[8].isHighlighted)
        #expect(bars[8].fraction == 1)
        #expect(bars[6].fraction == 0.5)
    }

    @Test func trendsLabelsLastWeekAndConvertsPounds() {
        let weeks = [CutMeFacts.Week(weekStart: F.monday(weeksAgo: 1), volumeKg: 1_000)]
        let trends = CutMeLogic.trends(weeks, change: 0.3, unit: .lb, now: F.now, calendar: F.calendar, locale: F.locale)
        guard case .data(let value, let unit, let line, _) = trends else { Issue.record("no trends"); return }
        #expect(value == "2,205")
        #expect(unit == "lb")
        #expect(line == "Last week")
    }

    // MARK: Balance

    @Test func balanceSplitsPushAndPullAndListsRecentMuscles() throws {
        let balance = try #require(F.model(F.full).balance)
        #expect(balance.push == "56%")
        #expect(balance.pull == "44%")
        #expect(abs((balance.pushFraction ?? 0) - 0.56) < 0.0001)
        #expect(balance.rows.map(\.title) == ["Quadriceps", "Chest", "Hamstrings"])
        #expect(balance.rows.map(\.value) == ["Today", "2 days ago", "3 days ago"])
    }

    @Test func balanceWithoutPushPullKeepsMusclesAndHidesWhenEmpty() throws {
        let rowsOnly = try #require(CutMeLogic.balance(push: 0, pull: 0, muscles: F.muscles, now: F.now, calendar: F.calendar))
        #expect(rowsOnly.push == nil)
        #expect(rowsOnly.rows.count == 3)
        #expect(CutMeLogic.balance(push: nil, pull: nil, muscles: [], now: F.now, calendar: F.calendar) == nil)
        #expect(CutMeLogic.daysAgo(F.daysAgo(1), now: F.now, calendar: F.calendar) == "Yesterday")
    }

    // MARK: Collection

    @Test func milestonesSkipRecordsAndLockedOnes() {
        let count = CutMeLogic.milestoneCount([
            ("ach.pr.bench", true), ("ach.first.workout", true), ("ach.ten.workouts", false), ("ach.streak.4", true)
        ])
        #expect(count == 2)
        let model = F.model(F.full)
        #expect(model.prCount == "31")
        #expect(model.milestoneCount == "12")
    }
}
