//
//  CutExerciseStatsHost.swift
//  WRKT
//
//  ExerciseStatisticsView's work behind the Cut screen: the same ExerciseStatsAggregator call on
//  the same completed workouts, run once off the main thread as the legacy view does. The Cut
//  model (records, all chart series, sessions) is built in that same background pass, so the
//  segment switch only re-reads a series. CutPresentationReader tells a pushed screen from a
//  presented sheet; the exercise details Stats tab embeds it without chrome.
//

import SwiftUI

struct CutExerciseStatsHost: View {
    let exerciseID: String
    let exerciseName: String
    let trackingMode: TrackingMode
    let isEmbedded: Bool

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cutSheetDepth) private var sheetDepth
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var stats: ExerciseStatistics?
    @State private var model: CutExerciseStatsModel?
    @State private var inSheet = false
    @State private var logEntry: LogTarget?

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var chrome: CutExerciseStatsChrome {
        if isEmbedded { return .embedded }
        return inSheet ? .presented : .pushed
    }

    var body: some View {
        CutExerciseStatsView(
            title: exerciseName,
            model: model,
            chrome: chrome,
            actions: CutExerciseStatsActions(
                back: { dismiss() },
                close: { dismiss() },
                openSession: { id in
                    Haptics.light()
                    logEntry = LogTarget(id: id)
                }
            )
        )
        .background(CutPresentationReader { inSheet = $0 })
        .toolbar(.hidden, for: .navigationBar)
        .task(id: weightUnitRaw) { await load() }
        .sheet(item: $logEntry) { target in
            if let stats, let entry = stats.history.allWorkouts.first(where: { $0.id == target.id }) {
                CutSessionLogView(
                    model: CutSessionLogLogic.log(entry, exerciseName: exerciseName, trackingMode: trackingMode,
                                                     records: model?.records ?? [], unit: unit, now: .now),
                    close: { logEntry = nil }
                )
                // An embedded host already sits inside its sheet's depth; a presented one adds itself.
                .environment(\.cutSheetDepth, sheetDepth + (chrome == .presented ? 1 : 0))
            }
        }
    }

    /// The legacy load: the aggregator over the store's completed workouts on a detached task.
    /// The statistics are computed once; a unit change only rebuilds the model from them.
    private func load() async {
        let unit = unit
        let existing = stats
        let workouts = existing == nil ? store.completedWorkouts : []
        let exerciseID = exerciseID
        let exerciseName = exerciseName
        let trackingMode = trackingMode
        let aggregator = ExerciseStatsAggregator()
        let result = await Task.detached(priority: .userInitiated) { () -> (ExerciseStatistics, CutExerciseStatsModel) in
            let computed = existing ?? aggregator.computeStatistics(
                exerciseID: exerciseID, exerciseName: exerciseName, trackingMode: trackingMode, from: workouts
            )
            return (computed, CutExerciseStatsLogic.model(computed, unit: unit, now: .now))
        }.value
        stats = result.0
        model = result.1
    }

    private struct LogTarget: Identifiable {
        let id: UUID
    }
}
