import Foundation
import SwiftData

// Frozen stored declarations from 32251df138b6cb344b12f5b901c605aebbb6d0d2 (2026-05-24).
// The archive's exact source is unconfirmed. Do not edit these historical definitions.
// Methods and computed properties are omitted; they are not part of the stored schema.
enum LegacyStoreSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [
        RewardProgress.self, Achievement.self, ChallengeAssignment.self, RewardLedgerEntry.self,
        Wallet.self, ExercisePR.self, DexStamp.self, WeeklyTrainingSummary.self,
        DailyAppleExerciseSummary.self, ExerciseVolumeSummary.self, MovingAverage.self, ExerciseProgressionSummary.self,
        ExerciseTrend.self, PushPullBalance.self, MuscleGroupFrequency.self, MovementPatternBalance.self,
        WeeklyGoal.self, HealthSyncAnchor.self, RouteFetchTask.self, MapSnapshotCache.self,
        PlannedWorkout.self, PlannedExercise.self, WorkoutSplit.self, PlanBlock.self,
        PlanBlockExercise.self, EarnedPlate.self, BarbellPlateEvent.self, BarbellConfig.self,
        BarbellCosmeticUnlock.self, BarbellProcessedHKWorkout.self,
    ] }

    @Model final class RewardProgress {
        @Attribute(.unique) var id: String = "global"
        var xp: Int = 0
        var level: Int = 1
        var prevLevelXP: Int = 0
        var nextLevelXP: Int = 150
        var dataCutoffDate: Date = Date.now
        var longestStreak: Int = 0
        var currentStreak: Int = 0
        var lastActivityAt: Date? = nil
        var streakFrozen: Bool = false
        var freezeUsedAt: Date? = nil
        var weeklyStreakFrozen: Bool = false
        var weeklyFreezeUsedAt: Date? = nil
        var weeklyFreezeProtectedWeekStart: Date? = nil
        var weeklyGoalStreakCurrent: Int = 0
        var weeklyGoalStreakLongest: Int = 0
        var lastWeekGoalMet: Date? = nil
        var weeklySuperStreakCurrent: Int = 0
        var weeklySuperStreakLongest: Int = 0
        var lastWeekSuperStreakMet: Date? = nil
        var lastAwardedMilestoneLevel: Int = 0

        init() { }
    }

    @Model final class Achievement {
        @Attribute(.unique) var id: String
        var title: String
        var desc: String
        var tierRaw: String?
        var progress: Int
        var target: Int
        var unlockedAt: Date?
        var lastUpdatedAt: Date

        init() {
            self.id = ""
            self.title = ""
            self.desc = ""
            self.progress = 0
            self.target = 0
            self.lastUpdatedAt = .distantPast
        }
    }

    @Model final class ChallengeAssignment {
        @Attribute(.unique) var id: String
        var ruleId: String
        var kindRaw: String
        var startedAt: Date
        var expiresAt: Date
        var completedAt: Date?
        var claimedAt: Date?

        init() {
            self.id = ""
            self.ruleId = ""
            self.kindRaw = ""
            self.startedAt = .distantPast
            self.expiresAt = .distantPast
        }
    }

    @Model final class RewardLedgerEntry {
        @Attribute(.unique) var id: String
        var occurredAt: Date
        var event: String
        var ruleId: String?
        var deltaXP: Int
        var deltaCoins: Int
        var metadataJSON: String?

        init() {
            self.id = ""
            self.occurredAt = .distantPast
            self.event = ""
            self.deltaXP = 0
            self.deltaCoins = 0
        }
    }

    @Model final class Wallet {
        @Attribute(.unique) var id: String
        var coins: Int

        init() {
            self.id = ""
            self.coins = 0
        }
    }

    @Model final class ExercisePR {
        var exerciseId: String
        var exerciseName: String
        var bestE1RM: Double
        var bestWeightKg: Double
        var bestReps: Int
        var updatedAt: Date

        init() {
            self.exerciseId = ""
            self.exerciseName = ""
            self.bestE1RM = 0
            self.bestWeightKg = 0
            self.bestReps = 0
            self.updatedAt = .distantPast
        }
    }

    @Model final class DexStamp {
        @Attribute(.unique) var key: String
        var unlockedAt: Date?

        init() {
            self.key = ""
        }
    }

    @Model final class WeeklyTrainingSummary {
        @Attribute(.unique) var key: String
        var weekStart: Date
        var totalVolume: Double
        var sessions: Int
        var totalSets: Int
        var totalReps: Int
        var minutes: Int
        var appleExerciseMinutes: Int?
        var cardioSessions: Int?
        var lastHealthSync: Date?
        var containsBodyweightEstimates: Bool = false

        init() {
            self.key = ""
            self.weekStart = .distantPast
            self.totalVolume = 0
            self.sessions = 0
            self.totalSets = 0
            self.totalReps = 0
            self.minutes = 0
        }
    }

    @Model final class DailyAppleExerciseSummary {
        @Attribute(.unique) var key: String
        var dayStart: Date
        var minutes: Int
        var lastHealthSync: Date?

        init() {
            self.key = ""
            self.dayStart = .distantPast
            self.minutes = 0
        }
    }

    @Model final class ExerciseVolumeSummary {
        @Attribute(.unique) var key: String
        var exerciseID: String
        var weekStart: Date
        var volume: Double

        init() {
            self.key = ""
            self.exerciseID = ""
            self.weekStart = .distantPast
            self.volume = 0
        }
    }

    @Model final class MovingAverage {
        @Attribute(.unique) var key: String
        var weekStart: Date
        var fourWeekAvg: Double
        var stdDev: Double
        var personalAvg: Double
        var percentChange: Double
        var isAboveAverage: Bool

        init() {
            self.key = ""
            self.weekStart = .distantPast
            self.fourWeekAvg = 0
            self.stdDev = 0
            self.personalAvg = 0
            self.percentChange = 0
            self.isAboveAverage = false
        }
    }

    @Model final class ExerciseProgressionSummary {
        @Attribute(.unique) var key: String
        var exerciseID: String
        var weekStart: Date
        var totalVolume: Double
        var maxWeight: Double
        var totalSets: Int
        var totalReps: Int
        var sessionCount: Int
        var avgE1RM: Double

        init() {
            self.key = ""
            self.exerciseID = ""
            self.weekStart = .distantPast
            self.totalVolume = 0
            self.maxWeight = 0
            self.totalSets = 0
            self.totalReps = 0
            self.sessionCount = 0
            self.avgE1RM = 0
        }
    }

    @Model final class ExerciseTrend {
        @Attribute(.unique) var exerciseID: String
        var trendDirection: String
        var volumeChange: Double
        var strengthChange: Double
        var lastUpdated: Date
        var sampleCount: Int = 0
        var lowConfidence: Bool = false

        init() {
            self.exerciseID = ""
            self.trendDirection = ""
            self.volumeChange = 0
            self.strengthChange = 0
            self.lastUpdated = .distantPast
        }
    }

    @Model final class PushPullBalance {
        @Attribute(.unique) var key: String
        var weekStart: Date
        var pushVolume: Double
        var pullVolume: Double
        var horizontalPushVolume: Double
        var horizontalPullVolume: Double
        var verticalPushVolume: Double
        var verticalPullVolume: Double
        var ratio: Double

        init() {
            self.key = ""
            self.weekStart = .distantPast
            self.pushVolume = 0
            self.pullVolume = 0
            self.horizontalPushVolume = 0
            self.horizontalPullVolume = 0
            self.verticalPushVolume = 0
            self.verticalPullVolume = 0
            self.ratio = 0
        }
    }

    @Model final class MuscleGroupFrequency {
        @Attribute(.unique) var muscleGroup: String
        var lastTrained: Date
        var weeklyFrequency: Int
        var totalVolume: Double
        var weeklySetCount: Int = 0
        var weeklyHardSetCount: Int = 0

        init() {
            self.muscleGroup = ""
            self.lastTrained = .distantPast
            self.weeklyFrequency = 0
            self.totalVolume = 0
        }
    }

    @Model final class MovementPatternBalance {
        @Attribute(.unique) var key: String
        var weekStart: Date
        var compoundVolume: Double
        var isolationVolume: Double
        var bilateralVolume: Double
        var unilateralVolume: Double
        var hingeVolume: Double
        var squatVolume: Double

        init() {
            self.key = ""
            self.weekStart = .distantPast
            self.compoundVolume = 0
            self.isolationVolume = 0
            self.bilateralVolume = 0
            self.unilateralVolume = 0
            self.hingeVolume = 0
            self.squatVolume = 0
        }
    }

    @Model final class WeeklyGoal {
        @Attribute(.unique) var id: String = "weekly.goal"
        var isSet: Bool
        var targetActiveMinutes: Int
        var targetDailySteps: Int = 10000
        var targetStrengthDays: Int
        var anchorWeekday: Int
        var trackingMode: String = "exerciseMinutes"
        var createdAt: Date
        var updatedAt: Date

        init() {
            self.isSet = false
            self.targetActiveMinutes = 0
            self.targetStrengthDays = 0
            self.anchorWeekday = 0
            self.createdAt = .distantPast
            self.updatedAt = .distantPast
        }
    }

    @Model final class HealthSyncAnchor {
        @Attribute(.unique) var dataType: String
        var anchorData: Data?
        var lastSyncDate: Date
        var syncCount: Int

        init() {
            self.dataType = ""
            self.lastSyncDate = .distantPast
            self.syncCount = 0
        }
    }

    @Model final class RouteFetchTask {
        @Attribute(.unique) var workoutUUID: String
        var workoutDate: Date
        var priority: Int
        var allowAutoPost: Bool?
        var attemptCount: Int
        var lastAttemptDate: Date?
        var status: String
        var createdAt: Date

        init() {
            self.workoutUUID = ""
            self.workoutDate = .distantPast
            self.priority = 0
            self.attemptCount = 0
            self.status = ""
            self.createdAt = .distantPast
        }
    }

    @Model final class MapSnapshotCache {
        @Attribute(.unique) var workoutUUID: String
        var snapshotData: Data?
        var generatedAt: Date
        var routeHash: String?

        init() {
            self.workoutUUID = ""
            self.generatedAt = .distantPast
        }
    }

    @Model final class PlannedWorkout {
        @Attribute(.unique) var id: UUID
        var scheduledDate: Date
        var splitDayName: String
        var splitID: UUID?
        var exercises: [PlannedExercise]
        var completedWorkoutID: UUID?
        var status: String
        var notes: String?
        var targetVolume: Double
        var actualVolume: Double?
        var completionPercentage: Double?

        init() {
            self.id = UUID()
            self.scheduledDate = .distantPast
            self.splitDayName = ""
            self.exercises = []
            self.status = ""
            self.targetVolume = 0
        }
    }

    @Model final class PlannedExercise {
        var id: UUID
        var exerciseID: String
        var exerciseName: String
        var ghostSets: [GhostSet]
        var progressionStrategyRaw: String
        var order: Int
        var notes: String?
        var lastPerformance: String?
        var lastCompletedDate: Date?

        init() {
            self.id = UUID()
            self.exerciseID = ""
            self.exerciseName = ""
            self.ghostSets = []
            self.progressionStrategyRaw = ""
            self.order = 0
        }
    }

    @Model final class WorkoutSplit {
        @Attribute(.unique) var id: UUID
        var name: String
        var planBlocks: [PlanBlock]
        var anchorDate: Date
        var cursor: Int
        var reschedulePolicy: String
        var isActive: Bool
        var creatorUserID: String?
        var creatorUsername: String?
        var creatorDisplayName: String?
        var originProgramID: UUID?
        var lastSharedProgramID: UUID?
        var programDescription: String?
        var importedAt: Date?
        var createdAt: Date?

        init() {
            self.id = UUID()
            self.name = ""
            self.planBlocks = []
            self.anchorDate = .distantPast
            self.cursor = 0
            self.reschedulePolicy = ""
            self.isActive = false
        }
    }

    @Model final class PlanBlock {
        var id: UUID
        var dayName: String
        var exercises: [PlanBlockExercise]
        var isRestDay: Bool

        init() {
            self.id = UUID()
            self.dayName = ""
            self.exercises = []
            self.isRestDay = false
        }
    }

    @Model final class PlanBlockExercise {
        var id: UUID
        var exerciseID: String
        var exerciseName: String
        var sets: Int
        var reps: Int
        var startingWeight: Double?
        var progressionStrategyRaw: String
        var order: Int

        init() {
            self.id = UUID()
            self.exerciseID = ""
            self.exerciseName = ""
            self.sets = 0
            self.reps = 0
            self.progressionStrategyRaw = ""
            self.order = 0
        }
    }

    @Model final class EarnedPlate {
        @Attribute(.unique) var id: String
        var tierID: Int
        var weightKg: Double
        var engravingText: String
        var earnedAt: Date
        var earnedByEvent: String
        var sourceWorkoutID: String?
        var isRacked: Bool
        var rackPosition: Int?
        var displayOrder: Int
        var liftTypeID: String? = nil
        var currentTierRaw: String = "iron"
        var workoutsUsedCount: Int = 0
        var prCount: Int = 0
        var chalkUseCount: Int = 0
        var gripWearCount: Int = 0
        var pressUseCount: Int = 0
        var firstEarnedAt: Date = Foundation.Date.distantPast
        var lastUsedAt: Date? = nil

        init() {
            self.id = ""
            self.tierID = 0
            self.weightKg = 0
            self.engravingText = ""
            self.earnedAt = .distantPast
            self.earnedByEvent = ""
            self.isRacked = false
            self.displayOrder = 0
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

        init() {
            self.stableKey = ""
            self.plateID = ""
            self.kindRaw = ""
            self.occurredAt = .distantPast
            self.summary = ""
            self.isSilent = false
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
            self.id = ""
            self.selectedBarSkinID = 0
            self.totalStrengthWorkouts = 0
            self.needsSupabaseSync = false
            self.backfillCompletedV1 = false
        }
    }

    @Model final class BarbellCosmeticUnlock {
        @Attribute(.unique) var cosmeticID: String
        var id: String
        var unlockedAt: Date
        var sourceRaw: String
        var sourceWorkoutID: String?
        var catalogVersion: String?

        init() {
            self.cosmeticID = ""
            self.id = ""
            self.unlockedAt = .distantPast
            self.sourceRaw = ""
        }
    }

    @Model final class BarbellProcessedHKWorkout {
        @Attribute(.unique) var healthKitUUID: String
        var processedAt: Date

        init() {
            self.healthKitUUID = ""
            self.processedAt = .distantPast
        }
    }

    @Model final class CachedPost {
        @Attribute(.unique) var id: String
        var userId: String
        var caption: String?
        var workoutDataJSON: String
        var workoutDataListJSON: String?
        var imageUrls: [String]
        var visibility: String
        var likesCount: Int
        var commentsCount: Int
        var isLiked: Bool
        var createdAt: Date
        var updatedAt: Date
        var cachedAt: Date
        var authorUsername: String
        var authorDisplayName: String?
        var authorAvatarUrl: String?

        init() {
            self.id = ""
            self.userId = ""
            self.workoutDataJSON = ""
            self.imageUrls = []
            self.visibility = ""
            self.likesCount = 0
            self.commentsCount = 0
            self.isLiked = false
            self.createdAt = .distantPast
            self.updatedAt = .distantPast
            self.cachedAt = .distantPast
            self.authorUsername = ""
        }
    }

    @Model final class CachedProfile {
        @Attribute(.unique) var id: String
        var username: String
        var displayName: String?
        var avatarUrl: String?
        var bio: String?
        var isPrivate: Bool
        var autoPostPRs: Bool = true
        var birthYear: Int?
        var createdAt: Date
        var updatedAt: Date
        var cachedAt: Date

        init() {
            self.id = ""
            self.username = ""
            self.isPrivate = false
            self.createdAt = .distantPast
            self.updatedAt = .distantPast
            self.cachedAt = .distantPast
        }
    }

    @Model final class CachedNotification {
        @Attribute(.unique) var id: String
        var userId: String
        var type: String
        var actorId: String
        var targetId: String?
        var read: Bool
        var createdAt: Date
        var cachedAt: Date
        var metadata: [String: String]?
        var actorUsername: String
        var actorDisplayName: String?
        var actorAvatarUrl: String?

        init() {
            self.id = ""
            self.userId = ""
            self.type = ""
            self.actorId = ""
            self.read = false
            self.createdAt = .distantPast
            self.cachedAt = .distantPast
            self.actorUsername = ""
        }
    }

}

enum LegacyCacheSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [LegacyStoreSchema.CachedPost.self, LegacyStoreSchema.CachedProfile.self, LegacyStoreSchema.CachedNotification.self]
    }
}
