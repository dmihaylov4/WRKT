import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Main App Entry Point

@main
struct WRKTApp: App {
    // Create exactly once
    private let container: ModelContainer

    init() {
        self.container = Self.makeContainer()

        // Request notification permissions for rest timer
        requestNotificationPermissions()
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()

        // Request authorization for alerts, sounds, and badges
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error)")
            } else if granted {
                print("✅ Notification permissions granted")
            } else {
                print("⚠️ Notification permissions denied by user")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .modelContainer(container)   // <- reuse the same instance
        }
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            RewardProgress.self, Achievement.self, ChallengeAssignment.self, RewardLedgerEntry.self,
            Wallet.self, ExercisePR.self, DexStamp.self, WeeklyTrainingSummary.self, ExerciseVolumeSummary.self,
            MovingAverage.self, ExerciseProgressionSummary.self, ExerciseTrend.self, PushPullBalance.self,
            MuscleGroupFrequency.self, MovementPatternBalance.self, WeeklyGoal.self,
            HealthSyncAnchor.self, RouteFetchTask.self, MapSnapshotCache.self,
            PlannedWorkout.self, PlannedExercise.self, WorkoutSplit.self, PlanBlock.self, PlanBlockExercise.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do { return try ModelContainer(for: schema, configurations: config) }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }
}
