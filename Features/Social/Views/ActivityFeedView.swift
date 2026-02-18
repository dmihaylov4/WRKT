import SwiftUI
import Kingfisher

/// Activity feed showing notifications
struct ActivityFeedView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: ActivityFeedViewModel?

    var body: some View {
        Group {
            if let viewModel {
                NotificationListView(viewModel: viewModel)
            } else {
                // Show skeleton loading state
                List {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonNotificationRow()
                            .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.insetGrouped)
                .task {
                    if viewModel == nil {
                        let vm = ActivityFeedViewModel(
                            notificationRepository: deps.notificationRepository,
                            authService: deps.authService,
                            realtimeService: deps.realtimeService
                        )
                        viewModel = vm
                        await vm.loadNotifications()
                        await vm.subscribeToRealtimeUpdates()
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            // Use weak reference to avoid retain cycle during deallocation
            if let vm = viewModel {
                Task { [weak vm] in
                    await vm?.cleanup()
                }
            }
        }
    }
}

/// List of notifications
private struct NotificationListView: View {
    @Bindable var viewModel: ActivityFeedViewModel

    var body: some View {
        ZStack {
            if viewModel.notifications.isEmpty && !viewModel.isLoading, let error = viewModel.error {
                // Show error view if initial load failed
                ErrorView(error: error) {
                    Task {
                        await viewModel.loadNotifications()
                    }
                }
            } else if viewModel.notifications.isEmpty && !viewModel.isLoading {
                EmptyNotificationsView()
            } else {
                List {
                    ForEach(viewModel.notifications) { notification in
                        NotificationRow(notification: notification)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteNotification(notification)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                if !notification.read {
                                    Button {
                                        Task {
                                            await viewModel.markAsRead(notification)
                                        }
                                    } label: {
                                        Label("Mark Read", systemImage: "envelope.open")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .listRowBackground(notification.read ? Color.clear : Color.blue.opacity(0.05))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.loadNotifications()
        }
        .task {
            await viewModel.loadNotifications()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasUnreadNotifications {
                    Button("Mark All Read") {
                        Task {
                            await viewModel.markAllAsRead()
                        }
                    }
                }

                if !viewModel.notifications.isEmpty {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.clearAllNotifications()
                        }
                    } label: {
                        Text("Clear All")
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.error, !viewModel.notifications.isEmpty {
                InlineErrorView(
                    error: error,
                    onRetry: {
                        Task {
                            await viewModel.loadNotifications()
                        }
                    },
                    onDismiss: {
                        viewModel.error = nil
                    }
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var hasUnreadNotifications: Bool {
        viewModel.notifications.contains { !$0.read }
    }
}

/// Individual notification row
private struct NotificationRow: View {
    @Environment(\.dependencies) private var deps
    let notification: NotificationWithActor

    var body: some View {
        NavigationLink {
            destinationView
        } label: {
            HStack(spacing: 12) {
                // Actor avatar (chamfered logo style)
                KFImage(notification.actor.avatarUrl.flatMap(URL.init))
                    .placeholder {
                        ChamferedRectangleAlt(.small)
                            .fill(DS.Semantic.brandSoft)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.title3)
                                    .foregroundStyle(DS.Semantic.brand)
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(ChamferedRectangleAlt(.small))

                VStack(alignment: .leading, spacing: 4) {
                    // Notification message
                    Text(notification.message)
                        .font(.subheadline)
                        .foregroundStyle(notification.read ? .secondary : .primary)

                    // Time
                    Text(notification.timeText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Icon
                Image(systemName: notification.type.icon)
                    .foregroundStyle(colorForType(notification.type))
                    .font(.title3)

                // Unread indicator
                if !notification.read {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch notification.type {
        case .friendRequest, .friendAccepted:
            // Navigate to friend requests or the actor's profile
            SocialProfileView(userId: notification.actor.id)
                .environment(\.dependencies, deps)

        case .postLike, .postComment, .commentReply, .commentMention:
            // Navigate to the post if we have a target ID
            if let targetId = notification.targetId {
                PostLoaderView(postId: targetId)
                    .environment(\.dependencies, deps)
            } else {
                Text("Post not found")
            }

        case .battleInvite, .battleAccepted, .battleDeclined, .battleLeadTaken, .battleLeadLost,
             .battleOpponentActivity, .battleEndingSoon, .battleCompleted, .battleVictory, .battleDefeat:
            // Navigate to battle detail if we have a target ID
            if let targetId = notification.targetId {
                BattleLoaderView(battleId: targetId)
                    .environment(\.dependencies, deps)
            } else {
                Text("Battle not found")
            }

        case .challengeInvite, .challengeJoined, .challengeMilestone, .challengeLeaderboardChange,
             .challengeEndingSoon, .challengeCompleted, .challengeNewParticipant:
            // Navigate to challenge detail if we have a target ID
            if let targetId = notification.targetId {
                ChallengeLoaderView(challengeId: targetId)
                    .environment(\.dependencies, deps)
            } else {
                Text("Challenge not found")
            }

        case .virtualRunInvite:
            // Navigate to the inviter's profile
            SocialProfileView(userId: notification.actor.id)
                .environment(\.dependencies, deps)

        case .workoutCompleted:
            // Navigate to the workout post if we have a target ID
            if let targetId = notification.targetId {
                PostLoaderView(postId: targetId)
                    .environment(\.dependencies, deps)
            } else {
                SocialProfileView(userId: notification.actor.id)
                    .environment(\.dependencies, deps)
            }
        }
    }

    private func colorForType(_ type: NotificationType) -> Color {
        switch type.color {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return .pink
        case "gold": return .yellow // iOS doesn't have .gold, use yellow
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
}

/// Empty state when no notifications
private struct EmptyNotificationsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Notifications")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When friends interact with you, you'll see their activity here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

/// Loads a post by ID and displays PostDetailView
struct PostLoaderView: View {
    @Environment(\.dependencies) private var deps
    let postId: UUID

    @State private var post: PostWithAuthor?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading post...")
            } else if let post = post {
                PostDetailView(post: post)
                    .environment(\.dependencies, deps)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("Post Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button("Try Again") {
                        Task {
                            await loadPost()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .task {
            await loadPost()
        }
    }

    private func loadPost() async {
        guard let userId = deps.authService.currentUser?.id else {
            errorMessage = "Not logged in"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch the feed and find the post
            // Note: This is not ideal - we should have a fetchPostById method
            let result = try await deps.postRepository.fetchFeed(userId: userId, limit: 100, cursor: nil)
            if let foundPost = result.posts.first(where: { $0.post.id == postId }) {
                post = foundPost
            } else {
                errorMessage = "This post may have been deleted or is no longer accessible"
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Battle Loader View
struct BattleLoaderView: View {
    @Environment(\.dependencies) private var deps
    let battleId: UUID

    @State private var battle: BattleWithParticipants?
    @State private var viewModel: BattleViewModel?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading battle...")
            } else if let battle = battle, let viewModel = viewModel {
                BattleDetailView(battle: battle, viewModel: viewModel)
                    .environment(\.dependencies, deps)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("Battle Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button("Try Again") {
                        Task {
                            await loadBattle()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .task {
            await loadBattle()
        }
    }

    private func loadBattle() async {
        isLoading = true
        errorMessage = nil

        // Create the viewModel if needed
        if viewModel == nil {
            viewModel = BattleViewModel(
                battleRepository: deps.battleRepository,
                authService: deps.authService
            )
        }

        do {
            battle = try await deps.battleRepository.fetchBattle(id: battleId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Challenge Loader View
struct ChallengeLoaderView: View {
    @Environment(\.dependencies) private var deps
    let challengeId: UUID

    @State private var challenge: ChallengeWithProgress?
    @State private var viewModel: ChallengesViewModel?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading challenge...")
            } else if let challenge = challenge, let viewModel = viewModel {
                ChallengeDetailView(challenge: challenge, viewModel: viewModel)
                    .environment(\.dependencies, deps)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    Text("Challenge Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button("Try Again") {
                        Task {
                            await loadChallenge()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .task {
            await loadChallenge()
        }
    }

    private func loadChallenge() async {
        isLoading = true
        errorMessage = nil

        // Create the viewModel if needed
        if viewModel == nil {
            viewModel = ChallengesViewModel(
                challengeRepository: deps.challengeRepository,
                authService: deps.authService
            )
        }

        do {
            challenge = try await deps.challengeRepository.fetchChallenge(id: challengeId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
