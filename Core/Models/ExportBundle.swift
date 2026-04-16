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
    static let currentVersion = 1

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
            displayOrder: plate.displayOrder
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
            rackPosition: rackPosition
        )
        plate.displayOrder = displayOrder
        return plate
    }
}
