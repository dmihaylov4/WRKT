import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import BackgroundTasks
import OSLog

// MARK: - Main App Entry Point

@main
struct WRKTApp: App {
    static let storage = AppDataStore()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var dataStore = WRKTApp.storage

    init() {
        _ = DS.Redesign.roundedShapesEnabled

        // Configure navigation and tab bar appearances for accessibility
        configureUIKitAppearances()

        // Register background tasks BEFORE app finishes launching (required by iOS)
        registerBackgroundTasks()
    }

    @MainActor
    private func prepareServices() async {
        // Prepare optional services only after the user database opens successfully.
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = MuscleIndex.shared  // Force initialization synchronously
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        AppLogger.success("MuscleIndex preloaded in \(String(format: "%.2f", elapsed * 1000))ms", category: AppLogger.app)

        // Initialize image cache service for social features
        _ = ImageCacheService.shared
        AppLogger.success("Image cache configured (50MB memory, 100MB disk)", category: AppLogger.app)

        // Configure Google Sign-In
        SignInWithGoogleService.shared.configure()
        AppLogger.success("Google Sign-In configured", category: AppLogger.app)

        // Set up notification delegate to handle notification interactions
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationManager.shared
        AppLogger.success("Notification delegate configured", category: AppLogger.app)

        // Setup smart nudge notification categories
        await SmartNudgeManager.shared.setupNotificationCategories()

        // Reset daily nudge counters on app launch
        SmartNudgeManager.shared.resetDailyCounts()

        // Register for push notifications
        await PushNotificationService.shared.registerForPushNotifications()
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
        if DS.Redesign.usesSystemShell {
            // System shell: keep the default background so bars render as Liquid Glass
            navBarAppearance.configureWithDefaultBackground()
        } else {
            navBarAppearance.configureWithOpaqueBackground()

            // Set dark background that persists with Reduce Transparency
            navBarAppearance.backgroundColor = UIColor(Color(hex: "#000000"))
            navBarAppearance.shadowColor = UIColor(Color(hex: "#000000"))
        }

        // Configure title and button colors for visibility
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: DS.Typography.uiFont(.navigationTitle)
        ]
        navBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: DS.Typography.uiFont(.navigationLargeTitle)
        ]

        // Configure button colors (back button, toolbar buttons, etc.)
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color(hex: "#CCFF00")),
            .font: DS.Typography.uiFont(.buttonRegular)
        ]
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

        // System shell: the system tab bar keeps its default Liquid Glass appearance
        // and must stay visible, so skip the opaque tab bar setup and the hiding below.
        guard !DS.Redesign.usesSystemShell else {
            AppLogger.success("UIKit appearances configured for the system shell", category: AppLogger.app)
            return
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
            .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            .font: DS.Typography.uiFont(.tabLabel)
        ]

        // Selected state - accent yellow
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "#CCFF00"))
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color(hex: "#CCFF00")),
            .font: DS.Typography.uiFont(.tabLabel)
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

        // Hide native tab bar — app uses a fully custom tab bar via safeAreaInset
        UITabBar.appearance().isHidden = true

        AppLogger.success("UIKit appearances configured for accessibility (Reduce Transparency support)", category: AppLogger.app)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = dataStore.container {
                    WorkoutDataGate(recoveryCopy: dataStore.recoveryCopy)
                        .modelContainer(container)
                        .task { await prepareServices() }
                } else {
                    StorageRecoveryView(recoveryCopy: dataStore.recoveryCopy, retry: dataStore.retry)
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                guard dataStore.container != nil else { return }
                handleURL(url)
            }
        }
    }

    private func handleURL(_ url: URL) {
        AppLogger.info("Received URL: \(url.absoluteString)", category: AppLogger.app)

        // Forward Google Sign-In redirect URLs to GoogleSignIn SDK first
        if SignInWithGoogleService.shared.handleURL(url) {
            return
        }

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
                    await handleEmailVerificationDeepLink(url: url)
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

    private func handleEmailVerificationDeepLink(url: URL) async {
        let authService = SupabaseAuthService.shared
        await authService.handleEmailConfirmation(url: url)
    }

}
