import SwiftUI

struct CutExercisePickerHost: View {
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: ExerciseRepository
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var region = CutExercisePickerModel.Region.all
    @State private var searchText = ""
    @State private var query = ""
    @State private var displayedCount = CutExercisePickerLogic.pageSize
    @State private var debounce: Task<Void, Never>?
    @State private var cachedModel: CutExercisePickerModel?

    var body: some View {
        NavigationStack {
            CutExercisePickerView(model: model, searchText: searchText, actions: .init(search: search,
                region: { region = $0; displayedCount = CutExercisePickerLogic.pageSize; refresh() },
                select: select, loadMore: {
                    displayedCount = CutExercisePickerLogic.nextPage(displayedCount: displayedCount, totalCount: model.totalCount)
                    refresh()
                }, cancel: { dismiss() }))
        }
        .onAppear(perform: refresh)
        .onReceive(repo.$exercises) { _ in refresh() }
        .onChange(of: repo.didLoadFull) { _, _ in refresh() }
        .onChange(of: favorites.ids) { _, _ in refresh() }
        .onDisappear { debounce?.cancel() }
    }

    private var model: CutExercisePickerModel {
        cachedModel ?? CutExercisePickerLogic.model(exercises: [], region: region, query: query,
                                                    favorites: favorites.ids, displayedCount: displayedCount)
    }

    private func refresh() {
        cachedModel = CutExercisePickerLogic.model(exercises: Array(repo.byID.values), region: region,
            query: query, favorites: favorites.ids, displayedCount: displayedCount)
    }

    private func search(_ text: String) {
        searchText = text
        debounce?.cancel()
        debounce = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled, searchText == text else { return }
            query = text
            displayedCount = CutExercisePickerLogic.pageSize
            refresh()
        }
    }

    private func select(_ id: String) {
        guard let exercise = CutExercisePickerLogic.selection(id, model: model, exercises: Array(repo.byID.values)) else { return }
        onSelect(exercise)
        dismiss()
    }
}
