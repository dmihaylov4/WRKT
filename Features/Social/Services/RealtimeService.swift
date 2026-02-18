//
//  RealtimeService.swift
//  WRKT
//
//  Supabase Realtime service for live updates
//

import Foundation
import Supabase

/// Events that can be received from realtime subscriptions
enum RealtimeEvent<T> {
    case insert(T)
    case update(T)
    case delete(UUID)
}

/// Service for managing Supabase Realtime subscriptions
@MainActor
final class RealtimeService {
    private let client: SupabaseClient
    private var activeChannels: [String: RealtimeChannelV2] = [:]
    private var observationTokens: [String: Any] = [:] // Keep observation tokens alive

    init(client: SupabaseClient = SupabaseClientWrapper.shared.client) {
        self.client = client
    }

    // MARK: - Connection Status

    /// Get the connection status for a channel
    func channelStatus(for channelId: String) -> RealtimeChannelV2.Status? {
        return activeChannels[channelId]?.status
    }

    // MARK: - Posts Subscription

    /// Subscribe to new posts in the feed
    func subscribeToNewPosts(
        userId: UUID,
        onInsert: @escaping (WorkoutPost) -> Void
    ) async throws -> String {
        let channelId = "feed_posts_\(userId.uuidString)"

        // If already subscribed, unsubscribe first
        if let existingChannel = activeChannels[channelId] {
            await existingChannel.unsubscribe()
            activeChannels.removeValue(forKey: channelId)
        }

        let channel = await client.channel(channelId)

        // Listen for INSERT events on workout_posts
        let changes = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "workout_posts",
            callback: { action in
                switch action {
                case .insert(let insertAction):
                    if let post = try? insertAction.decodeRecord(as: WorkoutPost.self, decoder: JSONDecoder()) {
                        onInsert(post)
                    }
                default:
                    break
                }
            }
        )

        await channel.subscribe()
        activeChannels[channelId] = channel

        return channelId
    }

    // MARK: - Likes Subscription

    /// Subscribe to likes on a specific post
    func subscribeToPostLikes(
        postId: UUID,
        onInsert: @escaping (PostLike) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) async throws -> String {
        let channelId = "post_likes_\(postId.uuidString)"

        // If already subscribed, unsubscribe first
        if let existingChannel = activeChannels[channelId] {
            await existingChannel.unsubscribe()
            activeChannels.removeValue(forKey: channelId)
        }

        let channel = await client.channel(channelId)

        // Listen for INSERT and DELETE on post_likes
        let changes = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "post_likes",
            filter: "post_id=eq.\(postId.uuidString)",
            callback: { action in
                switch action {
                case .insert(let insertAction):
                    if let like = try? insertAction.decodeRecord(as: PostLike.self, decoder: JSONDecoder()) {
                        onInsert(like)
                    }
                case .delete(let deleteAction):
                    let oldRecord = deleteAction.oldRecord
                    if let idValue = oldRecord["id"],
                       case .string(let idString) = idValue,
                       let id = UUID(uuidString: idString) {
                        onDelete(id)
                    }
                default:
                    break
                }
            }
        )

        await channel.subscribe()
        activeChannels[channelId] = channel

        return channelId
    }

    // MARK: - Comments Subscription

    /// Subscribe to comments on a specific post
    func subscribeToPostComments(
        postId: UUID,
        onInsert: @escaping (PostComment) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) async throws -> String {
        let channelId = "post_comments_\(postId.uuidString)"

        // If already subscribed, unsubscribe first
        if let existingChannel = activeChannels[channelId] {
            await existingChannel.unsubscribe()
            activeChannels.removeValue(forKey: channelId)
        }

        let channel = await client.channel(channelId)

        // Listen for INSERT and DELETE on post_comments
        let changes = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "post_comments",
            filter: "post_id=eq.\(postId.uuidString)",
            callback: { action in
                switch action {
                case .insert(let insertAction):
                    if let comment = try? insertAction.decodeRecord(as: PostComment.self, decoder: JSONDecoder()) {
                        onInsert(comment)
                    }
                case .delete(let deleteAction):
                    let oldRecord = deleteAction.oldRecord
                    if let idValue = oldRecord["id"],
                       case .string(let idString) = idValue,
                       let id = UUID(uuidString: idString) {
                        onDelete(id)
                    }
                default:
                    break
                }
            }
        )

        await channel.subscribe()
        activeChannels[channelId] = channel

        return channelId
    }

    // MARK: - Notifications Subscription

    /// Subscribe to notifications for the current user
    func subscribeToNotifications(
        userId: UUID,
        onInsert: @escaping (AppNotification) -> Void
    ) async throws -> String {
        let userIdLowercase = userId.uuidString.lowercased()
        let channelId = "notifications_\(userIdLowercase)"

        AppLogger.info("📡 Subscribing to notifications for user: \(userIdLowercase)", category: AppLogger.app)

        // If already subscribed, unsubscribe and remove from client
        if let existingChannel = activeChannels[channelId] {
            AppLogger.info("🔄 Unsubscribing from existing channel: \(channelId)", category: AppLogger.app)
            await existingChannel.unsubscribe()
            await client.removeChannel(existingChannel)
            activeChannels.removeValue(forKey: channelId)
        }

        // Wait a moment for cleanup to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Create a fresh channel
        let channel = await client.channel(channelId)

        // TEMPORARY: Listen for ALL notifications to test if events are being broadcast
        // Once working, we'll re-enable the filter
        AppLogger.info("🔌 Setting up Postgres change listener for notifications table", category: AppLogger.app)

        // Set up the listener BEFORE subscribing - keep reference to the change config
        let changeConfig = await channel.onPostgresChange(
            AnyAction.self,  // Use AnyAction to catch any change type
            schema: "public",
            table: "notifications",
            // filter: "user_id=eq.\(userIdLowercase)", // TEMPORARILY DISABLED FOR TESTING
            callback: { action in
                AppLogger.info("📨 Realtime event received", category: AppLogger.app)

                // Try to handle different action types
                switch action {
                case .insert(let insertAction):
                    // Configure decoder for Supabase date format
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .custom { decoder in
                        let container = try decoder.singleValueContainer()
                        let dateString = try container.decode(String.self)

                        // Try ISO8601 with fractional seconds first
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let date = formatter.date(from: dateString) {
                            return date
                        }

                        // Try without fractional seconds
                        formatter.formatOptions = [.withInternetDateTime]
                        if let date = formatter.date(from: dateString) {
                            return date
                        }

                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
                    }

                    // Try to decode
                    do {
                        let notification = try insertAction.decodeRecord(as: AppNotification.self, decoder: decoder)
                        AppLogger.info("✉️ Decoded notification from realtime: type=\(notification.type.rawValue), id=\(notification.id), userId=\(notification.userId)", category: AppLogger.app)

                        // Only call onInsert if it matches the user
                        if notification.userId.uuidString.lowercased() == userIdLowercase {
                            AppLogger.info("✅ Notification matches user filter, calling onInsert", category: AppLogger.app)
                            onInsert(notification)
                        } else {
                            AppLogger.info("⏭️ Notification for different user (\(notification.userId)), skipping", category: AppLogger.app)
                        }
                    } catch {
                        AppLogger.error("❌ Failed to decode notification from realtime", error: error, category: AppLogger.app)
                        AppLogger.error("Record keys: \(insertAction.record.keys.joined(separator: ", "))", error: nil, category: AppLogger.app)
                    }
                default:
                    AppLogger.info("📨 Other action type received: \(action)", category: AppLogger.app)
                }
            }
        )

        // CRITICAL: Store the observation token to keep the callback alive
        observationTokens[channelId] = changeConfig

        // Now subscribe to the channel
        AppLogger.info("📡 Calling channel.subscribe()...", category: AppLogger.app)
        await channel.subscribe()
        activeChannels[channelId] = channel

        // Wait a moment for the subscription to establish
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Log channel status after subscription
        let status = channel.status
        AppLogger.info("✅ Subscribed to notifications channel: \(channelId), status: \(String(describing: status))", category: AppLogger.app)

        // If status is not subscribed, log a warning
        if status != .subscribed {
            AppLogger.warning("⚠️ Channel status is not 'subscribed': \(String(describing: status))", category: AppLogger.app)
        }

        // Monitor channel status changes with reconnection logic
        Task { @MainActor in
            for await newStatus in await channel.statusChange {
                AppLogger.info("🔄 Notifications channel status changed: \(String(describing: newStatus))", category: AppLogger.app)

                // Log detailed status for debugging
                switch newStatus {
                case .subscribed:
                    AppLogger.info("✅ WebSocket connected successfully", category: AppLogger.app)
                case .subscribing:
                    AppLogger.info("⏳ Connecting to WebSocket...", category: AppLogger.app)
                case .unsubscribed:
                    AppLogger.warning("❌ WebSocket disconnected! Status: unsubscribed", category: AppLogger.app)
                    AppLogger.warning("⚠️ Realtime notifications will not work until reconnected", category: AppLogger.app)
                @unknown default:
                    AppLogger.warning("⚠️ Unknown channel status: \(String(describing: newStatus))", category: AppLogger.app)
                }
            }
        }

        return channelId
    }

    // MARK: - Friendships Subscription

    /// Subscribe to friendship changes for the current user
    func subscribeToFriendships(
        userId: UUID,
        onUpdate: @escaping (Friendship) -> Void,
        onInsert: @escaping (Friendship) -> Void
    ) async throws -> String {
        let channelId = "friendships_\(userId.uuidString)"

        // If already subscribed, unsubscribe first
        if let existingChannel = activeChannels[channelId] {
            await existingChannel.unsubscribe()
            activeChannels.removeValue(forKey: channelId)
        }

        let channel = await client.channel(channelId)

        // Listen for UPDATE and INSERT on friendships where user is involved
        let changes = await channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "friendships",
            filter: "or(user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString))",
            callback: { action in
                switch action {
                case .update(let updateAction):
                    if let friendship = try? updateAction.decodeRecord(as: Friendship.self, decoder: JSONDecoder()) {
                        onUpdate(friendship)
                    }
                case .insert(let insertAction):
                    if let friendship = try? insertAction.decodeRecord(as: Friendship.self, decoder: JSONDecoder()) {
                        onInsert(friendship)
                    }
                default:
                    break
                }
            }
        )

        await channel.subscribe()
        activeChannels[channelId] = channel

        return channelId
    }

    // MARK: - Unsubscribe

    /// Unsubscribe from a specific channel
    func unsubscribe(channelId: String) async {
        guard let channel = activeChannels[channelId] else {
            return
        }

        await channel.unsubscribe()
        activeChannels.removeValue(forKey: channelId)
        observationTokens.removeValue(forKey: channelId) // Clean up observation token
    }

    /// Unsubscribe from all active channels
    func unsubscribeAll() async {

        for (channelId, channel) in activeChannels {
            await channel.unsubscribe()
        }

        activeChannels.removeAll()
        observationTokens.removeAll() // Clean up all observation tokens
    }

    // MARK: - Connection Management

    /// Get count of active channels
    var activeChannelCount: Int {
        return activeChannels.count
    }

    /// Check if a specific channel is subscribed
    func isSubscribed(channelId: String) -> Bool {
        return activeChannels[channelId]?.status == .subscribed
    }
}
