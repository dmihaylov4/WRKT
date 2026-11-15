//
//  CutSetEditorModel.swift
//  WRKT
//
//  The plain values and step rules behind the Cut set editor (RetrospectiveSetEditor): one row
//  per set with weight in the user's unit and reps, the steps the minus and plus buttons take,
//  and the set Add set appends. Weight is stored in kilograms; only the display converts.
//

import Foundation

struct CutSetEditorRow: Equatable, Identifiable {
    var id: Int
    /// "1"
    var number: String
    /// "62.5", in the user's unit.
    var weight: String
    var reps: String
    var canDecreaseWeight: Bool
    var canDecreaseReps: Bool
}

struct CutSetEditorModel: Equatable {
    var exerciseName: String
    /// "kg" or "lb"
    var unitLabel: String
    /// "4 sets"
    var countLine: String
    var rows: [CutSetEditorRow]
}

/// One change the set editor makes. Indexes are set positions.
enum CutSetEditorEdit: Equatable {
    case weightDown(Int), weightUp(Int), repsDown(Int), repsUp(Int)
    /// Typed text in the user's unit; text that is not a number changes nothing.
    case typedWeight(Int, String)
    case typedReps(Int, String)
    case delete(Int)
    case add
}

enum CutSetEditorLogic {
    /// The entry after one edit. Out-of-range indexes change nothing.
    static func apply(_ edit: CutSetEditorEdit, to entry: WorkoutEntry, unit: WeightUnit, locale: Locale = .current) -> WorkoutEntry {
        var entry = entry
        func update(_ index: Int, _ change: (inout SetInput) -> Void) {
            guard entry.sets.indices.contains(index) else { return }
            change(&entry.sets[index])
        }
        switch edit {
        case .weightDown(let i): update(i) { $0.weight = decreasedWeight($0.weight, unit: unit) }
        case .weightUp(let i): update(i) { $0.weight = increasedWeight($0.weight, unit: unit) }
        case .repsDown(let i): update(i) { $0.reps = decreasedReps($0.reps) }
        case .repsUp(let i): update(i) { $0.reps = increasedReps($0.reps) }
        case .typedWeight(let i, let text):
            if let kg = typedWeight(text, unit: unit, locale: locale) { update(i) { $0.weight = kg } }
        case .typedReps(let i, let text):
            if let reps = typedReps(text) { update(i) { $0.reps = reps } }
        case .delete(let i):
            if entry.sets.indices.contains(i) { entry.sets.remove(at: i) }
        case .add:
            entry.sets.append(newSet(after: entry.sets))
        }
        return entry
    }

    /// The legacy factor, kept so stored kilograms round-trip exactly as before.
    static let poundsPerKilogram = 2.20462

    static func model(_ entry: WorkoutEntry, unit: WeightUnit) -> CutSetEditorModel {
        CutSetEditorModel(
            exerciseName: entry.exerciseName,
            unitLabel: unit.label,
            countLine: entry.sets.count == 1 ? "1 set" : "\(entry.sets.count) sets",
            rows: entry.sets.enumerated().map { index, set in
                CutSetEditorRow(
                    id: index,
                    number: "\(index + 1)",
                    weight: weightText(set.weight, unit: unit),
                    reps: "\(set.reps)",
                    canDecreaseWeight: canDecreaseWeight(set.weight, unit: unit),
                    canDecreaseReps: canDecreaseReps(set.reps)
                )
            }
        )
    }

    // MARK: Weight

    /// 2.5 kg or 5 lb.
    static func step(_ unit: WeightUnit) -> Double {
        unit == .kg ? 2.5 : 5
    }

    static func displayWeight(_ kg: Double, unit: WeightUnit) -> Double {
        unit == .kg ? kg : kg * poundsPerKilogram
    }

    static func kilograms(fromDisplay value: Double, unit: WeightUnit) -> Double {
        unit == .kg ? value : value / poundsPerKilogram
    }

    /// "60", "62.5": one decimal, without a trailing ".0".
    static func weightText(_ kg: Double, unit: WeightUnit) -> String {
        let value = (displayWeight(kg, unit: unit) * 10).rounded() / 10
        return value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func canDecreaseWeight(_ kg: Double, unit: WeightUnit) -> Bool {
        displayWeight(kg, unit: unit) > 0
    }

    /// One step down in the user's unit, never below zero. Returns kilograms.
    static func decreasedWeight(_ kg: Double, unit: WeightUnit) -> Double {
        kilograms(fromDisplay: max(0, displayWeight(kg, unit: unit) - step(unit)), unit: unit)
    }

    /// One step up in the user's unit. Returns kilograms.
    static func increasedWeight(_ kg: Double, unit: WeightUnit) -> Double {
        kilograms(fromDisplay: displayWeight(kg, unit: unit) + step(unit), unit: unit)
    }

    /// A typed weight in the user's unit, as kilograms; nil for text that is not a number
    /// or is negative, so the set keeps its weight.
    static func typedWeight(_ text: String, unit: WeightUnit, locale: Locale = .current) -> Double? {
        guard let value = number(text, locale: locale), value >= 0 else { return nil }
        return kilograms(fromDisplay: value, unit: unit)
    }

    // MARK: Reps

    /// The legacy floor: minus stops at one rep.
    static func canDecreaseReps(_ reps: Int) -> Bool {
        reps > 1
    }

    static func decreasedReps(_ reps: Int) -> Int {
        canDecreaseReps(reps) ? reps - 1 : reps
    }

    static func increasedReps(_ reps: Int) -> Int {
        reps + 1
    }

    /// Typed reps as a whole number; nil for anything else, so the set keeps its reps.
    static func typedReps(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
        return value
    }

    // MARK: Selection

    /// The set whose steppers show after one is deleted (`count` is the number before the
    /// delete): the same set when it stays, the next one in its place, or the new last set.
    static func selection(afterDeleting deleted: Int, selected: Int, count: Int) -> Int {
        if deleted < selected { return selected - 1 }
        if deleted == selected { return max(0, min(selected, count - 2)) }
        return selected
    }

    // MARK: Sets

    /// Add set copies the last set's reps and weight, or starts at 10 reps with no weight.
    static func newSet(after sets: [SetInput]) -> SetInput {
        guard let last = sets.last else { return SetInput(reps: 10, weight: 0, isCompleted: true) }
        return SetInput(reps: last.reps, weight: last.weight, isCompleted: true)
    }

    private static func number(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if let value = formatter.number(from: trimmed)?.doubleValue { return value }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
