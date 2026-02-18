//
//  ExercisePickerView.swift
//  WRKT
//
//  Exercise picker for adding exercises to planned workouts
//

import SwiftUI
import Combine

struct ExercisePickerView: View {
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var favs: FavoritesStore

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedRegion: MuscleRegion? = nil
    @State private var displayedCount = 50 // Start with 50 exercises
    @State private var searchDebounce: Task<Void, Never>? = nil
    @FocusState private var isSearchFocused: Bool

    // Cache filtered results to avoid recalculating on every render
    @State private var cachedFilteredExercises: [Exercise] = []

    enum MuscleRegion: String, CaseIterable, Identifiable {
        case upper = "Upper Body"
        case lower = "Lower Body"
        case all = "All Exercises"

        var id: String { rawValue }
    }

    // Full filtered list (now using cached state)
    private var allFilteredExercises: [Exercise] {
        cachedFilteredExercises
    }

    // Recalculate filtered exercises when filters change
    private func updateFilteredExercises() {
        var exercises = Array(repo.byID.values)

        // Filter by region
        if let region = selectedRegion, region != .all {
            let keywords: Set<String> = {
                switch region {
                case .upper:
                    return ["chest", "back", "shoulder", "bicep", "tricep", "forearm", "trap", "lat", "pec", "delt"]
                case .lower:
                    return ["quad", "hamstring", "glute", "calf", "adductor", "abductor", "hip", "leg"]
                case .all:
                    return []
                }
            }()

            exercises = exercises.filter { exercise in
                exercise.primaryMuscles.contains { muscle in
                    keywords.contains { muscle.lowercased().contains($0) }
                }
            }
        }

        // Filter by debounced search text
        if !debouncedSearchText.isEmpty {
            exercises = exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(debouncedSearchText)
            }
        }

        // Sort: favorites first, then alphabetically
        cachedFilteredExercises = favoritesFirst(exercises, favIDs: favs.ids)
    }

    // Paginated subset for display
    private var displayedExercises: [Exercise] {
        Array(allFilteredExercises.prefix(displayedCount))
    }

    private var hasMoreExercises: Bool {
        displayedCount < allFilteredExercises.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom search bar (fixes Auto Layout constraint conflicts)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.body)

                    TextField("Search exercises", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.default)
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .frame(minHeight: 20)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.Semantic.surface)
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Region filter
                Picker("Region", selection: $selectedRegion) {
                    Text("All").tag(MuscleRegion?.none)
                    ForEach(MuscleRegion.allCases.filter { $0 != .all }) { region in
                        Text(region.rawValue).tag(MuscleRegion?.some(region))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Exercise list with pagination
                List {
                    ForEach(displayedExercises) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            ExerciseRowContent(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // Load more when approaching the end
                            if exercise.id == displayedExercises.last?.id && hasMoreExercises {
                                loadMoreExercises()
                            }
                        }
                    }

                    // Load more indicator
                    if hasMoreExercises {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .onAppear {
                            loadMoreExercises()
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFocused = false
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: searchText) { _, newValue in
                debounceSearch(newValue)
            }
            .onChange(of: selectedRegion) { _, _ in
                // Reset pagination when filter changes
                displayedCount = 50
                updateFilteredExercises()
            }
            .onChange(of: debouncedSearchText) { _, _ in
                updateFilteredExercises()
            }
            .onAppear {
                // Initial load
                updateFilteredExercises()
            }
        }
    }

    private func debounceSearch(_ text: String) {
        searchDebounce?.cancel()
        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                debouncedSearchText = text
                displayedCount = 50 // Reset pagination on search
            }
        }
    }

    private func loadMoreExercises() {
        displayedCount = min(displayedCount + 50, allFilteredExercises.count)
    }

    private func favoritesFirst(_ exercises: [Exercise], favIDs: Set<String>) -> [Exercise] {
        let favorites = exercises.filter { favIDs.contains($0.id) }
        let nonFavorites = exercises.filter { !favIDs.contains($0.id) }

        let sortedFavorites = favorites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sortedNonFavorites = nonFavorites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return sortedFavorites + sortedNonFavorites
    }
}

// MARK: - Exercise Row Content

private struct ExerciseRowContent: View {
    let exercise: Exercise
    @EnvironmentObject var favs: FavoritesStore

    var body: some View {
        HStack(spacing: 12) {
            // Favorite star
            if favs.ids.contains(exercise.id) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Theme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)

                if !exercise.primaryMuscles.isEmpty {
                    Text(exercise.primaryMuscles.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.Theme.accent)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

