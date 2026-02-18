//
//  ActivityFeedViewModel.swift
//  WRKT
//
//  ViewModel for activity feed showing notifications
//

import Foundation

@MainActor
@Observable
final class ActivityFeedViewModel {
    private let notificationRepository: NotificationRepository
    private let authService: SupabaseAuthService
    private let realtimeService: RealtimeService

    var notifications: [NotificationWithActor] = []
    var isLoading = false
    var error: UserFriendlyError?
    var newNotificationsCount = 0 // Count of new unread notifications

    private var realtimeChannelId: String?
    private let retryManager = RetryManager.shared
    private let errorHandler = ErrorHandler.shared

    init(notificationRepository: NotificationRepository, authService: SupabaseAuthService, realtimeService: RealtimeService) {
        self.notificationRepository = notificationRepository
        self.authService = authService
        self.realtimeService = realtimeService
    }

    deinit {
        // Don't create async tasks in deinit as they create retain cycles
        // cleanup() will be called from the view's onDisappear
        
    }

    func loadNotifications() async {
        guard let userId = authService.currentUser?.id else { return }

        isLoading = true
        error = nil

        let result = await retryManager.fetchWithRetry {
            try await self.notificationRepository.fetchNotifications(userId: userId)
        }

        switch result {
        case .success(let notifs):
            notifications = notifs
            error = nil
            isLoading = false

        case .failure(let err, let attempts):
           
            let userError = errorHandler.handleError(err, context: .notification)
            errorHandler.logError(userError, context: .notification)
            self.error = userError
            isLoading = false
        }
    }

    func markAsRead(_ notification: NotificationWithActor) async {
        guard !notification.read else { return }

        do {
            try await notificationRepository.markAsRead(notificationId: notification.id)

            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                var updated = notifications[index]
                updated.notification.read = true
                notifications[index] = updated
            }
        } catch {
            let userError = errorHandler.handleError(error, context: .notification)
            self.error = userError
        }
    }

    func markAllAsRead() async {
        guard let userId = authService.currentUser?.id else { return }

        do {
            try await notificationRepository.markAllAsRead(userId: userId)

            // Update all local notifications
            notifications = notifications.map { notification in
                var updated = notification
                updated.notification.read = true
                return updated
            }
        } catch {
            let userError = errorHandler.handleError(error, context: .notification)
            self.error = userError
        }
    }

    func deleteNotification(_ notification: NotificationWithActor) async {
        do {
            try await notificationRepository.deleteNotification(notificationId: notification.id)

            // Remove from local state
            notifications.removeAll { $0.id == notification.id }
        } catch {
            let userError = errorHandler.handleError(error, context: .notification)
            self.error = userError
        }
    }

    func clearAllNotifications() async {
        guard let userId = authService.currentUser?.id else { return }

        do {
            try await notificationRepository.deleteAllNotifications(userId: userId)

            // Clear local state
            notifications.removeAll()
        } catch {
            let userError = errorHandler.handleError(error, context: .notification)
            self.error = userError
        }
    }

    // MARK: - Realtime Updates

    /// Subscribe to realtime notifications
    /// NOTE: NotificationBadgeManager already handles realtime subscriptions globally.
    /// This view just needs to refresh its list when notifications change.
    func subscribeToRealtimeUpdates() async {
        // Don't subscribe here - NotificationBadgeManager already handles it
        // Just refresh periodically or when notificationCount changes
        AppLogger.info("ActivityFeed: Skipping duplicate subscription (NotificationBadgeManager handles it)", category: AppLogger.app)
    }

    /// Handle a new notification received via realtime
    private func handleNewNotification(_ newNotification: AppNotification) async {
        

        // Increment badge counter
        newNotificationsCount += 1

        // Refresh the list to show the new notification
        await loadNotifications()

        Haptics.light()
    }

    /// Cleanup realtime subscriptions
    func cleanup() async {
        if let channelId = realtimeChannelId {
            await realtimeService.unsubscribe(channelId: channelId)
            realtimeChannelId = nil
           
        }
    }
}
