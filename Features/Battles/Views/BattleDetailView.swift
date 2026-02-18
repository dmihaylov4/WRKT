//
//  BattleDetailView.swift
//  WRKT
//
//  Detailed view of a battle with live scores and timeline
//

import SwiftUI

struct BattleDetailView: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    private var authService: SupabaseAuthService { deps.authService }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Battle status header
                    statusHeader

                    // Score comparison
                    scoreComparison

                    // Progress chart (if active)
                    if battle.battle.status == .active {
                        progressTimeline
                    }

                    // Battle details
                    detailsSection

                    // Winner announcement (if completed)
                    if battle.battle.status == .completed {
                        winnerSection
                    }
                }
                .padding()
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle("Battle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DS.Semantic.brand)
                }
            }
        }
    }

    // MARK: - Sections
    @ViewBuilder
    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(battleTypeLabel)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(statusText)
                        .font(.title2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Spacer()

                statusBadge
            }

            // Time indicator
            if battle.battle.status == .active {
                let daysRemaining = battle.battle.daysRemaining
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.brand)

                    Text("\(daysRemaining) \(daysRemaining == 1 ? "day" : "days") remaining")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            } else if battle.battle.status == .completed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Status.success)

                    Text("Battle completed")
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textPrimary)
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
    private var scoreComparison: some View {
        VStack(spacing: 16) {
            // Large score display
            HStack(alignment: .top, spacing: 0) {
                // Your score
                VStack(spacing: 8) {
                    Text("You")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(formatScore(viewModel.getCurrentUserScore(for: battle)))
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(
                            viewModel.isCurrentUserWinning(for: battle)
                                ? DS.Semantic.brand
                                : DS.Semantic.textPrimary
                        )

                    Text(scoreUnit)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if viewModel.isCurrentUserWinning(for: battle) && battle.battle.status == .active {
                        Label("Winning", systemImage: "crown.fill")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DS.Semantic.brandSoft)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    viewModel.isCurrentUserWinning(for: battle)
                        ? DS.Semantic.brandSoft
                        : DS.Semantic.fillSubtle
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // VS divider
                Text("VS")
                    .font(.headline.bold())
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(width: 60)
                    .padding(.vertical, 24)

                // Opponent score
                VStack(spacing: 8) {
                    Text("Opponent")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(formatScore(viewModel.getOpponentScore(for: battle)))
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(
                            !viewModel.isCurrentUserWinning(for: battle)
                                ? DS.Semantic.brand
                                : DS.Semantic.textPrimary
                        )

                    Text(scoreUnit)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if !viewModel.isCurrentUserWinning(for: battle) && battle.battle.status == .active {
                        Label("Winning", systemImage: "crown.fill")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.brand)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DS.Semantic.brandSoft)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    !viewModel.isCurrentUserWinning(for: battle)
                        ? DS.Semantic.brandSoft
                        : DS.Semantic.fillSubtle
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Score difference
            if battle.battle.status == .active {
                let difference = abs(
                    viewModel.getCurrentUserScore(for: battle) - viewModel.getOpponentScore(for: battle)
                )
                if difference > 0 {
                    Text(differenceText(difference: difference))
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var progressTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            // Simple progress bars
            VStack(spacing: 16) {
                // Your progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("You")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Spacer()

                        Text(formatScore(viewModel.getCurrentUserScore(for: battle)))
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.brand)
                    }

                    ProgressView(
                        value: viewModel.getCurrentUserScore(for: battle),
                        total: max(
                            viewModel.getCurrentUserScore(for: battle),
                            viewModel.getOpponentScore(for: battle)
                        )
                    )
                    .tint(DS.Semantic.brand)
                }

                // Opponent progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Opponent")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Spacer()

                        Text(formatScore(viewModel.getOpponentScore(for: battle)))
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    ProgressView(
                        value: viewModel.getOpponentScore(for: battle),
                        total: max(
                            viewModel.getCurrentUserScore(for: battle),
                            viewModel.getOpponentScore(for: battle)
                        )
                    )
                    .tint(DS.Semantic.textSecondary)
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
                DetailRow(label: "Battle Type", value: battleTypeLabel)
                DetailRow(label: "Duration", value: "\(battle.battle.duration) days")
                DetailRow(
                    label: "Start Date",
                    value: battle.battle.startDate.formatted(date: .abbreviated, time: .omitted)
                )
                DetailRow(
                    label: "End Date",
                    value: battle.battle.endDate.formatted(date: .abbreviated, time: .omitted)
                )
                DetailRow(label: "Status", value: battle.battle.status.rawValue.capitalized)
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
    private var winnerSection: some View {
        if let winner = viewModel.getWinner(for: battle) {
            VStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(DS.Semantic.brand)

                Text(isCurrentUserWinner(winner) ? "You Won!" : "You Lost")
                    .font(.title.bold())
                    .foregroundStyle(
                        isCurrentUserWinner(winner)
                            ? DS.Semantic.brand
                            : DS.Semantic.textPrimary
                    )

                Text(winnerMessage(winner))
                    .font(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(
                isCurrentUserWinner(winner)
                    ? DS.Semantic.brandSoft
                    : DS.Semantic.fillSubtle
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isCurrentUserWinner(winner)
                            ? DS.Semantic.brand.opacity(0.3)
                            : DS.Semantic.border,
                        lineWidth: 1.5
                    )
            )
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(battle.battle.status.rawValue.capitalized)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor)
            .clipShape(Capsule())
    }

    // MARK: - Helpers
    private var battleTypeLabel: String {
        switch battle.battle.battleType {
        case .volume:
            return "Total Volume"
        case .workoutCount:
            return "Workout Count"
        case .consistency:
            return "Consistency"
        case .exercise:
            return "Exercise Battle"
        case .pr:
            return "PR Battle"
        }
    }

    private var statusText: String {
        switch battle.battle.status {
        case .pending:
            return "Battle Pending"
        case .active:
            return battleTypeLabel + " Battle"
        case .completed:
            return "Battle Completed"
        case .declined:
            return "Battle Declined"
        case .cancelled:
            return "Battle Cancelled"
        }
    }

    private var statusColor: Color {
        switch battle.battle.status {
        case .pending:
            return DS.Status.warning
        case .active:
            return DS.Semantic.brand
        case .completed:
            return DS.Status.success
        case .declined:
            return DS.Status.error
        case .cancelled:
            return DS.Semantic.textSecondary
        }
    }

    private var scoreUnit: String {
        switch battle.battle.battleType {
        case .volume:
            return "kg"
        case .workoutCount:
            return "workouts"
        case .consistency:
            return "days"
        case .exercise:
            return "reps"
        case .pr:
            return "kg"
        }
    }

    private func formatScore(_ score: Double) -> String {
        switch battle.battle.battleType {
        case .volume:
            return "\((score / 1000).safeInt)K"
        case .workoutCount, .consistency, .exercise:
            return "\(Int(score))"
        case .pr:
            return "\(Int(score))"
        }
    }

    private func differenceText(difference: Double) -> String {
        let formattedDiff = formatScore(difference)
        let leader = viewModel.isCurrentUserWinning(for: battle) ? "You're" : "Opponent is"
        return "\(leader) ahead by \(formattedDiff) \(scoreUnit)"
    }

    private func isCurrentUserWinner(_ winner: UserProfile) -> Bool {
        guard let userId = authService.currentUser?.id else { return false }
        return winner.id == userId
    }

    private func winnerMessage(_ winner: UserProfile) -> String {
        if isCurrentUserWinner(winner) {
            return "Congratulations on your victory!"
        } else {
            return "Better luck next time. Challenge them to a rematch!"
        }
    }
}
