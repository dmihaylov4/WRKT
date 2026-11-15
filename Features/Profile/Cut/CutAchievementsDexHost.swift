//
//  CutAchievementsDexHost.swift
//  WRKT
//
//  AchievementsDexView's state behind the Cut page: the same AchievementsDexVM (search with its
//  debounce, scope, unlocked-first order) rebuilt from every exercise and the dex stamps on
//  appear and when either changes; a tile opens DexDetailView. CutDexDetailHost is
//  DexDetailView's state: the same store reads, and the same Try a PR and Add to current
//  workout flows (start a workout if needed, add the exercise, open the live tab, close).
//

import SwiftUI
import SwiftData

struct CutAchievementsDexHost: View {
    @EnvironmentObject private var repo: ExerciseRepository
    @Query private var stamps: [DexStamp]
    @StateObject private var vm = AchievementsDexVM()
    @State private var selected: DexItem?

    var body: some View {
        CutAchievementsDexView(
            model: CutAchievementsDexLogic.model(items: vm.filtered, unlocked: vm.unlockedCount,
                                                 total: vm.totalCount, isSearching: vm.isSearching),
            scope: $vm.scope,
            open: { id in selected = vm.filtered.first { $0.id == id } }
        )
        .searchable(text: $vm.search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationDestination(item: $selected) { DexDetailView(item: $0) }
        .navigationDestination(for: DexItem.self) { DexDetailView(item: $0) }
        .task { await rebuild(stamps) }
        .onChange(of: repo.exercises) { _, _ in Task { await rebuild(stamps) } }
        .onChange(of: stamps) { _, newStamps in Task { await rebuild(newStamps) } }
    }

    private func rebuild(_ stamps: [DexStamp]) async {
        // Every exercise for the dex, not the paginated list.
        let all = await repo.getAllExercises()
        vm.rebuild(exercises: all, stamps: stamps)
    }
}

struct CutDexDetailHost: View {
    let item: DexItem

    @EnvironmentObject private var repo: ExerciseRepository
    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @State private var ladder: [(reps: Int, weightKg: Double?)] = []

    private var exercise: Exercise? { repo.exercise(byID: item.id) }

    var body: some View {
        CutDexDetailView(model: CutDexDetailLogic.model(facts), actions: CutDexDetailActions(
            tryPR: tryPR,
            addToWorkout: addToWorkout
        )) {
            if let exercise { ExerciseMusclesSection(exercise: exercise, focus: .full) }
        }
        .task { rebuildLadder() }
        .onChange(of: exercise?.id) { _, _ in rebuildLadder() }
    }

    private var facts: CutDexDetailFacts {
        let ex = exercise
        let attempt = ex.flatMap { store.personalRecordAttempt(for: $0) }
        return CutDexDetailFacts(
            name: item.name,
            unlockedAt: item.unlockedAt,
            bestE1RMKg: ex.flatMap { store.bestE1RM(exercise: $0) },
            lastWorking: ex.flatMap { store.lastWorkingSet(exercise: $0) },
            ladder: ladder,
            attempt: attempt.map { ($0.reps, $0.weightKg) },
            hasExercise: ex != nil,
            unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg
        )
    }

    private func rebuildLadder() {
        guard let ex = exercise else { ladder = []; return }
        ladder = (1...12).map { ($0, store.bestWeightForExactReps(exercise: ex, reps: $0)) }
    }

    private func tryPR() {
        guard let ex = exercise, let next = store.personalRecordAttempt(for: ex) else { return }
        store.startWorkoutIfNeeded()
        let entryID = store.addExerciseToCurrent(ex)
        store.updateEntrySets(entryID: entryID, sets: [
            SetInput(reps: next.reps, weight: next.weightKg, tag: .working, autoWeight: false)
        ])
        NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
        dismiss()
    }

    private func addToWorkout() {
        guard let ex = exercise else { return }
        store.startWorkoutIfNeeded()
        _ = store.addExerciseToCurrent(ex)
        NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
        dismiss()
    }
}
