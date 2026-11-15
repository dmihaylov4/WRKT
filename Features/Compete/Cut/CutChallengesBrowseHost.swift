import SwiftUI

struct CutChallengesBrowseHost: View {
    @Environment(\.dependencies) private var deps
    @State private var viewModel: ChallengesViewModel?
    @State private var tab: CutChallengesBrowseModel.Tab
    @State private var refreshing = false
    @State private var frozenRows: ([CutCompeteItem], [CutCompeteItem], [CutCompeteItem])?
    @AppStorage("weight_unit") private var weightUnitRaw = WeightUnit.kg.rawValue
    init(initialTab: ChallengesBrowseView.ChallengeTab) {
        _tab = State(initialValue: initialTab == .browse ? .browse : initialTab == .completed ? .completed : .active)
    }
    private var model: CutChallengesBrowseModel {
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
        func rows(_ values: [ChallengeWithProgress], descriptions: Bool = false) -> [CutCompeteItem] { values.map { .challenge($0, unit: unit, showsDescription: descriptions) } }
        let values = frozenRows ?? (rows(viewModel?.activeChallenges ?? []), rows(viewModel?.availableChallenges ?? [], descriptions: true), rows(viewModel?.completedChallenges ?? [], descriptions: true))
        let presets = viewModel?.getFeaturedChallenges().map { CutChallengesBrowseModel.Preset(title: $0.title, description: $0.description, duration: "\($0.duration) days", difficulty: $0.difficulty.displayName) } ?? []
        return CutChallengesBrowseLogic.model(tab: tab, active: values.0, available: values.1, completed: values.2, presets: presets,
            loading: viewModel == nil || viewModel?.isLoading == true, error: viewModel?.error?.message)
    }
    var body: some View {
        CutChallengesBrowseView(model: model, select: { tab = $0; Haptics.light() }, open: { id in
            guard let vm = viewModel, let item = (vm.activeChallenges + vm.availableChallenges + vm.completedChallenges).first(where: { $0.id == id }) else { return }
            vm.openChallengeDetail(item)
        }, openPreset: { title in
            guard let vm = viewModel, let preset = vm.getFeaturedChallenges().first(where: { $0.title == title }) else { return }
            Task { await vm.openOrCreateChallengeFromPreset(preset) }
        }, retry: { Task { await refresh() } }, refresh: refresh)
        .navigationTitle("Challenges").navigationBarTitleDisplayMode(.inline)
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
    private func refresh() async {
        guard let vm = viewModel, !refreshing else { return }
        refreshing = true
        let unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
        func rows(_ values: [ChallengeWithProgress], descriptions: Bool = false) -> [CutCompeteItem] { values.map { .challenge($0, unit: unit, showsDescription: descriptions) } }
        frozenRows = (rows(vm.activeChallenges), rows(vm.availableChallenges, descriptions: true), rows(vm.completedChallenges, descriptions: true))
        await CutCompeteRefresh.challenges(vm)
        frozenRows = nil
        refreshing = false
    }
}
