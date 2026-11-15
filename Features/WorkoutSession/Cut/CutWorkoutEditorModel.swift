//
//  CutWorkoutEditorModel.swift
//  WRKT
//
//  The plain values and rules behind the Cut workout editors: editing a completed workout
//  (CompletedWorkoutEditor) and logging a past one (RetrospectiveWorkoutBuilder). Rows, the
//  Save rules and the workouts a save produces all live here, so they are tested without views.
//

import Foundation

/// One exercise in an editor: its name and the first sets in short.
struct CutWorkoutEditorRow: Equatable, Identifiable {
    var id: UUID
    var name: String
    /// "5×100kg, 5×100kg, 5×100kg, +1"
    var preview: String
}

struct CutWorkoutEditorModel: Equatable {
    /// "Friday 13 Nov, 18:42"
    var dateLine: String
    var isSyncedWithWatch: Bool
    var rows: [CutWorkoutEditorRow]
    var canSave: Bool
}

struct CutWorkoutLogModel: Equatable {
    /// The day being logged: "Sat 17 Oct"
    var dayTitle: String
    var rows: [CutWorkoutEditorRow]
    var canSave: Bool
    /// Why Save is off when the times are the problem.
    var timeIssue: String?
}

enum CutWorkoutEditorLogic {
    static let namePlaceholder = "e.g. Upper Body, Leg Day"
    static let nameHint = "If left blank, the name comes from the exercises."

    // MARK: Rows

    static func rows(_ entries: [WorkoutEntry], unit: WeightUnit) -> [CutWorkoutEditorRow] {
        entries.map { CutWorkoutEditorRow(id: $0.id, name: $0.exerciseName, preview: preview($0.sets, unit: unit)) }
    }

    /// The first three sets in short, then how many more ("+2"). "No sets" when empty.
    static func preview(_ sets: [SetInput], unit: WeightUnit) -> String {
        guard !sets.isEmpty else { return "No sets" }
        var parts = sets.prefix(3).map { compact($0, unit: unit) }
        if sets.count > 3 { parts.append("+\(sets.count - 3)") }
        return parts.joined(separator: ", ")
    }

    /// "5×100kg" with a weight, "12 reps" without one, a time or a distance by tracking mode.
    static func compact(_ set: SetInput, unit: WeightUnit) -> String {
        switch set.trackingMode {
        case .timed: return CutWorkoutDetailLogic.duration(set.durationSeconds)
        case .distance: return CutWorkoutDetailLogic.setValue(set, unit: unit)
        case .weighted, .bodyweight:
            if set.trackingMode == .bodyweight || set.weight <= 0 {
                return set.reps == 1 ? "1 rep" : "\(set.reps) reps"
            }
            return unit.formatSetCompact(reps: set.reps, weightKg: set.weight)
        }
    }

    // MARK: Edit a completed workout

    static func editor(_ workout: CompletedWorkout, name: String, entries: [WorkoutEntry], unit: WeightUnit,
                       now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> CutWorkoutEditorModel {
        CutWorkoutEditorModel(
            dateLine: dateTime(workout.date, now: now, calendar: calendar, locale: locale),
            isSyncedWithWatch: workout.matchedHealthKitUUID != nil,
            rows: rows(entries, unit: unit),
            canSave: hasChanges(workout, name: name, entries: entries)
        )
    }

    /// Save turns on once the name or the exercises differ from what the editor opened with.
    /// Spaces around the name do not count as a change.
    static func hasChanges(_ workout: CompletedWorkout, name: String, entries: [WorkoutEntry]) -> Bool {
        savedName(name) != savedName(workout.workoutName ?? "") || entries != workout.entries
    }

    /// The trimmed name, or nil so the name comes from the exercises.
    static func savedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The workout an edit saves: everything kept, the name and exercises replaced.
    static func edited(_ workout: CompletedWorkout, name: String, entries: [WorkoutEntry]) -> CompletedWorkout {
        var updated = workout
        updated.entries = entries
        updated.workoutName = savedName(name)
        return updated
    }

    /// A new exercise starts with three completed sets of 10 at the last working weight.
    static func newEntry(_ exercise: Exercise, suggestedWeightKg: Double?) -> WorkoutEntry {
        let weight = suggestedWeightKg ?? 0
        return WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles,
            sets: (0..<3).map { _ in SetInput(reps: 10, weight: weight, isCompleted: true) }
        )
    }

    // MARK: Log a past workout

    /// A one-hour workout ending at 20:00 on the chosen day.
    static func defaultTimes(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date
        return (end.addingTimeInterval(-3600), end)
    }

    static func log(date: Date, start: Date, end: Date, entries: [WorkoutEntry], unit: WeightUnit,
                    now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> CutWorkoutLogModel {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return CutWorkoutLogModel(
            dayTitle: formatter(sameYear ? "EEE d MMM" : "d MMM yyyy", calendar: calendar, locale: locale).string(from: date),
            rows: rows(entries, unit: unit),
            canSave: canSaveLog(entries: entries, start: start, end: end),
            timeIssue: end <= start ? "Finish after the start to save." : nil
        )
    }

    /// The legacy rule: at least one exercise and a finish after the start.
    static func canSaveLog(entries: [WorkoutEntry], start: Date, end: Date) -> Bool {
        !entries.isEmpty && end > start
    }

    /// The workout a log saves: ending at the finish, every set marked done.
    static func logged(id: UUID = UUID(), name: String, entries: [WorkoutEntry], start: Date, end: Date) -> CompletedWorkout {
        CompletedWorkout(
            id: id,
            date: end,
            startedAt: start,
            entries: entries.map { entry in
                var updated = entry
                updated.sets = entry.sets.map { set in
                    var done = set
                    done.isCompleted = true
                    return done
                }
                return updated
            },
            plannedWorkoutID: nil,
            workoutName: savedName(name)
        )
    }

    // MARK: Formats

    /// "Friday 13 Nov, 18:42", with the year when it is not this year.
    static func dateTime(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "EEEE d MMM, HH:mm" : "EEEE d MMM yyyy, HH:mm", calendar: calendar, locale: locale)
            .string(from: date)
    }

    private static func formatter(_ format: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        CutWorkoutDetailLogic.formatter(format, locale: locale, calendar: calendar)
    }
}
