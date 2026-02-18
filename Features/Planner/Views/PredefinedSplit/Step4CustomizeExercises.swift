//
//  Step4CustomizeExercises.swift
//  WRKT
//
//  Step 4: Customize exercises

import SwiftUI
import Combine
struct Step4CustomizeExercises: View {
    @ObservedObject var config: PlanConfig
    @EnvironmentObject var repo: ExerciseRepository
    let onAutoAdvance: () -> Void
    @Binding var selectedDayIndex: Int

    @StateObject private var searchVM = ExerciseSearchVM()

    var body: some View {
        VStack(spacing: 0) {
            // Show choice screen if user hasn't chosen yet
            if config.wantsToCustomize == nil {
                customizeChoiceScreen
            } else if config.wantsToCustomize == true {
                // Show customization interface with Done button
                customizationInterface
            } else {
                // User chose defaults - show preview
                exercisePreview
            }
        }
    }

    // MARK: - Choice Screen
    private var customizeChoiceScreen: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize exercises?")
                    .font(.title2.bold())

                Text("You can use the default exercises or customize them to your preferences.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            VStack(spacing: 16) {
                RestDayOptionCard(
                    icon: "checkmark.circle",
                    title: "Use Default Exercises",
                    description: "Start with the recommended exercises for this split",
                    isSelected: config.wantsToCustomize == false
                ) {
                    config.wantsToCustomize = false
                }

                RestDayOptionCard(
                    icon: "slider.horizontal.3",
                    title: "Customize Exercises",
                    description: "Modify exercises, sets, reps, and starting weights",
                    isSelected: config.wantsToCustomize == true
                ) {
                    config.wantsToCustomize = true
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
    }

    // MARK: - Exercise Preview
    private var exercisePreview: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercise preview")
                    .font(.title2.bold())

                Text("These are the default exercises for your split. You can proceed or go back to customize.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 16)

            // Day tabs
            if let template = config.selectedTemplate {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(template.days.enumerated()), id: \.offset) { index, day in
                            DayTab(
                                title: day.name,
                                isSelected: selectedDayIndex == index
                            ) {
                                selectedDayIndex = index
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)

                // Exercise list for selected day (read-only)
                let selectedDay = template.days[selectedDayIndex]

                ScrollView {
                    VStack(spacing: 12) {
                        if !selectedDay.exercises.isEmpty {
                            ForEach(selectedDay.exercises) { exercise in
                                ExerciseRowPreview(exercise: exercise)
                            }
                        } else {
                            Text("No exercises")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Customization Interface
    private var customizationInterface: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize exercises")
                    .font(.title2.bold())

                Text("Modify the exercises for each workout day.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 16)

            // Day tabs
            if let template = config.selectedTemplate {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(template.days.enumerated()), id: \.offset) { index, day in
                            DayTab(
                                title: day.name,
                                isSelected: selectedDayIndex == index
                            ) {
                                selectedDayIndex = index
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)

                // Exercise list for selected day
                let selectedDay = template.days[selectedDayIndex]

                ScrollView {
                    VStack(spacing: 12) {
                        // Current exercises
                        if let exercises = config.customizedDays[selectedDay.id] ?? Optional(selectedDay.exercises), !exercises.isEmpty {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                ExerciseRowEditable(
                                    exercise: exercise,
                                    onRemove: {
                                        removeExercise(dayID: selectedDay.id, index: index)
                                    },
                                    onEdit: { sets, reps, weight in
                                        updateExercise(dayID: selectedDay.id, index: index, sets: sets, reps: reps, weight: weight)
                                    }
                                )
                            }
                        }

                        // Add exercise button
                        Button {
                            searchVM.isShowingSearch = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add Exercise")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(DS.Palette.marone)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Palette.marone.opacity(0.1))
                            .clipShape(ChamferedRectangle(.medium))
                            .overlay(
                                ChamferedRectangle(.medium)
                                    .stroke(DS.Palette.marone.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $searchVM.isShowingSearch) {
            ExerciseSearchSheet(
                searchVM: searchVM,
                onSelect: { exercise in
                    guard let template = config.selectedTemplate else { return }
                    let selectedDay = template.days[selectedDayIndex]
                    addExercise(dayID: selectedDay.id, exercise: exercise)
                    searchVM.isShowingSearch = false
                }
            )
            .environmentObject(repo)
        }
    }

    private func addExercise(dayID: String, exercise: Exercise) {
        guard let template = config.selectedTemplate else { return }
        guard let dayTemplate = template.days.first(where: { $0.id == dayID }) else { return }

        var exercises = config.customizedDays[dayID] ?? dayTemplate.exercises

        let newExercise = ExerciseTemplate(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            sets: 3,
            reps: 10,
            startingWeight: nil,
            progressionStrategy: .linear(increment: 2.5)
        )

        exercises.append(newExercise)
        config.customizedDays[dayID] = exercises
    }

    private func removeExercise(dayID: String, index: Int) {
        guard let template = config.selectedTemplate else { return }
        guard let dayTemplate = template.days.first(where: { $0.id == dayID }) else { return }

        var exercises = config.customizedDays[dayID] ?? dayTemplate.exercises
        exercises.remove(at: index)
        config.customizedDays[dayID] = exercises
    }

    private func updateExercise(dayID: String, index: Int, sets: Int, reps: Int, weight: Double?) {
        guard let template = config.selectedTemplate else { return }
        guard let dayTemplate = template.days.first(where: { $0.id == dayID }) else { return }

        var exercises = config.customizedDays[dayID] ?? dayTemplate.exercises
        guard index < exercises.count else { return }

        // Create a new ExerciseTemplate with updated values
        let oldExercise = exercises[index]
        let updatedExercise = ExerciseTemplate(
            exerciseID: oldExercise.exerciseID,
            exerciseName: oldExercise.exerciseName,
            sets: sets,
            reps: reps,
            startingWeight: weight,
            progressionStrategy: oldExercise.progressionStrategy,
            notes: oldExercise.notes
        )

        exercises[index] = updatedExercise
        config.customizedDays[dayID] = exercises
    }
}

// MARK: - Day Tab
struct DayTab: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.marone)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? DS.Palette.marone.opacity(0.15) : DS.Palette.marone.opacity(0.05))
                .clipShape(ChamferedRectangle(.small))
                .overlay(
                    ChamferedRectangle(.small)
                        .stroke(isSelected ? DS.Palette.marone : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise Row Editable
struct ExerciseRowEditable: View {
    let exercise: ExerciseTemplate
    let onRemove: () -> Void
    let onEdit: (Int, Int, Double?) -> Void

    @State private var showEditSheet = false

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Text("\(exercise.sets) sets × \(exercise.reps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let weight = exercise.startingWeight, weight > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.1f", weight)) kg")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.marone)
                        }
                    }
                }

                Spacer()

                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Palette.marone.opacity(0.7))

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(DS.Semantic.surface)
            .clipShape(ChamferedRectangle(.medium))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditSheet) {
            ExerciseEditSheet(
                exercise: exercise,
                onSave: { sets, reps, weight in
                    onEdit(sets, reps, weight)
                    showEditSheet = false
                }
            )
        }
    }
}


// MARK: - Exercise Search Sheet
struct ExerciseSearchSheet: View {
    @ObservedObject var searchVM: ExerciseSearchVM
    @EnvironmentObject var repo: ExerciseRepository
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Exercise) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filters
                FiltersBar(equip: $searchVM.equipmentFilter, move: $searchVM.movementFilter)

                Divider()

                // Exercise List
                List {
                    // Summary row
                    if repo.totalExerciseCount > 0 {
                        Text("\(repo.exercises.count) of \(repo.totalExerciseCount) exercises")
                            .font(.caption).foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }

                    // Exercise rows with pagination
                    ForEach(Array(repo.exercises.enumerated()), id: \.element.id) { index, ex in
                        Button {
                            onSelect(ex)
                        } label: {
                            PlannerExerciseRow(ex: ex)
                                .onAppear {
                                    // Load more when approaching end of list
                                    if shouldLoadMore(at: index) {
                                        Task {
                                            await repo.loadNextPage()
                                        }
                                    }
                                }
                        }
                        .listRowSeparator(.hidden)
                    }

                    // Loading indicator
                    if repo.isLoadingPage {
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
                .searchable(text: $searchVM.searchQuery, placement: .navigationBarDrawer(displayMode: .always))
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await searchVM.loadInitialPage(repo: repo)
            }
            .onChange(of: searchVM.currentFilters) { _, _ in
                Task {
                    await searchVM.handleFiltersChanged(repo: repo)
                }
            }
            .onDisappear {
                // Only reset repository if filters were actually modified (performance optimization)
                let shouldResetRepo = searchVM.hasModifiedFilters
                searchVM.reset()

                if shouldResetRepo {
                    Task {
                        let defaultFilters = ExerciseFilters(
                            muscleGroup: nil,
                            equipment: .all,
                            moveType: .all,
                            searchQuery: ""
                        )
                        await repo.resetPagination(with: defaultFilters)
                    }
                }
            }
        }
    }

    /// Determine if we should load more exercises
    private func shouldLoadMore(at index: Int) -> Bool {
        guard repo.hasMorePages && !repo.isLoadingPage else { return false }
        return index >= repo.exercises.count - PlannerConstants.ExerciseLimits.paginationTrigger
    }
}

// MARK: - Planner Exercise Row (BodyBrowse style with + button)
struct PlannerExerciseRow: View {
    let ex: Exercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ex.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    PremiumChip(
                        title: ex.equipBucket.rawValue,
                        icon: "dumbbell.fill",
                        color: .blue
                    )
                    PremiumChip(
                        title: ex.moveBucket.rawValue,
                        icon: ex.moveBucket == .pull ? "arrow.down.backward" :
                              ex.moveBucket == .push ? "arrow.up.forward" : "arrow.right",
                        color: chipColor(for: ex.moveBucket)
                    )
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(DS.Palette.marone)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func chipColor(for bucket: MoveBucket) -> Color {
        switch bucket {
        case .push: return .orange
        case .pull: return .green
        default: return .purple
        }
    }
}

// MARK: - Exercise Row Preview (Read-Only)
struct ExerciseRowPreview: View {
    let exercise: ExerciseTemplate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.exerciseName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text("\(exercise.sets) sets × \(exercise.reps) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let weight = exercise.startingWeight, weight > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", weight)) kg")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.marone)
                    }
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(DS.Palette.marone.opacity(0.5))
        }
        .padding(12)
        .background(DS.Semantic.surface)
        .clipShape(ChamferedRectangle(.medium))
    }
}

// MARK: - Step 5: Program Length
