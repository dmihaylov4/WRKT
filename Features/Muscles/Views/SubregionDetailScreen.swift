//
//  SubregionDetailScreen.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 07.10.25.
//


import SwiftUI

/// Unified screen that shows optional deep filters (chips) and a list of exercises.
/// - If a deep filter (e.g. Upper/Mid/Lower Chest) exists, a segmented picker is shown.
/// - The list is always rendered and loads from the repository JSON if needed.
struct SubregionDetailScreen: View {
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var favs: FavoritesStore
    let subregion: String
    let preselectedDeep: String?

    @State private var selectedDeep: String? = nil
    @State private var sheetContext: LogSheetContext? = nil

    init(subregion: String, preselectedDeep: String? = nil) {
        self.subregion = subregion
        self.preselectedDeep = preselectedDeep
        _selectedDeep = State(initialValue: preselectedDeep)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Deep filters
            if let deep = MuscleTaxonomy.deepSubregions(for: subregion), !deep.isEmpty {
                Picker("Filter", selection: Binding(
                    get: { selectedDeep ?? "All" },
                    set: { selectedDeep = $0 == "All" ? nil : $0 }
                )) {
                    Text("All").tag("All")
                    ForEach(deep, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityLabel("Deep filter")
            }

            // List of exercises
            if repo.exercises.isEmpty {
                ContentUnavailableView("Loading exercises…", systemImage: "dumbbell")
                   // .task {
                     //   if repo.exercises.isEmpty {
                       //     repo.loadFromBundle(fileName: "exercises", fileExtension: "json")
                        //}
                    //}
            } else {
                List(filteredExercises, id: \.id) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ex.name).font(.body)
                        Text("\(ex.category.capitalized) • \(ex.equipment ?? "Bodyweight")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                        FavoriteHeartButton(exerciseID: ex.id)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sheetContext = LogSheetContext(exercise: ex, entryID: nil)


                    }
                    .contextMenu {
                        // Open the logging sheet WITHOUT adding yet.
                        Button("Add & Log") {
                            sheetContext = LogSheetContext(exercise: ex, entryID: nil)
                        }

                        // Add silently (no sheet). This one *does* add immediately by design.
                        Button("Add Only") {
                            _ = store.addExerciseToCurrent(ex)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
                            //NotificationCenter.default.post(name: .resetHomeToRoot, object: nil)  // ⬅️ show the two big tiles
                            AppBus.postResetHome(reason: .user_intent)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                .listStyle(.insetGrouped)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredExercises.map { $0.id })

                if filteredExercises.isEmpty {
                    ContentUnavailableView("No exercises found", systemImage: "magnifyingglass")
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle(subregion.capitalized)
        .sheet(item: $sheetContext) { ctx in
            ExerciseSessionView(
                exercise: ctx.exercise,
                initialEntryID: ctx.entryID ?? store.existingEntry(for: ctx.exercise.id)?.id,  // Reuse existing entry if available
                returnToHomeOnSave: true              // after saving, go back to Home root
            )
        }
    }

    // MARK: Filtering
    private var filteredExercises: [Exercise] {
        let base: [Exercise]
        if let deep = selectedDeep {
            base = repo.deepExercises(parent: subregion, child: deep)
        } else {
            base = parentFiltered(subregion)
        }
        return favoritesFirst(base, favIDs: favs.ids)
    }

    private func parentFiltered(_ subregion: String) -> [Exercise] {
        let keys = MuscleMapper.synonyms(for: subregion)
        return repo.exercises
            .filter { ex in
                let muscles = (ex.primaryMuscles + ex.secondaryMuscles).map { $0.lowercased() }
                let name = ex.name.lowercased()
                let hitMuscle = muscles.contains { m in keys.contains(where: { m.contains($0) }) }
                let hitName = keys.contains { name.contains($0) }
                return hitMuscle || hitName
            }
            .sorted { $0.name < $1.name }
    }
}

// Near your other small types
struct LogSheetContext: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let entryID: UUID?    // nil means “not yet in current workout”
}
