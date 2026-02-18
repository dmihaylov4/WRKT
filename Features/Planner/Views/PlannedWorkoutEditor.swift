//
//  PlannedWorkoutEditor.swift
//  WRKT
//
//  Editor for creating and editing planned workouts
//

import SwiftUI
import SwiftData

struct PlannedWorkoutEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2

    let date: Date
    let existingWorkout: PlannedWorkout?

    @State private var workoutName: String = ""
    @State private var plannedExercises: [PlannedExerciseConfig] = []
    @State private var showingExercisePicker = false
    @State private var editingExercise: PlannedExerciseConfig? = nil
    @State private var showingDeleteConfirmation = false

    // Temporary config struct for editing before saving to SwiftData
    struct PlannedExerciseConfig: Identifiable {
        let id: UUID
        var exerciseID: String
        var exerciseName: String
        var ghostSets: [GhostSet]
        var notes: String?
        var order: Int

        init(id: UUID = UUID(), exerciseID: String, exerciseName: String,
             ghostSets: [GhostSet] = [GhostSet(reps: 10, weight: 0)],
             notes: String? = nil, order: Int = 0) {
            self.id = id
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.ghostSets = ghostSets
            self.notes = notes
            self.order = order
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Date (read-only)
                    HStack {
                        Text("Date")
                            .foregroundStyle(DS.Semantic.textPrimary)
                        Spacer()
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    // Workout name (optional)
                    TextField("Workout Name (Optional)", text: $workoutName)
                        .foregroundStyle(DS.Semantic.textPrimary)
                } header: {
                    Text("Workout Details")
                }

                Section {
                    if plannedExercises.isEmpty {
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add First Exercise", systemImage: "plus.circle.fill")
                                .foregroundStyle(DS.Theme.accent)
                        }
                    } else {
                        ForEach(plannedExercises) { exercise in
                            PlannedExerciseRow(exercise: exercise)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingExercise = exercise
                                }
                        }
                        .onDelete(perform: deleteExercise)
                        .onMove(perform: moveExercise)

                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle")
                                .foregroundStyle(DS.Theme.accent)
                        }
                    }
                } header: {
                    Text("Exercises (\(plannedExercises.count))")
                }

                // Delete section for existing workouts
                if existingWorkout != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Workout", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Semantic.surface)
            .navigationTitle(existingWorkout == nil ? "Plan Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePlannedWorkout()
                    }
                    .disabled(plannedExercises.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete Workout?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deletePlannedWorkout()
                }
            } message: {
                Text("This will permanently delete this planned workout.")
            }
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
        }
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
        guard let existing = existingWorkout else { return }

        workoutName = existing.splitDayName
        plannedExercises = existing.exercises.map { exercise in
            PlannedExerciseConfig(
                id: exercise.id,
                exerciseID: exercise.exerciseID,
                exerciseName: exercise.exerciseName,
                ghostSets: exercise.ghostSets,
                notes: exercise.notes,
                order: exercise.order
            )
        }.sorted { $0.order < $1.order }
    }

    private func savePlannedWorkout() {
        // Convert configs to PlannedExercise models
        let exercises = plannedExercises.map { config in
            PlannedExercise(
                id: config.id,
                exerciseID: config.exerciseID,
                exerciseName: config.exerciseName,
                ghostSets: config.ghostSets,
                progressionStrategy: .static,
                order: config.order
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
        } else {
            // Create new workout
            let planned = PlannedWorkout(
                scheduledDate: Calendar.current.startOfDay(for: date),
                splitDayName: workoutName.isEmpty ? "Custom Workout" : workoutName,
                exercises: exercises
            )
            modelContext.insert(planned)
        }

        try? modelContext.save()

        // Notify calendar to reload planned workouts
        NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)

        Haptics.success()
        dismiss()
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

// MARK: - Planned Exercise Row

private struct PlannedExerciseRow: View {
    let exercise: PlannedWorkoutEditor.PlannedExerciseConfig

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.exerciseName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)

                // Ghost sets preview
                HStack(spacing: 4) {
                    ForEach(exercise.ghostSets.prefix(3)) { set in
                        Text("\(set.reps)×\(set.weight.safeInt)kg")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Theme.accent.opacity(0.1), in: ChamferedRectangle(.micro))
                    }

                    if exercise.ghostSets.count > 3 {
                        Text("+\(exercise.ghostSets.count - 3)")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
                .opacity(0.6)
        }
        .padding(.vertical, 4)
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
                                .font(.headline.weight(.semibold))
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
                            .font(.subheadline)
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
                                .font(.headline.weight(.semibold))
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                // Delete button
                Button {
                    onDelete()
                    Haptics.light()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
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
                        .font(.caption2.weight(.semibold))
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
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .multilineTextAlignment(.center)
                                .frame(minWidth: 40)
                        } else {
                            Text("\(set.reps)")
                                .font(.title2.monospacedDigit().weight(.bold))
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
                        .font(.caption2.weight(.semibold))
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
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 70, maxWidth: 100)
                        } else {
                            Text(String(format: "%.1f", displayWeight))
                                .font(.title2.monospacedDigit().weight(.bold))
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
            .font(.title2)
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
