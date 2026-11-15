//
//  CutPostDetailHost.swift
//  WRKT
//
//  Feeds the Cut post detail from what the legacy PostDetailView already uses: the same
//  PostDetailViewModel (like state, comments, replies, mentions, cardio refresh), the same
//  image URLs and the same likes sheet. PostLoaderView's fetch-by-id is mirrored for the
//  loading and not found states. Only the presentation differs.
//

import SwiftUI

struct CutPostDetailHost: View {
    let post: PostWithAuthor

    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var viewModel: PostDetailViewModel?
    @State private var showingLikes = false
    @State private var editingPost: PostWithAuthor?
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var currentUserId: UUID? { deps.authService.currentUser?.id }

    var body: some View {
        Group {
            if let viewModel {
                CutPostDetailView(
                    model: CutPostDetailLogic.model(Self.facts(viewModel, currentUserId: currentUserId), now: .now, weightUnit: weightUnit),
                    commentText: Binding(get: { viewModel.commentText }, set: { viewModel.commentText = $0 }),
                    actions: actions(viewModel)
                ) {
                    // The poster's photos and generated maps, as on the feed; the detail never builds a route.
                    CutSocialPostMedia(post: viewModel.post, currentUserId: currentUserId, allowsBackfill: false, mapsOpenFullscreen: true) { false }
                }
            } else {
                CutPostLoaderStateView(state: .loading)
            }
        }
        // The bar is the top row (back, author, like); the lime block carries the title.
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLikes) {
            LikesListView(postId: post.post.id, postRepository: deps.postRepository)
        }
        // Your own post: the feed's editor and delete, from the menu in the top row.
        .sheet(item: $editingPost) { editing in
            EditPostView(
                post: editing,
                currentUserId: currentUserId,
                onSave: { @MainActor @Sendable caption, visibility in
                    await savePost(caption: caption, visibility: visibility)
                },
                onBackfillRoute: { @MainActor @Sendable [deps] in
                    // The feed's route rebuild; it needs no feed state for one post.
                    await FeedViewModel(postRepository: deps.postRepository, authService: deps.authService,
                                        realtimeService: deps.realtimeService).backfillRouteMap(for: editing)
                }
            )
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) { Task { await deletePost() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the post, its likes and its comments.")
        }
        .alert("Could not delete the post", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
        .task {
            // PostDetailView's loads, in the same order.
            if viewModel == nil {
                let vm = PostDetailViewModel(post: post, postRepository: deps.postRepository, authService: deps.authService)
                viewModel = vm
                await vm.refreshLikeState()
                await vm.loadComments()
                if vm.canRefreshCardioData, post.post.workoutData.cardioHRZones == nil {
                    await vm.refreshCardioData()
                }
            }
        }
    }

    private func actions(_ vm: PostDetailViewModel) -> CutPostDetailActions {
        CutPostDetailActions(
            like: { Task { await vm.toggleLike() } },
            showLikes: { showingLikes = true },
            refreshCardio: { Task { await vm.refreshCardioData() } },
            retryComments: { Task { await vm.loadComments() } },
            reply: { id in
                if let comment = vm.comments.first(where: { $0.id == id }) { vm.startReply(to: comment) }
            },
            cancelReply: { vm.cancelReply() },
            deleteComment: { id in
                if let comment = vm.comments.first(where: { $0.id == id }) {
                    Task { await vm.deleteComment(comment) }
                }
            },
            commentTextChanged: { vm.detectMentionQuery(in: $0) },
            selectSuggestion: { id in
                if let user = vm.mentionSuggestions.first(where: { $0.id == id }) { vm.insertMention(user) }
            },
            send: { await vm.postComment() },
            dismissError: { vm.error = nil },
            feedback: { Haptics.light() },
            editPost: { editingPost = vm.post },
            deletePost: { if !isDeleting { confirmsDelete = true } }
        )
    }

    /// FeedViewModel.updatePost's save, applied to the post on screen.
    private func savePost(caption: String?, visibility: PostVisibility) async {
        guard let vm = viewModel else { return }
        do {
            try await deps.postRepository.updatePost(vm.post.post.id, caption: caption, visibility: visibility)
            var updated = vm.post
            updated.post.caption = caption
            updated.post.visibility = visibility
            updated.post.updatedAt = Date()
            vm.post = updated
            Haptics.success()
        } catch {
            vm.error = "Failed to update post"
            Haptics.error()
        }
    }

    /// Deletes the post and leaves the screen; the feed drops it on its next refresh.
    private func deletePost() async {
        guard let vm = viewModel, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await deps.postRepository.deletePost(vm.post.post.id)
            Haptics.warning()
            dismiss()
        } catch {
            deleteFailed = true
            Haptics.error()
        }
    }

    // MARK: Facts

    @MainActor
    static func facts(_ vm: PostDetailViewModel, currentUserId: UUID?) -> CutPostDetailFacts {
        let item = vm.post
        return CutPostDetailFacts(
            post: CutSocialFeedHost.facts(for: item, currentUserId: currentUserId),
            battleDetail: item.post.battleStats.map { "\($0.battleType.displayName), \($0.durationDays)-day battle, ended \($0.endDate.formatted(date: .abbreviated, time: .omitted))" },
            zoneMethod: HRZoneCalculator.shared.methodDisplayName,
            workouts: item.post.allWorkouts.map(workoutFacts),
            currentUserId: currentUserId,
            canRefreshCardio: vm.canRefreshCardioData,
            isRefreshingCardio: vm.isRefreshingCardioData,
            isTogglingLike: vm.isTogglingLike,
            comments: vm.comments.map(commentFacts),
            isLoadingComments: vm.isLoadingComments,
            error: vm.error,
            replyingTo: vm.replyingTo.map { $0.author.map(personFacts) ?? .init(id: $0.userId, username: "unknown") },
            suggestions: vm.mentionSuggestions.map(personFacts),
            commentText: vm.commentText,
            isPostingComment: vm.isPostingComment
        )
    }

    static func workoutFacts(_ workout: CompletedWorkout) -> CutPostDetailFacts.WorkoutFacts {
        let isCardio = workout.isCardioWorkout && workout.entries.isEmpty
        return CutPostDetailFacts.WorkoutFacts(
            name: workout.workoutName.flatMap { $0.isEmpty ? nil : $0 } ?? workout.workoutTypeDisplayName,
            isCardio: isCardio,
            durationSeconds: WorkoutPostStatsViews.duration(for: workout),
            calories: workout.matchedHealthKitCalories,
            sets: WorkoutPostStatsViews.totalSets(for: workout),
            distanceMeters: workout.matchedHealthKitDistance ?? 0,
            exercises: workout.entries.map { entry in
                CutPostDetailFacts.ExerciseFacts(
                    name: entry.exerciseName,
                    sets: entry.sets.map { set in
                        CutPostDetailFacts.SetFacts(value: set.displayValue, reps: set.reps, tag: set.tag,
                                                    workSeconds: set.workDuration, restSeconds: set.restAfterSeconds)
                    },
                    volumeKg: entry.sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight },
                    workSeconds: entry.totalDuration > 0 ? entry.totalWorkTime : 0,
                    restSeconds: entry.totalDuration > 0 ? entry.totalRestTime : 0,
                    totalReps: entry.sets.reduce(0) { $0 + $1.reps }
                )
            },
            averageHeartRate: workout.matchedHealthKitHeartRate,
            maxHeartRate: workout.matchedHealthKitMaxHeartRate,
            minHeartRate: workout.matchedHealthKitMinHeartRate,
            heartRateSamples: workout.matchedHealthKitHeartRateSamples ?? [],
            splits: workout.cardioSplits ?? [],
            zones: workout.cardioHRZones ?? [],
            power: workout.cardioAvgPower,
            cadence: workout.cardioAvgCadence,
            strideLength: workout.cardioAvgStrideLength,
            groundContact: workout.cardioAvgGroundContactTime,
            verticalOscillation: workout.cardioAvgVerticalOscillation
        )
    }

    static func commentFacts(_ comment: PostComment) -> CutPostDetailFacts.CommentFacts {
        CutPostDetailFacts.CommentFacts(
            id: comment.id,
            userId: comment.userId,
            name: comment.author?.displayName,
            username: comment.author?.username,
            avatarURL: comment.author?.avatarUrl,
            text: comment.content,
            createdAt: comment.createdAt,
            replies: (comment.replies ?? []).map(commentFacts)
        )
    }

    static func personFacts(_ profile: UserProfile) -> CutPostDetailFacts.PersonFacts {
        .init(id: profile.id, username: profile.username, name: profile.displayName, avatarURL: profile.avatarUrl)
    }
}

// MARK: - Loader

/// PostLoaderView's fetch behind the Cut loading and not found states; a found post opens
/// PostDetailView, which branches to the Cut detail itself.
struct CutPostLoaderHost: View {
    let postId: UUID

    @Environment(\.dependencies) private var deps
    @State private var post: PostWithAuthor?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                CutPostLoaderStateView(state: .loading)
            } else if let post {
                PostDetailView(post: post)
                    .environment(\.dependencies, deps)
            } else {
                CutPostLoaderStateView(state: .failed(errorMessage ?? CutPostDetailLogic.notFoundMessage)) {
                    Task { await loadPost() }
                }
            }
        }
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPost() }
    }

    /// PostLoaderView.loadPost, unchanged: the post is looked up in the first feed page.
    private func loadPost() async {
        guard let userId = deps.authService.currentUser?.id else {
            errorMessage = "Not logged in"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await deps.postRepository.fetchFeed(userId: userId, limit: 100, cursor: nil)
            if let found = result.posts.first(where: { $0.post.id == postId }) {
                post = found
            } else {
                errorMessage = CutPostDetailLogic.notFoundMessage
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
