//
//  CompeteView.swift
//  WRKT
//
//  Main competition tab combining challenges and battles
//

import SwiftUI

struct CompeteView: View {
    @State private var selectedSection: CompeteSection = .overview

    enum CompeteSection {
        case overview, challenges, battles
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                sectionPicker

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
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle("Compete")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private var sectionPicker: some View {
        HStack(spacing: 0) {
            SectionTab(
                title: "Overview",
                icon: "chart.bar.fill",
                isSelected: selectedSection == .overview,
                action: { withAnimation { selectedSection = .overview } }
            )

            SectionTab(
                title: "Challenges",
                icon: "trophy.fill",
                isSelected: selectedSection == .challenges,
                action: { withAnimation { selectedSection = .challenges } }
            )

            SectionTab(
                title: "Battles",
                icon: "bolt.fill",
                isSelected: selectedSection == .battles,
                action: { withAnimation { selectedSection = .battles } }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(DS.Semantic.surface50)
    }
}

// MARK: - Section Tab Component
struct SectionTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? DS.Semantic.brand : DS.Semantic.textSecondary)

                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? DS.Semantic.brand : DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected ? DS.Semantic.brandSoft : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Overview Section
struct OverviewSection: View {
    @Environment(\.dependencies) private var deps
    @State private var challengesVM: ChallengesViewModel?
    @State private var battlesVM: BattleViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero stats
                statsGrid

                // Active challenges preview
                if let vm = challengesVM, !vm.activeChallenges.isEmpty {
                    activeChallengesSection(vm: vm)
                }

                // Active battles preview
                if let vm = battlesVM, !vm.activeBattles.isEmpty {
                    activeBattlesSection(vm: vm)
                }

                // Pending battles (needs action)
                if let vm = battlesVM, !vm.pendingBattles.filter({ vm.isPendingAction(for: $0) }).isEmpty {
                    pendingBattlesSection(vm: vm)
                }

                // Quick actions
                quickActions
            }
            .padding()
        }
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
                label: "Completed Challenges",
                color: DS.Status.success
            )

            CompeteStatTile(
                icon: "flag.checkered",
                value: battlesWonCount > 0 ? "\(battlesWonCount)" : "—",
                label: "Battles Won",
                color: DS.Status.success
            )
        }
    }

    @ViewBuilder
    private func activeChallengesSection(vm: ChallengesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Challenges")
                    .font(.title3.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                NavigationLink {
                    ChallengesBrowseView()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.brand)
                }
            }

            ForEach(vm.activeChallenges.prefix(3)) { challenge in
                CompactChallengeCard(challenge: challenge, viewModel: vm)
            }
        }
    }

    @ViewBuilder
    private func activeBattlesSection(vm: BattleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Battles")
                    .font(.title3.bold())
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                NavigationLink {
                    BattlesListView()
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.brand)
                }
            }

            ForEach(vm.activeBattles.prefix(3)) { battle in
                CompactBattleCard(battle: battle, viewModel: vm)
            }
        }
    }

    @ViewBuilder
    private func pendingBattlesSection(vm: BattleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Action Needed", systemImage: "exclamationmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(DS.Status.warning)

                Spacer()
            }

            ForEach(vm.pendingBattles.filter { vm.isPendingAction(for: $0) }) { battle in
                PendingBattleCard(battle: battle, viewModel: vm, onTap: {
                    vm.openBattleDetail(battle)
                })
            }
        }
    }

    @ViewBuilder
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title3.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 12) {
                NavigationLink {
                    ChallengesBrowseView()
                } label: {
                    QuickActionCard(
                        icon: "trophy.fill",
                        title: "Join a Challenge",
                        description: "Compete with the community",
                        color: DS.Semantic.brand
                    )
                }

                if let vm = battlesVM {
                    @Bindable var bindableVM = vm
                    Button {
                        vm.openCreateBattle()
                    } label: {
                        QuickActionCard(
                            icon: "bolt.fill",
                            title: "Challenge a Friend",
                            description: "Start a 1v1 battle",
                            color: DS.Semantic.accentWarm
                        )
                    }
                    .sheet(isPresented: $bindableVM.showCreateBattle) {
                        CreateBattleView(viewModel: vm)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Components
struct CompeteStatTile: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title.bold())
                .foregroundStyle(DS.Semantic.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }
}

struct CompactChallengeCard: View {
    let challenge: ChallengeWithProgress
    let viewModel: ChallengesViewModel

    var body: some View {
        Button {
            viewModel.openChallengeDetail(challenge)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.challenge.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(challenge.userProgressPercentage)%")
                        .font(.headline.bold())
                        .foregroundStyle(DS.Semantic.brand)

                    let daysRemaining = challenge.challenge.daysRemaining
                    if daysRemaining > 0 {
                        Text("\(daysRemaining)d left")
                            .font(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
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

    private var progressText: String {
        let currentValue = challenge.userProgress
        let goalValue = challenge.challenge.goalValue

        switch challenge.challenge.challengeType {
        case .workoutCount:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber)) workouts"
        case .totalVolume:
            let current = Int(truncating: currentValue as NSDecimalNumber)
            let goal = Int(truncating: goalValue as NSDecimalNumber)
            return "\(current / 1000)K/\(goal / 1000)K kg"
        case .streak:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber)) days"
        case .specificExercise:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber))"
        case .custom:
            return "\(Int(truncating: currentValue as NSDecimalNumber))/\(Int(truncating: goalValue as NSDecimalNumber)) \(challenge.challenge.goalMetric)"
        }
    }
}

struct CompactBattleCard: View {
    let battle: BattleWithParticipants
    let viewModel: BattleViewModel

    var body: some View {
        Button {
            viewModel.openBattleDetail(battle)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(battleTypeLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(scoreText)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if viewModel.isCurrentUserWinning(for: battle) {
                        Label("Winning", systemImage: "crown.fill")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.brand)
                    } else {
                        Label("Behind", systemImage: "arrow.up")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    let daysRemaining = battle.battle.daysRemaining
                    if daysRemaining > 0 {
                        Text("\(daysRemaining)d left")
                            .font(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(
                viewModel.isCurrentUserWinning(for: battle)
                    ? DS.Semantic.brandSoft
                    : DS.Semantic.card
            )
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(
                        viewModel.isCurrentUserWinning(for: battle)
                            ? DS.Semantic.brand.opacity(0.3)
                            : DS.Semantic.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var battleTypeLabel: String {
        switch battle.battle.battleType {
        case .volume:
            return "Volume Battle"
        case .workoutCount:
            return "Workout Battle"
        case .consistency:
            return "Consistency Battle"
        case .exercise:
            return "Exercise Battle"
        case .pr:
            return "PR Battle"
        }
    }

    private var scoreText: String {
        let yourScore = viewModel.getCurrentUserScore(for: battle)
        let opponentScore = viewModel.getOpponentScore(for: battle)

        switch battle.battle.battleType {
        case .volume:
            return "\((yourScore / 1000).safeInt)K vs \((opponentScore / 1000).safeInt)K kg"
        case .workoutCount, .consistency, .exercise, .pr:
            return "\(Int(yourScore)) vs \(Int(opponentScore))"
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
    }
}
