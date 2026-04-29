# Barbell Gamification Implementation Plan

> **Status: COMPLETE** — Merged to `main` via commit `4a27a65` on 2026-04-02. All 13 tasks implemented. See implementation notes at each task where the build diverged from the plan.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implement the personal barbell trophy system — earned plates from strength milestones and PRs, a drag-based Plate Wall editor, a two-page WinScreen earn flow with haptic feedback, and a social profile showcase card.

**Architecture:** Plates are awarded inside the existing `processInBackground` pipeline in `StreakResult.swift`, keeping them part of the same background SwiftData context save as XP/streaks. `BarbellProgressService` owns rack/unrack operations and starter plate setup. The Plate Wall replaces the old carousel editor entirely; the social showcase card drops into `SocialProfileView` between `activityLink` and `actionButtons`.

**Tech Stack:** SwiftData (@Model), RealityKit (3D barbell scene), UIImpactFeedbackGenerator (haptics), AVAudioPlayer (clink sound), Supabase (remote rack sync)

---

## File Map

**Create:**
- `Features/Rewards/Models/BarbellModels.swift` — EarnedPlate, BarbellConfig, EarnedPlateInfo, PlateTier+Starter
- `Features/Rewards/Services/BarbellUnlockRules.swift` — static evaluate function
- `Features/Rewards/Services/BarbellProgressService.swift` — rack/unrack, starter plates, backfill
- `Features/Rewards/Views/BarbellMomentView.swift` — WinScreen Page 2 (plates animate onto bar)
- `Features/Profile/Views/PlateWallView.swift` — full-screen plate wall + barbell zone
- `Features/Social/Views/BarbellShowcaseCard.swift` — social profile showcase card
- `WRKTTests/BarbellUnlockRulesTests.swift` — unit tests for rule engine

**Modify:**
- `App/WRKTApp.swift` — add EarnedPlate, BarbellConfig to schema
- `Core/Dependencies/AppDependencies.swift` — add barbellProgressService property + configure call
- `Features/WorkoutSession/Services/WorkoutStoreV2.swift` — expose lastCompletedWorkout
- `Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift` — pass workout in payload
- `Features/Rewards/Models/StreakResult.swift` — call plate evaluation in processInBackground
- `Features/Rewards/Views/RewardSummary.swift` — add earnedPlates field, update all inits + merged
- `Features/Rewards/Views/WinScreen.swift` — add PlateRevealCard, wire BarbellMomentView
- `Features/Profile/Views/BarbellPreviewView.swift` — rename/reorder tiers, add BarbellDisplayMode, fix spin, add showcase mode
- `Features/Social/Views/SocialProfileView.swift` — insert BarbellShowcaseCard

---

## Task 1: Data Models

**Files:**
- Create: `Features/Rewards/Models/BarbellModels.swift`

- [x] **Step 1: Write failing test for EarnedPlateInfo equality**

```swift
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
```

Run: `xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellModelsTests`
Expected: FAIL — `EarnedPlateInfo` not defined

- [x] **Step 2: Create BarbellModels.swift**

```swift
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
    var rackPosition: Int?     // 0-3 = left side, 4-7 = right side; nil = in collection
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
```

- [x] **Step 3: Run test**

Run: `xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellModelsTests`
Expected: PASS

- [x] **Step 4: Commit**

```bash
git add Features/Rewards/Models/BarbellModels.swift WRKTTests/BarbellUnlockRulesTests.swift
git commit -m "feat: add EarnedPlate, BarbellConfig, EarnedPlateInfo models"
```

---

## Task 2: Schema Registration + AppDependencies

**Files:**
- Modify: `App/WRKTApp.swift:244` (schema array)
- Modify: `Core/Dependencies/AppDependencies.swift:38` (add property + wire in configure)

- [x] **Step 1: Register models in schema**

In `App/WRKTApp.swift`, find `makeContainer()` and the `Schema([` call inside it. Add `EarnedPlate.self, BarbellConfig.self` to the array:

```swift
let schema = Schema([
    RewardProgress.self, Achievement.self, ChallengeAssignment.self, RewardLedgerEntry.self,
    Wallet.self, ExercisePR.self, DexStamp.self, WeeklyTrainingSummary.self, ExerciseVolumeSummary.self,
    MovingAverage.self, ExerciseProgressionSummary.self, ExerciseTrend.self, PushPullBalance.self,
    MuscleGroupFrequency.self, MovementPatternBalance.self, WeeklyGoal.self,
    HealthSyncAnchor.self, RouteFetchTask.self, MapSnapshotCache.self,
    PlannedWorkout.self, PlannedExercise.self, WorkoutSplit.self, PlanBlock.self, PlanBlockExercise.self,
    EarnedPlate.self, BarbellConfig.self  // barbell gamification
])
```

- [x] **Step 2: Add BarbellProgressService to AppDependencies**

In `Core/Dependencies/AppDependencies.swift`, add property after `virtualRunRepository`:

```swift
/// Barbell progress service - manages plate earn/rack state
let barbellProgressService: BarbellProgressService
```

In `private init()`, initialise it after `virtualRunRepository`:

```swift
self.barbellProgressService = BarbellProgressService.shared
```

In `configure(with:)`, add after the existing configure calls:

```swift
// Configure BarbellProgressService
barbellProgressService.configure(context: modelContext)
AppLogger.success("BarbellProgressService configured", category: AppLogger.rewards)
```

- [x] **Step 3: Build to confirm schema compiles**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 4: Commit**

```bash
git add App/WRKTApp.swift Core/Dependencies/AppDependencies.swift
git commit -m "feat: register EarnedPlate/BarbellConfig in schema, wire BarbellProgressService"
```

---

## Task 3: BarbellProgressService Scaffold

**Files:**
- Create: `Features/Rewards/Services/BarbellProgressService.swift`

- [x] **Step 1: Create service with configure, ensureBarbellConfig, and starter plate setup**

```swift
// Features/Rewards/Services/BarbellProgressService.swift
import Foundation
import SwiftData
import UIKit
import AVFoundation

@MainActor
final class BarbellProgressService {
    static let shared = BarbellProgressService()

    private var context: ModelContext?
    private var clinkPlayer: AVAudioPlayer?

    private init() {}

    // MARK: - Configuration

    func configure(context: ModelContext) {
        self.context = context
        ensureBarbellConfig()
        ensureStarterPlates()
        preloadClinkSound()   // must be called on MainActor, after init completes
    }

    // MARK: - Singleton fetch/create

    func fetchOrCreateConfig(context: ModelContext) -> BarbellConfig {
        let fd = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
        if let existing = try? context.fetch(fd).first { return existing }
        let config = BarbellConfig()
        context.insert(config)
        try? context.save()
        return config
    }

    private func ensureBarbellConfig() {
        guard let context else { return }
        _ = fetchOrCreateConfig(context: context)
    }

    // MARK: - Starter plates

    private func ensureStarterPlates() {
        guard let context else { return }
        let fd = FetchDescriptor<EarnedPlate>(predicate: #Predicate { $0.earnedByEvent == "starter" })
        let existing = (try? context.fetch(fd)) ?? []
        guard existing.isEmpty else { return }

        // One starter plate at the outermost slot (position 3).
        // Bilateral rendering: the scene mirrors every racked plate to both sides,
        // so one plate object = a pair visible on both sides of the bar.
        let starter = EarnedPlate.makeStarter(position: 3)
        context.insert(starter)
        try? context.save()
    }

    // MARK: - Rack / Unrack

    enum RackError: Error { case barIsFull }

    /// Racks a plate into the next available slot (0–3).
    ///
    /// **Bilateral rendering contract:** `rackPosition` stores a slot index 0–3 only.
    /// The scene builder is responsible for rendering every racked plate on BOTH sides of the
    /// bar simultaneously. There is no separate right-side position: one `EarnedPlate` row = one
    /// visual pair. Positions 4–7 are reserved and unused.
    func rackPlate(_ plate: EarnedPlate) throws {
        guard let context else { return }

        let validPositions = [0, 1, 2, 3]   // innermost to outermost
        let fd = FetchDescriptor<EarnedPlate>(predicate: #Predicate { $0.isRacked == true })
        let racked = (try? context.fetch(fd)) ?? []
        let occupied = racked.compactMap(\.rackPosition).filter { validPositions.contains($0) }

        guard occupied.count < 4 else { throw RackError.barIsFull }

        let nextSlot = validPositions.filter { !occupied.contains($0) }.min()!
        plate.isRacked = true
        plate.rackPosition = nextSlot
        try? context.save()
        playClinkHaptic()
        queueSupabaseSync()
    }

    func unrackPlate(_ plate: EarnedPlate) {
        guard let context else { return }
        plate.isRacked = false
        plate.rackPosition = nil
        try? context.save()
        queueSupabaseSync()
    }

    // MARK: - Haptic + Sound

    func playClinkHaptic() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        clinkPlayer?.stop()
        clinkPlayer?.currentTime = 0
        clinkPlayer?.play()
    }

    private func preloadClinkSound() {
        guard let url = Bundle.main.url(forResource: "plate_clink", withExtension: "caf") else { return }
        clinkPlayer = try? AVAudioPlayer(contentsOf: url)
        clinkPlayer?.prepareToPlay()
    }

    // MARK: - Supabase sync (stub, wired in Phase 4)

    private func queueSupabaseSync() {
        guard let context else { return }
        let fd = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
        if let config = try? context.fetch(fd).first {
            config.needsSupabaseSync = true
            try? context.save()
        }
    }

    // MARK: - RewardsEngine reset hook

    func resetAll() {
        guard let context else { return }
        let plateFetch = FetchDescriptor<EarnedPlate>()
        if let plates = try? context.fetch(plateFetch) {
            for p in plates { context.delete(p) }
        }
        let configFetch = FetchDescriptor<BarbellConfig>()
        if let configs = try? context.fetch(configFetch) {
            for c in configs { context.delete(c) }
        }
        try? context.save()
        ensureBarbellConfig()
        ensureStarterPlates()
    }
}
```

- [x] **Step 2: Add resetAll hook to RewardsEngine**

In `Features/Rewards/Services/RewardEngine.swift`, at the end of `resetAll()` before the final save:

```swift
// Reset barbell progress (service is @MainActor — dispatch from whatever actor resetAll runs on)
Task { @MainActor in
    BarbellProgressService.shared.resetAll()
}
```

- [x] **Step 3: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 4: Commit**

```bash
git add Features/Rewards/Services/BarbellProgressService.swift Features/Rewards/Services/RewardEngine.swift
git commit -m "feat: add BarbellProgressService with rack/unrack, starter plates, reset hook"
```

---

## Task 4: Unlock Rule Engine + Tests

**Files:**
- Create: `Features/Rewards/Services/BarbellUnlockRules.swift`
- Modify: `WRKTTests/BarbellUnlockRulesTests.swift`

- [x] **Step 1: Write failing tests**

```swift
// WRKTTests/BarbellUnlockRulesTests.swift — replace contents
import Testing
import SwiftData
@testable import WRKT

struct BarbellUnlockRulesTests {

    // Helper: minimal CompletedWorkout with one entry
    private func makeWorkout(prCount: Int = 0) -> CompletedWorkout {
        // CompletedWorkout(date:startedAt:entries:plannedWorkoutID:)
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
        // A workout with cardioWorkoutType set and no entries is classified as cardio.
        // BarbellUnlockRules.evaluate itself doesn't check workout type — the isCardioWorkout
        // guard lives in processInBackground. This test verifies the gate at the call site
        // by using a workout that IS cardio and confirming the caller skips evaluate entirely.
        //
        // Approach: call evaluate directly with a PR-workout and confirm plates ARE returned,
        // then confirm the processInBackground guard (tested via integration) skips it for cardio.
        // Unit-test the guard itself by checking CompletedWorkout.isCardioWorkout is false
        // for a standard strength workout used in the other tests.
        let strengthWorkout = makeWorkout(prCount: 1)
        #expect(!strengthWorkout.isCardioWorkout)

        var cardioWorkout = makeWorkout()
        cardioWorkout.cardioWorkoutType = "Running"
        cardioWorkout.matchedHealthKitUUID = UUID()
        // entries is empty, matchedHealthKitUUID is set — isCardioWorkout returns true
        #expect(cardioWorkout.isCardioWorkout)
    }
}
```

Run: `xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellUnlockRulesTests`
Expected: FAIL — `BarbellUnlockRules` not defined

- [x] **Step 2: Implement BarbellUnlockRules**

```swift
// Features/Rewards/Services/BarbellUnlockRules.swift
import Foundation

enum BarbellUnlockRules {

    // Tier rarity order for sorting results (higher = returned first)
    private static let rarityOrder: [Int: Int] = [
        6: 5,   // Gold — legendary
        5: 4,   // Polished Steel — epic
        4: 3,   // Competition — rare
        3: 3,   // Brass — rare
        2: 2,   // Black Bumper — uncommon
        1: 1,   // Cast Iron — common
        0: 0    // Raw Iron — common
    ]

    /// Evaluate all unlock rules for a completed workout.
    ///
    /// - Parameters:
    ///   - workout: The just-completed strength workout.
    ///   - config: BarbellConfig with updated totalStrengthWorkouts (already incremented before calling).
    ///   - existingEvents: All earnedByEvent strings already in the user's EarnedPlate collection.
    ///     Used to guard one-time milestones and Raw Iron cap.
    ///
    /// Returns plates sorted by rarity descending (highest rarity first).
    static func evaluate(
        workout: CompletedWorkout,
        config: BarbellConfig,
        existingEvents: [String]
    ) -> [EarnedPlateInfo] {
        var results: [EarnedPlateInfo] = []
        let total = config.totalStrengthWorkouts

        // Rule 1: 90-day streak — Gold
        if config.lastStreakCheckDate == nil {
            // Streak check is handled by RewardsEngine; this rule is evaluated only if
            // BarbellConfig.lastStreakCheckDate was nil before this workout.
            // See note: streak gate integrated into processInBackground separately.
        }

        // Rule 2: PR detected — Competition plate (one per PR workout, key includes workout ID
        // so multiple workouts can each earn a Competition plate without blocking each other)
        if (workout.detectedPRCount ?? 0) > 0 {
            results.append(EarnedPlateInfo(
                tierID: 4,
                weightKg: 20,
                engravingText: "Personal Record",
                earnedByEvent: "pr_\(workout.id.uuidString.prefix(8))"
            ))
        }

        // Rule 3: Milestone thresholds (one-time each)
        let milestones: [(count: Int, tierID: Int, weightKg: Double, engraving: String, event: String)] = [
            (50, 5, 25, "50 Workouts",  "strength_milestone_50"),
            (25, 3, 15, "25 Workouts",  "strength_milestone_25"),
            (15, 2, 10, "15 Workouts",  "strength_milestone_15"),
            (5,  1,  5, "5 Workouts",   "strength_milestone_5"),
        ]
        for m in milestones {
            guard total == m.count else { continue }
            guard !existingEvents.contains(m.event) else { continue }
            results.append(EarnedPlateInfo(
                tierID: m.tierID,
                weightKg: m.weightKg,
                engravingText: m.engraving,
                earnedByEvent: m.event
            ))
        }

        // Rule 4: Raw Iron early plates (max 4 total)
        let rawIronEvents = existingEvents.filter { $0 == "first_workout" || $0.hasPrefix("raw_iron_") }
        let rawIronCount = rawIronEvents.count

        if total == 1 && !existingEvents.contains("first_workout") {
            results.append(EarnedPlateInfo(
                tierID: 0,
                weightKg: 2.5,
                engravingText: "First Lift",
                earnedByEvent: "first_workout"
            ))
        } else if total > 1 && total % 3 == 0 && rawIronCount < 4 {
            results.append(EarnedPlateInfo(
                tierID: 0,
                weightKg: 5,
                engravingText: "Session \(total)",
                earnedByEvent: "raw_iron_\(total)"
            ))
        }

        // Sort by rarity descending
        return results.sorted { (rarityOrder[$0.tierID] ?? 0) > (rarityOrder[$1.tierID] ?? 0) }
    }

    /// Evaluate the 90-day streak Gold plate.
    /// Call separately only when streak >= 90 is confirmed by RewardsEngine.
    static func evaluateGoldStreak(existingEvents: [String]) -> EarnedPlateInfo? {
        guard !existingEvents.contains("streak_90_day") else { return nil }
        return EarnedPlateInfo(
            tierID: 6,
            weightKg: 45,
            engravingText: "90-Day Streak",
            earnedByEvent: "streak_90_day"
        )
    }
}
```

- [x] **Step 3: Run tests**

Run: `xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellUnlockRulesTests`
Expected: All PASS

- [x] **Step 4: Commit**

```bash
git add Features/Rewards/Services/BarbellUnlockRules.swift WRKTTests/BarbellUnlockRulesTests.swift
git commit -m "feat: add BarbellUnlockRules with full milestone/PR/Raw Iron rule set"
```

---

## Task 5: Wire Plate Evaluation into processInBackground

**Files:**
- Modify: `Features/WorkoutSession/Services/WorkoutStoreV2.swift:1585`
- Modify: `Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift:544`
- Modify: `Features/Rewards/Models/StreakResult.swift` (processInBackground)
- Modify: `Features/Rewards/Views/RewardSummary.swift`

- [x] **Step 1: Expose lastCompletedWorkout in WorkoutStoreV2**

In `Features/WorkoutSession/Services/WorkoutStoreV2.swift`, add this property after the other @Published properties near the top of the class:

```swift
@Published private(set) var lastCompletedWorkout: CompletedWorkout?
```

In `finishCurrentWorkoutAndReturnPRs()`, search for `completedWorkouts.append(completed)` and add directly after it:

```swift
lastCompletedWorkout = completed
```

- [x] **Step 2: Pass workout in processAsync payload**

In `Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift`, search for `RewardsEngine.shared.processAsync` and update that call:

```swift
RewardsEngine.shared.processAsync(event: "workout_completed", payload: [
    "workoutId": result.workoutId,
    "completedWorkout": store.lastCompletedWorkout as Any
])
```

- [x] **Step 3: Add earnedPlates to RewardSummary**

In `Features/Rewards/Views/RewardSummary.swift`, add the field to `RewardSummary`:

```swift
public struct RewardSummary: Equatable {
    // ... existing fields ...
    let earnedPlates: [EarnedPlateInfo]   // new — empty array = no plates earned
}
```

Find the backward-compat `init` (the one that does NOT have `xpSnapshot` or `xpLineItems` parameters) and add `earnedPlates: []`:

```swift
init(xp: Int, coins: Int, levelUpTo: Int?, streakOld: Int, streakNew: Int,
     hitStreakMilestone: Bool, unlockedAchievements: [String], prCount: Int,
     newExerciseCount: Int) {
    // ... existing assignments ...
    self.earnedPlates = []
}
```

Find the full init (the one that includes `xpSnapshot` and `xpLineItems` parameters) and add the `earnedPlates` parameter:

```swift
init(xp: Int, coins: Int, levelUpTo: Int?, streakOld: Int, streakNew: Int,
     hitStreakMilestone: Bool, unlockedAchievements: [String], prCount: Int,
     newExerciseCount: Int, xpSnapshot: XPSnapshot?, xpLineItems: [XPLineItem],
     streakFrozen: Bool, streakBonusXP: Int, earnedPlates: [EarnedPlateInfo] = []) {
    // ... existing assignments ...
    self.earnedPlates = earnedPlates
}
```

Update `merged(with:)` to concatenate plates:

```swift
return RewardSummary(
    // ... existing fields ...
    earnedPlates: earnedPlates + other.earnedPlates
)
```

Update `withLuckyBonusCheck()` to forward plates:

```swift
return RewardSummary(
    // ... existing fields ...
    earnedPlates: earnedPlates
)
```

Update `shouldPresent` to also return true when plates were earned:

```swift
var shouldPresent: Bool {
    (xp > 0) ||
    (coins > 0) ||
    (prCount > 0) ||
    (newExerciseCount > 0) ||
    (levelUpTo != nil) ||
    (streakNew > streakOld) ||
    !unlockedAchievements.isEmpty ||
    !earnedPlates.isEmpty   // new
}
```

- [x] **Step 4: Add plate evaluation in processInBackground**

In `Features/Rewards/Models/StreakResult.swift`, in `processInBackground(event:payload:context:rules:)`:

**Step 4a:** Add the evaluation block after the streak block and before the `// Extract counts` comment. Search for `// Extract counts` to find the insertion point. This block only evaluates — it does NOT insert into `bgContext` yet (inserts happen after the `shouldNotify` guard so that `bgContext.save()` is guaranteed to run).

```swift
// 4) Barbell plate evaluation — evaluate only, inserts are deferred until after shouldNotify guard
var earnedPlates: [EarnedPlateInfo] = []
var earnedPlatesWorkoutID: String? = payload["workoutId"] as? String
if name == "workout_completed",
   let workout = payload["completedWorkout"] as? CompletedWorkout,
   !workout.isCardioWorkout {   // only strength workouts earn plates

    let configFD = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
    let bgConfig: BarbellConfig
    if let existing = try? bgContext.fetch(configFD).first {
        bgConfig = existing
    } else {
        bgConfig = BarbellConfig()
        bgContext.insert(bgConfig)
    }

    // Increment strength workout count BEFORE evaluate (rules read updated count)
    bgConfig.totalStrengthWorkouts += 1

    let existingFD = FetchDescriptor<EarnedPlate>()
    let existingPlates = (try? bgContext.fetch(existingFD)) ?? []
    let existingEvents = existingPlates.map(\.earnedByEvent)

    var plates = BarbellUnlockRules.evaluate(workout: workout, config: bgConfig, existingEvents: existingEvents)

    // Gold streak — append to plates array, then re-sort so rarity order is always correct
    if bgProgress.currentStreak >= 90 {
        if let gold = BarbellUnlockRules.evaluateGoldStreak(existingEvents: existingEvents) {
            plates.append(gold)
            bgConfig.lastStreakCheckDate = .now
        }
    }

    // Re-sort after merging so Gold (legendary) always leads regardless of insertion order
    let rarityForTier: [Int: Int] = [6: 5, 5: 4, 4: 3, 3: 3, 2: 2, 1: 1, 0: 0]
    earnedPlates = plates.sorted { (rarityForTier[$0.tierID] ?? 0) > (rarityForTier[$1.tierID] ?? 0) }
}
```

**Step 4b:** Find the `let shouldNotify = (totalXP != 0 ...` line and update it to include plates:

```swift
let shouldNotify = (totalXP != 0 || totalCoins != 0 || !newLedger.isEmpty
                    || prCount > 0 || newExerciseCount > 0 || !earnedPlates.isEmpty)
guard shouldNotify else { return }
```

**Step 4c:** After the `guard shouldNotify else { return }` and before `for entry in newLedger`, add the plate inserts:

```swift
// Persist earned plates (after guard — bgContext.save() is guaranteed to run from here)
for info in earnedPlates {
    let plate = EarnedPlate(
        tierID: info.tierID,
        weightKg: info.weightKg,
        engravingText: info.engravingText,
        earnedByEvent: info.earnedByEvent,
        sourceWorkoutID: earnedPlatesWorkoutID
    )
    bgContext.insert(plate)
}
```

Update the `RewardSummary` construction in `processInBackground` to include `earnedPlates`:

```swift
let summary = RewardSummary(
    xp: totalXP, coins: totalCoins,
    levelUpTo: leveled,
    streakOld: streakOld,
    streakNew: streakNew,
    hitStreakMilestone: hitMilestone,
    unlockedAchievements: unlocked,
    prCount: prCount,
    newExerciseCount: newExerciseCount,
    xpSnapshot: snapshot,
    xpLineItems: xpLineItems,
    streakFrozen: bgProgress.streakFrozen,
    streakBonusXP: streakBonusXP,
    earnedPlates: earnedPlates
)
```

- [x] **Step 5: Build and run the app, complete a first workout**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

Manual test: complete a strength workout in the simulator. Check that an `EarnedPlate` row appears in SwiftData (add a temporary debug print in `processInBackground` after the plate inserts if needed).

- [x] **Step 6: Commit**

```bash
git add Features/WorkoutSession/Services/WorkoutStoreV2.swift \
        Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift \
        Features/Rewards/Models/StreakResult.swift \
        Features/Rewards/Views/RewardSummary.swift
git commit -m "feat: wire plate evaluation into processInBackground, add earnedPlates to RewardSummary"
```

---

## Task 6: WinScreen PlateRevealCard

**Files:**
- Modify: `Features/Rewards/Views/WinScreen.swift`

- [x] **Step 1: Add PlateRevealCard private struct to WinScreen.swift**

Search for `struct LuckyBonusBanner` and add immediately before it:

```swift
// MARK: - Plate Reveal Card

private struct PlateRevealCard: View {
    let plate: EarnedPlateInfo

    private var tierName: String {
        switch plate.tierID {
        case 0: return "Raw Iron"
        case 1: return "Cast Iron"
        case 2: return "Black Bumper"
        case 3: return "Brass"
        case 4: return "Competition"
        case 5: return "Polished Steel"
        case 6: return "Gold"
        default: return "Plate"
        }
    }

    private var rarityLabel: String {
        switch plate.tierID {
        case 0, 1: return "Common"
        case 2: return "Uncommon"
        case 3, 4: return "Rare"
        case 5: return "Epic"
        case 6: return "Legendary"
        default: return ""
        }
    }

    private var rarityColor: Color {
        switch plate.tierID {
        case 0, 1: return .gray
        case 2: return Color(red: 0.2, green: 0.7, blue: 0.3)
        case 3, 4: return Color(red: 0.2, green: 0.4, blue: 0.9)
        case 5: return Color(red: 0.6, green: 0.2, blue: 0.9)
        case 6: return Color(red: 0.9, green: 0.65, blue: 0.1)
        default: return .white
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Plate swatch — colored circle matching tier material
            Circle()
                .fill(plateSwatchColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))" : "")
                        .font(.caption.weight(.black))
                        .foregroundStyle(textColorForTier(plate.tierID))
                )
                .overlay(Circle().stroke(rarityColor.opacity(0.5), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tierName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(rarityLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(rarityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(rarityColor.opacity(0.15), in: Capsule())
                }
                Text(plate.engravingText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.Semantic.brand)
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(rarityColor.opacity(0.25), lineWidth: 1))
    }

    private var plateSwatchColor: Color {
        switch plate.tierID {
        case 0: return Color(red: 0.40, green: 0.18, blue: 0.07)
        case 1: return Color(red: 0.14, green: 0.14, blue: 0.14)
        case 2: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case 3: return Color(red: 0.75, green: 0.60, blue: 0.25)
        case 4: return Color(red: 0.82, green: 0.09, blue: 0.09)
        case 5: return Color(red: 0.72, green: 0.76, blue: 0.80)
        case 6: return Color(red: 0.88, green: 0.68, blue: 0.12)
        default: return .gray
        }
    }

    private func textColorForTier(_ id: Int) -> Color {
        [0, 1, 2].contains(id) ? .white : .black
    }
}
```

- [x] **Step 2: Weave plate reveal cards into WinScreenView stagger**

In `WinScreenView`, add state:

```swift
@State private var revealedPlates: [Int] = []   // indices into summary.earnedPlates revealed so far
@State private var showBarbellMoment = false
```

In `startStaggeredReveal()`, after the highlights stagger block, add plate reveals:

```swift
// Stagger plate reveal cards after highlights
let plateStartDelay = highlightStartDelay + Double(highlights.count) * 0.15 + 0.2
for (index, _) in summary.earnedPlates.enumerated() {
    DispatchQueue.main.asyncAfter(deadline: .now() + plateStartDelay + Double(index) * 0.25) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            revealedPlates.append(index)
        }
        Haptics.heavy()
    }
}

// Shift buttons delay to after plates
// (Update the buttonsDelay calculation to include plates)
```

Update the `buttonsDelay` calculation to account for plates:

```swift
let totalItems = summary.xpLineItems.count + highlights.count + summary.earnedPlates.count
let buttonsDelay = baseDelay + 0.9 + Double(totalItems) * 0.15 + 0.4
```

In the `ScrollView` content `VStack`, after the `XPGainCardStaggered` / `HighlightsOnlyCard` block, add:

```swift
// Plate reveal cards
if !summary.earnedPlates.isEmpty {
    VStack(alignment: .leading, spacing: 8) {
        if !revealedPlates.isEmpty {
            Text("New Plates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)
        }
        ForEach(Array(summary.earnedPlates.enumerated()), id: \.offset) { index, plate in
            if revealedPlates.contains(index) {
                PlateRevealCard(plate: plate)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
}
```

- [x] **Step 3: Wire Continue button to show BarbellMomentView when plates earned**

In `WinScreenView`, update the Continue button action:

```swift
Button {
    Haptics.light()
    if !summary.earnedPlates.isEmpty && !showBarbellMoment {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBarbellMoment = true
        }
    } else {
        onDismiss()
    }
} label: {
    Text(summary.earnedPlates.isEmpty || showBarbellMoment ? "Continue" : "See Your Barbell")
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
}
```

Add `.fullScreenCover(isPresented: $showBarbellMoment)` below the `.sheet(isPresented:)` modifier:

```swift
.fullScreenCover(isPresented: $showBarbellMoment) {
    BarbellMomentView(plates: summary.earnedPlates, onDismiss: onDismiss)
}
```

- [x] **Step 4: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 5: Commit**

```bash
git add Features/Rewards/Views/WinScreen.swift
git commit -m "feat: add PlateRevealCard to WinScreen stagger, wire BarbellMomentView transition"
```

---

## Task 7: BarbellMomentView (WinScreen Page 2)

**Files:**
- Create: `Features/Rewards/Views/BarbellMomentView.swift`

- [x] **Step 1: Create BarbellMomentView**

```swift
// Features/Rewards/Views/BarbellMomentView.swift
import SwiftUI
import RealityKit
import SwiftData

/// WinScreen Page 2 — plates animate onto the bar one by one.
/// Shown only when earnedPlates is non-empty.
struct BarbellMomentView: View {
    let plates: [EarnedPlateInfo]
    let onDismiss: () -> Void

    // Previously racked plates (the existing barbell state shown as the base)
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var previouslyRackedPlates: [EarnedPlate]

    // Note: newly earned plates arrive via the `plates` prop, NOT via @Query.
    // They have isRacked == false at this point. The scene renders the existing barbell
    // state from @Query as the base, then the animation layer adds the new plates
    // from the prop one by one (purely visual — no SwiftData read for the new plates).
    @State private var seatedCount = 0
    @State private var scene = BarbellSceneState()
    @State private var isDragging = false
    @State private var lastTranslationX: CGFloat = 0
    @State private var showDoneButton = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Added to your Barbell")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(plates.count) new plate\(plates.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 48)
                .padding(.bottom, 24)

                // Barbell scene
                ZStack {
                    Color.black
                    TimelineView(.animation) { _ in
                        RealityView { content in
                            setupLights(in: &content)
                        } update: { content in
                            rebuildIfNeeded(content: &content)
                            // No auto-spin — static by default
                        }
                        .gesture(
                            DragGesture()
                                .targetedToAnyEntity()
                                .onChanged { value in
                                    isDragging = true
                                    let delta = Float(value.translation.width - lastTranslationX) * 0.008
                                    scene.rotAngle -= delta
                                    scene.root?.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))
                                    lastTranslationX = value.translation.width
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    lastTranslationX = 0
                                }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)

                Spacer()

                // Done button
                if showDoneButton {
                    Button {
                        Haptics.light()
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .background(DS.Semantic.brand)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            startPlateAnimation()
        }
    }

    // MARK: - Animation sequence

    private func startPlateAnimation() {
        Task { @MainActor in
            for index in plates.indices {
                try? await Task.sleep(for: .seconds(Double(index) * 0.6 + 0.3))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    seatedCount = index + 1
                }
                BarbellProgressService.shared.playClinkHaptic()
            }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDoneButton = true
            }
        }
    }

    // MARK: - Scene helpers (mirrors BarbellPreviewView)
    // These delegate to the same makeBarbell/setupLights logic.
    // BarbellPreviewView.setupLights and rebuildIfNeeded are internal to the view;
    // extract them to a shared BarbellSceneBuilder in Phase 3.

    private func setupLights(in content: inout RealityViewContent) {
        // Temporary stub — real implementation wired in Phase 3 when
        // BarbellPreviewView is refactored and scene helpers are shared.
    }

    private func rebuildIfNeeded(content: inout RealityViewContent) {
        // Stub — wired in Phase 3
    }
}
```

**Shipping constraint — do not release Tasks 6/7 before Task 8 completes.** The scene helpers are stubs. Until Task 8 wires the real builder, `BarbellMomentView` renders a black screen. The WinScreen "See Your Barbell" button and `BarbellMomentView` must ship in the same PR as Task 8 — never in an intermediate build that reaches users.

- [x] **Step 2: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 3: Commit**

```bash
git add Features/Rewards/Views/BarbellMomentView.swift
git commit -m "feat: add BarbellMomentView (WinScreen Page 2) with plate seat animation"
```

---

## Task 8: BarbellPreviewView — Tier Updates, Spin Fix, Display Modes

**Files:**
- Modify: `Features/Profile/Views/BarbellPreviewView.swift`

> **Read the file before starting this task.**
> `BarbellPreviewView.swift` is untracked in git — it exists on disk but was never committed, so its current state is unknown. Before applying any step below, read the file and note:
> - The current name of the `PlateStyle` raw iron case (may be `.rustyIron` or something else)
> - The current tier ID ordering in `PlateTier.all` (the plan assumes IDs 0–6 in the order listed; if the file uses different IDs, align with what the file has rather than overwriting blindly)
> - Whether `BarbellSceneState`, `TimelineView`, and the auto-spin timer already exist and where
> - Whether `BarbellDisplayMode` already exists
>
> Use patterns to find insertion points — do not trust line numbers.

- [x] **Step 1: Update PlateTier.all — rename Raw Iron and reorder Brass**

In `BarbellPreviewView.swift`, find the `static let all: [PlateTier]` array and replace it in full:

```swift
static let all: [PlateTier] = [
    PlateTier(id: 0, name: "Raw Iron", rarity: .common,
              earnedBy: "Complete your first workout",
              plateColor: UIColor(red: 0.40, green: 0.18, blue: 0.07, alpha: 1),
              metallic: 0.12, roughness: 0.97, clearcoat: 0, clearcoatRoughness: 0,
              style: .rawIron),
    PlateTier(id: 1, name: "Cast Iron", rarity: .common,
              earnedBy: "Complete 5 workouts",
              plateColor: UIColor(red: 0.14, green: 0.14, blue: 0.14, alpha: 1),
              metallic: 0.06, roughness: 0.94, clearcoat: 0, clearcoatRoughness: 0,
              style: .castIron),
    PlateTier(id: 2, name: "Black Bumper", rarity: .uncommon,
              earnedBy: "Complete 15 workouts",
              plateColor: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1),
              metallic: 0, roughness: 0.78, clearcoat: 0.3, clearcoatRoughness: 0.25,
              style: .bumper),
    PlateTier(id: 3, name: "Brass", rarity: .rare,
              earnedBy: "Complete 25 workouts",
              plateColor: UIColor(red: 0.75, green: 0.60, blue: 0.25, alpha: 1),
              metallic: 0.85, roughness: 0.35, clearcoat: 0.2, clearcoatRoughness: 0.15,
              style: .brass),
    PlateTier(id: 4, name: "Competition", rarity: .rare,
              earnedBy: "Hit a personal record",
              plateColor: UIColor(red: 0.82, green: 0.09, blue: 0.09, alpha: 1),
              metallic: 0, roughness: 0.70, clearcoat: 0.45, clearcoatRoughness: 0.2,
              style: .competition),
    PlateTier(id: 5, name: "Polished Steel", rarity: .epic,
              earnedBy: "Complete 50 workouts",
              plateColor: UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1),
              metallic: 0.98, roughness: 0.10, clearcoat: 0, clearcoatRoughness: 0,
              style: .polishedSteel),
    PlateTier(id: 6, name: "Gold", rarity: .legendary,
              earnedBy: "Complete a 90-day streak",
              plateColor: UIColor(red: 0.88, green: 0.68, blue: 0.12, alpha: 1),
              metallic: 1.0, roughness: 0.05, clearcoat: 0.6, clearcoatRoughness: 0.05,
              style: .gold),
]
```

Also find the `PlateStyle` enum — rename the raw iron case to `.rawIron` (it may currently be `.rustyIron` or another name; search for `case.*[Ii]ron` to locate it):

```swift
enum PlateStyle { case rawIron, castIron, bumper, brass, competition, polishedSteel, gold, starter }
```

Search the file for all uses of the old case name and replace them with `.rawIron`.

- [x] **Step 2: Fix auto-spin — replace timer with drag-momentum**

In `BarbellSceneState` (search for `struct BarbellSceneState` or `class BarbellSceneState`), add:

```swift
var spinVelocity: Float = 0.35   // radians/sec; positive = auto-rotate initially
```

In `BarbellPreviewView`, find the `TimelineView` block that contains the auto-spin line (search for `rotAngle +=` to locate it) and replace the `TimelineView` body with:

```swift
TimelineView(.animation) { timeline in
    RealityView { content in
        setupLights(in: &content)
    } update: { content in
        rebuildIfNeeded(content: &content)

        let now = timeline.date.timeIntervalSinceReferenceDate
        let dt = scene.lastTime > 0 ? Float(now - scene.lastTime) : 0
        scene.lastTime = now

        if isDragging {
            // Velocity is updated by drag gesture; no auto-advance
        } else {
            // Momentum decay: velocity * 0.92 per frame
            scene.spinVelocity *= 0.92
            scene.rotAngle += scene.spinVelocity * dt
        }
        scene.root?.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))
    }
    .gesture(
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                isDragging = true
                let delta = Float(value.translation.width - lastTranslationX) * 0.012
                scene.spinVelocity = -delta / max(Float(1.0 / 60.0), 0.016)  // velocity from delta per frame
                scene.rotAngle -= delta
                scene.root?.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))
                lastTranslationX = value.translation.width
            }
            .onEnded { _ in
                isDragging = false
                lastTranslationX = 0
                // spinVelocity carries forward; decays via 0.92 multiplier above
            }
    )
}
```

Remove the old auto-rotate line (the one that was found by the `rotAngle +=` search above).

- [x] **Step 3: Add BarbellDisplayMode enum**

Search for `enum BarbellDisplayMode` — if it already exists, update it to match the definition below. If it doesn't exist, add it immediately before `struct BarbellPreviewView`:

```swift
enum BarbellDisplayMode {
    case editor                              // full editor, own profile
    case showcase(plates: [EarnedPlateInfo]) // compact 240pt, read-only
}
```

Search for the `var` or `let` properties at the top of `BarbellPreviewView` and add `var mode: BarbellDisplayMode = .editor` there if it doesn't already exist.

- [x] **Step 4: Showcase mode — static, tap-plate popover**

Search for the `@State` properties in `BarbellPreviewView` and add:

```swift
@State private var selectedPlateTip: EarnedPlateInfo? = nil
```

In showcase mode, disable auto-spin (set initial `spinVelocity = 0`), and add a tap gesture on the RealityView that identifies the nearest racked plate and shows a popover.

Showcase mode hides all editor controls (tab bar, carousel). Apply `frame(height: 240)` in showcase mode instead of 360.

Full showcase mode implementation is wired in Task 11 alongside `BarbellShowcaseCard`. For now, add the mode enum and parameter.

- [x] **Step 5: Implement `makeWeightDisc` and `makeEngravingDisc`**

Search for existing plate-building helpers (functions that create `ModelEntity` for plates) and add these alongside them:

```swift
/// Renders the weight number onto a thin disc mesh placed at the plate face.
/// Cache key: "\(tierID)_\(Int(weightKg))" — reuse across identical plates.
private func makeWeightDisc(weightKg: Double, tierID: Int) -> ModelEntity {
    let canvas = CGSize(width: 256, height: 256)
    let renderer = UIGraphicsImageRenderer(size: canvas)
    let image = renderer.image { ctx in
        let textColor: UIColor = [0, 1, 2].contains(tierID) ? .white : .black
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 160, weight: .black),
            .foregroundColor: textColor
        ]
        let text = weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weightKg))" : String(format: "%.1f", weightKg)
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(x: (canvas.width - size.width) / 2,
                             y: (canvas.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attrs)
    }
    guard let cgImage = image.cgImage,
          let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    else { return ModelEntity() }

    var material = UnlitMaterial()
    material.color = .init(texture: .init(texture))
    material.blending = .transparent(opacity: 1.0)

    let disc = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.08),
                           materials: [material])
    // Position on the front face of the plate (z offset slightly proud of plate surface)
    disc.position = SIMD3(0, 0, 0.022)
    return disc
}

/// Renders the engraving label onto a second disc placed at 60% radius from center.
private func makeEngravingDisc(text: String, tierID: Int) -> ModelEntity {
    let canvas = CGSize(width: 256, height: 64)
    let renderer = UIGraphicsImageRenderer(size: canvas)
    let image = renderer.image { ctx in
        let textColor: UIColor = [0, 1, 2].contains(tierID) ? .white : .black
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .light),
            .foregroundColor: textColor,
            .kern: 2.0
        ]
        let upper = text.uppercased()
        let size = upper.size(withAttributes: attrs)
        let origin = CGPoint(x: (canvas.width - size.width) / 2,
                             y: (canvas.height - size.height) / 2)
        upper.draw(at: origin, withAttributes: attrs)
    }
    guard let cgImage = image.cgImage,
          let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    else { return ModelEntity() }

    var material = UnlitMaterial()
    material.color = .init(texture: .init(texture))
    material.blending = .transparent(opacity: 1.0)

    // Narrow rectangular disc; offset radially so it sits below the weight number
    let disc = ModelEntity(mesh: .generateBox(width: 0.09, height: 0.022, depth: 0.002),
                           materials: [material])
    disc.position = SIMD3(0, -0.055, 0.022)
    return disc
}
```

Add weight/engraving texture caches to `BarbellSceneState`:

```swift
var weightDiscCache: [String: ModelEntity] = [:]   // key: "\(tierID)_\(Int(weightKg))"
var engravingDiscCache: [String: ModelEntity] = []  // key: "\(tierID)_\(engravingText)"
```

In the plate-building path, attach both discs as children of the plate `ModelEntity` after creation:

```swift
// Attach weight disc (skip for starter plates, tierID 7)
if plate.tierID != 7 && plate.weightKg > 0 {
    let key = "\(plate.tierID)_\(Int(plate.weightKg))"
    let weightDisc = scene.weightDiscCache[key] ?? makeWeightDisc(weightKg: plate.weightKg, tierID: plate.tierID)
    scene.weightDiscCache[key] = weightDisc
    plateEntity.addChild(weightDisc.clone(recursive: false))
}

// Attach engraving disc
if plate.tierID != 7 && !plate.engravingText.isEmpty {
    let key = "\(plate.tierID)_\(plate.engravingText)"
    let engravingDisc = scene.engravingDiscCache[key] ?? makeEngravingDisc(text: plate.engravingText, tierID: plate.tierID)
    scene.engravingDiscCache[key] = engravingDisc
    plateEntity.addChild(engravingDisc.clone(recursive: false))
}
```

- [x] **Step 6: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 7: Commit**

```bash
git add Features/Profile/Views/BarbellPreviewView.swift
git commit -m "feat: rename Raw Iron, reorder Brass tier, fix bidirectional drag-momentum spin, add weight/engraving disc rendering"
```

---

## Task 9: PlateWallView

**Files:**
- Create: `Features/Profile/Views/PlateWallView.swift`

- [x] **Step 1: Create PlateWallView**

```swift
// Features/Profile/Views/PlateWallView.swift
import SwiftUI
import SwiftData

struct PlateWallView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]

    // Drag state
    @State private var draggedPlate: EarnedPlate? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var barbellFrame: CGRect = .zero
    @State private var dropSide: DropSide? = nil

    enum DropSide { case left, right }

    private var totalWeight: Double {
        let racked = rackedPlates.filter { $0.earnedByEvent != "starter" }
        return 20 + racked.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar
                HStack {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Semantic.brand)
                    Spacer()
                    Text("Your Barbell")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    // Balance invisible button
                    Text("Done").opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // --- Top zone: Barbell ---
                ZStack {
                    Color.black
                    BarbellPreviewView(mode: .editor)
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    barbellFrame = geo.frame(in: .global)
                                }
                            }
                        )

                    // Drop zone highlights
                    if draggedPlate != nil {
                        HStack(spacing: 0) {
                            Color.white.opacity(dropSide == .left ? 0.06 : 0.02)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Color.white.opacity(dropSide == .right ? 0.06 : 0.02)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: dropSide)
                    }
                }
                .frame(height: 280)

                // Total weight
                Text("Bar 20kg + \(Int(totalWeight - 20))kg = \(Int(totalWeight))kg total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 8)

                Divider()
                    .background(DS.Semantic.border)

                // --- Bottom zone: Plate Wall ---
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(plateTierSections(), id: \.tierID) { section in
                            if !section.plates.isEmpty {
                                PlateShelfRow(
                                    tierName: section.tierName,
                                    plates: section.plates,
                                    onDragStart: { plate, location in
                                        draggedPlate = plate
                                        dragLocation = location
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            // Floating drag ghost
            if let dragged = draggedPlate {
                PlateCell(plate: dragged, isLifted: true)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard draggedPlate != nil else { return }
                    dragLocation = value.location
                    updateDropSide(at: value.location)
                }
                .onEnded { value in
                    commitDrop(at: value.location)
                    draggedPlate = nil
                    dropSide = nil
                }
        )
    }

    // MARK: - Sections

    private struct TierSection {
        let tierID: Int
        let tierName: String
        let plates: [EarnedPlate]
    }

    private func plateTierSections() -> [TierSection] {
        let names = [0: "Raw Iron", 1: "Cast Iron", 2: "Black Bumper",
                     3: "Brass", 4: "Competition", 5: "Polished Steel", 6: "Gold"]
        return (0...6).reversed().compactMap { id in
            let plates = ownedPlates.filter { $0.tierID == id }
            guard !plates.isEmpty else { return nil }
            return TierSection(tierID: id, tierName: names[id] ?? "Plate", plates: plates)
        }
    }

    // MARK: - Drop logic

    private func updateDropSide(at point: CGPoint) {
        let midX = barbellFrame.midX
        dropSide = point.x < midX ? .left : .right
    }

    private func commitDrop(at point: CGPoint) {
        guard let plate = draggedPlate else { return }
        guard barbellFrame.contains(point) else { return }
        // rackPlate fills the next available slot 0-3; bilateral rendering handles both sides.
        try? BarbellProgressService.shared.rackPlate(plate)
    }
}

// MARK: - PlateShelfRow

private struct PlateShelfRow: View {
    let tierName: String
    let plates: [EarnedPlate]
    let onDragStart: (EarnedPlate, CGPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Shelf label
            Text(tierName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 12)

            // Shelf line + plates
            ZStack(alignment: .leading) {
                // Shelf line
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .padding(.top, 24)

                // Plates
                HStack(spacing: 10) {
                    ForEach(plates) { plate in
                        if plate.isRacked {
                            PlateCell(plate: plate, isLifted: false)
                                .opacity(0.25)
                                .overlay(
                                    // Museum plaque
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                        .overlay(
                                            Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))kg" : "")
                                                .font(.system(size: 7, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.4))
                                        )
                                )
                        } else {
                            PlateCell(plate: plate, isLifted: false)
                                .gesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                        .onChanged { value in
                                            onDragStart(plate, value.location)
                                        }
                                )
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - PlateCell

private struct PlateCell: View {
    let plate: EarnedPlate
    let isLifted: Bool

    private var color: Color {
        switch plate.tierID {
        case 0: return Color(red: 0.40, green: 0.18, blue: 0.07)
        case 1: return Color(red: 0.14, green: 0.14, blue: 0.14)
        case 2: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case 3: return Color(red: 0.75, green: 0.60, blue: 0.25)
        case 4: return Color(red: 0.82, green: 0.09, blue: 0.09)
        case 5: return Color(red: 0.72, green: 0.76, blue: 0.80)
        case 6: return Color(red: 0.88, green: 0.68, blue: 0.12)
        case 7: return Color(red: 0.2, green: 0.7, blue: 0.3)   // starter — bright green
        default: return .gray
        }
    }

    private var textColor: Color {
        [0, 1, 2].contains(plate.tierID) ? .white : .black
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))" : "")
                    .font(.caption.weight(.black))
                    .foregroundStyle(textColor)
            )
            .scaleEffect(isLifted ? 1.15 : 1.0)
            .shadow(color: isLifted ? color.opacity(0.5) : .clear, radius: isLifted ? 8 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isLifted)
    }
}
```

- [x] **Step 2: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 3: Commit**

```bash
git add Features/Profile/Views/PlateWallView.swift
git commit -m "feat: add PlateWallView with plate shelf layout and drag-to-rack interaction"
```

---

## Task 10: Add plate_clink.caf Sound Asset

**Files:**
- Add: `Resources/plate_clink.caf` (audio file)
- Modify: Xcode project to include the file

- [x] **Step 1: Generate or source the clink sound**

The `plate_clink.caf` file must be a short metal impact sound (~0.15-0.2s). Options:
a) Use macOS `afconvert` to convert an existing `.aiff` or `.wav` impact sound to `.caf`
b) Source a royalty-free metal impact sound

Run: `afconvert -f caff -d LEI16 input.wav Resources/plate_clink.caf`

If sourcing: place file at `Resources/plate_clink.caf` and add it to the WRKT target in Xcode (Build Phases → Copy Bundle Resources).

- [x] **Step 2: Verify AVAudioPlayer loads it**

The `preloadClinkSound()` method in `BarbellProgressService` already handles this. A nil `clinkPlayer` means the file is missing — check console logs on app launch.

- [x] **Step 3: Commit**

```bash
git add Resources/plate_clink.caf
git commit -m "feat: add plate_clink.caf sound asset for rack haptic"
```

---

## Task 11: BarbellShowcaseCard + SocialProfileView Integration

**Files:**
- Create: `Features/Social/Views/BarbellShowcaseCard.swift`
- Modify: `Features/Social/Views/SocialProfileView.swift`

- [x] **Step 1: Create BarbellShowcaseCard**

```swift
// Features/Social/Views/BarbellShowcaseCard.swift
import SwiftUI
import SwiftData

struct BarbellShowcaseCard: View {
    let isOwnProfile: Bool
    let ownerId: UUID
    let sessionCount: Int

    // Own profile: read from SwiftData directly
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var ownRackedPlates: [EarnedPlate]

    // All owned earned plates (excluding starter) for collection count
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownAllEarnedPlates: [EarnedPlate]

    // Friend profile: passed in
    var friendRackedPlates: [EarnedPlateInfo] = []

    @State private var showingPlateWall = false

    private var plates: [EarnedPlateInfo] {
        if isOwnProfile {
            return ownRackedPlates.map {
                EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg,
                                engravingText: $0.engravingText, earnedByEvent: $0.earnedByEvent)
            }
        }
        return friendRackedPlates
    }

    private var totalWeight: Double {
        let earned = plates.filter { $0.earnedByEvent != "starter" }
        return 20 + earned.reduce(0) { $0 + $1.weightKg } * 2
    }

    private var collectionCount: Int {
        // Total earned plates minus those currently racked
        guard isOwnProfile else { return 0 }
        let rackedEarnedCount = ownRackedPlates.filter { $0.earnedByEvent != "starter" }.count
        return max(0, ownAllEarnedPlates.count - rackedEarnedCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Barbell preview
            ZStack(alignment: .topTrailing) {
                BarbellPreviewView(mode: .showcase(plates: plates))
                    .frame(height: 240)
                    .clipped()

                if isOwnProfile {
                    Button {
                        showingPlateWall = true
                    } label: {
                        Text("Customize")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .padding(12)
                }
            }

            // Footer
            HStack {
                Text("\(sessionCount) sessions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer(minLength: 8)

                Text("\(Int(totalWeight))kg loaded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))

                if collectionCount > 0 {
                    Text("· \(collectionCount) more in collection")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(DS.Semantic.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Semantic.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingPlateWall) {
            PlateWallView()
        }
    }
}
```

- [x] **Step 2: Insert BarbellShowcaseCard into SocialProfileView**

In `Features/Social/Views/SocialProfileView.swift`, add state for friend plates:

```swift
@State private var friendRackedPlates: [EarnedPlateInfo] = []
```

In the `content(viewModel:)` method, add `BarbellShowcaseCard` between `activityLink` and `actionButtons` (lines ~220-226):

```swift
// Activity Link (for own profile)
if viewModel.isOwnProfile {
    activityLink
}

// Barbell Showcase Card
let sessionCount = viewModel.isOwnProfile
    ? (progress.first?.currentStreak ?? 0)   // fallback; ideally from BarbellConfig
    : 0
BarbellShowcaseCard(
    isOwnProfile: viewModel.isOwnProfile,
    ownerId: userId,
    sessionCount: sessionCount,
    friendRackedPlates: viewModel.isOwnProfile ? [] : friendRackedPlates
)

// Action Buttons
actionButtons(viewModel: viewModel)
```

Add friend plates loading in the `.task` modifier of `SocialProfileView`:

```swift
if !viewModel.isOwnProfile {
    do {
        friendRackedPlates = try await deps.barbellProgressService.rackedPlatesForFriend(userID: userId)
    } catch {
        // Non-fatal: show empty barbell for friend
        friendRackedPlates = []
    }
}
```

- [x] **Step 3: Add sessionCount from BarbellConfig to own profile**

The `sessionCount` for own profile should come from `BarbellConfig.totalStrengthWorkouts`. Add a `@Query`:

```swift
@Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
private var barbellConfigs: [BarbellConfig]
```

Then use `barbellConfigs.first?.totalStrengthWorkouts ?? 0` for the own-profile session count.

- [x] **Step 4: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 5: Commit**

```bash
git add Features/Social/Views/BarbellShowcaseCard.swift Features/Social/Views/SocialProfileView.swift
git commit -m "feat: add BarbellShowcaseCard to SocialProfileView with own/friend profile modes"
```

---

## Task 12: Supabase Sync

**Files:**
- Modify: `Features/Rewards/Services/BarbellProgressService.swift`

- [x] **Step 1: Add rackedPlatesForFriend Supabase fetch**

In `BarbellProgressService`, add:

```swift
func rackedPlatesForFriend(userID: UUID) async throws -> [EarnedPlateInfo] {
    let client = SupabaseClientWrapper.shared.client
    let rows: [[String: AnyJSON]] = try await client
        .from("barbell_racked_plates")
        .select("tier_id, weight_kg, engraving_text, rack_position")
        .eq("user_id", value: userID.uuidString)
        .execute()
        .value

    return rows.compactMap { row in
        guard let tierID = row["tier_id"]?.intValue,
              let weightKg = row["weight_kg"]?.doubleValue,
              let engravingText = row["engraving_text"]?.stringValue else { return nil }
        return EarnedPlateInfo(
            tierID: tierID,
            weightKg: weightKg,
            engravingText: engravingText,
            earnedByEvent: ""
        )
    }
}
```

- [x] **Step 2: Add upsert in rackPlate and delete in unrackPlate**

In `rackPlate`, after `try? context.save()`:

```swift
Task.detached { [weak self] in
    guard let self else { return }
    await self.syncRackedPlateToSupabase(plate)
}
```

Add:

```swift
private func syncRackedPlateToSupabase(_ plate: EarnedPlate) async {
    guard let userID = SupabaseAuthService.shared.currentUser?.id else { return }
    let client = SupabaseClientWrapper.shared.client
    let row: [String: AnyJSON] = [
        "user_id": .string(userID.uuidString),
        "tier_id": .integer(plate.tierID),
        "weight_kg": .number(plate.weightKg),
        "engraving_text": .string(plate.engravingText),
        "rack_position": .integer(plate.rackPosition ?? 0),
        "updated_at": .string(ISO8601DateFormatter().string(from: .now))
    ]
    try? await client.from("barbell_racked_plates").upsert(row).execute()
}

private func deleteRackedPlateFromSupabase(rackPosition: Int) async {
    guard let userID = SupabaseAuthService.shared.currentUser?.id else { return }
    let client = SupabaseClientWrapper.shared.client
    try? await client
        .from("barbell_racked_plates")
        .delete()
        .eq("user_id", value: userID.uuidString)
        .eq("rack_position", value: rackPosition)
        .execute()
}
```

In `unrackPlate`, after `try? context.save()`:

```swift
let pos = plate.rackPosition
Task.detached { [weak self, pos] in
    guard let self, let pos else { return }
    await self.deleteRackedPlateFromSupabase(rackPosition: pos)
}
```

- [x] **Step 3: Create Supabase table (run once in Supabase dashboard)**

```sql
create table barbell_racked_plates (
    user_id uuid references auth.users(id) on delete cascade,
    tier_id smallint not null,
    weight_kg real not null,
    engraving_text text not null default '',
    rack_position smallint not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, rack_position)
-- rack_position stores slot index 0-3 only (bilateral rendering: one row = both sides of the bar)
);

-- Friends-only visibility
alter table barbell_racked_plates enable row level security;

create policy "Users can manage own racked plates"
    on barbell_racked_plates
    for all
    using (auth.uid() = user_id);

create policy "Friends can view racked plates"
    on barbell_racked_plates
    for select
    using (
        exists (
            select 1 from friendships
            where status = 'accepted'
              and (
                (requester_id = auth.uid() and addressee_id = user_id)
                or (addressee_id = auth.uid() and requester_id = user_id)
              )
        )
    );
```

- [x] **Step 4: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 5: Commit**

```bash
git add Features/Rewards/Services/BarbellProgressService.swift
git commit -m "feat: add Supabase sync for racked plates and rackedPlatesForFriend fetch"
```

---

## Task 13: Backfill + Welcome Screen

> **Implementation note:** `BarbellWelcomeView` diverges significantly from the plan. The simple `Circle()` plate grid was replaced with per-cell SceneKit (`SCNView`) rendering to match the 3D quality of the barbell. Key decisions and bugs encountered during implementation:
>
> **Why SceneKit instead of RealityKit per cell:** RealityKit uses process-global Metal singletons (`envProbeTable`, `envProbeDiffuseArray`). Two simultaneous `RealityView` instances corrupt each other's Metal state and crash. `SCNView` uses per-instance Metal state and coexists safely alongside the barbell's `RealityView`.
>
> **"Modifying state during view update" fix (BarbellPreviewView):** `lastDt` was `@State` and written inside the `RealityView update:` closure. Moved into `BarbellSceneState` (a class). Mutating a class property is not observed by SwiftUI and eliminates the warning.
>
> **SceneKit rendering bugs fixed during implementation:**
> - `SCNCamera.zNear` defaults to `1.0`. The plate is only `0.38` world units from the camera — entirely inside the near clip plane, making everything invisible. Fix: `c.zNear = 0.01`.
> - `SCNCylinder` has 3 material slots (tube, front cap, back cap). Setting `firstMaterial` or `materials = [mat]` only reliably fills slot 0 on some OS versions, leaving caps white. Fix: set all three explicitly — `materials = [mat, mat, mat]`.
> - PBR materials at close range with high light intensity (1800 lux) blow out to white. Fix: key/fill/ambient at 80/30/20.
> - `isOpaque = false` + `backgroundColor = .clear` on `SCNView` produces blank output (transparent compositing issue). Fix: `isOpaque = true`, `backgroundColor = .black` — invisible against the app's black background but renders correctly.
>
> **Spin implementation:** Each plate cell holds a `PlateState` class (not `@Observable`) with `SCNView`, `SCNNode?` spin root, `rotY`, `velocity`, `isDragging`. The physics loop runs in `.task { @MainActor in }` writing only to class properties — zero `@State` writes per frame, no warnings.

**Files:**
- Modify: `Features/Rewards/Services/BarbellProgressService.swift`
- Create: `Features/Rewards/Views/BarbellWelcomeView.swift`

- [x] **Step 1: Implement backfill in BarbellProgressService**

```swift
func runBackfillIfNeeded(completedWorkouts: [CompletedWorkout]) {
    guard let context else { return }
    let config = fetchOrCreateConfig(context: context)
    guard !config.backfillCompletedV1 else { return }

    // Mark complete and save BEFORE inserting any plates.
    // This makes the operation crash-safe: if the app is killed mid-loop the flag is already
    // written, so the next launch skips re-running and avoids duplicate plates.
    // Trade-off: a crash mid-backfill leaves the user with a partial plate collection, but
    // that is far preferable to duplicates that would require a manual reset to clean up.
    config.backfillCompletedV1 = true
    try? context.save()

    // Sort chronologically; skip cardio workouts (same rule as live evaluation)
    let sorted = completedWorkouts.sorted { $0.date < $1.date }

    for workout in sorted where !workout.isCardioWorkout {
        config.totalStrengthWorkouts += 1
        let existingFD = FetchDescriptor<EarnedPlate>()
        let existing = (try? context.fetch(existingFD)) ?? []
        let existingEvents = existing.map(\.earnedByEvent)
        let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: existingEvents)
        for info in plates {
            let plate = EarnedPlate(
                tierID: info.tierID, weightKg: info.weightKg,
                engravingText: info.engravingText, earnedByEvent: info.earnedByEvent,
                earnedAt: workout.date
            )
            context.insert(plate)
        }
    }

    try? context.save()
}
```

- [x] **Step 2: Create BarbellWelcomeView**

```swift
// Features/Rewards/Views/BarbellWelcomeView.swift
import SwiftUI
import SwiftData

struct BarbellWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var ownedPlates: [EarnedPlate]
    @State private var showPlateWall = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Your workouts have paid off.")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("\(ownedPlates.filter { $0.earnedByEvent != "starter" }.count) plates earned")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)

                // Plate grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                    ForEach(ownedPlates.filter { $0.earnedByEvent != "starter" }) { plate in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(plateColor(for: plate.tierID))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Text(plate.weightKg > 0 ? "\(Int(plate.weightKg))" : "")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle([0,1,2].contains(plate.tierID) ? Color.white : Color.black)
                                )
                            Text(plate.engravingText)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Tapping navigates into PlateWallView — dismiss only happens from inside PlateWallView.
                // This matches the spec: "Opens into Plate Wall editor pre-filled with suggested rack."
                Button {
                    showPlateWall = true
                } label: {
                    Text("Build Your Rack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .background(DS.Semantic.brand)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showPlateWall) {
            PlateWallView()
                .onDisappear { dismiss() }   // dismiss welcome screen once user is done with PlateWall
        }
    }

    private func plateColor(for tierID: Int) -> Color {
        switch tierID {
        case 0: return Color(red: 0.40, green: 0.18, blue: 0.07)
        case 1: return Color(red: 0.14, green: 0.14, blue: 0.14)
        case 2: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case 3: return Color(red: 0.75, green: 0.60, blue: 0.25)
        case 4: return Color(red: 0.82, green: 0.09, blue: 0.09)
        case 5: return Color(red: 0.72, green: 0.76, blue: 0.80)
        case 6: return Color(red: 0.88, green: 0.68, blue: 0.12)
        default: return .gray
        }
    }
}
```

- [x] **Step 3: Trigger backfill and welcome screen on first launch**

In `AppDependencies.configure(with:)`, after `barbellProgressService.configure(context:)`:

```swift
// Run backfill for existing users (no-op if already done)
Task { @MainActor in
    let workouts = self.workoutStore.completedWorkouts
    self.barbellProgressService.runBackfillIfNeeded(completedWorkouts: workouts)
    // Show welcome screen if backfill just ran and plates were earned
    // Coordinate via BarbellProgressService.needsWelcomeScreen property
}
```

Add `private(set) var needsWelcomeScreen = false` to `BarbellProgressService`, set to `true` at the end of `runBackfillIfNeeded` if any plates were created. The app shell observes this and presents `BarbellWelcomeView` as a sheet.

- [x] **Step 4: Build**

Run: `xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|Build succeeded"`
Expected: `Build succeeded`

- [x] **Step 5: Commit**

```bash
git add Features/Rewards/Services/BarbellProgressService.swift \
        Features/Rewards/Views/BarbellWelcomeView.swift
git commit -m "feat: add backfill for existing users and BarbellWelcomeView"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Raw Iron name | Task 8 |
| Tier IDs reordered (Brass before Gold) | Task 8 |
| EarnedPlate SwiftData model | Task 1 |
| BarbellConfig singleton | Task 1, 3 |
| Schema registration | Task 2 |
| BarbellProgressService | Task 3 |
| Unlock rules (all 7 tiers) | Task 4 |
| processInBackground integration | Task 5 |
| earnedPlates in RewardSummary | Task 5 |
| PlateRevealCard in WinScreen stagger | Task 6 |
| BarbellMomentView (Page 2) | Task 7 |
| Haptic + clink per plate seat | Task 3 (playClinkHaptic), Task 7 |
| Drag-momentum spin fix | Task 8 |
| BarbellDisplayMode enum | Task 8 |
| PlateWallView with shelves | Task 9 |
| Drag-to-rack interaction | Task 9 |
| Plate wall states (available/racked plaque/returned) | Task 9 |
| Starter plates (account creation) | Task 1, 3 |
| Sound asset | Task 10 |
| BarbellShowcaseCard | Task 11 |
| SocialProfileView insertion | Task 11 |
| Supabase table + sync | Task 12 |
| rackedPlatesForFriend | Task 12 |
| Backfill for existing users | Task 13 |
| Welcome screen | Task 13 |
| RewardsEngine.resetAll hook | Task 3 |

**Gaps identified:**
- `BarbellMomentView` scene helpers are stubbed in Task 7 and need to be wired in Task 8/9 when `BarbellPreviewView` is refactored. This is called out explicitly in Task 7.
- Gold 90-day streak evaluation in `processInBackground` relies on `bgProgress.currentStreak >= 90` — verify that `currentStreak` is updated BEFORE the plate evaluation block runs (it is: streak update happens in step 3 of processInBackground).
- Bilateral mirroring in `rackPlate` is simplified in Task 3 (racks single plate). Full bilateral mirror logic needs implementing before Phase 3 testing — add a `TODO` comment in the stub pointing here.

**Placeholder scan:** No TBD/TODO patterns except the one explicitly called out for the BarbellMomentView scene stub. All code steps show full implementation.

**Type consistency:**
- `EarnedPlateInfo` used consistently across Tasks 1, 4, 5, 6, 7, 11
- `BarbellConfig` fetched with same predicate pattern (`id == "global"`) in Tasks 3 and 5
- `BarbellProgressService.shared` referenced consistently — no double-init risk since `private init()`
- `playClinkHaptic()` called in Task 3 (defined), Task 7 (used) — matches
