import Foundation
import Testing
@testable import WRKT

/// Shared fixtures for the Cut Plan logic and capture tests: November 2026, Monday first, UTC.
enum CutPlanFixtures {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }

    static func day(_ day: Int, month: Int = 11, year: Int = 2026, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Wednesday 11 November 2026, 10:00.
    static var today: Date { day(11, hour: 10) }

    static func strength(_ name: String, minutes: Int? = 52, source: CutPlanDayFacts.Strength.Source = .app) -> CutPlanDayFacts.Strength {
        .init(id: UUID(), source: source, name: name, durationSeconds: minutes.map { $0 * 60 })
    }

    static func cardio(_ name: String = "Running", km: Double = 6.2, seconds: Int = 2052) -> CutPlanDayFacts.Cardio {
        .init(id: UUID(), name: name, distanceKm: km, durationSeconds: seconds)
    }

    static func planned(_ name: String, exercises: Int = 6, status: WorkoutStatus = .scheduled) -> CutPlanDayFacts.Planned {
        .init(id: UUID(), name: name, exerciseCount: exercises, status: status)
    }

    /// A month like the mock's: strength, cardio and planned days around today.
    static var monthFacts: [Date: CutPlanDayFacts] {
        var facts: [Date: CutPlanDayFacts] = [:]
        for (number, name) in [(2, "Upper Body"), (4, "Lower Body"), (6, "Upper Body"), (9, "Lower Body")] {
            facts[day(number)] = CutPlanDayFacts(strength: [strength(name)])
        }
        facts[day(3)] = CutPlanDayFacts(cardio: [cardio()])
        facts[day(6)]?.cardio = [cardio(km: 5)]
        facts[day(7)] = CutPlanDayFacts(cardio: [cardio("Morning run")])
        facts[day(10)] = CutPlanDayFacts(planned: planned("Pull day"))
        facts[day(11)] = CutPlanDayFacts(planned: planned("Upper Body"))
        facts[day(13)] = CutPlanDayFacts(planned: planned("Lower Body"))
        facts[day(16)] = CutPlanDayFacts(planned: planned("Push day"))
        facts[day(18)] = CutPlanDayFacts(planned: planned("Pull day"))
        return facts
    }

    static func model(
        selected: Date,
        anchor: Date? = nil,
        facts: [Date: CutPlanDayFacts] = monthFacts,
        hasActivePlan: Bool = true,
        today: Date = today
    ) -> CutPlanModel {
        CutPlanLogic.model(monthAnchor: anchor ?? selected, selectedDay: selected, today: today,
                           facts: facts, hasActivePlan: hasActivePlan, calendar: calendar)
    }
}

struct CutPlanLogicTests {
    private let calendar = CutPlanFixtures.calendar
    private let today = CutPlanFixtures.today
    private func day(_ number: Int, month: Int = 11, year: Int = 2026) -> Date {
        CutPlanFixtures.day(number, month: month, year: year)
    }

    // MARK: Month grid

    @Test func monthGridPadsToWholeWeeksMondayFirst() {
        let days = CutPlanLogic.gridDays(for: today, calendar: calendar)
        #expect(days.count == 42)
        #expect(days.first == day(26, month: 10))
        #expect(days[6] == day(1))
        #expect(days.last == day(6, month: 12))
    }

    @Test func monthGridSundayFirst() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let days = CutPlanLogic.gridDays(for: today, calendar: sundayFirst)
        #expect(days.count == 35)
        #expect(days.first == day(1))
        #expect(days.last == day(5, month: 12))
        #expect(CutPlanLogic.weekdaySymbols(calendar: sundayFirst).first == "S")
    }

    @Test func monthGridCrossesDaylightSavingWithoutGaps() {
        var berlin = calendar
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let days = CutPlanLogic.gridDays(for: berlin.date(from: DateComponents(year: 2026, month: 3, day: 15))!, calendar: berlin)
        let numbers = days.map { berlin.component(.day, from: $0) }
        #expect(days.count % 7 == 0)
        #expect(numbers.contains(29) && numbers.contains(30))
        #expect(Set(days.map { berlin.startOfDay(for: $0) }).count == days.count)
    }

    @Test func monthHeaderValues() {
        let month = CutPlanLogic.month(anchor: today, selectedDay: today, today: today, facts: [:], calendar: calendar)
        #expect(month.title == "November 2026")
        #expect(month.weekdaySymbols == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(month.weeks.count == 6)
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        let cells = month.weeks.flatMap { $0 }
        #expect(cells.filter(\.isSelected).map(\.day) == [11])
        #expect(cells.filter(\.isToday).map(\.day) == [11])
        #expect(cells.filter(\.inMonth).count == 30)
        #expect(!cells[0].inMonth && cells[0].day == 26)
    }

    // MARK: Marks

    @Test func marksArePlainAndAtMostTwo() {
        typealias F = CutPlanDayFacts
        #expect(CutPlanLogic.marks(for: .empty) == [])
        #expect(CutPlanLogic.marks(for: F(strength: [CutPlanFixtures.strength("A")])) == [.strength])
        #expect(CutPlanLogic.marks(for: F(cardio: [CutPlanFixtures.cardio()])) == [.cardio])
        #expect(CutPlanLogic.marks(for: F(planned: CutPlanFixtures.planned("P"))) == [.planned])
        #expect(CutPlanLogic.marks(for: F(planned: CutPlanFixtures.planned("P", status: .completed))) == [.strength])
        #expect(CutPlanLogic.marks(for: F(strength: [CutPlanFixtures.strength("A")], cardio: [CutPlanFixtures.cardio()],
                                         planned: CutPlanFixtures.planned("P"))) == [.strength, .cardio])
        #expect(CutPlanLogic.marks(for: F(cardio: [CutPlanFixtures.cardio()], planned: CutPlanFixtures.planned("P"))) == [.planned, .cardio])
    }

    // MARK: Day state, in priority order

    @Test func todayPlannedComesFirstEvenWithHistory() {
        let planned = CutPlanFixtures.planned("Upper Body")
        let facts = CutPlanDayFacts(strength: [CutPlanFixtures.strength("Arms")], planned: planned)
        #expect(CutPlanLogic.state(for: today, facts: facts, today: today, hasActivePlan: true, calendar: calendar)
                == .plannedToday(planned))
    }

    @Test func historyComesBeforeAPlan() {
        let strength = [CutPlanFixtures.strength("Upper Body")]
        let completed = CutPlanDayFacts(strength: strength, planned: CutPlanFixtures.planned("Upper Body", status: .completed))
        #expect(CutPlanLogic.state(for: today, facts: completed, today: today, hasActivePlan: true, calendar: calendar)
                == .done(strength: strength, cardio: []))
        let past = CutPlanDayFacts(strength: strength, planned: CutPlanFixtures.planned("Legs"))
        #expect(CutPlanLogic.state(for: day(9), facts: past, today: today, hasActivePlan: true, calendar: calendar)
                == .done(strength: strength, cardio: []))
    }

    @Test func plannedOnOtherDays() {
        let planned = CutPlanFixtures.planned("Pull day")
        #expect(CutPlanLogic.state(for: day(10), facts: .init(planned: planned), today: today, hasActivePlan: true, calendar: calendar)
                == .planned(planned, isPast: true))
        #expect(CutPlanLogic.state(for: day(20), facts: .init(planned: planned), today: today, hasActivePlan: true, calendar: calendar)
                == .planned(planned, isPast: false))
    }

    @Test func emptyDaysByContext() {
        #expect(CutPlanLogic.state(for: today, facts: .empty, today: today, hasActivePlan: false, calendar: calendar)
                == .empty(.today, hasActivePlan: false))
        #expect(CutPlanLogic.state(for: day(1), facts: .empty, today: today, hasActivePlan: true, calendar: calendar)
                == .empty(.past, hasActivePlan: true))
        #expect(CutPlanLogic.state(for: day(30), facts: .empty, today: today, hasActivePlan: true, calendar: calendar)
                == .empty(.future, hasActivePlan: true))
        // A completed plan with no workout left on the day is not offered again.
        let orphan = CutPlanDayFacts(planned: CutPlanFixtures.planned("Legs", status: .completed))
        #expect(CutPlanLogic.state(for: day(9), facts: orphan, today: today, hasActivePlan: true, calendar: calendar)
                == .empty(.past, hasActivePlan: true))
    }

    // MARK: Panel

    private func panel(_ date: Date, _ facts: CutPlanDayFacts, active: Bool = true) -> CutPlanDayPanel {
        CutPlanLogic.panel(for: date, facts: facts, today: today, hasActivePlan: active, calendar: calendar)
    }

    @Test func panelTitles() {
        #expect(CutPlanLogic.panelTitle(for: today, today: today, calendar: calendar) == "Today")
        #expect(CutPlanLogic.panelTitle(for: day(20), today: today, calendar: calendar) == "Fri 20 Nov")
        #expect(CutPlanLogic.panelTitle(for: day(20, month: 10, year: 2025), today: today, calendar: calendar) == "Mon 20 Oct 2025")
    }

    @Test func panelTodayPlanned() {
        let planned = CutPlanFixtures.planned("Upper Body")
        let result = panel(today, .init(planned: planned))
        #expect(result == CutPlanDayPanel(title: "Today", isToday: true, headline: "Upper Body",
                                          line: "Planned, 6 exercises", actions: [.startPlanned(planned.id), .viewDay]))
    }

    @Test func panelTodayDoneWithOneWorkout() {
        let workout = CutPlanFixtures.strength("Upper Body", minutes: 65)
        let result = panel(today, .init(strength: [workout], planned: CutPlanFixtures.planned("Upper Body", status: .completed)))
        #expect(result.headline == "Upper Body")
        #expect(result.line == "Done, 1:05")
        #expect(result.actions == [.viewWorkout(.app(workout.id)), .viewDay])
    }

    @Test func panelPastStrengthWithRun() {
        let workout = CutPlanFixtures.strength("Lower Body")
        let result = panel(day(6), .init(strength: [workout], cardio: [CutPlanFixtures.cardio(km: 5)]))
        #expect(result.title == "Fri 6 Nov")
        #expect(!result.isToday)
        #expect(result.line == "Done, 52 min, plus 5.0 km running")
        #expect(result.actions == [.viewDay])
    }

    @Test func panelWatchStrengthOpensItsDetail() {
        let workout = CutPlanFixtures.strength("Traditional Strength", source: .healthKit)
        #expect(panel(day(4), .init(strength: [workout])).actions == [.viewWorkout(.healthKitStrength(workout.id)), .viewDay])
    }

    @Test func panelSeveralWorkouts() {
        let result = panel(day(4), .init(strength: [CutPlanFixtures.strength("Upper Body"), CutPlanFixtures.strength("Arms")]))
        #expect(result.headline == "2 workouts")
        #expect(result.line == "Upper Body, Arms")
        #expect(result.actions == [.viewDay])
    }

    @Test func panelPastCardio() {
        let run = CutPlanFixtures.cardio("Morning run")
        let result = panel(day(7), .init(cardio: [run]))
        #expect(result.headline == "Morning run")
        #expect(result.line == "Done, 6.2 km in 34:12")
        #expect(result.actions == [.viewWorkout(.cardio(run.id)), .viewDay])
        let yoga = panel(day(7), .init(cardio: [CutPlanFixtures.cardio("Yoga", km: 0, seconds: 3600)]))
        #expect(yoga.line == "Done, 1:00")
    }

    @Test func panelPastNothing() {
        #expect(panel(day(5), .empty) == CutPlanDayPanel(title: "Thu 5 Nov", isToday: false, headline: "Nothing logged",
                                                          line: nil, actions: [.logWorkout]))
    }

    @Test func panelPastMissedPlan() {
        let result = panel(day(10), .init(planned: CutPlanFixtures.planned("Pull day")))
        #expect(result.headline == "Pull day")
        #expect(result.line == "Missed, 6 exercises planned")
        #expect(result.actions == [.logWorkout, .viewDay])
        #expect(panel(day(10), .init(planned: CutPlanFixtures.planned("Pull day", exercises: 1, status: .skipped))).line
                == "Skipped, 1 exercise planned")
    }

    @Test func panelFuturePlanned() {
        let planned = CutPlanFixtures.planned("Lower Body")
        let result = panel(day(13), .init(planned: planned))
        #expect(result.title == "Fri 13 Nov")
        #expect(result.line == "Planned, 6 exercises")
        #expect(result.actions == [.editPlanned(planned.id), .viewDay])
    }

    @Test func panelFutureEmpty() {
        #expect(panel(day(14), .empty).headline == "Rest day")
        #expect(panel(day(14), .empty, active: false).headline == "Nothing planned")
        #expect(panel(day(14), .empty).actions == [.planWorkout])
    }

    @Test func panelTodayEmpty() {
        let result = panel(today, .empty, active: false)
        #expect(result.headline == "Nothing logged yet")
        #expect(result.actions == [.startWorkout])
    }

    @Test func panelNeverOffersMoreThanTwoActions() {
        let samples: [CutPlanDayState] = [
            .plannedToday(CutPlanFixtures.planned("A")),
            .done(strength: [CutPlanFixtures.strength("A")], cardio: [CutPlanFixtures.cardio()]),
            .done(strength: [CutPlanFixtures.strength("A")], cardio: []),
            .planned(CutPlanFixtures.planned("A"), isPast: true),
            .planned(CutPlanFixtures.planned("A"), isPast: false),
            .empty(.today, hasActivePlan: true), .empty(.past, hasActivePlan: true), .empty(.future, hasActivePlan: false)
        ]
        for state in samples {
            #expect((1...2).contains(CutPlanLogic.content(for: state).actions.count))
        }
    }

    @Test func actionLabelsAndEmphasis() {
        #expect(CutPlanLogic.label(for: .startPlanned(UUID())) == "Start workout")
        #expect(CutPlanLogic.label(for: .viewDay) == "View day")
        #expect(CutPlanLogic.label(for: .logWorkout) == "Log a workout")
        #expect(CutPlanLogic.label(for: .planWorkout) == "Plan a workout")
        #expect(CutPlanLogic.isPrimary(.startWorkout))
        #expect(!CutPlanLogic.isPrimary(.viewDay))
        #expect(!CutPlanLogic.isPrimary(.editPlanned(UUID())))
    }

    // MARK: Accessibility

    @Test func dayCellLabels() {
        let model = CutPlanFixtures.model(selected: day(13))
        let cells = model.month.weeks.flatMap { $0 }
        let friday = cells.first { $0.date == day(13) }
        #expect(friday?.accessibilityLabel == "Friday 13 November, planned: Lower Body, selected")
        #expect(cells.first { $0.date == day(11) }?.accessibilityLabel == "Wednesday 11 November, today, planned: Upper Body")
        #expect(cells.first { $0.date == day(6) }?.accessibilityLabel == "Friday 6 November, done: Upper Body, cardio: Running")
        #expect(cells.first { $0.date == day(5) }?.accessibilityLabel == "Thursday 5 November")
    }

    // MARK: Formatting

    @Test func durations() {
        #expect(CutPlanLogic.duration(3120) == "52 min")
        #expect(CutPlanLogic.duration(3600) == "1:00")
        #expect(CutPlanLogic.duration(3900) == "1:05")
        #expect(CutPlanLogic.clock(2052) == "34:12")
        #expect(CutPlanLogic.clock(3900) == "1:05")
        #expect(CutPlanLogic.distance(6.25) == "6.2 km" || CutPlanLogic.distance(6.25) == "6.3 km")
    }

    // MARK: Facts

    @Test func factsFoldWorkoutsRunsAndPlans() {
        let days = CutPlanLogic.gridDays(for: today, calendar: calendar)
        let watchUUID = UUID(), matchedUUID = UUID(), ignoredUUID = UUID()
        var app = CompletedWorkout(date: day(9, month: 11).addingTimeInterval(18 * 3600),
                                   startedAt: day(9).addingTimeInterval(17 * 3600), entries: [], workoutName: "Legs")
        app.matchedHealthKitUUID = matchedUUID
        let outside = CompletedWorkout(date: day(1, month: 9), entries: [], workoutName: "Old")
        let runs = [
            Run(date: day(9).addingTimeInterval(8 * 3600), distanceKm: 0, durationSec: 1800, healthKitUUID: matchedUUID,
                workoutType: "Traditional Strength Training"),
            Run(date: day(4).addingTimeInterval(8 * 3600), distanceKm: 0, durationSec: 2400, healthKitUUID: watchUUID,
                workoutType: "Traditional Strength Training"),
            Run(date: day(4).addingTimeInterval(9 * 3600), distanceKm: 0, durationSec: 2400, healthKitUUID: ignoredUUID,
                workoutType: "Traditional Strength Training"),
            Run(date: day(3).addingTimeInterval(7 * 3600), distanceKm: 6.2, durationSec: 2052, healthKitUUID: UUID(),
                workoutType: "Running")
        ]
        let first = CutPlanFixtures.planned("Push"), second = CutPlanFixtures.planned("Pull")
        let facts = CutPlanLogic.facts(
            days: days, workouts: [app, outside], runs: runs,
            planned: [(day(16), first), (day(16).addingTimeInterval(60), second)],
            ignoredHealthKitUUIDs: [ignoredUUID], calendar: calendar,
            workoutName: { $0.workoutName ?? "Workout" }, healthKitStrengthName: { _ in "Watch strength" })

        #expect(facts.count == days.count)
        #expect(facts[day(9)]?.strength.map(\.name) == ["Legs"])
        #expect(facts[day(9)]?.strength.first?.durationSeconds == 3600)
        #expect(facts[day(4)]?.strength.map(\.name) == ["Watch strength"])
        #expect(facts[day(4)]?.strength.first?.source == .healthKit)
        #expect(facts[day(3)]?.cardio.map(\.name) == ["Running"])
        #expect(facts[day(16)]?.planned == first)
        #expect(facts.values.allSatisfy { !$0.strength.contains { $0.name == "Old" } })
    }

    @Test func cardioNamePrefersTheActivityName() {
        #expect(CutPlanLogic.cardioName(Run(distanceKm: 5, durationSec: 1500, workoutType: "Cycling", workoutName: "Commute")) == "Commute")
        #expect(CutPlanLogic.cardioName(Run(distanceKm: 5, durationSec: 1500, workoutType: "Cycling", workoutName: "  ")) == "Cycling")
    }

    // MARK: Week, gestures, header

    @Test func frozenWeekRule() {
        let current = day(9)
        #expect(CutPlanLogic.isFrozenWeek(weekStart: day(2), currentWeekStart: current, protectedWeekStart: nil,
                                          streakFrozen: true, calendar: calendar))
        #expect(!CutPlanLogic.isFrozenWeek(weekStart: day(2), currentWeekStart: current, protectedWeekStart: nil,
                                           streakFrozen: false, calendar: calendar))
        #expect(CutPlanLogic.isFrozenWeek(weekStart: day(26, month: 10), currentWeekStart: current,
                                          protectedWeekStart: day(26, month: 10), streakFrozen: false, calendar: calendar))
    }

    @Test func swipeSteps() {
        #expect(CutPlanLogic.swipeStep(translation: CGSize(width: -90, height: 10)) == 1)
        #expect(CutPlanLogic.swipeStep(translation: CGSize(width: 90, height: 10)) == -1)
        #expect(CutPlanLogic.swipeStep(translation: CGSize(width: 40, height: 0)) == 0)
        #expect(CutPlanLogic.swipeStep(translation: CGSize(width: 90, height: 80)) == 0)
    }

    @Test func goToTodayOnlyAwayFromTheCurrentMonth() {
        #expect(!CutPlanFixtures.model(selected: day(20)).showsGoToToday)
        #expect(CutPlanFixtures.model(selected: day(1, month: 12)).showsGoToToday)
    }
}
