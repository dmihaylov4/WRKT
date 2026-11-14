import Foundation
import Testing
@testable import WRKT

/// The home screen widgets' snapshot, staleness rule, copy and publishing.
@MainActor
struct HomeWidgetLogicTests {
    // MARK: Fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Wednesday 11 November 2026, 10:00 UTC.
    private var now: Date { date(day: 11, hour: 10) }

    private func date(day: Int, hour: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Monday 16 November, the end of the goal week that contains `now` (Monday anchor).
    private var weekEnd: Date { date(day: 16) }

    private func week(strength: Int = 2, cardio: Int = 45, streak: Int = 3, met: Bool = false) -> HomeWidgetSnapshot.Week {
        HomeWidgetSnapshot.Week(strengthDone: met ? 4 : strength, strengthTarget: 4,
                                cardioMinutes: met ? 150 : cardio, cardioTarget: 150,
                                streakWeeks: streak, weekEnd: weekEnd)
    }

    private func snapshot(
        _ today: HomeWidgetSnapshot.Today,
        next: HomeWidgetSnapshot.Session? = nil,
        week: HomeWidgetSnapshot.Week? = nil
    ) -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(writtenAt: now, day: calendar.startOfDay(for: now), today: today,
                           nextSession: next, week: week)
    }

    private func session(_ name: String, day: Int) -> HomeWidgetSnapshot.Session {
        .init(name: name, date: date(day: day, hour: 7))
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-widget-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Building

    @Test func builderMapsEveryHeroState() {
        let builder = HomeWidgetSnapshotBuilder.self
        #expect(builder.today(from: .planned(name: "Upper Body", exerciseCount: 5)) == .planned(name: "Upper Body", exerciseCount: 5))
        #expect(builder.today(from: .live(name: "Push", exercisesDone: 1, exerciseCount: 4, startDate: now)) == .inProgress(name: "Push"))
        #expect(builder.today(from: .resting(nextLine: "Bench 85 kg x 6", countdown: .fixed(60)))
                == .inProgress(name: CutTrainLogic.liveWorkoutName))
        #expect(builder.today(from: .doneToday(next: nil)) == .doneToday)
        #expect(builder.today(from: .restDay(next: nil)) == .restDay)
        #expect(builder.today(from: .noPlan) == .noPlan)
    }

    @Test func builderSnapshotFromFixtureValues() {
        var outlook = PlanOutlook()
        outlook.hasActivePlan = true
        outlook.nextSession = .init(name: "Lower Body", date: date(day: 13, hour: 7))
        let snapshot = HomeWidgetSnapshotBuilder.snapshot(
            hero: .restDay(next: outlook.nextSession),
            outlook: outlook,
            weeklyGoal: CutTrainWeeklyGoal(strengthDone: 2, strengthTarget: 4, cardioMinutes: 45, cardioTarget: 150),
            streakWeeks: 3,
            anchorWeekday: 2,
            now: now,
            calendar: calendar
        )
        #expect(snapshot.version == HomeWidgetSnapshot.currentVersion)
        #expect(snapshot.writtenAt == now)
        #expect(snapshot.day == date(day: 11))
        #expect(snapshot.today == .restDay)
        #expect(snapshot.nextSession == .init(name: "Lower Body", date: date(day: 13, hour: 7)))
        #expect(snapshot.week == week())
    }

    @Test func builderDropsNextSessionWithoutPlanAndGoalWithoutStats() {
        var outlook = PlanOutlook()
        outlook.nextSession = .init(name: "Stale", date: date(day: 13))
        let snapshot = HomeWidgetSnapshotBuilder.snapshot(
            hero: .noPlan, outlook: outlook, weeklyGoal: nil, streakWeeks: -1,
            anchorWeekday: 2, now: now, calendar: calendar
        )
        #expect(snapshot.nextSession == nil)
        #expect(snapshot.week == nil)
    }

    @Test func weekEndFollowsAnchorWeekday() {
        // Monday anchor: the week of Wed 11 Nov ends Mon 16 Nov.
        #expect(HomeWidgetSnapshotBuilder.weekEnd(now: now, anchorWeekday: 2, calendar: calendar) == date(day: 16))
        // Sunday anchor: ends Sun 15 Nov.
        #expect(HomeWidgetSnapshotBuilder.weekEnd(now: now, anchorWeekday: 1, calendar: calendar) == date(day: 15))
        // Wednesday anchor on a Wednesday: the week started today and ends next Wednesday.
        #expect(HomeWidgetSnapshotBuilder.weekEnd(now: now, anchorWeekday: 4, calendar: calendar) == date(day: 18))
    }

    // MARK: Store and publisher

    @Test func storeRoundTrip() throws {
        let store = HomeWidgetSnapshotStore(directory: try tempDirectory())
        #expect(store.read() == nil)
        let written = snapshot(.planned(name: "Upper Body", exerciseCount: 5),
                               next: session("Lower Body", day: 13), week: week())
        #expect(store.write(written))
        #expect(store.read() == written)
    }

    @Test func storeWithoutContainerDoesNothing() {
        let store = HomeWidgetSnapshotStore(directory: nil)
        #expect(store.write(snapshot(.noPlan)) == false)
        #expect(store.read() == nil)
    }

    @Test func storeIgnoresOtherVersions() throws {
        let store = HomeWidgetSnapshotStore(directory: try tempDirectory())
        var future = snapshot(.noPlan)
        future.version = HomeWidgetSnapshot.currentVersion + 1
        #expect(store.write(future))
        #expect(store.read() == nil)
    }

    @Test func publisherSkipsUnchangedContent() throws {
        let directory = try tempDirectory()
        var reloads = 0
        let publisher = HomeWidgetPublisher(store: HomeWidgetSnapshotStore(directory: directory)) { reloads += 1 }
        let first = snapshot(.restDay, week: week())
        #expect(publisher.publish(first))
        #expect(reloads == 1)

        var later = first
        later.writtenAt = now.addingTimeInterval(600)
        #expect(publisher.publish(later) == false)
        #expect(reloads == 1)

        var changed = first
        changed.week?.strengthDone = 3
        #expect(publisher.publish(changed))
        #expect(reloads == 2)

        // A fresh publisher (app relaunch) compares with what is on disk.
        var relaunchReloads = 0
        let relaunched = HomeWidgetPublisher(store: HomeWidgetSnapshotStore(directory: directory)) { relaunchReloads += 1 }
        #expect(relaunched.publish(changed) == false)
        #expect(relaunchReloads == 0)
    }

    // MARK: Staleness: today

    @Test func sameDayShowsSnapshotAsWritten() {
        let next = session("Lower Body", day: 13)
        let cases: [(HomeWidgetSnapshot.Today, HomeWidgetContent.Today)] = [
            (.planned(name: "Upper Body", exerciseCount: 5), .planned(name: "Upper Body", exerciseCount: 5)),
            (.inProgress(name: "Push"), .inProgress(name: "Push")),
            (.doneToday, .doneToday(next: next)),
            (.restDay, .restDay(next: next)),
            (.noPlan, .noPlan),
        ]
        for (stored, expected) in cases {
            let content = HomeWidgetLogic.content(for: snapshot(stored, next: next), now: date(day: 11, hour: 23), calendar: calendar)
            #expect(content.today == expected)
        }
    }

    @Test func noSnapshotIsEmpty() {
        #expect(HomeWidgetLogic.content(for: nil, now: now, calendar: calendar) == .empty)
    }

    @Test func nextDayCarriesInProgressAndNoPlan() {
        let tomorrow = date(day: 12, hour: 8)
        #expect(HomeWidgetLogic.content(for: snapshot(.inProgress(name: "Push")), now: tomorrow, calendar: calendar).today
                == .inProgress(name: "Push"))
        #expect(HomeWidgetLogic.content(for: snapshot(.noPlan), now: tomorrow, calendar: calendar).today == .noPlan)
    }

    @Test func nextDayWithSessionTodayBecomesPlannedWithoutCount() {
        for stored: HomeWidgetSnapshot.Today in [.planned(name: "Upper Body", exerciseCount: 5), .doneToday, .restDay] {
            let content = HomeWidgetLogic.content(for: snapshot(stored, next: session("Lower Body", day: 12)),
                                                  now: date(day: 12, hour: 8), calendar: calendar)
            #expect(content.today == .planned(name: "Lower Body", exerciseCount: nil))
        }
    }

    @Test func nextDayWithLaterSessionIsRestDay() {
        let next = session("Lower Body", day: 14)
        let content = HomeWidgetLogic.content(for: snapshot(.doneToday, next: next), now: date(day: 12, hour: 8), calendar: calendar)
        #expect(content.today == .restDay(next: next))
    }

    @Test func nextDayWithoutOrPastSessionIsUnknown() {
        let tomorrow = date(day: 12, hour: 8)
        #expect(HomeWidgetLogic.content(for: snapshot(.restDay), now: tomorrow, calendar: calendar).today == .unknown)
        #expect(HomeWidgetLogic.content(for: snapshot(.planned(name: "Upper", exerciseCount: 3)), now: tomorrow,
                                        calendar: calendar).today == .unknown)
        // The stored next session was on day 12; on day 13 it is in the past.
        #expect(HomeWidgetLogic.content(for: snapshot(.restDay, next: session("Lower Body", day: 12)),
                                        now: date(day: 13, hour: 8), calendar: calendar).today == .unknown)
    }

    @Test func sameDayNextSessionOnTodayIsNotNamedAsNext() {
        // A next session that is not after today is dropped from "Next:".
        let content = HomeWidgetLogic.content(for: snapshot(.restDay, next: session("Odd", day: 11)), now: now, calendar: calendar)
        #expect(content.today == .restDay(next: nil))
    }

    // MARK: Staleness: week

    @Test func weekBeforeEndIsAsWritten() {
        let content = HomeWidgetLogic.content(for: snapshot(.restDay, week: week()), now: date(day: 15, hour: 23), calendar: calendar)
        #expect(content.week == .init(strengthDone: 2, strengthTarget: 4, cardioMinutes: 45, cardioTarget: 150, streakWeeks: 3))
    }

    @Test func weekRolloverResetsCountsAndDropsStreakWhenMissed() {
        let content = HomeWidgetLogic.content(for: snapshot(.restDay, week: week()), now: weekEnd, calendar: calendar)
        #expect(content.week == .init(strengthDone: 0, strengthTarget: 4, cardioMinutes: 0, cardioTarget: 150, streakWeeks: nil))
    }

    @Test func weekRolloverKeepsStreakWhenMetForOneWeek() {
        let met = snapshot(.restDay, week: week(met: true))
        let nextWeek = HomeWidgetLogic.content(for: met, now: date(day: 20), calendar: calendar)
        #expect(nextWeek.week == .init(strengthDone: 0, strengthTarget: 4, cardioMinutes: 0, cardioTarget: 150, streakWeeks: 3))
        // A further week with no app run may have broken it.
        let twoWeeks = HomeWidgetLogic.content(for: met, now: date(day: 23), calendar: calendar)
        #expect(twoWeeks.week?.streakWeeks == nil)
        #expect(twoWeeks.week?.strengthDone == 0)
    }

    @Test func noGoalHasNoWeek() {
        #expect(HomeWidgetLogic.content(for: snapshot(.restDay), now: now, calendar: calendar).week == nil)
    }

    // MARK: Timeline

    @Test func entryDatesAreNowAndMidnight() {
        let dates = HomeWidgetLogic.entryDates(now: now, snapshot: snapshot(.restDay, week: week()), calendar: calendar)
        #expect(dates == [now, date(day: 12)])
    }

    @Test func entryDatesIncludeWeekEndBeforeMidnight() {
        var weekly = week()
        weekly.weekEnd = date(day: 11, hour: 18)
        let dates = HomeWidgetLogic.entryDates(now: now, snapshot: snapshot(.restDay, week: weekly), calendar: calendar)
        #expect(dates == [now, date(day: 11, hour: 18), date(day: 12)])
    }

    @Test func entryDatesWithoutSnapshot() {
        #expect(HomeWidgetLogic.entryDates(now: now, snapshot: nil, calendar: calendar) == [now, date(day: 12)])
        #expect(HomeWidgetLogic.nextMidnight(after: date(day: 11), calendar: calendar) == date(day: 12))
    }

    // MARK: Copy

    @Test func todayLines() {
        let next = session("Lower Body", day: 12)
        #expect(HomeWidgetLogic.todayLine(.planned(name: "Upper", exerciseCount: 5), now: now, calendar: calendar) == "Today, 5 exercises")
        #expect(HomeWidgetLogic.todayLine(.planned(name: "Upper", exerciseCount: 1), now: now, calendar: calendar) == "Today, 1 exercise")
        #expect(HomeWidgetLogic.todayLine(.planned(name: "Upper", exerciseCount: nil), now: now, calendar: calendar) == "Today")
        #expect(HomeWidgetLogic.todayLine(.inProgress(name: "Push"), now: now, calendar: calendar) == "In progress")
        #expect(HomeWidgetLogic.todayLine(.restDay(next: next), now: now, calendar: calendar) == "Next: Lower Body, tomorrow")
        #expect(HomeWidgetLogic.todayLine(.doneToday(next: session("Pull", day: 14)), now: now, calendar: calendar)
                == "Next: Pull, Saturday")
        #expect(HomeWidgetLogic.todayLine(.restDay(next: nil), now: now, calendar: calendar) == "Today")
        #expect(HomeWidgetLogic.todayLine(.noPlan, now: now, calendar: calendar) == "Today")
        #expect(HomeWidgetLogic.todayLine(.unknown, now: now, calendar: calendar) == "Today")
    }

    @Test func todayTitles() {
        #expect(HomeWidgetLogic.todayTitle(.planned(name: "Upper Body", exerciseCount: 5)) == "Upper Body")
        #expect(HomeWidgetLogic.todayTitle(.inProgress(name: "Push")) == "Push")
        #expect(HomeWidgetLogic.todayTitle(.restDay(next: nil)) == "Rest day")
        #expect(HomeWidgetLogic.todayTitle(.doneToday(next: nil)) == "Done today")
        #expect(HomeWidgetLogic.todayTitle(.noPlan) == "No plan yet")
        #expect(HomeWidgetLogic.todayTitle(.unknown) == "Train")
    }

    @Test func fieldTone() {
        #expect(HomeWidgetLogic.fieldIsLime(.planned(name: "A", exerciseCount: 1)))
        #expect(HomeWidgetLogic.fieldIsLime(.inProgress(name: "A")))
        #expect(HomeWidgetLogic.fieldIsLime(.noPlan))
        #expect(HomeWidgetLogic.fieldIsLime(.unknown))
        #expect(!HomeWidgetLogic.fieldIsLime(.restDay(next: nil)))
        #expect(!HomeWidgetLogic.fieldIsLime(.doneToday(next: nil)))
    }

    @Test func heroLinesMatchCutHeroText() {
        for text in ["Upper Body", "No plan yet", "Rest day", "Done today", "Train", "Full Body Strength A", "Live workout"] {
            #expect(HomeWidgetLogic.heroLines(text) == CutHeroText.lines(of: CutHeroText.balancedLines(text)), "\(text)")
        }
    }

    @Test func relativeDayMatchesTrainTab() {
        for day in [10, 11, 12, 13, 17, 18, 25] {
            let target = date(day: day, hour: 7)
            #expect(HomeWidgetLogic.relativeDay(target, now: now, calendar: calendar)
                    == CutTrainLogic.relativeDay(target, now: now, calendar: calendar, style: .long), "day \(day)")
        }
    }

    @Test func fractionsAndWeeks() {
        #expect(HomeWidgetLogic.fraction(2, of: 4) == 0.5)
        #expect(HomeWidgetLogic.fraction(6, of: 4) == 1)
        #expect(HomeWidgetLogic.fraction(1, of: 0) == 0)
        #expect(HomeWidgetLogic.fraction(-1, of: 4) == 0)
        #expect(HomeWidgetLogic.weeks(1) == "1 week")
        #expect(HomeWidgetLogic.weeks(3) == "3 weeks")
    }

    // MARK: Accessibility

    @Test func weeklyGoalSentenceMatchesTrainTab() {
        let goal = CutTrainWeeklyGoal(strengthDone: 2, strengthTarget: 4, cardioMinutes: 45, cardioTarget: 150)
        let week = HomeWidgetContent.Week(strengthDone: 2, strengthTarget: 4, cardioMinutes: 45, cardioTarget: 150, streakWeeks: 3)
        #expect(HomeWidgetLogic.weeklyGoalSentence(week) == CutTrainLogic.weeklyGoalAccessibilityLabel(goal) + ".")
        #expect(HomeWidgetLogic.weeklyGoalSentence(nil) == "No weekly goal set yet.")
    }

    @Test func todaySentences() {
        let next = session("Lower Body", day: 12)
        #expect(HomeWidgetLogic.todaySentence(.planned(name: "Upper Body", exerciseCount: 5), now: now, calendar: calendar)
                == "Today: Upper Body, 5 exercises.")
        #expect(HomeWidgetLogic.todaySentence(.planned(name: "Upper Body", exerciseCount: nil), now: now, calendar: calendar)
                == "Today: Upper Body.")
        #expect(HomeWidgetLogic.todaySentence(.inProgress(name: "Push"), now: now, calendar: calendar)
                == "Workout in progress: Push.")
        #expect(HomeWidgetLogic.todaySentence(.restDay(next: next), now: now, calendar: calendar)
                == "Today is a rest day, next: Lower Body tomorrow.")
        #expect(HomeWidgetLogic.todaySentence(.doneToday(next: nil), now: now, calendar: calendar)
                == "Today's session is done.")
        #expect(HomeWidgetLogic.todaySentence(.noPlan, now: now, calendar: calendar) == "No training plan yet.")
        #expect(HomeWidgetLogic.todaySentence(.unknown, now: now, calendar: calendar)
                == "Today: open VOLIA to see your session.")
    }

    @Test func todayAndWeekSentences() {
        let today = HomeWidgetContent.Today.planned(name: "Upper Body", exerciseCount: 5)
        let streak = HomeWidgetContent(today: today, week: .init(strengthDone: 2, strengthTarget: 4, cardioMinutes: 45,
                                                                 cardioTarget: 150, streakWeeks: 3))
        #expect(HomeWidgetLogic.todayAndWeekSentence(streak, now: now, calendar: calendar)
                == "Today: Upper Body, 5 exercises; strength 2 of 4 days this week, 3 weeks streak.")
        let noStreak = HomeWidgetContent(today: today, week: .init(strengthDone: 1, strengthTarget: 1, cardioMinutes: 45,
                                                                   cardioTarget: 150, streakWeeks: nil))
        #expect(HomeWidgetLogic.todayAndWeekSentence(noStreak, now: now, calendar: calendar)
                == "Today: Upper Body, 5 exercises; strength 1 of 1 day this week, cardio 45 of 150 minutes.")
        #expect(HomeWidgetLogic.todayAndWeekSentence(HomeWidgetContent(today: .noPlan, week: nil), now: now, calendar: calendar)
                == "No training plan yet; no weekly goal set yet.")
    }

    // MARK: Deep link

    @Test func trainDeepLink() {
        #expect(HomeWidgetShared.trainURL.absoluteString == "wrkt://train")
        #expect(HomeWidgetShared.isTrainURL(HomeWidgetShared.trainURL))
        #expect(HomeWidgetShared.isTrainURL(URL(string: "WRKT://Train")!))
        #expect(!HomeWidgetShared.isTrainURL(URL(string: "wrkt://auth")!))
        #expect(!HomeWidgetShared.isTrainURL(URL(string: "https://train")!))
        #expect(HomeWidgetShared.Kind.all.count == 3)
    }
}
