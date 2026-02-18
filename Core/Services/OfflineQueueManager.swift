import Foundation
import Observation

/// Queue for actions performed while offline
@MainActor
@Observable
final class OfflineQueueManager {
    static let shared = OfflineQueueManager()

    private(set) var queuedActions: [QueuedAction] = []
    private(set) var isSyncing = false

    private let userDefaultsKey = "offlineQueue"
    private let networkMonitor = NetworkMonitor.shared

    init() {
        loadQueue()
        observeNetworkChanges()
    }

    // MARK: - Queue Management

    /// Add an action to the queue
    func enqueue(_ action: QueuedAction) {
        queuedActions.append(action)
        saveQueue()
    }

    /// Remove an action from the queue
    func dequeue(_ actionId: UUID) {
        queuedActions.removeAll { $0.id == actionId }
        saveQueue()
    }

    /// Clear all queued actions
    func clearQueue() {
        queuedActions.removeAll()
        saveQueue()
    }

    /// Get count of queued actions
    var queueCount: Int {
        queuedActions.count
    }

    // MARK: - Sync

    /// Sync all queued actions when online
    func syncQueue(dependencies: AppDependencies) async {
        guard !isSyncing else { return }
        guard networkMonitor.isConnected else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }


        var successCount = 0
        var failureCount = 0

        // Process actions in order
        for action in queuedActions {
            do {
                try await executeAction(action, dependencies: dependencies)
                dequeue(action.id)
                successCount += 1
            } catch {
                failureCount += 1
                // Keep in queue for retry
            }
        }

    }

    // MARK: - Action Execution

    private func executeAction(_ action: QueuedAction, dependencies: AppDependencies) async throws {
        switch action.type {
        case .likePost:
            guard let postId = action.data["postId"],
                  let postUUID = UUID(uuidString: postId) else {
                throw QueueError.invalidData
            }
            try await dependencies.postRepository.likePost(postUUID)

        case .unlikePost:
            guard let postId = action.data["postId"],
                  let postUUID = UUID(uuidString: postId) else {
                throw QueueError.invalidData
            }
            try await dependencies.postRepository.unlikePost(postUUID)

        case .addComment:
            guard let postId = action.data["postId"],
                  let postUUID = UUID(uuidString: postId),
                  let content = action.data["content"] else {
                throw QueueError.invalidData
            }
            _ = try await dependencies.postRepository.addComment(postId: postUUID, content: content)

        case .deletePost:
            guard let postId = action.data["postId"],
                  let postUUID = UUID(uuidString: postId) else {
                throw QueueError.invalidData
            }
            try await dependencies.postRepository.deletePost(postUUID)

        case .updatePost:
            guard let postId = action.data["postId"],
                  let postUUID = UUID(uuidString: postId),
                  let visibilityString = action.data["visibility"],
                  let visibility = PostVisibility(rawValue: visibilityString) else {
                throw QueueError.invalidData
            }
            let caption = action.data["caption"]?.isEmpty == false ? action.data["caption"] : nil
            try await dependencies.postRepository.updatePost(postUUID, caption: caption, visibility: visibility)

        case .sendFriendRequest:
            guard let friendId = action.data["friendId"],
                  let friendUUID = UUID(uuidString: friendId),
                  let currentUserId = dependencies.authService.currentUser?.id else {
                throw QueueError.invalidData
            }
            _ = try await dependencies.friendshipRepository.sendFriendRequest(to: friendUUID, from: currentUserId)

        case .acceptFriendRequest:
            guard let friendshipId = action.data["friendshipId"],
                  let friendshipUUID = UUID(uuidString: friendshipId) else {
                throw QueueError.invalidData
            }
            _ = try await dependencies.friendshipRepository.acceptFriendRequest(friendshipId: friendshipUUID)

        case .rejectFriendRequest:
            guard let friendshipId = action.data["friendshipId"],
                  let friendshipUUID = UUID(uuidString: friendshipId) else {
                throw QueueError.invalidData
            }
            try await dependencies.friendshipRepository.rejectFriendRequest(friendshipId: friendshipUUID)

        case .markNotificationRead:
            guard let notificationId = action.data["notificationId"],
                  let notificationUUID = UUID(uuidString: notificationId) else {
                throw QueueError.invalidData
            }
            try await dependencies.notificationRepository.markAsRead(notificationId: notificationUUID)
        }
    }

    // MARK: - Network Observation

    private func observeNetworkChanges() {
        // Note: In a real implementation, you'd use Combine or async/await observation
        // For now, this is a placeholder. You can manually call syncQueue when needed.
    }

    // MARK: - Persistence

    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(queuedActions)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return
        }

        do {
            queuedActions = try JSONDecoder().decode([QueuedAction].self, from: data)
        } catch {
            queuedActions = []
        }
    }
}

// MARK: - Models

struct QueuedAction: Codable, Identifiable {
    let id: UUID
    let type: ActionType
    let data: [String: String] // Simple key-value storage
    let createdAt: Date

    init(type: ActionType, data: [String: String]) {
        self.id = UUID()
        self.type = type
        self.data = data
        self.createdAt = Date()
    }
}

enum ActionType: String, Codable {
    case likePost
    case unlikePost
    case addComment
    case deletePost
    case updatePost
    case sendFriendRequest
    case acceptFriendRequest
    case rejectFriendRequest
    case markNotificationRead
}

enum QueueError: LocalizedError {
    case invalidData
    case executionFailed

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid action data"
        case .executionFailed:
            return "Failed to execute action"
        }
    }
}
