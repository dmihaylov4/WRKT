
//
//  SearchView.swift
//  WRKT
//

import SwiftUI
import Foundation

enum SearchDestination: Hashable {
    case exercise(Exercise)
    case muscle(String)
}

struct SearchView: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStore

    @State private var query = ""
    @State private var path: [SearchDestination] = []
    @State private var browseState: BrowseState = .root
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                // Search bar
                HStack {
                    Spacer(minLength: 0)
                    TextField("Search exercises or muscles", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .dsInputField()                 // your design system modifier
                        .focused($isSearchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal)

                // Recent + quick filters
                HistoryAndFilters(query: $query)

                // Content
                if query.isEmpty {
                    // Browse fallback
                    switch browseState {
                    case .root:
                        BodyBrowseRootView(state: $browseState)
                    case .region(let region):
                        SubregionGridView(state: $browseState, region: region)
                    case .subregion(let name):
                        MuscleExerciseListView(state: $browseState, subregion: name)
                    case .deep(let parent, let child):
                        MuscleExerciseListDeepView(state: $browseState, parent: parent, child: child)
                    }
                } else {
                    SuggestionList(query: query)
                }
            }
            .navigationDestination(for: SearchDestination.self) { dest in
                switch dest {
                case .exercise(let ex):
                    ExerciseSessionView(exercise: ex)
                case .muscle(let group):
                    MuscleGroupView(group: group)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isSearchFocused = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) {
            CurrentWorkoutBar().environmentObject(store)
        }
    }

    @ViewBuilder
    func TitleWithStreak() -> some View {
        HStack(spacing: 8) {
            Text("Train")
            Spacer()
            let streak = store.streak()
            if streak > 0 {
                Label("\(streak)", systemImage: "flame.fill")
                    .symbolRenderingMode(.multicolor)
                    .padding(6)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("Streak \(streak) days")
            }
        }
    }
}

struct SuggestionList: View {
    @EnvironmentObject var repo: ExerciseRepository
    let query: String

    var body: some View {
        let result = repo.search(query)
        List {
            if !result.exercises.isEmpty {
                Section("Exercises") {
                    ForEach(result.exercises) { ex in
                        NavigationLink(value: SearchDestination.exercise(ex)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.body)
                                HStack(spacing: 8) {
                                    Text(ex.category.capitalized)
                                    if let equip = ex.equipment { Text(equip) }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !result.muscleGroups.isEmpty {
                Section("Muscle Groups") {
                    ForEach(result.muscleGroups, id: \.self) { group in
                        NavigationLink(value: SearchDestination.muscle(group)) {
                            Label(group.capitalized, systemImage: "dumbbell")
                        }
                    }
                }
            }

            if result.exercises.isEmpty && result.muscleGroups.isEmpty && !query.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different term."))
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct HistoryAndFilters: View {
    @EnvironmentObject var store: WorkoutStore
    @Binding var query: String

    // Consider aligning these with the most common values from your Excel dataset.
    private let equipmentFilters = ["Bodyweight", "Dumbbell", "Barbell", "Kettlebell", "Machine"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent) { item in
                            Button {
                                query = item.name   // quick search by name
                            } label: {
                                Label(item.name, systemImage: "clock")
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .accessibilityElement(children: .contain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipmentFilters, id: \.self) { tag in
                        Button { query = tag } label: {
                            Text(tag)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filter by \(tag)")
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var recent: [WorkoutStore.ExerciseSummary] {
        store.recentExercises(limit: 10)
    }
}
