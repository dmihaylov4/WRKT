import SwiftUI

struct CutBattlesListHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: BattleViewModel?
    @State private var tab: CutBattlesListModel.Tab = .active
    @State private var processing: Set<UUID> = []
    @State private var refreshing = false
    @State private var frozenRows: ([CutCompeteItem], [CutCompeteItem], [CutCompeteItem])?
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    private var model: CutBattlesListModel {
        func rows(_ values: [BattleWithParticipants]) -> [CutCompeteItem] {
            values.map { CutCompeteLogic.battle(.init($0, userID: deps.authService.currentUser?.id), unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg) }
        }
        let snapshot = frozenRows ?? (rows(viewModel?.activeBattles ?? []), rows(viewModel?.pendingBattles ?? []), rows(viewModel?.completedBattles ?? []))
        return CutBattlesListLogic.model(tab: tab, active: snapshot.0, pending: snapshot.1, completed: snapshot.2,
            loading: viewModel == nil || viewModel?.isLoading == true, error: viewModel?.error?.message)
    }
    var body: some View {
        // Both existing entry points push this screen on Compete's navigation stack.
        Group {
            CutBattlesListView(model: model, processing: processing, select: { tab = $0; Haptics.light() }, actions: .init(open: open,
                accept: { act($0, accept: true) }, decline: { act($0, accept: false) }, startBattle: { viewModel?.openCreateBattle() },
                retry: { Task { await refresh() } }), refresh: refresh)
            .navigationTitle("Battles").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Create battle", systemImage: "plus") { viewModel?.openCreateBattle() }.tint(DS.Cut.Colors.lime).disabled(viewModel == nil)
            } }
            .task {
                guard viewModel == nil else { return }
                let vm = BattleViewModel(battleRepository: deps.battleRepository, authService: deps.authService)
                viewModel = vm
                await vm.onAppear()
            }
            .sheet(isPresented: Binding(get: { viewModel?.showBattleDetail ?? false }, set: { if !$0 { viewModel?.closeBattleDetail() } })) {
                if let vm = viewModel, let battle = vm.selectedBattle { BattleDetailView(battle: battle, viewModel: vm) }
            }
            .sheet(isPresented: Binding(get: { viewModel?.showCreateBattle ?? false }, set: { if !$0 { viewModel?.closeCreateBattle() } })) {
                if let vm = viewModel { CreateBattleView(viewModel: vm) }
            }
            .alert(item: Binding(get: { viewModel?.error }, set: { _ in viewModel?.error = nil })) { error in
                Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
        }
    }
    private func open(_ target: CutCompeteItem.Target) {
        guard case .battle(let id) = target, let vm = viewModel,
              let battle = (vm.activeBattles + vm.pendingBattles + vm.completedBattles).first(where: { $0.id == id }) else { return }
        vm.openBattleDetail(battle)
    }
    private func act(_ id: UUID, accept: Bool) {
        guard let vm = viewModel, let battle = vm.pendingBattles.first(where: { $0.id == id }), !processing.contains(id) else { return }
        processing.insert(id)
        Task {
            if accept { await vm.acceptBattle(battle.battle) } else { await vm.declineBattle(battle.battle) }
            processing.remove(id)
        }
    }
    private func refresh() async {
        guard let vm = viewModel, !refreshing else { return }
        refreshing = true
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
        func rows(_ items: [BattleWithParticipants]) -> [CutCompeteItem] { items.map { CutCompeteLogic.battle(.init($0, userID: deps.authService.currentUser?.id), unit: unit) } }
        frozenRows = (rows(vm.activeBattles), rows(vm.pendingBattles), rows(vm.completedBattles))
        await CutCompeteRefresh.battles(vm)
        frozenRows = nil
        refreshing = false
    }
}
