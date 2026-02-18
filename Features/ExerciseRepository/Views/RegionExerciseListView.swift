//
//  RegionExerciseListView.swift
//  WRKT
//
//  Display ALL exercises for a body region (upper/lower) with two-tier filtering
//

import SwiftUI

struct RegionExerciseListView: View {
    let bodyRegion: BodyRegion

    @EnvironmentObject private var store: WorkoutStoreV2
    @EnvironmentObject private var customStore: CustomExerciseStore
    @EnvironmentObject private var favs: FavoritesStore
    private let repo = ExerciseRepository.shared

    // Filter state
    @State private var selectedMuscle: String? = nil
    @State private var selectedDeepFilter: String? = nil
    @State private var equipmentFilter: EquipBucket = .all
    @State private var movementFilter: MoveBucket = .all
    @State private var isSecondaryFiltersExpanded = false

    // Search state
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?

    // Sheet presentation
    @State private var showingSessionFor: SessionSheetContext?
    @State private var showingCreateExercise = false

    // Filtered exercises (cached)
    @State private var filteredExercises: [Exercise] = []
    @State private var filterTask: Task<Void, Never>?

    var body: some View {
        contentView
            .modifier(FilterChangeModifier(
                selectedMuscle: selectedMuscle,
                selectedDeepFilter: selectedDeepFilter,
                equipmentFilter: equipmentFilter,
                movementFilter: movementFilter,
                searchText: searchText,
                debouncedSearchText: debouncedSearchText,
                favIds: favs.ids,
                customExercisesCount: customStore.customExercises.count,
                onFilterChange: updateFilters,
                onSearchTextChange: handleSearchTextChange
            ))
    }

    private var contentView: some View {
        exerciseListView
            .toolbar { toolbarContent }
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .top) { topSafeAreaContent }
            .sheet(item: $showingSessionFor) { ctx in
                sessionSheet(ctx)
            }
            .sheet(isPresented: $showingCreateExercise) {
                createSheet
            }
    }

    private func sessionSheet(_ ctx: SessionSheetContext) -> some View {
        ExerciseSessionView(
            exercise: ctx.exercise,
            initialEntryID: store.existingEntry(for: ctx.exercise.id)?.id,
            returnToHomeOnSave: true
        )
        .environmentObject(store)
    }

    private var createSheet: some View {
        CreateExerciseView(preselectedMuscle: selectedMuscle ?? "")
            .environmentObject(customStore)
            .environmentObject(repo)
    }

    // MARK: - View Components

    private var exerciseListView: some View {
        List {
            ForEach(filteredExercises, id: \.id) { exercise in
                exerciseRowView(exercise)
            }

            if filteredExercises.isEmpty {
                emptyStateView
            }
        }
        .listStyle(.plain)
        .background(DS.Semantic.surface)
        .animation(.default, value: filteredExercises.map { $0.id })
        .navigationTitle(bodyRegion == .upper ? "Upper Body" : "Lower Body")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exerciseRowView(_ exercise: Exercise) -> some View {
        ExerciseRow(exercise: exercise)
            .contentShape(Rectangle())
            .onTapGesture { openSession(for: exercise) }
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Semantic.surface)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyStateView: some View {
        EmptyStateView(
            isSearching: isSearching,
            searchText: searchText,
            hasFiltersApplied: hasFiltersApplied,
            onClearFilters: clearAllFilters
        )
        .listRowSeparator(.hidden)
        .listRowBackground(DS.Semantic.surface)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if !isSearching {
                    searchButton
                }
                createButton
            }
            .tint(DS.Palette.marone)
        }
    }

    private var searchButton: some View {
        Button {
            isSearching = true
            searchFocused = true
            Haptics.light()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3)
        }
        .accessibilityLabel("Search exercises")
    }

    private var createButton: some View {
        Button {
            showingCreateExercise = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
        .accessibilityLabel("Create custom exercise")
    }

    @ViewBuilder
    private var topSafeAreaContent: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBarView
            } else {
                filterBarView
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSearching)
        .background(DS.Semantic.surface)
    }

    private var searchBarView: some View {
        ExerciseSearchBar(
            text: $searchText,
            isFocused: $searchFocused,
            onCancel: {
                searchFocused = false
                isSearching = false
                searchText = ""
                debouncedSearchText = ""
                Haptics.light()
            }
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
        .zIndex(1)
    }

    private var filterBarView: some View {
        VStack(spacing: 12) {
            TwoTierFilterBar(
                bodyRegion: bodyRegion,
                selectedMuscle: $selectedMuscle,
                selectedDeepFilter: $selectedDeepFilter,
                equipment: $equipmentFilter,
                movement: $movementFilter,
                isSecondaryExpanded: $isSecondaryFiltersExpanded
            )
            .padding(.top, 8)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
        .zIndex(0)
    }

    // MARK: - Helper Methods

    private func handleSearchTextChange(_ newValue: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedSearchText = newValue
            }
        }
    }

    // MARK: - Filtering Logic

    private func updateFilters() {
        // Cancel previous filter task
        filterTask?.cancel()

        filterTask = Task {
            var exercises = repo.exercises

            // Step 1: Filter by body region
            let regionMuscles = MuscleTaxonomy.subregions(for: bodyRegion)
            exercises = exercises.filter { exercise in
                let muscles = exercise.primaryMuscles + exercise.secondaryMuscles
                return muscles.contains { muscle in
                    regionMuscles.contains { subregion in
                        let keys = MuscleMapper.synonyms(for: subregion)
                        return keys.contains { key in
                            muscle.lowercased().contains(key.lowercased())
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }

            // Step 2: Search filter (if searching) - use smart fuzzy search
            if isSearching && !debouncedSearchText.isEmpty {
                exercises = exercises.filter { SmartSearch.matches(query: debouncedSearchText, in: $0.name) }
                    .sorted { SmartSearch.score(query: debouncedSearchText, in: $0.name) >
                             SmartSearch.score(query: debouncedSearchText, in: $1.name) }

                guard !Task.isCancelled else { return }

                // When searching, skip muscle/equipment/movement filters
                await MainActor.run {
                    filteredExercises = exercises
                }
                return
            }

            // Step 3: Filter by selected muscle group (if any and not searching)
            if let muscle = selectedMuscle {
                let keys = MuscleMapper.synonyms(for: muscle)
                exercises = exercises.filter { exercise in
                    let muscles = exercise.primaryMuscles + exercise.secondaryMuscles
                    return muscles.contains { m in
                        keys.contains { key in
                            m.lowercased().contains(key.lowercased())
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }

            // Step 4: Filter by deep subregion (if any)
            if let deep = selectedDeepFilter {
                // Use deep filter matching logic
                let deepKeys = MuscleMapper.deepSynonyms(for: selectedMuscle ?? "", deep: deep)
                exercises = exercises.filter { exercise in
                    let muscles = exercise.primaryMuscles + exercise.secondaryMuscles
                    return muscles.contains { m in
                        deepKeys.contains { key in
                            m.lowercased().contains(key.lowercased())
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }

            // Step 5: Apply equipment filter (only when not searching)
            if equipmentFilter != .all {
                exercises = exercises.filter { exercise in
                    guard let equipment = exercise.equipment else { return false }
                    return equipment.lowercased() == equipmentFilter.rawValue.lowercased()
                }
            }

            guard !Task.isCancelled else { return }

            // Step 6: Apply movement filter (only when not searching)
            if movementFilter != .all {
                exercises = exercises.filter { exercise in
                    movementFilter.matches(exercise)
                }
            }

            guard !Task.isCancelled else { return }

            // Sort by favorites first, then alphabetically
            exercises.sort { lhs, rhs in
                let lhsFav = FavoritesStore.shared.contains(lhs.id)
                let rhsFav = FavoritesStore.shared.contains(rhs.id)
                if lhsFav != rhsFav {
                    return lhsFav
                }
                return lhs.name < rhs.name
            }

            await MainActor.run {
                filteredExercises = exercises
            }
        }
    }

    private var hasFiltersApplied: Bool {
        selectedMuscle != nil ||
        selectedDeepFilter != nil ||
        equipmentFilter != .all ||
        movementFilter != .all
    }

    private func clearAllFilters() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedMuscle = nil
            selectedDeepFilter = nil
            equipmentFilter = .all
            movementFilter = .all
            // Also clear search if active
            if isSearching {
                searchText = ""
                debouncedSearchText = ""
            }
        }
        Haptics.light()
    }

    private func openSession(for exercise: Exercise) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showingSessionFor = SessionSheetContext(id: UUID(), exercise: exercise)
    }
}

// MARK: - Exercise Row Component

private struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(exercise.name)
                        .font(.body)
                    if exercise.isCustom {
                        CustomExerciseBadge()
                    }
                }
                if let mechanic = exercise.mechanic {
                    MechanicPill(mechanic: mechanic)
                }
            }
            Spacer(minLength: 8)
            FavoriteHeartButton(exerciseID: exercise.id)
        }
    }
}

// MARK: - Empty State Component

private struct EmptyStateView: View {
    let isSearching: Bool
    let searchText: String
    let hasFiltersApplied: Bool
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Exercises Found")
                .font(.headline)

            if isSearching {
                Text("No exercises match '\(searchText)'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if hasFiltersApplied {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    onClearFilters()
                } label: {
                    Text("Clear All Filters")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.marone)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(DS.Palette.marone.opacity(0.15))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                Text("No exercises available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Filter Change ViewModifier

private struct FilterChangeModifier: ViewModifier {
    let selectedMuscle: String?
    let selectedDeepFilter: String?
    let equipmentFilter: EquipBucket
    let movementFilter: MoveBucket
    let searchText: String
    let debouncedSearchText: String
    let favIds: Set<String>
    let customExercisesCount: Int
    let onFilterChange: () -> Void
    let onSearchTextChange: (String) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(FilterStateChangeModifier(
                selectedMuscle: selectedMuscle,
                selectedDeepFilter: selectedDeepFilter,
                equipmentFilter: equipmentFilter,
                movementFilter: movementFilter,
                onFilterChange: onFilterChange
            ))
            .modifier(SearchChangeModifier(
                searchText: searchText,
                debouncedSearchText: debouncedSearchText,
                favIds: favIds,
                customExercisesCount: customExercisesCount,
                onFilterChange: onFilterChange,
                onSearchTextChange: onSearchTextChange
            ))
    }
}

private struct FilterStateChangeModifier: ViewModifier {
    let selectedMuscle: String?
    let selectedDeepFilter: String?
    let equipmentFilter: EquipBucket
    let movementFilter: MoveBucket
    let onFilterChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onFilterChange)
            .onChange(of: selectedMuscle) { _, _ in onFilterChange() }
            .onChange(of: selectedDeepFilter) { _, _ in onFilterChange() }
            .onChange(of: equipmentFilter) { _, _ in onFilterChange() }
            .onChange(of: movementFilter) { _, _ in onFilterChange() }
    }
}

private struct SearchChangeModifier: ViewModifier {
    let searchText: String
    let debouncedSearchText: String
    let favIds: Set<String>
    let customExercisesCount: Int
    let onFilterChange: () -> Void
    let onSearchTextChange: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: searchText) { _, newValue in onSearchTextChange(newValue) }
            .onChange(of: debouncedSearchText) { _, _ in onFilterChange() }
            .onChange(of: favIds) { _, _ in onFilterChange() }
            .onChange(of: customExercisesCount) { _, _ in onFilterChange() }
    }
}

// MARK: - Muscle Mapper Helper Extension

extension MuscleMapper {
    static func deepSynonyms(for muscle: String, deep: String) -> [String] {
        // Map deep subregions to search keywords
        let muscleLower = muscle.lowercased()
        let deepLower = deep.lowercased()

        if muscleLower.contains("chest") {
            switch deepLower {
            case "upper chest", "upper":
                return ["upper", "incline", "clavicular"]
            case "mid chest", "mid":
                return ["middle", "mid", "flat", "sternal"]
            case "lower chest", "lower":
                return ["lower", "decline", "abdominal"]
            default:
                return [deepLower]
            }
        } else if muscleLower.contains("back") {
            switch deepLower {
            case "lats", "latissimus":
                return ["lat", "latissimus", "dorsi"]
            case "mid-back", "mid back":
                return ["rhomboid", "mid", "middle"]
            case "lower back":
                return ["lower back", "lumbar", "erector"]
            case "traps/rear delts", "traps", "rear delts":
                return ["trap", "trapezius", "rear delt", "posterior delt"]
            default:
                return [deepLower]
            }
        }

        return [deepLower]
    }
}

// MARK: - Preview

#Preview("Upper Body") {
    NavigationStack {
        RegionExerciseListView(bodyRegion: .upper)
            .environmentObject(WorkoutStoreV2(repo: .shared))
            .environmentObject(CustomExerciseStore.shared)
            .environmentObject(FavoritesStore.shared)
    }
}

#Preview("Lower Body") {
    NavigationStack {
        RegionExerciseListView(bodyRegion: .lower)
            .environmentObject(WorkoutStoreV2(repo: .shared))
            .environmentObject(CustomExerciseStore.shared)
            .environmentObject(FavoritesStore.shared)
    }
}
