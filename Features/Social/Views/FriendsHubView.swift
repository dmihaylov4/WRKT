//
//  FriendsHubView.swift
//  WRKT
//
//  Redesigned friends hub with Instagram Stories-style friend activity
//

import SwiftUI
import Kingfisher

struct FriendsHubView: View {
    @Environment(\.dependencies) private var deps
    @State private var badgeManager = NotificationBadgeManager.shared
    @EnvironmentObject var authService: SupabaseAuthService
    @State private var viewModel: FriendsHubViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Friend Requests Banner (if pending)
                if badgeManager.friendRequestCount > 0 {
                    friendRequestsBanner
                }

                // Horizontal Stories Scroll
                if let vm = viewModel {
                    if !vm.activeFriends.isEmpty {
                        storiesSection(viewModel: vm)
                    }

                    // Recent Activity Section
                    if !vm.recentlyActiveFriends.isEmpty {
                        recentActivitySection(viewModel: vm)
                    }
                }

                // Quick Actions
                quickActionsSection

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
        }
        .background(DS.Semantic.surface)
        .refreshable {
            await viewModel?.refresh()
            await badgeManager.refreshBadges()
        }
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

    // MARK: - Friend Requests Banner

    private var friendRequestsBanner: some View {
        NavigationLink {
            FriendRequestsView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Semantic.brand.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "person.badge.plus.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Semantic.brand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Friend Requests")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("\(badgeManager.friendRequestCount) pending")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                Text("\(badgeManager.friendRequestCount)")
                    .font(.callout.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.Semantic.brand)
                    .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding()
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangleAlt(.large))
            .overlay(
                ChamferedRectangleAlt(.large)
                    .stroke(DS.Semantic.brand.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Stories Section

    private func storiesSection(viewModel: FriendsHubViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friends")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.activeFriends) { friend in
                        NavigationLink {
                            SocialProfileView(userId: friend.id)
                                .environment(\.dependencies, deps)
                        } label: {
                            FriendStoryAvatar(friend: friend)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Recent Activity Section

    private func recentActivitySection(viewModel: FriendsHubViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                Text("\(viewModel.recentlyActiveFriends.count) active")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(viewModel.recentlyActiveFriends.prefix(5)) { friend in
                    NavigationLink {
                        SocialProfileView(userId: friend.id)
                            .environment(\.dependencies, deps)
                    } label: {
                        ActivityRow(friend: friend)
                    }

                    if friend.id != viewModel.recentlyActiveFriends.prefix(5).last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(DS.Semantic.fillSubtle)
            .clipShape(ChamferedRectangleAlt(.large))
            .padding(.horizontal)
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                FriendsListView()
            } label: {
                quickActionRow(
                    icon: "person.2.fill",
                    title: "My Friends",
                    color: DS.Semantic.brand
                )
            }

            Divider()
                .padding(.leading, 56)

            NavigationLink {
                UserSearchView()
            } label: {
                quickActionRow(
                    icon: "magnifyingglass",
                    title: "Find Friends",
                    color: DS.Status.info
                )
            }

            if let currentUser = authService.currentUser {
                Divider()
                    .padding(.leading, 56)

                NavigationLink {
                    SocialProfileView(userId: currentUser.id)
                } label: {
                    quickActionRow(
                        icon: "person.circle.fill",
                        title: "My Profile",
                        color: DS.Status.success
                    )
                }
            }
        }
        .background(DS.Semantic.fillSubtle)
        .clipShape(ChamferedRectangleAlt(.large))
        .padding(.horizontal)
    }

    private func quickActionRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 32)

            Text(title)
                .font(.body)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding()
    }
}

// MARK: - Hexagon Shape (Hard-edge design)

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let centerX = rect.midX
        let centerY = rect.midY

        // Pointy-top hexagon (rotated 30 degrees from flat-top)
        let radius = min(width, height) / 2

        var path = Path()

        // Start from top point and go clockwise
        for i in 0..<6 {
            let angle = (Double(i) * 60.0 - 90.0) * .pi / 180.0
            let x = centerX + CGFloat(cos(angle)) * radius
            let y = centerY + CGFloat(sin(angle)) * radius

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Friend Story Avatar

struct FriendStoryAvatar: View {
    let friend: ActiveFriend

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                // Avatar with premium chamfered ring (logo style)
                avatarImage
                    .frame(width: 60, height: 60)
                    .clipShape(ChamferedRectangleAlt(.large))
                    .padding(6) // Space for the ring
                    .background(
                        ChamferedRectangleAlt(.large)
                            .stroke(ringColor, lineWidth: 2.5)
                            .padding(2)
                    )

                // Active indicator - small chamfered badge with glow
                if friend.isActive {
                    ChamferedRectangleAlt(.micro)
                        .fill(DS.Status.success)
                        .frame(width: 14, height: 14)
                        .overlay(
                            ChamferedRectangleAlt(.micro)
                                .stroke(DS.Semantic.surface, lineWidth: 2)
                        )
                        .shadow(color: DS.Status.success.opacity(0.5), radius: 4, x: 0, y: 0)
                        .offset(x: 2, y: 2)
                }
            }

            // Username
            Text(friend.profile.displayName ?? friend.profile.username)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .frame(width: 76)
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        KFImage(URL(string: friend.profile.avatarUrl ?? ""))
            .placeholder {
                ChamferedRectangleAlt(.large)
                    .fill(DS.Semantic.brandSoft)
                    .overlay(
                        Text(friend.profile.username.prefix(1).uppercased())
                            .font(.title2.bold())
                            .foregroundStyle(DS.Semantic.brand)
                    )
            }
            .fade(duration: 0.25)
            .resizable()
            .scaledToFill()
    }

    /// Ring color based on activity status
    private var ringColor: Color {
        if friend.isActive {
            return DS.Semantic.brand
        } else if friend.isRecentlyActive {
            return DS.Semantic.brand.opacity(0.4)
        } else {
            return DS.Semantic.border.opacity(0.5)
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let friend: ActiveFriend

    var body: some View {
        HStack(spacing: 12) {
            // Chamfered Avatar (logo style)
            KFImage(URL(string: friend.profile.avatarUrl ?? ""))
                .placeholder {
                    ChamferedRectangleAlt(.small)
                        .fill(DS.Semantic.brandSoft)
                        .overlay(
                            Text(friend.profile.username.prefix(1).uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(DS.Semantic.brand)
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(ChamferedRectangleAlt(.small))

            // Name and activity
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.profile.displayName ?? friend.profile.username)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)

                HStack(spacing: 4) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption2)
                        .foregroundStyle(DS.Status.success)

                    if let lastWorkout = friend.lastWorkoutText {
                        Text("Worked out \(lastWorkout)")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    } else {
                        Text("Recently active")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }

            Spacer()

            // Workout count badge
            if friend.recentWorkoutCount > 0 {
                Text("\(friend.recentWorkoutCount)")
                    .font(.caption.bold())
                    .foregroundStyle(DS.Semantic.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Semantic.brandSoft)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding()
    }
}
