// Features/Rewards/Models/BarbellModels.swift
import Foundation
import SwiftData

// MARK: - EarnedPlate (@Model)

@Model final class EarnedPlate {
    @Attribute(.unique) var id: String
    var tierID: Int          // PlateTier.id; 7 = starter plate
    var weightKg: Double
    var engravingText: String
    var earnedAt: Date
    var earnedByEvent: String  // e.g. "first_workout", "pr_a1b2c3d4", "strength_milestone_5", "starter"
    var sourceWorkoutID: String?
    var isRacked: Bool
    var rackPosition: Int?     // 0-3 = slot index; bilateral rendering: one row = both sides of bar
    var displayOrder: Int      // earnedAt unix timestamp for sorting
    var liftTypeID: String? = nil
    var currentTierRaw: String = "iron"
    var workoutsUsedCount: Int = 0
    var prCount: Int = 0
    var chalkUseCount: Int = 0
    var gripWearCount: Int = 0
    var pressUseCount: Int = 0
    var firstEarnedAt: Date = Foundation.Date.distantPast
    var lastUsedAt: Date? = nil

    init(
        id: String = UUID().uuidString,
        tierID: Int,
        weightKg: Double,
        engravingText: String,
        earnedAt: Date = .now,
        earnedByEvent: String,
        sourceWorkoutID: String? = nil,
        isRacked: Bool = false,
        rackPosition: Int? = nil,
        liftTypeID: String? = nil,
        currentTier: BarbellPlateProgressionTier = .iron,
        workoutsUsedCount: Int = 0,
        prCount: Int = 0,
        chalkUseCount: Int = 0,
        gripWearCount: Int = 0,
        pressUseCount: Int = 0,
        firstEarnedAt: Date? = nil,
        lastUsedAt: Date? = nil
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
        self.liftTypeID = liftTypeID
        self.currentTierRaw = currentTier.rawValue
        self.workoutsUsedCount = workoutsUsedCount
        self.prCount = prCount
        self.chalkUseCount = chalkUseCount
        self.gripWearCount = gripWearCount
        self.pressUseCount = pressUseCount
        self.firstEarnedAt = firstEarnedAt ?? earnedAt
        self.lastUsedAt = lastUsedAt
    }

    var currentTier: BarbellPlateProgressionTier {
        get { BarbellPlateProgressionTier(rawValue: currentTierRaw) ?? .iron }
        set { currentTierRaw = newValue.rawValue }
    }

    var effectiveFirstEarnedAt: Date {
        firstEarnedAt == .distantPast ? earnedAt : firstEarnedAt
    }

    func applyProjection(_ projection: BarbellPlateProjection) {
        if projection.currentTier.rank < currentTier.rank {
            AppLogger.warning(
                "Ignored local plate tier downgrade for plate=\(id) local=\(currentTier.rawValue) recomputed=\(projection.currentTier.rawValue)",
                category: AppLogger.rewards
            )
        } else {
            currentTier = projection.currentTier
        }
        workoutsUsedCount = max(workoutsUsedCount, projection.workoutsUsedCount)
        prCount = max(prCount, projection.prCount)
        chalkUseCount = max(chalkUseCount, projection.chalkUseCount)
        gripWearCount = max(gripWearCount, projection.gripWearCount)
        pressUseCount = max(pressUseCount, projection.pressUseCount)
        firstEarnedAt = firstEarnedAt == .distantPast ? projection.firstEarnedAt : min(firstEarnedAt, projection.firstEarnedAt)
        if let projectedLastUsedAt = projection.lastUsedAt {
            lastUsedAt = max(lastUsedAt ?? projectedLastUsedAt, projectedLastUsedAt)
        }
    }
}

enum BarbellPlateProgressionTier: String, Codable, CaseIterable, Equatable, Sendable {
    case iron
    case steel
    case chrome
    case gold
    case obsidian
    case cosmic

    var rank: Int {
        switch self {
        case .iron: return 0
        case .steel: return 1
        case .chrome: return 2
        case .gold: return 3
        case .obsidian: return 4
        case .cosmic: return 5
        }
    }
}

enum BarbellPlateProgressionScope {
    static let globalLegacy = "global"

    static func normalizedLiftTypeID(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return globalLegacy
        }
        return value
    }

    static func isGlobal(_ value: String?) -> Bool {
        normalizedLiftTypeID(value) == globalLegacy
    }
}

@Model final class BarbellPlateEvent {
    @Attribute(.unique) var stableKey: String
    var plateID: String
    var kindRaw: String
    var occurredAt: Date
    var workoutID: String?
    var tierRaw: String?
    var milestoneID: String?
    var summary: String
    var isSilent: Bool

    init(
        stableKey: String,
        plateID: String,
        kind: Kind,
        occurredAt: Date,
        workoutID: String? = nil,
        tier: BarbellPlateProgressionTier? = nil,
        milestoneID: String? = nil,
        summary: String,
        isSilent: Bool = true
    ) {
        self.stableKey = stableKey
        self.plateID = plateID
        self.kindRaw = kind.rawValue
        self.occurredAt = occurredAt
        self.workoutID = workoutID
        self.tierRaw = tier?.rawValue
        self.milestoneID = milestoneID
        self.summary = summary
        self.isSilent = isSilent
    }

    enum Kind: String, Codable, Sendable {
        case earned
        case tieredUp
        case personalRecord
        case milestoneVolume
        case anniversary
    }

    var kind: Kind {
        Kind(rawValue: kindRaw) ?? .earned
    }
}

struct BarbellPlateEventDraft: Equatable, Sendable {
    let stableKey: String
    let plateID: String
    let kind: BarbellPlateEvent.Kind
    let occurredAt: Date
    let workoutID: String?
    let tier: BarbellPlateProgressionTier?
    let milestoneID: String?
    let summary: String
    let isSilent: Bool

    func toModel() -> BarbellPlateEvent {
        BarbellPlateEvent(
            stableKey: stableKey,
            plateID: plateID,
            kind: kind,
            occurredAt: occurredAt,
            workoutID: workoutID,
            tier: tier,
            milestoneID: milestoneID,
            summary: summary,
            isSilent: isSilent
        )
    }
}

struct BarbellPlateProjection: Equatable, Sendable {
    let plateID: String
    let liftTypeID: String?
    let currentTier: BarbellPlateProgressionTier
    let workoutsUsedCount: Int
    let prCount: Int
    let chalkUseCount: Int
    let gripWearCount: Int
    let pressUseCount: Int
    let firstEarnedAt: Date
    let lastUsedAt: Date?
    let eventDrafts: [BarbellPlateEventDraft]
}

struct BarbellPlateTierProgress: Equatable, Sendable {
    let currentTier: BarbellPlateProgressionTier
    let nextTier: BarbellPlateProgressionTier?
    let progressFraction: Double
    let primaryText: String
    let secondaryText: String?

    init(
        currentTier: BarbellPlateProgressionTier,
        workoutsUsedCount: Int,
        prCount: Int
    ) {
        self.currentTier = currentTier

        switch currentTier {
        case .iron:
            nextTier = .steel
            progressFraction = Self.clamp(Double(workoutsUsedCount) / 10)
            primaryText = "\(max(0, 10 - workoutsUsedCount)) workouts to Steel"
            secondaryText = "\(workoutsUsedCount)/10 workouts"
        case .steel:
            nextTier = .chrome
            progressFraction = prCount > 0 ? 1 : 0
            primaryText = prCount > 0 ? "Chrome ready" : "1 PR to Chrome"
            secondaryText = "\(prCount)/1 PR"
        case .chrome:
            nextTier = .gold
            let workoutProgress = Self.clamp(Double(workoutsUsedCount) / 50)
            let prProgress = Self.clamp(Double(prCount) / 3)
            let remainingWorkouts = max(0, 50 - workoutsUsedCount)
            let remainingPRs = max(0, 3 - prCount)
            progressFraction = min(workoutProgress, prProgress)
            primaryText = "\(remainingWorkouts) \(Self.plural("workout", remainingWorkouts)) and \(remainingPRs) \(Self.plural("PR", remainingPRs)) to Gold"
            secondaryText = "\(workoutsUsedCount)/50 workouts / \(prCount)/3 PRs"
        case .gold, .obsidian, .cosmic:
            nextTier = nil
            progressFraction = 1
            primaryText = "\(currentTier.rawValue.capitalized) reached"
            secondaryText = "MVP progression complete"
        }
    }

    init(plate: EarnedPlate) {
        self.init(
            currentTier: plate.currentTier,
            workoutsUsedCount: plate.workoutsUsedCount,
            prCount: plate.prCount
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func plural(_ word: String, _ count: Int) -> String {
        count == 1 ? word : "\(word)s"
    }
}

// MARK: - BarbellConfig (@Model, singleton id = "global")

enum BarbellCustomizationDefaults {
    static let barSkinID = "steel_default"
    static let roomThemeID = "dark_gym"
    static let rackStyleID = "matte_black"
    static let showPlateEngravings = true

    static func barSkinID(forLegacyID legacyID: Int) -> String? {
        switch legacyID {
        case 1: return "black_oxide"
        case 2: return "gold"
        case 3: return "cerakote"
        default: return nil
        }
    }
}

@Model final class BarbellConfig {
    @Attribute(.unique) var id: String
    var selectedBarSkinID: Int
    var selectedBarSkinIDRaw: String?
    var selectedRoomThemeIDRaw: String?
    var selectedRackStyleIDRaw: String?
    var selectedCollarIDRaw: String?
    var selectedBannerIDRaw: String?
    var showPlateEngravingsRaw: Bool?
    var roomName: String?
    var roomMotto: String?
    var displayLoadoutData: Data?
    var totalStrengthWorkouts: Int
    var totalFunctionalHKWorkouts: Int = 0
    var lastStreakCheckDate: Date?
    var needsSupabaseSync: Bool
    var backfillCompletedV1: Bool
    var unlockedSkinIDs: [String] = []

    init() {
        self.id = "global"
        self.selectedBarSkinID = 0
        self.selectedBarSkinIDRaw = BarbellCustomizationDefaults.barSkinID
        self.selectedRoomThemeIDRaw = BarbellCustomizationDefaults.roomThemeID
        self.selectedRackStyleIDRaw = BarbellCustomizationDefaults.rackStyleID
        self.selectedCollarIDRaw = nil
        self.selectedBannerIDRaw = nil
        self.showPlateEngravingsRaw = BarbellCustomizationDefaults.showPlateEngravings
        self.roomName = nil
        self.roomMotto = nil
        self.displayLoadoutData = nil
        self.totalStrengthWorkouts = 0
        self.totalFunctionalHKWorkouts = 0
        self.lastStreakCheckDate = nil
        self.needsSupabaseSync = false
        self.backfillCompletedV1 = false
        self.unlockedSkinIDs = []
    }

    struct MutableSnapshot: Equatable {
        let selectedBarSkinID: Int
        let selectedBarSkinIDRaw: String?
        let selectedRoomThemeIDRaw: String?
        let selectedRackStyleIDRaw: String?
        let selectedCollarIDRaw: String?
        let selectedBannerIDRaw: String?
        let showPlateEngravingsRaw: Bool?
        let roomName: String?
        let roomMotto: String?
        let displayLoadoutData: Data?
        let totalStrengthWorkouts: Int
        let totalFunctionalHKWorkouts: Int
        let lastStreakCheckDate: Date?
        let needsSupabaseSync: Bool
        let backfillCompletedV1: Bool
        let unlockedSkinIDs: [String]
    }

    var mutableSnapshot: MutableSnapshot {
        MutableSnapshot(
            selectedBarSkinID: selectedBarSkinID,
            selectedBarSkinIDRaw: selectedBarSkinIDRaw,
            selectedRoomThemeIDRaw: selectedRoomThemeIDRaw,
            selectedRackStyleIDRaw: selectedRackStyleIDRaw,
            selectedCollarIDRaw: selectedCollarIDRaw,
            selectedBannerIDRaw: selectedBannerIDRaw,
            showPlateEngravingsRaw: showPlateEngravingsRaw,
            roomName: roomName,
            roomMotto: roomMotto,
            displayLoadoutData: displayLoadoutData,
            totalStrengthWorkouts: totalStrengthWorkouts,
            totalFunctionalHKWorkouts: totalFunctionalHKWorkouts,
            lastStreakCheckDate: lastStreakCheckDate,
            needsSupabaseSync: needsSupabaseSync,
            backfillCompletedV1: backfillCompletedV1,
            unlockedSkinIDs: unlockedSkinIDs
        )
    }

    var effectiveSelectedBarSkinID: String {
        if let selectedBarSkinIDRaw, !selectedBarSkinIDRaw.isEmpty {
            return selectedBarSkinIDRaw
        }
        return BarbellCustomizationDefaults.barSkinID(forLegacyID: selectedBarSkinID)
            ?? BarbellCustomizationDefaults.barSkinID
    }

    var barSkinIndex: Int {
        switch effectiveSelectedBarSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
        default: return 0
        }
    }

    var effectiveSelectedRoomThemeID: String {
        guard let selectedRoomThemeIDRaw, !selectedRoomThemeIDRaw.isEmpty else {
            return BarbellCustomizationDefaults.roomThemeID
        }
        return selectedRoomThemeIDRaw
    }

    var effectiveSelectedRackStyleID: String {
        guard let selectedRackStyleIDRaw, !selectedRackStyleIDRaw.isEmpty else {
            return BarbellCustomizationDefaults.rackStyleID
        }
        return selectedRackStyleIDRaw
    }

    var showPlateEngravings: Bool {
        showPlateEngravingsRaw ?? BarbellCustomizationDefaults.showPlateEngravings
    }

    var displayLoadout: DisplayLoadout {
        guard let displayLoadoutData,
              let loadout = try? JSONDecoder().decode(DisplayLoadout.self, from: displayLoadoutData) else {
            return DisplayLoadout()
        }
        return loadout
    }

    func setDisplayLoadout(_ loadout: DisplayLoadout) {
        displayLoadoutData = try? JSONEncoder().encode(loadout)
    }

    func migrateLegacyCustomizationFieldsIfNeeded() {
        if selectedBarSkinIDRaw == nil,
           let migrated = BarbellCustomizationDefaults.barSkinID(forLegacyID: selectedBarSkinID) {
            selectedBarSkinIDRaw = migrated
        }
        selectedBarSkinIDRaw = selectedBarSkinIDRaw ?? BarbellCustomizationDefaults.barSkinID
        selectedRoomThemeIDRaw = selectedRoomThemeIDRaw ?? BarbellCustomizationDefaults.roomThemeID
        selectedRackStyleIDRaw = selectedRackStyleIDRaw ?? BarbellCustomizationDefaults.rackStyleID
        showPlateEngravingsRaw = showPlateEngravingsRaw ?? BarbellCustomizationDefaults.showPlateEngravings
    }

    func resetMutableFieldsToDefaults() {
        let defaults = BarbellConfig()
        selectedBarSkinID = defaults.selectedBarSkinID
        selectedBarSkinIDRaw = defaults.selectedBarSkinIDRaw
        selectedRoomThemeIDRaw = defaults.selectedRoomThemeIDRaw
        selectedRackStyleIDRaw = defaults.selectedRackStyleIDRaw
        selectedCollarIDRaw = defaults.selectedCollarIDRaw
        selectedBannerIDRaw = defaults.selectedBannerIDRaw
        showPlateEngravingsRaw = defaults.showPlateEngravingsRaw
        roomName = defaults.roomName
        roomMotto = defaults.roomMotto
        displayLoadoutData = defaults.displayLoadoutData
        totalStrengthWorkouts = defaults.totalStrengthWorkouts
        totalFunctionalHKWorkouts = defaults.totalFunctionalHKWorkouts
        lastStreakCheckDate = defaults.lastStreakCheckDate
        needsSupabaseSync = defaults.needsSupabaseSync
        backfillCompletedV1 = defaults.backfillCompletedV1
        unlockedSkinIDs = defaults.unlockedSkinIDs
    }
}

@Model final class BarbellProcessedHKWorkout {
    @Attribute(.unique) var healthKitUUID: String
    var processedAt: Date

    init(healthKitUUID: String, processedAt: Date = .now) {
        self.healthKitUUID = healthKitUUID
        self.processedAt = processedAt
    }
}

struct DisplayLoadout: Codable, Equatable, Sendable {
    var onBar: [String]
    var onWall: [String]

    init(onBar: [String] = [], onWall: [String] = []) {
        self.onBar = onBar
        self.onWall = onWall
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.onBar = try container.decodeIfPresent([String].self, forKey: .onBar) ?? []
        self.onWall = try container.decodeIfPresent([String].self, forKey: .onWall) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(onBar, forKey: .onBar)
        try container.encode(onWall, forKey: .onWall)
    }

    private enum CodingKeys: String, CodingKey {
        case onBar
        case onWall
    }

    func sanitized(earnedPlateIDs: Set<String>, maximumBarPlateCount: Int = 8) -> DisplayLoadout {
        var seen = Set<String>()

        func clean(_ ids: [String], limit: Int? = nil) -> [String] {
            var result: [String] = []
            for id in ids {
                guard earnedPlateIDs.contains(id), seen.insert(id).inserted else { continue }
                result.append(id)
                if let limit, result.count >= limit { break }
            }
            return result
        }

        let sanitizedBar = clean(onBar, limit: maximumBarPlateCount)
        let sanitizedWall = clean(onWall)
        return DisplayLoadout(onBar: sanitizedBar, onWall: sanitizedWall)
    }
}

@Model final class BarbellCosmeticUnlock {
    @Attribute(.unique) var cosmeticID: String
    var id: String
    var unlockedAt: Date
    var sourceRaw: String
    var sourceWorkoutID: String?
    var catalogVersion: String?

    init(
        id: String = UUID().uuidString,
        cosmeticID: String,
        unlockedAt: Date = .now,
        sourceRaw: String,
        sourceWorkoutID: String? = nil,
        catalogVersion: String? = nil
    ) {
        self.id = id
        self.cosmeticID = cosmeticID
        self.unlockedAt = unlockedAt
        self.sourceRaw = sourceRaw
        self.sourceWorkoutID = sourceWorkoutID
        self.catalogVersion = catalogVersion
    }

    var source: BarbellCosmeticUnlockSource {
        BarbellCosmeticUnlockSource(rawValue: sourceRaw) ?? .workout
    }
}

enum BarbellCosmeticUnlockSource: String, Codable, Equatable, Sendable {
    case `default`
    case workout
    case seasonal
    case setBonus
    case hidden
    case migration
    case support
}

struct BarbellCosmeticUnlockDraft: Equatable, Sendable {
    let cosmeticID: String
    let unlockedAt: Date
    let source: BarbellCosmeticUnlockSource
    let sourceWorkoutID: String?
    let catalogVersion: String?

    func toModel() -> BarbellCosmeticUnlock {
        BarbellCosmeticUnlock(
            cosmeticID: cosmeticID,
            unlockedAt: unlockedAt,
            sourceRaw: source.rawValue,
            sourceWorkoutID: sourceWorkoutID,
            catalogVersion: catalogVersion
        )
    }
}

// MARK: - EarnedPlateInfo (plain struct, cross-thread DTO)

public struct EarnedPlateInfo: Equatable, Sendable {
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedByEvent: String
    let liftTypeID: String?

    init(
        tierID: Int,
        weightKg: Double,
        engravingText: String,
        earnedByEvent: String,
        liftTypeID: String? = nil
    ) {
        self.tierID = tierID
        self.weightKg = weightKg
        self.engravingText = engravingText
        self.earnedByEvent = earnedByEvent
        self.liftTypeID = liftTypeID
    }
}

enum BarbellRewardEventKind: String, Equatable, Sendable {
    case newPlate
    case tierUp
    case cosmeticUnlock
    case setBonus
    case personalRecord
    case agingMilestone
}

struct BarbellRewardEvent: Equatable, Identifiable, Sendable {
    let id: String
    let kind: BarbellRewardEventKind
    let title: String
    let detail: String?
    let occurredAt: Date
    let workoutID: String?
    let plate: EarnedPlateInfo?

    init(
        id: String,
        kind: BarbellRewardEventKind,
        title: String,
        detail: String? = nil,
        occurredAt: Date,
        workoutID: String? = nil,
        plate: EarnedPlateInfo? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.occurredAt = occurredAt
        self.workoutID = workoutID
        self.plate = plate
    }
}

struct BarbellRewardPresentationQueue: Equatable, Sendable {
    let primary: BarbellRewardEvent?
    let compactEvents: [BarbellRewardEvent]

    var fullScreenPlate: EarnedPlateInfo? {
        guard primary?.kind == .newPlate else { return nil }
        return primary?.plate
    }

    var compactCount: Int { compactEvents.count }

    var compactSummary: String? {
        guard !compactEvents.isEmpty else { return nil }
        return "and \(compactEvents.count) more"
    }
}

enum BarbellRewardPresentationSource: String, Sendable {
    case liveWorkoutCompletion
    case syncRepair
    case manualImport
    case migrationBackfill
}

enum BarbellRealityPerformanceBudget {
    static let editorTargetFPS = 60
    static let friendShowcaseMinimumFPS = 30
    static let maximumLiveParticleSystems = 4
    static let goldAndAboveStaticFallbackTier = 6

    static var requiresStaticOnlyRendering: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled ||
        ProcessInfo.processInfo.thermalState == .serious ||
        ProcessInfo.processInfo.thermalState == .critical
    }

    static func shouldUseStaticFallback(forTierID tierID: Int) -> Bool {
        requiresStaticOnlyRendering && tierID >= goldAndAboveStaticFallbackTier
    }
}

struct EarnedPlateSyncPayload: Sendable {
    let earnedByEvent: String
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedAt: Date
    let sourceWorkoutID: String?
    let isRacked: Bool
    let rackPosition: Int?
    let liftTypeID: String?
    let currentTier: BarbellPlateProgressionTier
    let workoutsUsedCount: Int
    let prCount: Int
    let chalkUseCount: Int
    let gripWearCount: Int
    let pressUseCount: Int
    let firstEarnedAt: Date
    let lastUsedAt: Date?

    init(
        info: EarnedPlateInfo,
        earnedAt: Date,
        sourceWorkoutID: String?,
        isRacked: Bool = false,
        rackPosition: Int? = nil
    ) {
        self.earnedByEvent = info.earnedByEvent
        self.tierID = info.tierID
        self.weightKg = info.weightKg
        self.engravingText = info.engravingText
        self.earnedAt = earnedAt
        self.sourceWorkoutID = sourceWorkoutID
        self.isRacked = isRacked
        self.rackPosition = rackPosition
        self.liftTypeID = BarbellPlateProgressionScope.normalizedLiftTypeID(info.liftTypeID)
        self.currentTier = .iron
        self.workoutsUsedCount = 0
        self.prCount = 0
        self.chalkUseCount = 0
        self.gripWearCount = 0
        self.pressUseCount = 0
        self.firstEarnedAt = earnedAt
        self.lastUsedAt = nil
    }

    init(plate: EarnedPlate) {
        self.earnedByEvent = plate.earnedByEvent
        self.tierID = plate.tierID
        self.weightKg = plate.weightKg
        self.engravingText = plate.engravingText
        self.earnedAt = plate.earnedAt
        self.sourceWorkoutID = plate.sourceWorkoutID
        self.isRacked = plate.isRacked
        self.rackPosition = plate.rackPosition
        self.liftTypeID = BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID)
        self.currentTier = plate.currentTier
        self.workoutsUsedCount = plate.workoutsUsedCount
        self.prCount = plate.prCount
        self.chalkUseCount = plate.chalkUseCount
        self.gripWearCount = plate.gripWearCount
        self.pressUseCount = plate.pressUseCount
        self.firstEarnedAt = plate.effectiveFirstEarnedAt
        self.lastUsedAt = plate.lastUsedAt
    }
}

struct BarbellPlateEventSyncPayload: Sendable {
    let stableKey: String
    let earnedByEvent: String
    let kind: BarbellPlateEvent.Kind
    let occurredAt: Date
    let workoutID: String?
    let tier: BarbellPlateProgressionTier?
    let milestoneID: String?
    let summary: String
    let isSilent: Bool

    init(event: BarbellPlateEvent, earnedByEvent: String) {
        self.stableKey = event.stableKey
        self.earnedByEvent = earnedByEvent
        self.kind = event.kind
        self.occurredAt = event.occurredAt
        self.workoutID = event.workoutID
        self.tier = event.tierRaw.flatMap(BarbellPlateProgressionTier.init(rawValue:))
        self.milestoneID = event.milestoneID
        self.summary = event.summary
        self.isSilent = event.isSilent
    }
}

struct BarbellCosmeticUnlockSyncPayload: Sendable {
    let cosmeticID: String
    let unlockedAt: Date
    let source: BarbellCosmeticUnlockSource
    let sourceWorkoutID: String?
    let catalogVersion: String?

    init(draft: BarbellCosmeticUnlockDraft) {
        self.cosmeticID = draft.cosmeticID
        self.unlockedAt = draft.unlockedAt
        self.source = draft.source
        self.sourceWorkoutID = draft.sourceWorkoutID
        self.catalogVersion = draft.catalogVersion
    }

    init(unlock: BarbellCosmeticUnlock) {
        self.cosmeticID = unlock.cosmeticID
        self.unlockedAt = unlock.unlockedAt
        self.source = unlock.source
        self.sourceWorkoutID = unlock.sourceWorkoutID
        self.catalogVersion = unlock.catalogVersion
    }
}

struct BarbellFriendShowcase: Equatable, Sendable {
    let barSkinID: String
    let roomThemeID: String
    let rackStyleID: String
    let collarID: String?
    let bannerID: String?
    let showPlateEngravings: Bool
    let roomName: String?
    let roomMotto: String?
    let plates: [EarnedPlateInfo]

    init(
        barSkinID: String = BarbellCustomizationDefaults.barSkinID,
        roomThemeID: String = BarbellCustomizationDefaults.roomThemeID,
        rackStyleID: String = BarbellCustomizationDefaults.rackStyleID,
        collarID: String? = nil,
        bannerID: String? = nil,
        showPlateEngravings: Bool = BarbellCustomizationDefaults.showPlateEngravings,
        roomName: String? = nil,
        roomMotto: String? = nil,
        plates: [EarnedPlateInfo] = []
    ) {
        self.barSkinID = barSkinID
        self.roomThemeID = roomThemeID
        self.rackStyleID = rackStyleID
        self.collarID = collarID
        self.bannerID = bannerID
        self.showPlateEngravings = showPlateEngravings
        self.roomName = roomName
        self.roomMotto = roomMotto
        self.plates = plates
    }
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
