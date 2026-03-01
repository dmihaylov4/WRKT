//
//  Notifications.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 07.10.25.
//

import Foundation
import UserNotifications
import Combine
extension Notification.Name {

    static let resetHomeToRoot = Notification.Name("resetHomeToRoot")
       static let openHomeRoot    = Notification.Name("openHomeRoot")
       static let homeTabReselected = Notification.Name("homeTabReselected")
       static let calendarTabReselected = Notification.Name("calendarTabReselected")
       static let cardioTabReselected = Notification.Name("cardioTabReselected")
       static let socialTabReselected = Notification.Name("socialTabReselected")
       static let tabSelectionChanged = Notification.Name("tabSelectionChanged")
       static let tabDidChange = Notification.Name("tabDidChange")
       static let openLiveOverlay = Notification.Name("openLiveOverlay")
       static let dismissLiveOverlay = Notification.Name("dismissLiveOverlay")
       static let rewardsDidSummarize = Notification.Name("rewardsDidSummarize")
       static let friendshipStatusChanged = Notification.Name("friendshipStatusChanged")
}

// MARK: - NotificationManager

/// Manages user notifications and handles notification interactions
@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        Task {
            await checkAuthorizationStatus()
        }
    }

    /// Request notification permissions from the user
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                AppLogger.success("Notification permissions granted", category: AppLogger.app)
            } else {
                AppLogger.warning("Notification permissions denied", category: AppLogger.app)
            }
            await checkAuthorizationStatus()
        } catch {
            AppLogger.error("Notification permission error", error: error, category: AppLogger.app)
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        AppLogger.debug("Notification received: \(userInfo)", category: AppLogger.app)

        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        AppLogger.debug("Notification tapped: \(userInfo)", category: AppLogger.app)

        // Handle notification tap - route to appropriate view based on notification type
        // This can be expanded based on different notification types

        completionHandler()
    }
}
