//
//  CutBalanceModel.swift
//  WRKT
//
//  The Cut Balance screen as plain values: the latest week's push and pull shares with one
//  sentence of verdict, when each muscle group was last trained, and the movement patterns by
//  tonnage. The figures are the StatsAggregator rows the legacy Training Balance section reads
//  (PushPullBalance, MuscleGroupFrequency, MovementPatternBalance); the verdict uses the legacy
//  pull to push ratio bands. The body map is not part of the Cut screen.
//

import Foundation

struct CutBalanceFacts: Equatable {
    /// The latest PushPullBalance row in the window, in kilograms.
    struct PushPull: Equatable {
        var push: Double
        var pull: Double
        var horizontalPush: Double
        var verticalPush: Double
        var horizontalPull: Double
        var verticalPull: Double
        /// The stored pull to push ratio (999 when there is pull and no push, 0 with no pull).
        var ratio: Double
    }

    /// The latest MovementPatternBalance row in the window, in kilograms.
    struct Patterns: Equatable {
        var squat: Double
        var hinge: Double
    }

    struct Muscle: Equatable {
        var name: String
        var lastTrained: Date
    }

    var pushPull: PushPull?
    var patterns: Patterns?
    var muscles: [Muscle] = []
    var unit: WeightUnit = .kg
}

struct CutBalanceModel: Equatable {
    struct Split: Equatable {
        var push: String
        var pull: String
        /// The push share of the bar, 0...1.
        var pushFraction: Double
        var verdict: String
        var accessibilityLabel: String
    }

    struct MuscleRow: Equatable, Identifiable {
        enum Tone: Equatable { case today, recent, stale }
        var name: String
        var value: String
        var tone: Tone
        var id: String { name }
    }

    struct Movement: Equatable, Identifiable {
        var title: String
        var value: String
        var fraction: Double
        var accessibilityLabel: String
        var id: String { title }
    }

    var title: String
    var split: CutBalanceModel.Split?
    var musclesTitle: String
    var muscles: [MuscleRow]
    var movementsTitle: String
    var movements: [Movement]
    /// Shown when there is nothing at all to show.
    var emptyLine: String?
}

enum CutBalanceLogic {
    /// More calendar days than the aggregator's 7 day frequency window: shown in amber.
    static let staleAfterDays = 7

    static func model(_ facts: CutBalanceFacts, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> CutBalanceModel {
        let split = facts.pushPull.flatMap { split($0) }
        let muscles = muscleRows(facts.muscles, now: now, calendar: calendar)
        let movements = movements(facts.pushPull, patterns: facts.patterns, unit: facts.unit, locale: locale)
        let isEmpty = split == nil && muscles.isEmpty && movements.isEmpty
        return CutBalanceModel(
            title: "Balance",
            split: split,
            musclesTitle: "Last trained",
            muscles: muscles,
            movementsTitle: "Movements",
            movements: movements,
            emptyLine: isEmpty ? "Log a workout to see how your training is spread." : nil
        )
    }

    // MARK: Push and pull

    static func split(_ pushPull: CutBalanceFacts.PushPull) -> CutBalanceModel.Split? {
        let total = pushPull.push + pushPull.pull
        guard total > 0 else { return nil }
        let pushPercent = Int((pushPull.push / total * 100).rounded())
        let push = "\(pushPercent)%"
        let pull = "\(100 - pushPercent)%"
        let verdict = verdict(ratio: pushPull.ratio)
        return CutBalanceModel.Split(push: push, pull: pull, pushFraction: pushPull.push / total, verdict: verdict,
                                     accessibilityLabel: "Push \(push), pull \(pull). \(verdict)")
    }

    /// The legacy ratio bands (pull divided by push, target 1.0 to 1.5) as one plain sentence.
    static func verdict(ratio: Double) -> String {
        switch ratio {
        case ..<0, 0: return "Only push work logged. Add some pulling."
        case 0..<0.8: return "Push heavy. Add more pulling."
        case 0.8..<1.0: return "Slightly push heavy. Add a little pulling."
        case 1.0..<1.5: return "Balanced. Keep pull at or above push."
        case 1.5..<2.0: return "Slightly pull heavy. Add a little pushing."
        case 10...: return "Only pull work logged. Add some pushing."
        default: return "Pull heavy. Add more pushing."
        }
    }

    // MARK: Last trained

    static func muscleRows(_ muscles: [CutBalanceFacts.Muscle], now: Date, calendar: Calendar) -> [CutBalanceModel.MuscleRow] {
        muscles
            .sorted { $0.lastTrained != $1.lastTrained ? $0.lastTrained > $1.lastTrained : $0.name < $1.name }
            .map { muscle in
                let days = CutStatsFormat.daysAgo(muscle.lastTrained, now: now, calendar: calendar)
                return CutBalanceModel.MuscleRow(name: muscle.name, value: relativeDays(days), tone: tone(days: days))
            }
    }

    /// "Today", "Yesterday", "2 days ago".
    static func relativeDays(_ days: Int) -> String {
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    static func tone(days: Int) -> CutBalanceModel.MuscleRow.Tone {
        if days < 1 { return .today }
        return days > staleAfterDays ? .stale : .recent
    }

    // MARK: Movements

    /// The movement patterns with tonnage, largest first; bars are relative to the largest.
    static func movements(_ pushPull: CutBalanceFacts.PushPull?, patterns: CutBalanceFacts.Patterns?,
                          unit: WeightUnit, locale: Locale) -> [CutBalanceModel.Movement] {
        var rows: [(String, Double)] = []
        if let pushPull {
            rows += [("Horizontal push", pushPull.horizontalPush), ("Vertical push", pushPull.verticalPush),
                     ("Horizontal pull", pushPull.horizontalPull), ("Vertical pull", pushPull.verticalPull)]
        }
        if let patterns {
            rows += [("Squat", patterns.squat), ("Hinge", patterns.hinge)]
        }
        let present = rows.filter { $0.1 > 0 }
        let top = present.map(\.1).max() ?? 0
        return present
            .enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map { _, row in
                CutBalanceModel.Movement(
                    title: row.0,
                    value: CutStatsFormat.volume(row.1, unit: unit, locale: locale),
                    fraction: top > 0 ? row.1 / top : 0,
                    accessibilityLabel: "\(row.0), \(CutStatsFormat.spokenVolume(row.1, unit: unit, locale: locale))"
                )
            }
    }
}
