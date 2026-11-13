//
//  CutSocialHost.swift
//  WRKT
//
//  Feeds the Cut Social views from what the legacy tab already loads: the feed view model,
//  the arena's battle and challenge repositories, the friends hub view model and the badge
//  manager. Same fetches, refresh triggers, sheets and destinations as FeedView and
//  FriendsHubView; only the presentation differs. Lives inside SocialView's NavigationStack,
//  which keeps the path, the profile, post, battle and challenge destinations, the badge
//  subscription and notification routing.
//

import SwiftUI
import Kingfisher

/// Destinations the legacy tab opened with NavigationLink, pushed on SocialView's path instead.
enum CutSocialRoute: Hashable {
    case activity
    case friendRequests
    case friendsList
    case userSearch
}

struct CutSocialHost: View {
    @Binding var section: SocialView.SocialSection
    @Binding var path: NavigationPath

    @Environment(\.dependencies) private var deps
    @State private var badgeManager = NotificationBadgeManager.shared
    @State private var showingCreatePost = false
    @State private var showingBattleCreation = false
    /// Bumped when the create post sheet closes; the feed refreshes, as FeedView did.
    @State private var feedRefreshToken = 0

    var body: some View {
        CutSocialShell(header: header, section: section, actions: shellActions) {
            switch section {
            case .feed:
                CutSocialFeedHost(path: $path, refreshToken: feedRefreshToken)
                    .id("feed-view-stable")
            case .compete:
                UnifiedCompeteView()
                    .id("compete-view-stable")
            case .friends:
                CutSocialFriendsHost(path: $path)
                    .id("friends-view-stable")
            }
        }
        .navigationDestination(for: CutSocialRoute.self) { route in
            switch route {
            case .activity:
                ActivityFeedView().environment(\.dependencies, deps)
            case .friendRequests:
                FriendRequestsView().environment(\.dependencies, deps)
            case .friendsList:
                FriendsListView().environment(\.dependencies, deps)
            case .userSearch:
                UserSearchView().environment(\.dependencies, deps)
            }
        }
        .sheet(isPresented: $showingCreatePost, onDismiss: { feedRefreshToken += 1 }) {
            PostCreationView()
        }
        .sheet(isPresented: $showingBattleCreation) {
            if deps.authService.currentUser?.id != nil {
                CreateBattleView(
                    viewModel: BattleViewModel(
                        battleRepository: deps.battleRepository,
                        authService: deps.authService
                    )
                )
            }
        }
    }

    private var header: CutSocialHeaderModel {
        let user = deps.authService.currentUser
        let name = user?.profile?.displayName ?? user?.profile?.username ?? ""
        return CutSocialHeaderModel(
            notifications: badgeManager.notificationCount,
            friendRequests: badgeManager.friendRequestCount,
            avatarURL: user?.profile?.avatarUrl,
            initials: CutSocialLogic.initials(name),
            showsProfile: user != nil
        )
    }

    private var shellActions: CutSocialShellActions {
        CutSocialShellActions(
            select: { section = $0 },
            openProfile: {
                if let id = deps.authService.currentUser?.id { path.append(id) }
            },
            openActivity: { path.append(CutSocialRoute.activity) },
            createPost: { showingCreatePost = true },
            startBattle: { showingBattleCreation = true }
        )
    }
}

// MARK: - Feed

/// FeedView's data and flows behind the Cut feed. Created when the Feed pane shows and torn
/// down when it goes, as FeedView was.
struct CutSocialFeedHost: View {
    @Binding var path: NavigationPath
    let refreshToken: Int

    @Environment(\.dependencies) private var deps
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var viewModel: FeedViewModel?
    @State private var showingProgressShare = false
    @State private var pendingProgressWorkouts: [CompletedWorkout] = []
    @State private var pendingProgressStats: WeeklyProgressStats?
    @State private var postToEdit: PostWithAuthor?
    @State private var likesPost: PostWithAuthor?
    @State private var activeBattles: [BattleWithParticipants] = []
    @State private var activeChallenges: [ChallengeWithProgress] = []

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var currentUserId: UUID? { deps.authService.currentUser?.id }

    var body: some View {
        CutSocialFeedView(model: model, actions: actions) { row in
            if let post = viewModel?.posts.first(where: { $0.post.id == row.id }) {
                CutSocialPostMedia(post: post, currentUserId: currentUserId) {
                    await viewModel?.backfillRouteMap(for: post) ?? false
                }
            }
        }
        .sheet(isPresented: $showingProgressShare, onDismiss: {
            pendingProgressStats = nil
            pendingProgressWorkouts = []
            Task { await viewModel?.refresh() }
        }) {
            if let stats = pendingProgressStats {
                PostCreationView(workouts: pendingProgressWorkouts, stats: stats)
            } else {
                PostCreationView()
            }
        }
        .sheet(item: $postToEdit) { editPost in
            if let vm = viewModel {
                EditPostView(
                    post: editPost,
                    currentUserId: currentUserId,
                    onSave: { @MainActor @Sendable [editPost] caption, visibility in
                        await vm.updatePost(editPost, caption: caption, visibility: visibility)
                    },
                    onBackfillRoute: { @MainActor @Sendable [editPost] in
                        await vm.backfillRouteMap(for: editPost)
                    }
                )
            }
        }
        .sheet(item: $likesPost) { post in
            LikesListView(postId: post.post.id, postRepository: deps.postRepository)
        }
        .task {
            if viewModel == nil {
                let vm = FeedViewModel(
                    postRepository: deps.postRepository,
                    authService: deps.authService,
                    realtimeService: deps.realtimeService
                )
                viewModel = vm
                await vm.loadInitialFeed()
                await vm.subscribeToRealtimeUpdates()
            }
            await loadActiveArena()
        }
        .onDisappear {
            if let vm = viewModel {
                Task { [weak vm] in await vm?.cleanup() }
            }
        }
        .onChange(of: refreshToken) { _, _ in
            Task { await viewModel?.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .battleScoresDidUpdate)) { _ in
            Task { await loadActiveArena() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProgressShareSheet)) { _ in
            let data = ProgressShareCoordinator.shared.consume()
            pendingProgressWorkouts = data.workouts
            pendingProgressStats = data.stats
            showingProgressShare = true
        }
    }

    // MARK: Model

    private var model: CutSocialFeedModel {
        guard let vm = viewModel else { return CutSocialFeedModel(content: .loading) }
        let rows = vm.posts.map {
            CutSocialLogic.row(Self.facts(for: $0, currentUserId: currentUserId), now: .now, weightUnit: weightUnit)
        }
        let error = vm.error.map { (title: $0.title, message: $0.message, canRetry: $0.isRetryable) }
        return CutSocialFeedModel(
            content: CutSocialLogic.content(hasViewModel: true, isLoading: vm.isLoading, error: error, rows: rows),
            newPosts: vm.newPostsAvailable,
            arena: arenaFacts.map { CutSocialLogic.arenaItem($0, weightUnit: weightUnit) },
            offlineQueue: vm.isOnline ? nil : vm.queuedActionCount,
            inlineError: CutSocialLogic.inlineError(message: vm.error?.message, postCount: vm.posts.count),
            isLoadingMore: vm.isLoadingMore,
            reachedEnd: !vm.hasMorePages && !vm.posts.isEmpty
        )
    }

    private var arenaFacts: [CutSocialArenaFacts] {
        activeBattles.map { battle in
            .battle(id: battle.id,
                    opponentName: battle.opponentProfile.displayName ?? battle.opponentProfile.username,
                    userScore: NSDecimalNumber(decimal: battle.userScore).doubleValue,
                    opponentScore: NSDecimalNumber(decimal: battle.opponentScore).doubleValue,
                    unit: battle.battle.scoreUnit)
        } + activeChallenges.map { challenge in
            .challenge(id: challenge.id, title: challenge.challenge.title, percent: challenge.userProgressPercentage)
        }
    }

    /// Plain facts for one post, read the way PostCard reads it.
    static func facts(for item: PostWithAuthor, currentUserId: UUID?) -> CutSocialPostFacts {
        let post = item.post
        let partner = post.postType == .shared ? item.partners.first { $0.removedAt == nil } : nil
        let isOwn = currentUserId != nil && post.userId == currentUserId
        let canRemoveMe: Bool = {
            guard let currentUserId, post.userId != currentUserId else { return false }
            return item.partners.contains { $0.userId == currentUserId && $0.removedAt == nil }
        }()

        let kind: CutSocialPostFacts.Kind
        if post.postType == .weeklyProgress, let stats = post.weeklyStats {
            kind = .weekly(weekStart: stats.weekStart, strengthDone: stats.strengthDaysDone, strengthTarget: stats.strengthTarget,
                           activeMinutesDone: stats.activeMinutesDone, activeMinutesTarget: stats.activeMinutesTarget,
                           streak: stats.streak)
        } else if post.postType == .battle, let stats = post.battleStats {
            kind = .battle(won: stats.isWinner, myName: stats.myName,
                           myScore: NSDecimalNumber(decimal: stats.myScore).doubleValue,
                           opponentName: stats.opponentName,
                           opponentScore: NSDecimalNumber(decimal: stats.opponentScore).doubleValue,
                           unit: stats.scoreUnit)
        } else if post.isMultiWorkout {
            let workouts = post.allWorkouts
            let durations = workouts.compactMap { WorkoutPostStatsViews.duration(for: $0) }
            kind = .multi(count: workouts.count,
                          cardioCount: workouts.filter { $0.entries.isEmpty && $0.isCardioWorkout }.count,
                          volumeKg: workouts.reduce(0) { $0 + WorkoutPostStatsViews.totalVolume(for: $1) },
                          sets: workouts.reduce(0) { $0 + WorkoutPostStatsViews.totalSets(for: $1) },
                          durationSeconds: durations.isEmpty ? nil : durations.reduce(0, +))
        } else {
            let workout = post.workoutData
            let name = workout.workoutName.flatMap { $0.isEmpty ? nil : $0 } ?? workout.workoutTypeDisplayName
            if workout.isCardioWorkout && workout.entries.isEmpty {
                kind = .cardio(name: name, distanceMeters: workout.matchedHealthKitDistance ?? 0,
                               durationSeconds: workout.matchedHealthKitDuration,
                               calories: workout.matchedHealthKitCalories,
                               averageHeartRate: workout.matchedHealthKitHeartRate)
            } else {
                kind = .strength(name: name, volumeKg: WorkoutPostStatsViews.totalVolume(for: workout),
                                 sets: WorkoutPostStatsViews.totalSets(for: workout),
                                 durationSeconds: WorkoutPostStatsViews.duration(for: workout))
            }
        }

        let visibility: CutSocialPostFacts.Visibility = switch post.visibility {
        case .publicPost: .everyone
        case .friends: .friends
        case .privatePost: .onlyMe
        }

        return CutSocialPostFacts(
            id: post.id,
            author: .init(id: item.author.id, name: item.author.displayName ?? item.author.username, avatarURL: item.author.avatarUrl),
            partner: partner.map {
                .init(id: $0.userId, name: $0.profile?.displayName ?? $0.profile?.username ?? "Partner", avatarURL: $0.profile?.avatarUrl)
            },
            createdAt: post.createdAt,
            caption: post.caption,
            visibility: visibility,
            kind: kind,
            likes: post.likesCount,
            comments: post.commentsCount,
            isLiked: item.isLikedByCurrentUser,
            isOwn: isOwn,
            canRemoveMe: canRemoveMe
        )
    }

    // MARK: Actions

    private func post(_ id: UUID) -> PostWithAuthor? {
        viewModel?.posts.first { $0.post.id == id }
    }

    private var actions: CutSocialFeedActions {
        CutSocialFeedActions(
            refresh: { await viewModel?.refresh() },
            retry: {
                guard let vm = viewModel else { return }
                Task {
                    if vm.posts.isEmpty {
                        await vm.loadInitialFeed()
                    } else {
                        await vm.refresh()
                    }
                }
            },
            loadNewPosts: { Task { await viewModel?.loadNewPosts() } },
            sync: { Task { await viewModel?.syncQueuedActions() } },
            dismissError: { viewModel?.error = nil },
            findFriends: { path.append(CutSocialRoute.userSearch) },
            openArena: { target in
                switch target {
                case .battle(let id): path.append(BattleDestination(battleId: id))
                case .challenge(let id): path.append(ChallengeDestination(challengeId: id))
                }
            },
            rowAppeared: { id in
                guard let vm = viewModel, let post = post(id) else { return }
                Task { await vm.loadMoreIfNeeded(currentPost: post) }
            },
            like: { id in
                guard let vm = viewModel, let post = post(id) else { return }
                Task { await vm.toggleLike(for: post) }
            },
            openPost: { path.append(PostDestination(postId: $0)) },
            openProfile: { path.append($0) },
            perform: { action, id in
                guard let vm = viewModel, let post = post(id) else { return }
                switch action {
                case .edit: postToEdit = post
                case .delete: Task { await vm.deletePost(post) }
                case .removeMe: Task { await vm.removeMeFromSharedPost(post) }
                case .likes: likesPost = post
                case .report:
                    // The legacy card's report: a confirmation toast, nothing is sent yet.
                    Haptics.success()
                    WorkoutToastManager.shared.show(message: "Report submitted. Thank you.")
                }
            }
        )
    }

    // MARK: Arena (FeedView's loaders)

    private func loadActiveArena() async {
        async let battles = loadActiveBattles()
        async let challenges = loadActiveChallenges()
        let (loadedBattles, loadedChallenges) = await (battles, challenges)
        activeBattles = loadedBattles
        activeChallenges = loadedChallenges
    }

    private func loadActiveBattles() async -> [BattleWithParticipants] {
        guard let currentUserId = deps.authService.currentUser?.id else { return [] }
        do {
            let battles = try await deps.battleRepository.fetchActiveBattles()
            return Array(battles.prefix(3)).map { battle in
                var updated = battle
                updated.currentUserId = currentUserId
                return updated
            }
        } catch {
            return []
        }
    }

    private func loadActiveChallenges() async -> [ChallengeWithProgress] {
        guard let userId = deps.authService.currentUser?.id else { return [] }
        do {
            if deps.workoutStore.isStorageLoaded == false {
                try? await deps.workoutStore.reloadWorkouts()
            }
            let userChallenges = try await deps.challengeRepository.fetchUserChallenges(userId: userId)
            let completedWorkouts = deps.workoutStore.completedWorkouts
            let participating = userChallenges
                .filter { $0.isParticipating && !$0.isCompleted && $0.challenge.isActive }
                .map { challenge in
                    challenge.shouldCompleteFirstRep(from: completedWorkouts)
                        ? challenge.completedFirstRepFromWorkoutHistory()
                        : challenge
                }
                .filter { !$0.isCompleted }
            return Array(participating.prefix(3))
        } catch {
            return []
        }
    }
}

// MARK: - Post media

/// Photos and route maps for one post, resolved and backfilled exactly as PostCard does:
/// generated maps first for cardio, then the poster's photos; a missing route map on your own
/// cardio post is built once on appear and can be requested again with Get route map.
struct CutSocialPostMedia: View {
    let post: PostWithAuthor
    let currentUserId: UUID?
    let backfill: () async -> Bool

    @State private var resolved: [(image: PostImage, url: URL)] = []
    @State private var isBackfilling = false
    @State private var showingViewer = false
    @State private var selectedIndex = 0

    private let imageUploadService = ImageUploadService()

    private var photos: [URL] { resolved.filter { !$0.image.isGeneratedMapImage }.map(\.url) }
    private var maps: [URL] { resolved.filter { $0.image.isGeneratedMapImage }.map(\.url) }
    private var isCardio: Bool { post.post.workoutData.isCardioWorkout }

    /// Maps lead for cardio and multi-workout posts; strength posts show photos only.
    private var urls: [URL] {
        (post.post.isMultiWorkout || isCardio) ? maps + photos : photos
    }

    private var canBuildRoute: Bool {
        post.post.userId == currentUserId && isCardio && !post.post.isMultiWorkout
            && post.post.workoutData.matchedHealthKitUUID != nil
    }

    private var taskKey: String {
        "\(post.post.id.uuidString)-\(post.post.images?.count ?? 0)-\(post.post.updatedAt.timeIntervalSince1970)"
    }

    var body: some View {
        Group {
            if !urls.isEmpty {
                carousel
            } else if canBuildRoute {
                Button {
                    Task { await runBackfill() }
                } label: {
                    Label(isBackfilling ? "Building route" : "Get route map", systemImage: "map")
                }
                .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
                .disabled(isBackfilling)
            }
        }
        .task(id: taskKey) {
            await loadImageURLs()
            if canBuildRoute, maps.isEmpty {
                await runBackfill()
            }
        }
        .sheet(isPresented: $showingViewer) {
            ImageViewer(imageUrls: urls.map(\.absoluteString), selectedIndex: $selectedIndex)
        }
    }

    private var carousel: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                KFImage(url)
                    .placeholder { Rectangle().fill(DS.Cut.Colors.controlFill) }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndex = index
                        showingViewer = true
                    }
                    .tag(index)
                    .accessibilityLabel(Text(index < maps.count && isCardio ? "Route map" : "Photo \(index + 1)"))
                    .accessibilityAddTraits(.isButton)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))
        .frame(height: 200)
    }

    private func loadImageURLs() async {
        guard let userId = currentUserId, let images = post.post.images, !images.isEmpty else { return }
        var pairs: [(image: PostImage, url: URL)] = []
        for image in images {
            if let url = try? await imageUploadService.getImageURL(for: image, currentUserId: userId, postOwnerId: post.post.userId) {
                pairs.append((image, url))
            }
        }
        resolved = pairs
    }

    private func runBackfill() async {
        guard !isBackfilling else { return }
        isBackfilling = true
        if await backfill() {
            await loadImageURLs()
        }
        isBackfilling = false
    }
}

// MARK: - Friends

/// FriendsHubView's data behind the Cut Friends pane.
struct CutSocialFriendsHost: View {
    @Binding var path: NavigationPath

    @Environment(\.dependencies) private var deps
    @State private var badgeManager = NotificationBadgeManager.shared
    @State private var viewModel: FriendsHubViewModel?

    var body: some View {
        CutSocialFriendsView(model: model, actions: CutSocialFriendsActions(
            refresh: {
                await viewModel?.refresh()
                await badgeManager.refreshBadges()
            },
            openRequests: { path.append(CutSocialRoute.friendRequests) },
            openFriend: { path.append($0) },
            openFriends: { path.append(CutSocialRoute.friendsList) },
            findFriends: { path.append(CutSocialRoute.userSearch) }
        ))
        .task {
            if viewModel == nil {
                viewModel = FriendsHubViewModel(
                    friendshipRepository: deps.friendshipRepository,
                    postRepository: deps.postRepository,
                    authService: deps.authService
                )
            }
            await viewModel?.loadFriends()
            await badgeManager.refreshBadges()
        }
    }

    private var model: CutSocialFriendsModel {
        let loaded: [CutSocialFriendFacts]? = {
            guard let vm = viewModel, !(vm.isLoading && vm.activeFriends.isEmpty) else { return nil }
            return vm.activeFriends.map { friend in
                CutSocialFriendFacts(
                    id: friend.id,
                    name: friend.profile.displayName ?? friend.profile.username,
                    avatarURL: friend.profile.avatarUrl,
                    lastWorkout: friend.lastWorkoutDate,
                    workoutsThisWeek: friend.recentWorkoutCount
                )
            }
        }()
        return CutSocialLogic.friends(loaded, requests: badgeManager.friendRequestCount, now: .now)
    }
}
