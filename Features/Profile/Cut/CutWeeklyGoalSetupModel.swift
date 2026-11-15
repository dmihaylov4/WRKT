//
//  CutWeeklyGoalSetupModel.swift
//  WRKT
//
//  The Cut weekly goal setup (WeeklyGoalSetupView): the draft it edits, the legacy bounds and
//  steps (age 10 to 100, active minutes 30 to 600 by 15, daily steps 1,000 to 30,000 by 500,
//  strength days 0 to 7), and the lines it shows. Saving writes the same goal fields and the
//  same age commit as the legacy screen (see CutWeeklyGoalSetupHost).
//

import Foundation

struct CutWeeklyGoalSetupDraft: Equatable {
    var targetMinutes = 150
    var targetDailySteps = 10000
    var targetStrengthDays = 2
    /// 1 is Sunday; 2 (Monday) is the legacy default.
    var weekStartDay = 2
    var trackingMode: ActivityTrackingMode = .exerciseMinutes
    var age = AgeDraft(saved: nil)
}

struct CutWeeklyGoalSetupModel: Equatable {
    var title = "Weekly goal"
    var subtitle = "Set targets for steps, minutes, and strength days."
    var age: String
    var canDecreaseAge: Bool
    var canIncreaseAge: Bool
    var ageFooter = "Used to calculate your heart rate zones"
    /// "Active minutes (MVPA)" or "Daily steps", per tracking mode.
    var activityTitle: String
    var activityValue: String
    var activityFooter: String
    var strengthDays: String
    var canDecreaseStrength: Bool
    var canIncreaseStrength: Bool
    var strengthFooter = "Aim for 2-3 strength sessions per week"
    var weekStartOptions: [CutSettingsOption<Int>]
    var weekStartFooter: String
    var saveTitle = "Save goal"
}

enum CutWeeklyGoalSetupLogic {
    static let minutesRange = 30...600
    static let minutesStep = 15
    static let stepsRange = 1000...30000
    static let stepsStep = 500
    static let strengthRange = 0...7

    static func model(_ draft: CutWeeklyGoalSetupDraft, weekdaySymbols: [String] = Calendar.current.weekdaySymbols,
                      locale: Locale = .current) -> CutWeeklyGoalSetupModel {
        let minutesMode = draft.trackingMode == .exerciseMinutes
        return CutWeeklyGoalSetupModel(
            age: "\(draft.age.age)",
            canDecreaseAge: draft.age.age > AgeDraft.range.lowerBound,
            canIncreaseAge: draft.age.age < AgeDraft.range.upperBound,
            activityTitle: minutesMode ? "Active minutes (MVPA)" : "Daily steps",
            activityValue: minutesMode ? "\(draft.targetMinutes) min" : draft.targetDailySteps.formatted(.number.locale(locale)),
            activityFooter: minutesMode ? "Apple Watch tracks exercise time automatically"
                                        : "Aim for 10,000 steps per day for good health",
            strengthDays: "\(draft.targetStrengthDays) \(draft.targetStrengthDays == 1 ? "day" : "days")",
            canDecreaseStrength: draft.targetStrengthDays > strengthRange.lowerBound,
            canIncreaseStrength: draft.targetStrengthDays < strengthRange.upperBound,
            weekStartOptions: (1...7).map {
                CutSettingsOption(value: $0, label: CutWeeklyGoalLogic.weekdayName($0, symbols: weekdaySymbols))
            },
            weekStartFooter: "Your week will start on \(CutWeeklyGoalLogic.weekdayName(draft.weekStartDay, symbols: weekdaySymbols))"
        )
    }

    /// One stepper tap inside the range; nil when it would not change (the legacy guard, no haptic).
    static func stepped(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int? {
        let next = value + delta
        return range.contains(next) ? next : nil
    }

    /// A slider position snapped to the legacy step, as Int(value) of a stepped slider gave.
    static func snapped(_ value: Double, step: Int, in range: ClosedRange<Int>) -> Int {
        let steps = ((value - Double(range.lowerBound)) / Double(step)).rounded()
        return min(max(range.lowerBound + Int(steps) * step, range.lowerBound), range.upperBound)
    }

    /// The goal as saved: set, the four targets, the mode and the time.
    static func apply(_ draft: CutWeeklyGoalSetupDraft, to goal: WeeklyGoal, now: Date = .now) {
        goal.isSet = true
        goal.targetActiveMinutes = draft.targetMinutes
        goal.targetDailySteps = draft.targetDailySteps
        goal.targetStrengthDays = draft.targetStrengthDays
        goal.anchorWeekday = draft.weekStartDay
        goal.mode = draft.trackingMode
        goal.updatedAt = now
    }
}
