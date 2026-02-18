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

    // Badge manager for notifications
    @State private var badgeManager = NotificationBadgeManager.shared

    // Virtual run invite
    @State private var isInvitingToRun = false
    @State private var runInviteSent = false

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
                            .font(.headline)
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

            // NOTE: Don't validate streak here - validation should only happen on app cold start
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
            loadError = "Failed to load profile: \(lastError?.localizedDescription ?? "Unknown error")"
        }
    }

    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("Profile Not Found")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(error)
                .font(.subheadline)
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
            VStack(spacing: 24) {
                // Profile Header
                profileHeader(viewModel: viewModel)

                // Battle Invite Card (if present)
                if let battle = battle, battle.battle.status == .pending {
                    battleInviteCard(battle: battle, viewModel: viewModel)
                }

                // Stats Row
                statsRow(viewModel: viewModel)

                // Activity Link (for own profile)
                if viewModel.isOwnProfile {
                    activityLink
                }

                // Action Buttons
                actionButtons(viewModel: viewModel)

                Divider()

                // Posts Section
                postsSection(viewModel: viewModel)
            }
            .padding()
        }
        .refreshable {
            async let posts: () = viewModel.loadUserPosts()
            async let friends: () = viewModel.loadFriendCount()
            _ = await (posts, friends)
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
        VStack(spacing: 16) {
            // Profile Picture (Chamfered logo style)
            ZStack(alignment: .bottomTrailing) {
                KFImage(URL(string: viewModel.profile.avatarUrl ?? ""))
                    .placeholder {
                        ChamferedRectangleAlt(.hero)
                            .fill(DS.Semantic.brandSoft)
                            .overlay(
                                Text(viewModel.profile.username.prefix(1).uppercased())
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(DS.Semantic.brand)
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(ChamferedRectangleAlt(.hero))
                    .overlay(
                        ChamferedRectangleAlt(.hero)
                            .stroke(DS.Semantic.brand, lineWidth: 2.5)
                    )
                    .id(viewModel.profile.avatarUrl ?? "")

                // Edit button for own profile (hexagonal)
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
                            Hexagon()
                                .fill(DS.Semantic.brand)
                                .frame(width: 32, height: 32)

                            if viewModel.isUploadingAvatar {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                    .disabled(viewModel.isUploadingAvatar)
                }
            }

            // Username & Display Name
            VStack(spacing: 4) {
                if let displayName = viewModel.profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.title2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("@\(viewModel.profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                } else {
                    Text("@\(viewModel.profile.username)")
                        .font(.title2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }

            // Bio
            if let bio = viewModel.profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func statsRow(viewModel: ProfileViewModel) -> some View {
        HStack(spacing: 32) {
            statItem(value: "\(viewModel.posts.count)", label: "Workouts")
            statItem(value: "\(viewModel.friendCount)", label: "Friends")
            // Only show streak for own profile - other users' streaks are not available
            if viewModel.isOwnProfile {
                statItem(value: "\(progress.first?.weeklyGoalStreakCurrent ?? 0)", label: "Streak")
            }
        }
        .padding()
        .background(DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
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
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DS.Semantic.brand)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding()
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func actionButtons(viewModel: ProfileViewModel) -> some View {
        Group {
            if viewModel.isOwnProfile {
                Button {
                    showingEditProfile = true
                } label: {
                    Text("Edit Profile")
                        .font(.headline)
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

        case .friends:
            Menu {
                Button {
                    Task { await sendRunInvite() }
                } label: {
                    Label("Invite to Run", systemImage: "figure.run")
                }
                .disabled(isInvitingToRun)

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
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

        case .pendingSent:
            Button {
                Task {
                    await viewModel.cancelFriendRequest()
                }
            } label: {
                Text("Cancel Request")
            }
            .buttonStyle(SecondaryButtonStyle())

        case .pendingReceived:
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
        }
    }

    private func postsSection(viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workouts")
                .font(.headline)
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
                        .font(.subheadline)
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
        VStack(alignment: .leading, spacing: 12) {
            if let caption = post.caption {
                Text(caption)
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .lineLimit(2)
            }

            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(DS.Semantic.brand)
                Text(post.workoutData.workoutName ?? "Workout")
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                Text(post.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            HStack(spacing: 16) {
                Label("\(post.exerciseCount) exercises", systemImage: "dumbbell.fill")
                Label("\(post.totalSets) sets", systemImage: "list.bullet")
            }
            .font(.caption)
            .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding()
        .background(DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Battle Invite Card

    @ViewBuilder
    private func battleInviteCard(battle: BattleWithParticipants, viewModel: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.title2)
                    .foregroundStyle(DS.Semantic.brand)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Battle Challenge!")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("\(viewModel.profile.displayName ?? viewModel.profile.username) challenged you")
                        .font(.subheadline)
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
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    Task {
                        await declineBattle(battle: battle.battle)
                    }
                } label: {
                    Text("Decline")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Semantic.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    Task {
                        await acceptBattle(battle: battle.battle)
                    }
                } label: {
                    Text("Accept Challenge")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Semantic.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.brand, lineWidth: 2)
        )
        .shadow(color: DS.Semantic.brand.opacity(0.2), radius: 8, y: 4)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DS.Semantic.brand)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline.bold())
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
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DS.Palette.marone)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DS.Semantic.textPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .font(.caption)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
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
