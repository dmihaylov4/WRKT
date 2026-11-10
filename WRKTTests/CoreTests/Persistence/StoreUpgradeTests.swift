import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class StoreUpgradeTests: XCTestCase {
    private var directory: URL!
    private var support: URL { directory.appendingPathComponent("Application Support") }
    private var documents: URL { directory.appendingPathComponent("Documents") }
    private var storeURL: URL { support.appendingPathComponent("default.store") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    func testUnversionedStoreUpgradesWithoutLosingRecordsOrRelationshipsAndBackupReopens() throws {
        try seedLegacyStore(at: storeURL)
        let note = Data("existing user file".utf8)
        try note.write(to: documents.appendingPathComponent("notes.txt"))
        let storage = AppDataStore(storeURL: storeURL, documents: documents, preferences: { ["weightUnit": "lb"] })
        XCTAssertNil(storage.error)
        let context = try XCTUnwrap(storage.container).mainContext
        try assertCurrentRecords(context)

        let copy = try XCTUnwrap(storage.recoveryCopy)
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("Documents/notes.txt")), note)
        let oldSchema = Schema(LegacyStoreSchema.models)
        // Read a disposable copy of the snapshot, leaving the immutable backup untouched.
        let restored = directory.appendingPathComponent("restored")
        try FileManager.default.copyItem(at: copy.appendingPathComponent("Application Support"), to: restored)
        let old = try ModelContainer(for: oldSchema, configurations:
            ModelConfiguration(schema: oldSchema, url: restored.appendingPathComponent("default.store")))
        XCTAssertEqual(try old.mainContext.fetch(FetchDescriptor<LegacyStoreSchema.Wallet>()).first?.coins, 275)
        XCTAssertEqual(try old.mainContext.fetch(FetchDescriptor<LegacyStoreSchema.WorkoutSplit>()).first?.planBlocks.first?.exercises.first?.reps, 8)
        // Opening an already-upgraded database does not duplicate records or replace the snapshot.
        let manifest = try Data(contentsOf: copy.appendingPathComponent("manifest.json"))
        storage.retry()
        try assertCurrentRecords(context)
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("manifest.json")), manifest)
    }

    func testBackupFailureLeavesExistingDatabaseClosedAndUnmodifiedThenRetrySucceeds() throws {
        try seedLegacyStore(at: storeURL)
        let blockedDirectory = support.appendingPathComponent("UpgradeBackups")
        try Data("not a directory".utf8).write(to: blockedDirectory)
        let storage = AppDataStore(storeURL: storeURL, documents: documents, preferences: { [:] })
        XCTAssertNil(storage.container)
        XCTAssertNotNil(storage.error)
        try autoreleasepool {
            let schema = Schema(LegacyStoreSchema.models)
            let original = try ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, url: storeURL))
            XCTAssertEqual(try original.mainContext.fetch(FetchDescriptor<LegacyStoreSchema.Wallet>()).first?.coins, 275)
        }
        try FileManager.default.removeItem(at: blockedDirectory)
        storage.retry()
        try assertCurrentRecords(XCTUnwrap(storage.container).mainContext)
    }

    func testCorruptDatabaseIsPreservedAndNeverReplacedWithAnEmptyStore() throws {
        let bytes = Data("unreadable original database".utf8)
        try bytes.write(to: storeURL)
        let storage = AppDataStore(storeURL: storeURL, documents: documents, preferences: { [:] })
        XCTAssertNil(storage.container)
        XCTAssertNotNil(storage.error)
        let copy = try XCTUnwrap(storage.recoveryCopy)
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("Application Support/default.store")), bytes)
        XCTAssertEqual(try Data(contentsOf: storeURL), bytes)
    }

    func testCacheMigrationPreservesRecordsAndFailureDoesNotCrashOrTouchUserStore() throws {
        XCTAssertNotEqual(CacheManager.storeURL, AppDataStore.defaultStoreURL)
        let cacheURL = support.appendingPathComponent("SocialCache/cache.store")
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try seedLegacyCache(at: cacheURL)
        let schema = Schema(versionedSchema: CacheStoreSchema.self)
        let container = try ModelContainer(for: schema, migrationPlan: CacheStoreMigration.self,
            configurations: ModelConfiguration(schema: schema, url: cacheURL))
        let profile = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CachedProfile>()).first)
        XCTAssertEqual(profile.username, "existing-user")
        XCTAssertFalse(profile.autoPostWatchWorkouts)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CachedPost>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CachedNotification>()), 1)
        let corruptURL = support.appendingPathComponent("broken-cache.store")
        let corrupt = Data("keep this cache for inspection".utf8)
        try corrupt.write(to: corruptURL)
        let cache = CacheManager(storeURL: corruptURL)
        XCTAssertEqual(cache.getCacheStats().posts, 0)
        cache.clearAllCache()
        XCTAssertEqual(try Data(contentsOf: corruptURL), corrupt)
    }

    func testAlreadyCurrentUnversionedStoreCanAdoptTheMigrationPlan() throws {
        try autoreleasepool {
            let schema = Schema(AppStoreSchema.models)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
            old.mainContext.insert(Wallet(id: "global", coins: 912))
            try old.mainContext.save()
        }
        let storage = AppDataStore(storeURL: storeURL, documents: documents, preferences: { [:] })
        XCTAssertNil(storage.error)
        let container = try XCTUnwrap(storage.container)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Wallet>()).first?.coins, 912)
    }

    func testCacheOnlyLegacyStoreIsPreservedInsteadOfReplacedWithEmptyUserData() throws {
        try seedLegacyCache(at: storeURL)
        let storage = AppDataStore(storeURL: storeURL, documents: documents, preferences: { [:] })
        XCTAssertNil(storage.container)
        XCTAssertNotNil(storage.error)
        XCTAssertNotNil(storage.recoveryCopy)
        let schema = Schema(LegacyCacheSchema.models)
        let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        XCTAssertEqual(try old.mainContext.fetch(FetchDescriptor<LegacyStoreSchema.CachedProfile>()).first?.username, "existing-user")
    }

    func testCorruptWorkoutHistoryBlocksStartupAndIsIncludedInRecoveryCopy() throws {
        try seedLegacyStore(at: storeURL)
        let history = documents.appendingPathComponent("WRKT_Storage")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let bytes = Data("{truncated history".utf8)
        try bytes.write(to: history.appendingPathComponent("workouts_v2.json"))
        let storage = AppDataStore(storeURL: storeURL, documents: documents, preferences: { [:] })
        XCTAssertNil(storage.container)
        let copy = try XCTUnwrap(storage.recoveryCopy)
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("Documents/WRKT_Storage/workouts_v2.json")), bytes)
        XCTAssertEqual(try Data(contentsOf: history.appendingPathComponent("workouts_v2.json")), bytes)
    }

    func testSnapshotIncludesJournalsExternalFilesAndPreferencesAndRemainsImmutable() throws {
        let files = ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT/_EXTERNAL_DATA/blob", "other/manifest.json"]
        for name in files {
            let url = support.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: url)
        }
        let backup = UpgradeBackup(applicationSupport: support, documents: documents,
            destination: support.appendingPathComponent("UpgradeBackups/test"))
        let copy = try backup.createIfNeeded(preferences: ["weightUnit": "lb"])
        try backup.verify()
        for name in files {
            XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("Application Support/" + name)), Data(name.utf8))
        }
        let settings = try PropertyListSerialization.propertyList(from: Data(contentsOf: copy.appendingPathComponent("Preferences.plist")), format: nil) as? [String: String]
        XCTAssertEqual(settings?["weightUnit"], "lb")
        try Data("new version".utf8).write(to: storeURL)
        _ = try backup.createIfNeeded()
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("Application Support/default.store")), Data("default.store".utf8))
        try Data("corrupted copy".utf8).write(to: copy.appendingPathComponent("Application Support/default.store"))
        XCTAssertThrowsError(try backup.verify())
    }

    func testInterruptedSnapshotCanRetryWithoutAccumulatingCopiesOrRemovingOtherBackups() throws {
        let backups = support.appendingPathComponent("UpgradeBackups")
        let incomplete = backups.appendingPathComponent(".incomplete-test")
        let previous = backups.appendingPathComponent("previous/keep.txt")
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("partial copy".utf8).write(to: incomplete.appendingPathComponent("partial"))
        let bytes = Data("original data".utf8)
        try bytes.write(to: storeURL)
        try bytes.write(to: previous)
        let backup = UpgradeBackup(applicationSupport: support, documents: documents,
            destination: backups.appendingPathComponent("test"))
        let copy = try backup.createIfNeeded()
        try backup.verify()
        XCTAssertFalse(FileManager.default.fileExists(atPath: incomplete.path))
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("Application Support/default.store")), bytes)
        XCTAssertEqual(try Data(contentsOf: storeURL), bytes)
        XCTAssertEqual(try Data(contentsOf: previous), bytes)
    }

    private func seedLegacyCache(at url: URL) throws {
        let schema = Schema(LegacyCacheSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let profile = LegacyStoreSchema.CachedProfile()
        profile.username = "existing-user"
        container.mainContext.insert(profile)
        container.mainContext.insert(LegacyStoreSchema.CachedPost())
        container.mainContext.insert(LegacyStoreSchema.CachedNotification())
        try container.mainContext.save()
    }

    private func seedLegacyStore(at url: URL) throws {
        let schema = Schema(LegacyStoreSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = container.mainContext
        let wallet = LegacyStoreSchema.Wallet()
        wallet.coins = 275
        let progress = LegacyStoreSchema.RewardProgress()
        progress.xp = 1234
        progress.weeklyGoalStreakLongest = 12
        let split = LegacyStoreSchema.WorkoutSplit()
        split.name = "Existing plan"
        split.cursor = 3
        let block = LegacyStoreSchema.PlanBlock()
        block.dayName = "Push"
        let exercise = LegacyStoreSchema.PlanBlockExercise()
        exercise.exerciseID = "bench-press"
        exercise.reps = 8
        exercise.startingWeight = 42.5
        block.exercises = [exercise]
        split.planBlocks = [block]
        let planned = LegacyStoreSchema.PlannedWorkout()
        let plannedExercise = LegacyStoreSchema.PlannedExercise()
        plannedExercise.ghostSets = [GhostSet(reps: 8, weight: 42.5)]
        planned.exercises = [plannedExercise]
        planned.splitID = split.id
        let anchor = LegacyStoreSchema.HealthSyncAnchor()
        anchor.dataType = "all_workouts"
        anchor.anchorData = Data([1, 2, 3])
        let plate = LegacyStoreSchema.EarnedPlate()
        plate.engravingText = "Existing achievement"
        plate.workoutsUsedCount = 37
        let models: [any PersistentModel] = [wallet, progress, split, block, exercise, planned, plannedExercise, anchor, plate,
            LegacyStoreSchema.Achievement(), LegacyStoreSchema.ChallengeAssignment(), LegacyStoreSchema.RewardLedgerEntry(),
            LegacyStoreSchema.ExercisePR(), LegacyStoreSchema.DexStamp(), LegacyStoreSchema.WeeklyTrainingSummary(),
            LegacyStoreSchema.DailyAppleExerciseSummary(), LegacyStoreSchema.ExerciseVolumeSummary(), LegacyStoreSchema.MovingAverage(),
            LegacyStoreSchema.ExerciseProgressionSummary(), LegacyStoreSchema.ExerciseTrend(), LegacyStoreSchema.PushPullBalance(),
            LegacyStoreSchema.MuscleGroupFrequency(), LegacyStoreSchema.MovementPatternBalance(), LegacyStoreSchema.WeeklyGoal(),
            LegacyStoreSchema.RouteFetchTask(), LegacyStoreSchema.MapSnapshotCache(), LegacyStoreSchema.BarbellPlateEvent(),
            LegacyStoreSchema.BarbellConfig(), LegacyStoreSchema.BarbellCosmeticUnlock(), LegacyStoreSchema.BarbellProcessedHKWorkout()]
        for model in models { context.insert(model) }
        try context.save()
    }

    private func assertCurrentRecords(_ context: ModelContext) throws {
        XCTAssertEqual(try context.fetch(FetchDescriptor<Wallet>()).first?.coins, 275)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardProgress>()).first?.xp, 1234)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardProgress>()).first?.weeklyGoalStreakLongest, 12)
        let split = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSplit>()).first)
        XCTAssertEqual(split.name, "Existing plan")
        XCTAssertEqual(split.cursor, 3)
        XCTAssertNil(split.planBlockOrder, "Migration must not invent an order for legacy plans")
        XCTAssertEqual(split.planBlocks.first?.exercises.first?.startingWeight, 42.5)
        let planned = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedWorkout>()).first)
        XCTAssertEqual(planned.splitID, split.id)
        XCTAssertEqual(planned.exercises.first?.ghostSets.first?.weight, 42.5)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HealthSyncAnchor>()).first?.anchorData, Data([1, 2, 3]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<EarnedPlate>()).first?.workoutsUsedCount, 37)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EarnedPlate>()).first?.engravingText, "Existing achievement")
        // Every entity in the legacy store must survive, including derived and operational data.
        let counts = try [
            context.fetchCount(FetchDescriptor<RewardProgress>()), context.fetchCount(FetchDescriptor<Achievement>()),
            context.fetchCount(FetchDescriptor<ChallengeAssignment>()), context.fetchCount(FetchDescriptor<RewardLedgerEntry>()),
            context.fetchCount(FetchDescriptor<Wallet>()), context.fetchCount(FetchDescriptor<ExercisePR>()),
            context.fetchCount(FetchDescriptor<DexStamp>()), context.fetchCount(FetchDescriptor<WeeklyTrainingSummary>()),
            context.fetchCount(FetchDescriptor<DailyAppleExerciseSummary>()), context.fetchCount(FetchDescriptor<ExerciseVolumeSummary>()),
            context.fetchCount(FetchDescriptor<MovingAverage>()), context.fetchCount(FetchDescriptor<ExerciseProgressionSummary>()),
            context.fetchCount(FetchDescriptor<ExerciseTrend>()), context.fetchCount(FetchDescriptor<PushPullBalance>()),
            context.fetchCount(FetchDescriptor<MuscleGroupFrequency>()), context.fetchCount(FetchDescriptor<MovementPatternBalance>()),
            context.fetchCount(FetchDescriptor<WeeklyGoal>()), context.fetchCount(FetchDescriptor<HealthSyncAnchor>()),
            context.fetchCount(FetchDescriptor<RouteFetchTask>()), context.fetchCount(FetchDescriptor<MapSnapshotCache>()),
            context.fetchCount(FetchDescriptor<PlannedWorkout>()), context.fetchCount(FetchDescriptor<PlannedExercise>()),
            context.fetchCount(FetchDescriptor<WorkoutSplit>()), context.fetchCount(FetchDescriptor<PlanBlock>()),
            context.fetchCount(FetchDescriptor<PlanBlockExercise>()), context.fetchCount(FetchDescriptor<EarnedPlate>()),
            context.fetchCount(FetchDescriptor<BarbellPlateEvent>()), context.fetchCount(FetchDescriptor<BarbellConfig>()),
            context.fetchCount(FetchDescriptor<BarbellCosmeticUnlock>()), context.fetchCount(FetchDescriptor<BarbellProcessedHKWorkout>())]
        XCTAssertEqual(counts, Array(repeating: 1, count: 30))
    }
}
