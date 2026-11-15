//
//  CutPlanWeekModel.swift
//  WRKT
//
//  The Plan tab's "Weekly goal" page in the Cut language: the plain values it shows and the
//  pure rules that pick them, carried over from the legacy MonthHeader banners (goal streak,
//  week progress, push and pull balance). CutPlanWeekHost feeds it; tests feed it fixtures.
//

import Foundation

// MARK: - Input

struct CutPlanWeekInput: Equatable {
    /// The selected week's progress against the goal.
    struct Progress: Equatable {
        let weekStart: Date
        let strengthDone: Int
        let strengthTarget: Int
        let cardioMinutes: Int
        let cardioTarget: Int
    }

    /// Weekly goal streak in weeks.
    var streak = 0
    /// Nil without a weekly goal.
    var progress: Progress?
    /// The week is freeze protected.
    var isFrozen = false
    /// Start of the current week, to call the selected week "This week".
    var currentWeekStart: Date?
    /// Push and pull volume over the last four weeks.
    var pushVolume = 0.0
    var pullVolume = 0.0
}

// MARK: - Screen values

struct CutPlanWeekModel: Equatable {
    struct Goal: Equatable {
        /// "This week", or "9 to 15 Nov".
        let weekLabel: String
        /// "2/4"
        let strengthValue: String
        /// "95/150"
        let cardioValue: String
        /// Left arm of the V mark.
        let strengthFraction: Double
        /// Right arm of the V mark.
        let cardioFraction: Double
        let status: String?
        /// Both goals met: the status is the week's key value, in lime.
        let isSuperWeek: Bool
        let accessibilityLabel: String
    }

    struct Streak: Equatable {
        /// "6"
        let value: String
        /// "week goal streak"
        let label: String
        let filledSegments: Int
        let totalSegments: Int
        /// "Next milestone: 12 weeks"
        let milestoneLine: String
    }

    let goal: Goal?
    let streak: Streak?
    /// The push and pull warning, when the balance is off.
    let balanceMessage: String?
    /// No goal and no streak.
    let showsEmpty: Bool
}

// MARK: - Logic

enum CutPlanWeekLogic {
    /// The legacy streak bar runs to twelve weeks.
    static let streakMilestone = 12

    static func model(_ input: CutPlanWeekInput, calendar: Calendar, locale: Locale = .current) -> CutPlanWeekModel {
        CutPlanWeekModel(
            goal: input.progress.map { goal($0, isFrozen: input.isFrozen, currentWeekStart: input.currentWeekStart,
                                             calendar: calendar, locale: locale) },
            streak: streak(input.streak),
            balanceMessage: balanceMessage(push: input.pushVolume, pull: input.pullVolume),
            showsEmpty: input.progress == nil && input.streak <= 0
        )
    }

    // MARK: Goal

    static func goal(_ progress: CutPlanWeekInput.Progress, isFrozen: Bool, currentWeekStart: Date?,
                     calendar: Calendar, locale: Locale) -> CutPlanWeekModel.Goal {
        // A frozen week counts as done, as on the legacy banner.
        let strength = isFrozen ? progress.strengthTarget : progress.strengthDone
        let cardio = isFrozen ? progress.cardioTarget : progress.cardioMinutes
        let state = status(progress, isFrozen: isFrozen)
        let days = progress.strengthTarget == 1 ? "day" : "days"
        var label = "Weekly goal: strength \(strength) of \(progress.strengthTarget) \(days), "
            + "cardio \(cardio) of \(progress.cardioTarget) minutes"
        if let text = state.text { label += ". " + text }
        return CutPlanWeekModel.Goal(
            weekLabel: weekLabel(progress.weekStart, currentWeekStart: currentWeekStart, calendar: calendar, locale: locale),
            strengthValue: "\(strength)/\(progress.strengthTarget)",
            cardioValue: "\(cardio)/\(progress.cardioTarget)",
            strengthFraction: fraction(strength, of: progress.strengthTarget),
            cardioFraction: fraction(cardio, of: progress.cardioTarget),
            status: state.text,
            isSuperWeek: state.isSuper,
            accessibilityLabel: label
        )
    }

    /// Done over target in 0...1; nothing to fill without a target.
    static func fraction(_ done: Int, of target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, Double(done) / Double(target)))
    }

    /// The legacy banner's line: super week first, then freeze, then which goal is left.
    static func status(_ progress: CutPlanWeekInput.Progress, isFrozen: Bool) -> (text: String?, isSuper: Bool) {
        let strengthMet = progress.strengthDone >= progress.strengthTarget
        // No cardio target counts as met, as on the legacy banner.
        let cardioMet = progress.cardioTarget > 0 ? progress.cardioMinutes >= progress.cardioTarget : true
        if strengthMet && cardioMet { return ("Super week: both goals met", true) }
        if isFrozen { return ("Freeze protected", false) }
        if strengthMet { return ("Strength goal met. Finish the cardio minutes for a super week.", false) }
        if cardioMet { return ("Cardio goal met. Finish the strength days for a super week.", false) }
        return (nil, false)
    }

    /// "This week", or the week's days: "9 to 15 Nov", "30 Nov to 6 Dec".
    static func weekLabel(_ weekStart: Date, currentWeekStart: Date?, calendar: Calendar, locale: Locale) -> String {
        if let currentWeekStart, calendar.isDate(weekStart, inSameDayAs: currentWeekStart) { return "This week" }
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let month = CutWorkoutDetailLogic.formatter("MMM", locale: locale, calendar: calendar)
        let startDay = calendar.component(.day, from: weekStart)
        let endDay = calendar.component(.day, from: end)
        if calendar.isDate(weekStart, equalTo: end, toGranularity: .month) {
            return "\(startDay) to \(endDay) \(month.string(from: end))"
        }
        return "\(startDay) \(month.string(from: weekStart)) to \(endDay) \(month.string(from: end))"
    }

    // MARK: Streak

    static func streak(_ weeks: Int) -> CutPlanWeekModel.Streak? {
        guard weeks > 0 else { return nil }
        return CutPlanWeekModel.Streak(
            value: "\(weeks)",
            label: "week goal streak",
            filledSegments: min(weeks, streakMilestone),
            totalSegments: streakMilestone,
            milestoneLine: "Next milestone: \(streakMilestone) weeks"
        )
    }

    // MARK: Push and pull

    /// Warns when pulling and pushing volume over the last four weeks are far apart. The ratio
    /// is pull over push, as on the training balance screen: above 2 is pull-heavy, below 0.5
    /// is push-heavy. With no push work at all there is no ratio to print.
    static func balanceMessage(push: Double, pull: Double) -> String? {
        guard push > 0 || pull > 0 else { return nil }
        guard push > 0 else {
            return "This week's plan is pull-heavy (no push work). Consider balancing with push work."
        }
        let ratio = pull / push
        let text = String(format: "%.1f", ratio)
        if ratio > 2.0 {
            return "This week's plan is pull-heavy (ratio \(text)). Consider balancing with push work."
        }
        if ratio < 0.5 {
            return "This week's plan is push-heavy (ratio \(text)). Consider adding a row or pull variation."
        }
        return nil
    }
}
