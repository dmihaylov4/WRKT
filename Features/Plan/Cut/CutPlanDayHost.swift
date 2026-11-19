//
//  CutPlanDayHost.swift
//  WRKT
//
//  Feeds CutPlanDayView from what the legacy DayDetail reads: the store's workouts and runs for
//  the day, and the day's planned workout (fetched on appear, on a date change and whenever
//  planned workouts change). Day actions go back to CutPlanHost through the same selectedAction
//  binding; rows push the same detail views; the planned card's Start (with its different-day
//  alert) and Delete (with its confirmation) behave as before.
//

import SwiftUI
import SwiftData

struct CutPlanDayHost: View {
    let date: Date
    @Binding var selectedAction: DayActionCard.DayAction?

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context

    @State private var plannedWorkout: PlannedWorkout?
    @State private var destination: CutPlanWorkoutRef?
    @State private var showDateMismatchAlert = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        CutPlanDayView(model: model, actions: CutPlanDayActions(
            perform: perform,
            open: { destination = $0 },
            openCompletedPlan: { selectedAction = .viewCompletedWorkout($0) },
            planMenu: handleMenu
        ))
        .workoutDetailScrollEdge()
        // The hero carries the date; the bar keeps only the back button.
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $destination) { destinationView($0) }
        .onAppear(perform: loadPlannedWorkout)
        .onChange(of: date) { _, _ in loadPlannedWorkout() }
        .onReceive(NotificationCenter.default.publisher(for: .plannedWorkoutsChanged)) { _ in
            loadPlannedWorkout()
        }
        .alert("Workout Scheduled for Different Day", isPresented: $showDateMismatchAlert) {
            Button("Start Now (Logs Today)", role: .destructive) {
                if let planned = plannedWorkout { selectedAction = .startPlannedWorkout(planned) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workout is scheduled for \(plannedWorkout?.scheduledDate.formatted(date: .abbreviated, time: .omitted) ?? ""). Starting it will log the workout for today instead.")
        }
        .alert("Delete Workout?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: deletePlannedWorkout)
        } message: {
            Text("This will permanently delete this planned workout.")
        }
    }

    // MARK: Model

    private var model: CutPlanDayModel {
        CutPlanDayLogic.model(date: date, input: input, today: .now, calendar: .current)
    }

    /// The legacy DayDetail's reads, as plain values.
    private var input: CutPlanDayInput {
        let workouts = store.workouts(on: date)
        let runs = store.runSummaries(on: date)
        let matched = Set(workouts.compactMap(\.matchedHealthKitUUID))
        let watchStrength = runs.filter { run in
            guard run.countsAsStrengthDay, let uuid = run.healthKitUUID else { return false }
            return !matched.contains(uuid) && !store.ignoredHealthKitUUIDs.contains(uuid)
        }
        return CutPlanDayInput(
            workouts: workouts.map { workout in
                CutPlanDayInput.Workout(
                    id: workout.id,
                    name: workout.workoutName.flatMap { $0.isEmpty ? nil : $0 } ?? MuscleGroupClassifier.classify(workout),
                    ended: workout.date,
                    isHealthMatched: workout.matchedHealthKitUUID != nil,
                    exerciseCount: workout.entries.count,
                    setCount: workout.entries.reduce(0) { $0 + $1.sets.count },
                    repCount: workout.entries.reduce(0) { sum, entry in sum + entry.sets.reduce(0) { $0 + max(0, $1.reps) } }
                )
            },
            watchStrength: watchStrength.map {
                .init(id: $0.id, name: MuscleGroupClassifier.classifyHealthKitStrength($0), ended: $0.date)
            },
            cardio: runs.filter { !$0.countsAsStrengthDay }.map {
                .init(id: $0.id, name: CutPlanLogic.cardioName($0), start: $0.date,
                      distanceKm: max(0, $0.distanceKm), durationSeconds: max(0, $0.durationSec))
            },
            runCount: runs.count,
            planned: plannedWorkout.map { planned in
                CutPlanDayInput.Planned(
                    id: planned.id,
                    name: planned.splitDayName,
                    status: planned.workoutStatus,
                    exercises: planned.exercises.map {
                        .init(name: $0.exerciseName, setCount: $0.ghostSets.count, firstReps: $0.ghostSets.first?.reps ?? 0)
                    },
                    completedWorkoutID: planned.completedWorkoutID,
                    isLogged: store.completedWorkouts.contains { $0.plannedWorkoutID == planned.id }
                )
            }
        )
    }

    // MARK: Actions

    private func perform(_ action: CutPlanDayPanel.Action) {
        switch action {
        case .startWorkout:
            selectedAction = .startWorkout(date)
        case .logWorkout:
            selectedAction = .logWorkout(date)
        case .planWorkout:
            selectedAction = .planWorkout(date)
        case .startPlanned(let id):
            if let planned = plannedWorkout, planned.id == id { selectedAction = .startPlannedWorkout(planned) }
        case .editPlanned(let id):
            if let planned = plannedWorkout, planned.id == id { selectedAction = .editPlannedWorkout(planned) }
        case .viewWorkout(let ref):
            destination = ref
        case .viewDay:
            break
        }
    }

    private func handleMenu(_ item: CutPlanDayModel.PlanMenuItem) {
        guard let planned = plannedWorkout else { return }
        switch item {
        case .startNow:
            // The legacy card asks before starting a session planned for another day.
            if Calendar.current.isDateInToday(planned.scheduledDate) {
                selectedAction = .startPlannedWorkout(planned)
            } else {
                showDateMismatchAlert = true
            }
        case .startAgain:
            selectedAction = .startPlannedWorkout(planned)
        case .delete:
            showDeleteConfirmation = true
        }
    }

    // MARK: Destinations

    @ViewBuilder
    private func destinationView(_ ref: CutPlanWorkoutRef) -> some View {
        switch ref {
        case .app(let id):
            if let workout = store.completedWorkouts.first(where: { $0.id == id }) {
                WorkoutDetailView(workout: workout)
            }
        case .healthKitStrength(let id):
            if let run = store.runSummary(id: id) {
                HealthKitStrengthDetailView(run: run)
            }
        case .cardio(let id):
            if let run = store.runSummary(id: id) {
                CardioDetailView(run: run)
            }
        }
    }

    // MARK: Data

    private func loadPlannedWorkout() {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<PlannedWorkout> { $0.scheduledDate == startOfDay }
        plannedWorkout = try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// The legacy planned card's delete.
    private func deletePlannedWorkout() {
        guard let planned = plannedWorkout else { return }
        context.delete(planned)
        do {
            try context.save()
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
            Haptics.success()
        } catch {
            AppLogger.error("Failed to delete planned workout: \(error)", category: AppLogger.app)
        }
    }
}
