// Features/Rewards/Models/BarbellModels.swift
import Foundation
import SwiftData

// MARK: - EarnedPlate (@Model)

@Model final class EarnedPlate {
    @Attribute(.unique) var id: String
    var tierID: Int          // 0-6 = earned tiers, 7 = starter plate
    var weightKg: Double
    var engravingText: String
    var earnedAt: Date
    var earnedByEvent: String  // e.g. "first_workout", "pr_a1b2c3d4", "strength_milestone_5", "starter"
    var sourceWorkoutID: String?
    var isRacked: Bool
    var rackPosition: Int?     // 0-3 = slot index; bilateral rendering: one row = both sides of bar
    var displayOrder: Int      // earnedAt unix timestamp for sorting

    init(
        id: String = UUID().uuidString,
        tierID: Int,
        weightKg: Double,
        engravingText: String,
        earnedAt: Date = .now,
        earnedByEvent: String,
        sourceWorkoutID: String? = nil,
        isRacked: Bool = false,
        rackPosition: Int? = nil
    ) {
        self.id = id
        self.tierID = tierID
        self.weightKg = weightKg
        self.engravingText = engravingText
        self.earnedAt = earnedAt
        self.earnedByEvent = earnedByEvent
        self.sourceWorkoutID = sourceWorkoutID
        self.isRacked = isRacked
        self.rackPosition = rackPosition
        self.displayOrder = Int(earnedAt.timeIntervalSince1970)
    }
}

// MARK: - BarbellConfig (@Model, singleton id = "global")

@Model final class BarbellConfig {
    @Attribute(.unique) var id: String
    var selectedBarSkinID: Int
    var totalStrengthWorkouts: Int
    var lastStreakCheckDate: Date?
    var needsSupabaseSync: Bool
    var backfillCompletedV1: Bool

    init() {
        self.id = "global"
        self.selectedBarSkinID = 0
        self.totalStrengthWorkouts = 0
        self.lastStreakCheckDate = nil
        self.needsSupabaseSync = false
        self.backfillCompletedV1 = false
    }
}

// MARK: - EarnedPlateInfo (plain struct, cross-thread DTO)

public struct EarnedPlateInfo: Equatable, Sendable {
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedByEvent: String
}

// MARK: - Starter Plate Spec (tierID = 7)
// Not in the earn table. Awarded at account creation.
// Visual: small radius, matte rubber, bright solid color. No weight stamp.

extension EarnedPlate {
    static func makeStarter(position: Int) -> EarnedPlate {
        EarnedPlate(
            tierID: 7,
            weightKg: 0,
            engravingText: "",
            earnedByEvent: "starter",
            isRacked: true,
            rackPosition: position
        )
    }
}
