//
//  CutWeeklyGoalModel.swift
//  WRKT
//
//  What the Cut weekly goal detail (WeeklyGoalDetailView) shows, as plain values: the week's
//  progress as the V mark with its two numbers and the pace line, the quick actions the week
//  still allows (start strength, view cardio and sync from Apple Health while minutes are left,
//  or the targets complete line), and the goal's three settings.
//

import Foundation

struct CutWeeklyGoalFacts: Equatable {
    var mvpaDone: Int
    var mvpaTarget: Int
    var strengthDaysDone: Int
    var strengthTarget: Int
    var minutesLeft: Int
    var strengthDaysLeft: Int
    var paceStatus: PaceStatus
    var targetActiveMinutes: Int
    var targetStrengthDays: Int
    /// 1 is Sunday, as Calendar counts weekdays.
    var anchorWeekday: Int
}

struct CutWeeklyGoalModel: Equatable {
    struct Action: Equatable {
        var title: String
        var subtitle: String
    }

    var title = "Weekly goal"
    var weekLabel = "This week"
    /// The V mark, its numbers and the pace line, as the Plan tab's weekly goal draws them.
    var goal: CutPlanWeekModel.Goal
    var startStrength: Action?
    var viewCardio: Action?
    var syncHealth: Action?
    /// Both targets met: the line that replaces the actions.
    var completeLine: String?
    var settings: [CutSettingsRowValue]
}

/// A title and value pair for a plain value row.
struct CutSettingsRowValue: Equatable, Identifiable {
    var title: String
    var value: String
    var id: String { title }
}

enum CutWeeklyGoalLogic {
    static func model(_ facts: CutWeeklyGoalFacts, weekdaySymbols: [String] = Calendar.current.weekdaySymbols) -> CutWeeklyGoalModel {
        CutWeeklyGoalModel(
            goal: goal(facts),
            startStrength: facts.strengthDaysLeft > 0
                ? .init(title: "Start strength workout", subtitle: daysRemaining(facts.strengthDaysLeft))
                : nil,
            viewCardio: facts.minutesLeft > 0
                ? .init(title: "View cardio activity", subtitle: "\(facts.minutesLeft) min remaining")
                : nil,
            syncHealth: facts.minutesLeft > 0
                ? .init(title: "Sync from Apple Health", subtitle: "Import runs and exercise minutes")
                : nil,
            completeLine: facts.minutesLeft == 0 && facts.strengthDaysLeft == 0 ? "Weekly targets complete" : nil,
            settings: [
                .init(title: "Target active minutes", value: "\(facts.targetActiveMinutes) min"),
                .init(title: "Target strength days", value: "\(facts.targetStrengthDays) days"),
                .init(title: "Week starts", value: weekdayName(facts.anchorWeekday, symbols: weekdaySymbols))
            ]
        )
    }

    static func goal(_ facts: CutWeeklyGoalFacts) -> CutPlanWeekModel.Goal {
        let status = statusLine(facts.paceStatus)
        let days = facts.strengthTarget == 1 ? "day" : "days"
        return CutPlanWeekModel.Goal(
            weekLabel: "This week",
            strengthValue: "\(facts.strengthDaysDone)/\(facts.strengthTarget)",
            cardioValue: "\(facts.mvpaDone)/\(facts.mvpaTarget)",
            strengthFraction: CutPlanWeekLogic.fraction(facts.strengthDaysDone, of: facts.strengthTarget),
            cardioFraction: CutPlanWeekLogic.fraction(facts.mvpaDone, of: facts.mvpaTarget),
            status: status,
            isSuperWeek: false,
            accessibilityLabel: "This week: strength \(facts.strengthDaysDone) of \(facts.strengthTarget) \(days), "
                + "active minutes \(facts.mvpaDone) of \(facts.mvpaTarget). \(status)"
        )
    }

    /// WeeklyProgress.statusLine, in sentence case.
    static func statusLine(_ pace: PaceStatus) -> String {
        switch pace {
        case .ahead: "Ahead of pace"
        case .onTrack: "On track"
        case .behind: "Behind pace"
        }
    }

    static func daysRemaining(_ days: Int) -> String {
        "\(days) day\(days == 1 ? "" : "s") remaining"
    }

    /// The legacy lookup: weekday 1 is the first symbol (Sunday), wrapping past 7.
    static func weekdayName(_ weekday: Int, symbols: [String]) -> String {
        guard !symbols.isEmpty else { return "" }
        return symbols[((weekday - 1) % symbols.count + symbols.count) % symbols.count]
    }
}
