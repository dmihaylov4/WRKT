//
//  HomeWidgetSnapshot.swift
//  WRKT
//
//  The one value the home screen widgets read: weekly goal numbers, streak and today's state,
//  written by the app to the app group container. Compiled into the app and the widget
//  extension (see the WRKTWidgets exception set in the project). The widget never opens the
//  SwiftData store or HealthKit; it decodes this file and resolves it against the clock with
//  `HomeWidgetLogic`, so a snapshot from an earlier day never shows yesterday's "Today".
//

import Foundation

// MARK: - Shared constants

nonisolated enum HomeWidgetShared {
    /// The app group both targets carry in their entitlements.
    static let appGroupID = "group.com.dmihaylov.trak.shared"
    static let snapshotFileName = "home-widget-snapshot.json"

    /// Opens the app on the Train tab. Handled in WRKTApp.handleURL.
    static let trainURL = URL(string: "wrkt://train")!

    static func isTrainURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "wrkt" && url.host?.lowercased() == "train"
    }

    /// Widget kinds, used for reloads.
    enum Kind {
        static let weeklyGoal = "VoliaWeeklyGoalWidget"
        static let today = "VoliaTodayWidget"
        static let todayAndWeek = "VoliaTodayAndWeekWidget"
        static let all = [weeklyGoal, today, todayAndWeek]
    }
}

// MARK: - Snapshot

/// What the app knew when it last wrote: the day it describes, today's state and the week.
nonisolated struct HomeWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = HomeWidgetSnapshot.currentVersion
    /// When the app wrote the snapshot.
    var writtenAt: Date
    /// Start of the day `today` describes.
    var day: Date
    var today: Today
    /// The plan's next scheduled session after `day`, if any. Lets the widget name the session
    /// on the next day before the app runs again.
    var nextSession: Session?
    /// Nil when no weekly goal is set.
    var week: Week?

    enum Today: Codable, Equatable, Sendable {
        /// Today's planned session is not completed.
        case planned(name: String, exerciseCount: Int)
        /// A workout with entries is running.
        case inProgress(name: String)
        /// A plan is active and today's planned session is completed.
        case doneToday
        /// A plan is active but nothing is scheduled today.
        case restDay
        /// No active plan.
        case noPlan
    }

    struct Session: Codable, Equatable, Sendable {
        var name: String
        var date: Date
    }

    struct Week: Codable, Equatable, Sendable {
        var strengthDone: Int
        var strengthTarget: Int
        var cardioMinutes: Int
        var cardioTarget: Int
        /// Completed weekly goals in a row.
        var streakWeeks: Int
        /// When the goal week the numbers count ends (the next week's start).
        var weekEnd: Date

        var isMet: Bool {
            strengthDone >= strengthTarget && cardioMinutes >= cardioTarget
        }
    }
}

// MARK: - Resolved content

/// What a widget shows at a given moment, after the staleness rule.
nonisolated struct HomeWidgetContent: Equatable, Sendable {
    enum Today: Equatable, Sendable {
        /// `exerciseCount` is nil when only the name is known (a session carried over from the
        /// previous day's snapshot).
        case planned(name: String, exerciseCount: Int?)
        case inProgress(name: String)
        case doneToday(next: HomeWidgetSnapshot.Session?)
        case restDay(next: HomeWidgetSnapshot.Session?)
        case noPlan
        /// No snapshot, or one too old to say anything true about today.
        case unknown
    }

    struct Week: Equatable, Sendable {
        var strengthDone: Int
        var strengthTarget: Int
        var cardioMinutes: Int
        var cardioTarget: Int
        /// Nil when the week rolled over and the streak may have changed.
        var streakWeeks: Int?
    }

    var today: Today
    /// Nil when no weekly goal is set or nothing was written yet.
    var week: Week?

    static let empty = HomeWidgetContent(today: .unknown, week: nil)
}

// MARK: - Logic

nonisolated enum HomeWidgetLogic {
    /// The staleness rule.
    ///
    /// Today: a snapshot from today is shown as written. From another day, a running workout
    /// stays "In progress" (the app keeps it open across midnight and rewrites when it ends),
    /// "No plan" stays, and with a plan the stored next session decides: on today it becomes
    /// today's planned session (exercise count unknown), later it makes today a rest day,
    /// otherwise the state is unknown.
    ///
    /// Week: once `weekEnd` has passed the counts reset to zero against the same targets. The
    /// streak is kept only when the finished week met its goal and no further week has passed;
    /// otherwise it is unknown until the app runs, since a missed week resets it.
    static func content(
        for snapshot: HomeWidgetSnapshot?,
        now: Date,
        calendar: Calendar = .current
    ) -> HomeWidgetContent {
        guard let snapshot else { return .empty }
        return HomeWidgetContent(
            today: today(for: snapshot, now: now, calendar: calendar),
            week: snapshot.week.map { week(for: $0, now: now, calendar: calendar) }
        )
    }

    static func today(for snapshot: HomeWidgetSnapshot, now: Date, calendar: Calendar) -> HomeWidgetContent.Today {
        let next = snapshot.nextSession.flatMap { session in
            calendar.startOfDay(for: session.date) > calendar.startOfDay(for: now) ? session : nil
        }
        if calendar.isDate(snapshot.day, inSameDayAs: now) {
            switch snapshot.today {
            case .planned(let name, let count): return .planned(name: name, exerciseCount: count)
            case .inProgress(let name): return .inProgress(name: name)
            case .doneToday: return .doneToday(next: next)
            case .restDay: return .restDay(next: next)
            case .noPlan: return .noPlan
            }
        }
        switch snapshot.today {
        case .inProgress(let name):
            return .inProgress(name: name)
        case .noPlan:
            return .noPlan
        case .planned, .doneToday, .restDay:
            guard let session = snapshot.nextSession else { return .unknown }
            if calendar.isDate(session.date, inSameDayAs: now) {
                return .planned(name: session.name, exerciseCount: nil)
            }
            if session.date > now { return .restDay(next: session) }
            return .unknown
        }
    }

    static func week(for week: HomeWidgetSnapshot.Week, now: Date, calendar: Calendar) -> HomeWidgetContent.Week {
        guard now >= week.weekEnd else {
            return .init(strengthDone: week.strengthDone, strengthTarget: week.strengthTarget,
                         cardioMinutes: week.cardioMinutes, cardioTarget: week.cardioTarget,
                         streakWeeks: week.streakWeeks)
        }
        let followingWeekEnd = calendar.date(byAdding: .day, value: 7, to: week.weekEnd) ?? week.weekEnd
        let keepsStreak = week.isMet && now < followingWeekEnd
        return .init(strengthDone: 0, strengthTarget: week.strengthTarget,
                     cardioMinutes: 0, cardioTarget: week.cardioTarget,
                     streakWeeks: keepsStreak ? week.streakWeeks : nil)
    }

    /// Timeline entry dates: now, the week's end when it falls before the next midnight, and
    /// the next midnight. The timeline is reloaded at its end (`.atEnd`).
    static func entryDates(now: Date, snapshot: HomeWidgetSnapshot?, calendar: Calendar = .current) -> [Date] {
        let midnight = nextMidnight(after: now, calendar: calendar)
        var dates = [now]
        if let weekEnd = snapshot?.week?.weekEnd, weekEnd > now, weekEnd < midnight {
            dates.append(weekEnd)
        }
        dates.append(midnight)
        return dates
    }

    static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }

    // MARK: Copy

    /// The field's tone: lime unless there is nothing left to train today (as on the Train tab).
    static func fieldIsLime(_ today: HomeWidgetContent.Today) -> Bool {
        switch today {
        case .restDay, .doneToday: false
        default: true
        }
    }

    /// The line above the hero.
    static func todayLine(_ today: HomeWidgetContent.Today, now: Date, calendar: Calendar = .current) -> String {
        switch today {
        case .planned(_, let count):
            guard let count, count > 0 else { return "Today" }
            return count == 1 ? "Today, 1 exercise" : "Today, \(count) exercises"
        case .inProgress:
            return "In progress"
        case .restDay(let next), .doneToday(let next):
            guard let next else { return "Today" }
            return "Next: \(next.name), \(relativeDay(next.date, now: now, calendar: calendar))"
        case .noPlan, .unknown:
            return "Today"
        }
    }

    /// The hero before it is set on lines.
    static func todayTitle(_ today: HomeWidgetContent.Today) -> String {
        switch today {
        case .planned(let name, _), .inProgress(let name): name
        case .restDay: "Rest day"
        case .doneToday: "Done today"
        case .noPlan: "No plan yet"
        case .unknown: "Train"
        }
    }

    /// The hero set on at most two lines (same rule as CutHeroText.balancedLines).
    static func heroLines(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return words }
        var best = (index: 1, longest: Int.max)
        for index in 1..<words.count {
            let first = words[..<index].joined(separator: " ").count
            let second = words[index...].joined(separator: " ").count
            let longest = max(first, second)
            // Ties go to the later break, so the first line carries more ("No plan / yet").
            if longest <= best.longest { best = (index, longest) }
        }
        return [words[..<best.index].joined(separator: " "), words[best.index...].joined(separator: " ")]
    }

    /// "today", "tomorrow", a weekday within six days, otherwise a short date
    /// (CutTrainLogic.relativeDay with the long style).
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = calendar.locale ?? .current
            formatter.setLocalizedDateFormatFromTemplate(abs(days) <= 6 ? "EEEE" : "MMMd")
            return formatter.string(from: date)
        }
    }

    static func fraction(_ done: Int, of target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(max(Double(done) / Double(target), 0), 1)
    }

    static func weeks(_ count: Int) -> String {
        count == 1 ? "1 week" : "\(count) weeks"
    }

    // MARK: Accessibility

    /// One sentence for the weekly goal widget (CutTrainLogic.weeklyGoalAccessibilityLabel).
    static func weeklyGoalSentence(_ week: HomeWidgetContent.Week?) -> String {
        guard let week else { return "No weekly goal set yet." }
        return weekClause(week) + "."
    }

    /// One sentence for the Today widget.
    static func todaySentence(_ today: HomeWidgetContent.Today, now: Date, calendar: Calendar = .current) -> String {
        todayClause(today, now: now, calendar: calendar) + "."
    }

    /// One sentence for the Today and week widget.
    static func todayAndWeekSentence(
        _ content: HomeWidgetContent,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let today = todayClause(content.today, now: now, calendar: calendar)
        guard let week = content.week else { return today + "; no weekly goal set yet." }
        let days = week.strengthTarget == 1 ? "day" : "days"
        var clause = "strength \(week.strengthDone) of \(week.strengthTarget) \(days) this week"
        if let streak = week.streakWeeks, streak > 0 {
            clause += ", \(weeks(streak)) streak"
        } else {
            clause += ", cardio \(week.cardioMinutes) of \(week.cardioTarget) minutes"
        }
        return today + "; " + clause + "."
    }

    private static func weekClause(_ week: HomeWidgetContent.Week) -> String {
        let days = week.strengthTarget == 1 ? "day" : "days"
        return "Weekly goal: strength \(week.strengthDone) of \(week.strengthTarget) \(days), "
            + "cardio \(week.cardioMinutes) of \(week.cardioTarget) minutes"
    }

    private static func todayClause(_ today: HomeWidgetContent.Today, now: Date, calendar: Calendar) -> String {
        func nextPart(_ next: HomeWidgetSnapshot.Session?) -> String {
            guard let next else { return "" }
            return ", next: \(next.name) \(relativeDay(next.date, now: now, calendar: calendar))"
        }
        switch today {
        case .planned(let name, let count):
            guard let count, count > 0 else { return "Today: \(name)" }
            return "Today: \(name), \(count) \(count == 1 ? "exercise" : "exercises")"
        case .inProgress(let name):
            return "Workout in progress: \(name)"
        case .restDay(let next):
            return "Today is a rest day" + nextPart(next)
        case .doneToday(let next):
            return "Today's session is done" + nextPart(next)
        case .noPlan:
            return "No training plan yet"
        case .unknown:
            return "Today: open VOLIA to see your session"
        }
    }
}

// MARK: - Store

/// Reads and writes the snapshot file. The directory is injectable for tests; by default it is
/// the app group container, which is nil when the entitlement is missing (then reads return nil
/// and writes do nothing).
nonisolated struct HomeWidgetSnapshotStore: Sendable {
    let directory: URL?

    init(directory: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: HomeWidgetShared.appGroupID
    )) {
        self.directory = directory
    }

    var fileURL: URL? {
        directory?.appendingPathComponent(HomeWidgetShared.snapshotFileName)
    }

    func read() -> HomeWidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(HomeWidgetSnapshot.self, from: data),
              snapshot.version == HomeWidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    /// Writes atomically. Returns false when there is no container or the write failed.
    @discardableResult
    func write(_ snapshot: HomeWidgetSnapshot) -> Bool {
        guard let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
