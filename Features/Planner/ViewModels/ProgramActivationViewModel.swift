//
//  ProgramActivationViewModel.swift
//  WRKT
//
//  Holds customization state for activating a library program.
//

import Foundation
import Observation

@Observable
@MainActor
final class ProgramActivationViewModel {
    private let plannerStore: PlannerStoreInterface

    var startDate: Date
    var restDayOverrides: [UUID: Bool]
    var startingWeights: [UUID: Double]
    var isSaving = false
    var errorMessage: String?

    init(
        split: WorkoutSplit,
        plannerStore: PlannerStoreInterface
    ) {
        self.plannerStore = plannerStore
        self.startDate = Calendar.current.startOfDay(for: .now)
        self.restDayOverrides = Dictionary(uniqueKeysWithValues: split.planBlocks.map { ($0.id, $0.isRestDay) })
        self.startingWeights = Dictionary(
            uniqueKeysWithValues: split.planBlocks
                .flatMap(\.exercises)
                .compactMap { exercise in
                    guard let weight = exercise.startingWeight else { return nil }
                    return (exercise.id, weight)
                }
        )
    }

    func activate(split: WorkoutSplit) -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try plannerStore.activate(
                split,
                customization: ActivationCustomization(
                    startDate: startDate,
                    restDayOverrides: restDayOverrides,
                    startingWeights: startingWeights
                )
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
