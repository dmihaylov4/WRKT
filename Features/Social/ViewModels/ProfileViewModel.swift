//
//  ProfileViewModel.swift
//  WRKT
//
//  ViewModel for user profile view with posts, friendships, and avatar upload
//

import Foundation
import SwiftUI
import PhotosUI

@MainActor
@Observable
final class ProfileViewModel {
    var profile: UserProfile
    var posts: [WorkoutPost] = []
    var isLoadingPosts = false
    var isUploadingAvatar = false
    var selectedPhoto: PhotosPickerItem?
    var error: String?
    var friendCount: Int = 0

    // Friend status
    var friendshipStatus: ProfileFriendshipStatus = .none
    var currentFriendship: Friendship?
    var isLoadingFriendship = false
    var isMuted: Bool = false

    private let postRepository: PostRepository
    private let friendshipRepository: FriendshipRepository
    private let imageUploadService: ImageUploadService
    private let authService: SupabaseAuthService
    nonisolated(unsafe) private var friendshipObserver: NSObjectProtocol?
    nonisolated(unsafe) private var pendingRemovalTask: Task<Void, Never>?

    var isOwnProfile: Bool {
        profile.id == authService.currentUser?.id
    }

    init(
        profile: UserProfile,
        postRepository: PostRepository,
        friendshipRepository: FriendshipRepository,
        imageUploadService: ImageUploadService,
        authService: SupabaseAuthService
    ) {
        self.profile = profile
        self.postRepository = postRepository
        self.friendshipRepository = friendshipRepository
        self.imageUploadService = imageUploadService
        self.authService = authService

        // Listen for friendship status changes
        setupFriendshipObserver()
    }

    deinit {
        if let observer = friendshipObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pendingRemovalTask?.cancel()
    }

    private func setupFriendshipObserver() {
        guard let currentUserId = authService.currentUser?.id else { return }

        friendshipObserver = NotificationCenter.default.addObserver(
            forName: .friendshipStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let friendship = notification.object as? Friendship else { return }

            // Check if this friendship involves the current profile
            if (friendship.userId == currentUserId && friendship.friendId == self.profile.id) ||
               (friendship.userId == self.profile.id && friendship.friendId == currentUserId) {
                // Refresh friendship status
                Task { @MainActor in
                    await self.loadFriendshipStatus()
                }
            }
        }
    }

    func loadUserPosts() async {
        guard !isLoadingPosts else { return }

        isLoadingPosts = true
        error = nil

        do {
            posts = try await postRepository.fetchUserPosts(userId: profile.id)
            isLoadingPosts = false
        } catch {
            self.error = error.localizedDescription
            isLoadingPosts = false
        }
    }

    func loadFriendCount() async {
        do {
            let friends = try await friendshipRepository.fetchFriends(userId: profile.id)
            friendCount = friends.count
        } catch {
            friendCount = 0
        }
    }

    func loadFriendshipStatus() async {
        guard !isOwnProfile else { return }
        guard let currentUserId = authService.currentUser?.id else { return }

        isLoadingFriendship = true

        do {
            let friendship = try await friendshipRepository.checkFriendshipStatus(
                userId: currentUserId,
                friendId: profile.id
            )

            currentFriendship = friendship

            // Map database status to view status
            if let friendship = friendship {
                switch friendship.status {
                case .accepted:
                    friendshipStatus = .friends
                    isMuted = friendship.mutedNotifications
                case .pending:
                    // Determine if pending is sent or received based on user_id
                    if friendship.userId == currentUserId {
                        friendshipStatus = .pendingSent
                    } else {
                        friendshipStatus = .pendingReceived
                    }
                    isMuted = false
                case .blocked:
                    friendshipStatus = .none
                    isMuted = false
                }
            } else {
                friendshipStatus = .none
                isMuted = false
            }

            isLoadingFriendship = false
        } catch {
            isLoadingFriendship = false
        }
    }

    func sendFriendRequest() async {
        guard let currentUserId = authService.currentUser?.id else { return }

        AppLogger.info("👤 sendFriendRequest() called: from=\(currentUserId) to=\(profile.id)", category: AppLogger.app)

        isLoadingFriendship = true

        do {
            AppLogger.info("📤 Calling friendshipRepository.sendFriendRequest()", category: AppLogger.app)
            try await friendshipRepository.sendFriendRequest(to: profile.id, from: currentUserId)
            friendshipStatus = .pendingSent
            isLoadingFriendship = false
            Haptics.success()
            AppLogger.info("✅ Friend request sent successfully", category: AppLogger.app)
        } catch {
            AppLogger.error("❌ Failed to send friend request", error: error, category: AppLogger.app)
            self.error = "Failed to send friend request"
            isLoadingFriendship = false
            Haptics.error()
        }
    }

    func acceptFriendRequest() async {
        guard let friendshipId = currentFriendship?.id else { return }

        isLoadingFriendship = true

        do {
            let updatedFriendship = try await friendshipRepository.acceptFriendRequest(friendshipId: friendshipId)
            currentFriendship = updatedFriendship
            friendshipStatus = .friends
            isLoadingFriendship = false
            Haptics.success()
        } catch {
            self.error = "Failed to accept friend request"
            isLoadingFriendship = false
            Haptics.error()
        }
    }

    func declineFriendRequest() async {
        guard let friendshipId = currentFriendship?.id else { return }

        isLoadingFriendship = true

        do {
            try await friendshipRepository.rejectFriendRequest(friendshipId: friendshipId)
            currentFriendship = nil
            friendshipStatus = .none
            isLoadingFriendship = false
            Haptics.success()
        } catch {
            self.error = "Failed to decline friend request"
            isLoadingFriendship = false
            Haptics.error()
        }
    }

    func cancelFriendRequest() async {
        guard let friendshipId = currentFriendship?.id else { return }

        isLoadingFriendship = true

        do {
            // Canceling uses the same endpoint as rejecting
            try await friendshipRepository.rejectFriendRequest(friendshipId: friendshipId)
            currentFriendship = nil
            friendshipStatus = .none
            isLoadingFriendship = false
            Haptics.soft()
        } catch {
            self.error = "Failed to cancel friend request"
            isLoadingFriendship = false
            Haptics.error()
        }
    }

    func toggleMuteNotifications() async {
        guard let friendshipId = currentFriendship?.id else { return }

        let newMutedState = !isMuted

        do {
            try await friendshipRepository.toggleMuteNotifications(friendshipId: friendshipId, muted: newMutedState)
            isMuted = newMutedState
            Haptics.soft()
        } catch {
            AppLogger.error("Failed to toggle mute notifications", error: error, category: AppLogger.app)
            Haptics.error()
        }
    }

    func removeFriend() {
        guard case .friends = friendshipStatus,
              let friendshipId = currentFriendship?.id else { return }

        // Store previous state for undo
        let previousStatus = friendshipStatus
        let previousFriendship = currentFriendship

        // Optimistic update
        friendshipStatus = .none
        currentFriendship = nil
        Haptics.warning()

        // Show undo toast
        UndoToastManager.shared.show(
            message: "Removed @\(profile.username)",
            undoAction: { [weak self] in
                self?.undoRemoveFriend(
                    friendshipId: friendshipId,
                    previousStatus: previousStatus,
                    previousFriendship: previousFriendship
                )
            }
        )

        // Schedule backend deletion (5 seconds)
        pendingRemovalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await performRemoval(friendshipId: friendshipId)
            }
        }
    }

    private func performRemoval(friendshipId: UUID) async {
        do {
            try await friendshipRepository.removeFriendship(friendshipId: friendshipId)

            WorkoutToastManager.shared.show(
                message: "Friend removed",
                icon: "checkmark.circle.fill"
            )

            // Notify FriendsListView to refresh
            NotificationCenter.default.post(name: .friendshipStatusChanged, object: nil)
        } catch {
            // Restore on error
            self.error = "Failed to remove friend"
            Haptics.error()
            await loadFriendshipStatus()
        }
    }

    private func undoRemoveFriend(
        friendshipId: UUID,
        previousStatus: ProfileFriendshipStatus,
        previousFriendship: Friendship?
    ) {
        pendingRemovalTask?.cancel()
        friendshipStatus = previousStatus
        currentFriendship = previousFriendship

        Haptics.success()
        WorkoutToastManager.shared.show(
            message: "Friend restored",
            icon: "checkmark.circle.fill"
        )

        // Notify FriendsListView to refresh
        NotificationCenter.default.post(name: .friendshipStatusChanged, object: nil)
    }

    func uploadProfilePicture() async {
        guard let selectedPhoto = selectedPhoto else { return }
        guard let currentUserId = authService.currentUser?.id else { return }

        isUploadingAvatar = true
        error = nil

        do {
            // Load image from PhotosPicker
            guard let imageData = try await selectedPhoto.loadTransferable(type: Data.self),
                  let image = UIImage(data: imageData),
                  let jpegData = image.jpegData(compressionQuality: 0.8),
                  let finalImage = UIImage(data: jpegData) else {
                throw SupabaseError.serverError("Failed to load image")
            }

            // Upload to storage
            let avatarUrl = try await imageUploadService.uploadProfilePicture(
                image: finalImage,
                userId: currentUserId
            )

            // Save to database and update local state
            try await authService.updateProfile(avatarUrl: avatarUrl)

            // Update local profile state
            var updatedProfile = profile
            updatedProfile.avatarUrl = avatarUrl
            profile = updatedProfile

            isUploadingAvatar = false
            self.selectedPhoto = nil
            Haptics.success()
        } catch {
            self.error = "Failed to upload profile picture: \(error.localizedDescription)"
            isUploadingAvatar = false
            Haptics.error()
        }
    }
}
