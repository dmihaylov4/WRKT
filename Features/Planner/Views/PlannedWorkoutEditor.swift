//
//  PlannedWorkoutEditor.swift
//  WRKT
//
//  Editor for creating and editing planned workouts
//

import SwiftUI
import SwiftData

struct PlannedWorkoutEditor: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2

    let date: Date
    let existingWorkout: PlannedWorkout?

    @State private var scheduledDate: Date = .now
    @State private var workoutName: String = ""
    @State private var plannedExercises: [PlannedExerciseConfig] = []
    @State private var showingExercisePicker = false
    @State private var editingExercise: PlannedExerciseConfig? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingRescheduleOptions = false
    @State private var schedulingErrorMessage: String?

    // Temporary config struct for editing before saving to SwiftData
    struct PlannedExerciseConfig: Identifiable {
        let id: UUID
        var exerciseID: String
        var exerciseName: String
        var ghostSets: [GhostSet]
        var progressionStrategy: ProgressionStrategy
        var notes: String?
        var order: Int

        init(id: UUID = UUID(), exerciseID: String, exerciseName: String,
             ghostSets: [GhostSet] = [GhostSet(reps: 10, weight: 0)],
             progressionStrategy: ProgressionStrategy = .static,
             notes: String? = nil, order: Int = 0) {
            self.id = id
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.ghostSets = ghostSets
            self.progressionStrategy = progressionStrategy
            self.notes = notes
            self.order = order
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerActions
                    detailSection
                    exercisesSection

                    if existingWorkout != nil {
                        deleteSection
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle(existingWorkout == nil ? "Plan Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(onSelect: addExercise)
                    .environmentObject(repo)
                    .environmentObject(FavoritesStore())
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseDetailEditor(exercise: binding(for: exercise))
                    .environmentObject(store)
            }
            .onAppear {
                loadExistingWorkout()
            }
            .toolbarBackground(DS.Semantic.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if showingDeleteConfirmation {
                    deleteConfirmationOverlay
                }
            }
            .confirmationDialog(
                "Move Planned Workout",
                isPresented: $showingRescheduleOptions,
                titleVisibility: .visible
            ) {
                Button("Move This Workout Only") {
                    savePlannedWorkout(rescheduleBehavior: .moveOnly)
                }
                Button("Shift All Upcoming Planned Workouts") {
                    savePlannedWorkout(rescheduleBehavior: .shiftUpcoming)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This workout belongs to an active plan. Choose whether to move just this workout or shift the rest of the upcoming plan by the same amount.")
            }
            .alert("Unable to Save Workout", isPresented: schedulingErrorAlertBinding) {
                Button("OK", role: .cancel) {
                    schedulingErrorMessage = nil
                }
            } message: {
                Text(schedulingErrorMessage ?? "")
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        ChamferedRectangle(.small)
                            .fill(DS.Theme.cardTop)
                            .overlay(ChamferedRectangle(.small).stroke(DS.Semantic.border, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(existingWorkout == nil ? "Plan Workout" : "Edit Workout")
                .dsFont(.headline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            Button {
                handleSaveTapped()
            } label: {
                Text("Save")
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(plannedExercises.isEmpty ? DS.Semantic.textSecondary : Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        ChamferedRectangle(.small)
                            .fill(plannedExercises.isEmpty ? DS.Semantic.surface50 : DS.Theme.accent)
                            .overlay(
                                ChamferedRectangle(.small)
                                    .stroke(plannedExercises.isEmpty ? DS.Semantic.border : DS.Theme.accent.opacity(0.4), lineWidth: 1)
                            )
                    )
            }
            .disabled(plannedExercises.isEmpty)
            .buttonStyle(.plain)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Workout Details")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(DS.Theme.accent)

                    if existingWorkout?.splitID != nil {
                        Text("Changing the date will let you move only this workout or shift the rest of the upcoming plan.")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
                .padding(16)

                Divider()
                    .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout Name")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    TextField("Workout Name (Optional)", text: $workoutName)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .textInputAutocapitalization(.words)
                }
                .padding(16)
            }
            .background(DS.Theme.cardTop)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
        }
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Exercises (\(plannedExercises.count))")
                Spacer()
                Text("Tap a row to edit sets and notes")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            VStack(spacing: 0) {
                if plannedExercises.isEmpty {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .dsFont(.title2)
                                .foregroundStyle(DS.Theme.accent)
                            Text("Add First Exercise")
                                .dsFont(.headline, weight: .semibold)
                                .foregroundStyle(DS.Semantic.textPrimary)
                            Text("Build the workout, then tap each exercise to edit sets and add notes.")
                                .dsFont(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(plannedExercises) { exercise in
                        PlannedExerciseRow(
                            exercise: exercise,
                            onDelete: { deleteExercise(id: exercise.id) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingExercise = exercise
                        }

                        if exercise.id != plannedExercises.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }

                    Divider()
                        .padding(.leading, 16)

                    Button {
                        showingExercisePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Exercise")
                                .fontWeight(.semibold)
                        }
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .background(DS.Theme.cardTop)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            HStack {
                Spacer()
                Label("Delete Workout", systemImage: "trash")
                    .dsFont(.headline, weight: .semibold)
                Spacer()
            }
            .padding(.vertical, 18)
            .background(DS.Theme.cardTop)
            .clipShape(ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(.red.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    showingDeleteConfirmation = false
                }

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Delete Workout?")
                        .dsFont(.headline, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("This will permanently delete this planned workout.")
                        .dsFont(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                HStack(spacing: 12) {
                    Button {
                        showingDeleteConfirmation = false
                    } label: {
                        Text("Cancel")
                            .dsFont(.subheadline, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                ChamferedRectangle(.medium)
                                    .fill(DS.Semantic.surface50)
                                    .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingDeleteConfirmation = false
                        deletePlannedWorkout()
                    } label: {
                        Text("Delete")
                            .dsFont(.subheadline, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                ChamferedRectangle(.medium)
                                    .fill(Color.red.opacity(0.9))
                                    .overlay(ChamferedRectangle(.medium).stroke(Color.red.opacity(0.35), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(
                ChamferedRectangle(.xl)
                    .fill(DS.Theme.cardTop)
                    .overlay(ChamferedRectangle(.xl).stroke(DS.Semantic.border, lineWidth: 1))
            )
            .padding(.horizontal, 20)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .dsFont(.headline, weight: .semibold)
            .foregroundStyle(DS.Semantic.textPrimary)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(DS.Semantic.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(16)
    }

    // MARK: - Exercise Management

    private func addExercise(_ exercise: Exercise) {
        // Get suggested starting weight from history
        let suggestedWeight: Double = {
            if let lastSet = store.lastWorkingSet(exercise: exercise) {
                return lastSet.weightKg
            }
            return 0
        }()

        let config = PlannedExerciseConfig(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            ghostSets: [
                GhostSet(reps: 10, weight: suggestedWeight),
                GhostSet(reps: 10, weight: suggestedWeight),
                GhostSet(reps: 10, weight: suggestedWeight)
            ],
            progressionStrategy: .static,
            order: plannedExercises.count
        )

        plannedExercises.append(config)
        Haptics.light()
    }

    private func deleteExercise(at offsets: IndexSet) {
        plannedExercises.remove(atOffsets: offsets)
        // Reorder
        for (index, _) in plannedExercises.enumerated() {
            plannedExercises[index].order = index
        }
    }

    private func deleteExercise(id: UUID) {
        guard let index = plannedExercises.firstIndex(where: { $0.id == id }) else { return }
        plannedExercises.remove(at: index)
        for (reindex, _) in plannedExercises.enumerated() {
            plannedExercises[reindex].order = reindex
        }
        Haptics.light()
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        plannedExercises.move(fromOffsets: source, toOffset: destination)
        // Reorder
        for (index, _) in plannedExercises.enumerated() {
            plannedExercises[index].order = index
        }
    }

    private func binding(for exercise: PlannedExerciseConfig) -> Binding<PlannedExerciseConfig> {
        guard let index = plannedExercises.firstIndex(where: { $0.id == exercise.id }) else {
            fatalError("Exercise not found")
        }
        return $plannedExercises[index]
    }

    // MARK: - Data Management

    private func loadExistingWorkout() {
        scheduledDate = Calendar.current.startOfDay(for: date)
        guard let existing = existingWorkout else { return }

        scheduledDate = Calendar.current.startOfDay(for: existing.scheduledDate)
        workoutName = existing.splitDayName
        plannedExercises = existing.exercises.map { exercise in
            PlannedExerciseConfig(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                exerciseName: exercise.exerciseName,
                ghostSets: exercise.ghostSets,
                progressionStrategy: exercise.progressionStrategy,
                notes: exercise.notes,
                order: exercise.order
            )
        }.sorted { $0.order < $1.order }
    }

    private var schedulingErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { schedulingErrorMessage != nil },
            set: { if !$0 { schedulingErrorMessage = nil } }
        )
    }

    private var normalizedScheduledDate: Date {
        Calendar.current.startOfDay(for: scheduledDate)
    }

    private var originalScheduledDate: Date {
        Calendar.current.startOfDay(for: existingWorkout?.scheduledDate ?? date)
    }

    private var isDateChanged: Bool {
        normalizedScheduledDate != originalScheduledDate
    }

    private func handleSaveTapped() {
        if existingWorkout?.splitID != nil, isDateChanged {
            showingRescheduleOptions = true
        } else {
            savePlannedWorkout(rescheduleBehavior: .moveOnly)
        }
    }

    private func savePlannedWorkout(rescheduleBehavior: RescheduleBehavior) {
        // Convert configs to PlannedExercise models
        let exercises = plannedExercises.map { config in
            PlannedExercise(
                id: config.id,
                exerciseID: config.exerciseID,
                exerciseName: config.exerciseName,
                ghostSets: config.ghostSets,
                progressionStrategy: config.progressionStrategy,
                order: config.order,
                notes: config.notes
                
            )
        }

        if let existing = existingWorkout {
            // Update existing workout
            existing.splitDayName = workoutName.isEmpty ? "Custom Workout" : workoutName
            existing.exercises = exercises

            // Recalculate target volume
            existing.targetVolume = exercises.reduce(0.0) { sum, exercise in
                sum + exercise.ghostSets.reduce(0.0) { setSum, ghost in
                    setSum + (Double(ghost.reps) * ghost.weight)
                }
            }

            do {
                if isDateChanged {
                    switch rescheduleBehavior {
                    case .moveOnly:
                        try dependencies.plannerStore.reschedulePlannedWorkout(existing, to: normalizedScheduledDate)
                    case .shiftUpcoming:
                        guard let splitID = existing.splitID else {
                            try dependencies.plannerStore.reschedulePlannedWorkout(existing, to: normalizedScheduledDate)
                            break
                        }
                        let dayOffset = Calendar.current.dateComponents(
                            [.day],
                            from: originalScheduledDate,
                            to: normalizedScheduledDate
                        ).day ?? 0
                        try dependencies.plannerStore.shiftUpcomingPlannedWorkouts(
                            for: splitID,
                            startingAt: originalScheduledDate,
                            by: dayOffset
                        )
                    }
                } else {
                    try modelContext.save()
                }
            } catch {
                schedulingErrorMessage = error.localizedDescription
                return
            }
        } else {
            do {
                if let conflict = try existingPlannedWorkout(on: normalizedScheduledDate) {
                    schedulingErrorMessage = "\"\(conflict.splitDayName)\" is already planned for \(normalizedScheduledDate.formatted(date: .abbreviated, time: .omitted)). Choose a different date."
                    return
                }
            } catch {
                schedulingErrorMessage = error.localizedDescription
                return
            }

            // Create new workout
            let planned = PlannedWorkout(
                scheduledDate: normalizedScheduledDate,
                splitDayName: workoutName.isEmpty ? "Custom Workout" : workoutName,
                exercises: exercises
            )
            modelContext.insert(planned)

            do {
                try modelContext.save()
            } catch {
                schedulingErrorMessage = error.localizedDescription
                return
            }
        }

        // Notify calendar to reload planned workouts
        NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)

        Haptics.success()
        dismiss()
    }

    private func existingPlannedWorkout(on targetDate: Date) throws -> PlannedWorkout? {
        let normalizedDate = Calendar.current.startOfDay(for: targetDate)
        let predicate = #Predicate<PlannedWorkout> { $0.scheduledDate == normalizedDate }
        return try modelContext.fetch(FetchDescriptor(predicate: predicate))
            .first(where: { $0.id != existingWorkout?.id })
    }

    private func deletePlannedWorkout() {
        guard let existing = existingWorkout else { return }

        modelContext.delete(existing)

        do {
            try modelContext.save()
            // Notify calendar to reload planned workouts
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
            Haptics.success()
            dismiss()
        } catch {
        }
    }
}

private extension PlannedWorkoutEditor {
    enum RescheduleBehavior {
        case moveOnly
        case shiftUpcoming
    }
}

// MARK: - Planned Exercise Row

private struct PlannedExerciseRow: View {
    let exercise: PlannedWorkoutEditor.PlannedExerciseConfig
    let onDelete: () -> Void

    @EnvironmentObject private var store: WorkoutStoreV2

    private var consecutiveSameWeight: Int {
        store.consecutiveSessionsAtSameWeight(for: exercise.exerciseID)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.exerciseName)
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Semantic.textPrimary)

                // Ghost sets preview
                HStack(spacing: 4) {
                    ForEach(exercise.ghostSets.prefix(3)) { set in
                        Text("\(set.reps)×\(set.weight.safeInt)kg")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Theme.accent.opacity(0.1), in: ChamferedRectangle(.micro))
                    }

                    if exercise.ghostSets.count > 3 {
                        Text("+\(exercise.ghostSets.count - 3)")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }

                if consecutiveSameWeight >= 3 {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.flattrend.xyaxis")
                            .dsFont(.caption2)
                        Text("\(consecutiveSameWeight) sessions without progress")
                            .dsFont(.caption2, weight: .semibold)
                    }
                    .foregroundStyle(DS.Semantic.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Semantic.accentGold.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(DS.Semantic.accentGold.opacity(0.3), lineWidth: 1))
                }

                HStack(spacing: 8) {
                    Image(systemName: exercise.notes?.isEmpty == false ? "note.text" : "square.and.pencil")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Theme.accent)

                    Text(notePreview)
                        .dsFont(.caption)
                        .foregroundStyle(exercise.notes?.isEmpty == false ? DS.Semantic.textPrimary : DS.Semantic.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(8)
                        .background(DS.Semantic.surface50, in: ChamferedRectangle(.small))
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .opacity(0.6)
            }
        }
        .padding(16)
    }

    private var notePreview: String {
        guard let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Tap to edit sets and add a note"
        }
        return notes
    }
}

// MARK: - Exercise Detail Editor

private struct ExerciseDetailEditor: View {
    @Binding var exercise: PlannedWorkoutEditor.PlannedExerciseConfig
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: WorkoutStoreV2
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
    private var step: Double { unit == .kg ? 2.5 : 5 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Sets section
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Sets (\(exercise.ghostSets.count))")
                                .dsFont(.headline, weight: .semibold)
                                .foregroundStyle(DS.Semantic.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()

                        // Set rows
                        ForEach(Array(exercise.ghostSets.enumerated()), id: \.offset) { index, set in
                            GhostSetRow(
                                setNumber: index + 1,
                                set: binding(for: set),
                                unit: unit,
                                step: step,
                                onDelete: {
                                    exercise.ghostSets.remove(at: index)
                                }
                            )

                            if index < exercise.ghostSets.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }

                        // Add set button
                        Button {
                            addSet()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Set")
                                    .fontWeight(.semibold)
                            }
                            .dsFont(.subheadline)
                            .foregroundStyle(DS.Theme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(DS.Theme.cardTop)
                    .clipShape(ChamferedRectangle(.large))
                    .overlay(
                        ChamferedRectangle(.large)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )

                    // Notes section
                    VStack(spacing: 0) {
                        HStack {
                            Text("Notes")
                                .dsFont(.headline, weight: .semibold)
                                .foregroundStyle(DS.Semantic.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()

                        TextField("Notes (optional)", text: Binding(
                            get: { exercise.notes ?? "" },
                            set: { exercise.notes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .lineLimit(3...6)
                        .padding(16)
                    }
                    .background(DS.Theme.cardTop)
                    .clipShape(ChamferedRectangle(.large))
                    .overlay(
                        ChamferedRectangle(.large)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
                }
                .padding(16)
            }
            .background(DS.Semantic.surface)
            .navigationTitle(exercise.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func binding(for set: GhostSet) -> Binding<GhostSet> {
        guard let index = exercise.ghostSets.firstIndex(where: { $0.id == set.id }) else {
            fatalError("Set not found")
        }
        return $exercise.ghostSets[index]
    }

    private func addSet() {
        if let lastSet = exercise.ghostSets.last {
            exercise.ghostSets.append(GhostSet(reps: lastSet.reps, weight: lastSet.weight))
        } else {
            exercise.ghostSets.append(GhostSet(reps: 10, weight: 0))
        }
        Haptics.light()
    }
}

// MARK: - Ghost Set Row

private struct GhostSetRow: View {
    let setNumber: Int
    @Binding var set: GhostSet
    let unit: WeightUnit
    let step: Double
    let onDelete: () -> Void

    @State private var isEditingReps = false
    @State private var isEditingWeight = false
    @FocusState private var focusedField: Field?

    enum Field {
        case reps, weight
    }

    private var displayWeight: Double {
        unit == .kg ? set.weight : (set.weight * 2.20462)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Set \(setNumber)")
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                // Delete button
                Button {
                    onDelete()
                    Haptics.light()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .dsFont(.title3)
                        .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Input controls
            HStack(spacing: 16) {
                // Reps input
                VStack(spacing: 6) {
                    Text("REPS")
                        .dsFont(.caption2, weight: .semibold)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    HStack(spacing: 8) {
                        StepperButton(
                            systemName: "minus.circle.fill",
                            isEnabled: set.reps > 1
                        ) {
                            if set.reps > 1 {
                                set.reps -= 1
                                Haptics.light()
                            }
                        }

                        if isEditingReps {
                            TextField("", value: $set.reps, format: .number)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .reps)
                                .dsFont(.title2, weight: .bold, monospacedDigits: true)
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(minWidth: 40)
                        } else {
                            Text("\(set.reps)")
                                .dsFont(.title2, weight: .bold, monospacedDigits: true)
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(minWidth: 40)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isEditingReps = true
                                    focusedField = .reps
                                }
                        }

                        StepperButton(
                            systemName: "plus.circle.fill",
                            isEnabled: true
                        ) {
                            set.reps += 1
                            Haptics.light()
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(DS.Semantic.border)
                    .frame(width: 1, height: 60)

                // Weight input
                VStack(spacing: 6) {
                    Text("WEIGHT (\(unit.rawValue))")
                        .dsFont(.caption2, weight: .semibold)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    HStack(spacing: 8) {
                        StepperButton(
                            systemName: "minus.circle.fill",
                            isEnabled: displayWeight > 0
                        ) {
                            let newWeight = max(0, displayWeight - step)
                            let kg = (unit == .kg) ? newWeight : newWeight / 2.20462
                            set.weight = kg
                            Haptics.light()
                        }

                        if isEditingWeight {
                            TextField("", value: Binding(
                                get: { displayWeight },
                                set: { newValue in
                                    let kg = (unit == .kg) ? newValue : newValue / 2.20462
                                    set.weight = kg
                                }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                            .dsFont(.title2, weight: .bold, monospacedDigits: true)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 70, maxWidth: 100)
                        } else {
                            Text(String(format: "%.1f", displayWeight))
                                .dsFont(.title2, weight: .bold, monospacedDigits: true)
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(minWidth: 70, maxWidth: 100)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isEditingWeight = true
                                    focusedField = .weight
                                }
                        }

                        StepperButton(
                            systemName: "plus.circle.fill",
                            isEnabled: true
                        ) {
                            let newWeight = displayWeight + step
                            let kg = (unit == .kg) ? newWeight : newWeight / 2.20462
                            set.weight = kg
                            Haptics.light()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                isEditingReps = false
                isEditingWeight = false
            }
        }
    }
}

// MARK: - Stepper Button

private struct StepperButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    @GestureState private var isPressingDown = false
    @State private var longPressTimer: Timer?

    var body: some View {
        Image(systemName: systemName)
            .dsFont(.title2)
            .foregroundStyle(isEnabled ? DS.Theme.accent : DS.Semantic.textSecondary.opacity(0.3))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressingDown) { _, state, _ in
                        state = true
                    }
                    .onChanged { _ in
                        if isEnabled && longPressTimer == nil {
                            // First action on press
                            action()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()

                            // Start timer after brief delay for long press
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if isPressingDown && isEnabled {
                                    startLongPress()
                                }
                            }
                        }
                    }
            )
            .onChange(of: isPressingDown) { _, pressing in
                if !pressing {
                    stopLongPress()
                }
            }
            .onDisappear { stopLongPress() }
    }

    private func startLongPress() {
        guard longPressTimer == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Repeat action every 0.1 seconds while holding
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if isEnabled {
                action()
            } else {
                stopLongPress()
            }
        }
    }

    private func stopLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
}
