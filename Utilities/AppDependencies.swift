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

    /// Rewards engine - manages achievements and rewards
    let rewardsEngine: RewardsEngine

    /// Win screen coordinator - manages reward celebration screens
    let winScreenCoordinator: WinScreenCoordinator

    /// Planner store - manages workout planning and splits
    let plannerStore: PlannerStore

    // MARK: - Computed Services

    /// Stats aggregator - created lazily with model context
    /// Must be set after initialization with proper context
    @Published private(set) var statsAggregator: StatsAggregator?

    // MARK: - Initialization

    private init() {
        print("🏗️ Initializing AppDependencies...")

        // Initialize services in correct order
        self.exerciseRepository = ExerciseRepository.shared
        self.workoutStore = WorkoutStoreV2()
        self.healthKitManager = HealthKitManager.shared
        self.favoritesStore = FavoritesStore()
        self.rewardsEngine = RewardsEngine.shared
        self.winScreenCoordinator = WinScreenCoordinator.shared
        self.plannerStore = PlannerStore.shared

        print("✅ AppDependencies initialized")
    }

    // MARK: - Configuration

    /// Configure services that require ModelContext
    /// Call this once after app launch with the main model context
    func configure(with modelContext: ModelContext) {
        print("⚙️ Configuring AppDependencies with ModelContext...")

        // Configure HealthKit with required dependencies
        healthKitManager.modelContext = modelContext
        healthKitManager.workoutStore = workoutStore
        healthKitManager.registerBackgroundTasks()

        // Configure RewardsEngine
        rewardsEngine.configure(context: modelContext)
        print("⚙️ Rewards configured:", rewardsEngine.debugRulesSummary())

        // Create and configure stats aggregator
        let aggregator = StatsAggregator(container: modelContext.container)
        Task {
            await aggregator.setExerciseRepository(exerciseRepository)
            workoutStore.installStats(aggregator)
            self.statsAggregator = aggregator
            print("✅ Stats aggregator configured")
        }

        // Configure planner store
        plannerStore.configure(container: modelContext.container, context: modelContext, workoutStore: workoutStore)
        print("✅ Planner store configured")

        print("✅ AppDependencies configuration complete")
    }

    /// Bootstrap services that have async initialization
    func bootstrap() async {
        print("🚀 Bootstrapping AppDependencies...")

        // Bootstrap exercise repository
        exerciseRepository.bootstrap(useSlimPreload: true)

        // Check HealthKit authorization
        let authStatus = healthKitManager.store.authorizationStatus(for: .workoutType())
        print("🏥 HealthKit authorization status: \(authStatus.rawValue)")

        if authStatus == .sharingAuthorized {
            print("✅ HealthKit authorized - setting connected state")
            healthKitManager.connectionState = .connected
            healthKitManager.setupBackgroundObservers()
        } else {
            print("⚠️ HealthKit not authorized")
        }

        print("✅ AppDependencies bootstrap complete")
    }

    // MARK: - Memory Management

    /// Log current memory footprint of services
    func logMemoryFootprint() {
        print("💾 AppDependencies Memory Footprint:")
        print("   - ExerciseRepository: \(exerciseRepository.exercises.count) exercises")
        print("   - WorkoutStore: \(workoutStore.completedWorkouts.count) completed workouts")
        print("   - HealthKitManager: \(workoutStore.runs.count) runs")
        print("   - FavoritesStore: \(favoritesStore.ids.count) favorites")
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
