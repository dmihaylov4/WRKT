//
//  CutStartSheetModel.swift
//  WRKT
//
//  Cut start workout sheet: the plain values it shows and the logic that picks them.
//  QuickWorkoutTypeSelector feeds it; tests and captures feed it fixtures.
//

import Foundation

/// Today's planned session as the start sheet shows it.
struct CutStartSheetPlan: Equatable {
    let name: String
    let exerciseCount: Int
}

/// Everything the Cut start sheet shows.
struct CutStartSheetModel: Equatable {
    /// Sentence case sheet title ("Start a workout", "Add exercise").
    let title: String
    /// Shown first, in lime, only when a planned session can be started from this sheet.
    let plan: CutStartSheetPlan?
    /// The sheet's existing choices, in their existing order.
    let choices: [QuickWorkoutTypeSelector.WorkoutType]
}

enum CutStartSheetLogic {
    /// The legacy sheet's choices, in order: the two quick options, then Custom.
    static let choices: [QuickWorkoutTypeSelector.WorkoutType] = [.upperBody, .lowerBody, .custom]

    static func model(legacyTitle: String, plan: CutStartSheetPlan?) -> CutStartSheetModel {
        CutStartSheetModel(title: title(legacyTitle), plan: plan, choices: choices)
    }

    /// The legacy title in sentence case: "Start Workout" reads "Start a workout",
    /// anything else keeps its first capital only ("Add Exercise" -> "Add exercise").
    static func title(_ legacyTitle: String) -> String {
        let trimmed = legacyTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("Start Workout") == .orderedSame { return "Start a workout" }
        guard let first = trimmed.first else { return "Start a workout" }
        return String(first).uppercased() + trimmed.dropFirst().lowercased()
    }

    /// The row title in sentence case; the view sets it in condensed capitals.
    static func choiceTitle(_ type: QuickWorkoutTypeSelector.WorkoutType) -> String {
        switch type {
        case .upperBody: "Upper body"
        case .lowerBody: "Lower body"
        case .custom: "Custom"
        }
    }

    /// The plan's one supporting line, or nil when it has no exercises to count.
    /// Says the hero is today's plan, so it does not read as a copy of the type row below.
    static func planLine(_ plan: CutStartSheetPlan) -> String {
        guard plan.exerciseCount > 0 else { return "Today's plan" }
        return plan.exerciseCount == 1 ? "Today's plan, 1 exercise" : "Today's plan, \(plan.exerciseCount) exercises"
    }
}
