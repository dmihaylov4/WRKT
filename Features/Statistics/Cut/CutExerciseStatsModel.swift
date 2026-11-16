//
//  CutExerciseStatsModel.swift
//  WRKT
//
//  One exercise's statistics in Cut as plain values: up to three records for the lime field,
//  one line series per segment (Weight, Volume, 1RM for weighted lifts), the merged sessions list
//  with the record sessions marked, and a session's log for the sheet. Everything is read from
//  the ExerciseStatistics value ExerciseStatsAggregator returns; weights stay in kilograms until
//  formatted in the user's unit. All series are built once, so a segment switch only re-reads one.
//

import Foundation

nonisolated struct CutExerciseStatsModel: Equatable {
    struct Record: Equatable, Identifiable {
        enum Kind: String, Equatable { case heaviest, oneRepMax, mostReps, mostRepsSession, longestHold }
        var kind: Kind
        var label: String
        var value: String
        var line: String
        var workoutID: UUID
        var accessibilityLabel: String
        var id: Kind { kind }

        /// How the session log names the record ("Record: heaviest, best 1RM").
        var phrase: String {
            switch kind {
            case .heaviest: return "heaviest"
            case .oneRepMax: return "best 1RM"
            case .mostReps, .mostRepsSession: return "most reps"
            case .longestHold: return "longest hold"
            }
        }
    }

    enum Metric: String, CaseIterable, Hashable { case weight, volume, oneRepMax }

    struct Point: Equatable {
        /// 0 at the first session, 1 at the latest.
        var x: Double
        /// 0 at the lowest value, 1 at the highest.
        var y: Double
    }

    struct Series: Equatable, Identifiable {
        var metric: Metric
        var title: String
        var points: [Point]
        var captionLeading: String
        var captionTrailing: String
        var accessibilityLabel: String
        var id: Metric { metric }
    }

    struct Session: Equatable, Identifiable {
        /// The history entry's ID, used to open its log.
        var id: UUID
        var workoutID: UUID
        var title: String
        var line: String
        var isRecord: Bool
        var accessibilityLabel: String
    }

    var title: String
    var records: [Record]
    var series: [Series]
    /// Shown in place of the chart with a single session.
    var chartNote: String?
    var sessionsTitle: String
    var sessions: [Session]
    /// Shown when the exercise has never been logged.
    var emptyLine: String?

    var defaultMetric: Metric? { series.first?.metric }

    func series(for metric: Metric?) -> Series? {
        series.first { $0.metric == metric } ?? series.first
    }
}

/// One session's log for the Browser sheet.
struct CutSessionLogModel: Equatable {
    struct SetRow: Equatable, Identifiable {
        var id: Int
        var label: String
        var value: String
    }

    var title: String
    var subtitle: String
    /// The records this session holds ("Record: heaviest, most reps"), nil when none.
    var recordLine: String?
    var stats: [CutStatColumn]
    var sets: [SetRow]
}

nonisolated enum CutExerciseStatsLogic {
    static func model(_ stats: ExerciseStatistics, unit: WeightUnit, now: Date,
                      calendar: Calendar = .current, locale: Locale = .current) -> CutExerciseStatsModel {
        let records = records(stats, unit: unit, calendar: calendar, locale: locale)
        let recordWorkouts = Set(records.map(\.workoutID))
        let sessions = stats.history.allWorkouts.map {
            session($0, trackingMode: stats.trackingMode, isRecord: recordWorkouts.contains($0.workoutID),
                    unit: unit, now: now, calendar: calendar, locale: locale)
        }
        let series = series(stats, unit: unit, calendar: calendar, locale: locale)
        let count = stats.frequencyStats.totalTimesPerformed
        return CutExerciseStatsModel(
            title: stats.exerciseName,
            records: records,
            series: series,
            chartNote: series.isEmpty && count == 1 ? "Log it once more to see a trend." : nil,
            sessionsTitle: "Sessions",
            sessions: sessions,
            emptyLine: count == 0 ? "No sessions logged yet." : nil
        )
    }

    // MARK: Records

    /// Up to three records for the lime field, in the mock's order for weighted lifts.
    static func records(_ stats: ExerciseStatistics, unit: WeightUnit, calendar: Calendar, locale: Locale) -> [CutExerciseStatsModel.Record] {
        let prs = stats.personalRecords
        var records: [CutExerciseStatsModel.Record] = []
        switch stats.trackingMode {
        case .weighted:
            if let pr = prs.heaviestWeight { records.append(heaviest(pr, added: false, unit: unit, calendar: calendar, locale: locale)) }
            if let pr = prs.bestE1RM {
                let value = CutStatsFormat.weight(pr.value, unit: unit, locale: locale)
                records.append(.init(kind: .oneRepMax, label: "Best 1RM", value: value, line: "estimated", workoutID: pr.workoutID,
                                     accessibilityLabel: "Best estimated 1RM, \(CutStatsFormat.spokenWeight(pr.value, unit: unit, locale: locale))"))
            }
            if let pr = prs.mostReps {
                let reps = Int(pr.value)
                let weightKg = pr.secondaryValue ?? 0
                let line = weightKg > 0 ? "at \(CutStatsFormat.weight(weightKg, unit: unit, locale: locale))" : "no added weight"
                let spoken = weightKg > 0 ? "at \(CutStatsFormat.spokenWeight(weightKg, unit: unit, locale: locale))" : "with no added weight"
                records.append(.init(kind: .mostReps, label: "Most reps", value: CutStatsFormat.number(reps, locale: locale), line: line,
                                     workoutID: pr.workoutID, accessibilityLabel: "Most reps, \(reps) \(spoken)"))
            }
        case .bodyweight:
            if let pr = prs.mostRepsBodyweight {
                let reps = Int(pr.value)
                records.append(.init(kind: .mostRepsSession, label: "Most reps", value: CutStatsFormat.number(reps, locale: locale),
                                     line: "in one session", workoutID: pr.workoutID,
                                     accessibilityLabel: "Most reps in one session, \(reps)"))
            }
            if let pr = prs.heaviestWeight { records.append(heaviest(pr, added: true, unit: unit, calendar: calendar, locale: locale)) }
        case .timed:
            if let pr = prs.longestHold {
                let seconds = Int(pr.value)
                let day = CutStatsFormat.dayMonth(pr.date, calendar: calendar, locale: locale)
                records.append(.init(kind: .longestHold, label: "Longest hold", value: CutStatsFormat.duration(seconds), line: day,
                                     workoutID: pr.workoutID,
                                     accessibilityLabel: "Longest hold, \(CutStatsFormat.spokenDuration(seconds)) on \(day)"))
            }
        case .distance:
            break
        }
        return records
    }

    private static func heaviest(_ pr: PRRecord, added: Bool, unit: WeightUnit, calendar: Calendar, locale: Locale) -> CutExerciseStatsModel.Record {
        let reps = Int(pr.secondaryValue ?? 0)
        let day = CutStatsFormat.dayMonth(pr.date, calendar: calendar, locale: locale)
        let weight = CutStatsFormat.weight(pr.value, unit: unit, locale: locale)
        let spoken = CutStatsFormat.spokenWeight(pr.value, unit: unit, locale: locale)
        return .init(kind: .heaviest, label: "Heaviest", value: added ? "+\(weight)" : weight, line: "x \(reps), \(day)",
                     workoutID: pr.workoutID,
                     accessibilityLabel: "Heaviest, \(added ? "plus " : "")\(spoken) for \(reps) \(reps == 1 ? "rep" : "reps") on \(day)")
    }

    // MARK: Series

    static func series(_ stats: ExerciseStatistics, unit: WeightUnit, calendar: Calendar, locale: Locale) -> [CutExerciseStatsModel.Series] {
        let data = stats.progressData
        let mode = stats.trackingMode
        var result: [CutExerciseStatsModel.Series] = []
        if let series = series(.weight, data.weightProgression, mode: mode, unit: unit, calendar: calendar, locale: locale) {
            result.append(series)
        }
        if let series = series(.volume, data.volumeProgression, mode: mode, unit: unit, calendar: calendar, locale: locale) {
            result.append(series)
        }
        if mode == .weighted,
           let series = series(.oneRepMax, data.e1rmProgression, mode: mode, unit: unit, calendar: calendar, locale: locale) {
            result.append(series)
        }
        return result
    }

    static func title(_ metric: CutExerciseStatsModel.Metric, mode: TrackingMode) -> String {
        switch (metric, mode) {
        case (.oneRepMax, _): return "1RM"
        case (.weight, .weighted): return "Weight"
        case (.volume, .weighted): return "Volume"
        case (.weight, .bodyweight): return "Reps per set"
        case (.volume, .bodyweight): return "Total reps"
        case (.weight, .timed): return "Per set"
        case (.volume, .timed): return "Total time"
        case (.weight, .distance): return "Per set"
        case (.volume, .distance): return "Total"
        }
    }

    /// What the line shows, for the chart's spoken description.
    static func subject(_ metric: CutExerciseStatsModel.Metric, mode: TrackingMode) -> String {
        switch (metric, mode) {
        case (.oneRepMax, _): return "Best estimated 1RM per session"
        case (.weight, .weighted): return "Average weight per session"
        case (.volume, .weighted): return "Volume per session"
        case (.weight, .bodyweight): return "Average reps per set"
        case (.volume, .bodyweight): return "Total reps per session"
        case (.weight, .timed): return "Average time per set"
        case (.volume, .timed): return "Total time per session"
        case (.weight, .distance): return "Average distance per set"
        case (.volume, .distance): return "Total distance per session"
        }
    }

    static func value(_ raw: Double, metric: CutExerciseStatsModel.Metric, mode: TrackingMode, unit: WeightUnit,
                      locale: Locale, spoken: Bool) -> String {
        switch mode {
        case .weighted:
            if metric == .volume {
                return spoken ? CutStatsFormat.spokenVolume(raw, unit: unit, locale: locale) : CutStatsFormat.volume(raw, unit: unit, locale: locale)
            }
            return spoken ? CutStatsFormat.spokenWeight(raw, unit: unit, locale: locale) : CutStatsFormat.weight(raw, unit: unit, locale: locale)
        case .bodyweight:
            let number = metric == .volume ? CutStatsFormat.number(Int(raw.rounded()), locale: locale) : CutStatsFormat.decimal(raw, locale: locale)
            return "\(number) reps"
        case .timed:
            let seconds = Int(raw.rounded())
            return spoken ? CutStatsFormat.spokenDuration(seconds) : CutStatsFormat.duration(seconds)
        case .distance:
            return CutStatsFormat.distance(raw, locale: locale)
        }
    }

    /// A drawable series needs two sessions; nil otherwise.
    static func series(_ metric: CutExerciseStatsModel.Metric, _ points: [ProgressPoint], mode: TrackingMode, unit: WeightUnit,
                       calendar: Calendar, locale: Locale) -> CutExerciseStatsModel.Series? {
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }
        let values = sorted.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = last.date.timeIntervalSince(first.date)
        let normalized = sorted.enumerated().map { index, point in
            CutExerciseStatsModel.Point(
                x: span > 0 ? point.date.timeIntervalSince(first.date) / span : Double(index) / Double(sorted.count - 1),
                y: high > low ? (point.value - low) / (high - low) : 0.5
            )
        }
        let sameMonth = calendar.isDate(first.date, equalTo: last.date, toGranularity: .month)
        let start = sameMonth
            ? CutStatsFormat.dayMonth(first.date, calendar: calendar, locale: locale)
            : CutStatsFormat.date(first.date, template: "MMM", calendar: calendar, locale: locale)
        let shown = { (raw: Double) in value(raw, metric: metric, mode: mode, unit: unit, locale: locale, spoken: false) }
        let spoken = { (raw: Double) in value(raw, metric: metric, mode: mode, unit: unit, locale: locale, spoken: true) }
        return CutExerciseStatsModel.Series(
            metric: metric,
            title: title(metric, mode: mode),
            points: normalized,
            captionLeading: "\(start), \(shown(first.value))",
            captionTrailing: "Latest, \(shown(last.value))",
            accessibilityLabel: "\(subject(metric, mode: mode)) \(trend(from: first.value, to: last.value, spoken: spoken)) over \(spanText(from: first.date, to: last.date, calendar: calendar))"
        )
    }

    /// "rising from 75 to 90 kilograms", "falling from ...", "holding at ..." (1 percent band).
    static func trend(from first: Double, to last: Double, spoken: (Double) -> String) -> String {
        let change = first != 0 ? (last - first) / abs(first) : (last > 0 ? 1 : 0)
        if change > 0.01 { return "rising from \(spoken(first)) to \(spoken(last))" }
        if change < -0.01 { return "falling from \(spoken(first)) to \(spoken(last))" }
        return "holding at \(spoken(last))"
    }

    /// "5 days", "3 weeks", "4 months".
    static func spanText(from start: Date, to end: Date, calendar: Calendar) -> String {
        let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 1)
        func plural(_ value: Int, _ word: String) -> String { "\(value) \(word)\(value == 1 ? "" : "s")" }
        if days < 14 { return plural(days, "day") }
        if days < 63 { return plural(Int((Double(days) / 7).rounded()), "week") }
        return plural(max(2, Int((Double(days) / 30.44).rounded())), "month")
    }

    // MARK: Sessions

    static func session(_ entry: ExerciseWorkoutEntry, trackingMode: TrackingMode, isRecord: Bool, unit: WeightUnit,
                        now: Date, calendar: Calendar, locale: Locale) -> CutExerciseStatsModel.Session {
        let title = CutStatsFormat.sessionDay(entry.date, now: now, calendar: calendar, locale: locale)
        let summary = summary(entry.sets, trackingMode: trackingMode, unit: unit, locale: locale)
        return CutExerciseStatsModel.Session(
            id: entry.id,
            workoutID: entry.workoutID,
            title: title,
            line: summary.shown,
            isRecord: isRecord,
            accessibilityLabel: "\(title), \(summary.spoken)\(isRecord ? ", record" : "")"
        )
    }

    /// "4 sets, top 90 kg x 5", "3 sets, 30 reps", "3 sets, longest 1:30".
    static func summary(_ sets: [SetPerformance], trackingMode: TrackingMode, unit: WeightUnit,
                        locale: Locale) -> (shown: String, spoken: String) {
        let count = CutStatsFormat.count(sets.count, "set", "sets", locale: locale)
        let reps = sets.reduce(0) { $0 + $1.reps }
        switch trackingMode {
        case .weighted:
            let top = sets.filter { $0.weight > 0 }.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
            if let top {
                return ("\(count), top \(CutStatsFormat.weight(top.weight, unit: unit, locale: locale)) x \(top.reps)",
                        "\(count), top set \(CutStatsFormat.spokenWeight(top.weight, unit: unit, locale: locale)) for \(top.reps) \(top.reps == 1 ? "rep" : "reps")")
            }
            return reps > 0 ? ("\(count), \(reps) reps", "\(count), \(reps) reps") : (count, count)
        case .bodyweight:
            return reps > 0 ? ("\(count), \(reps) reps", "\(count), \(reps) reps") : (count, count)
        case .timed:
            if let longest = sets.map(\.durationSeconds).max(), longest > 0 {
                return ("\(count), longest \(CutStatsFormat.duration(longest))",
                        "\(count), longest \(CutStatsFormat.spokenDuration(longest))")
            }
            return (count, count)
        case .distance:
            return (count, count)
        }
    }

    /// "90 kg x 5", "+10 kg x 8", "12 reps", "1:30".
    static func setValue(_ set: SetPerformance, unit: WeightUnit, locale: Locale) -> String {
        switch set.trackingMode {
        case .weighted:
            return set.weight > 0 ? "\(CutStatsFormat.weight(set.weight, unit: unit, locale: locale)) x \(set.reps)" : "\(set.reps) reps"
        case .bodyweight:
            return set.weight > 0 ? "+\(CutStatsFormat.weight(set.weight, unit: unit, locale: locale)) x \(set.reps)" : "\(set.reps) reps"
        case .timed:
            return CutStatsFormat.duration(set.durationSeconds)
        case .distance:
            return set.reps > 0 ? "\(set.reps) reps" : "Logged"
        }
    }
}

/// The session log is built on the main actor for the one session opened (its totals use the
/// shared CutStatColumn).
enum CutSessionLogLogic {
    static func log(_ entry: ExerciseWorkoutEntry, exerciseName: String, trackingMode: TrackingMode,
                    records: [CutExerciseStatsModel.Record], unit: WeightUnit, now: Date,
                    calendar: Calendar = .current, locale: Locale = .current) -> CutSessionLogModel {
        let day = CutStatsFormat.sessionDay(entry.date, now: now, calendar: calendar, locale: locale)
        let time = CutStatsFormat.date(entry.date, template: "jmm", calendar: calendar, locale: locale)
        let held = records.filter { $0.workoutID == entry.workoutID }.map(\.phrase)
        let reps = entry.sets.reduce(0) { $0 + $1.reps }
        var stats = [CutStatColumn(value: CutStatsFormat.number(entry.sets.count, locale: locale),
                                   label: entry.sets.count == 1 ? "set" : "sets")]
        switch trackingMode {
        case .timed:
            let total = entry.sets.reduce(0) { $0 + $1.durationSeconds }
            if total > 0 { stats.append(CutStatColumn(value: CutStatsFormat.duration(total), label: "total time")) }
        default:
            if reps > 0 { stats.append(CutStatColumn(value: CutStatsFormat.number(reps, locale: locale), label: reps == 1 ? "rep" : "reps")) }
        }
        if trackingMode == .weighted, entry.totalVolume > 0 {
            stats.append(CutStatColumn(value: CutStatsFormat.volumeNumber(entry.totalVolume, unit: unit, locale: locale),
                                       label: "\(CutStatsFormat.label(unit)) lifted"))
        }
        let rows = entry.sets.map { set in
            CutSessionLogModel.SetRow(
                id: set.setNumber,
                label: set.tag == .working ? "Set \(set.setNumber)" : "Set \(set.setNumber), \(set.tag.label.lowercased())",
                value: CutExerciseStatsLogic.setValue(set, unit: unit, locale: locale)
            )
        }
        return CutSessionLogModel(
            title: exerciseName,
            subtitle: "\(day), \(time)",
            recordLine: held.isEmpty ? nil : "Record: \(held.joined(separator: ", "))",
            stats: stats,
            sets: rows
        )
    }
}
