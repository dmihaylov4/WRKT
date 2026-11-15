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
    static func perform<Value>(snapshot: Value, operation: @escaping @MainActor () async -> (Value, failed: Bool), apply: @escaping @MainActor (Value) -> Void) async {
        let work = Task { @MainActor in
            let result = await operation()
            apply(CutCompeteLogic.refreshed(snapshot, candidate: result.0, failed: result.failed || Task.isCancelled))
        }
        await work.value
    }
    static func battles(_ vm: BattleViewModel) async {
        await perform(snapshot: (vm.activeBattles, vm.pendingBattles, vm.completedBattles), operation: {
            await vm.refresh()
            return ((vm.activeBattles, vm.pendingBattles, vm.completedBattles), failed: vm.error != nil)
        }, apply: { (vm.activeBattles, vm.pendingBattles, vm.completedBattles) = $0 })
    }
    static func challenges(_ vm: ChallengesViewModel) async {
        await perform(snapshot: (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges), operation: {
            await vm.refresh()
            return ((vm.activeChallenges, vm.availableChallenges, vm.completedChallenges), failed: vm.error != nil)
        }, apply: { (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges) = $0 })
    }
}

extension CutCompeteItem {
    static func challenge(_ value: ChallengeWithProgress, unit: WeightUnit, locale: Locale = .current, showsDescription: Bool = false) -> CutCompeteItem {
        CutCompeteLogic.challenge(.init(value, userID: nil), unit: unit, locale: locale, showsDescription: showsDescription)
    }
}
