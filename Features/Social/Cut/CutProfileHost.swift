import SwiftUI
import SwiftData
import PhotosUI

struct CutProfileHost: View {
    let userId: UUID
    let battleId: UUID?
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @Query private var progress: [RewardProgress]
    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" }) private var barbellConfigs: [BarbellConfig]
    @State private var viewModel: ProfileViewModel?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var battle: BattleWithParticipants?
    @State private var isBattleLoading = false
    @State private var showingEditProfile = false
    @State private var showingFriendBarbellRoom = false
    @State private var selectedPost: PostWithAuthor?
    @State private var friendRackedPlates: [EarnedPlateInfo] = []
    @State private var friendBarbellShowcase: BarbellFriendShowcase?

    var body: some View {
        CutProfileView(model: model, actions: actions, avatarPicker: {
            if let vm = viewModel, vm.isOwnProfile {
                PhotosPicker(selection: Binding(get: { vm.selectedPhoto }, set: { item in
                    vm.selectedPhoto = item
                    if item != nil { Task { await vm.uploadProfilePicture() } }
                }), matching: .images) {
                    if vm.isUploadingAvatar { ProgressView().frame(width: 44, height: 44) }
                    else { Label("Change profile photo", systemImage: "camera.fill").labelStyle(.iconOnly).frame(width: 44, height: 44) }
                }
                .buttonStyle(CutIconButtonStyle(tone: .lime, diameter: 44))
                .disabled(vm.isUploadingAvatar)
            }
        }, showcase: {
            if let vm = viewModel {
                if vm.isOwnProfile {
                    BarbellShowcaseCard(isOwnProfile: true, ownerId: userId,
                                        sessionCount: barbellConfigs.first?.totalStrengthWorkouts ?? 0, friendRackedPlates: [])
                } else {
                    BarbellShowcasePreviewSurface(context: .socialProfileCard, plates: friendRackedPlates,
                        selectedBarID: friendBarSkinIndex, selectedRoomThemeID: friendRoomThemeID,
                        selectedRackStyleID: friendRackStyleID, showPlateEngravings: friendShowPlateEngravings)
                        .frame(height: 240).clipped()
                }
            }
        })
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPost) { PostDetailView(post: $0) }
        .sheet(isPresented: $showingEditProfile) {
            if let vm = viewModel { EditProfileView(profile: vm.profile) { vm.profile = $0 } }
        }
        .sheet(isPresented: $showingFriendBarbellRoom) {
            FriendBarbellRoomView(showcase: friendBarbellShowcase, plates: friendRackedPlates,
                selectedBarSkinIndex: friendBarSkinIndex, selectedRoomThemeID: friendRoomThemeID,
                selectedRackStyleID: friendRackStyleID, showPlateEngravings: friendShowPlateEngravings, totalWeight: friendTotalWeight)
        }
        .task {
            if viewModel == nil && !isLoading { await loadProfile() }
            if let battleId, battle == nil && !isBattleLoading { await loadBattle(battleId: battleId) }
            else if battleId == nil, battle == nil && !isBattleLoading { await loadPendingBattleInvite() }
            await loadFriendBarbellShowcase()
            // Streak validation remains a cold-start responsibility, as in the legacy screen.
        }
    }

    private var model: CutProfileModel {
        CutProfileLogic.model(viewModel.map(facts), error: loadError, isLoading: isLoading, now: .now)
    }
    private func facts(_ vm: ProfileViewModel) -> CutProfileFacts {
        let friendship: CutProfileFacts.Friendship = switch vm.friendshipStatus {
        case .none: .none; case .friends: .friends; case .pendingSent: .pendingSent; case .pendingReceived: .pendingReceived
        }
        return .init(name: vm.profile.displayName, username: vm.profile.username, bio: vm.profile.bio, avatarURL: vm.profile.avatarUrl,
                     isOwn: vm.isOwnProfile, isPrivate: vm.profile.isPrivate, isBlocked: vm.currentFriendship?.status == .blocked,
                     friendship: friendship, isMuted: vm.isMuted, isLoadingFriendship: vm.isLoadingFriendship,
                     isUploadingAvatar: vm.isUploadingAvatar, friendCount: vm.friendCount, profileStreak: vm.profile.weeklyGoalStreak,
                     localStreak: progress.first?.weeklyGoalStreakCurrent ?? 0,
                     posts: vm.posts.map { item in
                         let w = item.post.workoutData
                         return .init(id: item.post.id, workoutDate: w.date, createdAt: item.post.createdAt,
                                      title: w.workoutName ?? w.workoutTypeDisplayName, caption: item.post.caption, icon: w.workoutIcon,
                                      isCardio: w.isCardioWorkout, exercises: item.post.exerciseCount, sets: item.post.totalSets,
                                      distanceMeters: w.matchedHealthKitDistance, durationSeconds: w.matchedHealthKitDuration,
                                      estimatedDuration: w.estimatedDuration, firstSplitPace: w.cardioSplits?.first?.paceSecPerKm)
                     }, isLoadingPosts: vm.isLoadingPosts, viewerWorkoutDates: store.completedWorkouts.map(\.date),
                     battle: battle.flatMap { $0.battle.status == .pending ? .init(type: $0.battle.battleType.displayName, days: $0.battle.duration, start: $0.battle.startDate) : nil }, barbellWeightKg: friendTotalWeight)
    }
    private var actions: CutProfileActions {
        .init(refresh: {
            guard let vm = viewModel else { return }
            async let posts: () = vm.loadUserPosts()
            async let friends: () = vm.loadFriendCount()
            async let barbell: () = loadFriendBarbellShowcase()
            async let invite: () = loadPendingBattleInvite()
            _ = await (posts, friends, barbell, invite)
        }, retry: { Task { await loadProfile() } }, perform: { action in
            guard let vm = viewModel else { return }
            switch action {
            case .edit: showingEditProfile = true
            case .add: Task { await vm.sendFriendRequest() }
            case .cancel: Task { await vm.cancelFriendRequest() }
            case .accept: Task { await vm.acceptFriendRequest() }
            case .decline: Task { await vm.declineFriendRequest() }
            case .mute, .unmute: Task { await vm.toggleMuteNotifications() }
            case .remove: vm.removeFriend()
            }
        }, openPost: { id in selectedPost = viewModel?.posts.first { $0.post.id == id } },
              acceptBattle: { if let battle { Task { await acceptBattle(battle: battle.battle) } } },
              declineBattle: { if let battle { Task { await declineBattle(battle: battle.battle) } } },
              openRoom: { showingFriendBarbellRoom = true })
    }
    private func loadFriendBarbellShowcase() async {
        guard userId != deps.authService.currentUser?.id else { return }

        do {
            let showcase = try await deps.barbellProgressService.friendBarbellShowcase(userID: userId)
            if showcase.plates.isEmpty,
               let existingShowcase = friendBarbellShowcase,
               !existingShowcase.plates.isEmpty {
                AppLogger.warning(
                    "Ignored empty friend barbell showcase refresh for user=\(userId) while existing showcase has plates",
                    category: AppLogger.rewards
                )
                return
            }
            friendBarbellShowcase = showcase
            friendRackedPlates = showcase.plates
        } catch {
            if let showcaseError = error as? BarbellShowcaseLoadError,
               showcaseError == .cancelled {
                return
            }

            if friendBarbellShowcase == nil {
                friendRackedPlates = []
            }
        }
    }

    private func loadBattle(battleId: UUID) async {
        AppLogger.info(" Loading battle: \(battleId)", category: AppLogger.battles)
        isBattleLoading = true

        do {
            let fetchedBattle = try await deps.battleRepository.fetchBattle(id: battleId)
            battle = fetchedBattle
            AppLogger.info(" Battle loaded successfully: status=\(fetchedBattle.battle.status), isPending=\(fetchedBattle.battle.status == .pending)", category: AppLogger.battles)
        } catch {
            AppLogger.error(" Failed to load battle: \(battleId)", error: error, category: AppLogger.battles)
            // Don't fail the entire profile view - just log and continue without the battle card
            // This allows the user to still see the profile even if battle loading fails
        }

        isBattleLoading = false
    }

    private func loadPendingBattleInvite() async {
        guard userId != deps.authService.currentUser?.id else { return }
        guard let currentUserId = deps.authService.currentUser?.id else { return }

        isBattleLoading = true
        defer { isBattleLoading = false }

        do {
            let pendingBattles = try await deps.battleRepository.fetchPendingBattles()
            battle = pendingBattles.first { pendingBattle in
                pendingBattle.battle.challengerId == userId &&
                pendingBattle.battle.opponentId == currentUserId
            }
        } catch {
            AppLogger.error("Failed to load pending battle invite for profile", error: error, category: AppLogger.battles)
        }
    }

    private func loadProfile() async {
        isLoading = true
        loadError = nil

        // Try to get profile from cache first (if viewing own profile)
        if userId == deps.authService.currentUser?.id,
           let currentProfile = deps.authService.currentUser?.profile {
            let vm = ProfileViewModel(
                profile: currentProfile,
                postRepository: deps.postRepository,
                friendshipRepository: deps.friendshipRepository,
                imageUploadService: deps.imageUploadService,
                authService: deps.authService
            )
            viewModel = vm
            isLoading = false

            async let posts: () = vm.loadUserPosts()
            async let friendship: () = vm.loadFriendshipStatus()
            async let friends: () = vm.loadFriendCount()
            _ = await (posts, friendship, friends)
        } else {
            // Fetch profile from database for other users
            // Retry up to 2 times to handle transient errors
            var lastError: Error?
            for attempt in 1...2 {
                do {
                    let profile = try await deps.authService.fetchProfile(userId: userId)

                    let vm = ProfileViewModel(
                        profile: profile,
                        postRepository: deps.postRepository,
                        friendshipRepository: deps.friendshipRepository,
                        imageUploadService: deps.imageUploadService,
                        authService: deps.authService
                    )
                    viewModel = vm
                    isLoading = false

                    async let posts: () = vm.loadUserPosts()
                    async let friendship: () = vm.loadFriendshipStatus()
                    async let friends: () = vm.loadFriendCount()
                    _ = await (posts, friendship, friends)
                    return // Success, exit early
                } catch {
                    lastError = error
                    if attempt < 2 {
                        // Wait briefly before retrying
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    }
                }
            }

            // All retries failed
            isLoading = false
            if let supabaseError = lastError as? SupabaseError {
                switch supabaseError {
                case .profileNotFound:
                    loadError = "Profile not found"
                default:
                    loadError = "Failed to load profile. Please try again."
                }
            } else {
                loadError = "Failed to load profile. Please try again."
            }
        }
    }

    private var friendBarSkinIndex: Int {
        switch friendBarbellShowcase?.barSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
        case "volia": return 4
        default: return 0
        }
    }

    private var friendRoomThemeID: String {
        friendBarbellShowcase?.roomThemeID ?? BarbellCustomizationDefaults.roomThemeID
    }

    private var friendRackStyleID: String {
        friendBarbellShowcase?.rackStyleID ?? BarbellCustomizationDefaults.rackStyleID
    }

    private var friendShowPlateEngravings: Bool {
        friendBarbellShowcase?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
    }

    private var friendTotalWeight: Double {
        let earned = friendRackedPlates.filter { $0.earnedByEvent != "starter" }
        return 20 + earned.reduce(0) { $0 + $1.weightKg } * 2
    }

    private func acceptBattle(battle: Battle) async {
        do {
            try await deps.battleRepository.acceptBattle(battle)
            Haptics.success()
            // Dismiss or refresh
            self.battle = nil
            dismiss()
        } catch {
            AppLogger.error("Failed to accept battle", error: error, category: AppLogger.battles)
            Haptics.error()
        }
    }

    private func declineBattle(battle: Battle) async {
        do {
            try await deps.battleRepository.declineBattle(battle)
            Haptics.success()
            // Dismiss or refresh
            self.battle = nil
            dismiss()
        } catch {
            AppLogger.error("Failed to decline battle", error: error, category: AppLogger.battles)
            Haptics.error()
        }
    }
}
