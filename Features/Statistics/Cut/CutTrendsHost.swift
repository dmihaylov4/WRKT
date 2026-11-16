//
//  CutTrendsHost.swift
//  WRKT
//
//  Feeds CutTrendsView from the same 12 week SwiftData queries as the legacy Training Trends
//  section (ProfileChartsView): WeeklyTrainingSummary, MovingAverage and ExerciseVolumeSummary.
//  The model is rebuilt only when those rows, the repository or the unit change, never in body.
//  A top lift pushes that exercise's statistics with the tracking mode the legacy list looked up.
//

import SwiftData
import SwiftUI

struct CutTrendsHost: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: ExerciseRepository

    @Query private var weekly: [WeeklyTrainingSummary]
    @Query private var movingAvgs: [MovingAverage]
    @Query private var exVolumes: [ExerciseVolumeSummary]

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var model: CutTrendsModel?
    @State private var lift: CutStatsExerciseTarget?

    init(weeks: Int = 12) {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: .now) ?? .distantPast
        _weekly = Query(filter: #Predicate<WeeklyTrainingSummary> { $0.weekStart >= cutoff },
                        sort: \WeeklyTrainingSummary.weekStart, order: .forward)
        _movingAvgs = Query(filter: #Predicate<MovingAverage> { $0.weekStart >= cutoff },
                            sort: \MovingAverage.weekStart, order: .forward)
        _exVolumes = Query(filter: #Predicate<ExerciseVolumeSummary> { $0.weekStart >= cutoff },
                           sort: \ExerciseVolumeSummary.weekStart, order: .forward)
    }

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        Group {
            if let model {
                CutTrendsView(model: model, actions: CutTrendsActions(
                    back: { dismiss() },
                    openLift: { open($0) }
                ))
            } else {
                DS.Cut.Colors.background.ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: rebuild)
        .onChange(of: weekly) { _, _ in rebuild() }
        .onChange(of: movingAvgs) { _, _ in rebuild() }
        .onChange(of: exVolumes) { _, _ in rebuild() }
        .onChange(of: repo.exercises.count) { _, _ in rebuild() }
        .onChange(of: weightUnitRaw) { _, _ in rebuild() }
        .navigationDestination(item: $lift) { target in
            ExerciseStatisticsView(exerciseID: target.id, exerciseName: target.name, trackingMode: target.trackingMode)
        }
    }

    /// Copies the summary rows into plain values and builds the model. A few dozen rows at most.
    private func rebuild() {
        let volumes = exVolumes.map { CutTrendsFacts.ExerciseVolume(exerciseID: $0.exerciseID, volumeKg: $0.volume) }
        var names: [String: String] = [:]
        for id in Set(volumes.map(\.exerciseID)) {
            if let exercise = repo.exercise(byID: id) { names[id] = exercise.name }
        }
        let facts = CutTrendsFacts(
            weeks: weekly.map {
                CutTrendsFacts.Week(weekStart: $0.weekStart, volumeKg: $0.totalVolume, sessions: $0.sessions,
                                    sets: $0.totalSets, reps: $0.totalReps)
            },
            personalAverageKg: movingAvgs.last?.personalAvg,
            exerciseVolumes: volumes,
            names: names,
            unit: unit
        )
        model = CutTrendsLogic.model(facts, now: .now)
    }

    /// The legacy Top lifts lookup: the repository's tracking mode, weighted when unknown.
    private func open(_ exerciseID: String) {
        Haptics.light()
        if let exercise = repo.exercise(byID: exerciseID) {
            lift = CutStatsExerciseTarget(id: exercise.id, name: exercise.name,
                                          trackingMode: TrackingMode(rawValue: exercise.trackingMode) ?? .weighted)
        } else {
            let name = model?.lifts.first { $0.id == exerciseID }?.name ?? exerciseID
            lift = CutStatsExerciseTarget(id: exerciseID, name: name, trackingMode: .weighted)
        }
    }
}

/// An exercise whose statistics a Cut statistics screen opens.
struct CutStatsExerciseTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let trackingMode: TrackingMode
}
