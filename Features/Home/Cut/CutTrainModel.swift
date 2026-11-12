//
//  CutTrainModel.swift
//  WRKT
//
//  Cut Train tab: the plain values the screen shows and the pure logic that picks them.
//  Nothing here reads a service; CutTrainHost feeds it from HomeViewModel, the workout
//  store and the rest timer, and tests and captures feed it fixtures.
//

import Foundation

/// Everything the Cut Train tab shows.
struct CutTrainModel: Equatable {
    var hero: CutTrainHero
    /// Nil when no weekly goal is set (the legacy card is hidden then too).
    var weeklyGoal: CutTrainWeeklyGoal?
    /// At most three, each shown only when its data exists.
    var rows: [CutTrainRow]
}

/// Where the rest countdown reads its seconds from.
enum CutTrainCountdown: Equatable {
    /// RestTimerManager.shared.ticker, observed by a leaf view only.
    case live
    /// A fixed value, for captures and previews.
    case fixed(TimeInterval)
}

/// The lime field's state, in priority order.
enum CutTrainHero: Equatable {
    /// A workout with entries is running and the rest timer counts down.
    case resting(nextLine: String?, countdown: CutTrainCountdown)
    /// A workout with entries is running.
    case live(name: String, exercisesDone: Int, exerciseCount: Int, startDate: Date)
    /// Today's planned session is not completed.
    case planned(name: String, exerciseCount: Int)
    /// A plan is active and today's planned session is completed.
    case doneToday(next: PlanOutlook.Session?)
    /// A plan is active but nothing is scheduled today.
    case restDay(next: PlanOutlook.Session?)
    /// No active plan.
    case noPlan
}

struct CutTrainWeeklyGoal: Equatable {
    let strengthDone: Int
    let strengthTarget: Int
    let cardioMinutes: Int
    let cardioTarget: Int
}

struct CutTrainRow: Equatable, Identifiable {
    enum Kind: Equatable {
        case battle, streak, lastWorkout
    }

    let kind: Kind
    let title: String
    let value: String

    var id: Kind { kind }
}

// MARK: - State selection

enum CutTrainLogic {
    /// The workout in progress as the hero needs it.
    struct ActiveWorkout: Equatable {
        let entries: [WorkoutEntry]
        let startDate: Date
        let plannedWorkoutID: UUID?
    }

    /// Today's planned session.
    struct TodaysPlan: Equatable {
        let id: UUID
        let name: String
        let exerciseCount: Int
    }

    /// The rest timer as the hero needs it: only a running countdown counts, as on the legacy hero.
    struct RunningRest: Equatable {
        let exerciseID: String
    }

    static let liveWorkoutName = "Live workout"

    static func hero(
        workout: ActiveWorkout?,
        rest: RunningRest?,
        todaysPlan: TodaysPlan?,
        outlook: PlanOutlook,
        unit: WeightUnit,
        countdown: CutTrainCountdown = .live
    ) -> CutTrainHero {
        if let workout, !workout.entries.isEmpty {
            if let rest {
                let next = nextSet(in: workout.entries, restingOn: rest.exerciseID)
                return .resting(nextLine: next.map { nextSetLine(name: $0.name, set: $0.set, unit: unit) },
                                countdown: countdown)
            }
            let name = workout.plannedWorkoutID != nil && workout.plannedWorkoutID == todaysPlan?.id
                ? (todaysPlan?.name ?? liveWorkoutName)
                : liveWorkoutName
            return .live(name: name,
                         exercisesDone: workout.entries.filter { isDone($0) }.count,
                         exerciseCount: workout.entries.count,
                         startDate: workout.startDate)
        }
        if let todaysPlan {
            return .planned(name: todaysPlan.name, exerciseCount: todaysPlan.exerciseCount)
        }
        if outlook.hasActivePlan {
            return outlook.completedToday ? .doneToday(next: outlook.nextSession) : .restDay(next: outlook.nextSession)
        }
        return .noPlan
    }

    /// The field is lime except on days with nothing left to train, which use the dark tone.
    static func fieldIsLime(_ hero: CutTrainHero) -> Bool {
        switch hero {
        case .restDay, .doneToday: false
        default: true
        }
    }

    /// An exercise is done when it has sets and every one is completed.
    static func isDone(_ entry: WorkoutEntry) -> Bool {
        !entry.sets.isEmpty && entry.sets.allSatisfy(\.isCompleted)
    }

    /// The first open set from the exercise being rested on onwards.
    static func nextSet(in entries: [WorkoutEntry], restingOn exerciseID: String) -> (name: String, set: SetInput)? {
        let start = entries.firstIndex { $0.exerciseID == exerciseID } ?? entries.startIndex
        for entry in entries[start...] {
            if let set = entry.sets.first(where: { !$0.isCompleted }) {
                return (entry.exerciseName, set)
            }
        }
        return nil
    }

    static func rows(
        battle: (title: String, value: String)?,
        streakWeeks: Int?,
        lastWorkout: (name: String, date: Date)?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [CutTrainRow] {
        var rows: [CutTrainRow] = []
        if let battle, !battle.title.isEmpty {
            rows.append(CutTrainRow(kind: .battle, title: battle.title, value: battle.value))
        }
        if let streakWeeks, streakWeeks > 0 {
            rows.append(CutTrainRow(kind: .streak, title: "Streak", value: weeks(streakWeeks)))
        }
        if let lastWorkout {
            rows.append(CutTrainRow(
                kind: .lastWorkout,
                title: "Last workout",
                value: "\(lastWorkout.name), \(relativeDay(lastWorkout.date, now: now, calendar: calendar, style: .short))"
            ))
        }
        return Array(rows.prefix(3))
    }

    /// The name the legacy last workout card shows: the saved name, or one classified from muscles.
    static func displayName(for workout: CompletedWorkout) -> String {
        if let name = workout.workoutName, !name.isEmpty { return name }
        let muscles = Set(workout.entries.flatMap(\.muscleGroups))
        let upper: Set<String> = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms"]
        let lower: Set<String> = ["Quads", "Hamstrings", "Glutes", "Calves"]
        let upperCount = muscles.intersection(upper).count
        let lowerCount = muscles.intersection(lower).count
        switch (upperCount > 0, lowerCount > 0) {
        case (true, false): return "Upper Body"
        case (false, true): return "Lower Body"
        case (true, true): return "Full Body"
        case (false, false): return "Workout"
        }
    }
}

// MARK: - Copy

extension CutTrainLogic {
    /// The hero text before it is set on lines.
    static func heroTitle(_ hero: CutTrainHero) -> String {
        switch hero {
        case .planned(let name, _), .live(let name, _, _, _): name
        case .restDay: "Rest day"
        case .doneToday: "Done today"
        case .noPlan: "No plan yet"
        case .resting: ""
        }
    }

    /// The hero size for text already set on lines: the 96 pt hero holds about eight condensed
    /// capitals across a phone, so longer lines step down a size instead of shrinking glyphs
    /// (shrunk glyphs would collide, since the tight line gap is set for the nominal size).
    static func heroSize(forLines text: String) -> DS.Cut.Typography.Hero {
        let longest = CutHeroText.lines(of: text).map(\.count).max() ?? 0
        switch longest {
        case ...8: return .xl
        case ...10: return .l
        case ...12: return .m
        case ...16: return .s
        default: return .xs
        }
    }

    /// The one supporting line, or nil when there is nothing true to say.
    static func heroLine(_ hero: CutTrainHero, now: Date = .now, calendar: Calendar = .current) -> String? {
        switch hero {
        case .planned(_, let count):
            guard count > 0 else { return nil }
            return count == 1 ? "1 exercise" : "\(count) exercises"
        case .restDay(let next), .doneToday(let next):
            guard let next else { return nil }
            return "Next: \(next.name), \(relativeDay(next.date, now: now, calendar: calendar, style: .long))"
        case .noPlan:
            return nil
        case .live(_, let done, let count, _):
            return "\(done) of \(count) \(count == 1 ? "exercise" : "exercises") done"
        case .resting(let nextLine, _):
            return nextLine
        }
    }

    static func nextSetLine(name: String, set: SetInput, unit: WeightUnit) -> String {
        if set.weight > 0, set.reps > 0 {
            // No-break spaces keep "85 kg x 6" together when the line wraps at large type.
            let weight = unit.format(set.weight).replacingOccurrences(of: " ", with: "\u{00A0}")
            return "Next: \(name), \(weight)\u{00A0}x\u{00A0}\(set.reps)"
        }
        if set.reps > 0 {
            return "Next: \(name), \(set.reps) \(set.reps == 1 ? "rep" : "reps")"
        }
        return "Next: \(name)"
    }

    /// Elapsed workout time: "4:05", "24:16", then "1:02" (h:mm) from one hour.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Rest countdown: "1:32"; from one hour "h:mm" like every other duration.
    static func countdown(_ seconds: TimeInterval) -> String {
        elapsed(seconds)
    }

    static func weeks(_ count: Int) -> String {
        count == 1 ? "1 week" : "\(count) weeks"
    }

    enum DayStyle { case short, long }

    /// "Today", "Yesterday", "tomorrow" (lowercase only after a comma in the rest line),
    /// a weekday within six days, otherwise a short date.
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar, style: DayStyle) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return style == .long ? "today" : "Today"
        case 1: return "tomorrow"
        case -1: return "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = calendar.locale ?? .current
            if abs(days) <= 6 {
                formatter.setLocalizedDateFormatFromTemplate(style == .long ? "EEEE" : "EEE")
            } else {
                formatter.setLocalizedDateFormatFromTemplate("MMMd")
            }
            return formatter.string(from: date)
        }
    }

    /// One sentence for VoiceOver.
    static func weeklyGoalAccessibilityLabel(_ goal: CutTrainWeeklyGoal) -> String {
        let days = goal.strengthTarget == 1 ? "day" : "days"
        return "Weekly goal: strength \(goal.strengthDone) of \(goal.strengthTarget) \(days), "
            + "cardio \(goal.cardioMinutes) of \(goal.cardioTarget) minutes"
    }

    static func fraction(_ done: Int, of target: Int) -> Double {
        target > 0 ? Double(done) / Double(target) : 0
    }
}
