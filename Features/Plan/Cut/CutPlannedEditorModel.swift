//
//  CutPlannedEditorModel.swift
//  WRKT
//
//  The plain values and rules behind the Cut planned workout editor (PlannedWorkoutEditor and
//  its exercise sheet): the exercises being edited as plain drafts, their rows, the set steps,
//  Save, the move dialog and the planned exercises a save writes. Tested without views.
//

import Foundation

// MARK: - Drafts

/// One planned set while editing. Weight is stored in kilograms.
struct CutPlannedSetDraft: Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var weightKg: Double
    /// SetTag raw value, kept as it was.
    var tag: String = SetTag.working.rawValue
}

/// One planned exercise while editing (the legacy PlannedExerciseConfig).
struct CutPlannedExerciseDraft: Equatable, Identifiable {
    var id = UUID()
    var exerciseID: String
    var exerciseName: String
    var sets: [CutPlannedSetDraft]
    var progression: ProgressionStrategy = .static
    var notes: String?
    var order: Int
}

// MARK: - Screen values

struct CutPlannedEditorModel: Equatable {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let name: String
        /// "10×60kg, 10×60kg, 10×60kg, +1"
        let preview: String
        /// "3 sessions without progress"
        let plateau: String?
        let note: String?
    }

    /// "Plan workout" or "Edit workout".
    let title: String
    /// The workout belongs to a plan: a new date offers to shift the rest of the plan.
    let showsMoveHint: Bool
    let rows: [Row]
    let canSave: Bool
    let canDelete: Bool
}

/// The exercise sheet: sets as rows (the batch 1 set editor rows) and the note.
struct CutPlannedSetsModel: Equatable {
    let exerciseName: String
    let unitLabel: String
    /// "3 sets"
    let countLine: String
    let rows: [CutSetEditorRow]
}

// MARK: - Logic

enum CutPlannedEditorLogic {
    static let defaultName = "Custom Workout"
    static let namePlaceholder = "e.g. Upper Body, Leg Day"
    static let nameHint = "If left blank, it is saved as Custom Workout."
    static let moveHint = "Changing the date lets you move only this workout or shift the rest of the upcoming plan."
    static let plateauThreshold = 3

    // MARK: Model

    static func model(
        isNew: Bool,
        hasSplit: Bool,
        drafts: [CutPlannedExerciseDraft],
        plateaus: [String: Int],
        unit: WeightUnit
    ) -> CutPlannedEditorModel {
        CutPlannedEditorModel(
            title: isNew ? "Plan workout" : "Edit workout",
            showsMoveHint: !isNew && hasSplit,
            rows: drafts.map { row($0, sessionsAtSameWeight: plateaus[$0.exerciseID] ?? 0, unit: unit) },
            canSave: canSave(drafts),
            canDelete: !isNew
        )
    }

    static func row(_ draft: CutPlannedExerciseDraft, sessionsAtSameWeight: Int, unit: WeightUnit) -> CutPlannedEditorModel.Row {
        CutPlannedEditorModel.Row(
            id: draft.id,
            name: draft.exerciseName,
            preview: preview(draft.sets, unit: unit),
            plateau: sessionsAtSameWeight >= plateauThreshold ? "\(sessionsAtSameWeight) sessions without progress" : nil,
            note: notePreview(draft.notes)
        )
    }

    /// The legacy chips in a line: the first three sets, then how many more.
    static func preview(_ sets: [CutPlannedSetDraft], unit: WeightUnit) -> String {
        guard !sets.isEmpty else { return "No sets" }
        var parts = sets.prefix(3).map { unit.formatSetCompact(reps: $0.reps, weightKg: $0.weightKg) }
        if sets.count > 3 { parts.append("+\(sets.count - 3)") }
        return parts.joined(separator: ", ")
    }

    static func notePreview(_ notes: String?) -> String? {
        guard let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return notes
    }

    // MARK: Exercises

    /// A picked exercise: three sets of 10 at the last working weight, at the end of the list.
    static func newDraft(exerciseID: String, name: String, suggestedWeightKg: Double?, order: Int) -> CutPlannedExerciseDraft {
        let weight = suggestedWeightKg ?? 0
        return CutPlannedExerciseDraft(
            exerciseID: exerciseID,
            exerciseName: name,
            sets: (0..<3).map { _ in CutPlannedSetDraft(reps: 10, weightKg: weight) },
            order: order
        )
    }

    /// The list without one exercise, renumbered.
    static func removing(_ id: UUID, from drafts: [CutPlannedExerciseDraft]) -> [CutPlannedExerciseDraft] {
        renumbered(drafts.filter { $0.id != id })
    }

    static func removing(atOffsets offsets: IndexSet, from drafts: [CutPlannedExerciseDraft]) -> [CutPlannedExerciseDraft] {
        renumbered(drafts.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
    }

    static func renumbered(_ drafts: [CutPlannedExerciseDraft]) -> [CutPlannedExerciseDraft] {
        drafts.enumerated().map { index, draft in
            var draft = draft
            draft.order = index
            return draft
        }
    }

    // MARK: Sets

    static func setsModel(_ draft: CutPlannedExerciseDraft, unit: WeightUnit) -> CutPlannedSetsModel {
        CutPlannedSetsModel(
            exerciseName: draft.exerciseName,
            unitLabel: unit.label,
            countLine: draft.sets.count == 1 ? "1 set" : "\(draft.sets.count) sets",
            rows: draft.sets.enumerated().map { index, set in
                CutSetEditorRow(
                    id: index,
                    number: "\(index + 1)",
                    weight: CutSetEditorLogic.weightText(set.weightKg, unit: unit),
                    reps: "\(set.reps)",
                    canDecreaseWeight: CutSetEditorLogic.canDecreaseWeight(set.weightKg, unit: unit),
                    canDecreaseReps: CutSetEditorLogic.canDecreaseReps(set.reps)
                )
            }
        )
    }

    /// The exercise after one set edit: the legacy steps (2.5 kg or 5 lb, never below zero;
    /// reps never below one by the minus), typed values in the user's unit, delete, and add
    /// (a copy of the last set, or 10 reps with no weight). Out-of-range rows change nothing.
    static func apply(_ edit: CutSetEditorEdit, to draft: CutPlannedExerciseDraft, unit: WeightUnit,
                      locale: Locale = .current) -> CutPlannedExerciseDraft {
        var draft = draft
        func update(_ index: Int, _ change: (inout CutPlannedSetDraft) -> Void) {
            guard draft.sets.indices.contains(index) else { return }
            change(&draft.sets[index])
        }
        switch edit {
        case .weightDown(let i): update(i) { $0.weightKg = CutSetEditorLogic.decreasedWeight($0.weightKg, unit: unit) }
        case .weightUp(let i): update(i) { $0.weightKg = CutSetEditorLogic.increasedWeight($0.weightKg, unit: unit) }
        case .repsDown(let i): update(i) { $0.reps = CutSetEditorLogic.decreasedReps($0.reps) }
        case .repsUp(let i): update(i) { $0.reps = CutSetEditorLogic.increasedReps($0.reps) }
        case .typedWeight(let i, let text):
            if let kg = CutSetEditorLogic.typedWeight(text, unit: unit, locale: locale) { update(i) { $0.weightKg = kg } }
        case .typedReps(let i, let text):
            if let reps = CutSetEditorLogic.typedReps(text) { update(i) { $0.reps = reps } }
        case .delete(let i):
            if draft.sets.indices.contains(i) { draft.sets.remove(at: i) }
        case .add:
            if let last = draft.sets.last {
                draft.sets.append(CutPlannedSetDraft(reps: last.reps, weightKg: last.weightKg))
            } else {
                draft.sets.append(CutPlannedSetDraft(reps: 10, weightKg: 0))
            }
        }
        return draft
    }

    /// An empty note is no note.
    static func savedNotes(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    // MARK: Save

    /// The legacy rule: at least one exercise.
    static func canSave(_ drafts: [CutPlannedExerciseDraft]) -> Bool {
        !drafts.isEmpty
    }

    /// The name a save writes: as typed, or "Custom Workout" when empty.
    static func savedName(_ name: String) -> String {
        name.isEmpty ? defaultName : name
    }

    enum SaveStep: Equatable {
        /// Ask whether to move this workout only or shift the upcoming plan.
        case askHowToMove
        case save
    }

    /// A plan workout moved to another day asks first; everything else saves.
    static func saveStep(hasSplit: Bool, original: Date, chosen: Date, calendar: Calendar) -> SaveStep {
        hasSplit && isDateChanged(original: original, chosen: chosen, calendar: calendar) ? .askHowToMove : .save
    }

    static func isDateChanged(original: Date, chosen: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: original) != calendar.startOfDay(for: chosen)
    }

    /// Whole days from the original date to the chosen one (the shift for the upcoming plan).
    static func dayOffset(original: Date, chosen: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: original), to: calendar.startOfDay(for: chosen)).day ?? 0
    }

    /// Why a new workout cannot go on a day that already has one.
    static func conflictMessage(existingName: String, date: Date) -> String {
        "\"\(existingName)\" is already planned for \(date.formatted(date: .abbreviated, time: .omitted)). Choose a different date."
    }

    /// The sum of reps times weight over every planned set.
    static func targetVolume(_ drafts: [CutPlannedExerciseDraft]) -> Double {
        drafts.reduce(0.0) { sum, draft in
            sum + draft.sets.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
        }
    }

    // MARK: Conversion

    static func drafts(from exercises: [PlannedExercise]) -> [CutPlannedExerciseDraft] {
        exercises.map { exercise in
            CutPlannedExerciseDraft(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                exerciseName: exercise.exerciseName,
                sets: exercise.ghostSets.map { CutPlannedSetDraft(id: $0.id, reps: $0.reps, weightKg: $0.weight, tag: $0.tag) },
                progression: exercise.progressionStrategy,
                notes: exercise.notes,
                order: exercise.order
            )
        }
        .sorted { $0.order < $1.order }
    }

    static func ghostSets(_ sets: [CutPlannedSetDraft]) -> [GhostSet] {
        sets.map { set in
            var ghost = GhostSet(reps: set.reps, weight: set.weightKg, tag: SetTag(rawValue: set.tag) ?? .working)
            ghost.id = set.id
            ghost.tag = set.tag
            return ghost
        }
    }

    static func plannedExercises(_ drafts: [CutPlannedExerciseDraft]) -> [PlannedExercise] {
        drafts.map { draft in
            PlannedExercise(
                id: draft.id,
                exerciseID: draft.exerciseID,
                exerciseName: draft.exerciseName,
                ghostSets: ghostSets(draft.sets),
                progressionStrategy: draft.progression,
                order: draft.order,
                notes: draft.notes
            )
        }
    }
}
