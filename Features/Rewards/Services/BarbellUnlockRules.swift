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
        let existingEventSet = Set(existingEvents)

        for lift in firstTrackedLiftTypes(in: workout) {
            let event = liftFirstEventKey(for: lift.id)
            guard !existingEventSet.contains(event) else { continue }
            results.append(EarnedPlateInfo(
                tierID: 0,
                weightKg: 5,
                engravingText: lift.engravingText,
                earnedByEvent: event,
                liftTypeID: lift.id
            ))
        }

        // Rule: PR detected: Competition plate (one per PR workout, key includes workout ID
        // so multiple workouts can each earn a Competition plate without blocking each other)
        if (workout.detectedPRCount ?? 0) > 0 {
            let fullEvent = prEventKey(for: workout.id)
            let legacyEvent = legacyPREventKey(for: workout.id)
            if !existingEvents.contains(fullEvent) && !existingEvents.contains(legacyEvent) {
                results.append(EarnedPlateInfo(
                    tierID: 4,
                    weightKg: 20,
                    engravingText: "Personal Record",
                    earnedByEvent: fullEvent
                ))
            }
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

    static func evaluateSeasonalCosmetics(
        workout: CompletedWorkout,
        config: BarbellConfig,
        existingCosmeticUnlockIDs: [String],
        catalog: BarbellCosmeticCatalog = .current
    ) -> [BarbellCosmeticUnlockDraft] {
        guard let item = catalog.activeSeasonalItem(for: workout.date) else { return [] }
        guard !existingCosmeticUnlockIDs.contains(item.id) else { return [] }
        guard let target = item.seasonalWorkoutTarget, target <= 1 else { return [] }

        return [
            BarbellCosmeticUnlockDraft(
                cosmeticID: item.id,
                unlockedAt: workout.date,
                source: .seasonal,
                sourceWorkoutID: workout.id.uuidString,
                catalogVersion: catalog.version
            )
        ]
    }

    static func prEventKey(for workoutID: UUID) -> String {
        "pr_\(workoutID.uuidString)"
    }

    static func legacyPREventKey(for workoutID: UUID) -> String {
        "pr_\(workoutID.uuidString.prefix(8))"
    }

    static func liftFirstEventKey(for liftTypeID: String) -> String {
        "lift_first_\(liftTypeID)"
    }

    static func firstTrackedLiftTypes(in workout: CompletedWorkout) -> [TrackedLiftType] {
        var found: [TrackedLiftType] = []
        var seen = Set<String>()

        for entry in workout.entries {
            guard entry.sets.contains(where: { $0.tag == .working && $0.isCompleted }) else { continue }
            let searchable = "\(entry.exerciseID) \(entry.exerciseName) \(entry.muscleGroups.joined(separator: " "))"
                .lowercased()
            guard let lift = TrackedLiftType.matching(searchable) else { continue }
            guard seen.insert(lift.id).inserted else { continue }
            found.append(lift)
        }

        return found
    }

    static func isFreshRewardEvent(
        occurredAt: Date,
        now: Date = .now,
        source: BarbellRewardPresentationSource
    ) -> Bool {
        source == .liveWorkoutCompletion && occurredAt > now.addingTimeInterval(-30)
    }

    static func makePresentationQueue(
        events: [BarbellRewardEvent],
        occurredAt: Date,
        now: Date = .now,
        source: BarbellRewardPresentationSource
    ) -> BarbellRewardPresentationQueue {
        guard isFreshRewardEvent(occurredAt: occurredAt, now: now, source: source) else {
            return BarbellRewardPresentationQueue(primary: nil, compactEvents: [])
        }

        let sorted = events.sorted {
            let lhs = presentationPriority(for: $0.kind)
            let rhs = presentationPriority(for: $1.kind)
            if lhs == rhs { return $0.occurredAt < $1.occurredAt }
            return lhs < rhs
        }
        return BarbellRewardPresentationQueue(
            primary: sorted.first,
            compactEvents: Array(sorted.dropFirst())
        )
    }

    private static func presentationPriority(for kind: BarbellRewardEventKind) -> Int {
        switch kind {
        case .newPlate: return 0
        case .tierUp: return 1
        case .cosmeticUnlock: return 2
        case .setBonus: return 3
        case .personalRecord: return 4
        case .agingMilestone: return 5
        }
    }
}

struct TrackedLiftType: Equatable, Sendable {
    let id: String
    let engravingText: String
    private let keywords: [String]

    static let all: [TrackedLiftType] = [
        TrackedLiftType(id: "squat", engravingText: "Squat", keywords: ["squat", "leg press"]),
        TrackedLiftType(id: "bench-press", engravingText: "Bench Press", keywords: ["bench press", "chest press"]),
        TrackedLiftType(id: "deadlift", engravingText: "Deadlift", keywords: ["deadlift", "romanian deadlift", "rdl"]),
        TrackedLiftType(id: "overhead-press", engravingText: "Overhead Press", keywords: ["overhead press", "shoulder press", "military press", "ohp"]),
        TrackedLiftType(id: "row", engravingText: "Row", keywords: ["row"])
    ]

    static func matching(_ text: String) -> TrackedLiftType? {
        all.first { lift in
            lift.keywords.contains { text.contains($0) }
        }
    }
}

enum BarbellPlateProjectionRules {
    static func rebuildProjection(
        for plate: EarnedPlate,
        workouts: [CompletedWorkout],
        now: Date = .now
    ) -> BarbellPlateProjection {
        let liftTypeID = BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID)
        let relatedWorkouts = workouts
            .filter { !$0.isCardioWorkout }
            .filter { workoutMatches($0, liftTypeID: liftTypeID) }
            .sorted { $0.date < $1.date }

        let workoutCount = relatedWorkouts.count
        let prCount = relatedWorkouts.filter { ($0.detectedPRCount ?? 0) > 0 }.count
        let firstEarnedAt = min(plate.effectiveFirstEarnedAt, plate.earnedAt)
        let lastUsedAt = relatedWorkouts.last?.date
        let aging = agingCounters(for: relatedWorkouts, liftTypeID: liftTypeID)
        let tier = projectedTier(workoutCount: workoutCount, prCount: prCount)
        let drafts = eventDrafts(
            plate: plate,
            tier: tier,
            relatedWorkouts: relatedWorkouts,
            firstEarnedAt: firstEarnedAt
        )

        return BarbellPlateProjection(
            plateID: plate.id,
            liftTypeID: liftTypeID,
            currentTier: tier,
            workoutsUsedCount: workoutCount,
            prCount: prCount,
            chalkUseCount: aging.chalk,
            gripWearCount: aging.grip,
            pressUseCount: aging.press,
            firstEarnedAt: firstEarnedAt,
            lastUsedAt: lastUsedAt,
            eventDrafts: drafts
        )
    }

    static func projectedTier(workoutCount: Int, prCount: Int) -> BarbellPlateProgressionTier {
        if workoutCount >= 50 && prCount >= 3 { return .gold }
        if prCount >= 1 { return .chrome }
        if workoutCount >= 10 { return .steel }
        return .iron
    }

    static func stableEventKey(
        plateID: String,
        kind: BarbellPlateEvent.Kind,
        workoutID: String?,
        tier: BarbellPlateProgressionTier? = nil,
        milestoneID: String? = nil,
        occurredAt: Date,
        calendar: Calendar = .init(identifier: .gregorian)
    ) -> String {
        let day = calendar.startOfDay(for: occurredAt).timeIntervalSince1970
        return [
            plateID,
            kind.rawValue,
            workoutID ?? "no_workout",
            tier?.rawValue ?? "no_tier",
            milestoneID ?? "no_milestone",
            String(Int(day))
        ].joined(separator: "|")
    }

    private static func workoutMatches(_ workout: CompletedWorkout, liftTypeID: String?) -> Bool {
        guard !BarbellPlateProgressionScope.isGlobal(liftTypeID) else { return true }
        guard let liftTypeID, !liftTypeID.isEmpty else { return true }
        return workout.entries.contains { entryMatchesLiftType($0, liftTypeID: liftTypeID) }
    }

    private static func matchingEntries(in workout: CompletedWorkout, liftTypeID: String?) -> [WorkoutEntry] {
        guard !BarbellPlateProgressionScope.isGlobal(liftTypeID) else { return workout.entries }
        guard let liftTypeID, !liftTypeID.isEmpty else { return workout.entries }
        return workout.entries.filter { entryMatchesLiftType($0, liftTypeID: liftTypeID) }
    }

    private static func entryMatchesLiftType(_ entry: WorkoutEntry, liftTypeID: String) -> Bool {
        let normalizedLiftTypeID = normalizeLiftTypeID(liftTypeID)
        if normalizeLiftTypeID(entry.exerciseID) == normalizedLiftTypeID ||
            normalizeLiftTypeID(entry.exerciseName) == normalizedLiftTypeID {
            return true
        }

        let searchable = "\(entry.exerciseID) \(entry.exerciseName) \(entry.muscleGroups.joined(separator: " "))"
            .lowercased()
        return TrackedLiftType.matching(searchable)?.id == normalizedLiftTypeID
    }

    private static func agingCounters(
        for workouts: [CompletedWorkout],
        liftTypeID: String?
    ) -> (chalk: Int, grip: Int, press: Int) {
        var chalk = 0
        var grip = 0
        var press = 0

        for workout in workouts {
            let entries = matchingEntries(in: workout, liftTypeID: liftTypeID)
            let didWork = entries.contains { entry in
                entry.sets.contains { $0.tag == .working && $0.isCompleted }
            }
            guard didWork else { continue }

            let names = entries.map { "\($0.exerciseID) \($0.exerciseName)".lowercased() }.joined(separator: " ")
            if names.contains("squat") || names.contains("deadlift") {
                chalk += 1
            }
            if names.contains("deadlift") || names.contains("row") {
                grip += 1
            }
            if names.contains("bench") || names.contains("ohp") || names.contains("overhead press") || names.contains("press") {
                press += 1
            }
        }

        return (chalk, grip, press)
    }

    private static func eventDrafts(
        plate: EarnedPlate,
        tier: BarbellPlateProgressionTier,
        relatedWorkouts: [CompletedWorkout],
        firstEarnedAt: Date
    ) -> [BarbellPlateEventDraft] {
        var drafts: [BarbellPlateEventDraft] = [
            BarbellPlateEventDraft(
                stableKey: stableEventKey(
                    plateID: plate.id,
                    kind: .earned,
                    workoutID: plate.sourceWorkoutID,
                    occurredAt: firstEarnedAt
                ),
                plateID: plate.id,
                kind: .earned,
                occurredAt: firstEarnedAt,
                workoutID: plate.sourceWorkoutID,
                tier: .iron,
                milestoneID: nil,
                summary: plate.engravingText.isEmpty ? "Plate earned" : "\(plate.engravingText) earned",
                isSilent: true
            )
        ]

        for reachedTier in BarbellPlateProgressionTier.allCases where reachedTier.rank > BarbellPlateProgressionTier.iron.rank && reachedTier.rank <= tier.rank {
            guard reachedTier.rank <= BarbellPlateProgressionTier.gold.rank else { continue }
            let occurredAt = tierReachedDate(for: reachedTier, in: relatedWorkouts) ?? firstEarnedAt
            drafts.append(BarbellPlateEventDraft(
                stableKey: stableEventKey(
                    plateID: plate.id,
                    kind: .tieredUp,
                    workoutID: nil,
                    tier: reachedTier,
                    occurredAt: occurredAt
                ),
                plateID: plate.id,
                kind: .tieredUp,
                occurredAt: occurredAt,
                workoutID: nil,
                tier: reachedTier,
                milestoneID: nil,
                summary: "Reached \(reachedTier.rawValue.capitalized)",
                isSilent: true
            ))
        }

        for workout in relatedWorkouts where (workout.detectedPRCount ?? 0) > 0 {
            drafts.append(BarbellPlateEventDraft(
                stableKey: stableEventKey(
                    plateID: plate.id,
                    kind: .personalRecord,
                    workoutID: workout.id.uuidString,
                    occurredAt: workout.date
                ),
                plateID: plate.id,
                kind: .personalRecord,
                occurredAt: workout.date,
                workoutID: workout.id.uuidString,
                tier: nil,
                milestoneID: nil,
                summary: "Personal record",
                isSilent: true
            ))
        }

        for milestone in [10, 50] where relatedWorkouts.count >= milestone {
            let occurredAt = relatedWorkouts[milestone - 1].date
            drafts.append(BarbellPlateEventDraft(
                stableKey: stableEventKey(
                    plateID: plate.id,
                    kind: .milestoneVolume,
                    workoutID: nil,
                    milestoneID: "workouts_\(milestone)",
                    occurredAt: occurredAt
                ),
                plateID: plate.id,
                kind: .milestoneVolume,
                occurredAt: occurredAt,
                workoutID: nil,
                tier: nil,
                milestoneID: "workouts_\(milestone)",
                summary: "\(milestone) workouts",
                isSilent: true
            ))
        }

        return drafts
    }

    private static func tierReachedDate(
        for tier: BarbellPlateProgressionTier,
        in workouts: [CompletedWorkout]
    ) -> Date? {
        switch tier {
        case .iron:
            return workouts.first?.date
        case .steel:
            return workouts.count >= 10 ? workouts[9].date : nil
        case .chrome:
            return workouts.first(where: { ($0.detectedPRCount ?? 0) > 0 })?.date
        case .gold:
            let prWorkouts = workouts.filter { ($0.detectedPRCount ?? 0) > 0 }
            guard workouts.count >= 50, prWorkouts.count >= 3 else { return nil }
            return max(workouts[49].date, prWorkouts[2].date)
        case .obsidian, .cosmic:
            return nil
        }
    }

    private static func normalizeLiftTypeID(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
