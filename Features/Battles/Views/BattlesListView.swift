//
//  BattlesListView.swift
//  WRKT
//
//  View all battles - active, pending, and completed
//

import SwiftUI

struct BattlesListView: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: BattleViewModel?
    @State private var selectedTab: BattleTab = .active

    enum BattleTab {
        case active, pending, completed
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    content(viewModel: viewModel)
                } else {
                    loadingState
                }
            }
            .navigationTitle("Battles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let viewModel = viewModel {
                        Button {
                            viewModel.openCreateBattle()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(DS.Semantic.brand)
                        }
                    }
                }
            }
            .task {
                if viewModel == nil {
                    let vm = BattleViewModel(
                        battleRepository: deps.battleRepository,
                        authService: deps.authService
                    )
                    viewModel = vm
                    await vm.onAppear()
                }
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: BattleViewModel) -> some View {
        @Bindable var bindableVM = viewModel

        VStack(spacing: 0) {
            // Tab selector
            tabPicker

            ScrollView {
                LazyVStack(spacing: 16) {
                    switch selectedTab {
                    case .active:
                        activeBattlesSection(viewModel: viewModel)
                    case .pending:
                        pendingBattlesSection(viewModel: viewModel)
                    case .completed:
                        completedBattlesSection(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .sheet(isPresented: $bindableVM.showBattleDetail) {
            if let battle = viewModel.selectedBattle {
                BattleDetailView(battle: battle, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $bindableVM.showCreateBattle) {
            CreateBattleView(viewModel: viewModel)
        }
        .alert(item: $bindableVM.error) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var tabPicker: some View {
        // Premium segmented control with frosted glass effect (matching Social view)
        HStack(spacing: 0) {
            ChallengePillButton(
                title: "Active",
                icon: "bolt.fill",
                isSelected: selectedTab == .active
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .active
                    Haptics.light()
                }
            }

            ChallengePillButton(
                title: "Pending",
                icon: "envelope.fill",
                isSelected: selectedTab == .pending,
                badge: viewModel?.pendingBattles.count ?? 0
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .pending
                    Haptics.light()
                }
            }

            ChallengePillButton(
                title: "Completed",
                icon: "trophy.fill",
                isSelected: selectedTab == .completed
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .completed
                    Haptics.light()
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Semantic.card.opacity(0.5))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.Semantic.border.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func activeBattlesSection(viewModel: BattleViewModel) -> some View {
        if viewModel.isLoading {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBattleCard()
            }
        } else if viewModel.activeBattles.isEmpty {
            emptyActiveBattlesState
        } else {
            ForEach(viewModel.activeBattles) { battle in
                BattleCard(
                    battle: battle,
                    viewModel: viewModel,
                    onTap: { viewModel.openBattleDetail(battle) }
                )
            }
        }
    }

    @ViewBuilder
    private func pendingBattlesSection(viewModel: BattleViewModel) -> some View {
        if viewModel.isLoading {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBattleCard()
            }
        } else if viewModel.pendingBattles.isEmpty {
            emptyPendingState
        } else {
            ForEach(viewModel.pendingBattles) { battle in
                PendingBattleCard(
                    battle: battle,
                    viewModel: viewModel,
                    onTap: { viewModel.openBattleDetail(battle) }
                )
            }
        }
    }

    @ViewBuilder
    private func completedBattlesSection(viewModel: BattleViewModel) -> some View {
        if viewModel.isLoading {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBattleCard()
            }
        } else if viewModel.completedBattles.isEmpty {
            emptyCompletedState
        } else {
            ForEach(viewModel.completedBattles) { battle in
                CompletedBattleCard(
                    battle: battle,
                    viewModel: viewModel,
                    onTap: { viewModel.openBattleDetail(battle) }
                )
            }
        }
    }

    // MARK: - Empty States
    @ViewBuilder
    private var emptyActiveBattlesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.brand.opacity(0.3))

            Text("No Active Battles")
                .font(.title2.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Challenge a friend to start battling!")
                .font(.body)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)

            if let viewModel = viewModel {
                Button {
                    viewModel.openCreateBattle()
                } label: {
                    Text("Create Battle")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.onBrand)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(DS.Semantic.brand)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyPendingState: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.brand.opacity(0.3))

            Text("No Pending Battles")
                .font(.title2.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("You have no battle invitations")
                .font(.body)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyCompletedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundStyle(DS.Semantic.brand.opacity(0.3))

            Text("No Completed Battles")
                .font(.title2.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Complete your first battle to see it here")
                .font(.body)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBattleCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Battle Card Components
struct BattleCard: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(battleTypeLabel)
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Text("Battle")
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }

                    Spacer()

                    // Time remaining
                    let daysRemaining = battle.battle.daysRemaining
                    if daysRemaining > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(daysRemaining)")
                                .font(.title3.bold())
                                .foregroundStyle(DS.Semantic.brand)

                            Text(daysRemaining == 1 ? "day left" : "days left")
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                }

                // Score comparison
                HStack(spacing: 16) {
                    // Your score
                    ScoreColumn(
                        label: "You",
                        score: viewModel.getCurrentUserScore(for: battle),
                        isWinning: viewModel.isCurrentUserWinning(for: battle),
                        battleType: battle.battle.battleType
                    )

                    // VS divider
                    Text("VS")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .padding(.horizontal, 8)

                    // Opponent score
                    ScoreColumn(
                        label: "Opponent",
                        score: viewModel.getOpponentScore(for: battle),
                        isWinning: !viewModel.isCurrentUserWinning(for: battle),
                        battleType: battle.battle.battleType
                    )
                }

                // Status indicator
                if viewModel.isCurrentUserWinning(for: battle) {
                    Label("You're winning!", systemImage: "crown.fill")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.brand)
                } else {
                    Label("You're behind", systemImage: "arrow.up.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: viewModel.isCurrentUserWinning(for: battle)
                        ? [DS.Semantic.brand.opacity(0.08), DS.Semantic.brand.opacity(0.03)]
                        : [DS.Semantic.surface50, DS.Semantic.surface50],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        viewModel.isCurrentUserWinning(for: battle)
                            ? DS.Semantic.brand.opacity(0.4)
                            : DS.Semantic.border,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

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
}

struct PendingBattleCard: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel
    let onTap: () -> Void

    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(battleTypeLabel)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(invitationText)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                Spacer()

                Image(systemName: "envelope.badge.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Semantic.brand)
            }

            Text("Duration: \(battle.battle.duration) days")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)

            // Action buttons
            if viewModel.isPendingAction(for: battle) {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            isProcessing = true
                            await viewModel.declineBattle(battle.battle)
                            isProcessing = false
                        }
                    } label: {
                        Text("Decline")
                            .font(.subheadline.bold())
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Semantic.surface50)
                            .clipShape(Capsule())
                    }
                    .disabled(isProcessing)

                    Button {
                        Task {
                            isProcessing = true
                            await viewModel.acceptBattle(battle.battle)
                            isProcessing = false
                        }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Accept")
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.onBrand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.Semantic.brand)
                        .clipShape(Capsule())
                    }
                    .disabled(isProcessing)
                }
            } else {
                Text("Waiting for opponent to accept")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.brand.opacity(0.3), lineWidth: 1.5)
        )
    }

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

    private var invitationText: String {
        if viewModel.isPendingAction(for: battle) {
            return "Battle Invitation"
        } else {
            return "Battle Sent"
        }
    }
}

struct CompletedBattleCard: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(battleTypeLabel)
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Text(resultText)
                            .font(.headline)
                            .foregroundStyle(didWin ? DS.Semantic.brand : DS.Semantic.textPrimary)
                    }

                    Spacer()

                    if didWin {
                        Image(systemName: "trophy.fill")
                            .font(.title3)
                            .foregroundStyle(DS.Semantic.brand)
                    }
                }

                // Final scores
                HStack(spacing: 16) {
                    ScoreColumn(
                        label: "You",
                        score: viewModel.getCurrentUserScore(for: battle),
                        isWinning: didWin,
                        battleType: battle.battle.battleType
                    )

                    Text("VS")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.textSecondary)

                    ScoreColumn(
                        label: "Opponent",
                        score: viewModel.getOpponentScore(for: battle),
                        isWinning: !didWin,
                        battleType: battle.battle.battleType
                    )
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
        .buttonStyle(.plain)
    }

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

    private var didWin: Bool {
        guard let winner = viewModel.getWinner(for: battle) else {
            return false
        }
        return viewModel.isCurrentUserWinner(winner: winner, battle: battle)
    }

    private var authService: SupabaseAuthService {
        AppDependencies.shared.authService
    }

    private var resultText: String {
        didWin ? "Victory!" : "Defeat"
    }
}

struct ScoreColumn: View {
    let label: String
    let score: Double
    let isWinning: Bool
    let battleType: BattleType

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(scoreText)
                .font(.title2.bold())
                .foregroundStyle(isWinning ? DS.Semantic.brand : DS.Semantic.textPrimary)

            Text(scoreLabel)
                .font(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isWinning ? DS.Semantic.brandSoft : DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var scoreText: String {
        switch battleType {
        case .volume:
            return "\((score / 1000).safeInt)K"
        case .workoutCount:
            return "\(Int(score))"
        case .consistency:
            return "\(Int(score))"
        case .exercise:
            return "\(Int(score))"
        case .pr:
            return "\(Int(score))"
        }
    }

    private var scoreLabel: String {
        switch battleType {
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
}

// MARK: - Skeleton Loading Card
struct SkeletonBattleCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Rectangle()
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 120, height: 16)
                    .clipShape(Capsule())

                Spacer()

                Rectangle()
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 60, height: 24)
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                Rectangle()
                    .fill(DS.Semantic.fillSubtle)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Rectangle()
                    .fill(DS.Semantic.fillSubtle)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}
