//
//  ChallengeDetailView.swift
//  WRKT
//
//  Detailed view of a challenge with leaderboard and progress
//

import SwiftUI

struct ChallengeDetailView: View {
    let challenge: ChallengeWithProgress
    let viewModel: ChallengesViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header section
                    headerSection

                    // Progress section
                    if let progress = challenge.participation {
                        progressSection(progress: progress)
                    }

                    // Stats section
                    statsSection

                    // Leaderboard section
                    leaderboardSection

                    // Challenge details
                    detailsSection
                }
                .padding()
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle(challenge.challenge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DS.Semantic.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButton
                    .padding()
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Sections
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challengeTypeLabel)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(challenge.challenge.title)
                        .font(.title2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Spacer()

                // Difficulty badge
                if let difficulty = challenge.challenge.difficulty {
                    Text(difficulty.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(difficultyTextColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(difficultyColor)
                        .clipShape(Capsule())
                }
            }

            if let description = challenge.challenge.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            // Time remaining
            let daysRemaining = challenge.challenge.daysRemaining
            Label(
                daysRemaining > 0
                    ? "\(daysRemaining) \(daysRemaining == 1 ? "day" : "days") remaining"
                    : "Challenge ended",
                systemImage: "clock.fill"
            )
            .font(.subheadline)
            .foregroundStyle(daysRemaining > 0 ? DS.Semantic.brand : DS.Semantic.textSecondary)
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func progressSection(progress: ChallengeParticipant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Progress")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 16) {
                // Large progress circle or bar
                CircularProgressView(
                    progress: Double(challenge.userProgressPercentage),
                    total: 100,
                    lineWidth: 12
                )
                .frame(height: 180)

                // Progress text
                VStack(spacing: 4) {
                    Text(progressValueText(progress: progress))
                        .font(.title3.bold())
                        .foregroundStyle(DS.Semantic.brand)

                    Text(progressTargetText)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statsSection: some View {
        HStack(spacing: 12) {
            ChallengeStatCard(
                icon: "person.2.fill",
                value: "\(challenge.challenge.participantCount)",
                label: "Participants"
            )

            ChallengeStatCard(
                icon: "calendar.badge.clock",
                value: "\(challenge.challenge.duration)",
                label: "Days"
            )

            ChallengeStatCard(
                icon: "target",
                value: targetValueText,
                label: "Goal"
            )
        }
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            if challenge.topParticipants.isEmpty {
                Text("No participants yet")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(challenge.topParticipants.enumerated()), id: \.element.id) { index, participantProfile in
                        LeaderboardRow(
                            rank: index + 1,
                            userId: participantProfile.participant.userId.uuidString,
                            progress: participantProfile.participant.currentProgress,
                            target: challenge.challenge.goalValue,
                            challengeType: challenge.challenge.challengeType
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                DetailRow(
                    label: "Challenge Type",
                    value: challengeTypeLabel
                )

                if let difficulty = challenge.challenge.difficulty {
                    DetailRow(
                        label: "Difficulty",
                        value: difficulty.displayName
                    )
                }

                DetailRow(
                    label: "Duration",
                    value: "\(challenge.challenge.duration) days"
                )

                DetailRow(
                    label: "Target",
                    value: targetValueText
                )

                DetailRow(
                    label: "Start Date",
                    value: challenge.challenge.startDate.formatted(date: .abbreviated, time: .omitted)
                )

                DetailRow(
                    label: "End Date",
                    value: challenge.challenge.endDate.formatted(date: .abbreviated, time: .omitted)
                )

                if challenge.challenge.isPublic {
                    DetailRow(
                        label: "Visibility",
                        value: "Public"
                    )
                }
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        if challenge.isParticipating {
            Button {
                Task {
                    await viewModel.leaveChallenge(challenge.challenge)
                    dismiss()
                }
            } label: {
                Text("Leave Challenge")
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Semantic.surface50)
                    .clipShape(Capsule())
            }
        } else {
            Button {
                Task {
                    await viewModel.joinChallenge(challenge.challenge)
                    dismiss()
                }
            } label: {
                Text("Join Challenge")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Semantic.brand)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers
    private var challengeTypeLabel: String {
        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "Workout Count"
        case .totalVolume:
            return "Total Volume"
        case .streak:
            return "Streak"
        case .specificExercise:
            return "Exercise Challenge"
        case .custom:
            return "Custom Challenge"
        }
    }

    private var difficultyColor: Color {
        guard let difficulty = challenge.challenge.difficulty else {
            return DS.Semantic.textSecondary
        }

        switch difficulty {
        case .beginner:
            return DS.Semantic.fillSubtle
        case .intermediate:
            return DS.Semantic.surface50
        case .advanced:
            return DS.Semantic.textSecondary.opacity(0.2)
        }
    }

    private var difficultyTextColor: Color {
        guard let difficulty = challenge.challenge.difficulty else {
            return DS.Semantic.textSecondary
        }

        switch difficulty {
        case .beginner:
            return DS.Semantic.textSecondary
        case .intermediate:
            return DS.Semantic.textPrimary
        case .advanced:
            return DS.Semantic.textPrimary
        }
    }

    private var targetValueText: String {
        let goalValue = NSDecimalNumber(decimal: challenge.challenge.goalValue).intValue

        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "\(goalValue)"
        case .totalVolume:
            return "\(goalValue / 1000)K kg"
        case .streak:
            return "\(goalValue) days"
        case .specificExercise:
            return "\(goalValue)"
        case .custom:
            return "\(goalValue) \(challenge.challenge.goalMetric)"
        }
    }

    private func progressValueText(progress: ChallengeParticipant) -> String {
        let currentValue = NSDecimalNumber(decimal: progress.currentProgress).intValue
        let goalValue = NSDecimalNumber(decimal: challenge.challenge.goalValue).intValue

        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "\(currentValue)/\(goalValue)"
        case .totalVolume:
            return "\(currentValue / 1000)K/\(goalValue / 1000)K kg"
        case .streak:
            return "\(currentValue)/\(goalValue)"
        case .specificExercise:
            return "\(currentValue)/\(goalValue)"
        case .custom:
            return "\(currentValue)/\(goalValue) \(challenge.challenge.goalMetric)"
        }
    }

    private var progressTargetText: String {
        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "workouts completed"
        case .totalVolume:
            return "kilograms lifted"
        case .streak:
            return "consecutive days"
        case .specificExercise:
            return "reps completed"
        case .custom:
            return challenge.challenge.goalMetric
        }
    }
}

// MARK: - Supporting Components
struct CircularProgressView: View {
    let progress: Double
    let total: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(DS.Semantic.fillSubtle, lineWidth: lineWidth)

            // Progress circle
            Circle()
                .trim(from: 0, to: min(progress / total, 1.0))
                .stroke(
                    DS.Semantic.brand,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)

            // Percentage text
            VStack(spacing: 4) {
                Text("\(Int(progress))%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Complete")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
    }
}

struct ChallengeStatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DS.Semantic.brand)

            Text(value)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let userId: String
    let progress: Decimal
    let target: Decimal
    let challengeType: ChallengeType

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("\(rank)")
                .font(.headline.bold())
                .foregroundStyle(rankColor)
                .frame(width: 32, height: 32)
                .background(rankColor.opacity(0.15))
                .clipShape(Circle())

            // User info (simplified - would need user lookup)
            VStack(alignment: .leading, spacing: 2) {
                Text("User \(userId.prefix(8))")
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            // Progress percentage
            let percentage = (NSDecimalNumber(decimal: progress).doubleValue / NSDecimalNumber(decimal: target).doubleValue) * 100
            Text("\(Int(percentage))%")
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.brand)
        }
        .padding(12)
        .background(rank <= 3 ? DS.Semantic.brandSoft : DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rankColor: Color {
        switch rank {
        case 1:
            return Color(hex: "#FFD700") // Gold
        case 2:
            return Color(hex: "#C0C0C0") // Silver
        case 3:
            return Color(hex: "#CD7F32") // Bronze
        default:
            return DS.Semantic.textSecondary
        }
    }

    private var progressText: String {
        let progressValue = NSDecimalNumber(decimal: progress).intValue
        let targetValue = NSDecimalNumber(decimal: target).intValue

        switch challengeType {
        case .workoutCount:
            return "\(progressValue)/\(targetValue) workouts"
        case .totalVolume:
            return "\(progressValue / 1000)K/\(targetValue / 1000)K kg"
        case .streak:
            return "\(progressValue)/\(targetValue) days"
        case .specificExercise:
            return "\(progressValue)/\(targetValue) reps"
        case .custom:
            return "\(progressValue)/\(targetValue)"
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }
}
