import SwiftUI

struct CutChallengesBrowseHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: ChallengesViewModel?
    @State private var tab: CutChallengesBrowseModel.Tab
    @State private var refreshing = false
    @State private var joining: Set<UUID> = []
    @State private var frozenRows: ([CutCompeteItem], [CutCompeteItem], [CutCompeteItem])?
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    init(initialTab: ChallengesBrowseView.ChallengeTab) {
        _tab = State(initialValue: initialTab == .browse ? .browse : initialTab == .completed ? .completed : .active)
    }
    private var model: CutChallengesBrowseModel {
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
        func rows(_ values: [ChallengeWithProgress]) -> [CutCompeteItem] { values.map { .challenge($0, unit: unit) } }
        let values = frozenRows ?? (rows(viewModel?.activeChallenges ?? []), rows(viewModel?.availableChallenges ?? []), rows(viewModel?.completedChallenges ?? []))
        let presets = viewModel?.getFeaturedChallenges().map { CutChallengesBrowseModel.Preset(title: $0.title, description: $0.description, duration: "\($0.duration) days", difficulty: $0.difficulty.displayName) } ?? []
        return CutChallengesBrowseLogic.model(tab: tab, active: values.0, available: values.1, completed: values.2, presets: presets,
            loading: viewModel == nil || viewModel?.isLoading == true, error: viewModel?.error?.message)
    }
    var body: some View {
        CutChallengesBrowseView(model: model, processing: joining, select: { tab = $0; Haptics.light() }, open: { id in
            guard let vm = viewModel, let item = (vm.activeChallenges + vm.availableChallenges + vm.completedChallenges).first(where: { $0.id == id }) else { return }
            vm.openChallengeDetail(item)
        }, join: join, openPreset: { title in
            guard let vm = viewModel, let preset = vm.getFeaturedChallenges().first(where: { $0.title == title }) else { return }
            Task { await reload(preset: preset) }
        }, retry: { Task { await refresh() } }, refresh: refresh)
        .navigationTitle("Challenges").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task {
            guard viewModel == nil else { return }
            let vm = ChallengesViewModel(challengeRepository: deps.challengeRepository, authService: deps.authService, workoutStore: deps.workoutStore)
            viewModel = vm
            await vm.onAppear()
        }
        .sheet(item: Binding(get: { viewModel?.selectedChallenge }, set: { _ in viewModel?.closeChallengeDetail() }), onDismiss: { Task { await refresh() } }) { challenge in
            if let vm = viewModel { ChallengeDetailView(challenge: challenge, viewModel: vm) }
        }
        .alert(item: Binding(get: { viewModel?.error }, set: { _ in viewModel?.error = nil })) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
    /// Join on a row opens the challenge's detail, where the join is made.
    private func join(_ id: UUID) {
        guard let vm = viewModel, let item = vm.availableChallenges.first(where: { $0.id == id }) else { return }
        vm.openChallengeDetail(item)
    }
    private func refresh() async { await reload(preset: nil) }
    private func reload(preset: PresetChallenge?) async {
        guard let vm = viewModel, !refreshing else { return }
        refreshing = true
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
        func rows(_ values: [ChallengeWithProgress]) -> [CutCompeteItem] { values.map { .challenge($0, unit: unit) } }
        frozenRows = (rows(vm.activeChallenges), rows(vm.availableChallenges), rows(vm.completedChallenges))
        if let preset {
            await CutCompeteRefresh.perform(snapshot: (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges), operation: {
                await vm.openOrCreateChallengeFromPreset(preset)
                return ((vm.activeChallenges, vm.availableChallenges, vm.completedChallenges), failed: vm.error != nil)
            }, apply: { (vm.activeChallenges, vm.availableChallenges, vm.completedChallenges) = $0 })
        } else {
            await CutCompeteRefresh.challenges(vm)
        }
        frozenRows = nil
        refreshing = false
    }
}
