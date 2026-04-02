import Foundation

enum BarbellUnlockRules {

    // Tier rarity order for sorting results (higher = returned first)
    private static let rarityOrder: [Int: Int] = [
        6: 5,   // Gold: legendary
        5: 4,   // Polished Steel: epic
        4: 3,   // Competition: rare
        3: 3,   // Brass: rare
        2: 2,   // Black Bumper: uncommon
        1: 1,   // Cast Iron: common
        0: 0    // Raw Iron: common
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

        // Rule: PR detected: Competition plate (one per PR workout, key includes workout ID
        // so multiple workouts can each earn a Competition plate without blocking each other)
        if (workout.detectedPRCount ?? 0) > 0 {
            results.append(EarnedPlateInfo(
                tierID: 4,
                weightKg: 20,
                engravingText: "Personal Record",
                earnedByEvent: "pr_\(workout.id.uuidString.prefix(8))"
            ))
        }

        // Rule: Milestone thresholds (one-time each)
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

        // Rule: Raw Iron early plates (max 4 total)
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
