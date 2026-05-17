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

    @State private var showingBattleExitConfirmation = false
    @State private var isProcessingBattleExit = false
    @State private var isProcessingBattleAccept = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var deps

    private var authService: SupabaseAuthService { deps.authService }

    private var liveBattle: BattleWithParticipants {
        viewModel.selectedBattle ?? battle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Battle status header
                    statusHeader

                    BattleRewardPreviewBlock(
                        battleType: battle.battle.battleType,
                        targetMetric: battle.battle.targetMetric
                    )

                    // Accept / Decline row (pending invite, current user is opponent)
                    if canAcceptBattle {
                        battlePendingActions
                    }

                    // Score comparison
                    scoreComparison

                    // Progress chart (if active)
                    if battle.battle.status == .active {
                        progressTimeline
                    }

                    // Leave / Cancel section (active or challenger-side pending)
                    if canExitBattle && !canAcceptBattle {
                        battleExitSection
                    }

                    // Battle details
                    detailsSection

                    // Winner announcement (if completed)
                    if battle.battle.status == .completed {
                        winnerSection
                    }
                }
                .padding()
                .padding(.bottom, 32)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle("Battle")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.refreshSelectedBattle()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DS.Semantic.brand)
                }
            }
        }
        .alert(battleExitConfirmationTitle, isPresented: $showingBattleExitConfirmation) {
            Button("Keep Battle", role: .cancel) {}
            Button(battleExitActionTitle, role: .destructive) {
                Task {
                    await performBattleExit()
                }
            }
        } message: {
            Text(battleExitConfirmationMessage)
        }
    }

    // MARK: - Sections
    @ViewBuilder
    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(battleTypeLabel)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(statusText)
                        .dsFont(.title2, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Spacer()

                statusBadge
            }

            // Time indicator
            statusLine
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var scoreComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                BattleScorePanel(
                    title: "You",
                    subtitle: "Your score",
                    score: formatScore(viewModel.getCurrentUserScore(for: liveBattle)),
                    unit: scoreUnit,
                    isLeading: isCurrentUserLeading,
                    isTied: isTied
                )

                Text("VS")
                    .dsFont(.headline, weight: .black)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(width: 34)

                BattleScorePanel(
                    title: "Opponent",
                    subtitle: opponentName,
                    score: formatScore(viewModel.getOpponentScore(for: liveBattle)),
                    unit: scoreUnit,
                    isLeading: isOpponentLeading,
                    isTied: isTied
                )
            }

            if shouldShowScoreSummary {
                HStack(spacing: 8) {
                    Text(scoreSummaryText)
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DS.Semantic.fillSubtle, in: ChamferedRectangleAlt(.medium))
                .overlay(
                    ChamferedRectangleAlt(.medium)
                        .stroke(DS.Semantic.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var progressTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            // Simple progress bars
            VStack(spacing: 14) {
                BattleProgressRow(
                    label: "You",
                    value: formatScore(viewModel.getCurrentUserScore(for: liveBattle)),
                    progress: viewModel.getCurrentUserScore(for: liveBattle),
                    total: progressTotal,
                    tint: DS.Semantic.brand
                )

                BattleProgressRow(
                    label: opponentName,
                    value: formatScore(viewModel.getOpponentScore(for: liveBattle)),
                    progress: viewModel.getOpponentScore(for: liveBattle),
                    total: progressTotal,
                    tint: DS.Semantic.textSecondary
                )
            }
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var battlePendingActions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await performBattleAccept() }
            } label: {
                Group {
                    if isProcessingBattleAccept {
                        ProgressView().tint(.black)
                    } else {
                        Text("Accept")
                            .dsFont(.subheadline, weight: .bold)
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DS.Semantic.brand, in: SingleChamferedRectangle(corner: .topTrailing, .large))
            }
            .buttonStyle(.plain)
            .disabled(isProcessingBattleAccept || isProcessingBattleExit)

            Button {
                showingBattleExitConfirmation = true
            } label: {
                Text("Decline")
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(DS.Status.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.Semantic.card, in: SingleChamferedRectangle(corner: .topLeading, .large))
                    .overlay(
                        SingleChamferedRectangle(corner: .topLeading, .large)
                            .stroke(DS.Status.error.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isProcessingBattleExit || isProcessingBattleAccept)
        }
    }

    @ViewBuilder
    private var battleExitSection: some View {
        Button {
            showingBattleExitConfirmation = true
        } label: {
            HStack(spacing: 12) {
                Image(battleIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(DS.Status.error)
                    .frame(width: 36, height: 36)
                    .background(DS.Status.error.opacity(0.12), in: ChamferedRectangleAlt(.small))
                    .overlay(
                        ChamferedRectangleAlt(.small)
                            .stroke(DS.Status.error.opacity(0.25), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(battleExitActionTitle)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Status.error)

                    Text(battleExitDescription)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isProcessingBattleExit {
                    ProgressView()
                        .tint(DS.Status.error)
                } else {
                    Text("Confirm")
                        .dsFont(.caption2, weight: .bold)
                        .foregroundStyle(DS.Status.error)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(DS.Status.error.opacity(0.12), in: ChamferedRectangle(.micro))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Status.error.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessingBattleExit)
    }

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                BattleDetailMetric(label: "Type", value: battleTypeLabel)
                BattleDetailMetric(label: "Duration", value: "\(battle.battle.duration)d")
                BattleDetailMetric(
                    label: "Start",
                    value: battle.battle.startDate.formatted(date: .abbreviated, time: .omitted)
                )
                BattleDetailMetric(
                    label: "End",
                    value: battle.battle.endDate.formatted(date: .abbreviated, time: .omitted)
                )
            }
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var winnerSection: some View {
        if let winner = viewModel.getWinner(for: battle) {
            VStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(DS.Typography.custom(size: 48, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(DS.Semantic.brand)

                Text(isCurrentUserWinner(winner) ? "You Won!" : "You Lost")
                    .dsFont(.title, weight: .bold)
                    .foregroundStyle(
                        isCurrentUserWinner(winner)
                            ? DS.Semantic.brand
                            : DS.Semantic.textPrimary
                    )

                Text(winnerMessage(winner))
                    .dsFont(.body)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(
                isCurrentUserWinner(winner) ? DS.Semantic.brandSoft : DS.Semantic.fillSubtle,
                in: ChamferedRectangle(.large)
            )
            .overlay(
                ChamferedRectangle(.large)
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
            .dsFont(.caption, weight: .bold)
            .foregroundStyle(statusTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor, in: ChamferedRectangle(.small))
            .overlay(
                ChamferedRectangle(.small)
                    .stroke(statusColor.opacity(0.35), lineWidth: 1)
            )
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
        case .runningDistance:
            return "Running Distance"
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

    private var statusTextColor: Color {
        switch battle.battle.status {
        case .active:
            return .black
        default:
            return DS.Semantic.textPrimary
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 10) {
            Image(battleIconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(DS.Semantic.brand)
                .frame(width: 30, height: 30)
                .background(DS.Semantic.brandSoft, in: ChamferedRectangleAlt(.small))
                .overlay(
                    ChamferedRectangleAlt(.small)
                        .stroke(DS.Semantic.brand.opacity(0.24), lineWidth: 1)
                )

            Text(statusLineText)
                .dsFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
    }

    private var statusLineText: String {
        switch battle.battle.status {
        case .active:
            let daysRemaining = battle.battle.daysRemaining
            let dayText = daysRemaining == 1 ? "1 day left" : "\(daysRemaining) days left"
            return "\(dayText) against \(opponentName)"
        case .completed:
            return "Battle completed"
        case .pending:
            return "Waiting for battle acceptance"
        case .declined:
            return "Battle invitation declined"
        case .cancelled:
            return "Battle cancelled"
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
        case .runningDistance:
            return "km"
        }
    }

    private var opponentName: String {
        battle.opponentProfile.displayName ?? battle.opponentProfile.username
    }

    private var isCurrentUserLeading: Bool {
        viewModel.getCurrentUserScore(for: liveBattle) > viewModel.getOpponentScore(for: liveBattle)
    }

    private var isOpponentLeading: Bool {
        viewModel.getOpponentScore(for: liveBattle) > viewModel.getCurrentUserScore(for: liveBattle)
    }

    private var isTied: Bool {
        viewModel.getCurrentUserScore(for: liveBattle) == viewModel.getOpponentScore(for: liveBattle)
    }

    private var shouldShowScoreSummary: Bool {
        guard battle.battle.status == .active else { return false }
        return true
    }

    private var progressTotal: Double {
        max(
            viewModel.getCurrentUserScore(for: liveBattle),
            viewModel.getOpponentScore(for: liveBattle),
            1
        )
    }

    private var scoreSummaryText: String {
        if isTied {
            return "Tied"
        }

        let difference = abs(
            viewModel.getCurrentUserScore(for: liveBattle) - viewModel.getOpponentScore(for: liveBattle)
        )

        return differenceText(difference: difference)
    }

    private var currentUserId: UUID? {
        authService.currentUser?.id
    }

    private var isCurrentUserChallenger: Bool {
        currentUserId == battle.battle.challengerId
    }

    private var isCurrentUserOpponent: Bool {
        currentUserId == battle.battle.opponentId
    }

    private var canExitBattle: Bool {
        guard isCurrentUserChallenger || isCurrentUserOpponent else { return false }

        switch battle.battle.status {
        case .pending, .active:
            return true
        case .completed, .declined, .cancelled:
            return false
        }
    }

    private var canAcceptBattle: Bool {
        battle.battle.status == .pending && isCurrentUserOpponent
    }

    private var battleExitActionTitle: String {
        if battle.battle.status == .active {
            return "Leave Battle"
        }

        if battle.battle.status == .pending && isCurrentUserOpponent {
            return "Decline Battle"
        }

        return "Cancel Battle"
    }

    private var battleExitDescription: String {
        if battle.battle.status == .active {
            return "Ends this active battle for both participants."
        }

        if battle.battle.status == .pending && isCurrentUserOpponent {
            return "Declines the invitation and removes it from your battles."
        }

        return "Withdraws the invitation before \(opponentName) accepts."
    }

    private var battleExitConfirmationTitle: String {
        "\(battleExitActionTitle)?"
    }

    private var battleExitConfirmationMessage: String {
        if battle.battle.status == .active {
            return "Leaving cancels this battle for both you and \(opponentName). Scores will stop updating."
        }

        if battle.battle.status == .pending && isCurrentUserOpponent {
            return "Decline this battle invitation from \(opponentName)?"
        }

        return "Cancel this battle invitation to \(opponentName)?"
    }

    private var battleIconName: String {
        switch battle.battle.battleType {
        case .volume:
            return "battle-volume-icon"
        case .consistency:
            return "battle-consistency-icon"
        case .workoutCount:
            return "battle-workout-count-icon"
        case .pr:
            return "battle-flags-icon"
        case .exercise:
            return "battle-opponent-icon"
        case .runningDistance:
            return "battle-workout-count-icon"
        }
    }

    private func formatScore(_ score: Double) -> String {
        switch battle.battle.battleType {
        case .volume:
            if score >= 1000 {
                return String(format: "%.1fk", score / 1000)
            }
            return "\(Int(score))"
        case .workoutCount, .consistency, .exercise:
            return "\(Int(score))"
        case .pr:
            return "\(Int(score))"
        case .runningDistance:
            return String(format: "%.1f", score)
        }
    }

    private func differenceText(difference: Double) -> String {
        let formattedDiff = formatScore(difference)
        let leader = isCurrentUserLeading ? "You're" : "Opponent is"
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

    private func performBattleExit() async {
        guard !isProcessingBattleExit else { return }

        isProcessingBattleExit = true
        defer { isProcessingBattleExit = false }

        let didExit: Bool
        if battle.battle.status == .pending && isCurrentUserOpponent {
            didExit = await viewModel.declineBattle(battle.battle)
        } else {
            didExit = await viewModel.cancelBattle(battle.battle)
        }

        if didExit {
            dismiss()
        }
    }

    private func performBattleAccept() async {
        guard !isProcessingBattleAccept else { return }

        isProcessingBattleAccept = true
        defer { isProcessingBattleAccept = false }

        let didAccept = await viewModel.acceptBattle(battle.battle)
        if didAccept {
            dismiss()
        }
    }
}

private struct BattleScorePanel: View {
    let title: String
    let subtitle: String
    let score: String
    let unit: String
    let isLeading: Bool
    let isTied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(isLeading && !isTied ? DS.Semantic.brand : DS.Semantic.textPrimary)

                Text(subtitle)
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score)
                    .font(DS.Typography.custom(size: 36, weight: .black, relativeTo: .title, monospacedDigits: true))
                    .foregroundStyle(isLeading && !isTied ? DS.Semantic.brand : DS.Semantic.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(unit)
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Text(statusText)
                .dsFont(.caption2, weight: .bold)
                .foregroundStyle(isLeading && !isTied ? DS.Semantic.brand : DS.Semantic.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isLeading && !isTied ? DS.Semantic.brandSoft : DS.Semantic.surface50,
                    in: ChamferedRectangle(.micro)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            isLeading && !isTied ? DS.Semantic.brandSoft : DS.Semantic.fillSubtle,
            in: ChamferedRectangle(.large)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(isLeading && !isTied ? DS.Semantic.brand.opacity(0.42) : DS.Semantic.border, lineWidth: 1)
        )
    }

    private var statusText: String {
        if isTied { return "Tied" }
        return isLeading ? "Leading" : "Score"
    }
}

private struct BattleProgressRow: View {
    let label: String
    let value: String
    let progress: Double
    let total: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text(value)
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(tint)
            }

            ProgressView(value: progress, total: total)
                .tint(tint)
        }
    }
}

private struct BattleDetailMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .dsFont(.caption2, weight: .bold)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(value)
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Semantic.fillSubtle, in: ChamferedRectangleAlt(.medium))
        .overlay(
            ChamferedRectangleAlt(.medium)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }
}
