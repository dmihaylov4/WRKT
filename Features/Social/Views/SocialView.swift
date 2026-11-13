//
//  SocialView.swift
//  WRKT
//
//  Main social hub combining Feed, Compete, and Friends
//

import SwiftUI
import Kingfisher

private let USE_MOCK_VIEWS_FOR_SCREENSHOTS = false


// Navigation destination for profile with optional context
struct ProfileDestination: Hashable {
    let userId: UUID
    let battleId: UUID?

    init(userId: UUID, battleId: UUID? = nil) {
        self.userId = userId
        self.battleId = battleId
    }
}

// Navigation destination for post detail
struct PostDestination: Hashable {
    let postId: UUID
}

struct BattleDestination: Hashable {
    let battleId: UUID
}

struct ChallengeDestination: Hashable {
    let challengeId: UUID
}

struct SocialView: View {
    @Environment(\.dependencies) private var deps
    @Binding var pendingNotification: AppNotification?

    @State private var selectedSection: SocialSection = .feed
    @State private var badgeManager = NotificationBadgeManager.shared
    @State private var navigationPath = NavigationPath()

    enum SocialSection: String {
        case feed = "Feed"
        case compete = "Compete"
        case friends = "Friends"
    }

    init(pendingNotification: Binding<AppNotification?> = .constant(nil)) {
        self._pendingNotification = pendingNotification
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // The one Cut branch point: same path, destinations, badges and notification routing.
            Group {
            if DS.Redesign.cutEnabled {
                CutSocialHost(section: $selectedSection, path: $navigationPath)
            } else {
            VStack(spacing: 0) {
                // Profile header above tabs
                profileHeader

                /// Section picker
                sectionPicker

                // Content
                Group {


                        // NORMAL MODE: Use real views with live data
                        switch selectedSection {
                        case .feed:
                            FeedView(
                                onNavigateToProfile: { userId in
                                    navigationPath.append(userId)
                                },
                                onNavigateToPost: { postId in
                                    navigationPath.append(PostDestination(postId: postId))
                                },
                                onNavigateToBattle: { battleId in
                                    navigationPath.append(BattleDestination(battleId: battleId))
                                },
                                onNavigateToChallenge: { challengeId in
                                    navigationPath.append(ChallengeDestination(challengeId: challengeId))
                                }
                            )
                                .id("feed-view-stable") // Stable ID to prevent recreation
                            //TestNotificationButton()
                        case .compete:
                            UnifiedCompeteView()
                                .id("compete-view-stable")
                        case .friends:
                            FriendsHubView()
                                .id("friends-view-stable")
                        }
                    }

            }
            }
            }
            .ignoresSafeArea(.keyboard)
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { userId in
                SocialProfileView(userId: userId, battleId: nil)
                    .environment(\.dependencies, deps)
            }
            .navigationDestination(for: ProfileDestination.self) { destination in
                SocialProfileView(userId: destination.userId, battleId: destination.battleId)
                    .environment(\.dependencies, deps)
            }
            .navigationDestination(for: PostDestination.self) { destination in
                PostLoaderView(postId: destination.postId)
                    .environment(\.dependencies, deps)
            }
            .navigationDestination(for: BattleDestination.self) { destination in
                BattleLoaderView(battleId: destination.battleId)
                    .environment(\.dependencies, deps)
            }
            .navigationDestination(for: ChallengeDestination.self) { destination in
                ChallengeLoaderView(challengeId: destination.challengeId)
                    .environment(\.dependencies, deps)
            }
        }
        .onChange(of: selectedSection) { _, _ in
            // Clear navigation path when switching tabs to prevent accumulation
            navigationPath = NavigationPath()
        }
        .onChange(of: navigationPath) { old, new in
            // Dismiss keyboard the moment a pop begins — before the transition animates.
            // onDisappear fires too late and leaves the keyboard safe-area inset on FeedView.
            if new.count < old.count {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
        .task {
            AppLogger.info("📱 SocialView .task started", category: AppLogger.app)

            // Refresh badges when social tab is opened
            await badgeManager.refreshBadges()

            // Also ensure real-time subscriptions are active
            // This helps recover from any connection issues
            AppLogger.info("🚀 Calling badgeManager.startRealtimeSubscriptions() from SocialView.task", category: AppLogger.app)
            await badgeManager.startRealtimeSubscriptions()
        }
        .onChange(of: pendingNotification) { oldValue, newValue in
            guard let notification = newValue else { return }
            handleNotificationNavigation(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialTabReselected)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSection = .feed
            }
            navigationPath = NavigationPath()
        }
    }

    private func handleNotificationNavigation(_ notification: AppNotification) {
        guard notification.type.isVisible else { return }
        AppLogger.info("🧭 SocialView handling notification: type=\(notification.type.rawValue), actorId=\(notification.actorId), targetId=\(notification.targetId?.uuidString ?? "nil")", category: AppLogger.app)

        switch notification.type {
        // Battle notifications - navigate to the battle detail when possible.
        case .battleInvite:
            if let battleId = notification.targetId {
                navigationPath.append(BattleDestination(battleId: battleId))
            } else {
                navigationPath.append(notification.actorId)
            }

        case .battleAccepted, .battleDeclined, .battleLeadTaken, .battleLeadLost,
             .battleOpponentActivity, .battleEndingSoon, .battleCompleted, .battleVictory, .battleDefeat:
            if let battleId = notification.targetId {
                navigationPath.append(BattleDestination(battleId: battleId))
            } else {
                navigationPath.append(notification.actorId)
            }

        // Challenge notifications - navigate to challenge detail (TODO: implement challenge detail)
        case .challengeInvite, .challengeJoined, .challengeMilestone, .challengeLeaderboardChange,
             .challengeEndingSoon, .challengeCompleted, .challengeNewParticipant:
            // For now, just navigate to activity feed
            selectedSection = .feed

        // Social notifications - navigate to actor profile or post
        case .friendRequest, .friendAccepted:
            navigationPath.append(notification.actorId)

        case .postLike, .postComment, .commentReply, .commentMention, .postParticipantTag:
            // Navigate to the specific post
            if let postId = notification.targetId {
                navigationPath.append(PostDestination(postId: postId))
            } else {
                // Fallback to feed if no targetId
                selectedSection = .feed
            }

        case .virtualRunInvite, .unknown:
            return

        case .workoutCompleted:
            // Navigate to the workout post or actor's profile
            if let postId = notification.targetId {
                navigationPath.append(PostDestination(postId: postId))
            } else {
                navigationPath.append(notification.actorId)
            }

        case .programInvite:
            break
        }
    }

    // MARK: - Profile Header

    @ViewBuilder
    private var profileHeader: some View {
        HStack {
            if let currentUser = deps.authService.currentUser {
                profileToolbarButton(currentUser: currentUser)
            } else {
                toolbarPlaceholder
            }

            Spacer()

            Text(selectedSection.rawValue)
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            activityToolbarButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var toolbarPlaceholder: some View {
        Color.clear
            .frame(width: 48, height: 48)
    }

    private func profileToolbarButton(currentUser: AuthUser) -> some View {
        Button {
            navigationPath.append(currentUser.id)
        } label: {
            ZStack {
                ChamferedRectangleAlt(.small)
                    .fill(DS.Semantic.card.opacity(0.78))
                    .frame(width: 48, height: 48)
                    .overlay(
                        ChamferedRectangleAlt(.small)
                            .stroke(DS.Semantic.brand.opacity(0.88), lineWidth: 2)
                    )

                KFImage(URL(string: currentUser.profile?.avatarUrl ?? ""))
                    .placeholder {
                        ChamferedRectangleAlt(.micro)
                            .fill(DS.Semantic.brandSoft)
                            .overlay(
                                Image("tab-profile")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(DS.Semantic.brand)
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(ChamferedRectangleAlt(.micro))
            }
            .contentShape(ChamferedRectangleAlt(.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile")
    }

    private var activityToolbarButton: some View {
        NavigationLink {
            ActivityFeedView()
                .environment(\.dependencies, deps)
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    DS.RoleShape(.control, legacy: ChamferedRectangle(.small))
                        .fill(DS.Semantic.card.opacity(0.78))
                        .frame(width: 48, height: 48)
                        .overlay(
                            DS.RoleShape(.control, legacy: ChamferedRectangle(.small))
                                .stroke(DS.Semantic.border.opacity(0.75), lineWidth: 1)
                        )

                    Image("social-activity-icon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(DS.Semantic.brand)
                }

                if badgeManager.notificationCount > 0 {
                    Text("\(min(badgeManager.notificationCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, badgeManager.notificationCount > 9 ? 3 : 0)
                        .background(DS.Semantic.brand)
                        .clipShape(DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.micro)))
                        .overlay(
                            DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.micro))
                                .stroke(DS.Semantic.surface, lineWidth: 2)
                        )
                        .offset(x: 5, y: -5)
                }
            }
            .contentShape(ChamferedRectangle(.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open activity")
    }

    // MARK: - Section Picker

    @ViewBuilder
    private var sectionPicker: some View {
        // Premium segmented control with frosted glass effect
        HStack(spacing: 0) {
            PillSegmentButton(
                title: "Feed",
                iconAsset: "social-feed-icon",
                isSelected: selectedSection == .feed,
                badge: nil
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedSection = .feed
                    Haptics.light()
                }
            }

            PillSegmentButton(
                title: "Compete",
                iconAsset: "streak-icon",
                isSelected: selectedSection == .compete,
                badge: nil
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedSection = .compete
                    Haptics.light()
                }
            }

            PillSegmentButton(
                title: "Friends",
                iconAsset: "social-friends-icon",
                isSelected: selectedSection == .friends,
                badge: badgeManager.friendRequestCount > 0 ? badgeManager.friendRequestCount : nil
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedSection = .friends
                    Haptics.light()
                }
            }
        }
        .padding(4)
        .background(
            DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.large))
                .fill(DS.Semantic.card.opacity(0.5))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.large))
                .stroke(DS.Semantic.border.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Premium Pill Segment Button

struct PillSegmentButton: View {
    let title: String
    let iconAsset: String
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Icon
                ZStack {
                    Image(iconAsset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundStyle(isSelected ? .black : DS.Semantic.textSecondary)

                    // Badge indicator (top-right corner)
                    if let count = badge {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Semantic.accentWarm)
                            .clipShape(Circle())
                            .offset(x: 12, y: -10)
                    }
                }

                // Label
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .black : DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                Group {
                    if isSelected {
                        DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.small))
                            .fill(DS.Semantic.brand)
                            .shadow(color: DS.Semantic.brand.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
