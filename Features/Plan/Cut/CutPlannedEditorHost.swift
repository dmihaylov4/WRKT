//
//  CutPlannedEditorHost.swift
//  WRKT
//
//  PlannedWorkoutEditor's state and flows behind the Cut editor: the same exercise picker,
//  suggested starting weight, exercise sheet, move dialog for plan workouts, same-day conflict
//  check, SwiftData saves through the planner store, delete confirmation, notifications and
//  haptics. The rules come from CutPlannedEditorLogic.
//

import SwiftUI
import SwiftData

struct CutPlannedEditorHost: View {
    let date: Date
    let existingWorkout: PlannedWorkout?

    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: ExerciseRepository
    @EnvironmentObject private var store: WorkoutStoreV2
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var scheduledDate: Date
    @State private var workoutName: String
    @State private var drafts: [CutPlannedExerciseDraft]
    @State private var showingExercisePicker = false
    @State private var editingExercise: CutEditingEntry?
    @State private var showingDeleteConfirmation = false
    @State private var showingRescheduleOptions = false
    @State private var schedulingErrorMessage: String?

    init(date: Date, existingWorkout: PlannedWorkout?) {
        self.date = date
        self.existingWorkout = existingWorkout
        let calendar = Calendar.current
        _scheduledDate = State(initialValue: calendar.startOfDay(for: existingWorkout?.scheduledDate ?? date))
        _workoutName = State(initialValue: existingWorkout?.splitDayName ?? "")
        _drafts = State(initialValue: existingWorkout.map { CutPlannedEditorLogic.drafts(from: $0.exercises) } ?? [])
    }

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var originalDate: Date { existingWorkout?.scheduledDate ?? date }

    private var model: CutPlannedEditorModel {
        var plateaus: [String: Int] = [:]
        for draft in drafts where plateaus[draft.exerciseID] == nil {
            plateaus[draft.exerciseID] = store.consecutiveSessionsAtSameWeight(for: draft.exerciseID)
        }
        return CutPlannedEditorLogic.model(isNew: existingWorkout == nil, drafts: drafts, plateaus: plateaus, unit: unit)
    }

    var body: some View {
        NavigationStack {
            CutPlannedEditorView(
                model: model,
                name: $workoutName,
                date: $scheduledDate,
                actions: CutPlannedEditorActions(
                    cancel: { dismiss() },
                    save: handleSaveTapped,
                    addExercise: { showingExercisePicker = true },
                    editExercise: { editingExercise = CutEditingEntry(id: $0) },
                    deleteExercises: { offsets in
                        drafts = CutPlannedEditorLogic.removing(atOffsets: offsets, from: drafts)
                        Haptics.light()
                    },
                    deleteWorkout: { showingDeleteConfirmation = true }
                )
            )
            .confirmationDialog("Move Planned Workout", isPresented: $showingRescheduleOptions, titleVisibility: .visible) {
                Button("Move This Workout Only") { save(shiftUpcoming: false) }
                Button("Shift All Upcoming Planned Workouts") { save(shiftUpcoming: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This workout belongs to an active plan. Choose whether to move just this workout or shift the rest of the upcoming plan by the same amount.")
            }
            .alert("Unable to Save Workout", isPresented: Binding(
                get: { schedulingErrorMessage != nil },
                set: { if !$0 { schedulingErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { schedulingErrorMessage = nil }
            } message: {
                Text(schedulingErrorMessage ?? "")
            }
            .alert("Delete Workout?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: deletePlannedWorkout)
            } message: {
                Text("This will permanently delete this planned workout.")
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(onSelect: addExercise)
                .environmentObject(repo)
                .environmentObject(FavoritesStore())
        }
        .sheet(item: $editingExercise) { editing in
            if let index = drafts.firstIndex(where: { $0.id == editing.id }) {
                NavigationStack {
                    CutPlannedSetsView(
                        model: CutPlannedEditorLogic.setsModel(drafts[index], unit: unit),
                        notes: Binding(
                            get: { drafts.indices.contains(index) ? drafts[index].notes ?? "" : "" },
                            set: { if drafts.indices.contains(index) { drafts[index].notes = CutPlannedEditorLogic.savedNotes($0) } }
                        ),
                        apply: { edit in
                            guard drafts.indices.contains(index) else { return }
                            drafts[index] = CutPlannedEditorLogic.apply(edit, to: drafts[index], unit: unit)
                        },
                        done: { editingExercise = nil }
                    )
                }
            }
        }
    }

    // MARK: Exercises

    private func addExercise(_ exercise: Exercise) {
        drafts.append(CutPlannedEditorLogic.newDraft(exerciseID: exercise.id, name: exercise.name,
                                                     suggestedWeightKg: store.lastWorkingSet(exercise: exercise)?.weightKg,
                                                     order: drafts.count))
        Haptics.light()
    }

    // MARK: Save

    private func handleSaveTapped() {
        switch CutPlannedEditorLogic.saveStep(hasSplit: existingWorkout?.splitID != nil, original: originalDate,
                                              chosen: scheduledDate, calendar: .current) {
        case .askHowToMove: showingRescheduleOptions = true
        case .save: save(shiftUpcoming: false)
        }
    }

    /// The legacy save, step for step.
    private func save(shiftUpcoming: Bool) {
        let calendar = Calendar.current
        let chosen = calendar.startOfDay(for: scheduledDate)
        let original = calendar.startOfDay(for: originalDate)
        let exercises = CutPlannedEditorLogic.plannedExercises(drafts)
        let name = CutPlannedEditorLogic.savedName(workoutName)

        if let existing = existingWorkout {
            existing.splitDayName = name
            existing.exercises = exercises
            existing.targetVolume = CutPlannedEditorLogic.targetVolume(drafts)
            do {
                if CutPlannedEditorLogic.isDateChanged(original: original, chosen: chosen, calendar: calendar) {
                    if shiftUpcoming, let splitID = existing.splitID {
                        try dependencies.plannerStore.shiftUpcomingPlannedWorkouts(
                            for: splitID, startingAt: original,
                            by: CutPlannedEditorLogic.dayOffset(original: original, chosen: chosen, calendar: calendar))
                    } else {
                        try dependencies.plannerStore.reschedulePlannedWorkout(existing, to: chosen)
                    }
                } else {
                    try modelContext.save()
                }
            } catch {
                schedulingErrorMessage = error.localizedDescription
                return
            }
        } else {
            do {
                let predicate = #Predicate<PlannedWorkout> { $0.scheduledDate == chosen }
                if let conflict = try modelContext.fetch(FetchDescriptor(predicate: predicate)).first {
                    schedulingErrorMessage = CutPlannedEditorLogic.conflictMessage(existingName: conflict.splitDayName, date: chosen)
                    return
                }
            } catch {
                schedulingErrorMessage = error.localizedDescription
                return
            }
            modelContext.insert(PlannedWorkout(scheduledDate: chosen, splitDayName: name, exercises: exercises))
            do {
                try modelContext.save()
            } catch {
                schedulingErrorMessage = error.localizedDescription
                return
            }
        }

        NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
        Haptics.success()
        dismiss()
    }

    private func deletePlannedWorkout() {
        guard let existing = existingWorkout else { return }
        modelContext.delete(existing)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
            Haptics.success()
            dismiss()
        } catch {
            AppLogger.error("Failed to delete planned workout: \(error)", category: AppLogger.app)
        }
    }
}
