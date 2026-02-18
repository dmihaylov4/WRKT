//  AggregatedExerciseListView.swift
//  WRKT
//
//  Shows all exercises from multiple subregions aggregated together
//

import SwiftUI

struct AggregatedExerciseListView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var favs: FavoritesStore

    let subregions: [String]
    let title: String

    @State private var showingSessionFor: Exercise? = nil
    @State private var searchText = ""
    @State private var filteredExercises: [Exercise] = []

    private var allExercises: [Exercise] {
        var exercises: [Exercise] = []

        for subregion in subregions {
            let keys = MuscleMapper.synonyms(for: subregion)
            let subregionExercises = repo.byID.values.filter { ex in
                let prim = ex.primaryMuscles.map { $0.lowercased() }
                return prim.contains { m in keys.contains { key in m.contains(key) } }
            }
            exercises.append(contentsOf: subregionExercises)
        }

        // Remove duplicates and sort
        let unique = Array(Set(exercises))
        let sorted = unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Favorites first
        return favoritesFirst(sorted, favIDs: favs.ids)
    }

    private var displayedExercises: [Exercise] {
        if searchText.isEmpty {
            return allExercises
        } else {
            return allExercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        List {
            ForEach(displayedExercises) { exercise in
                Button {
                    openSession(for: exercise)
                } label: {
                    ExerciseRowContent(exercise: exercise)
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $showingSessionFor) { exercise in
            ExerciseSessionView(
                exercise: exercise,
                initialEntryID: store.existingEntry(for: exercise.id)?.id
            )
            .environmentObject(store)
            .environmentObject(repo)
        }
    }

    private func openSession(for ex: Exercise) {
        showingSessionFor = ex
    }

    private func favoritesFirst(_ exercises: [Exercise], favIDs: Set<String>) -> [Exercise] {
        let favorites = exercises.filter { favIDs.contains($0.id) }
        let nonFavorites = exercises.filter { !favIDs.contains($0.id) }
        return favorites + nonFavorites
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

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
                .opacity(0.6)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
