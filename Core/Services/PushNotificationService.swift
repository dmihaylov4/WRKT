import Foundation
import UIKit
import UserNotifications
import Supabase
import Combine

/// Service to handle APNs push notification registration and token management
@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var deviceToken: String?
    @Published private(set) var isRegistered = false

    private override init() {
        super.init()
    }

    // MARK: - Registration

    /// Register for remote notifications
    func registerForPushNotifications() async {
        let center = UNUserNotificationCenter.current()

        // Check current authorization status
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // Request authorization
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    await registerWithAPNs()
                } else {
                    AppLogger.warning("User denied push notification permission", category: AppLogger.app)
                }
            } catch {
                AppLogger.error("Failed to request notification authorization", error: error, category: AppLogger.app)
            }

        case .authorized, .provisional, .ephemeral:
            await registerWithAPNs()

        case .denied:
            AppLogger.info("Push notifications are denied. User can enable in Settings.", category: AppLogger.app)

        @unknown default:
            break
        }
    }

    /// Register with APNs to get device token
    private func registerWithAPNs() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        AppLogger.info("Registering for remote notifications...", category: AppLogger.app)
    }

    // MARK: - Token Handling

    /// Called when APNs registration succeeds
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        self.deviceToken = tokenString
        self.isRegistered = true

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        AppLogger.success("Registered for remote notifications. Environment: \(environment)", category: AppLogger.app)

        // Upload token to Supabase if user is logged in
        Task {
            await uploadTokenToServer()
        }
    }

    /// Called when APNs registration fails
    func didFailToRegisterForRemoteNotifications(error: Error) {
        AppLogger.error("Failed to register for remote notifications", error: error, category: AppLogger.app)
        self.isRegistered = false
    }

    // MARK: - Server Sync

    /// Upload device token to Supabase
    func uploadTokenToServer() async {
        guard let token = deviceToken else {
            AppLogger.debug("No device token to upload", category: AppLogger.app)
            return
        }

        // Check if user is logged in
        guard let userId = SupabaseAuthService.shared.currentUser?.id else {
            AppLogger.debug("User not logged in, skipping token upload", category: AppLogger.app)
            return
        }

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        let client = SupabaseClientWrapper.shared.client

        do {
            // Use the upsert_device_token function
            try await client
                .rpc("upsert_device_token", params: [
                    "p_user_id": userId.uuidString,
                    "p_token": token,
                    "p_platform": "ios",
                    "p_environment": environment
                ])
                .execute()

            AppLogger.success("Device token uploaded to server", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to upload device token", error: error, category: AppLogger.app)
        }
    }

    /// Remove device token from server (call on logout)
    func removeTokenFromServer() async {
        guard let token = deviceToken else { return }

        let client = SupabaseClientWrapper.shared.client

        do {
            try await client
                .from("device_tokens")
                .delete()
                .eq("token", value: token)
                .execute()

            AppLogger.success("Device token removed from server", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to remove device token", error: error, category: AppLogger.app)
        }

        deviceToken = nil
        isRegistered = false
    }

    // MARK: - Notification Handling

    /// Handle received remote notification
    func handleRemoteNotification(userInfo: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) {
        AppLogger.info("Received remote notification: \(userInfo)", category: AppLogger.app)

        // Parse notification data
        if let notificationType = userInfo["type"] as? String {
            AppLogger.info("Notification type: \(notificationType)", category: AppLogger.app)

            // Post notification for the app to handle navigation
            NotificationCenter.default.post(
                name: .didReceivePushNotification,
                object: nil,
                userInfo: userInfo
            )
        }

        completion(.newData)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceivePushNotification = Notification.Name("didReceivePushNotification")
}
