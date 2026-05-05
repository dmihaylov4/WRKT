//
//  SocialProfileView.swift
//  WRKT
//
//  Social user profile view with workout posts and stats
//

import SwiftUI
import PhotosUI
import SwiftData
import Kingfisher

@MainActor

enum ProfileFriendshipStatus {
    case none
    case friends
    case pendingSent
    case pendingReceived
}

struct SocialProfileView: View {
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @Query private var progress: [RewardProgress]

    let userId: UUID
    let battleId: UUID?

    @State private var viewModel: ProfileViewModel?
    @State private var showingEditProfile = false
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var battle: BattleWithParticipants?
    @State private var isBattleLoading = false
    @State private var showingFriendBarbellRoom = false

    // Badge manager for notifications
    @State private var badgeManager = NotificationBadgeManager.shared

    // Virtual run invite
    @State private var isInvitingToRun = false
    @State private var runInviteSent = false

    // Barbell showcase
    @State private var friendRackedPlates: [EarnedPlateInfo] = []
    @State private var friendBarbellShowcase: BarbellFriendShowcase?
    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
    private var barbellConfigs: [BarbellConfig]

    init(userId: UUID, battleId: UUID? = nil) {
        self.userId = userId
        self.battleId = battleId
    }

    var body: some View {
        Group {
            // Only show error if we're not loading and there's an error
            if let error = loadError, !isLoading {
                errorView(error: error)
            } else if let viewModel = viewModel {
                content(viewModel: viewModel)
            } else {
                // Show skeleton loading state
                ScrollView {
                    SkeletonProfileHeader()
                        .padding(.bottom, 20)

                    // Skeleton posts section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Workouts")
                            .dsFont(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .padding(.horizontal)

                        ForEach(0..<2, id: \.self) { _ in
                            SkeletonPostCard()
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            AppLogger.info("📱 SocialProfileView .task started: userId=\(userId), battleId=\(battleId?.uuidString ?? "nil")", category: AppLogger.battles)

            if viewModel == nil && !isLoading {
                await loadProfile()
            }

            // Load battle if battleId is provided
            if let battleId = battleId, battle == nil && !isBattleLoading {
                AppLogger.info("🎯 Attempting to load battle with ID: \(battleId)", category: AppLogger.battles)
                await loadBattle(battleId: battleId)
            } else if battleId == nil {
                AppLogger.info("⚠️ No battleId provided to SocialProfileView", category: AppLogger.battles)
            }

            // Refresh notification badges
            await badgeManager.refreshBadges()

            await loadFriendBarbellShowcase()

            // NOTE: Don't validate streak here - validation should only happen on app cold start
        }
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
        AppLogger.info("📊 Loading battle: \(battleId)", category: AppLogger.battles)
        isBattleLoading = true

        do {
            let fetchedBattle = try await deps.battleRepository.fetchBattle(id: battleId)
            battle = fetchedBattle
            AppLogger.info("✅ Battle loaded successfully: status=\(fetchedBattle.battle.status), isPending=\(fetchedBattle.battle.status == .pending)", category: AppLogger.battles)
        } catch {
            AppLogger.error("❌ Failed to load battle: \(battleId)", error: error, category: AppLogger.battles)
            // Don't fail the entire profile view - just log and continue without the battle card
            // This allows the user to still see the profile even if battle loading fails
        }

        isBattleLoading = false
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

    private func errorView(error: String) -> some View {
        let isMissingProfile = error == "Profile not found"

        return VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(isMissingProfile ? "Profile Not Found" : "Couldn’t Load Profile")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(error)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await loadProfile()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Palette.marone)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(viewModel: ProfileViewModel) -> some View {
        ScrollView {
            if viewModel.isOwnProfile {
                VStack(spacing: 24) {
                    profileHeader(viewModel: viewModel)
                    activityLink
                    BarbellShowcaseCard(
                        isOwnProfile: true,
                        ownerId: userId,
                        sessionCount: barbellConfigs.first?.totalStrengthWorkouts ?? 0,
                        friendRackedPlates: []
                    )
                    actionButtons(viewModel: viewModel)
                    postsSection(viewModel: viewModel)
                }
                .padding()
            } else {
                VStack(spacing: 20) {
                    friendProfileTopCard(viewModel: viewModel)
                    headToHeadCard(viewModel: viewModel)
                    accountabilitySnapshot(viewModel: viewModel)
                    actionButtons(viewModel: viewModel)

                    if let battle = battle, battle.battle.status == .pending {
                        battleInviteCard(battle: battle, viewModel: viewModel)
                    }

                    postsSection(viewModel: viewModel)
                }
                .padding()
            }
        }
        .refreshable {
            async let posts: () = viewModel.loadUserPosts()
            async let friends: () = viewModel.loadFriendCount()
            async let barbell: () = loadFriendBarbellShowcase()
            _ = await (posts, friends, barbell)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: viewModel.profile) { updatedProfile in
                viewModel.profile = updatedProfile
            }
        }
        .alert("Run Invite Sent!", isPresented: $runInviteSent) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your friend will be notified. Get ready to run!")
        }
    }

    private func profileHeader(viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            profileHeaderContent(viewModel: viewModel)

            if viewModel.isOwnProfile {
                Rectangle()
                    .fill(DS.Semantic.border.opacity(0.5))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    statItem(value: "\(viewModel.posts.count)", label: "Recent Posts")
                        .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(DS.Semantic.border)
                        .frame(width: 1, height: 32)

                    statItem(value: "\(viewModel.friendCount)", label: "Friends")
                        .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(DS.Semantic.border)
                        .frame(width: 1, height: 32)

                    statItem(value: "\(progress.first?.weeklyGoalStreakCurrent ?? 0)", label: "Streak")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            ChamferedRectangle(.xl)
                .fill(DS.Semantic.fillSubtle)
        )
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    private func profileHeaderContent(viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                profileAvatar(viewModel: viewModel)

                VStack(alignment: .leading, spacing: 14) {
                    profileIdentity(viewModel: viewModel)
                    profileStatusStack(viewModel: viewModel)
                }

                Spacer(minLength: 0)
            }

            if let bio = viewModel.profile.bio, !bio.isEmpty {
                Rectangle()
                    .fill(DS.Semantic.border.opacity(0.5))
                    .frame(height: 1)

                Text(bio)
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var friendBarSkinIndex: Int {
        switch friendBarbellShowcase?.barSkinID {
        case "black_oxide": return 1
        case "gold", "brass_accent", "may_2026_brass_accent": return 2
        case "cerakote": return 3
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

    private func friendProfileTopCard(viewModel: ProfileViewModel) -> some View {
        VStack(spacing: 0) {
            profileHeaderContent(viewModel: viewModel)
                .padding(20)

            Rectangle()
                .fill(DS.Semantic.border.opacity(0.5))
                .frame(height: 1)

            ZStack(alignment: .topTrailing) {
                BarbellPreviewView(
                    mode: .showcase(plates: friendRackedPlates),
                    selectedBarID: friendBarSkinIndex,
                    selectedRoomThemeID: friendRoomThemeID,
                    selectedRackStyleID: friendRackStyleID,
                    showPlateEngravings: friendShowPlateEngravings
                )
                .frame(height: 240)
                .clipped()

                Button { showingFriendBarbellRoom = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .accessibilityLabel("Open barbell room")
                .padding(12)
            }

            HStack {
                Text("\(Int(friendTotalWeight))kg loaded")
                    .dsFont(.caption, weight: .medium)
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            ChamferedRectangle(.xl)
                .fill(DS.Semantic.fillSubtle)
        )
        .clipShape(ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .sheet(isPresented: $showingFriendBarbellRoom) {
            FriendBarbellRoomView(
                showcase: friendBarbellShowcase,
                plates: friendRackedPlates,
                selectedBarSkinIndex: friendBarSkinIndex,
                selectedRoomThemeID: friendRoomThemeID,
                selectedRackStyleID: friendRackStyleID,
                showPlateEngravings: friendShowPlateEngravings,
                totalWeight: friendTotalWeight
            )
        }
    }

    private func profileAvatar(viewModel: ProfileViewModel) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ChamferedRectangle(.large)
                .fill(DS.Semantic.surface.opacity(0.55))
                .frame(width: 112, height: 124)
                .overlay(alignment: .center) {
                    KFImage(URL(string: viewModel.profile.avatarUrl ?? ""))
                        .placeholder {
                            Rectangle()
                                .fill(DS.Semantic.brandSoft)
                                .overlay(
                                    Text(viewModel.profile.username.prefix(1).uppercased())
                                        .font(.system(size: 34, weight: .bold))
                                        .foregroundStyle(DS.Semantic.brand)
                                )
                        }
                        .fade(duration: 0.25)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 104)
                        .clipShape(Rectangle())
                        .id(viewModel.profile.avatarUrl ?? "")
                }

            if viewModel.isOwnProfile {
                PhotosPicker(selection: Binding(
                    get: { viewModel.selectedPhoto },
                    set: { newValue in
                        viewModel.selectedPhoto = newValue
                        if newValue != nil {
                            Task {
                                await viewModel.uploadProfilePicture()
                            }
                        }
                    }
                ), matching: .images) {
                    ZStack {
                        ChamferedRectangle(.small)
                            .fill(DS.Semantic.brand)
                            .frame(width: 34, height: 34)

                        if viewModel.isUploadingAvatar {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "camera.fill")
                                .dsFont(.caption, weight: .bold)
                                .foregroundStyle(.black)
                        }
                    }
                }
                .disabled(viewModel.isUploadingAvatar)
            }
        }
    }

    private func profileIdentity(viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let displayName = viewModel.profile.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(DS.Typography.custom(size: 28, weight: .bold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .multilineTextAlignment(.leading)

                Text("@\(viewModel.profile.username)")
                    .dsFont(.title3, weight: .medium)
                    .foregroundStyle(DS.Semantic.textSecondary)
            } else {
                Text("@\(viewModel.profile.username)")
                    .font(DS.Typography.custom(size: 28, weight: .bold))
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func profileStatusStack(viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            profileMetaRow(
                label: "Last Active",
                value: latestActivityDate(for: viewModel.posts).map { relativeTimeText(for: $0) } ?? "No recent sessions"
            )

            profileMetaRow(
                label: "Streak",
                value: streakText(viewModel.profile.weeklyGoalStreak)
            )
        }
        .padding(.top, 2)
    }

    private func streakText(_ streak: Int) -> String {
        streak == 0 ? "No streak yet" : "\(streak) week\(streak == 1 ? "" : "s")"
    }

    private func profileMetaRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(label):")
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textSecondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
    }

    private func accountabilityInsightCard(viewModel: ProfileViewModel) -> some View {
        let insight = primaryInsight(for: viewModel)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: insight.icon)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.brand)

                Text(insight.title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            Text(insight.message)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ChamferedRectangle(.large)
                .fill(DS.Semantic.fillSubtle)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.brand.opacity(0.35), lineWidth: 1)
        )
    }

    private func accountabilitySnapshot(viewModel: ProfileViewModel) -> some View {
        let thisWeek = friendWorkoutsThisWeek(posts: viewModel.posts)
        let active14 = activeDays(for: viewModel.posts, days: 14)
        let lastActive = latestActivityDate(for: viewModel.posts).map { relativeTimeText(for: $0) } ?? "No activity"

        return VStack(alignment: .leading, spacing: 12) {
            Text("Accountability Snapshot")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "This Week", value: "\(thisWeek)", detail: thisWeek == 1 ? "shared session" : "shared sessions")
                metricCard(title: "Last Active", value: lastActive, detail: "most recent session")
                metricCard(title: "Last 14 Days", value: "\(active14)", detail: active14 == 1 ? "active day" : "active days")
                metricCard(title: "Recent Posts", value: "\(viewModel.posts.count)", detail: "activity on profile")
            }
        }
    }

    private func headToHeadCard(viewModel: ProfileViewModel) -> some View {
        let yourWeek = viewerWorkoutsThisWeek()
        let friendWeek = friendWorkoutsThisWeek(posts: viewModel.posts)
        let yourActiveDays = viewerActiveDays(days: 14)
        let friendActiveDays = activeDays(for: viewModel.posts, days: 14)
        let maxCount = max(yourWeek, friendWeek, 1)
        let friendName = displayName(for: viewModel.profile)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("You vs \(friendName)")
                    .dsFont(.title2, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(headToHeadMessage(friendName: friendName, yourWeek: yourWeek, friendWeek: friendWeek))
                    .dsFont(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)

                Text(headToHeadCallout(friendName: friendName, yourWeek: yourWeek, friendWeek: friendWeek))
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.brand)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("This Week")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)

                HStack(spacing: 12) {
                    headToHeadStatCard(label: "You", value: "\(yourWeek)", detail: yourWeek == 1 ? "session" : "sessions")
                    headToHeadStatCard(label: friendName, value: "\(friendWeek)", detail: friendWeek == 1 ? "session" : "sessions")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Sessions")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)

                comparisonRow(label: "You", value: yourWeek, total: maxCount, color: DS.Palette.marone)
                comparisonRow(label: friendName, value: friendWeek, total: maxCount, color: Color.white.opacity(0.78))
            }
            .padding(16)
            .background(DS.Semantic.surface.opacity(0.4))
            .clipShape(ChamferedRectangle(.medium))

            Rectangle()
                .fill(DS.Semantic.border.opacity(0.45))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text("Consistency")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)

                HStack(spacing: 12) {
                    compactTrendStat(label: "You 14d", value: "\(yourActiveDays) active days")
                    compactTrendStat(label: "\(friendName) 14d", value: "\(friendActiveDays) active days")
                    compactTrendStat(label: "Streak", value: streakText(viewModel.profile.weeklyGoalStreak))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ChamferedRectangle(.large)
                .fill(DS.Semantic.fillSubtle)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    private func headToHeadCallout(friendName: String, yourWeek: Int, friendWeek: Int) -> String {
        if yourWeek == friendWeek {
            return yourWeek == 0
                ? "Neither of you has started this week."
                : "Next session breaks the tie."
        }

        if yourWeek > friendWeek {
            let delta = yourWeek - friendWeek
            return delta == 1 ? "One more session extends the lead." : "You’ve built a \(delta)-session lead."
        }

        let delta = friendWeek - yourWeek
        return delta == 1 ? "One session ties \(friendName)." : "You need \(delta) sessions to catch \(friendName)."
    }

    private func headToHeadStatCard(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(value)
                .font(DS.Typography.custom(size: 28, weight: .bold))
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(detail)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.Semantic.surface.opacity(0.4))
        .clipShape(ChamferedRectangle(.medium))
    }

    private func compactTrendStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(value)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(title: String, value: String, detail: String) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(value)
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(14)
        .background(
            ChamferedRectangle(.medium)
                .fill(DS.Semantic.fillSubtle)
        )
        .overlay(
            ChamferedRectangle(.medium)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    private func comparisonRow(label: String, value: Int, total: Int, color: Color) -> some View {
        let ratio = total > 0 ? CGFloat(value) / CGFloat(total) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                Text("\(value)")
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.Semantic.border.opacity(0.6))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: max(8, geo.size.width * ratio), height: 10)
                }
            }
            .frame(height: 10)
        }
    }

    private func relationshipBadge(viewModel: ProfileViewModel) -> some View {
        let badge: (String, String) = {
            if viewModel.isOwnProfile {
                return ("You", "person.fill")
            }

            switch viewModel.friendshipStatus {
            case .none:
                return ("Not Friends", "plus")
            case .friends:
                return ("Friends", "person.2.fill")
            case .pendingSent:
                return ("Request Sent", "arrow.up.right")
            case .pendingReceived:
                return ("Wants to Connect", "arrow.down.left")
            }
        }()

        return pillLabel(icon: badge.1, text: badge.0, tint: DS.Semantic.brand)
    }

    private func pillLabel(icon: String, text: String, tint: Color = DS.Semantic.brand) -> some View {
        return HStack(spacing: 6) {
            angularBadgeIcon(systemName: icon, tint: tint)
            Text(text)
        }
        .dsFont(.caption, weight: .semibold)
        .foregroundStyle(DS.Semantic.textPrimary)
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(DS.Semantic.surface.opacity(0.55))
        .clipShape(ChamferedRectangle(.small))
        .overlay(
            ChamferedRectangle(.small)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private func angularBadgeIcon(systemName: String, tint: Color) -> some View {
        ZStack {
            ChamferedRectangle(.small)
                .fill(tint.opacity(0.14))

            ChamferedRectangle(.small)
                .stroke(tint.opacity(0.35), lineWidth: 1)

            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
    }

    private func primaryInsight(for viewModel: ProfileViewModel) -> (title: String, message: String, icon: String) {
        let friendName = displayName(for: viewModel.profile)
        let friendWeek = friendWorkoutsThisWeek(posts: viewModel.posts)
        let yourWeek = viewerWorkoutsThisWeek()

        if let lastWorkout = latestActivityDate(for: viewModel.posts) {
            let hoursAgo = Date().timeIntervalSince(lastWorkout) / 3600
            if hoursAgo <= 24 {
                return (
                    "Fresh activity",
                    "\(friendName) logged a session \(relativeTimeText(for: lastWorkout)). This is the right moment to answer back.",
                    "bolt.fill"
                )
            }
        }

        if friendWeek > yourWeek {
            let delta = friendWeek - yourWeek
            return (
                "Momentum favors \(friendName)",
                delta == 1 ? "You’re one session behind. A single workout ties it." : "You’re \(delta) sessions behind. This should feel urgent.",
                "figure.run"
            )
        }

        if yourWeek > friendWeek {
            let delta = yourWeek - friendWeek
            return (
                "You have the edge",
                delta == 1 ? "You’re ahead by one session. Another workout makes the gap real." : "You’re ahead by \(delta) sessions. Don’t let the pressure disappear.",
                "flag.fill"
            )
        }

        let active14 = activeDays(for: viewModel.posts, days: 14)
        return (
            "It’s close",
            active14 > 0 ? "\(friendName) has been active \(active14) day\(active14 == 1 ? "" : "s") in the last two weeks. The next move matters." : "\(friendName) has no recent shared activity. Use this profile to pull them back in.",
            "equal.circle.fill"
        )
    }

    private func headToHeadMessage(friendName: String, yourWeek: Int, friendWeek: Int) -> String {
        if yourWeek == friendWeek {
            return yourWeek == 0
                ? "Neither of you has logged a session this week yet."
                : "You’re tied. The next session puts someone in front."
        }

        if yourWeek > friendWeek {
            let delta = yourWeek - friendWeek
            return delta == 1 ? "You’re ahead by one session." : "You’re ahead by \(delta) sessions."
        }

        let delta = friendWeek - yourWeek
        return delta == 1 ? "\(friendName) is ahead by one session." : "\(friendName) is ahead by \(delta) sessions."
    }

    private func displayName(for profile: UserProfile) -> String {
        if let name = profile.displayName, !name.isEmpty {
            return name
        }
        return profile.username
    }

    private func latestActivityDate(for posts: [WorkoutPost]) -> Date? {
        posts.map(\.workoutData.date).max()
    }

    private func friendWorkoutsThisWeek(posts: [WorkoutPost]) -> Int {
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: 2)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? .now

        return posts.filter { post in
            post.workoutData.date >= weekStart && post.workoutData.date < weekEnd
        }.count
    }

    private func activeDays(for posts: [WorkoutPost], days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: .now) ?? .now
        let uniqueDays = Set(posts
            .filter { $0.workoutData.date >= cutoff }
            .map { Calendar.current.startOfDay(for: $0.workoutData.date) })

        return uniqueDays.count
    }

    private func viewerWorkoutsThisWeek() -> Int {
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: 2)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? .now

        return store.completedWorkouts.filter { workout in
            workout.date >= weekStart && workout.date < weekEnd
        }.count
    }

    private func viewerActiveDays(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: .now) ?? .now
        let uniqueDays = Set(store.completedWorkouts
            .filter { $0.date >= cutoff }
            .map { Calendar.current.startOfDay(for: $0.date) })

        return uniqueDays.count
    }

    private func relativeTimeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private var activityLink: some View {
        NavigationLink {
            ActivityFeedView()
                .environment(\.dependencies, deps)
        } label: {
            HStack {
                Label("Activity", systemImage: "bell.fill")
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                if badgeManager.notificationCount > 0 {
                    Text("\(badgeManager.notificationCount)")
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DS.Semantic.brand)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding()
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.medium))
        }
    }

    private func actionButtons(viewModel: ProfileViewModel) -> some View {
        return Group {
            if viewModel.isOwnProfile {
                Button {
                    showingEditProfile = true
                } label: {
                    Text("Edit Profile")
                        .dsFont(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Palette.marone)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                friendActionButton(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private func friendActionButton(viewModel: ProfileViewModel) -> some View {
        switch viewModel.friendshipStatus {
        case .none:
            VStack(alignment: .leading, spacing: 12) {
                Text("Next Move")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Button {
                    Task {
                        await viewModel.sendFriendRequest()
                    }
                } label: {
                    if viewModel.isLoadingFriendship {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Add Friend")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isLoadingFriendship)

                Text("Add them first, then use this page to compare momentum and push each other.")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(16)
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )

        case .friends:
            VStack(alignment: .leading, spacing: 12) {
                Text("Next Move")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                HStack(spacing: 12) {
                    Button {
                        Task { await sendRunInvite() }
                    } label: {
                        HStack {
                            if isInvitingToRun {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "figure.run")
                                Text("Invite to Run")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isInvitingToRun)

                    Menu {
                        Button {
                            Task { await viewModel.toggleMuteNotifications() }
                        } label: {
                            Label(
                                viewModel.isMuted ? "Unmute Notifications" : "Mute Notifications",
                                systemImage: viewModel.isMuted ? "bell.fill" : "bell.slash.fill"
                            )
                        }

                        Button(role: .destructive) {
                            viewModel.removeFriend()
                        } label: {
                            Label("Remove Friend", systemImage: "person.fill.xmark")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DS.Semantic.brand)
                            Text("Friends")

                            if viewModel.isMuted {
                                Image(systemName: "bell.slash.fill")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Semantic.surface)
                        .clipShape(ChamferedRectangle(.medium))
                    }
                }

                Text("Use the run invite when you want action now. Use the friend menu when you need quieter control.")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(16)
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )

        case .pendingSent:
            VStack(alignment: .leading, spacing: 12) {
                Text("Waiting On Them")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Button {
                    Task {
                        await viewModel.cancelFriendRequest()
                    }
                } label: {
                    Text("Cancel Request")
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("They need to accept before this page becomes useful for accountability.")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(16)
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )

        case .pendingReceived:
            VStack(alignment: .leading, spacing: 12) {
                Text("Open The Loop")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.acceptFriendRequest()
                        }
                    } label: {
                        Text("Accept")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        Task {
                            await viewModel.declineFriendRequest()
                        }
                    } label: {
                        Text("Decline")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Text("Accept to unlock head-to-head pressure and live accountability actions.")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(16)
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
        }
    }

    private func postsSection(viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            if viewModel.isLoadingPosts {
                // Show skeleton posts while loading
                LazyVStack(spacing: 16) {
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonPostCard()
                    }
                }
            } else if viewModel.posts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 50))
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text("No workouts shared yet")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { post in
                        // Simple post preview
                        postPreview(post: post)
                    }
                }
            }
        }
    }

    private func postPreview(post: WorkoutPost) -> some View {
        let workout = post.workoutData

        return VStack(alignment: .leading, spacing: 12) {
            if let caption = post.caption {
                Text(caption)
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .lineLimit(2)
            }

            HStack {
                Image(systemName: workout.workoutIcon)
                    .foregroundStyle(DS.Semantic.brand)
                Text(workout.workoutName ?? workout.workoutTypeDisplayName)
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                Text(post.createdAt, style: .date)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            HStack(spacing: 16) {
                if workout.isCardioWorkout {
                    cardioPreviewStats(for: workout)
                } else {
                    Label("\(post.exerciseCount) exercises", systemImage: "dumbbell.fill")
                    Label("\(post.totalSets) sets", systemImage: "list.bullet")
                }
            }
            .dsFont(.caption)
            .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding()
        .background(DS.Semantic.fillSubtle)
        .clipShape(ChamferedRectangle(.medium))
    }

    @ViewBuilder
    private func cardioPreviewStats(for workout: CompletedWorkout) -> some View {
        if let distanceMeters = workout.matchedHealthKitDistance, distanceMeters > 0 {
            Label(formatDistance(distanceMeters), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }

        if let durationSec = workout.matchedHealthKitDuration, durationSec > 0 {
            Label(formatCardioDuration(durationSec), systemImage: "clock.fill")
        } else if let duration = workout.estimatedDuration, duration > 0 {
            Label(formatCardioDuration(Int(duration)), systemImage: "clock.fill")
        }

        if let pace = cardioPace(for: workout) {
            Label("\(formatPace(pace))/km", systemImage: "speedometer")
        }
    }

    private func cardioPace(for workout: CompletedWorkout) -> Double? {
        guard let distanceMeters = workout.matchedHealthKitDistance,
              distanceMeters > 0 else { return nil }

        if let durationSec = workout.matchedHealthKitDuration, durationSec > 0 {
            return Double(durationSec) / (distanceMeters / 1000)
        }

        if let splitPace = workout.cardioSplits?.first?.paceSecPerKm, splitPace > 0 {
            return Double(splitPace)
        }

        return nil
    }

    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let minutes = Int(secPerKm) / 60
        let seconds = Int(secPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatCardioDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    // MARK: - Battle Invite Card

    @ViewBuilder
    private func battleInviteCard(battle: BattleWithParticipants, viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "flag.2.crossed.fill")
                    .dsFont(.title2)
                    .foregroundStyle(DS.Semantic.brand)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Battle Challenge!")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("\(viewModel.profile.displayName ?? viewModel.profile.username) challenged you")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()
            }

            // Battle Details
            VStack(alignment: .leading, spacing: 12) {
                detailRow(icon: "figure.strengthtraining.traditional", label: "Type", value: battle.battle.battleType.displayName)
                detailRow(icon: "calendar", label: "Duration", value: "\(battle.battle.duration) days")
                detailRow(icon: "clock", label: "Starts", value: battle.battle.startDate.formatted(date: .abbreviated, time: .omitted))
            }
            .padding()
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.medium))

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    Task {
                        await declineBattle(battle: battle.battle)
                    }
                } label: {
                    Text("Decline")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Semantic.fillSubtle)
                        .clipShape(ChamferedRectangle(.medium))
                }

                Button {
                    Task {
                        await acceptBattle(battle: battle.battle)
                    }
                } label: {
                    Text("Accept Challenge")
                        .dsFont(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Semantic.brand)
                        .clipShape(ChamferedRectangle(.medium))
                }
            }
        }
        .padding()
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.brand, lineWidth: 2)
        )
        .shadow(color: DS.Semantic.brand.opacity(0.2), radius: 8, y: 4)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.brand)
                .frame(width: 20)

            Text(label)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)

            Spacer()

            Text(value)
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }

    private func sendRunInvite() async {
        guard let currentUserId = deps.authService.currentUser?.id else { return }
        isInvitingToRun = true
        do {
            try await deps.virtualRunRepository.sendInvite(to: userId, from: currentUserId)
            Haptics.success()
            runInviteSent = true
        } catch {
            AppLogger.error("Failed to send run invite", error: error, category: AppLogger.social)
            Haptics.error()
        }
        isInvitingToRun = false
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

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DS.Palette.marone)
            .clipShape(ChamferedRectangle(.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(.headline)
            .foregroundStyle(DS.Semantic.textPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangle(.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Edit Profile View (Placeholder)

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps
    let profile: UserProfile
    let onProfileUpdated: (UserProfile) -> Void

    @State private var displayName: String
    @State private var bio: String
    @State private var isPrivate: Bool
    @State private var isSaving = false
    @State private var error: String?

    init(profile: UserProfile, onProfileUpdated: @escaping (UserProfile) -> Void) {
        self.profile = profile
        self.onProfileUpdated = onProfileUpdated
        _displayName = State(initialValue: profile.displayName ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _isPrivate = State(initialValue: profile.isPrivate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Information") {
                    TextField("Display Name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Private Profile", isOn: $isPrivate)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("When enabled, your profile won't appear in search results. People can only find you if they already know your username.")
                        .dsFont(.caption)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .dsFont(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        error = nil

        do {
            // Update profile in database
            try await deps.authService.updateProfile(
                displayName: displayName.isEmpty ? nil : displayName,
                bio: bio.isEmpty ? nil : bio,
                isPrivate: isPrivate
            )

            // Get updated profile from auth service
            if let updatedProfile = deps.authService.currentUser?.profile {
                onProfileUpdated(updatedProfile)
            }

            Haptics.success()
            dismiss()
        } catch {
            self.error = "Failed to save profile: \(error.localizedDescription)"
            isSaving = false
            Haptics.error()
        }
    }
}
