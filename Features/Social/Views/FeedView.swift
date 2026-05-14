//
//  FeedView.swift
//  WRKT
//
//  Social feed view with infinite scroll
//

import SwiftUI
import Kingfisher


struct FeedView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: FeedViewModel?
    @State private var selectedPost: PostWithAuthor?
    @State private var showingCreatePost = false
    @State private var postToEdit: PostWithAuthor?
    @State private var selectedUserId: UUID?
    @State private var selectedBattle: BattleWithParticipants?
    @State private var selectedChallenge: ChallengeWithProgress?

    // Badge manager for notifications
    @State private var badgeManager = NotificationBadgeManager.shared

    // Active Arena data
    @State private var activeBattles: [BattleWithParticipants] = []
    @State private var activeChallenges: [ChallengeWithProgress] = []
    @State private var isLoadingArena = true

    // FAB state
    @State private var isFABExpanded = false
    @State private var showingWorkoutSelector = false
    @State private var showingBattleCreation = false
    @State private var selectedMuscleFilter: MuscleFilter?

    // User search
    @State private var showingUserSearch = false

    // Likes list
    @State private var likesPost: PostWithAuthor?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                feedContent(viewModel: viewModel)
            } else {
                // Show skeleton loading state
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonPostCard()
                        }
                    }
                    .padding()
                }
            }
        }
        .overlay {
            // Dimmed background when FAB is expanded
            if isFABExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            isFABExpanded = false
                        }
                    }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Floating Action Button
            FloatingActionButton(
                isExpanded: $isFABExpanded,
                onCreatePost: {
                    showingCreatePost = true
                },
                onLogWorkout: {
                    showingWorkoutSelector = true
                },
                onStartBattle: {
                    showingBattleCreation = true
                }
            )
            .padding(.bottom, 56) // lift above custom tab bar (UITabBar.isHidden breaks safe area propagation)
        }
        .sheet(isPresented: $showingCreatePost, onDismiss: {
            // Refresh feed when post creation sheet is dismissed
            Task {
                if let vm = viewModel {
                    await vm.refresh()
                }
            }
        }) {
            PostCreationView()
        }
        .sheet(item: $postToEdit) { editPost in
            if let vm = viewModel {
                EditPostView(
                    post: editPost,
                    currentUserId: deps.authService.currentUser?.id,
                    onSave: { @MainActor @Sendable [editPost] caption, visibility in
                        await vm.updatePost(editPost, caption: caption, visibility: visibility)
                    },
                    onBackfillRoute: { @MainActor @Sendable [editPost] in
                        await vm.backfillRouteMap(for: editPost)
                    }
                )
            }
        }
        .sheet(isPresented: $showingWorkoutSelector) {
            NavigationStack {
                QuickWorkoutTypeSelector(date: Date()) { workoutType in
                    handleWorkoutTypeSelection(workoutType)
                }
            }
        }
        .sheet(isPresented: $showingBattleCreation) {
            if let currentUserId = deps.authService.currentUser?.id {
                CreateBattleView(
                    viewModel: BattleViewModel(
                        battleRepository: deps.battleRepository,
                        authService: deps.authService
                    )
                )
            }
        }
        .sheet(isPresented: $showingUserSearch) {
            NavigationStack {
                UserSearchView()
                    .environment(\.dependencies, deps)
            }
        }
        .sheet(item: $likesPost) { post in
            LikesListView(postId: post.post.id, postRepository: deps.postRepository)
        }
        .sheet(item: $selectedMuscleFilter) { muscleFilter in
            NavigationStack {
                MuscleExerciseListView(
                    state: .constant(.root),
                    subregion: nil,
                    muscleFilter: muscleFilter,
                    navigationPath: .constant(NavigationPath())
                )
                .withDependencies(deps)
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
        .navigationDestination(item: $selectedUserId) { userId in
            SocialProfileView(userId: userId)
        }
        .navigationDestination(item: $selectedBattle) { battle in
            BattleDetailView(
                battle: battle,
                viewModel: BattleViewModel(
                    battleRepository: deps.battleRepository,
                    authService: deps.authService
                )
            )
        }
        .navigationDestination(item: $selectedChallenge) { challenge in
            ChallengeDetailView(
                challenge: challenge,
                viewModel: ChallengesViewModel(
                    challengeRepository: deps.challengeRepository,
                    authService: deps.authService,
                    workoutStore: deps.workoutStore
                )
            )
            .onDisappear {
                // Refresh arena when returning from challenge detail
                Task {
                    await loadActiveArena()
                }
            }
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

            // Load active arena data
            await loadActiveArena()
        }
        .onDisappear {
            // Use weak reference to avoid retain cycle during deallocation
            if let vm = viewModel {
                Task { [weak vm] in
                    await vm?.cleanup()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialTabReselected)) { _ in
            selectedPost = nil
        }
    }

    @ViewBuilder
    private func feedContent(viewModel: FeedViewModel) -> some View {
        VStack(spacing: 0) {
            // Offline banner at the top
            if !viewModel.isOnline {
                OfflineBanner(queueCount: viewModel.queuedActionCount) {
                    Task {
                        await viewModel.syncQueuedActions()
                    }
                }
            }

            // Show error view if initial load failed
            if viewModel.posts.isEmpty && !viewModel.isLoading, let error = viewModel.error {
                ScrollView {
                    ErrorView(error: error) {
                        Task {
                            await viewModel.loadInitialFeed()
                        }
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            } else if viewModel.posts.isEmpty && !viewModel.isLoading {
                ScrollView {
                    emptyState
                }
                .refreshable {
                    await viewModel.refresh()
                }
            } else {
                ScrollView {
                VStack(spacing: 0) {
                    // Active Arena - only show if there are active competitions
                    if !activeBattles.isEmpty || !activeChallenges.isEmpty {
                        ActiveArena(
                            activeBattles: activeBattles,
                            activeChallenges: activeChallenges,
                            onBattleTap: { battle in
                                selectedBattle = battle
                            },
                            onChallengeTap: { challenge in
                                selectedChallenge = challenge
                            }
                        )
                        .padding(.top, 8)
                    }

                    LazyVStack(spacing: 16) {
                        // New posts available banner
                        if viewModel.newPostsAvailable > 0 {
                        Button {
                            Task {
                                await viewModel.loadNewPosts()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(DS.Semantic.brand)
                                Text("\(viewModel.newPostsAvailable) new \(viewModel.newPostsAvailable == 1 ? "post" : "posts")")
                                    .dsFont(.subheadline, weight: .bold)
                                    .foregroundStyle(DS.Semantic.textPrimary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(DS.Semantic.brandSoft)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Show skeleton cards during initial load
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonPostCard()
                        }
                    } else {
                        // Real posts
                        ForEach(viewModel.posts) { post in
                            PostCard(
                                post: post,
                                currentUserId: deps.authService.currentUser?.id,
                                onLike: {
                                    Task {
                                        await viewModel.toggleLike(for: post)
                                    }
                                },
                                onComment: {
                                    selectedPost = post
                                },
                                onShowLikes: {
                                    likesPost = post
                                },
                                onProfileTap: {
                                    selectedUserId = post.author.id
                                },
                                onPostTap: {
                                    selectedPost = post
                                },
                                onEdit: {
                                    postToEdit = post
                                },
                                onDelete: {
                                    Task {
                                        await viewModel.deletePost(post)
                                    }
                                },
                                onBackfillRoute: {
                                    await viewModel.backfillRouteMap(for: post)
                                }
                            )
                            .onAppear {
                                Task {
                                    await viewModel.loadMoreIfNeeded(currentPost: post)
                                }
                            }
                        }

                        // Loading indicator at bottom during pagination
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 8)
                                Text("Loading more...")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                Spacer()
                            }
                            .padding()
                        }

                        // End of feed indicator
                        if !viewModel.hasMorePages && !viewModel.posts.isEmpty {
                            HStack {
                                Spacer()
                                Text("You're all caught up!")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                    .padding(.vertical, 16)
                                Spacer()
                            }
                        }
                    }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 80)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .overlay(alignment: .top) {
                // Show inline error banner for errors during refresh/pagination
                if let error = viewModel.error, !viewModel.posts.isEmpty {
                    InlineErrorView(
                        error: error,
                        onRetry: {
                            Task {
                                await viewModel.refresh()
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.textSecondary)

            VStack(spacing: 8) {
                Text("No Posts Yet")
                    .dsFont(.title2, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Add friends to see their workouts here")
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingUserSearch = true
            } label: {
                Text("Find Friends")
                    .dsFont(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(DS.Semantic.brand)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadActiveArena() async {
        isLoadingArena = true

        // Load active battles and challenges in parallel
        async let battlesResult = loadActiveBattles()
        async let challengesResult = loadActiveChallenges()

        let (battles, challenges) = await (battlesResult, challengesResult)

        activeBattles = battles
        activeChallenges = challenges
        isLoadingArena = false
    }

    private func loadActiveBattles() async -> [BattleWithParticipants] {
        guard let currentUserId = deps.authService.currentUser?.id else {
            return []
        }

        do {
            let battles = try await deps.battleRepository.fetchActiveBattles()
            // Limit to first 3 for the arena
            let limited = Array(battles.prefix(3))
            return limited.map { battle in
                var updated = battle
                updated.currentUserId = currentUserId
                return updated
            }
        } catch {
            return []
        }
    }

    private func loadActiveChallenges() async -> [ChallengeWithProgress] {
        guard let userId = deps.authService.currentUser?.id else {
            return []
        }

        do {
            if deps.workoutStore.isStorageLoaded == false {
                try? await deps.workoutStore.reloadWorkouts()
            }

            let userChallenges = try await deps.challengeRepository.fetchUserChallenges(userId: userId)
            let completedWorkouts = deps.workoutStore.completedWorkouts
            let participating = userChallenges
                .filter { $0.isParticipating && !$0.isCompleted && $0.challenge.isActive }
                .map { challenge in
                    if challenge.shouldCompleteFirstRep(from: completedWorkouts) {
                        return challenge.completedFirstRepFromWorkoutHistory()
                    }
                    return challenge
                }
                .filter { !$0.isCompleted }

            // Limit to first 3 for the arena
            let limited = Array(participating.prefix(3))
            return limited
        } catch {
            return []
        }
    }

    // MARK: - Workout Type Selection

    private func handleWorkoutTypeSelection(_ type: QuickWorkoutTypeSelector.WorkoutType) {
        // Map workout type to muscle filter
        let muscleFilter: MuscleFilter

        switch type {
        case .upperBody:
            muscleFilter = .upperBody
        case .lowerBody:
            muscleFilter = .lowerBody
        case .custom:
            muscleFilter = .fullBody
        }

        // Dismiss the workout selector, then show muscle exercise list
        showingWorkoutSelector = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.selectedMuscleFilter = muscleFilter
        }
    }
}

// MARK: - Preview

#Preview {
    FeedView()
        .environment(\.dependencies, AppDependencies.shared)
}
