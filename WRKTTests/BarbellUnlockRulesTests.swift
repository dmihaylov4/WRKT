// WRKTTests/BarbellUnlockRulesTests.swift
import Testing
@testable import WRKT

struct BarbellModelsTests {
    @Test func earnedPlateInfoEquality() {
        let a = EarnedPlateInfo(tierID: 0, weightKg: 2.5, engravingText: "First Lift", earnedByEvent: "first_workout")
        let b = EarnedPlateInfo(tierID: 0, weightKg: 2.5, engravingText: "First Lift", earnedByEvent: "first_workout")
        #expect(a == b)
    }
}
