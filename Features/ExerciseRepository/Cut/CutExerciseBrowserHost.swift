import SwiftUI

struct CutExerciseBrowserHost: View {
    @Binding var state: BrowseState
    let subregion: String?
    var muscleFilter: MuscleFilter?
    var navigationPath: Binding<NavigationPath>?
    @EnvironmentObject private var repo: ExerciseRepository
    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var customStore: CustomExerciseStore
    @StateObject private var onboarding = OnboardingManager.shared
    @State private var filters = CutExerciseBrowserFilters()
    @State private var searchText = ""
    @State private var debounce: Task<Void, Never>?
    @State private var filtersExpanded = false
    @State private var expandedSuggestions: Set<String> = []
    @State private var cachedModel: CutExerciseBrowserModel?
    @State private var session: SessionSheetContext?
    @State private var creating = false
    @State private var frames = CutExerciseTutorialFrames()
    @State private var tutorialIndex = 0
    @State private var showingTutorial = false

    var body: some View {
        CutExerciseBrowserView(
            model: cachedModel ?? CutExerciseBrowserLogic.model(exercises: [], subregion: subregion,
                muscleFilter: muscleFilter, filters: filters, favorites: favorites.ids),
            searchText: searchText, filtersExpanded: filtersExpanded, expandedSuggestions: expandedSuggestions,
            tutorial: showingTutorial ? CutExerciseTutorialLogic.step(tutorialIndex, frames: frames) : nil,
            actions: actions
        )
        .onAppear {
            refresh()
            // First-use tips must measure the actual filters, not spotlight zero frames
            // after a timeout while the controls are still collapsed.
            if !onboarding.hasSeenBodyBrowse { filtersExpanded = true }
        }
        .onDisappear { debounce?.cancel() }
        .onChange(of: filters) { _, _ in refresh() }
        .onChange(of: favorites.ids) { _, _ in refresh() }
        .onReceive(repo.$exercises) { _ in refresh() }
        .onChange(of: repo.didLoadFull) { _, _ in refresh() }
        .onChange(of: frames.isReady) { _, ready in
            if ready && !onboarding.hasSeenBodyBrowse { showingTutorial = true }
        }
        .sheet(item: $session) { context in
            ExerciseSessionView(exercise: context.exercise,
                                initialEntryID: store.existingEntry(for: context.exercise.id)?.id,
                                returnToHomeOnSave: true)
                .environmentObject(store)
        }
        .sheet(isPresented: $creating) {
            CreateExerciseView(preselectedMuscle: filters.muscle ?? subregion ?? "")
                .environmentObject(customStore)
                .environmentObject(repo)
        }
    }

    private func refresh() {
        let scope = subregion.map { Set(repo.exercisesForMuscle($0).map(\.id)) }
        let selected = filters.muscle.map { Set(repo.exercisesForMuscle($0).map(\.id)) }
        cachedModel = CutExerciseBrowserLogic.model(exercises: Array(repo.byID.values), subregion: subregion,
            muscleFilter: muscleFilter, filters: filters, scopedIDs: scope, selectedMuscleIDs: selected,
            favorites: favorites.ids)
    }

    private var actions: CutExerciseBrowserActions {
        .init(search: { text in
            searchText = text
            debounce?.cancel()
            debounce = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard !Task.isCancelled, searchText == text else { return }
                filters.query = text
            }
        }, toggleSearch: {
            filters.isSearching = true
            Haptics.light()
        }, cancelSearch: {
            debounce?.cancel()
            filters.isSearching = false
            filters.query = ""
            searchText = ""
            Haptics.light()
        }, toggleFilters: {
            filtersExpanded.toggle()
            Haptics.light()
        }, muscle: { filters.muscle = $0; Haptics.light() },
        equipment: { filters.equipment = $0; Haptics.light() },
        movement: { filters.movement = $0; Haptics.light() }, clear: {
            filters.equipment = .all
            filters.movement = .all
            if filters.isSearching {
                debounce?.cancel()
                filters.query = ""
                searchText = ""
            }
        }, open: { id in
            guard let exercise = repo.byID[id] else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            session = SessionSheetContext(id: UUID(), exercise: exercise)
        }, favorite: { id in
            favorites.toggle(id)
            Haptics.light()
        }, create: { creating = true }, toggleSuggestion: { muscle in
            if !expandedSuggestions.insert(muscle).inserted { expandedSuggestions.remove(muscle) }
        }, showAll: showAll, frame: { target, frame in
            guard !onboarding.hasSeenBodyBrowse else { return }
            frames.set(frame, for: target)
        }, nextTip: {
            if tutorialIndex < 3 { tutorialIndex += 1 } else { completeTutorial() }
        }, skipTips: completeTutorial)
    }

    private func showAll(_ muscle: String) {
        debounce?.cancel()
        filters.isSearching = false
        filters.query = ""
        searchText = ""
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Haptics.light()
        // One navigation transaction after resigning focus: do not send two path updates.
        DispatchQueue.main.async {
            if let navigationPath {
                var path = navigationPath.wrappedValue
                if !path.isEmpty { path.removeLast() }
                path.append(BrowseRoute.subregion(muscle))
                navigationPath.wrappedValue = path
            } else {
                state = .subregion(muscle)
            }
        }
    }

    private func completeTutorial() {
        onboarding.complete(.bodyBrowse)
        showingTutorial = false
        filtersExpanded = false
    }
}
