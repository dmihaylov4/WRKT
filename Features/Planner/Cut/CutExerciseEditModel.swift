//
//  CutExerciseEditModel.swift
//  WRKT
//
//  One exercise's sets, reps and starting weight, for the two legacy edit sheets it replaces:
//  the setup flow's ExerciseEditSheet and the friend program's ProgramExerciseEditSheet.
//

import Foundation

struct CutExerciseEditModel: Equatable {
    enum Context: Equatable {
        /// New program flow: sets 1 to 10, reps 1 to 30, an empty weight stays empty.
        case setup
        /// A program from a friend: sets 1 to 20, reps 1 to 100, zero weight clears it.
        case invite
    }

    var name: String
    var subtitle: String?
    var sets: Int
    var reps: Int
    var weight: Double?
    var context: Context
    var unitLabel: String
    var weightStep: Double

    var setsRange: ClosedRange<Int> { context == .setup ? 1...10 : 1...20 }
    var repsRange: ClosedRange<Int> { context == .setup ? 1...30 : 1...100 }
    var setsLine: String { "\(sets) \(sets == 1 ? "set" : "sets")" }
    var repsLine: String { "\(reps) \(reps == 1 ? "rep" : "reps")" }
    var canLowerSets: Bool { sets > setsRange.lowerBound }
    var canRaiseSets: Bool { sets < setsRange.upperBound }
    var canLowerReps: Bool { reps > repsRange.lowerBound }
    var canRaiseReps: Bool { reps < repsRange.upperBound }
    var canLowerWeight: Bool { (weight ?? 0) > 0 }
}

enum CutExerciseEditLogic {
    static func model(name: String, sets: Int, reps: Int, weight: Double?, context: CutExerciseEditModel.Context,
                      unitLabel: String, weightStep: Double) -> CutExerciseEditModel {
        var model = CutExerciseEditModel(name: name, subtitle: context == .invite ? "Changes apply to your copy." : nil,
                                         sets: sets, reps: reps, weight: weight, context: context, unitLabel: unitLabel,
                                         weightStep: weightStep > 0 ? weightStep : 2.5)
        model.sets = clamp(sets, model.setsRange)
        model.reps = clamp(reps, model.repsRange)
        return model
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(max(value, range.lowerBound), range.upperBound) }

    static func stepSets(_ model: inout CutExerciseEditModel, by delta: Int) { model.sets = clamp(model.sets + delta, model.setsRange) }
    static func stepReps(_ model: inout CutExerciseEditModel, by delta: Int) { model.reps = clamp(model.reps + delta, model.repsRange) }

    /// The legacy minus never went below zero; plus adds one step.
    static func stepWeight(_ model: inout CutExerciseEditModel, up: Bool) {
        let current = model.weight ?? 0
        model.weight = up ? current + model.weightStep : max(0, current - model.weightStep)
    }

    /// The weight each legacy sheet saved.
    static func savedWeight(_ model: CutExerciseEditModel) -> Double? {
        switch model.context {
        case .setup: return model.weight
        case .invite: return (model.weight ?? 0) > 0 ? model.weight : nil
        }
    }
}
