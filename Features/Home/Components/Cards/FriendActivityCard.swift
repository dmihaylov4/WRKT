//
//  FriendActivityCard.swift
//  WRKT
//
//  Shows recent friend workout activity (last 3 days)
//

import SwiftUI
import Kingfisher

struct FriendActivityCard: View {
    let summary: FriendActivitySummary

    /// One entry per friend, keeping the most recent activity
    private var dedupedActivities: [FriendActivitySummary.FriendWorkoutActivity] {
        var seen = Set<UUID>()
        return summary.activities.filter { activity in
            seen.insert(activity.friendId).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Friend Activity")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if !dedupedActivities.isEmpty {
                    Text("\(dedupedActivities.count) recent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Title
            if summary.userWorkedOutToday {
                Text("You're all crushing it!")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 2)
            } else if summary.activities.isEmpty {
                Text("Be the first to work out!")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 2)
            } else {
                Text("Your friends are working out")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 2)
            }

            // Friend activities (1 per person, max 2 shown)
            if !dedupedActivities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(dedupedActivities.prefix(2))) { activity in
                        FriendActivityRow(activity: activity)
                    }

                    if dedupedActivities.count > 2 {
                        Text("+ \(dedupedActivities.count - 2) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Friend Activity Row

private struct FriendActivityRow: View {
    let activity: FriendActivitySummary.FriendWorkoutActivity

    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            KFImage(URL(string: activity.friendAvatarUrl ?? ""))
                .placeholder {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            Text(String(activity.friendName.prefix(1)).uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(Color(.systemGray))
                        )
                }
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(activity.friendName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(activity.timeAgoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text(activity.workoutName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let duration = activity.durationText {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(duration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("With Activities") {
    VStack {
        FriendActivityCard(
            summary: FriendActivitySummary(
                activities: [
                    FriendActivitySummary.FriendWorkoutActivity(
                        id: UUID(),
                        friendId: UUID(),
                        friendName: "John",
                        friendUsername: "john_doe",
                        friendAvatarUrl: nil,
                        workoutName: "Leg Day",
                        duration: 45,
                        completedAt: Date().addingTimeInterval(-7200) // 2h ago
                    ),
                    FriendActivitySummary.FriendWorkoutActivity(
                        id: UUID(),
                        friendId: UUID(),
                        friendName: "Sarah",
                        friendUsername: "sarah_m",
                        friendAvatarUrl: nil,
                        workoutName: "Upper Body",
                        duration: 60,
                        completedAt: Date().addingTimeInterval(-14400) // 4h ago
                    ),
                    FriendActivitySummary.FriendWorkoutActivity(
                        id: UUID(),
                        friendId: UUID(),
                        friendName: "Mike",
                        friendUsername: "mike_fit",
                        friendAvatarUrl: nil,
                        workoutName: "Full Body",
                        duration: 30,
                        completedAt: Date().addingTimeInterval(-3600) // 1h ago
                    )
                ],
                userWorkedOutToday: false
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Empty State") {
    VStack {
        FriendActivityCard(
            summary: FriendActivitySummary(
                activities: [],
                userWorkedOutToday: false
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("User Completed") {
    VStack {
        FriendActivityCard(
            summary: FriendActivitySummary(
                activities: [
                    FriendActivitySummary.FriendWorkoutActivity(
                        id: UUID(),
                        friendId: UUID(),
                        friendName: "John",
                        friendUsername: "john_doe",
                        friendAvatarUrl: nil,
                        workoutName: "Leg Day",
                        duration: 45,
                        completedAt: Date().addingTimeInterval(-7200) // 2h ago
                    )
                ],
                userWorkedOutToday: true
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
