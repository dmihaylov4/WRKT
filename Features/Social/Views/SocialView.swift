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
                            FeedView()
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
        }
        .onChange(of: selectedSection) { _, _ in
            // Clear navigation path when switching tabs to prevent accumulation
            navigationPath = NavigationPath()
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
    }

    private func handleNotificationNavigation(_ notification: AppNotification) {
        AppLogger.info("🧭 SocialView handling notification: type=\(notification.type.rawValue), actorId=\(notification.actorId), targetId=\(notification.targetId?.uuidString ?? "nil")", category: AppLogger.app)

        switch notification.type {
        // Battle notifications - navigate to inviter/opponent profile with battle context
        case .battleInvite:
            // Navigate to profile with battle context
            let destination = ProfileDestination(
                userId: notification.actorId,
                battleId: notification.targetId
            )
            navigationPath.append(destination)

        case .battleAccepted, .battleDeclined, .battleLeadTaken, .battleLeadLost,
             .battleOpponentActivity, .battleEndingSoon, .battleCompleted, .battleVictory, .battleDefeat:
            // Navigate to profile without battle card (battle is active/completed)
            navigationPath.append(notification.actorId)

        // Challenge notifications - navigate to challenge detail (TODO: implement challenge detail)
        case .challengeInvite, .challengeJoined, .challengeMilestone, .challengeLeaderboardChange,
             .challengeEndingSoon, .challengeCompleted, .challengeNewParticipant:
            // For now, just navigate to activity feed
            selectedSection = .feed

        // Social notifications - navigate to actor profile or post
        case .friendRequest, .friendAccepted:
            navigationPath.append(notification.actorId)

        case .postLike, .postComment, .commentReply, .commentMention:
            // Navigate to the specific post
            if let postId = notification.targetId {
                navigationPath.append(PostDestination(postId: postId))
            } else {
                // Fallback to feed if no targetId
                selectedSection = .feed
            }

        case .virtualRunInvite:
            // Navigate to the inviter's profile
            navigationPath.append(notification.actorId)

        case .workoutCompleted:
            // Navigate to the workout post or actor's profile
            if let postId = notification.targetId {
                navigationPath.append(PostDestination(postId: postId))
            } else {
                navigationPath.append(notification.actorId)
            }
        }
    }

    // MARK: - Profile Header

    @ViewBuilder
    private var profileHeader: some View {
        HStack {
            // Profile button
            if let currentUser = deps.authService.currentUser {
                Button {
                    navigationPath.append(currentUser.id)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        // Profile Picture with chamfered logo shape
                        KFImage(URL(string: currentUser.profile?.avatarUrl ?? ""))
                            .placeholder {
                                ChamferedRectangleAlt(.small)
                                    .fill(DS.Semantic.brandSoft)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(DS.Semantic.brand)
                                    )
                            }
                            .fade(duration: 0.25)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(ChamferedRectangleAlt(.small))
                            .overlay(
                                ChamferedRectangleAlt(.small)
                                    .stroke(DS.Semantic.brand, lineWidth: 2)
                            )

                        // Notification badge
                        if badgeManager.notificationCount > 0 {
                            ChamferedRectangleAlt(.micro)
                                .fill(DS.Palette.marone)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    ChamferedRectangleAlt(.micro)
                                        .stroke(Color.black, lineWidth: 2)
                                )
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Placeholder for alignment
                Color.clear.frame(width: 40, height: 40)
            }

            Spacer()

            // Title based on selected section
            Text(selectedSection.rawValue)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            // Right side spacer for centering
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Section Picker

    @ViewBuilder
    private var sectionPicker: some View {
        // Premium segmented control with frosted glass effect
        HStack(spacing: 0) {
            PillSegmentButton(
                title: "Feed",
                icon: "newspaper.fill",
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
                icon: "flame.fill",
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
                icon: "person.2.fill",
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
            ChamferedRectangleAlt(.large)
                .fill(DS.Semantic.card.opacity(0.5))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            ChamferedRectangleAlt(.large)
                .stroke(DS.Semantic.border.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Premium Pill Segment Button

struct PillSegmentButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Icon
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .black : DS.Semantic.textSecondary)
                        .symbolEffect(.bounce, value: isSelected)

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
                        ChamferedRectangleAlt(.small)
                            .fill(DS.Semantic.brand)
                            .shadow(color: DS.Semantic.brand.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compete Tab Content (without NavigationStack wrapper)

struct CompeteTabContent: View {
    @State private var selectedSection: CompeteSection = .overview

    enum CompeteSection {
        case overview, challenges, battles
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            competeSectionPicker

            // Content
            Group {
                switch selectedSection {
                case .overview:
                    OverviewSection()
                case .challenges:
                    ChallengesBrowseView()
                case .battles:
                    BattlesListView()
                }
            }
        }
    }

    @ViewBuilder
    private var competeSectionPicker: some View {
        // Compact pill control for compete sections
        HStack(spacing: 4) {
            CompactPillButton(
                title: "Overview",
                isSelected: selectedSection == .overview,
                action: { withAnimation { selectedSection = .overview } }
            )

            CompactPillButton(
                title: "Challenges",
                isSelected: selectedSection == .challenges,
                action: { withAnimation { selectedSection = .challenges } }
            )

            CompactPillButton(
                title: "Battles",
                isSelected: selectedSection == .battles,
                action: { withAnimation { selectedSection = .battles } }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.Semantic.surface)
    }
}

// MARK: - Compact Pill Button (for nested sections)

struct CompactPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? DS.Semantic.textPrimary : DS.Semantic.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? DS.Semantic.brandSoft : DS.Semantic.surface50,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
