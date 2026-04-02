// WRKTTests/BarbellUnlockRulesTests.swift
import Testing
import Foundation
@testable import WRKT

struct BarbellModelsTests {
    @Test func earnedPlateInfoEquality() {
        let a = EarnedPlateInfo(tierID: 0, weightKg: 2.5, engravingText: "First Lift", earnedByEvent: "first_workout")
        let b = EarnedPlateInfo(tierID: 0, weightKg: 2.5, engravingText: "First Lift", earnedByEvent: "first_workout")
        #expect(a == b)
    }
}

struct BarbellUnlockRulesTests {

    // Helper: minimal CompletedWorkout with one entry
    private func makeWorkout(prCount: Int = 0) -> CompletedWorkout {
        var w = CompletedWorkout(date: .now, startedAt: .now, entries: [], plannedWorkoutID: nil)
        w.detectedPRCount = prCount
        return w
    }

    private func makeConfig(totalWorkouts: Int, lastStreakCheckDate: Date? = nil) -> BarbellConfig {
        let c = BarbellConfig()
        c.totalStrengthWorkouts = totalWorkouts
        c.lastStreakCheckDate = lastStreakCheckDate
        return c
    }

    @Test func firstWorkoutEarnsRawIron() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 1)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: [])
        #expect(plates.contains { $0.tierID == 0 && $0.engravingText == "First Lift" })
    }

    @Test func milestone5EarnsCastIron() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 5)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: [])
        #expect(plates.contains { $0.tierID == 1 && $0.earnedByEvent == "strength_milestone_5" })
    }

    @Test func milestone5NotAwardedTwice() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 5)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: ["strength_milestone_5"])
        #expect(!plates.contains { $0.earnedByEvent == "strength_milestone_5" })
    }

    @Test func prEarnsCompetitionPlate() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 3)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: [])
        #expect(plates.contains { $0.tierID == 4 })
    }

    @Test func multipleRulesReturnMultiplePlates() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 5)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: [])
        // Both Cast Iron (milestone 5) and Competition (PR) should fire
        #expect(plates.count >= 2)
    }

    @Test func platesOrderedByRarityDescending() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 5)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: [])
        // Competition (rare, tierID 4) should come before Cast Iron (common, tierID 1)
        let ids = plates.map(\.tierID)
        let competitionIdx = ids.firstIndex(of: 4)!
        let castIronIdx = ids.firstIndex(of: 1)!
        #expect(competitionIdx < castIronIdx)
    }

    @Test func earlyRawIronEvery3Workouts() {
        // Workout 3: totalWorkouts = 3, 3 % 3 == 0, existing Raw Iron count < 4
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 3)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: ["first_workout"])
        #expect(plates.contains { $0.tierID == 0 })
    }

    @Test func earlyRawIronCappedAt4() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 12)
        // Already have 4 raw iron plates
        let existing = ["first_workout", "raw_iron_3", "raw_iron_6", "raw_iron_9"]
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: existing)
        #expect(!plates.contains { $0.tierID == 0 })
    }

    @Test func cardioWorkoutEarnsNoPlates() {
        // Verify CompletedWorkout.isCardioWorkout classification works correctly.
        // The isCardioWorkout guard lives in processInBackground (not in evaluate itself).
        // This test confirms the guard logic by checking isCardioWorkout on the workout type.
        let strengthWorkout = makeWorkout(prCount: 1)
        #expect(!strengthWorkout.isCardioWorkout)

        var cardioWorkout = makeWorkout()
        cardioWorkout.cardioWorkoutType = "Running"
        cardioWorkout.matchedHealthKitUUID = UUID()
        // entries is empty, matchedHealthKitUUID is set: isCardioWorkout returns true
        #expect(cardioWorkout.isCardioWorkout)
    }
}
