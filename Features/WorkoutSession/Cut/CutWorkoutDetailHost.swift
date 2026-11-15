//
//  CutWorkoutDetailHost.swift
//  WRKT
//
//  WorkoutDetailView's and HealthKitStrengthDetailView's data and flows behind the Cut records:
//  the same store reads, editor sheet, delete confirmation, exercise stats sheet, live session
//  sheet and tab dismissals. The menu sits beside the title rather than in the navigation bar,
//  so it also works when the detail is presented as a sheet without a navigation bar.
//

import SwiftUI

// MARK: - Workout detail

struct CutWorkoutDetailHost: View {
    let workout: CompletedWorkout

    @Environment(\.cutSheetDepth) private var sheetDepth
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var repo: ExerciseRepository
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var inSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showingEditor = false
    @State private var statsTarget: CutExerciseStatsTarget?
    @State private var sessionExercise: Exercise?

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    /// The latest copy from the store, so an edit shows in place.
    private var current: CompletedWorkout {
        store.completedWorkouts.first { $0.id == workout.id } ?? workout
    }

    /// Exercises that open the live session: the workout must be the one still running, and
    /// (the legacy rule) the repository must know the exercise.
    private var sessionExerciseIDs: Set<String> {
        let current = current
        guard CutWorkoutDetailLogic.opensLiveSession(
            workoutDate: current.date,
            workoutExerciseIDs: current.entries.map(\.exerciseID),
            currentStartedAt: store.currentWorkout?.startedAt,
            currentExerciseIDs: store.currentWorkout?.entries.map(\.exerciseID) ?? []
        ) else { return [] }
        let known = Set(repo.exercises.map(\.id))
        return Set(current.entries.map(\.exerciseID)).intersection(known)
    }

    private var model: CutWorkoutDetailModel {
        let current = current
        let samples = current.matchedHealthKitHeartRateSamples ?? []
        let calculator = HRZoneCalculator.shared
        let zones = samples.count > 5
            ? CutWorkoutDetailLogic.zoneSummaries(
                boundaries: calculator.zoneBoundaries().map { ($0.zone, $0.name, $0.rangeString) },
                durations: calculator.zoneDurations(for: samples))
            : []
        return CutWorkoutDetailLogic.detail(current, zones: zones, zoneMethod: calculator.methodDisplayName,
                                            unit: unit, sessionExerciseIDs: sessionExerciseIDs, now: .now)
    }

    var body: some View {
        let model = model
        CutWorkoutDetailView(model: model, actions: CutWorkoutDetailActions(
            edit: { showingEditor = true },
            delete: {
                Haptics.light()
                showDeleteConfirmation = true
            },
            showStats: { statsTarget = CutExerciseStatsTarget(id: $0.exerciseID, name: $0.name) },
            openSession: { exercise in
                if let found = repo.exercises.first(where: { $0.id == exercise.exerciseID }) {
                    sessionExercise = found
                }
            }
        ), inSheet: inSheet, close: { dismiss() })
        .background(CutPresentationReader { inSheet = $0 })
        .workoutDetailScrollEdge()
        // The hero carries the name; a pushed detail keeps only the back button in the bar.
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            CompletedWorkoutEditor(workout: current, isNewWorkout: false)
                .environmentObject(store)
                .environmentObject(repo)
                .environment(\.cutSheetDepth, sheetDepth + (inSheet ? 1 : 0))
        }
        .sheet(item: $statsTarget) { target in
            NavigationStack {
                CutExerciseStatsLoader(exerciseID: target.id, exerciseName: target.name)
                    .withDependencies()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $sessionExercise) { exercise in
            NavigationStack {
                ExerciseSessionView(
                    exercise: exercise,
                    initialEntryID: store.existingEntry(for: exercise.id)?.id
                )
            }
            .environment(\.cutSheetDepth, sheetDepth + (inSheet ? 1 : 0))
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            CutSheetConfirm("Delete workout?", message: "Your logged workout will be deleted. You can undo this.",
                primaryTitle: "Delete workout", cancelTitle: "Keep workout", confirm: {
                    showDeleteConfirmation = false
                    store.deleteWorkout(current)
                    dismiss()
                }, cancel: { showDeleteConfirmation = false })
                .environment(\.cutSheetDepth, sheetDepth + (inSheet ? 1 : 0))
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { _ in dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: .calendarTabReselected)) { _ in dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: .cardioTabReselected)) { _ in dismiss() }
    }
}

// MARK: - Apple Health strength

struct CutHealthStrengthHost: View {
    let run: Run

    @Environment(\.cutSheetDepth) private var sheetDepth
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var repo: ExerciseRepository

    @State private var showingEditor = false
    @State private var showDeleteConfirmation = false

    /// The detailed workout made from this Health workout, if details were added.
    private var existingWorkout: CompletedWorkout? {
        guard let healthKitUUID = run.healthKitUUID else { return nil }
        return store.completedWorkouts.first { $0.matchedHealthKitUUID == healthKitUUID }
    }

    var body: some View {
        let existing = existingWorkout
        let model = CutWorkoutDetailLogic.healthStrength(run, existing: existing, now: .now)
        CutHealthStrengthView(model: model, actions: CutHealthStrengthActions(
            edit: { showingEditor = true },
            delete: {
                Haptics.light()
                showDeleteConfirmation = true
            }
        ))
        .workoutDetailScrollEdge()
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            if let workout = existingWorkout {
                CompletedWorkoutEditor(workout: workout, isNewWorkout: false)
                    .environmentObject(store)
                    .environmentObject(repo)
            } else {
                CompletedWorkoutEditor(workout: CutWorkoutDetailLogic.workout(from: run), isNewWorkout: true)
                    .environmentObject(store)
                    .environmentObject(repo)
            }
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            CutSheetConfirm("Delete workout?", message: "Your logged workout will be deleted. You can undo this.",
                primaryTitle: "Delete workout", cancelTitle: "Keep workout", confirm: {
                    showDeleteConfirmation = false
                    if let workout = existingWorkout { store.deleteWorkout(workout) } else { store.removeRun(withId: run.id) }
                    dismiss()
                }, cancel: { showDeleteConfirmation = false })
                .environment(\.cutSheetDepth, sheetDepth)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { _ in dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: .calendarTabReselected)) { _ in dismiss() }
    }
}

// MARK: - Exercise stats

struct CutExerciseStatsTarget: Identifiable, Equatable {
    /// The exercise ID.
    let id: String
    let name: String
}

/// The legacy stats wrapper: looks up the exercise's tracking mode, then shows its statistics.
private struct CutExerciseStatsLoader: View {
    let exerciseID: String
    let exerciseName: String

    @EnvironmentObject private var repo: ExerciseRepository
    @State private var trackingMode: TrackingMode = .weighted
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading")
                    .tint(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Cut.Colors.background.ignoresSafeArea())
            } else {
                ExerciseStatisticsView(exerciseID: exerciseID, exerciseName: exerciseName, trackingMode: trackingMode)
            }
        }
        .task { await loadTrackingMode() }
    }

    private func loadTrackingMode() async {
        if let exercise = repo.exercise(byID: exerciseID) {
            trackingMode = TrackingMode(rawValue: exercise.trackingMode) ?? .weighted
        } else {
            let all = await repo.getAllExercises()
            if let exercise = all.first(where: { $0.id == exerciseID }) {
                trackingMode = TrackingMode(rawValue: exercise.trackingMode) ?? .weighted
            } else {
                trackingMode = .weighted
            }
        }
        isLoading = false
    }
}
