//
//  UnifiedCompeteView.swift
//  WRKT
//
//  Unified competition view without nested tabs - single scroll experience
//

import SwiftUI

struct UnifiedCompeteView: View {
    @Environment(\.dependencies) private var deps
    @State private var challengesVM: ChallengesViewModel?
    @State private var battlesVM: BattleViewModel?

    var body: some View {
        contentView
            .sheet(item: Binding(
                get: { challengesVM?.selectedChallenge },
                set: { _ in challengesVM?.closeChallengeDetail() }
            ), onDismiss: {
                // Refresh challenges when detail view is dismissed
                Task {
                    await challengesVM?.refresh()
                }
            }) { challenge in
                if let vm = challengesVM {
                    ChallengeDetailView(challenge: challenge, viewModel: vm)
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Active competitions carousel (if any exist)
                if let cvm = challengesVM, let bvm = battlesVM {
                    if !cvm.activeChallenges.isEmpty || !bvm.activeBattles.isEmpty {
                        activeCompetitionsCarousel(challengesVM: cvm, battlesVM: bvm)
                    }
                }

                // Quick stats overview
                statsGrid

                // Creation grid - two large buttons
                creationGrid

                // Pending invites (action needed)
                if let vm = battlesVM, !vm.pendingBattles.filter({ vm.isPendingAction(for: $0) }).isEmpty {
                    pendingInvitesSection(vm: vm)
                }

                // Recommended challenges
                if let vm = challengesVM, !vm.availableChallenges.isEmpty {
                    recommendedChallengesSection(vm: vm)
                }

                // Recent completions (if any)
                if let cvm = challengesVM, let bvm = battlesVM {
                    if !cvm.completedChallenges.isEmpty || !bvm.completedBattles.isEmpty {
                        recentCompletionsSection(challengesVM: cvm, battlesVM: bvm)
                    }
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .task {
            if challengesVM == nil {
                let cvm = ChallengesViewModel(
                    challengeRepository: deps.challengeRepository,
                    authService: deps.authService
                )
                challengesVM = cvm
                await cvm.onAppear()
            }

            if battlesVM == nil {
                let bvm = BattleViewModel(
                    battleRepository: deps.battleRepository,
                    authService: deps.authService
                )
                battlesVM = bvm
                await bvm.onAppear()
            }
        }
    }

    // MARK: - Active Competitions Carousel

    @ViewBuilder
    private func activeCompetitionsCarousel(challengesVM: ChallengesViewModel, battlesVM: BattleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Competitions")
                .font(.title3.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Active battles
                    ForEach(battlesVM.activeBattles.prefix(5)) { battle in
                        LargeBattleCard(battle: battle, viewModel: battlesVM)
                    }

                    // Active challenges
                    ForEach(challengesVM.activeChallenges.prefix(5)) { challenge in
                        LargeChallengeCard(challenge: challenge, viewModel: challengesVM)
                    }
                }
                .padding(.horizontal, 1)
            }
            .padding(.horizontal, -16)
        }
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            let activeChallengesCount = challengesVM?.activeChallenges.count ?? 0
            let activeBattlesCount = battlesVM?.activeBattles.count ?? 0
            let completedChallengesCount = challengesVM?.completedChallenges.count ?? 0
            let battlesWonCount = battlesVM?.completedBattles.count ?? 0

            CompeteStatTile(
                icon: "trophy.fill",
                value: activeChallengesCount > 0 ? "\(activeChallengesCount)" : "—",
                label: "Active Challenges",
                color: DS.Semantic.brand
            )

            CompeteStatTile(
                icon: "bolt.fill",
                value: activeBattlesCount > 0 ? "\(activeBattlesCount)" : "—",
                label: "Active Battles",
                color: DS.Semantic.brand
            )

            CompeteStatTile(
                icon: "checkmark.seal.fill",
                value: completedChallengesCount > 0 ? "\(completedChallengesCount)" : "—",
                label: "Completed",
                color: DS.Status.success
            )

            CompeteStatTile(
                icon: "flag.checkered",
                value: battlesWonCount > 0 ? "\(battlesWonCount)" : "—",
                label: "Victories",
                color: DS.Status.success
            )
        }
    }

    // MARK: - Creation Grid

    @ViewBuilder
    private var creationGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start Competing")
                .font(.title3.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            HStack(spacing: 12) {
                // Start Battle button
                if let vm = battlesVM {
                    @Bindable var bindableVM = vm
                    Button {
                        vm.openCreateBattle()
                    } label: {
                        CreationGridButton(
                            icon: "bolt.fill",
                            title: "Start 1v1 Battle",
                            subtitle: "Challenge a friend",
                            color: DS.Semantic.brand
                        )
                    }
                    .sheet(isPresented: $bindableVM.showCreateBattle) {
                        CreateBattleView(viewModel: vm)
                    }
                }

                // Join Challenge button
                NavigationLink {
                    ChallengesBrowseView()
                } label: {
                    CreationGridButton(
                        icon: "trophy.fill",
                        title: "Join Challenge",
                        subtitle: "Community events",
                        color: DS.Semantic.accentWarm
                    )
                }
            }
        }
    }

    // MARK: - Pending Invites Section

    @ViewBuilder
    private func pendingInvitesSection(vm: BattleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Action Needed", systemImage: "exclamationmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(DS.Status.warning)

            VStack(spacing: 8) {
                ForEach(vm.pendingBattles.filter { vm.isPendingAction(for: $0) }.prefix(3)) { battle in
                    PendingBattleCard(battle: battle, viewModel: vm, onTap: {
                        vm.openBattleDetail(battle)
                    })
                }
            }

            if vm.pendingBattles.filter({ vm.isPendingAction(for: $0) }).count > 3 {
                NavigationLink {
                    BattlesListView()
                } label: {
                    HStack {
                        Text("View All Pending (\(vm.pendingBattles.filter({ vm.isPendingAction(for: $0) }).count))")
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(DS.Semantic.brand)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Recommended Challenges Section

    @ViewBuilder
    private func recommendedChallengesSection(vm: ChallengesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recommended Challenges")
                    .font(.title3.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                NavigationLink {
                    ChallengesBrowseView()
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(DS.Semantic.brand)
                }
            }

            VStack(spacing: 8) {
                ForEach(vm.availableChallenges.prefix(3)) { challenge in
                    RecommendedChallengeCard(challenge: challenge, viewModel: vm)
                }
            }
        }
    }

    // MARK: - Recent Completions Section

    @ViewBuilder
    private func recentCompletionsSection(challengesVM: ChallengesViewModel, battlesVM: BattleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Completions")
                .font(.title3.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 8) {
                // Show completed challenges
                ForEach(challengesVM.completedChallenges.prefix(2)) { challenge in
                    CompletedChallengeCard(challenge: challenge)
                }

                // Show completed battles
                ForEach(battlesVM.completedBattles.prefix(2)) { battle in
                    CompletedBattleCard(battle: battle, viewModel: battlesVM, onTap: {
                        battlesVM.openBattleDetail(battle)
                    })
                }
            }
        }
    }
}

// MARK: - Creation Grid Button

struct CreationGridButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangle(.xl))
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(color.opacity(0.3), lineWidth: 2)
        )
    }
}

// MARK: - Large Battle Card

struct LargeBattleCard: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel

    var body: some View {
        Button {
            viewModel.openBattleDetail(battle)
        } label: {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: battle.battle.battleType.icon)
                        .font(.title3)
                        .foregroundStyle(DS.Semantic.brand)

                    Text(battle.battle.battleType.displayName)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()
                }

                // Score comparison
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("You")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Text(formatScore(viewModel.getCurrentUserScore(for: battle)))
                            .font(.title2.bold())
                            .foregroundStyle(viewModel.isCurrentUserWinning(for: battle) ? DS.Semantic.success : DS.Semantic.textPrimary)
                    }

                    Text("VS")
                        .font(.caption.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    VStack(spacing: 4) {
                        Text(battle.opponentProfile.username)
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Text(formatScore(viewModel.getOpponentScore(for: battle)))
                            .font(.title2.bold())
                            .foregroundStyle(!viewModel.isCurrentUserWinning(for: battle) ? DS.Semantic.warning : DS.Semantic.textPrimary)
                    }
                }

                // Days remaining
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("\(battle.battle.daysRemaining) days left")
                        .font(.caption)
                    Spacer()
                    if viewModel.isCurrentUserWinning(for: battle) {
                        Label("Winning", systemImage: "crown.fill")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.success)
                    }
                }
                .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(16)
            .frame(width: 280)
            .background(
                viewModel.isCurrentUserWinning(for: battle)
                    ? DS.Semantic.brandSoft
                    : DS.Semantic.card
            )
            .clipShape(ChamferedRectangle(.xl))
            .overlay(
                ChamferedRectangle(.xl)
                    .stroke(
                        viewModel.isCurrentUserWinning(for: battle)
                            ? DS.Semantic.brand.opacity(0.5)
                            : DS.Semantic.border,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func formatScore(_ score: Double) -> String {
        if score >= 1000 {
            return String(format: "%.1fk", score / 1000)
        }
        return String(format: "%.0f", score)
    }
}

// MARK: - Large Challenge Card

struct LargeChallengeCard: View {
    let challenge: ChallengeWithProgress
    let viewModel: ChallengesViewModel

    var body: some View {
        Button {
            viewModel.openChallengeDetail(challenge)
        } label: {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: challenge.challenge.challengeType.icon)
                        .font(.title3)
                        .foregroundStyle(DS.Semantic.brand)

                    Text(challenge.challenge.title)
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)

                    Spacer()
                }

                // Progress circle
                ZStack {
                    Circle()
                        .stroke(DS.Semantic.surface50, lineWidth: 12)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: CGFloat(challenge.userProgressPercentage) / 100)
                        .stroke(
                            LinearGradient(
                                colors: [DS.Semantic.brand, DS.Semantic.brand.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.6), value: challenge.userProgressPercentage)

                    Text("\(challenge.userProgressPercentage)%")
                        .font(.title2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                }

                // Days remaining
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("\(challenge.challenge.daysRemaining) days left")
                        .font(.caption)
                    Spacer()
                    Text("\(challenge.challenge.participantCount) competing")
                        .font(.caption)
                }
                .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(16)
            .frame(width: 280)
            .background(DS.Semantic.card)
            .clipShape(ChamferedRectangle(.xl))
            .overlay(
                ChamferedRectangle(.xl)
                    .stroke(DS.Semantic.brand.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recommended Challenge Card

struct RecommendedChallengeCard: View {
    let challenge: ChallengeWithProgress
    let viewModel: ChallengesViewModel

    var body: some View {
        Button {
            viewModel.openChallengeDetail(challenge)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: challenge.challenge.challengeType.icon)
                    .font(.title2)
                    .foregroundStyle(DS.Semantic.brand)
                    .frame(width: 44, height: 44)
                    .background(DS.Semantic.brandSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.challenge.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    HStack(spacing: 8) {
                        if let difficulty = challenge.challenge.difficulty {
                            Text(difficulty.displayName)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(difficultyColor(difficulty))
                                .foregroundStyle(difficultyTextColor(difficulty))
                                .clipShape(Capsule())
                        }

                        Text("\(challenge.challenge.participantCount) competing")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(12)
            .background(DS.Semantic.card)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func difficultyColor(_ difficulty: ChallengeDifficulty) -> Color {
        switch difficulty {
        case .beginner: return DS.Semantic.fillSubtle
        case .intermediate: return DS.Semantic.surface50
        case .advanced: return DS.Semantic.textSecondary.opacity(0.2)
        }
    }

    private func difficultyTextColor(_ difficulty: ChallengeDifficulty) -> Color {
        switch difficulty {
        case .beginner: return DS.Semantic.textSecondary
        case .intermediate: return DS.Semantic.textPrimary
        case .advanced: return DS.Semantic.textPrimary
        }
    }
}

// MARK: - Completed Challenge Card

struct CompletedChallengeCard: View {
    let challenge: ChallengeWithProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(DS.Status.success)

            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.challenge.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text("Completed • \(challenge.userProgressPercentage)%")
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()
        }
        .padding(12)
        .background(DS.Status.success.opacity(0.1))
        .clipShape(ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Status.success.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        UnifiedCompeteView()
            .environment(\.dependencies, AppDependencies.shared)
            .navigationTitle("Compete")
            .navigationBarTitleDisplayMode(.large)
    }
}
