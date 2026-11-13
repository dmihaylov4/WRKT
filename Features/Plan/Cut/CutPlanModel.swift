//
//  CutPlanModel.swift
//  WRKT
//
//  Cut Plan tab: the plain values the screen shows and the pure logic that picks them.
//  Nothing here reads a service; CutPlanHost feeds it from the workout store, the planned
//  workouts it fetches and the plan library, and tests and captures feed it fixtures.
//

import Foundation

// MARK: - Day facts

/// What happened, or is planned, on one day, as plain values.
struct CutPlanDayFacts: Equatable {
    /// A strength session: logged in the app, or an unmatched Apple Watch strength workout.
    struct Strength: Equatable {
        enum Source: Equatable { case app, healthKit }
        let id: UUID
        let source: Source
        let name: String
        let durationSeconds: Int?
    }

    /// A cardio activity from Health.
    struct Cardio: Equatable {
        let id: UUID
        let name: String
        let distanceKm: Double
        let durationSeconds: Int
    }

    /// The planned session scheduled for the day.
    struct Planned: Equatable {
        let id: UUID
        let name: String
        let exerciseCount: Int
        let status: WorkoutStatus
    }

    var strength: [Strength] = []
    var cardio: [Cardio] = []
    var planned: Planned?

    static let empty = CutPlanDayFacts()

    var hasHistory: Bool { !strength.isEmpty || !cardio.isEmpty }
}

// MARK: - Screen values

/// A small mark under a day number.
enum CutPlanMark: Equatable {
    /// Strength done: lime, filled.
    case strength
    /// Cardio done: white, filled.
    case cardio
    /// A planned session not done yet: lime outline.
    case planned
}

struct CutPlanDayCell: Equatable, Identifiable {
    let date: Date
    let day: Int
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let marks: [CutPlanMark]
    let accessibilityLabel: String

    var id: Date { date }
}

struct CutPlanMonth: Equatable {
    /// "November 2026".
    let title: String
    /// Very short weekday symbols starting at the calendar's first weekday.
    let weekdaySymbols: [String]
    /// Rows of seven days, padded with days of the neighbouring months.
    let weeks: [[CutPlanDayCell]]
}

/// Where "View workout" goes.
enum CutPlanWorkoutRef: Hashable {
    case app(UUID)
    case healthKitStrength(UUID)
    case cardio(UUID)
}

/// The panel under the calendar: everything in it is about the selected day.
struct CutPlanDayPanel: Equatable {
    enum Action: Equatable, Hashable {
        /// Start today's planned session (the live workout).
        case startPlanned(UUID)
        /// Start a workout without a plan (the workout type selector).
        case startWorkout
        case viewWorkout(CutPlanWorkoutRef)
        /// The full day: summary, actions, planned session, workouts and cardio.
        case viewDay
        /// Log a past workout (retrospective builder).
        case logWorkout
        /// Plan a session on an empty future day (planned workout editor).
        case planWorkout
        /// Edit the planned session (planned workout editor).
        case editPlanned(UUID)
    }

    /// "Today", or "Tue 20 Oct" (shown uppercase).
    let title: String
    let isToday: Bool
    /// The workout or the state: "Lower Body", "Nothing logged", "Rest day".
    let headline: String
    /// One supporting line, or none.
    let line: String?
    /// At most two.
    let actions: [Action]
}

/// The selected day's state, in priority order.
enum CutPlanDayState: Equatable {
    /// Today's planned session is still to do.
    case plannedToday(CutPlanDayFacts.Planned)
    /// Strength or cardio was done.
    case done(strength: [CutPlanDayFacts.Strength], cardio: [CutPlanDayFacts.Cardio])
    /// A planned session on another day: upcoming, or missed in the past.
    case planned(CutPlanDayFacts.Planned, isPast: Bool)
    /// Nothing done and nothing planned.
    case empty(Date.DayContext, hasActivePlan: Bool)
}

struct CutPlanModel: Equatable {
    var month: CutPlanMonth
    var panel: CutPlanDayPanel
    /// The month on screen is not the current month: the header offers "Go to today".
    var showsGoToToday: Bool
}

/// Elements the first-run tutorial points at.
enum CutPlanTutorialTarget: Hashable, CaseIterable {
    case editPlan, week, calendar, day
}

// MARK: - Logic

enum CutPlanLogic {
    // MARK: Grid

    /// Every day shown for the month of `anchor`: the month itself padded to whole weeks
    /// starting at the calendar's first weekday.
    static func gridDays(for anchor: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first) - calendar.firstWeekday
        let lead = weekday < 0 ? weekday + 7 : weekday
        var days: [Date] = []
        for offset in stride(from: lead, to: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: first) { days.append(day) }
        }
        var day = first
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        while days.count % 7 != 0, let last = days.last,
              let next = calendar.date(byAdding: .day, value: 1, to: last) {
            days.append(next)
        }
        return days
    }

    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    static func monthTitle(_ anchor: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: anchor)
        let year = calendar.component(.year, from: anchor)
        return "\(calendar.standaloneMonthSymbols[month - 1]) \(year)"
    }

    static func month(
        anchor: Date,
        selectedDay: Date,
        today: Date,
        facts: [Date: CutPlanDayFacts],
        calendar: Calendar
    ) -> CutPlanMonth {
        let days = gridDays(for: anchor, calendar: calendar)
        let cells = days.map { date -> CutPlanDayCell in
            let dayFacts = facts[calendar.startOfDay(for: date)] ?? .empty
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
            return CutPlanDayCell(
                date: date,
                day: calendar.component(.day, from: date),
                inMonth: calendar.isDate(date, equalTo: anchor, toGranularity: .month),
                isToday: isToday,
                isSelected: isSelected,
                marks: marks(for: dayFacts),
                accessibilityLabel: accessibilityLabel(for: date, facts: dayFacts, isToday: isToday,
                                                       isSelected: isSelected, calendar: calendar)
            )
        }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        return CutPlanMonth(title: monthTitle(anchor, calendar: calendar),
                            weekdaySymbols: weekdaySymbols(calendar: calendar),
                            weeks: weeks)
    }

    /// At most two marks: strength (or a planned session still to do), then cardio.
    static func marks(for facts: CutPlanDayFacts) -> [CutPlanMark] {
        var marks: [CutPlanMark] = []
        if !facts.strength.isEmpty {
            marks.append(.strength)
        } else if let planned = facts.planned {
            marks.append(planned.status == .completed ? .strength : .planned)
        }
        if !facts.cardio.isEmpty {
            marks.append(.cardio)
        }
        return marks
    }

    /// "Tuesday 20 October, planned: Lower Body, selected".
    static func accessibilityLabel(
        for date: Date,
        facts: CutPlanDayFacts,
        isToday: Bool,
        isSelected: Bool,
        calendar: Calendar
    ) -> String {
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
        var parts = ["\(weekday) \(calendar.component(.day, from: date)) \(month)"]
        if isToday { parts.append("today") }
        if !facts.strength.isEmpty {
            parts.append("done: " + facts.strength.map(\.name).joined(separator: ", "))
        }
        if !facts.cardio.isEmpty {
            parts.append("cardio: " + facts.cardio.map(\.name).joined(separator: ", "))
        }
        if let planned = facts.planned, facts.strength.isEmpty, planned.status != .completed {
            parts.append("\(plannedStatusWord(planned.status)): \(planned.name)")
        }
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    private static func plannedStatusWord(_ status: WorkoutStatus) -> String {
        switch status {
        case .skipped: "skipped"
        case .rescheduled: "rescheduled"
        case .partial: "partly done"
        case .scheduled, .completed: "planned"
        }
    }

    /// Month navigation from a horizontal swipe on the grid: 1 next, -1 previous, 0 none.
    static func swipeStep(translation: CGSize, threshold: CGFloat = 60) -> Int {
        let horizontal = translation.width
        guard abs(horizontal) > abs(translation.height) * 1.5, abs(horizontal) > threshold else { return 0 }
        return horizontal < 0 ? 1 : -1
    }

    // MARK: Day state

    static func dayContext(_ date: Date, today: Date, calendar: Calendar) -> Date.DayContext {
        if calendar.isDate(date, inSameDayAs: today) { return .today }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: today) ? .past : .future
    }

    static func state(
        for date: Date,
        facts: CutPlanDayFacts,
        today: Date,
        hasActivePlan: Bool,
        calendar: Calendar
    ) -> CutPlanDayState {
        let context = dayContext(date, today: today, calendar: calendar)
        if context == .today, let planned = facts.planned, isStillToDo(planned.status) {
            return .plannedToday(planned)
        }
        if facts.hasHistory {
            return .done(strength: facts.strength, cardio: facts.cardio)
        }
        if let planned = facts.planned, planned.status != .completed {
            return .planned(planned, isPast: context == .past)
        }
        return .empty(context, hasActivePlan: hasActivePlan)
    }

    private static func isStillToDo(_ status: WorkoutStatus) -> Bool {
        status == .scheduled || status == .rescheduled
    }

    // MARK: Panel

    /// "Today", or "Tue 20 Oct"; another year adds it ("Tue 20 Oct 2025").
    static func panelTitle(for date: Date, today: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let month = calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1]
        var title = "\(weekday) \(calendar.component(.day, from: date)) \(month)"
        let year = calendar.component(.year, from: date)
        if year != calendar.component(.year, from: today) { title += " \(year)" }
        return title
    }

    static func panel(
        for date: Date,
        facts: CutPlanDayFacts,
        today: Date,
        hasActivePlan: Bool,
        calendar: Calendar
    ) -> CutPlanDayPanel {
        let title = panelTitle(for: date, today: today, calendar: calendar)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let state = state(for: date, facts: facts, today: today, hasActivePlan: hasActivePlan, calendar: calendar)
        let (headline, line, actions) = content(for: state)
        return CutPlanDayPanel(title: title, isToday: isToday, headline: headline, line: line, actions: actions)
    }

    static func content(for state: CutPlanDayState) -> (headline: String, line: String?, actions: [CutPlanDayPanel.Action]) {
        switch state {
        case .plannedToday(let planned):
            return (planned.name, "Planned, " + exercises(planned.exerciseCount), [.startPlanned(planned.id), .viewDay])

        case .done(let strength, let cardio):
            let total = strength.count + cardio.count
            var actions: [CutPlanDayPanel.Action] = []
            if total == 1 {
                if let only = strength.first {
                    actions.append(.viewWorkout(only.source == .app ? .app(only.id) : .healthKitStrength(only.id)))
                } else if let only = cardio.first {
                    actions.append(.viewWorkout(.cardio(only.id)))
                }
            }
            actions.append(.viewDay)
            return (doneHeadline(strength: strength, cardio: cardio), doneLine(strength: strength, cardio: cardio), actions)

        case .planned(let planned, let isPast):
            if isPast {
                return (planned.name, missedLine(planned), [.logWorkout, .viewDay])
            }
            let word = planned.status == .rescheduled ? "Rescheduled, " : "Planned, "
            return (planned.name, word + exercises(planned.exerciseCount), [.editPlanned(planned.id), .viewDay])

        case .empty(let context, let hasActivePlan):
            switch context {
            case .today: return ("Nothing logged yet", nil, [.startWorkout])
            case .past: return ("Nothing logged", nil, [.logWorkout])
            case .future: return (hasActivePlan ? "Rest day" : "Nothing planned", nil, [.planWorkout])
            }
        }
    }

    private static func doneHeadline(strength: [CutPlanDayFacts.Strength], cardio: [CutPlanDayFacts.Cardio]) -> String {
        if strength.count == 1 { return strength[0].name }
        if strength.count > 1 { return "\(strength.count) workouts" }
        if cardio.count == 1 { return cardio[0].name }
        return "\(cardio.count) cardio sessions"
    }

    private static func doneLine(strength: [CutPlanDayFacts.Strength], cardio: [CutPlanDayFacts.Cardio]) -> String {
        if strength.count > 1 {
            var line = strength.map(\.name).joined(separator: ", ")
            if !cardio.isEmpty { line += ", plus " + cardioCount(cardio.count) }
            return line
        }
        if let only = strength.first {
            var line = "Done" + (only.durationSeconds.map { ", " + duration($0) } ?? "")
            if cardio.count == 1 {
                line += ", plus " + (cardio[0].distanceKm > 0
                    ? distance(cardio[0].distanceKm) + " " + cardio[0].name.lowercased()
                    : cardio[0].name.lowercased())
            } else if cardio.count > 1 {
                line += ", plus " + cardioCount(cardio.count)
            }
            return line
        }
        if cardio.count == 1 {
            let only = cardio[0]
            if only.distanceKm > 0 {
                return "Done, " + distance(only.distanceKm) + " in " + clock(only.durationSeconds)
            }
            return "Done, " + duration(only.durationSeconds)
        }
        return cardio.map(\.name).joined(separator: ", ")
    }

    private static func missedLine(_ planned: CutPlanDayFacts.Planned) -> String {
        switch planned.status {
        case .skipped: "Skipped, " + exercises(planned.exerciseCount) + " planned"
        case .partial: "Partly done, " + exercises(planned.exerciseCount) + " planned"
        case .rescheduled: "Rescheduled, " + exercises(planned.exerciseCount) + " planned"
        case .scheduled, .completed: "Missed, " + exercises(planned.exerciseCount) + " planned"
        }
    }

    static func label(for action: CutPlanDayPanel.Action) -> String {
        switch action {
        case .startPlanned, .startWorkout: "Start workout"
        case .viewWorkout: "View workout"
        case .viewDay: "View day"
        case .logWorkout: "Log a workout"
        case .planWorkout: "Plan a workout"
        case .editPlanned: "Edit workout"
        }
    }

    /// Starting, logging and planning are lime pills; viewing and editing are outlined.
    static func isPrimary(_ action: CutPlanDayPanel.Action) -> Bool {
        switch action {
        case .startPlanned, .startWorkout, .logWorkout, .planWorkout: true
        case .viewWorkout, .viewDay, .editPlanned: false
        }
    }

    // MARK: Formatting

    static func exercises(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }

    private static func cardioCount(_ count: Int) -> String {
        count == 1 ? "1 cardio session" : "\(count) cardio sessions"
    }

    /// "52 min" under an hour, "1:05" from an hour.
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes >= 60 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return "\(minutes) min"
    }

    /// "34:12" under an hour, "1:05" (h:mm) from an hour.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total >= 3600 { return String(format: "%d:%02d", total / 3600, (total % 3600) / 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func distance(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    // MARK: Facts

    /// One day's facts for every day in `days`, keyed by start of day. App workouts and runs
    /// outside the range are skipped first, so the cost follows the history in view.
    /// Apple Watch strength workouts matched to an app workout, or discarded, are left out,
    /// as in the legacy day detail.
    static func facts(
        days: [Date],
        workouts: [CompletedWorkout],
        runs: [Run],
        planned: [(date: Date, planned: CutPlanDayFacts.Planned)],
        ignoredHealthKitUUIDs: Set<UUID>,
        calendar: Calendar,
        workoutName: (CompletedWorkout) -> String,
        healthKitStrengthName: (Run) -> String
    ) -> [Date: CutPlanDayFacts] {
        guard let first = days.first.map({ calendar.startOfDay(for: $0) }),
              let lastDay = days.last.map({ calendar.startOfDay(for: $0) }),
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return [:] }
        var result: [Date: CutPlanDayFacts] = [:]
        for day in days { result[calendar.startOfDay(for: day)] = .empty }

        let inRange = { (date: Date) in date >= first && date < end }
        let dayWorkouts = workouts.filter { inRange($0.date) }
        let matchedByDay = Dictionary(grouping: dayWorkouts.compactMap { workout in
            workout.matchedHealthKitUUID.map { (calendar.startOfDay(for: workout.date), $0) }
        }, by: \.0).mapValues { Set($0.map(\.1)) }

        for workout in dayWorkouts {
            let key = calendar.startOfDay(for: workout.date)
            let seconds = workout.startedAt.map { Int(workout.date.timeIntervalSince($0)) }
                ?? workout.matchedHealthKitDuration
            result[key, default: .empty].strength.append(
                .init(id: workout.id, source: .app, name: workoutName(workout),
                      durationSeconds: seconds.flatMap { $0 > 0 ? $0 : nil }))
        }
        for run in runs where inRange(run.date) {
            let key = calendar.startOfDay(for: run.date)
            if run.countsAsStrengthDay {
                guard let uuid = run.healthKitUUID,
                      !(matchedByDay[key]?.contains(uuid) ?? false),
                      !ignoredHealthKitUUIDs.contains(uuid) else { continue }
                result[key, default: .empty].strength.append(
                    .init(id: run.id, source: .healthKit, name: healthKitStrengthName(run),
                          durationSeconds: run.durationSec > 0 ? run.durationSec : nil))
            } else {
                result[key, default: .empty].cardio.append(
                    .init(id: run.id, name: cardioName(run), distanceKm: max(0, run.distanceKm),
                          durationSeconds: max(0, run.durationSec)))
            }
        }
        for (date, planned) in planned {
            let key = calendar.startOfDay(for: date)
            // The first planned session of a day wins, as in the legacy grid.
            if result[key] != nil, result[key]?.planned == nil {
                result[key]?.planned = planned
            }
        }
        return result
    }

    /// A Health activity's own name, else its type ("Running").
    static func cardioName(_ run: Run) -> String {
        if let name = run.workoutName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return CardioActivityType(from: run.workoutType).rawValue
    }

    // MARK: Week

    /// The legacy calendar's freeze rule: a week is frozen when it is the freeze-protected
    /// week, or the week before the current one while the weekly streak is frozen.
    static func isFrozenWeek(
        weekStart: Date,
        currentWeekStart: Date,
        protectedWeekStart: Date?,
        streakFrozen: Bool,
        calendar: Calendar
    ) -> Bool {
        if let protectedWeekStart, calendar.isDate(weekStart, inSameDayAs: protectedWeekStart) { return true }
        guard streakFrozen, let frozen = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) else { return false }
        return calendar.isDate(weekStart, inSameDayAs: frozen)
    }

    // MARK: Model

    static func model(
        monthAnchor: Date,
        selectedDay: Date,
        today: Date,
        facts: [Date: CutPlanDayFacts],
        hasActivePlan: Bool,
        calendar: Calendar
    ) -> CutPlanModel {
        CutPlanModel(
            month: month(anchor: monthAnchor, selectedDay: selectedDay, today: today, facts: facts, calendar: calendar),
            panel: panel(for: selectedDay, facts: facts[calendar.startOfDay(for: selectedDay)] ?? .empty,
                         today: today, hasActivePlan: hasActivePlan, calendar: calendar),
            showsGoToToday: !calendar.isDate(monthAnchor, equalTo: today, toGranularity: .month)
        )
    }
}
