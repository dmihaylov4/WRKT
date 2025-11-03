//
//  AppDependencies.swift
//  WRKT
//
//  Centralized dependency container for app services
//  Ensures single source of truth and efficient memory usage
//

import SwiftUI
import SwiftData
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
    let workoutStore: WorkoutStore

    /// HealthKit manager - syncs with Apple Health
    let healthKitManager: HealthKitManager

    /// Favorites store - manages user's favorite exercises
    let favoritesStore: FavoritesStore

    /// Rewards engine - manages achievements and rewards
    let rewardsEngine: RewardsEngine

    /// Win screen coordinator - manages reward celebration screens
    let winScreenCoordinator: WinScreenCoordinator

    // MARK: - Computed Services

    /// Stats aggregator - created lazily with model context
    /// Must be set after initialization with proper context
    @Published private(set) var statsAggregator: StatsAggregator?

    // MARK: - Initialization

    private init() {
        AppLogger.info("Initializing AppDependencies...", category: AppLogger.app)

        // Initialize services in correct order
        self.exerciseRepository = ExerciseRepository.shared
        self.workoutStore = WorkoutStore()
        self.healthKitManager = HealthKitManager.shared
        self.favoritesStore = FavoritesStore()
        self.rewardsEngine = RewardsEngine.shared
        self.winScreenCoordinator = WinScreenCoordinator.shared

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
        healthKitManager.registerBackgroundTasks()

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

        AppLogger.success("AppDependencies configuration complete", category: AppLogger.app)
    }

    /// Bootstrap services that have async initialization
    func bootstrap() async {
        AppLogger.info("Bootstrapping AppDependencies...", category: AppLogger.app)

        // Bootstrap exercise repository
        exerciseRepository.bootstrap(useSlimPreload: true)

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

    // MARK: - Memory Management

    /// Log current memory footprint of services
    func logMemoryFootprint() {
        AppLogger.info("AppDependencies Memory Footprint - ExerciseRepository: \(exerciseRepository.exercises.count) exercises, WorkoutStore: \(workoutStore.completedWorkouts.count) completed workouts, HealthKitManager: \(workoutStore.runs.count) runs, FavoritesStore: \(favoritesStore.favoriteIDs.count) favorites", category: AppLogger.performance)
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
            .environment(\.dependencies, dependencies)
    }
}
