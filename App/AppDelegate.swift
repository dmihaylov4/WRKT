import UIKit
import UserNotifications
import SwiftData

/// AppDelegate to handle push notification registration callbacks
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.info("AppDelegate: didFinishLaunchingWithOptions", category: AppLogger.app)
        let healthKit = HealthKitManager.shared
        // The store opens asynchronously. Every delivery and catch-up, including the BGProcessing
        // task, waits for it here and is configured against it before writing anything.
        healthKit.prepareForSync = { _ = await Self.configureHealthSyncWhenOpen() }
        if healthKit.connectionState == .connected {
            // Registered during launch so a background delivery that woke the app is received.
            healthKit.setupBackgroundObservers()
            Task { await healthKit.catchUpHealthChanges() }
        }
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in
                PushNotificationService.shared.storeLaunchNotification(userInfo: userInfo)
            }
        }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task {
            let storage = WRKTApp.storage
            // An open started while the device was locked may still be running; let it finish
            // (it fails on protected files) so the retry below is not swallowed by it.
            _ = await storage.openedContainer()
            storage.retry()
            guard await Self.configureHealthSyncWhenOpen() else { return }
            await HealthKitManager.shared.catchUpHealthChanges()
        }
    }

    /// Configures health sync once the user store is open. Never touches app services before that.
    @MainActor
    static func configureHealthSyncWhenOpen() async -> Bool {
        guard let container = await WRKTApp.storage.openedContainer() else { return false }
        AppDependencies.shared.configureHealthSync(with: container.mainContext)
        return true
    }

    // MARK: - Push Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    // MARK: - Remote Notification Handling

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRemoteNotification(
                userInfo: userInfo,
                completion: completionHandler
            )
        }
    }
}
