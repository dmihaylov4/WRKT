import SwiftData

enum AppStoreSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
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
}

enum AppStoreMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LegacyStoreSchema.self, AppStoreSchema.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LegacyStoreSchema.self, toVersion: AppStoreSchema.self)]
    }
}

enum CacheStoreSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [CachedPost.self, CachedProfile.self, CachedNotification.self] }
}

enum CacheStoreMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LegacyCacheSchema.self, CacheStoreSchema.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LegacyCacheSchema.self, toVersion: CacheStoreSchema.self)]
    }
}
