//
//  AppDependencies.swift
//  WRKT
//
//  Centralized dependency container for app services
//  Ensures single source of truth and efficient memory usage
//

import SwiftUI
import SwiftData
import Combine
import HealthKit
import OSLog
/// Main dependency container holding all app services
/// Created once at app launch and shared throughout the app lifecycle
@MainActor
final class AppDependencies: ObservableObject {
    // MARK: - Singleton
    static let shared = AppDependencies()

    // MARK: - Core Services

    /// Exercise repository - manages exercise database and media
    let exerciseRepository: ExerciseRepository

    /// Workout store - manages current and completed workouts
    let workoutStore: WorkoutStoreV2

    /// HealthKit manager - syncs with Apple Health
    let healthKitManager: HealthKitManager

    /// Favorites store - manages user's favorite exercises
    let favoritesStore: FavoritesStore

    /// Custom exercise store - manages user-created exercises
    let customExerciseStore: CustomExerciseStore

    /// Rewards engine - manages achievements and rewards
    let rewardsEngine: RewardsEngine

    /// Win screen coordinator - manages reward celebration screens
    let winScreenCoordinator: WinScreenCoordinator

    /// Planner store - manages workout planning and splits
    let plannerStore: PlannerStore

    /// Custom split store - manages user-created workout splits
    let customSplitStore: CustomSplitStore

    /// Supabase auth service - manages user authentication and social features
    let authService: SupabaseAuthService

    /// Friendship repository - manages friend requests and friendships
    let friendshipRepository: FriendshipRepository

    /// Post repository - manages workout posts, likes, and comments
    let postRepository: PostRepository

    /// Profile repository - manages user profiles
    let profileRepository: ProfileRepository

    /// Image upload service - manages image uploads to Supabase Storage
    let imageUploadService: ImageUploadService

    /// Notification repository - manages activity feed notifications
    let notificationRepository: NotificationRepository

    /// Realtime service - manages Supabase Realtime subscriptions for live updates
    let realtimeService: RealtimeService

    /// Challenge repository - manages community challenges and user participation
    let challengeRepository: ChallengeRepository

    /// Battle repository - manages 1v1 battles between friends
    let battleRepository: BattleRepository

    /// Virtual run repository - manages virtual running together sessions
    let virtualRunRepository: VirtualRunRepository

    // MARK: - Computed Services

    /// Stats aggregator - created lazily with model context
    /// Must be set after initialization with proper context
    @Published private(set) var statsAggregator: StatsAggregator?

    // MARK: - Initialization

    private init() {
        AppLogger.info("Initializing AppDependencies...", category: AppLogger.app)

        // Initialize services in correct order
        self.exerciseRepository = ExerciseRepository.shared
        self.workoutStore = WorkoutStoreV2()
        self.healthKitManager = HealthKitManager.shared
        self.favoritesStore = FavoritesStore()
        self.customExerciseStore = CustomExerciseStore.shared
        self.rewardsEngine = RewardsEngine.shared
        self.winScreenCoordinator = WinScreenCoordinator.shared
        self.plannerStore = PlannerStore.shared
        self.customSplitStore = CustomSplitStore.shared
        self.authService = SupabaseAuthService.shared
        self.friendshipRepository = FriendshipRepository()
        self.postRepository = PostRepository()
        self.profileRepository = ProfileRepository()
        self.imageUploadService = ImageUploadService()
        self.notificationRepository = NotificationRepository()
        self.realtimeService = RealtimeService()
        self.challengeRepository = ChallengeRepository(supabase: SupabaseClientWrapper.shared.client, authService: self.authService)
        self.battleRepository = BattleRepository(supabase: SupabaseClientWrapper.shared.client, authService: self.authService)
        self.virtualRunRepository = VirtualRunRepository()

        AppLogger.success("AppDependencies initialized", category: AppLogger.app)
    }

    // MARK: - Configuration

    /// Configure services that require ModelContext
    /// Call this once after app launch with the main model context
    func configure(with modelContext: ModelContext) {
        AppLogger.info("Configuring AppDependencies with ModelContext...", category: AppLogger.app)

        // Configure HealthKit with required dependencies
        healthKitManager.modelContext = modelContext
        healthKitManager.workoutStore = workoutStore
        // Note: Background tasks are registered in WRKTApp.init() before app finishes launching

        // Configure RewardsEngine
        rewardsEngine.configure(context: modelContext)
        AppLogger.info("Rewards configured: \(rewardsEngine.debugRulesSummary())", category: AppLogger.rewards)

        // Create and configure stats aggregator
        let aggregator = StatsAggregator(container: modelContext.container)
        Task {
            await aggregator.setExerciseRepository(exerciseRepository)
            workoutStore.installStats(aggregator)
            self.statsAggregator = aggregator
            AppLogger.success("Stats aggregator configured", category: AppLogger.app)
        }

        // Configure planner store
        plannerStore.configure(container: modelContext.container, context: modelContext, workoutStore: workoutStore)
        AppLogger.success("Planner store configured", category: AppLogger.app)

        // Wire up competitive features to workout store
        workoutStore.battleRepository = battleRepository
        workoutStore.challengeRepository = challengeRepository
        workoutStore.authService = authService
        AppLogger.success("Competitive features wired to workout store", category: AppLogger.app)

        // Wire up virtual run repository to WatchConnectivity
        WatchConnectivityManager.shared.virtualRunRepository = virtualRunRepository
        AppLogger.success("Virtual run repository wired to WatchConnectivity", category: AppLogger.app)

        AppLogger.success("AppDependencies configuration complete", category: AppLogger.app)
    }

    /// Bootstrap services that have async initialization
    func bootstrap() async {
        AppLogger.info("Bootstrapping AppDependencies...", category: AppLogger.app)

        // Bootstrap exercise repository (starts loading in background)
        exerciseRepository.bootstrap(useSlimPreload: true)

        // CRITICAL: Wait for FULL catalog to load before computing stats
        // The slim catalog (50 exercises) has no force/muscle data needed for classification
        AppLogger.info("Waiting for full exercise catalog to load...", category: AppLogger.app)
        var retries = 0
        while !exerciseRepository.didLoadFull && retries < 100 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            retries += 1
        }

        if exerciseRepository.didLoadFull {
            AppLogger.success("Full catalog loaded: \(exerciseRepository.exercises.count) exercises", category: AppLogger.app)
        } else {
            AppLogger.warning("Timeout waiting for full catalog after 10 seconds", category: AppLogger.app)
        }

        // Now trigger stats reindex with FULL exercise data
        if let stats = statsAggregator, workoutStore.completedWorkouts.count > 0 {
            AppLogger.info("Triggering initial stats reindex with full catalog", category: AppLogger.statistics)
            if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) {
                await stats.reindex(all: workoutStore.completedWorkouts, cutoff: cutoff)
            }
        }

        // Migrate exercise IDs in planned workouts (if needed)
        migrateExerciseIDsIfNeeded()

        // Check HealthKit connection state
        // Note: We check connectionState instead of authorizationStatus because
        // HealthKit's authorizationStatus is intentionally unreliable for privacy reasons.
        // The HealthKitManager uses testDataAccess() to verify actual access.
        let connectionState = healthKitManager.connectionState
        AppLogger.info("HealthKit connection state: \(connectionState)", category: AppLogger.health)

        if connectionState == .connected {
            AppLogger.success("HealthKit connected - setting up background observers", category: AppLogger.health)
            healthKitManager.setupBackgroundObservers()
        } else if connectionState == .disconnected {
            AppLogger.warning("HealthKit not authorized or access denied", category: AppLogger.health)
        } else {
            AppLogger.info("HealthKit authorization not yet determined", category: AppLogger.health)
        }

        AppLogger.success("AppDependencies bootstrap complete", category: AppLogger.app)
    }

    /// Migrate exercise IDs in planned workouts (one-time migration)
    private func migrateExerciseIDsIfNeeded() {
        let migrationKey = "exerciseIDMigration_v1_completed"

        // Check if migration already completed
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            AppLogger.debug("Exercise ID migration already completed", category: AppLogger.storage)
            return
        }

        // Map of old IDs → new IDs
        let idMapping: [String: String] = [
            "shoulder-press": "barbell-overhead-press",
            // Add any other mismatched IDs below if you find them in the logs
            // For example, if logs show generic IDs that should be specific:
            // "leg-press": "machine-45-degree-leg-press",
            // "leg-curl": "machine-seated-leg-curl",
        ]

        do {
            try plannerStore.migrateExerciseIDs(mapping: idMapping)

            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: migrationKey)
            AppLogger.success("✅ Exercise ID migration completed successfully", category: AppLogger.storage)
        } catch {
            AppLogger.error("Failed to migrate exercise IDs", error: error, category: AppLogger.storage)
        }
    }

    // MARK: - Memory Management

    /// Log current memory footprint of services
    func logMemoryFootprint() {
        AppLogger.info("AppDependencies Memory Footprint - ExerciseRepository: \(exerciseRepository.exercises.count) exercises, WorkoutStore: \(workoutStore.completedWorkouts.count) completed workouts, HealthKitManager: \(workoutStore.runs.count) runs, FavoritesStore: \(favoritesStore.ids.count) favorites, CustomExerciseStore: \(customExerciseStore.customExercises.count) custom exercises", category: AppLogger.performance)
    }
}

// MARK: - Environment Key

/// Environment key for injecting dependencies throughout the app
struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.shared
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Inject all app dependencies as environment objects
    func withDependencies(_ dependencies: AppDependencies = .shared) -> some View {
        self
            .environmentObject(dependencies.exerciseRepository)
            .environmentObject(dependencies.workoutStore)
            .environmentObject(dependencies.healthKitManager)
            .environmentObject(dependencies.favoritesStore)
            .environmentObject(dependencies.customExerciseStore)
            .environmentObject(dependencies.customSplitStore)
            .environmentObject(dependencies.authService)
            .environmentObject(dependencies.imageUploadService)
            .environment(\.dependencies, dependencies)
    }
}
