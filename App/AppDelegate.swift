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
        if healthKit.connectionState == .connected {
            let storage = WRKTApp.storage
            if let container = storage.container {
                AppDependencies.shared.configureHealthSync(with: container.mainContext)
            }
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
        let storage = WRKTApp.storage
        storage.retry()
        guard let container = storage.container else { return }
        AppDependencies.shared.configureHealthSync(with: container.mainContext)
        Task { await HealthKitManager.shared.catchUpHealthChanges() }
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
