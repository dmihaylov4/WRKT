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

    @Test func barbellConfigResetCoversMutableFields() {
        let config = BarbellConfig()
        config.selectedBarSkinID = 4
        config.selectedBarSkinIDRaw = "gold"
        config.selectedRoomThemeIDRaw = "concrete_room"
        config.selectedRackStyleIDRaw = "brushed_steel"
        config.selectedCollarIDRaw = "signature_collar"
        config.selectedBannerIDRaw = "garage_banner"
        config.showPlateEngravingsRaw = false
        config.roomName = "Old room"
        config.roomMotto = "Lift heavy"
        config.displayLoadoutData = try? JSONEncoder().encode(DisplayLoadout(onBar: ["a"], onWall: ["b"]))
        config.totalStrengthWorkouts = 99
        config.totalFunctionalHKWorkouts = 42
        config.lastStreakCheckDate = Date(timeIntervalSince1970: 1_700_000_000)
        config.needsSupabaseSync = true
        config.backfillCompletedV1 = true

        config.resetMutableFieldsToDefaults()

        #expect(config.mutableSnapshot == BarbellConfig().mutableSnapshot)
    }

    @Test func legacyDefaultBarSkinMigrationWritesRawDefault() {
        let config = BarbellConfig()
        config.selectedBarSkinID = 0
        config.selectedBarSkinIDRaw = nil

        config.migrateLegacyCustomizationFieldsIfNeeded()

        #expect(config.selectedBarSkinIDRaw == BarbellCustomizationDefaults.barSkinID)
    }

    @Test func seasonalBrassAccentUsesGoldBarPreviewSkin() {
        let config = BarbellConfig()
        config.selectedBarSkinIDRaw = "may_2026_brass_accent"

        #expect(config.barSkinIndex == 2)
    }

    @Test func displayLoadoutSanitizationUsesStringPlateIDs() {
        let loadout = DisplayLoadout(
            onBar: ["plate-a", "missing", "plate-a", "plate-b"],
            onWall: ["plate-b", "plate-c", "missing", "plate-c"]
        )

        let sanitized = loadout.sanitized(earnedPlateIDs: ["plate-a", "plate-b", "plate-c"])

        #expect(sanitized.onBar == ["plate-a", "plate-b"])
        #expect(sanitized.onWall == ["plate-c"])
    }

    @Test func suspiciousEmptyRemoteOnlyWhenLocalCollectionExists() {
        #expect(BarbellProgressService.shouldTreatRemoteAsSuspiciousEmpty(remoteCount: 0, localEarnedCount: 1))
        #expect(!BarbellProgressService.shouldTreatRemoteAsSuspiciousEmpty(remoteCount: 0, localEarnedCount: 0))
        #expect(!BarbellProgressService.shouldTreatRemoteAsSuspiciousEmpty(remoteCount: 2, localEarnedCount: 3))
    }

    @Test func monotonicTierNeverDowngradesStoredState() {
        #expect(BarbellProgressService.monotonicTier(stored: 5, recomputed: 3) == 5)
        #expect(BarbellProgressService.monotonicTier(stored: 3, recomputed: 5) == 5)
        #expect(BarbellProgressService.monotonicTier(stored: 4, recomputed: 4) == 4)
    }
}

struct BarbellUnlockRulesTests {

    // Helper: minimal CompletedWorkout with one entry
    private func makeWorkout(prCount: Int = 0) -> CompletedWorkout {
        var w = CompletedWorkout(date: .now, startedAt: .now, entries: [], plannedWorkoutID: nil)
        w.detectedPRCount = prCount
        return w
    }

    private func makeWorkout(
        exerciseID: String,
        exerciseName: String,
        completed: Bool = true
    ) -> CompletedWorkout {
        let entry = WorkoutEntry(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            muscleGroups: [],
            sets: [SetInput(reps: 5, weight: 100, tag: .working, isCompleted: completed)]
        )
        return CompletedWorkout(date: .now, startedAt: .now, entries: [entry], plannedWorkoutID: nil)
    }

    private func makeConfig(totalWorkouts: Int, lastStreakCheckDate: Date? = nil) -> BarbellConfig {
        let c = BarbellConfig()
        c.totalStrengthWorkouts = totalWorkouts
        c.lastStreakCheckDate = lastStreakCheckDate
        return c
    }

    private func makeFunctionalHKConfig(totalWorkouts: Int) -> BarbellConfig {
        let c = BarbellConfig()
        c.totalFunctionalHKWorkouts = totalWorkouts
        return c
    }

    private func evaluateNoBumperDrop(
        workout: CompletedWorkout,
        config: BarbellConfig,
        existingEvents: [String]
    ) -> [EarnedPlateInfo] {
        BarbellUnlockRules.evaluate(
            workout: workout,
            config: config,
            existingEvents: existingEvents,
            bumperVariantRoll: { 0 }
        )
    }

    @Test func firstWorkoutEarnsRawIron() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 1)
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: [])
        #expect(plates.contains { $0.tierID == 0 && $0.engravingText == "First Lift" })
    }

    @Test func milestone5EarnsCastIron() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 5)
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: [])
        #expect(plates.contains { $0.tierID == 1 && $0.earnedByEvent == "strength_milestone_5" })
    }

    @Test func premiumMilestonesEarnNewColorwayPlates() {
        let cases: [(count: Int, tierID: Int, event: String)] = [
            (75, 8, "strength_milestone_75"),
            (100, 9, "strength_milestone_100"),
            (125, 13, "strength_milestone_125"),
            (150, 10, "strength_milestone_150"),
            (200, 11, "strength_milestone_200"),
            (250, 12, "strength_milestone_250")
        ]

        for testCase in cases {
            let workout = makeWorkout()
            let config = makeConfig(totalWorkouts: testCase.count)
            let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: [])

            #expect(plates.contains { $0.tierID == testCase.tierID && $0.earnedByEvent == testCase.event })
        }
    }

    @Test func milestone5NotAwardedTwice() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 5)
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: ["strength_milestone_5"])
        #expect(!plates.contains { $0.earnedByEvent == "strength_milestone_5" })
    }

    @Test func prEarnsCompetitionPlate() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 3)
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: [])
        #expect(plates.contains { $0.tierID == 4 })
        #expect(plates.contains { $0.earnedByEvent == BarbellUnlockRules.prEventKey(for: workout.id) })
    }

    @Test func bumperDropDoesNotReplaceCompetitionPlate() {
        // Competition is a metallic plate — not eligible for bumper color upgrade.
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 3)

        let plates = BarbellUnlockRules.evaluate(
            workout: workout,
            config: config,
            existingEvents: [],
            bumperVariantRoll: { 0.96 }
        )

        #expect(plates.contains { $0.tierID == 4 })
        #expect(!plates.contains { $0.earnedByEvent == BarbellUnlockRules.prEventKey(for: workout.id) && $0.tierID != 4 })
    }

    @Test func bumperDropDoesNotReplaceBrassMilestonePlate() {
        // Brass is a metallic milestone plate — not eligible for bumper color upgrade.
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 25)

        let plates = BarbellUnlockRules.evaluate(
            workout: workout,
            config: config,
            existingEvents: [],
            bumperVariantRoll: { 0.74 }
        )

        #expect(plates.contains { $0.tierID == 3 && $0.earnedByEvent == "strength_milestone_25" })
    }

    @Test func bumperDropUpgradesBlackBumperMilestonePlate() {
        // Black Bumper (tier 2) is bumper-style — eligible for a colored variant upgrade.
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 15)

        let plates = BarbellUnlockRules.evaluate(
            workout: workout,
            config: config,
            existingEvents: [],
            bumperVariantRoll: { 0.75 }  // 0.74-0.78 -> Blue Bumper (15)
        )

        #expect(plates.contains {
            $0.tierID == 15 &&
            $0.earnedByEvent == "strength_milestone_15" &&
            $0.engravingText == "15 Workouts"
        })
        #expect(!plates.contains { $0.tierID == 2 })
    }

    @Test func bumperDropNeverDropsPurple() {
        // Purple (10) is a milestone plate — not in the random drop table.
        let rolls: [Double] = [0, 0.35, 0.70, 0.74, 0.78, 0.82, 0.86, 0.89, 0.92, 0.94, 0.96, 0.98, 0.9999]
        for roll in rolls {
            #expect(BarbellUnlockRules.randomBumperVariantTierID(roll: roll) != 10,
                    "Purple must not be randomly droppable (roll=\(roll))")
        }
    }

    @Test func bumperDropTableCovers10ColorVariants() {
        let expectedIDs: Set<Int> = [14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
        // Sample across the full range to verify all 10 colored bumpers appear.
        let samples = stride(from: 0.70, through: 0.9999, by: 0.003).compactMap {
            BarbellUnlockRules.randomBumperVariantTierID(roll: $0)
        }
        #expect(Set(samples) == expectedIDs)
    }

    @Test func functionalHKMilestonesAwardExpectedPlates() {
        let cases: [(count: Int, tierID: Int, weightKg: Double, event: String)] = [
            (5, 1, 5, "hk_milestone_5"),
            (15, 2, 10, "hk_milestone_15"),
            (25, 3, 15, "hk_milestone_25"),
            (50, 5, 25, "hk_milestone_50"),
            (100, 9, 30, "hk_milestone_100")
        ]

        for testCase in cases {
            let plates = BarbellUnlockRules.evaluateFunctionalHK(
                config: makeFunctionalHKConfig(totalWorkouts: testCase.count),
                existingEvents: [],
                bumperVariantRoll: { 0 }
            )

            #expect(plates.contains {
                $0.tierID == testCase.tierID &&
                $0.weightKg == testCase.weightKg &&
                $0.earnedByEvent == testCase.event
            })
        }
    }

    @Test func functionalHKMilestoneDoesNotAwardDuplicateEvent() {
        let plates = BarbellUnlockRules.evaluateFunctionalHK(
            config: makeFunctionalHKConfig(totalWorkouts: 5),
            existingEvents: ["hk_milestone_5"],
            bumperVariantRoll: { 0 }
        )

        #expect(!plates.contains { $0.earnedByEvent == "hk_milestone_5" })
    }

    @Test func functionalHKCastIronIsNotBumperUpgraded() {
        let plates = BarbellUnlockRules.evaluateFunctionalHK(
            config: makeFunctionalHKConfig(totalWorkouts: 5),
            existingEvents: [],
            bumperVariantRoll: { 0.75 }
        )

        #expect(plates.contains { $0.tierID == 1 && $0.earnedByEvent == "hk_milestone_5" })
        #expect(!plates.contains { $0.earnedByEvent == "hk_milestone_5" && $0.tierID != 1 })
    }

    @Test func functionalHKBlackBumperCanBeColorUpgraded() {
        let plates = BarbellUnlockRules.evaluateFunctionalHK(
            config: makeFunctionalHKConfig(totalWorkouts: 15),
            existingEvents: [],
            bumperVariantRoll: { 0.75 }
        )

        #expect(plates.contains {
            $0.tierID == 15 &&
            $0.earnedByEvent == "hk_milestone_15" &&
            $0.engravingText == "15 Sessions"
        })
        #expect(!plates.contains { $0.tierID == 2 })
    }

    @Test func actualCardioRunsDoNotCountAsFunctionalHKStrength() {
        let running = Run(
            date: .now,
            distanceKm: 5,
            durationSec: 1_800,
            healthKitUUID: UUID(),
            workoutType: "Running"
        )
        let functionalStrength = Run(
            date: .now,
            distanceKm: 0,
            durationSec: 1_800,
            healthKitUUID: UUID(),
            workoutType: "Functional Training"
        )

        #expect(!running.countsAsStrengthDay)
        #expect(functionalStrength.countsAsStrengthDay)
    }

    @Test func prExistingLegacyPrefixDoesNotEarnDuplicateFullUUIDPlate() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 3)
        let plates = BarbellUnlockRules.evaluate(
            workout: workout,
            config: config,
            existingEvents: [BarbellUnlockRules.legacyPREventKey(for: workout.id)],
            bumperVariantRoll: { 0 }
        )

        #expect(!plates.contains { $0.earnedByEvent == BarbellUnlockRules.prEventKey(for: workout.id) })
    }

    @Test func multipleRulesReturnMultiplePlates() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 5)
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: [])
        // Both Cast Iron (milestone 5) and Competition (PR) should fire
        #expect(plates.count >= 2)
    }

    @Test func platesOrderedByRarityDescending() {
        let workout = makeWorkout(prCount: 1)
        let config = makeConfig(totalWorkouts: 5)
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: [])
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
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: ["first_workout"])
        #expect(plates.contains { $0.tierID == 0 })
    }

    @Test func earlyRawIronCappedAt4() {
        let workout = makeWorkout()
        let config = makeConfig(totalWorkouts: 12)
        // Already have 4 raw iron plates
        let existing = ["first_workout", "raw_iron_3", "raw_iron_6", "raw_iron_9"]
        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: existing)
        #expect(!plates.contains { $0.tierID == 0 })
    }

    @Test func firstTrackedLiftTypeEarnsLiftPlate() {
        let workout = makeWorkout(exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press")
        let config = makeConfig(totalWorkouts: 2)

        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: ["first_workout"])

        #expect(plates.contains {
            $0.earnedByEvent == BarbellUnlockRules.liftFirstEventKey(for: "bench-press") &&
            $0.liftTypeID == "bench-press" &&
            $0.engravingText == "Bench Press"
        })
    }

    @Test func existingTrackedLiftTypeDoesNotEarnDuplicateLiftPlate() {
        let workout = makeWorkout(exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press")
        let config = makeConfig(totalWorkouts: 3)
        let existing = ["first_workout", BarbellUnlockRules.liftFirstEventKey(for: "bench-press")]

        let plates = evaluateNoBumperDrop(workout: workout, config: config, existingEvents: existing)

        #expect(!plates.contains { $0.liftTypeID == "bench-press" })
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

    @Test func rewardQueuePicksOneFullscreenEventByPriority() {
        let now = Date()
        let plate = EarnedPlateInfo(tierID: 0, weightKg: 2.5, engravingText: "First Lift", earnedByEvent: "first_workout")
        let events = [
            BarbellRewardEvent(id: "pr", kind: .personalRecord, title: "PR", occurredAt: now, plate: nil),
            BarbellRewardEvent(id: "plate", kind: .newPlate, title: "Plate", occurredAt: now, plate: plate),
            BarbellRewardEvent(id: "set", kind: .setBonus, title: "Set", occurredAt: now, plate: nil)
        ]

        let queue = BarbellUnlockRules.makePresentationQueue(
            events: events,
            occurredAt: now,
            now: now,
            source: .liveWorkoutCompletion
        )

        #expect(queue.primary?.kind == .newPlate)
        #expect(queue.fullScreenPlate == plate)
        #expect(queue.compactEvents.count == 2)
    }

    @Test func rewardQueueSuppressesBackfilledEvents() {
        let now = Date()
        let events = [
            BarbellRewardEvent(id: "plate", kind: .newPlate, title: "Plate", occurredAt: now)
        ]

        let queue = BarbellUnlockRules.makePresentationQueue(
            events: events,
            occurredAt: now,
            now: now,
            source: .migrationBackfill
        )

        #expect(queue.primary == nil)
        #expect(queue.compactEvents.isEmpty)
    }

    @Test func rewardQueueSuppressesStaleLiveEvents() {
        let now = Date()
        let stale = now.addingTimeInterval(-31)
        let events = [
            BarbellRewardEvent(id: "plate", kind: .newPlate, title: "Plate", occurredAt: stale)
        ]

        let queue = BarbellUnlockRules.makePresentationQueue(
            events: events,
            occurredAt: stale,
            now: now,
            source: .liveWorkoutCompletion
        )

        #expect(queue.primary == nil)
        #expect(queue.compactEvents.isEmpty)
    }

    @Test func catalogExposesActiveSeasonalCosmeticForWorkoutDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let workoutDate = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: 15
        )))

        let item = try #require(BarbellCosmeticCatalog.current.activeSeasonalItem(for: workoutDate))

        #expect(item.id == "may_2026_brass_accent")
        #expect(item.availableFrom != nil)
        #expect(item.availableUntil != nil)
        #expect(item.seasonalWorkoutTarget == 1)
    }

    @Test func seasonalCosmeticUnlocksInsideWindowOnlyOnce() throws {
        let calendar = Calendar(identifier: .gregorian)
        let workoutDate = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: 15
        )))
        var workout = makeWorkout()
        workout.date = workoutDate
        let config = makeConfig(totalWorkouts: 1)

        let unlocks = BarbellUnlockRules.evaluateSeasonalCosmetics(
            workout: workout,
            config: config,
            existingCosmeticUnlockIDs: []
        )

        #expect(unlocks.map(\.cosmeticID) == ["may_2026_brass_accent"])
        #expect(unlocks.first?.unlockedAt == workoutDate)
        #expect(unlocks.first?.source == .seasonal)
    }

    @Test func seasonalCosmeticDoesNotUnlockOutsideWindowOrWhenAlreadyOwned() throws {
        let calendar = Calendar(identifier: .gregorian)
        let outsideDate = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 1
        )))
        var workout = makeWorkout()
        workout.date = outsideDate
        let config = makeConfig(totalWorkouts: 1)

        #expect(BarbellUnlockRules.evaluateSeasonalCosmetics(
            workout: workout,
            config: config,
            existingCosmeticUnlockIDs: []
        ).isEmpty)

        workout.date = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: 15
        )))

        #expect(BarbellUnlockRules.evaluateSeasonalCosmetics(
            workout: workout,
            config: config,
            existingCosmeticUnlockIDs: ["may_2026_brass_accent"]
        ).isEmpty)
    }

    @Test func rewardSummaryPresentsSeasonalCosmeticOnlyQueue() {
        let now = Date()
        let queue = BarbellUnlockRules.makePresentationQueue(
            events: [
                BarbellRewardEvent(
                    id: "cosmetic_may_2026_brass_accent",
                    kind: .cosmeticUnlock,
                    title: "May Brass Accent",
                    detail: "Seasonal unlock",
                    occurredAt: now
                )
            ],
            occurredAt: now,
            now: now,
            source: .liveWorkoutCompletion
        )
        let summary = RewardSummary(
            xp: 0,
            coins: 0,
            levelUpTo: nil,
            streakOld: 0,
            streakNew: 0,
            hitStreakMilestone: false,
            unlockedAchievements: [],
            prCount: 0,
            newExerciseCount: 0,
            xpSnapshot: nil,
            xpLineItems: [],
            streakFrozen: false,
            streakBonusXP: 0,
            earnedPlates: [],
            rewardQueue: queue
        )

        #expect(summary.shouldPresent)
    }
}

@MainActor
struct BarbellProjectionRulesTests {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makePlate(
        liftTypeID: String? = nil,
        currentTier: BarbellPlateProgressionTier = .iron,
        earnedAt: Date? = nil
    ) -> EarnedPlate {
        EarnedPlate(
            id: "plate-1",
            tierID: 0,
            weightKg: 2.5,
            engravingText: "First Lift",
            earnedAt: earnedAt ?? baseDate,
            earnedByEvent: "first_workout",
            liftTypeID: liftTypeID,
            currentTier: currentTier
        )
    }

    private func makeWorkout(
        day: Int,
        exerciseID: String,
        exerciseName: String,
        prCount: Int = 0,
        completed: Bool = true
    ) -> CompletedWorkout {
        let set = SetInput(reps: 5, weight: 100, isCompleted: completed)
        let entry = WorkoutEntry(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            muscleGroups: [],
            sets: [set]
        )
        var workout = CompletedWorkout(
            date: baseDate.addingTimeInterval(TimeInterval(day * 86_400)),
            entries: [entry]
        )
        workout.detectedPRCount = prCount
        return workout
    }

    @Test func projectedTierUsesMvpThresholds() {
        #expect(BarbellPlateProjectionRules.projectedTier(workoutCount: 9, prCount: 0) == .iron)
        #expect(BarbellPlateProjectionRules.projectedTier(workoutCount: 10, prCount: 0) == .steel)
        #expect(BarbellPlateProjectionRules.projectedTier(workoutCount: 10, prCount: 1) == .chrome)
        #expect(BarbellPlateProjectionRules.projectedTier(workoutCount: 50, prCount: 2) == .chrome)
        #expect(BarbellPlateProjectionRules.projectedTier(workoutCount: 50, prCount: 3) == .gold)
    }

    @Test func projectionFiltersToLiftTypeAndCountsPRs() {
        let plate = makePlate(liftTypeID: "barbell-bench-press")
        let workouts = [
            makeWorkout(day: 1, exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press"),
            makeWorkout(day: 2, exerciseID: "barbell-back-squat", exerciseName: "Back Squat", prCount: 1),
            makeWorkout(day: 3, exerciseID: "barbell bench press", exerciseName: "Barbell Bench Press", prCount: 1)
        ]

        let projection = BarbellPlateProjectionRules.rebuildProjection(for: plate, workouts: workouts)

        #expect(projection.workoutsUsedCount == 2)
        #expect(projection.prCount == 1)
        #expect(projection.currentTier == .chrome)
        #expect(projection.pressUseCount == 2)
        #expect(projection.chalkUseCount == 0)
        #expect(projection.lastUsedAt == workouts[2].date)
    }

    @Test func globalProjectionBuildsAgingCountersFromCompletedWorkingSets() {
        let plate = makePlate()
        let workouts = [
            makeWorkout(day: 1, exerciseID: "deadlift", exerciseName: "Deadlift"),
            makeWorkout(day: 2, exerciseID: "barbell-row", exerciseName: "Barbell Row"),
            makeWorkout(day: 3, exerciseID: "overhead-press", exerciseName: "Overhead Press"),
            makeWorkout(day: 4, exerciseID: "back-squat", exerciseName: "Back Squat", completed: false)
        ]

        let projection = BarbellPlateProjectionRules.rebuildProjection(for: plate, workouts: workouts)

        #expect(projection.workoutsUsedCount == 4)
        #expect(projection.chalkUseCount == 1)
        #expect(projection.gripWearCount == 2)
        #expect(projection.pressUseCount == 1)
    }

    @Test func projectionCreatesStableSilentBiographyEvents() {
        let plate = makePlate()
        let workouts = (1...50).map { day in
            makeWorkout(
                day: day,
                exerciseID: "deadlift",
                exerciseName: "Deadlift",
                prCount: [5, 25, 50].contains(day) ? 1 : 0
            )
        }

        let projection = BarbellPlateProjectionRules.rebuildProjection(for: plate, workouts: workouts)
        let kinds = projection.eventDrafts.map(\.kind)

        #expect(projection.currentTier == .gold)
        #expect(kinds.contains(.earned))
        #expect(projection.eventDrafts.contains { $0.kind == .tieredUp && $0.tier == .steel })
        #expect(projection.eventDrafts.contains { $0.kind == .tieredUp && $0.tier == .chrome })
        #expect(projection.eventDrafts.contains { $0.kind == .tieredUp && $0.tier == .gold })
        #expect(projection.eventDrafts.filter { $0.kind == .personalRecord }.count == 3)
        #expect(projection.eventDrafts.contains { $0.kind == .milestoneVolume && $0.milestoneID == "workouts_10" })
        #expect(projection.eventDrafts.contains { $0.kind == .milestoneVolume && $0.milestoneID == "workouts_50" })
        #expect(projection.eventDrafts.allSatisfy { $0.isSilent })
        #expect(Set(projection.eventDrafts.map(\.stableKey)).count == projection.eventDrafts.count)
    }

    @Test func applyingProjectionDoesNotDowngradeStoredTierOrCounters() {
        let plate = makePlate(currentTier: .gold)
        plate.workoutsUsedCount = 80
        plate.prCount = 5
        plate.chalkUseCount = 12
        plate.gripWearCount = 9
        plate.pressUseCount = 7
        plate.lastUsedAt = baseDate.addingTimeInterval(100 * 86_400)

        let projection = BarbellPlateProjection(
            plateID: plate.id,
            liftTypeID: plate.liftTypeID,
            currentTier: .steel,
            workoutsUsedCount: 10,
            prCount: 0,
            chalkUseCount: 2,
            gripWearCount: 3,
            pressUseCount: 4,
            firstEarnedAt: baseDate.addingTimeInterval(-86_400),
            lastUsedAt: baseDate.addingTimeInterval(50 * 86_400),
            eventDrafts: []
        )

        plate.applyProjection(projection)

        #expect(plate.currentTier == .gold)
        #expect(plate.workoutsUsedCount == 80)
        #expect(plate.prCount == 5)
        #expect(plate.chalkUseCount == 12)
        #expect(plate.gripWearCount == 9)
        #expect(plate.pressUseCount == 7)
        #expect(plate.firstEarnedAt == projection.firstEarnedAt)
        #expect(plate.lastUsedAt == baseDate.addingTimeInterval(100 * 86_400))
    }

    @Test func tierProgressDescribesNextMvpTier() {
        let iron = BarbellPlateTierProgress(
            currentTier: .iron,
            workoutsUsedCount: 4,
            prCount: 0
        )
        #expect(iron.nextTier == .steel)
        #expect(iron.progressFraction == 0.4)
        #expect(iron.primaryText == "6 workouts to Steel")

        let steel = BarbellPlateTierProgress(
            currentTier: .steel,
            workoutsUsedCount: 12,
            prCount: 0
        )
        #expect(steel.nextTier == .chrome)
        #expect(steel.progressFraction == 0)
        #expect(steel.primaryText == "1 PR to Chrome")

        let chrome = BarbellPlateTierProgress(
            currentTier: .chrome,
            workoutsUsedCount: 25,
            prCount: 2
        )
        #expect(chrome.nextTier == .gold)
        #expect(chrome.progressFraction == 0.5)
        #expect(chrome.primaryText == "25 workouts and 1 PR to Gold")
    }

    @Test func tierProgressStopsAtGoldForMvp() {
        let gold = BarbellPlateTierProgress(
            currentTier: .gold,
            workoutsUsedCount: 80,
            prCount: 5
        )
        #expect(gold.nextTier == nil)
        #expect(gold.progressFraction == 1)
        #expect(gold.primaryText == "Gold reached")
    }
}
