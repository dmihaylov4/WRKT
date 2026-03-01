import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import BackgroundTasks
import OSLog

// MARK: - Main App Entry Point

@main
struct WRKTApp: App {
    // Connect AppDelegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Create exactly once, with fallback handling
    private let container: ModelContainer
    private let containerError: Error?
    private let isCriticalError: Bool
    @State private var showStorageError = false
    @State private var showCriticalError = false

    init() {
        let result = Self.makeContainer()
        self.container = result.container
        self.containerError = result.error
        self.isCriticalError = result.isCritical

        // Show appropriate error alert based on severity
        if result.isCritical {
            _showCriticalError = State(initialValue: true)
        } else if result.error != nil {
            _showStorageError = State(initialValue: true)
        }

        // Configure navigation and tab bar appearances for accessibility
        configureUIKitAppearances()

        // Register background tasks BEFORE app finishes launching (required by iOS)
        registerBackgroundTasks()

        // Preload MuscleIndex synchronously during app init to avoid first-render lag
        // This triggers the expensive SVG parsing during app launch (split-screen splash)
        // instead of blocking the UI when user first opens exercise info
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = MuscleIndex.shared  // Force initialization synchronously
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        AppLogger.success("MuscleIndex preloaded in \(String(format: "%.2f", elapsed * 1000))ms", category: AppLogger.app)

        // Initialize image cache service for social features
        _ = ImageCacheService.shared
        AppLogger.success("Image cache configured (50MB memory, 100MB disk)", category: AppLogger.app)

        // Set up notification delegate to handle notification interactions
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            center.delegate = NotificationManager.shared
            AppLogger.success("Notification delegate configured", category: AppLogger.app)

            // Setup smart nudge notification categories
            await SmartNudgeManager.shared.setupNotificationCategories()

            // Reset daily nudge counters on app launch
            SmartNudgeManager.shared.resetDailyCounts()

            // Register for push notifications
            await PushNotificationService.shared.registerForPushNotifications()

            // Trigger incremental sync on app launch if connected
            if HealthKitManager.shared.connectionState == .connected {
                AppLogger.info("App launched - triggering incremental HealthKit sync", category: AppLogger.health)
                Task {
                    try? await HealthKitManager.shared.syncWorkoutsIncremental()
                }
            }
        }
    }

    private func registerBackgroundTasks() {
        let taskID = "com.dmihaylov.trak.health.sync"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                AppLogger.error("Background task is not a BGProcessingTask", category: AppLogger.health)
                task.setTaskCompleted(success: false)
                return
            }

            // Delegate to HealthKitManager for actual processing
            AppLogger.info("Background task launched: \(taskID)", category: AppLogger.health)
            HealthKitManager.shared.handleHealthSyncTask(task: processingTask)
        }
        AppLogger.success("Background task registered: \(taskID)", category: AppLogger.health)
    }

    /// Configure UIKit navigation and tab bar appearances to maintain dark backgrounds
    /// even when "Reduce Transparency" accessibility setting is enabled
    private func configureUIKitAppearances() {
        // MARK: - Navigation Bar Configuration
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()

        // Set dark background that persists with Reduce Transparency
        navBarAppearance.backgroundColor = UIColor(Color(hex: "#000000"))
        navBarAppearance.shadowColor = UIColor(Color(hex: "#000000"))

        // Configure title and button colors for visibility
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        navBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white
        ]

        // Configure button colors (back button, toolbar buttons, etc.)
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: "#CCFF00"))]
        navBarAppearance.buttonAppearance = buttonAppearance
        navBarAppearance.backButtonAppearance = buttonAppearance
        navBarAppearance.doneButtonAppearance = buttonAppearance

        // Set tint color for navigation bar icons
        UINavigationBar.appearance().tintColor = UIColor(Color(hex: "#CCFF00"))

        // Apply to all navigation bar states
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().compactScrollEdgeAppearance = navBarAppearance
        }

        // MARK: - Tab Bar Configuration
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()

        // Set dark background that persists with Reduce Transparency
        tabBarAppearance.backgroundColor = UIColor(Color(hex: "#000000"))
        tabBarAppearance.shadowColor = UIColor(Color(hex: "#000000"))

        // Configure tab item colors
        // Normal (unselected) state - white with lower opacity
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.6)
        ]

        // Selected state - accent yellow
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "#CCFF00"))
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color(hex: "#CCFF00"))
        ]

        // Apply same configuration to inline and compact layouts
        tabBarAppearance.inlineLayoutAppearance = tabBarAppearance.stackedLayoutAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabBarAppearance.stackedLayoutAppearance

        // Apply to all tab bar states
        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }

        // Set tint color for tab bar
        UITabBar.appearance().tintColor = UIColor(Color(hex: "#CCFF00"))
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.6)

        AppLogger.success("UIKit appearances configured for accessibility (Reduce Transparency support)", category: AppLogger.app)
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .modelContainer(container)   // <- reuse the same instance
                .preferredColorScheme(.dark)  // Force dark mode throughout the app
                .onOpenURL { url in
                    handleURL(url)
                }
                .alert("Storage Warning", isPresented: $showStorageError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("App data storage encountered an issue and is running in temporary mode. Your data may not be saved permanently. Error: \(containerError?.localizedDescription ?? "Unknown error")")
                }
                .alert("Critical Storage Error", isPresented: $showCriticalError) {
                    Button("Continue", role: .cancel) {
                        // User acknowledges risk and continues with limited functionality
                        AppLogger.warning("User chose to continue despite critical storage error", category: AppLogger.storage)
                    }
                } message: {
                    Text("Unable to initialize data storage. The app is running in limited mode and data may not be saved.\n\nPlease try:\n• Force closing and reopening the app\n• Restarting your device\n• Reinstalling the app if issue persists\n\nError: \(containerError?.localizedDescription ?? "Unknown error")")
                }
        }
    }

    private func handleURL(_ url: URL) {
        AppLogger.info("Received URL: \(url.absoluteString)", category: AppLogger.app)

        // Handle wrkt:// URL scheme
        if url.scheme == "wrkt" {
            // Check for password recovery deep link
            if url.host == "auth" && url.path.contains("recovery") {
                AppLogger.info("Handling password recovery deep link", category: AppLogger.app)
                Task {
                    await handlePasswordRecoveryDeepLink(url: url)
                }
            }
            // Handle email confirmation deep link
            else if url.host == "auth" {
                AppLogger.info("Handling email verification deep link", category: AppLogger.app)
                Task {
                    await handleEmailVerificationDeepLink()
                }
            } else {
                AppLogger.info("Opening app from watch", category: AppLogger.app)
                // App will open automatically, no additional action needed
            }
        }
    }

    private func handlePasswordRecoveryDeepLink(url: URL) async {
        let authService = SupabaseAuthService.shared
        await authService.handlePasswordRecovery(url: url)
    }

    private func handleEmailVerificationDeepLink() async {
        let authService = SupabaseAuthService.shared

        // Check if user is verified
        let isVerified = await authService.checkEmailVerified()

        if isVerified {
            AppLogger.success("Email verified successfully, restoring session", category: AppLogger.app)
            // Restore session (will fetch profile and log them in)
            await authService.restoreSession()
            authService.clearSignupState()
        } else {
            AppLogger.warning("Email not yet verified", category: AppLogger.app)
        }
    }

    static func makeContainer() -> (container: ModelContainer, error: Error?, isCritical: Bool) {
        // Create schema with all models
        let schema = Schema([
            RewardProgress.self, Achievement.self, ChallengeAssignment.self, RewardLedgerEntry.self,
            Wallet.self, ExercisePR.self, DexStamp.self, WeeklyTrainingSummary.self, ExerciseVolumeSummary.self,
            MovingAverage.self, ExerciseProgressionSummary.self, ExerciseTrend.self, PushPullBalance.self,
            MuscleGroupFrequency.self, MovementPatternBalance.self, WeeklyGoal.self,
            HealthSyncAnchor.self, RouteFetchTask.self, MapSnapshotCache.self,
            PlannedWorkout.self, PlannedExercise.self, WorkoutSplit.self, PlanBlock.self, PlanBlockExercise.self
        ])

        // Attempt to create persistent container with file protection
        let persistentConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: persistentConfig)
            AppLogger.success("ModelContainer initialized successfully (persistent storage)", category: AppLogger.storage)
            return (container, nil, false)
        } catch {
            // Log the error for debugging
            AppLogger.error("Failed to create persistent ModelContainer", error: error, category: AppLogger.storage)

            // Fallback to in-memory container so app can continue
            let inMemoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: false,
                groupContainer: .none,
                cloudKitDatabase: .none
            )

            do {
                let fallbackContainer = try ModelContainer(for: schema, configurations: inMemoryConfig)
                AppLogger.success("Fallback to in-memory ModelContainer successful", category: AppLogger.storage)
                return (fallbackContainer, error, false)
            } catch let fallbackError {
                // If even in-memory fails, try one last time with an empty schema as absolute fallback
                AppLogger.critical("Both persistent and in-memory container creation failed. Attempting emergency fallback with empty schema.", category: AppLogger.storage)

                let emptySchema = Schema([])
                let emergencyConfig = ModelConfiguration(
                    schema: emptySchema,
                    isStoredInMemoryOnly: true,
                    allowsSave: false,
                    groupContainer: .none,
                    cloudKitDatabase: .none
                )

                do {
                    let emergencyContainer = try ModelContainer(for: emptySchema, configurations: emergencyConfig)
                    AppLogger.warning("Emergency fallback container created with empty schema. App will not function normally.", category: AppLogger.storage)
                    // Return with critical error flag set
                    return (emergencyContainer, fallbackError, true)
                } catch let emergencyError {
                    // This should theoretically never happen, but if it does, we have no choice
                    AppLogger.critical("Complete failure: All container creation attempts failed. Persistent: \(error.localizedDescription), In-memory: \(fallbackError.localizedDescription), Emergency: \(emergencyError.localizedDescription)", category: AppLogger.storage)

                    // Last resort: create the absolute simplest container with default configuration
                    // This allows the app to show the error UI instead of crashing immediately
                    do {
                        let minimalContainer = try ModelContainer(for: emptySchema)
                        AppLogger.critical("All storage mechanisms failed, running in minimal emergency mode", category: AppLogger.storage)
                        return (minimalContainer, fallbackError, true)
                    } catch {
                        AppLogger.critical("Complete storage failure - app cannot initialize storage", category: AppLogger.storage)
                        // If even this fails, we must crash, but we've logged everything for debugging
                        // Using preconditionFailure instead of fatalError to allow debugging in debug builds
                        preconditionFailure("Unable to initialize any ModelContainer. This indicates a serious system-level issue. Please reinstall the app. Errors - Persistent: \(error), In-memory: \(fallbackError), Emergency: \(emergencyError)")
                    }
                }
            }
        }
    }
}
