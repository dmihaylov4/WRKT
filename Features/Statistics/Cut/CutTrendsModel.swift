//
//  CutTrendsModel.swift
//  WRKT
//
//  The Cut Trends screen as plain values: this week's tonnage and its change on last week,
//  twelve weekly bars with the personal average as a dashed line, this week's workouts, sets
//  and reps, and the top lifts by tonnage. Every figure comes from the StatsAggregator
//  summaries the legacy Training Trends section reads (WeeklyTrainingSummary, MovingAverage,
//  ExerciseVolumeSummary); nothing here touches SwiftData or a service.
//

import Foundation

struct CutTrendsFacts: Equatable {
    struct Week: Equatable {
        var weekStart: Date
        /// Stored in kilograms (StatsAggregator sums reps x weightKg).
        var volumeKg: Double
        var sessions: Int
        var sets: Int
        var reps: Int
    }

    struct ExerciseVolume: Equatable {
        var exerciseID: String
        var volumeKg: Double
    }

    /// WeeklyTrainingSummary rows in the 12 week window.
    var weeks: [Week] = []
    /// The latest MovingAverage.personalAvg (all-time average weekly tonnage), in kilograms.
    var personalAverageKg: Double?
    /// ExerciseVolumeSummary rows in the 12 week window.
    var exerciseVolumes: [ExerciseVolume] = []
    /// Exercise names by ID; a missing name falls back to the ID, as in the legacy list.
    var names: [String: String] = [:]
    var unit: WeightUnit = .kg
}

struct CutTrendsModel: Equatable {
    struct Bar: Equatable, Identifiable {
        var id: Int
        var fraction: Double
        var isCurrent: Bool
    }

    struct Lift: Equatable, Identifiable {
        var id: String
        var name: String
        var value: String
        var accessibilityLabel: String
    }

    struct Hero: Equatable {
        var label: String
        var value: String
        var unit: String
        var change: String
        /// Lime only when the week is up on the last.
        var changeIsUp: Bool
        var accessibilityLabel: String
    }

    var title: String
    /// nil before any training in the window: `emptyLine` shows instead.
    var hero: Hero?
    var emptyLine: String?
    var bars: [Bar]
    /// Height of the dashed average line as a fraction of the chart; nil hides it.
    var averageFraction: Double?
    var captionLeading: String
    var captionTrailing: String?
    var chartAccessibilityLabel: String
    var stats: [CutStatColumn]
    var liftsTitle: String
    var lifts: [Lift]
}

enum CutTrendsLogic {
    static let weekCount = 12
    static let topLiftCount = 5

    static func model(_ facts: CutTrendsFacts, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> CutTrendsModel {
        let unit = facts.unit
        let thisWeek = CutStatsFormat.weekStart(for: now, calendar: calendar)
        let slots = (0..<weekCount).compactMap { index in
            calendar.date(byAdding: .weekOfYear, value: index - (weekCount - 1), to: thisWeek)
        }
        let slotWeeks = slots.map { slot in week(at: slot, in: facts.weeks, calendar: calendar) }
        let values = slotWeeks.map { $0?.volumeKg ?? 0 }
        let hasTraining = facts.weeks.contains { $0.volumeKg > 0 || $0.sessions > 0 }
        let lifts = topLifts(facts.exerciseVolumes, names: facts.names, unit: unit, locale: locale)

        guard hasTraining else {
            return CutTrendsModel(
                title: "Trends", hero: nil, emptyLine: "Log a workout to see your weekly trends.",
                bars: [], averageFraction: nil, captionLeading: "", captionTrailing: nil,
                chartAccessibilityLabel: "", stats: [], liftsTitle: "Top lifts", lifts: lifts
            )
        }

        let current = slotWeeks.last.flatMap { $0 }
        let previous = slotWeeks.dropLast().last.flatMap { $0 }
        let currentKg = current?.volumeKg ?? 0
        let change = change(current: currentKg, previous: previous?.volumeKg)

        // The legacy chart drew the personal average only with more than one week of data.
        let average = facts.weeks.count > 1 ? facts.personalAverageKg.flatMap { $0 > 0 ? $0 : nil } : nil
        let top = max(values.max() ?? 0, average ?? 0)
        let bars = values.enumerated().map { index, value in
            CutTrendsModel.Bar(id: index, fraction: top > 0 ? value / top : 0, isCurrent: index == weekCount - 1)
        }

        let hero = CutTrendsModel.Hero(
            label: "Lifted this week",
            value: CutStatsFormat.volumeNumber(currentKg, unit: unit, locale: locale),
            unit: CutStatsFormat.label(unit),
            change: change.line,
            changeIsUp: change.isUp,
            accessibilityLabel: "Lifted this week, \(CutStatsFormat.spokenVolume(currentKg, unit: unit, locale: locale)). \(change.line)"
        )

        return CutTrendsModel(
            title: "Trends",
            hero: hero,
            emptyLine: nil,
            bars: bars,
            averageFraction: average.map { top > 0 ? $0 / top : 0 },
            captionLeading: "12 weeks ago",
            captionTrailing: average == nil ? nil : "Dashed line: your average",
            chartAccessibilityLabel: chartLabel(values: values, averageKg: average, unit: unit, locale: locale),
            stats: [
                CutStatColumn(value: CutStatsFormat.number(current?.sessions ?? 0, locale: locale),
                              label: (current?.sessions ?? 0) == 1 ? "workout" : "workouts"),
                CutStatColumn(value: CutStatsFormat.number(current?.sets ?? 0, locale: locale),
                              label: (current?.sets ?? 0) == 1 ? "set" : "sets"),
                CutStatColumn(value: CutStatsFormat.number(current?.reps ?? 0, locale: locale),
                              label: (current?.reps ?? 0) == 1 ? "rep" : "reps")
            ],
            liftsTitle: "Top lifts",
            lifts: lifts
        )
    }

    /// The summary row for the week starting at `slot`; rows are summed if the store holds two.
    static func week(at slot: Date, in weeks: [CutTrendsFacts.Week], calendar: Calendar) -> CutTrendsFacts.Week? {
        let matches = weeks.filter { calendar.isDate($0.weekStart, inSameDayAs: slot) }
        guard !matches.isEmpty else { return nil }
        return matches.dropFirst().reduce(matches[0]) { total, week in
            CutTrendsFacts.Week(weekStart: total.weekStart, volumeKg: total.volumeKg + week.volumeKg,
                                sessions: total.sessions + week.sessions, sets: total.sets + week.sets,
                                reps: total.reps + week.reps)
        }
    }

    // MARK: Week on week

    /// The lime line under the hero: this week against last week.
    static func change(current: Double, previous: Double?) -> (line: String, isUp: Bool) {
        guard current > 0 else { return ("Nothing logged yet this week", false) }
        guard let previous, previous > 0 else { return ("Nothing logged last week", false) }
        let percent = Int(((current - previous) / previous * 100).rounded())
        if percent > 0 { return ("Up \(percent)% on last week", true) }
        if percent < 0 { return ("Down \(abs(percent))% on last week", false) }
        return ("Level with last week", false)
    }

    // MARK: Chart

    /// The chart in words: the direction over the twelve weeks, then this week and the average.
    static func chartLabel(values: [Double], averageKg: Double?, unit: WeightUnit, locale: Locale) -> String {
        var parts = ["Volume per week over the last 12 weeks, \(direction(values))"]
        if let current = values.last {
            parts.append("this week \(CutStatsFormat.spokenVolume(current, unit: unit, locale: locale))")
        }
        if let averageKg {
            parts.append("your average \(CutStatsFormat.spokenVolume(averageKg, unit: unit, locale: locale))")
        }
        return parts.joined(separator: ", ")
    }

    /// Rising, falling or steady: the later six weeks' mean against the earlier six (10 percent band).
    static func direction(_ values: [Double]) -> String {
        guard values.count >= 2 else { return "steady" }
        let half = values.count / 2
        let earlier = values.prefix(half).reduce(0, +) / Double(half)
        let later = values.suffix(values.count - half).reduce(0, +) / Double(values.count - half)
        guard earlier > 0 else { return later > 0 ? "rising" : "steady" }
        let change = (later - earlier) / earlier
        if change > 0.1 { return "rising" }
        if change < -0.1 { return "falling" }
        return "steady"
    }

    // MARK: Top lifts

    /// The legacy ranking: tonnage summed per exercise over the window, top five.
    static func topLifts(_ volumes: [CutTrendsFacts.ExerciseVolume], names: [String: String],
                         unit: WeightUnit, locale: Locale) -> [CutTrendsModel.Lift] {
        var totals: [String: Double] = [:]
        for row in volumes { totals[row.exerciseID, default: 0] += row.volumeKg }
        return totals
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(topLiftCount)
            .map { id, kg in
                let name = names[id] ?? id
                return CutTrendsModel.Lift(
                    id: id,
                    name: name,
                    value: CutStatsFormat.volume(kg, unit: unit, locale: locale),
                    accessibilityLabel: "\(name), \(CutStatsFormat.spokenVolume(kg, unit: unit, locale: locale)) over 12 weeks"
                )
            }
    }
}
