//
//  CutBalanceHost.swift
//  WRKT
//
//  Feeds CutBalanceView from the same SwiftData queries as the legacy Training Balance section:
//  PushPullBalance and MovementPatternBalance over 12 weeks (the latest row of each) and every
//  MuscleGroupFrequency row. The model is rebuilt only when those rows or the unit change.
//

import SwiftData
import SwiftUI

struct CutBalanceHost: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var pushPull: [PushPullBalance]
    @Query private var movementPatterns: [MovementPatternBalance]
    @Query(sort: \MuscleGroupFrequency.lastTrained, order: .reverse) private var muscles: [MuscleGroupFrequency]

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var model: CutBalanceModel?

    init(weeks: Int = 12) {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: .now) ?? .distantPast
        _pushPull = Query(filter: #Predicate<PushPullBalance> { $0.weekStart >= cutoff },
                          sort: \PushPullBalance.weekStart, order: .forward)
        _movementPatterns = Query(filter: #Predicate<MovementPatternBalance> { $0.weekStart >= cutoff },
                                  sort: \MovementPatternBalance.weekStart, order: .forward)
    }

    var body: some View {
        Group {
            if let model {
                CutBalanceView(model: model, back: { dismiss() })
            } else {
                DS.Cut.Colors.background.ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: rebuild)
        .onChange(of: pushPull) { _, _ in rebuild() }
        .onChange(of: movementPatterns) { _, _ in rebuild() }
        .onChange(of: muscles) { _, _ in rebuild() }
        .onChange(of: weightUnitRaw) { _, _ in rebuild() }
    }

    private func rebuild() {
        let facts = CutBalanceFacts(
            pushPull: pushPull.last.map {
                CutBalanceFacts.PushPull(push: $0.pushVolume, pull: $0.pullVolume,
                                         horizontalPush: $0.horizontalPushVolume, verticalPush: $0.verticalPushVolume,
                                         horizontalPull: $0.horizontalPullVolume, verticalPull: $0.verticalPullVolume,
                                         ratio: $0.ratio)
            },
            patterns: movementPatterns.last.map { CutBalanceFacts.Patterns(squat: $0.squatVolume, hinge: $0.hingeVolume) },
            muscles: muscles.map { CutBalanceFacts.Muscle(name: $0.muscleGroup, lastTrained: $0.lastTrained) },
            unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg
        )
        model = CutBalanceLogic.model(facts, now: .now)
    }
}
