import SwiftUI

struct ChallengeDetailView: View {
    let challenge: ChallengeWithProgress
    let viewModel: ChallengesViewModel

    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var showingLeaveConfirmation = false

    private var displayedChallenge: ChallengeWithProgress {
        guard challenge.shouldCompleteFirstRep(from: deps.workoutStore.completedWorkouts) else { return challenge }
        return challenge.completedFirstRepFromWorkoutHistory()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    if ChallengeRewardPreviewKind(challenge: displayedChallenge.challenge) != .none {
                        ChallengeRewardPreviewBlock(challenge: displayedChallenge.challenge)
                    }
                    if let progress = displayedChallenge.participation {
                        progressSection(progress: progress)
                    }
                    statsRow
                    if !displayedChallenge.topParticipants.isEmpty {
                        leaderboardSection
                    }
                }
                .padding()
                .padding(.bottom, 80)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle(displayedChallenge.challenge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Semantic.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButton
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog(
            "Leave Challenge?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Challenge", role: .destructive) {
                Task { await performLeaveChallenge() }
            }
            Button("Keep Challenge", role: .cancel) {}
        } message: {
            Text("Your challenge progress will stop updating.")
        }
        .alert(item: Binding(
            get: { viewModel.error },
            set: { _ in viewModel.error = nil }
        )) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challengeTypeLabel)
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(displayedChallenge.challenge.title)
                        .dsFont(.title2, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Spacer()

                if let difficulty = displayedChallenge.challenge.difficulty {
                    Text(difficulty.displayName)
                        .dsFont(.caption2, weight: .bold)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DS.Semantic.fillSubtle, in: ChamferedRectangle(.small))
                        .overlay(
                            ChamferedRectangle(.small)
                                .stroke(DS.Semantic.border, lineWidth: 1)
                        )
                }
            }

            if let description = displayedChallenge.challenge.description {
                Text(description)
                    .dsFont(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .dsFont(.caption)
                Text(displayedChallenge.challenge.isEvergreen ? "Ongoing" : (displayedChallenge.challenge.daysRemaining > 0 ? "\(displayedChallenge.challenge.daysRemaining) days remaining" : "Challenge ended"))
                    .dsFont(.subheadline, weight: .medium)
            }
            .foregroundStyle(displayedChallenge.challenge.daysRemaining > 0 || displayedChallenge.challenge.isEvergreen ? DS.Semantic.brand : DS.Semantic.textSecondary)
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressSection(progress: ChallengeParticipant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Progress")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 8) {
                HStack {
                    Text(progressValueText(progress: progress))
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.brand)

                    Spacer()

                    Text("\(displayedChallenge.userProgressPercentage)%")
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                ProgressView(
                    value: Double(displayedChallenge.userProgressPercentage),
                    total: 100
                )
                .tint(DS.Semantic.brand)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: displayedChallenge.userProgressPercentage)

                Text(progressTargetText)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    // MARK: - Stats row (CLAUDE.md convention)

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(
                value: "\(displayedChallenge.challenge.participantCount)",
                label: "Participants"
            )

            Rectangle()
                .fill(DS.Semantic.border)
                .frame(width: 1)

            statColumn(
                value: "\(displayedChallenge.challenge.duration)d",
                label: "Duration"
            )

            Rectangle()
                .fill(DS.Semantic.border)
                .frame(width: 1)

            statColumn(
                value: targetValueText,
                label: "Goal"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .dsFont(.headline, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Leaderboard

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 8) {
                ForEach(Array(displayedChallenge.topParticipants.enumerated()), id: \.element.id) { index, participantProfile in
                    leaderboardRow(
                        rank: index + 1,
                        username: participantProfile.profile.username,
                        progress: participantProfile.participant.currentProgress,
                        target: displayedChallenge.challenge.goalValue
                    )
                }
            }
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    private func leaderboardRow(rank: Int, username: String, progress: Decimal, target: Decimal) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .dsFont(.subheadline, weight: .black)
                .foregroundStyle(rankColor(rank))
                .frame(width: 28, height: 28)
                .background(rankColor(rank).opacity(0.14), in: ChamferedRectangle(.micro))

            VStack(alignment: .leading, spacing: 2) {
                Text(username)
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .lineLimit(1)

                Text(rowProgressText(progress: progress, target: target))
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            let pct = Int((NSDecimalNumber(decimal: progress).doubleValue / max(NSDecimalNumber(decimal: target).doubleValue, 1)) * 100)
            Text("\(min(pct, 100))%")
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(rank == 1 ? DS.Semantic.brand : DS.Semantic.textSecondary)
        }
        .padding(12)
        .background(rank <= 3 ? DS.Semantic.brandSoft : DS.Semantic.fillSubtle, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(rank <= 3 ? DS.Semantic.brand.opacity(0.2) : DS.Semantic.border, lineWidth: 1)
        )
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if challenge.isParticipating {
            Button {
                showingLeaveConfirmation = true
            } label: {
                Group {
                    if isProcessing {
                        ProgressView()
                            .tint(DS.Status.error)
                    } else {
                        Text("Leave Challenge")
                            .dsFont(.headline)
                            .foregroundStyle(DS.Status.error)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(DS.Status.error.opacity(0.1), in: ChamferedRectangle(.large))
                .overlay(
                    ChamferedRectangle(.large)
                        .stroke(DS.Status.error.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        } else {
            Button {
                guard !isProcessing else { return }
                isProcessing = true
                Task {
                    await viewModel.joinChallenge(challenge.challenge)
                    dismiss()
                }
            } label: {
                Group {
                    if isProcessing {
                        ProgressView().tint(.black)
                    } else {
                        Text("Join Challenge")
                            .dsFont(.headline)
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(DS.Semantic.brand, in: ChamferedRectangle(.large))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }

    // MARK: - Helpers

    private var challengeTypeLabel: String {
        switch displayedChallenge.challenge.challengeType {
        case .workoutCount:  return "Workout Count"
        case .totalVolume:   return "Total Volume"
        case .streak:        return "Streak"
        case .specificExercise: return "Exercise Challenge"
        case .custom:        return "Challenge"
        }
    }

    private var targetValueText: String {
        let v = NSDecimalNumber(decimal: displayedChallenge.challenge.goalValue).intValue
        switch displayedChallenge.challenge.challengeType {
        case .workoutCount:     return "\(v)"
        case .totalVolume:      return "\(v / 1000)K kg"
        case .streak:           return "\(v) days"
        case .specificExercise: return "\(v)"
        case .custom:
            if displayedChallenge.challenge.goalMetric == "conditioning_minutes" {
                return "\(v) min"
            }
            return "\(v)"
        }
    }

    private func progressValueText(progress: ChallengeParticipant) -> String {
        let cur = NSDecimalNumber(decimal: progress.currentProgress).intValue
        let goal = NSDecimalNumber(decimal: displayedChallenge.challenge.goalValue).intValue
        switch displayedChallenge.challenge.challengeType {
        case .workoutCount:     return "\(cur) / \(goal) workouts"
        case .totalVolume:      return "\(cur / 1000)K / \(goal / 1000)K kg"
        case .streak:           return "\(cur) / \(goal) days"
        case .specificExercise: return "\(cur) / \(goal) reps"
        case .custom:
            if displayedChallenge.challenge.goalMetric == "conditioning_minutes" {
                return "\(cur) / \(goal) min"
            }
            return "\(cur) / \(goal)"
        }
    }

    private var progressTargetText: String {
        switch displayedChallenge.challenge.challengeType {
        case .workoutCount:     return "workouts completed"
        case .totalVolume:      return "kilograms lifted"
        case .streak:           return "consecutive days"
        case .specificExercise: return "reps completed"
        case .custom:
            if displayedChallenge.challenge.goalMetric == "conditioning_minutes" {
                return "qualifying minutes logged"
            }
            return displayedChallenge.challenge.goalMetric
        }
    }

    private func rowProgressText(progress: Decimal, target: Decimal) -> String {
        let cur = NSDecimalNumber(decimal: progress).intValue
        let goal = NSDecimalNumber(decimal: target).intValue
        switch displayedChallenge.challenge.challengeType {
        case .workoutCount:     return "\(cur)/\(goal) workouts"
        case .totalVolume:      return "\(cur / 1000)K/\(goal / 1000)K kg"
        case .streak:           return "\(cur)/\(goal) days"
        case .specificExercise: return "\(cur)/\(goal) reps"
        case .custom:           return "\(cur)/\(goal)"
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return DS.Semantic.brand
        case 2: return DS.Semantic.textSecondary
        default: return DS.Semantic.textSecondary.opacity(0.6)
        }
    }

    private func performLeaveChallenge() async {
        guard !isProcessing else { return }

        isProcessing = true
        let didLeave = await viewModel.leaveChallenge(challenge.challenge)
        isProcessing = false

        if didLeave {
            dismiss()
        }
    }
}
