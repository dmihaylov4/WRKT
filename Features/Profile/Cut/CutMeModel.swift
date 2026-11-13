//
//  CutMeModel.swift
//  WRKT
//
//  The Me tab in the Cut language as plain values: level and XP with the streak, the weekly
//  goal, plan adherence, training trends, training balance and the collection. Every format and
//  decision is a pure function of facts the host reads from RewardProgress, the weekly goal,
//  PlannerStore and the statistics summaries, so each state renders and tests without SwiftData.
//

import Foundation

// MARK: - Facts (what the host reads)

struct CutMeFacts: Equatable {
    /// RewardProgress as plain values.
    struct Progress: Equatable {
        var level: Int
        var xp: Int
        var prevLevelXP: Int
        var nextLevelXP: Int
        /// Daily streak (used when no weekly goal is set).
        var dailyStreak: Int
        var dailyStreakLongest: Int
        var dailyFrozen: Bool
        /// Weekly goal streak (used when a weekly goal is set).
        var weeklyStreak: Int
        var weeklyStreakLongest: Int
        var weeklyFrozen: Bool
        var superStreak: Int
    }

    /// This week against the goal (WeeklyProgress).
    struct GoalProgress: Equatable {
        var strengthDone: Int
        var strengthTarget: Int
        var minutesDone: Int
        var minutesTarget: Int
    }

    /// RewardsEngine's answer to "can the streak be frozen now".
    struct Freeze: Equatable {
        var canActivate: Bool
        var reason: String?
    }

    /// One week of PlannerStore adherence.
    struct Adherence: Equatable {
        var planned: Int
        var completed: Int
        var missed: Int
    }

    /// One WeeklyTrainingSummary: its week and its tonnage in kilograms.
    struct Week: Equatable {
        var weekStart: Date
        var volumeKg: Double
    }

    struct Muscle: Equatable {
        var name: String
        var lastTrained: Date
    }

    var progress: Progress?
    /// A weekly goal is set (WeeklyGoal.isSet).
    var goalIsSet = false
    /// This week's progress against the goal; nil until the store has computed it.
    var goalProgress: GoalProgress?
    var freeze: Freeze?
    /// Four weeks, oldest first, the current week last.
    var adherence: [Adherence] = []
    var currentWeekEnded = false
    /// The last twelve weeks of summaries, in any order.
    var weeks: [Week] = []
    /// MovingAverage.percentChange of the latest week: change on the week before, in percent.
    var latestWeekChange: Double?
    /// The latest PushPullBalance.
    var pushVolume: Double?
    var pullVolume: Double?
    var muscles: [Muscle] = []
    /// Unlocked records in the PR collection.
    var prCount = 0
    /// Unlocked milestones (achievements other than records).
    var milestoneCount = 0
    /// The weight unit preference.
    var unit: WeightUnit = .kg
}

// MARK: - Model (what the view draws)

struct CutMeModel: Equatable {
    struct Hero: Equatable {
        /// Within-level XP: "240".
        var xp: String
        /// "/650 XP"
        var xpTotal: String
        /// 0...1 through the level: both arms of the V mark.
        var fraction: Double
        /// "6 week streak", or a quiet line when there is none.
        var line: String
        var lineIsActive: Bool
        var accessibilityLabel: String
    }

    enum Goal: Equatable {
        /// No weekly goal: one row to set it up.
        case setUp
        case progress(rows: [GoalRow])
    }

    struct GoalRow: Equatable, Identifiable {
        enum Kind: Equatable { case strength, minutes }
        var kind: Kind
        var title: String
        /// "2 of 4"
        var value: String
        var isMet: Bool
        var id: Kind { kind }
    }

    struct FreezeRow: Equatable {
        /// "Active" or "Ready", in lime.
        var value: String?
        /// Why it cannot be used now.
        var line: String?
        var canActivate: Bool
        var alertMessage: String
    }

    struct Adherence: Equatable {
        /// "3 of 4"
        var hero: String
        var line: String
        /// Slanted segments for the current week; nil when the plan has too many or none.
        var segments: Segments?
    }

    struct Segments: Equatable {
        var total: Int
        var filled: Int
    }

    struct WeekBar: Equatable, Identifiable {
        var id: Int
        var fraction: Double
        var isHighlighted: Bool
    }

    enum Trends: Equatable {
        case empty(line: String)
        case data(value: String, unit: String, line: String, bars: [WeekBar])
    }

    struct BalanceRow: Equatable, Identifiable {
        var title: String
        var value: String
        var id: String { title }
    }

    struct Balance: Equatable {
        /// "56%" and "44%"; nil without push or pull work.
        var push: String?
        var pull: String?
        var pushFraction: Double?
        var rows: [BalanceRow]
    }

    var title: String
    /// nil before the first workout: the empty line shows instead.
    var hero: Hero?
    var emptyLine: String?
    var goal: Goal
    var canShareWeek: Bool
    var freeze: FreezeRow?
    /// Super and longest streak.
    var streakStats: [CutStatColumn]
    var adherence: Adherence?
    var trends: Trends
    var balance: Balance?
    /// nil hides the numeral.
    var prCount: String?
    var milestoneCount: String?
}

// MARK: - Logic

enum CutMeLogic {
    static func model(_ facts: CutMeFacts, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> CutMeModel {
        let goalSet = facts.goalIsSet
        let goal: CutMeModel.Goal
        if goalSet, let progress = facts.goalProgress {
            goal = .progress(rows: goalRows(progress, locale: locale))
        } else {
            goal = .setUp
        }
        return CutMeModel(
            title: facts.progress.map { "Level \($0.level)" } ?? "Me",
            hero: facts.progress.map { hero($0, goalSet: goalSet, locale: locale) },
            emptyLine: facts.progress == nil ? "Finish a workout to earn XP and level up." : nil,
            goal: goal,
            canShareWeek: { if case .progress = goal { return true } else { return false } }(),
            freeze: facts.progress.flatMap { freezeRow($0, freeze: facts.freeze, goalSet: goalSet) },
            streakStats: facts.progress.map { streakStats($0, goalSet: goalSet, locale: locale) } ?? [],
            adherence: adherence(facts.adherence, currentWeekEnded: facts.currentWeekEnded, locale: locale),
            trends: trends(facts.weeks, change: facts.latestWeekChange, unit: facts.unit, now: now, calendar: calendar, locale: locale),
            balance: balance(push: facts.pushVolume, pull: facts.pullVolume, muscles: facts.muscles, now: now, calendar: calendar),
            prCount: facts.prCount > 0 ? number(facts.prCount, locale: locale) : nil,
            milestoneCount: facts.milestoneCount > 0 ? number(facts.milestoneCount, locale: locale) : nil
        )
    }

    // MARK: Level

    /// The legacy card's level window: never narrower than the level's XP step.
    static func levelWindow(level: Int, xp: Int, prevLevelXP: Int, nextLevelXP: Int) -> (done: Int, total: Int) {
        let step = 100 + 50 * max(0, level - 1)
        let start = max(prevLevelXP, nextLevelXP - step)
        let end = max(nextLevelXP, start + 1)
        return (max(0, xp - start), max(1, end - start))
    }

    static func hero(_ progress: CutMeFacts.Progress, goalSet: Bool, locale: Locale) -> CutMeModel.Hero {
        let window = levelWindow(level: progress.level, xp: progress.xp,
                                 prevLevelXP: progress.prevLevelXP, nextLevelXP: progress.nextLevelXP)
        let done = min(window.done, window.total)
        let streak = goalSet ? progress.weeklyStreak : progress.dailyStreak
        let line = streak > 0 ? streakText(streak, weekly: goalSet) : "No streak yet"
        return CutMeModel.Hero(
            xp: number(done, locale: locale),
            xpTotal: "/\(number(window.total, locale: locale)) XP",
            fraction: Double(done) / Double(window.total),
            line: line,
            lineIsActive: streak > 0,
            accessibilityLabel: "Level \(progress.level), \(done) of \(window.total) XP to the next level"
        )
    }

    static func streakText(_ count: Int, weekly: Bool) -> String {
        "\(count) \(weekly ? "week" : "day") streak"
    }

    /// Super and longest streak in weeks with a goal; the longest daily streak without one.
    /// Empty while every value is zero.
    static func streakStats(_ progress: CutMeFacts.Progress, goalSet: Bool, locale: Locale) -> [CutStatColumn] {
        if goalSet {
            guard progress.superStreak > 0 || progress.weeklyStreakLongest > 0 else { return [] }
            return [
                CutStatColumn(value: number(progress.superStreak, locale: locale), label: "Super streak", unit: "wk"),
                CutStatColumn(value: number(progress.weeklyStreakLongest, locale: locale), label: "Longest streak", unit: "wk")
            ]
        }
        guard progress.dailyStreakLongest > 0 else { return [] }
        return [CutStatColumn(value: number(progress.dailyStreakLongest, locale: locale), label: "Longest streak",
                              unit: progress.dailyStreakLongest == 1 ? "day" : "days")]
    }

    // MARK: Goal

    static func goalRows(_ progress: CutMeFacts.GoalProgress, locale: Locale) -> [CutMeModel.GoalRow] {
        [
            CutMeModel.GoalRow(kind: .strength, title: "Strength days",
                               value: "\(number(progress.strengthDone, locale: locale)) of \(number(progress.strengthTarget, locale: locale))",
                               isMet: progress.strengthDone >= progress.strengthTarget),
            CutMeModel.GoalRow(kind: .minutes, title: "Active minutes",
                               value: "\(number(progress.minutesDone, locale: locale)) of \(number(progress.minutesTarget, locale: locale))",
                               isMet: progress.minutesTarget > 0 && progress.minutesDone >= progress.minutesTarget)
        ]
    }

    /// The legacy freeze button's three states, plus the alert copy it showed.
    static func freezeRow(_ progress: CutMeFacts.Progress, freeze: CutMeFacts.Freeze?, goalSet: Bool) -> CutMeModel.FreezeRow? {
        guard let freeze else { return nil }
        let isActive = goalSet ? progress.weeklyFrozen : progress.dailyFrozen
        let message = goalSet
            ? "Protect your \(progress.weeklyStreak)-week streak. If you miss this week's goal, your streak is kept once."
            : "Protect your \(progress.dailyStreak)-day streak. If you miss tomorrow, your streak won't break and you earn 50 XP when you return."
        if isActive {
            return CutMeModel.FreezeRow(value: "Active", line: nil, canActivate: false, alertMessage: message)
        }
        if freeze.canActivate {
            return CutMeModel.FreezeRow(value: "Ready", line: nil, canActivate: true, alertMessage: message)
        }
        return CutMeModel.FreezeRow(value: nil, line: freeze.reason, canActivate: false, alertMessage: message)
    }

    // MARK: Plan adherence

    /// Hidden unless a plan scheduled something in the four weeks.
    static func adherence(_ weeks: [CutMeFacts.Adherence], currentWeekEnded: Bool, locale: Locale) -> CutMeModel.Adherence? {
        guard weeks.contains(where: { $0.planned > 0 }) else { return nil }
        let planned = weeks.reduce(0) { $0 + $1.planned }
        let completed = weeks.reduce(0) { $0 + $1.completed }
        let percent = Int((Double(completed) / Double(max(planned, 1)) * 100).rounded())
        let rolling = "\(percent)% over 4 weeks"

        guard let current = weeks.last, current.planned > 0 else {
            return CutMeModel.Adherence(hero: "\(number(completed, locale: locale)) of \(number(planned, locale: locale))",
                                        line: "Planned sessions over 4 weeks", segments: nil)
        }
        var parts: [String] = []
        if currentWeekEnded {
            if current.missed > 0 { parts.append("\(current.missed) missed this week") }
        } else {
            let left = current.planned - current.completed
            if left > 0 { parts.append("\(left) left this week") }
        }
        parts.append(rolling)
        let first = parts.joined(separator: ", ")
        return CutMeModel.Adherence(
            hero: "\(number(current.completed, locale: locale)) of \(number(current.planned, locale: locale))",
            line: first.prefix(1).uppercased() + first.dropFirst(),
            segments: current.planned <= 7
                ? CutMeModel.Segments(total: current.planned, filled: min(current.completed, current.planned)) : nil
        )
    }

    // MARK: Training trends

    static let trendWeeks = 12

    /// The latest week's tonnage as the hero over twelve weekly bars, the hero week in lime.
    static func trends(_ weeks: [CutMeFacts.Week], change: Double?, unit: WeightUnit, now: Date,
                       calendar: Calendar, locale: Locale) -> CutMeModel.Trends {
        guard let latest = weeks.max(by: { $0.weekStart < $1.weekStart }) else {
            return .empty(line: "Log a workout to see your weekly tonnage.")
        }
        // Twelve slots a week apart, aligned to the summaries' week start and ending at this week.
        let anchor = calendar.startOfDay(for: latest.weekStart)
        let daysSince = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: now)).day ?? 0
        let weeksSince = max(0, daysSince / 7)
        let slots: [Date] = (0..<trendWeeks).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: 7 * (weeksSince - back), to: anchor)
        }
        let values = slots.map { slot in
            weeks.filter { calendar.isDate($0.weekStart, inSameDayAs: slot) }.reduce(0) { $0 + $1.volumeKg }
        }
        let top = values.max() ?? 0
        let bars = values.enumerated().map { index, value in
            CutMeModel.WeekBar(id: index, fraction: top > 0 ? value / top : 0,
                               isHighlighted: calendar.isDate(slots[index], inSameDayAs: anchor))
        }

        var line = weekLabel(latest.weekStart, weeksAgo: weeksSince, calendar: calendar, locale: locale)
        if let change, change.isFinite {
            let rounded = Int(change.rounded())
            if rounded != 0 {
                line += ", \(rounded > 0 ? "up" : "down") \(abs(rounded))% on the week before"
            }
        }
        return .data(value: number(Int(unit.displayValue(latest.volumeKg).rounded()), locale: locale),
                     unit: unit == .kg ? "kg" : "lb", line: line, bars: bars)
    }

    static func weekLabel(_ weekStart: Date, weeksAgo: Int, calendar: Calendar, locale: Locale) -> String {
        switch weeksAgo {
        case 0: return "This week"
        case 1: return "Last week"
        default:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return "Week of \(formatter.string(from: weekStart))"
        }
    }

    // MARK: Training balance

    /// Push and pull shares of the latest week, then the three most recently trained muscles.
    /// nil when there is neither.
    static func balance(push: Double?, pull: Double?, muscles: [CutMeFacts.Muscle], now: Date,
                        calendar: Calendar) -> CutMeModel.Balance? {
        let total = (push ?? 0) + (pull ?? 0)
        let rows = muscles.sorted { $0.lastTrained > $1.lastTrained }.prefix(3).map {
            CutMeModel.BalanceRow(title: $0.name, value: daysAgo($0.lastTrained, now: now, calendar: calendar))
        }
        guard total > 0 || !rows.isEmpty else { return nil }
        guard total > 0 else { return CutMeModel.Balance(push: nil, pull: nil, pushFraction: nil, rows: Array(rows)) }
        let pushPercent = Int(((push ?? 0) / total * 100).rounded())
        return CutMeModel.Balance(push: "\(pushPercent)%", pull: "\(100 - pushPercent)%",
                                  pushFraction: (push ?? 0) / total, rows: Array(rows))
    }

    static func daysAgo(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    // MARK: Collection

    /// Unlocked achievements that are not records ("ach.pr." ids), as the legacy milestones list counts them.
    static func milestoneCount(_ achievements: [(id: String, unlocked: Bool)]) -> Int {
        achievements.filter { !$0.id.hasPrefix("ach.pr.") && $0.unlocked }.count
    }

    // MARK: Formatting

    static func number(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
