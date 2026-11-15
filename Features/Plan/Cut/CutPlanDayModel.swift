//
//  CutPlanDayModel.swift
//  WRKT
//
//  The Plan tab's "View day" page in the Cut language: the plain values it shows and the pure
//  rules that pick them, carried over from the legacy DayDetail, DayActionCard and
//  PlannedWorkoutCard. CutPlanDayHost feeds it from the workout store and the day's planned
//  workout; tests and captures feed it fixtures.
//

import Foundation

// MARK: - Input

/// One day's workouts, runs and planned session, as plain values.
struct CutPlanDayInput: Equatable {
    /// A workout logged in the app.
    struct Workout: Equatable {
        let id: UUID
        let name: String
        let ended: Date
        /// Matched to an Apple Health workout (the legacy heart badge).
        let isHealthMatched: Bool
        let exerciseCount: Int
        let setCount: Int
        let repCount: Int
    }

    /// An Apple Watch strength workout not matched to an app workout and not discarded.
    struct WatchStrength: Equatable {
        let id: UUID
        let name: String
        let ended: Date
    }

    /// A cardio activity from Health.
    struct Cardio: Equatable {
        let id: UUID
        let name: String
        let start: Date
        let distanceKm: Double
        let durationSeconds: Int
    }

    struct PlannedExercise: Equatable {
        let name: String
        let setCount: Int
        /// Reps of the first set, 0 without sets (the legacy "3 × 10").
        let firstReps: Int
    }

    /// The day's planned session.
    struct Planned: Equatable {
        let id: UUID
        let name: String
        let status: WorkoutStatus
        let exercises: [PlannedExercise]
        /// The workout that completed it, when linked.
        let completedWorkoutID: UUID?
        /// A logged workout points at this plan (the legacy card's "Completed" check).
        let isLogged: Bool
    }

    var workouts: [Workout] = []
    var watchStrength: [WatchStrength] = []
    var cardio: [Cardio] = []
    /// Every Health activity on the day, including Watch strength workouts hidden because they
    /// are matched or discarded: the legacy "No activity" rule counts them.
    var runCount = 0
    var planned: Planned?
}

// MARK: - Screen values

struct CutPlanDayModel: Equatable {
    /// A workout or cardio row. The whole row opens its detail.
    struct Row: Equatable, Identifiable {
        let id: UUID
        let target: CutPlanWorkoutRef
        let title: String
        let subtitle: String
        /// Trailing value: a cardio distance.
        let value: String?
        /// The heart icon: the workout came from, or is matched to, Apple Health.
        let isHealthMatched: Bool
        let accessibilityLabel: String
    }

    struct Section: Equatable {
        let title: String
        let rows: [Row]
        var count: Int { rows.count }
    }

    /// Extra planned-session actions behind the session's menu.
    enum PlanMenuItem: Equatable, Hashable {
        /// Start a session planned for another day; it logs today, so it asks first.
        case startNow
        /// Start a session already logged again.
        case startAgain
        case delete
    }

    struct PlanExercise: Equatable, Identifiable {
        let id: Int
        let name: String
        /// "3 × 10"
        let detail: String
    }

    /// The planned session: today's plan still to do, or a plan on another day.
    struct Plan: Equatable {
        let id: UUID
        /// "Today's plan" or "Planned".
        let sectionTitle: String
        let name: String
        /// "Planned, 6 exercises"
        let statusLine: String
        /// The first three exercises, shown when the session is opened.
        let exercises: [PlanExercise]
        /// "+3 more exercises"
        let moreLine: String?
        let actions: [CutPlanDayPanel.Action]
        let menu: [PlanMenuItem]
    }

    /// Today's plan, already done: a row that opens the finished workout.
    struct CompletedPlan: Equatable {
        /// "6 exercises, Upper Body"
        let subtitle: String
        /// Nil when the plan has no linked workout: the row then does nothing, as before.
        let workoutID: UUID?
    }

    /// "Wednesday\n11 November", with the year when it is not this year.
    let title: String
    /// "Wednesday 11 November": the title read as one phrase.
    let accessibilityTitle: String
    /// "Today", or nil.
    let line: String?
    /// The daily summary (workouts, exercises, sets, reps); nil without app workouts.
    let summary: [CutStatColumn]?
    /// Start, log or plan, before everything else.
    let actions: [CutPlanDayPanel.Action]
    let completedPlan: CompletedPlan?
    let plan: Plan?
    /// Nothing done and nothing planned.
    let showsNoActivity: Bool
    let workouts: Section?
    let cardio: Section?
}

// MARK: - Logic

enum CutPlanDayLogic {
    static func model(
        date: Date,
        input: CutPlanDayInput,
        today: Date,
        calendar: Calendar,
        locale: Locale = .current
    ) -> CutPlanDayModel {
        let context = CutPlanLogic.dayContext(date, today: today, calendar: calendar)
        let isToday = context == .today

        var actions: [CutPlanDayPanel.Action] = []
        var completedPlan: CutPlanDayModel.CompletedPlan?
        var plan: CutPlanDayModel.Plan?

        // The legacy action card shows without a plan, on today, and on past days.
        if input.planned == nil || isToday || context == .past {
            switch context {
            case .past:
                actions = [.logWorkout]
            case .today:
                if let planned = input.planned {
                    if planned.status == .completed || planned.status == .partial {
                        completedPlan = .init(subtitle: CutPlanLogic.exercises(planned.exercises.count) + ", " + planned.name,
                                              workoutID: planned.completedWorkoutID)
                    } else {
                        plan = todayPlan(planned)
                    }
                } else {
                    actions = [.startWorkout]
                }
            case .future:
                actions = [.planWorkout]
            }
        }
        // The legacy planned card: any day but today, unless the plan is completed.
        if let planned = input.planned, planned.status != .completed, !isToday {
            plan = otherDayPlan(planned)
        }

        return CutPlanDayModel(
            title: title(for: date, today: today, calendar: calendar),
            accessibilityTitle: title(for: date, today: today, calendar: calendar).replacingOccurrences(of: "\n", with: " "),
            line: isToday ? "Today" : nil,
            summary: summary(input.workouts),
            actions: actions,
            completedPlan: completedPlan,
            plan: plan,
            showsNoActivity: input.workouts.isEmpty && input.runCount == 0 && input.planned == nil,
            workouts: workoutsSection(input, calendar: calendar, locale: locale),
            cardio: cardioSection(input.cardio, calendar: calendar, locale: locale)
        )
    }

    // MARK: Title

    static func title(for date: Date, today: Date, calendar: Calendar) -> String {
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
        var second = "\(calendar.component(.day, from: date)) \(month)"
        let year = calendar.component(.year, from: date)
        if year != calendar.component(.year, from: today) { second += " \(year)" }
        return weekday + "\n" + second
    }

    // MARK: Summary

    /// The legacy daily summary counts app workouts only.
    static func summary(_ workouts: [CutPlanDayInput.Workout]) -> [CutStatColumn]? {
        guard !workouts.isEmpty else { return nil }
        return [
            CutStatColumn(value: "\(workouts.count)", label: "Workouts"),
            CutStatColumn(value: "\(workouts.reduce(0) { $0 + $1.exerciseCount })", label: "Exercises"),
            CutStatColumn(value: "\(workouts.reduce(0) { $0 + $1.setCount })", label: "Sets"),
            CutStatColumn(value: "\(workouts.reduce(0) { $0 + $1.repCount })", label: "Reps")
        ]
    }

    // MARK: Plan

    static func todayPlan(_ planned: CutPlanDayInput.Planned) -> CutPlanDayModel.Plan {
        CutPlanDayModel.Plan(
            id: planned.id,
            sectionTitle: "Today's plan",
            name: planned.name,
            statusLine: "Planned, " + CutPlanLogic.exercises(planned.exercises.count),
            exercises: planExercises(planned.exercises),
            moreLine: moreLine(planned.exercises.count),
            actions: [.startPlanned(planned.id), .editPlanned(planned.id)],
            menu: []
        )
    }

    static func otherDayPlan(_ planned: CutPlanDayInput.Planned) -> CutPlanDayModel.Plan {
        var menu: [CutPlanDayModel.PlanMenuItem] = []
        // The legacy card offered Start only for a scheduled plan, or Start Again once logged.
        if planned.isLogged {
            menu.append(.startAgain)
        } else if planned.status == .scheduled {
            menu.append(.startNow)
        }
        menu.append(.delete)
        return CutPlanDayModel.Plan(
            id: planned.id,
            sectionTitle: "Planned",
            name: planned.name,
            statusLine: statusWord(planned) + ", " + CutPlanLogic.exercises(planned.exercises.count),
            exercises: planExercises(planned.exercises),
            moreLine: moreLine(planned.exercises.count),
            actions: [.editPlanned(planned.id)],
            menu: menu
        )
    }

    /// The legacy card's status: a logged plan reads as completed whatever its stored status.
    static func statusWord(_ planned: CutPlanDayInput.Planned) -> String {
        if planned.isLogged { return "Completed" }
        switch planned.status {
        case .scheduled: return "Planned"
        case .completed: return "Completed"
        case .partial: return "Partially completed"
        case .skipped: return "Skipped"
        case .rescheduled: return "Rescheduled"
        }
    }

    static func planExercises(_ exercises: [CutPlanDayInput.PlannedExercise]) -> [CutPlanDayModel.PlanExercise] {
        exercises.prefix(3).enumerated().map { index, exercise in
            .init(id: index, name: exercise.name, detail: "\(exercise.setCount) × \(exercise.firstReps)")
        }
    }

    static func moreLine(_ count: Int) -> String? {
        guard count > 3 else { return nil }
        return count - 3 == 1 ? "+1 more exercise" : "+\(count - 3) more exercises"
    }

    static func menuLabel(_ item: CutPlanDayModel.PlanMenuItem) -> String {
        switch item {
        case .startNow: "Start now"
        case .startAgain: "Start again"
        case .delete: "Delete planned workout"
        }
    }

    // MARK: Rows

    static func workoutsSection(_ input: CutPlanDayInput, calendar: Calendar, locale: Locale) -> CutPlanDayModel.Section? {
        let app = input.workouts.map { workout in
            row(id: workout.id, target: .app(workout.id), title: workout.name,
                subtitle: "Ended: " + time(workout.ended, calendar: calendar, locale: locale),
                isHealthMatched: workout.isHealthMatched)
        }
        let watch = input.watchStrength.map { workout in
            row(id: workout.id, target: .healthKitStrength(workout.id), title: workout.name,
                subtitle: "Ended: " + time(workout.ended, calendar: calendar, locale: locale),
                isHealthMatched: true)
        }
        let rows = app + watch
        return rows.isEmpty ? nil : .init(title: "Workouts", rows: rows)
    }

    static func cardioSection(_ cardio: [CutPlanDayInput.Cardio], calendar: Calendar, locale: Locale) -> CutPlanDayModel.Section? {
        guard !cardio.isEmpty else { return nil }
        return .init(title: "Cardio", rows: cardio.map { run in
            let distance = run.distanceKm > 0 ? CutPlanLogic.distance(run.distanceKm) : nil
            return row(id: run.id, target: .cardio(run.id), title: run.name,
                       subtitle: time(run.start, calendar: calendar, locale: locale) + ", "
                           + CutPlanLogic.clock(run.durationSeconds),
                       value: distance, isHealthMatched: false)
        })
    }

    private static func row(id: UUID, target: CutPlanWorkoutRef, title: String, subtitle: String,
                            value: String? = nil, isHealthMatched: Bool) -> CutPlanDayModel.Row {
        let label = [title, subtitle, value, isHealthMatched ? "Apple Health" : nil].compactMap { $0 }.joined(separator: ", ")
        return .init(id: id, target: target, title: title, subtitle: subtitle, value: value,
                     isHealthMatched: isHealthMatched, accessibilityLabel: label)
    }

    /// The legacy short time: "21:19", or "9:19 PM" where the locale uses a 12 hour clock.
    static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
