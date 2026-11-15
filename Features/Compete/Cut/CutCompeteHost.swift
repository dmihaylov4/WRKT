import SwiftUI

struct CutCompeteHost: View {
    @Environment(\.dependencies) private var deps
    @State private var challengesVM: ChallengesViewModel?
    @State private var battlesVM: BattleViewModel?
    @State private var browsing = false
    @State private var pending = false
    @State private var processing: Set<UUID> = []
    @State private var frozenModel: CutCompeteModel?
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var model: CutCompeteModel {
        let userID = deps.authService.currentUser?.id
        func battles(_ values: [BattleWithParticipants]) -> [CutCompeteItem] {
            values.map { CutCompeteLogic.battle(.init($0, userID: userID), unit: unit) }
        }
        func challenges(_ values: [ChallengeWithProgress]) -> [CutCompeteItem] {
            values.map { CutCompeteItem.challenge($0, unit: unit) }
        }
        return CutCompeteLogic.model(pending: battles(battlesVM?.pendingBattles ?? []), battles: battles(battlesVM?.activeBattles ?? []),
            challenges: challenges(challengesVM?.activeChallenges ?? []), available: challenges(challengesVM?.availableChallenges ?? []),
            completedBattles: battles(battlesVM?.completedBattles ?? []), completedChallenges: challenges(challengesVM?.completedChallenges ?? []),
            loading: challengesVM == nil || battlesVM == nil || challengesVM?.isLoading == true || battlesVM?.isLoading == true,
            error: [challengesVM?.error?.message, battlesVM?.error?.message].compactMap { $0 }.first)
    }
    var body: some View {
        CutCompeteView(model: frozenModel ?? model, processing: processing, actions: .init(open: open, accept: { id in act(id, accept: true) },
            decline: { id in act(id, accept: false) }, startBattle: { battlesVM?.openCreateBattle() }, browse: { browsing = true },
            allPending: { pending = true }, retry: { Task { await refresh() } }))
        .task {
            guard challengesVM == nil else { return }
            let challenges = ChallengesViewModel(challengeRepository: deps.challengeRepository, authService: deps.authService, workoutStore: deps.workoutStore)
            let battles = BattleViewModel(battleRepository: deps.battleRepository, authService: deps.authService)
            challengesVM = challenges
            battlesVM = battles
            await challenges.onAppear()
            await battles.onAppear()
        }
        .sheet(item: Binding(get: { challengesVM?.selectedChallenge }, set: { _ in challengesVM?.closeChallengeDetail() }), onDismiss: {
            Task { await refresh(challenges: true, battles: false) }
        }) { challenge in
            if let vm = challengesVM { ChallengeDetailView(challenge: challenge, viewModel: vm) }
        }
        .sheet(item: Binding(get: { battlesVM?.selectedBattle }, set: { _ in battlesVM?.closeBattleDetail() }), onDismiss: {
            Task { await refresh(challenges: false, battles: true) }
        }) { battle in
            if let vm = battlesVM { BattleDetailView(battle: battle, viewModel: vm) }
        }
        .sheet(isPresented: Binding(get: { battlesVM?.showCreateBattle ?? false }, set: { if !$0 { battlesVM?.closeCreateBattle() } })) {
            if let vm = battlesVM { CreateBattleView(viewModel: vm) }
        }
        .navigationDestination(isPresented: $browsing) { ChallengesBrowseView(initialTab: .browse) }
        .navigationDestination(isPresented: $pending) { BattlesListView() }
        .onReceive(NotificationCenter.default.publisher(for: .openBattleCreateSheet)) { _ in battlesVM?.openCreateBattle() }
    }
    private func open(_ target: CutCompeteItem.Target) {
        switch target {
        case .battle(let id):
            if let vm = battlesVM, let battle = (vm.pendingBattles + vm.activeBattles + vm.completedBattles).first(where: { $0.id == id }) { vm.openBattleDetail(battle) }
        case .challenge(let id):
            if let vm = challengesVM, let challenge = (vm.activeChallenges + vm.availableChallenges + vm.completedChallenges).first(where: { $0.id == id }) { vm.openChallengeDetail(challenge) }
        }
    }
    private func act(_ id: UUID, accept: Bool) {
        guard let vm = battlesVM, let battle = vm.pendingBattles.first(where: { $0.id == id }), !processing.contains(id) else { return }
        processing.insert(id)
        Task {
            if accept { await vm.acceptBattle(battle.battle) } else { await vm.declineBattle(battle.battle) }
            processing.remove(id)
        }
    }
    private func refresh(challenges: Bool = true, battles: Bool = true) async {
        guard frozenModel == nil else { return }
        frozenModel = model
        defer { frozenModel = nil }
        if challenges, let vm = challengesVM { await CutCompeteRefresh.challenges(vm) }
        if battles, let vm = battlesVM { await CutCompeteRefresh.battles(vm) }
    }
}

/// Keep the loaded snapshot if a multi-request VM refresh fails partway through.
/// The unstructured task also survives cancellation of a SwiftUI refreshable owner.
@MainActor
enum CutCompeteRefresh {
    static func battles(_ vm: BattleViewModel) async {
        let work = Task { @MainActor in
            let previous = (vm.activeBattles, vm.pendingBattles, vm.completedBattles)
            await vm.refresh()
            (vm.activeBattles, vm.pendingBattles, vm.completedBattles) = CutCompeteLogic.refreshed(previous,
                candidate: (vm.activeBattles, vm.pendingBattles, vm.completedBattles), failed: vm.error != nil || Task.isCancelled)
        }
        await work.value
    }
    static func challenges(_ vm: ChallengesViewModel) async {
        let work = Task { @MainActor in
            let previous = (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges)
            await vm.refresh()
            (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges) = CutCompeteLogic.refreshed(previous,
                candidate: (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges), failed: vm.error != nil || Task.isCancelled)
        }
        await work.value
    }
}

extension CutCompeteItem {
    static func challenge(_ value: ChallengeWithProgress, unit: WeightUnit, locale: Locale = .current, showsDescription: Bool = false) -> CutCompeteItem {
        let c = value.challenge
        let detail = CutChallengeDetailLogic.model(.init(value, userID: nil), unit: unit, locale: locale)
        let amount = detail.about.first { $0.label == "Goal" }?.value ?? ""
        let kind = ChallengeRewardPreviewKind(challenge: c)
        return .init(id: .challenge(c.id), title: c.title, subtitle: [c.difficulty?.displayName, c.participantCount > 0 ? "\(c.participantCount) competing" : amount].compactMap { $0 }.joined(separator: " · "),
            value: detail.progress,
            trailing: value.isCompleted ? "Completed" : c.daysRemainingDisplay,
            note: showsDescription ? c.description : nil, progressLabel: detail.percentage,
            fraction: value.isParticipating ? Double(value.userProgressPercentage) / 100 : nil,
            plateTier: kind == .conditioningPlate ? 24 : nil, barSkinID: kind == .firstRepBarSkin ? 4 : nil,
            reward: kind == .firstRepBarSkin ? "VOLIA bar skin" : kind == .conditioningPlate ? "Heat Forge plate" : nil)
    }
}
