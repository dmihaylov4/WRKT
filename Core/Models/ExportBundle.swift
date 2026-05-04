//
//  ExportBundle.swift
//  WRKT
//
//  Versioned Codable envelope for data export/import.
//  Excluded: cardio runs (HealthKit), BarbellConfig (derived/internal state).
//

import Foundation

// MARK: - Envelope

struct ExportBundle: Codable {
    static let currentVersion: Int = 1

    let version: Int
    let appVersion: String
    let exportedAt: Date
    let completedWorkouts: [CompletedWorkout]
    let earnedPlates: [EarnedPlateExport]
}

// MARK: - EarnedPlate mirror (EarnedPlate is @Model, not Codable)

struct EarnedPlateExport: Codable {
    let id: String
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedAt: Date
    let earnedByEvent: String
    let sourceWorkoutID: String?
    let isRacked: Bool
    let rackPosition: Int?
    let displayOrder: Int
    var liftTypeID: String? = nil
    var currentTierRaw: String? = nil
    var workoutsUsedCount: Int? = nil
    var prCount: Int? = nil
    var chalkUseCount: Int? = nil
    var gripWearCount: Int? = nil
    var pressUseCount: Int? = nil
    var firstEarnedAt: Date? = nil
    var lastUsedAt: Date? = nil
}

extension EarnedPlateExport {
    init(_ plate: EarnedPlate) {
        self.init(
            id: plate.id,
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            earnedAt: plate.earnedAt,
            earnedByEvent: plate.earnedByEvent,
            sourceWorkoutID: plate.sourceWorkoutID,
            isRacked: plate.isRacked,
            rackPosition: plate.rackPosition,
            displayOrder: plate.displayOrder,
            liftTypeID: plate.liftTypeID,
            currentTierRaw: plate.currentTierRaw,
            workoutsUsedCount: plate.workoutsUsedCount,
            prCount: plate.prCount,
            chalkUseCount: plate.chalkUseCount,
            gripWearCount: plate.gripWearCount,
            pressUseCount: plate.pressUseCount,
            firstEarnedAt: plate.effectiveFirstEarnedAt,
            lastUsedAt: plate.lastUsedAt
        )
    }

    func toModel() -> EarnedPlate {
        let plate = EarnedPlate(
            id: id,
            tierID: tierID,
            weightKg: weightKg,
            engravingText: engravingText,
            earnedAt: earnedAt,
            earnedByEvent: earnedByEvent,
            sourceWorkoutID: sourceWorkoutID,
            isRacked: isRacked,
            rackPosition: rackPosition,
            liftTypeID: liftTypeID,
            currentTier: BarbellPlateProgressionTier(rawValue: currentTierRaw ?? "") ?? .iron,
            workoutsUsedCount: workoutsUsedCount ?? 0,
            prCount: prCount ?? 0,
            chalkUseCount: chalkUseCount ?? 0,
            gripWearCount: gripWearCount ?? 0,
            pressUseCount: pressUseCount ?? 0,
            firstEarnedAt: firstEarnedAt ?? earnedAt,
            lastUsedAt: lastUsedAt
        )
        plate.displayOrder = displayOrder != 0 ? displayOrder : Int(earnedAt.timeIntervalSince1970)
        return plate
    }
}
