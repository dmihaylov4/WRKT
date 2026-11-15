//
//  CutWorkoutEditorHost.swift
//  WRKT
//
//  CompletedWorkoutEditor's and RetrospectiveWorkoutBuilder's state and flows behind the Cut
//  editors: the same exercise picker, set editor sheet, suggested starting weight, store saves
//  and haptics. The rules (Save, the saved workout) come from CutWorkoutEditorLogic.
//

import SwiftUI

// MARK: - Edit workout

struct CutWorkoutEditorHost: View {
    let workout: CompletedWorkout
    let isNewWorkout: Bool

    @Environment(\.cutSheetDepth) private var sheetDepth
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var repo: ExerciseRepository
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var name: String
    @State private var entries: [WorkoutEntry]
    @State private var showingExercisePicker = false
    @State private var editingEntryID: CutEditingEntry?

    init(workout: CompletedWorkout, isNewWorkout: Bool) {
        self.workout = workout
        self.isNewWorkout = isNewWorkout
        _name = State(initialValue: workout.workoutName ?? "")
        _entries = State(initialValue: workout.entries)
    }

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        NavigationStack {
            CutWorkoutEditorView(
                model: CutWorkoutEditorLogic.editor(workout, name: name, entries: entries, unit: unit),
                name: $name,
                actions: CutWorkoutEditorActions(
                    cancel: { dismiss() },
                    save: save,
                    addExercise: { showingExercisePicker = true },
                    editExercise: { editingEntryID = CutEditingEntry(id: $0) },
                    deleteExercises: { entries.remove(atOffsets: $0) }
                )
            )
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(onSelect: addExercise)
                .environmentObject(repo)
                .environmentObject(FavoritesStore())
                .environment(\.cutSheetDepth, sheetDepth + 1)
        }
        .sheet(item: $editingEntryID) { editing in
            if let binding = entryBinding(editing.id, in: $entries) {
                RetrospectiveSetEditor(entry: binding)
                    .environmentObject(store)
                    .environment(\.cutSheetDepth, sheetDepth + 1)
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        entries.append(CutWorkoutEditorLogic.newEntry(exercise, suggestedWeightKg: store.lastWorkingSet(exercise: exercise)?.weightKg))
        Haptics.light()
    }

    private func save() {
        let updated = CutWorkoutEditorLogic.edited(workout, name: name, entries: entries)
        if isNewWorkout {
            store.addWorkout(updated)
        } else {
            store.updateWorkout(updated)
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Log workout

struct CutWorkoutLogHost: View {
    let date: Date

    @Environment(\.cutSheetDepth) private var sheetDepth
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var repo: ExerciseRepository
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var name = ""
    @State private var entries: [WorkoutEntry] = []
    @State private var start: Date
    @State private var end: Date
    @State private var showingExercisePicker = false
    @State private var editingEntryID: CutEditingEntry?

    init(date: Date) {
        self.date = date
        let times = CutWorkoutEditorLogic.defaultTimes(for: date)
        _start = State(initialValue: times.start)
        _end = State(initialValue: times.end)
    }

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        NavigationStack {
            CutWorkoutLogView(
                model: CutWorkoutEditorLogic.log(date: date, start: start, end: end, entries: entries, unit: unit),
                name: $name,
                start: $start,
                end: $end,
                actions: CutWorkoutEditorActions(
                    cancel: { dismiss() },
                    save: save,
                    addExercise: {
                        showingExercisePicker = true
                        Haptics.light()
                    },
                    editExercise: {
                        editingEntryID = CutEditingEntry(id: $0)
                        Haptics.light()
                    }
                )
            )
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(onSelect: addExercise)
                .environmentObject(repo)
                .environmentObject(FavoritesStore())
                .environment(\.cutSheetDepth, sheetDepth + 1)
        }
        .sheet(item: $editingEntryID) { editing in
            if let binding = entryBinding(editing.id, in: $entries) {
                RetrospectiveSetEditor(entry: binding)
                    .environmentObject(store)
                    .environment(\.cutSheetDepth, sheetDepth + 1)
            }
        }
    }

    private func addExercise(_ exercise: Exercise) {
        entries.append(CutWorkoutEditorLogic.newEntry(exercise, suggestedWeightKg: store.lastWorkingSet(exercise: exercise)?.weightKg))
        Haptics.light()
    }

    private func save() {
        guard CutWorkoutEditorLogic.canSaveLog(entries: entries, start: start, end: end) else { return }
        store.addWorkout(CutWorkoutEditorLogic.logged(name: name, entries: entries, start: start, end: end))
        Haptics.success()
        dismiss()
    }
}

// MARK: - Shared

/// The entry whose sets are open in the set editor.
struct CutEditingEntry: Identifiable, Equatable {
    let id: UUID
}

/// A binding to one entry by ID; nil once the entry is gone instead of crashing.
private func entryBinding(_ id: UUID, in entries: Binding<[WorkoutEntry]>) -> Binding<WorkoutEntry>? {
    guard let index = entries.wrappedValue.firstIndex(where: { $0.id == id }) else { return nil }
    return entries[index]
}
