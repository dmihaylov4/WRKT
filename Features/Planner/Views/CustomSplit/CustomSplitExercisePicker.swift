//
//  CustomSplitExercisePicker.swift
//  WRKT
//
//  Exercise picker for custom split creation

import SwiftUI

struct CustomSplitExercisePicker: View {
    @ObservedObject var config: PlanConfig
    let partName: String
    @EnvironmentObject var exerciseRepo: ExerciseRepository
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedExercises: Set<String> = []
    @State private var exerciseConfigs: [String: ExerciseConfig] = [:] // exerciseID -> config
    @State private var searchDebounce: Task<Void, Never>? = nil

    // Cache filtered results to avoid recalculating on every render
    @State private var cachedDisplayedExercises: [Exercise] = []

    struct ExerciseConfig {
        var sets: Int = 3
        var reps: Int = 10
        var weight: Double? = nil
    }

    private var displayedExercises: [Exercise] {
        cachedDisplayedExercises
    }

    private func updateDisplayedExercises() {
        // Use all exercises from repo (includes pagination)
        let exercises = exerciseRepo.exercises
        if debouncedSearchText.isEmpty {
            cachedDisplayedExercises = exercises
        } else {
            cachedDisplayedExercises = exercises.filter { exercise in
                exercise.name.lowercased().contains(debouncedSearchText.lowercased()) ||
                exercise.primaryMuscles.contains(where: { $0.lowercased().contains(debouncedSearchText.lowercased()) })
            }
        }
    }

    private var currentExercises: [ExerciseTemplate] {
        config.partExercises[partName] ?? []
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DS.Semantic.textSecondary)

                    TextField("Search exercises", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newValue in
                            debounceSearch(newValue)
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(DS.Semantic.surface, in: RoundedRectangle(cornerRadius: 10))
                .padding()

                // Selected count
                if !selectedExercises.isEmpty {
                    HStack {
                        Text("\(selectedExercises.count) exercise\(selectedExercises.count > 1 ? "s" : "") selected")
                            .font(.caption)
                            .foregroundStyle(DS.Theme.accent)

                        Spacer()

                        Button("Configure") {
                            // TODO: Show configuration sheet
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Theme.accent)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Exercise list
                List {
                    // Summary row
                    if exerciseRepo.totalExerciseCount > 0 {
                        Text("\(displayedExercises.count) of \(exerciseRepo.totalExerciseCount) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }

                    // Exercise rows with pagination
                    ForEach(Array(displayedExercises.enumerated()), id: \.element.id) { index, exercise in
                        ExerciseRow(
                            exercise: exercise,
                            isSelected: selectedExercises.contains(exercise.id)
                        ) {
                            toggleExercise(exercise)
                        }
                        .onAppear {
                            // Load more when approaching end of list
                            if shouldLoadMore(at: index) {
                                Task {
                                    await exerciseRepo.loadNextPage()
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                    }

                    // Loading indicator
                    if exerciseRepo.isLoadingPage {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(partName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedExercises.count))") {
                        saveExercises()
                    }
                    .disabled(selectedExercises.isEmpty)
                    .font(.body.weight(.semibold))
                }
            }
        }
        .task {
            // Load initial exercises if needed
            if exerciseRepo.exercises.isEmpty {
                await exerciseRepo.loadFirstPage(with: ExerciseFilters(
                    muscleGroup: nil,
                    equipment: .all,
                    moveType: .all,
                    searchQuery: ""
                ))
            }
        }
        .onAppear {
            // Pre-select currently added exercises
            selectedExercises = Set(currentExercises.map { $0.exerciseID })

            // Load existing configs
            for template in currentExercises {
                exerciseConfigs[template.exerciseID] = ExerciseConfig(
                    sets: template.sets,
                    reps: template.reps,
                    weight: template.startingWeight
                )
            }

            // Initial load of exercises
            updateDisplayedExercises()
        }
        .onChange(of: debouncedSearchText) { _, _ in
            updateDisplayedExercises()
        }
        .onChange(of: exerciseRepo.exercises) { _, _ in
            updateDisplayedExercises()
        }
    }

    private func debounceSearch(_ text: String) {
        searchDebounce?.cancel()
        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                debouncedSearchText = text
            }
        }
    }

    /// Determine if we should load more exercises
    private func shouldLoadMore(at index: Int) -> Bool {
        guard exerciseRepo.hasMorePages && !exerciseRepo.isLoadingPage else { return false }
        return index >= displayedExercises.count - PlannerConstants.ExerciseLimits.paginationTrigger
    }

    private func toggleExercise(_ exercise: Exercise) {
        if selectedExercises.contains(exercise.id) {
            selectedExercises.remove(exercise.id)
            exerciseConfigs.removeValue(forKey: exercise.id)
        } else {
            selectedExercises.insert(exercise.id)
            // Set default config
            exerciseConfigs[exercise.id] = ExerciseConfig(
                sets: 3,
                reps: suggestReps(for: exercise),
                weight: nil
            )
        }
    }

    private func suggestReps(for exercise: Exercise) -> Int {
        // Suggest reps based on exercise type
        if exercise.mechanic?.lowercased() == "compound" {
            return 6 // Heavier compounds: lower reps
        } else {
            return 12 // Isolation: higher reps
        }
    }

    private func saveExercises() {
        var templates: [ExerciseTemplate] = []

        for exerciseID in selectedExercises {
            guard let exercise = exerciseRepo.byID[exerciseID],
                  let config = exerciseConfigs[exerciseID] else {
                continue
            }

            let template = ExerciseTemplate(
                exerciseID: exerciseID,
                exerciseName: exercise.name,
                sets: config.sets,
                reps: config.reps,
                startingWeight: config.weight,
                progressionStrategy: .linear(increment: 2.5),
                notes: nil
            )

            templates.append(template)
        }

        // Update config
        config.partExercises[partName] = templates

        dismiss()
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? DS.Theme.accent : DS.Semantic.border, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(DS.Theme.accent)
                            .frame(width: 16, height: 16)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    HStack(spacing: 8) {
                        if let mechanic = exercise.mechanic {
                            Text(mechanic)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DS.Theme.accent.opacity(0.1), in: Capsule())
                                .foregroundStyle(DS.Theme.accent)
                        }

                        if let primaryMuscle = exercise.primaryMuscles.first {
                            Text(primaryMuscle)
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                // Always reserve space for checkmark to prevent layout shift
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isSelected ? DS.Theme.accent : Color.clear)
                    .font(.title3)
                    .frame(width: 28, height: 28) // Fixed size to prevent shift
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
