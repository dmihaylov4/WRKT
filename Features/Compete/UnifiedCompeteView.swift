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
            .sheet(item: Binding(
                get: { battlesVM?.selectedBattle },
                set: { _ in battlesVM?.closeBattleDetail() }
            ), onDismiss: {
                Task {
                    await battlesVM?.refresh()
                }
            }) { battle in
                if let vm = battlesVM {
                    BattleDetailView(battle: battle, viewModel: vm)
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
                    authService: deps.authService,
                    workoutStore: deps.workoutStore
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
                .dsFont(.title3, weight: .bold)
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
        ], spacing: 8) {
            let activeChallengesCount = challengesVM?.activeChallenges.count ?? 0
            let activeBattlesCount = battlesVM?.activeBattles.count ?? 0
            let completedChallengesCount = challengesVM?.completedChallenges.count ?? 0
            let battlesWonCount = battlesVM?.completedBattles.count ?? 0

            CompeteStatTile(
                icon: "trophy.fill",
                value: activeChallengesCount > 0 ? "\(activeChallengesCount)" : "—",
                label: "Active Challenges",
                color: DS.Semantic.brand,
                gridPosition: .topLeading
            )

            CompeteStatTile(
                icon: "bolt.fill",
                value: activeBattlesCount > 0 ? "\(activeBattlesCount)" : "—",
                label: "Active Battles",
                color: DS.Semantic.brand,
                gridPosition: .topTrailing
            )

            CompeteStatTile(
                icon: "checkmark.seal.fill",
                value: completedChallengesCount > 0 ? "\(completedChallengesCount)" : "—",
                label: "Completed",
                color: DS.Status.success,
                gridPosition: .bottomLeading
            )

            CompeteStatTile(
                icon: "flag.checkered",
                value: battlesWonCount > 0 ? "\(battlesWonCount)" : "—",
                label: "Victories",
                color: DS.Status.success,
                gridPosition: .bottomTrailing
            )
        }
    }

    // MARK: - Creation Grid

    @ViewBuilder
    private var creationGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start Competing")
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            HStack(spacing: 12) {
                // Start Battle button
                if let vm = battlesVM {
                    @Bindable var bindableVM = vm
                    Button {
                        vm.openCreateBattle()
                    } label: {
                        CreationGridButton(
                            iconName: "battle-workout-count-icon",
                            title: "Start 1v1 Battle",
                            subtitle: "Challenge a friend",
                            color: DS.Semantic.brand,
                            gridPosition: .rowLeading
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
                        iconName: "challenge-trophy-icon",
                        title: "Join Challenge",
                        subtitle: "Community events",
                        color: DS.Semantic.accentWarm,
                        gridPosition: .rowTrailing
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
                .dsFont(.title3, weight: .bold)
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
                            .dsFont(.subheadline, weight: .bold)
                        Image(systemName: "chevron.right")
                            .dsFont(.caption)
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
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                NavigationLink {
                    ChallengesBrowseView()
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .dsFont(.subheadline)
                        Image(systemName: "chevron.right")
                            .dsFont(.caption)
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
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 8) {
                // Show completed challenges
                ForEach(challengesVM.completedChallenges.prefix(2)) { challenge in
                    CompletedChallengeCard(challenge: challenge, onTap: {
                        challengesVM.openChallengeDetail(challenge)
                    })
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
    let iconName: String
    let title: String
    let subtitle: String
    let color: Color
    var gridPosition: DS.GridChamferPosition = .rowLeading

    var body: some View {
        let shape = SingleChamferedRectangle(corner: gridPosition.chamferCorner, .xl)
        content
            .clipShape(shape)
            .overlay(shape.stroke(color.opacity(0.3), lineWidth: 2))
    }

    private var content: some View {
        VStack(spacing: 12) {
            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .foregroundStyle(color)
                .frame(width: 60, height: 60)

            VStack(spacing: 4) {
                Text(title)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(DS.Semantic.card)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(battle.battle.battleType.displayName)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer()

                    PlateFaceView(
                        tierID: battle.battle.battleType.winnerPlateTierID,
                        progressionTier: .iron,
                        liftTypeID: nil,
                        weightKg: 35
                    )
                    .frame(width: 28, height: 28)
                    .clipped()
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You")
                            .dsFont(.caption2, weight: .bold)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        Text(formatScore(viewModel.getCurrentUserScore(for: battle)))
                            .dsFont(.title2, weight: .bold, monospacedDigits: true)
                            .foregroundStyle(viewModel.isCurrentUserWinning(for: battle) ? DS.Semantic.success : DS.Semantic.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("VS")
                        .dsFont(.caption2, weight: .bold)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(battle.opponentProfile.username)
                            .dsFont(.caption2, weight: .bold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .lineLimit(1)

                        Text(formatScore(viewModel.getOpponentScore(for: battle)))
                            .dsFont(.title2, weight: .bold, monospacedDigits: true)
                            .foregroundStyle(!viewModel.isCurrentUserWinning(for: battle) ? DS.Semantic.warning : DS.Semantic.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("\(battle.battle.daysRemaining) days left")
                        .dsFont(.caption, weight: .bold)
                    Spacer()
                    if viewModel.isCurrentUserWinning(for: battle) {
                        Text("Winning")
                            .dsFont(.caption, weight: .bold)
                            .foregroundStyle(DS.Semantic.success)
                    }
                }
                .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(14)
            .frame(width: 260, height: 138)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(challenge.challenge.title)
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    rewardBadge
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(challenge.userProgressPercentage)%")
                            .dsFont(.title2, weight: .bold, monospacedDigits: true)
                            .foregroundStyle(DS.Semantic.brand)
                        Spacer()
                        Text("Complete")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    ProgressView(value: Double(challenge.userProgressPercentage), total: 100)
                        .tint(DS.Semantic.brand)
                        .animation(.spring(duration: 0.6), value: challenge.userProgressPercentage)
                }

                HStack(spacing: 8) {
                    Text(challenge.challenge.daysRemainingDisplay)
                        .dsFont(.caption, weight: .bold)
                    Spacer()
                    Text("\(challenge.challenge.participantCount) competing")
                        .dsFont(.caption)
                }
                .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(14)
            .frame(width: 260, height: 138)
            .background(DS.Semantic.card)
            .clipShape(ChamferedRectangle(.xl))
            .overlay(
                ChamferedRectangle(.xl)
                    .stroke(DS.Semantic.brand.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rewardBadge: some View {
        switch ChallengeRewardPreviewKind(challenge: challenge.challenge) {
        case .firstRepBarSkin:
            if let skin = BarSkin.skin(forCosmeticID: "volia") {
                BarSkinPreviewTile(skin: skin)
                    .frame(width: 48, height: 16)
            }
        case .conditioningPlate:
            PlateFaceView(
                tierID: 24,
                progressionTier: .iron,
                liftTypeID: nil,
                weightKg: 20
            )
            .frame(width: 28, height: 28)
            .clipped()
        case .none:
            Image("angular-chevron-right-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
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
                Image(challengeIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(DS.Semantic.brand)
                    .frame(width: 44, height: 44)
                    .background(DS.Semantic.brandSoft)
                    .clipShape(ChamferedRectangleAlt(.small))
                    .overlay(
                        ChamferedRectangleAlt(.small)
                            .stroke(DS.Semantic.brand.opacity(0.24), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.challenge.title)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    HStack(spacing: 8) {
                        if let difficulty = challenge.challenge.difficulty {
                            Text(difficulty.displayName)
                                .dsFont(.caption2, weight: .bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(difficultyColor(difficulty))
                                .foregroundStyle(difficultyTextColor(difficulty))
                                .clipShape(Capsule())
                        }

                        Text("\(challenge.challenge.participantCount) competing")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                Spacer()

                rewardBadge
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

    @ViewBuilder
    private var rewardBadge: some View {
        switch ChallengeRewardPreviewKind(challenge: challenge.challenge) {
        case .firstRepBarSkin:
            if let skin = BarSkin.all.first(where: { $0.id == 4 }) {
                BarSkinPreviewTile(skin: skin)
                    .frame(width: 60, height: 20)
            }
        case .conditioningPlate:
            PlateFaceView(
                tierID: 24,
                progressionTier: .iron,
                liftTypeID: nil,
                weightKg: 20
            )
            .frame(width: 40, height: 40)
            .clipped()
        case .none:
            Image("angular-chevron-right-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
    }

    private var challengeIconName: String {
        switch challenge.challenge.challengeType {
        case .streak:
            return "streak-icon"
        case .workoutCount:
            return "battle-workout-count-icon"
        case .totalVolume:
            return "battle-volume-icon"
        case .specificExercise:
            return "battle-consistency-icon"
        case .custom:
            return "challenge-browse-icon"
        }
    }
}

// MARK: - Completed Challenge Card

struct CompletedChallengeCard: View {
    let challenge: ChallengeWithProgress
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                rewardPreview
                    .frame(width: 66, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.challenge.title)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("Completed • \(challenge.userProgressPercentage)%")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer(minLength: 8)

                Image("angular-chevron-right-icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .padding(12)
            .background(DS.Status.success.opacity(0.1))
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Status.success.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rewardPreview: some View {
        switch ChallengeRewardPreviewKind(challenge: challenge.challenge) {
        case .firstRepBarSkin:
            if let skin = BarSkin.skin(forCosmeticID: "volia") {
                BarSkinPreviewTile(skin: skin)
                    .frame(width: 66, height: 22)
            }
        case .conditioningPlate:
            PlateFaceView(
                tierID: 24,
                progressionTier: .iron,
                liftTypeID: nil,
                weightKg: 20
            )
            .frame(width: 44, height: 44)
            .clipped()
        case .none:
            Image("challenge-completed-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(DS.Status.success)
        }
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
