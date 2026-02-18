import Foundation
import SwiftUI

/// Manages notification badges for social features with real-time updates
@MainActor
@Observable
final class NotificationBadgeManager {
    static let shared = NotificationBadgeManager()

    var friendRequestCount: Int = 0
    var notificationCount: Int = 0

    private let friendshipRepository: FriendshipRepository
    private let notificationRepository: NotificationRepository
    private let authService: SupabaseAuthService
    private let realtimeService: RealtimeService
    private var refreshTask: Task<Void, Never>?

    // Real-time subscriptions
    private var notificationChannelId: String?
    private var friendshipChannelId: String?
    private var isSubscribing = false

    private init() {
        self.friendshipRepository = FriendshipRepository(
            client: SupabaseClientWrapper.shared.client
        )
        self.notificationRepository = NotificationRepository(
            client: SupabaseClientWrapper.shared.client
        )
        self.authService = SupabaseAuthService.shared
        self.realtimeService = RealtimeService(
            client: SupabaseClientWrapper.shared.client
        )
    }

    /// Fetch friend request count and notification count
    func refreshBadges() async {
        guard let userId = authService.currentUser?.id else {
            friendRequestCount = 0
            notificationCount = 0
            return
        }

        // Fetch both counts in parallel
        async let friendRequests = fetchFriendRequestCount(userId: userId)
        async let notifications = fetchNotificationCount(userId: userId)

        let (friendCount, notifCount) = await (friendRequests, notifications)
        friendRequestCount = friendCount
        notificationCount = notifCount
    }

    private func fetchFriendRequestCount(userId: UUID) async -> Int {
        do {
            let (incoming, _) = try await friendshipRepository.fetchPendingRequests(userId: userId)
            return incoming.count
        } catch {
            return 0
        }
    }

    private func fetchNotificationCount(userId: UUID) async -> Int {
        do {
            return try await notificationRepository.fetchUnreadCount(userId: userId)
        } catch {
            return 0
        }
    }

    // MARK: - Real-time Subscriptions

    /// Start real-time subscriptions (call this when app becomes active)
    func startRealtimeSubscriptions() async {
        AppLogger.info("🔍 startRealtimeSubscriptions() called", category: AppLogger.app)

        guard let userId = authService.currentUser?.id else {
            AppLogger.warning("❌ Cannot start realtime subscriptions - no user ID (currentUser is nil)", category: AppLogger.app)
            return
        }

        AppLogger.info("✅ User ID found: \(userId)", category: AppLogger.app)

        // Prevent concurrent subscription attempts
        if isSubscribing {
            AppLogger.warning("⏳ Already subscribing, skipping duplicate attempt", category: AppLogger.app)
            return
        }

        AppLogger.info("✅ Not currently subscribing", category: AppLogger.app)

        // If already subscribed, don't resubscribe
        if notificationChannelId != nil && friendshipChannelId != nil {
            AppLogger.info("✅ Already subscribed to real-time channels (notif: \(notificationChannelId ?? "nil"), friendship: \(friendshipChannelId ?? "nil"))", category: AppLogger.app)
            return
        }

        AppLogger.info("✅ Not yet subscribed, proceeding...", category: AppLogger.app)

        isSubscribing = true
        defer { isSubscribing = false }

        AppLogger.info("🚀 Starting realtime subscriptions for user: \(userId)", category: AppLogger.app)

        // Stop any existing subscriptions first to avoid duplicates
        await stopRealtimeSubscriptions()

        // Initial fetch
        await refreshBadges()

        // Subscribe to notifications
        do {
            AppLogger.info("📡 Attempting to subscribe to notifications...", category: AppLogger.app)
            let notifChannelId = try await realtimeService.subscribeToNotifications(userId: userId) { [weak self] notification in
                guard let self = self else {
                    AppLogger.warning("⚠️ Self is nil in notification callback", category: AppLogger.app)
                    return
                }
                Task { @MainActor in
                    AppLogger.info("🔔 Received notification via realtime: type=\(notification.type.rawValue), actorId=\(notification.actorId)", category: AppLogger.app)

                    await self.refreshNotificationCount(userId: userId)

                    // Show notification toast for all types (smart behavior based on app state)
                    await self.showNotificationToast(notification)
                }
            }
            notificationChannelId = notifChannelId
            AppLogger.info("✅ Successfully subscribed to notifications channel: \(notifChannelId)", category: AppLogger.app)
        } catch {
            AppLogger.error("❌ Failed to subscribe to notifications", error: error, category: AppLogger.app)
        }

        // Subscribe to friendship changes for real-time UI updates
        do {
            let friendshipChannelId = try await realtimeService.subscribeToFriendships(
                userId: userId,
                onUpdate: { [weak self] friendship in
                    guard let self = self else { return }
                    Task { @MainActor in
                        // Refresh badge counts when friendship status changes
                        await self.refreshBadges()

                        // Post notification for friendship status change
                        NotificationCenter.default.post(
                            name: .friendshipStatusChanged,
                            object: friendship
                        )
                    }
                },
                onInsert: { [weak self] friendship in
                    guard let self = self else { return }
                    Task { @MainActor in
                        // Refresh badge counts when new friend request arrives
                        await self.refreshBadges()
                    }
                }
            )
            self.friendshipChannelId = friendshipChannelId
            AppLogger.info("✅ Successfully subscribed to friendships channel: \(friendshipChannelId)", category: AppLogger.app)
        } catch {
            AppLogger.error("❌ Failed to subscribe to friendships", error: error, category: AppLogger.app)
        }
    }

    /// Stop real-time subscriptions (call this when app goes to background)
    func stopRealtimeSubscriptions() async {
        AppLogger.info("🛑 Stopping real-time subscriptions", category: AppLogger.app)

        if let channelId = notificationChannelId {
            await realtimeService.unsubscribe(channelId: channelId)
            notificationChannelId = nil
        }
        if let channelId = friendshipChannelId {
            await realtimeService.unsubscribe(channelId: channelId)
            friendshipChannelId = nil
        }

        AppLogger.info("✅ Real-time subscriptions stopped", category: AppLogger.app)
    }

    /// Refresh just the notification count
    private func refreshNotificationCount(userId: UUID) async {
        let count = await fetchNotificationCount(userId: userId)
        notificationCount = count
    }

    /// Fetch user profile by ID
    private func fetchProfile(userId: UUID) async throws -> UserProfile {
        try await authService.fetchProfile(userId: userId)
    }

    /// Show in-app toast for notification
    private func showNotificationToast(_ notification: AppNotification) async {
        // Fetch actor profile for personalized message
        guard let actorProfile = try? await fetchProfile(userId: notification.actorId) else {
            AppLogger.warning("Failed to fetch actor profile for notification", category: AppLogger.app)
            return
        }

        let actorName = actorProfile.displayName ?? actorProfile.username

        // Check if app is in foreground
        let isAppActive = await UIApplication.shared.applicationState == .active

        // Determine notification details based on type
        let (title, message, icon, toastType): (String, String, String, ToastNotificationType) = {
            switch notification.type {
            // Battle notifications
            case .battleInvite:
                return ("Battle Challenge!", "\(actorName) challenged you to a battle!", "flag.2.crossed.fill", .info)
            case .battleAccepted:
                return ("Battle Accepted!", "\(actorName) accepted your challenge!", "checkmark.shield.fill", .success)
            case .battleDeclined:
                return ("Battle Declined", "\(actorName) declined your challenge", "xmark.shield.fill", .warning)
            case .battleLeadTaken:
                let yourScore = notification.metadata?["your_score"] ?? "?"
                let opponentScore = notification.metadata?["opponent_score"] ?? "?"
                return ("Lead Taken!", "\(yourScore) vs \(opponentScore) - You're winning!", "arrow.up.circle.fill", .success)
            case .battleLeadLost:
                let yourScore = notification.metadata?["your_score"] ?? "?"
                let opponentScore = notification.metadata?["opponent_score"] ?? "?"
                return ("Lead Lost", "\(opponentScore) vs \(yourScore) - Time to step up!", "arrow.down.circle.fill", .warning)
            case .battleOpponentActivity:
                let scoreIncrease = notification.metadata?["score_increase"] ?? "0"
                let newScore = notification.metadata?["new_score"] ?? "?"
                let yourScore = notification.metadata?["your_score"] ?? "?"
                return ("Opponent Active", "\(actorName) just scored +\(scoreIncrease)! (\(newScore) vs \(yourScore))", "figure.run", .info)
            case .battleEndingSoon:
                return ("Battle Ending Soon", "Your battle with \(actorName) ends in 24 hours!", "clock.badge.exclamationmark.fill", .warning)
            case .battleCompleted:
                return ("Battle Ended", "Your battle with \(actorName) has ended", "flag.checkered", .info)
            case .battleVictory:
                return ("Victory!", "You beat \(actorName)!", "trophy.fill", .success)
            case .battleDefeat:
                return ("Battle Lost", "\(actorName) won this round", "hand.thumbsdown.fill", .info)

            // Challenge notifications
            case .challengeInvite:
                return ("Challenge Invite", "\(actorName) invited you to a challenge", "star.circle.fill", .info)
            case .challengeJoined:
                return ("Challenge Joined", "\(actorName) joined your challenge", "person.2.fill", .success)
            case .challengeMilestone:
                let milestone = notification.metadata?["milestone"] ?? "0"
                return ("Milestone Reached!", "You hit \(milestone)% in your challenge!", "star.fill", .success)
            case .challengeLeaderboardChange:
                let position = notification.metadata?["position"] ?? "?"
                return ("Leaderboard Update", "You moved up to #\(position)!", "chart.line.uptrend.xyaxis", .success)
            case .challengeEndingSoon:
                return ("Challenge Ending Soon", "Your challenge ends in 24 hours!", "timer", .warning)
            case .challengeCompleted:
                return ("Challenge Complete!", "Challenge finished! Check your rank", "checkmark.seal.fill", .success)
            case .challengeNewParticipant:
                return ("New Participant", "\(actorName) joined your challenge", "person.badge.plus", .info)

            // Post notifications
            case .postLike:
                return ("Post Liked", "\(actorName) liked your workout", "heart.fill", .success)
            case .postComment:
                return ("New Comment", "\(actorName) commented on your workout", "bubble.left.fill", .info)
            case .commentReply:
                return ("Comment Reply", "\(actorName) replied to your comment", "arrowshape.turn.up.left.fill", .info)
            case .commentMention:
                return ("Mentioned You", "\(actorName) mentioned you in a comment", "at", .info)

            // Social notifications (already handled separately, but included for completeness)
            case .friendRequest:
                return ("Friend Request", "\(actorName) sent you a friend request", "person.badge.plus", .info)
            case .friendAccepted:
                return ("Friend Request Accepted", "\(actorName) accepted your request", "person.badge.check", .success)

            // Virtual run notifications
            case .virtualRunInvite:
                return ("Virtual Run Invite", "\(actorName) wants to run with you!", "figure.run.circle.fill", .info)

            // Workout notifications
            case .workoutCompleted:
                return ("Workout Complete", "\(actorName) just finished a workout", "figure.strengthtraining.traditional", .success)
            }
        }()

        if isAppActive {
            // App is in foreground - show interactive toast with tap action
            AppLogger.info("📱 App is active - showing toast notification", category: AppLogger.app)

            let action = NotificationAction(label: "View") {
                // Navigate to the relevant screen
                self.navigateToNotification(notification)
            }

            AppNotificationManager.shared.show(
                ToastNotification(
                    type: toastType,
                    title: title,
                    message: message,
                    icon: icon,
                    duration: 5.0,
                    position: .top,
                    action: action,
                    onTap: {
                        // Also navigate when tapping anywhere on the toast
                        self.navigateToNotification(notification)
                    }
                )
            )
        } else {
            // App is in background/inactive - send local push notification
            AppLogger.info("📱 App is inactive - sending local notification", category: AppLogger.app)
            await sendLocalNotification(title: title, body: message)
        }
    }

    /// Navigate to the appropriate screen based on notification type
    private func navigateToNotification(_ notification: AppNotification) {
        AppLogger.info("🧭 Navigating to notification: type=\(notification.type.rawValue)", category: AppLogger.app)

        // Post a notification that can be observed by the navigation system
        NotificationCenter.default.post(
            name: .init("NavigateToNotification"),
            object: notification
        )

        // Also navigate to activity feed by default so user sees the notification
        NotificationCenter.default.post(name: .init("ShowActivityFeed"), object: nil)
    }

    /// Send a local notification
    private func sendLocalNotification(title: String, body: String) async {
        // Check notification permission status
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        AppLogger.debug("Notification settings - authorization: \(settings.authorizationStatus.rawValue), alertSetting: \(settings.alertSetting.rawValue)", category: AppLogger.app)

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            AppLogger.warning("Notification permission not granted. Status: \(settings.authorizationStatus.rawValue)", category: AppLogger.app)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            AppLogger.info("Local notification sent successfully: \(title)", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to send local notification", error: error, category: AppLogger.app)
        }
    }

    // MARK: - Legacy Polling (Deprecated)

    /// Start periodic refresh (DEPRECATED: Use startRealtimeSubscriptions instead)
    @available(*, deprecated, message: "Use startRealtimeSubscriptions() instead")
    func startPeriodicRefresh() {
        // Cancel any existing task
        refreshTask?.cancel()

        refreshTask = Task {
            while !Task.isCancelled {
                await refreshBadges()

                // Wait 30 seconds before next refresh
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    /// Stop periodic refresh (DEPRECATED: Use stopRealtimeSubscriptions instead)
    @available(*, deprecated, message: "Use stopRealtimeSubscriptions() instead")
    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
