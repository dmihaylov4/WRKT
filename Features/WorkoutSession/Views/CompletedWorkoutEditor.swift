//
//  CompletedWorkoutEditor.swift
//  WRKT
//
//  Editor for completed workouts - allows adding/removing exercises and editing sets
//  Particularly useful for editing Apple Watch workouts synced via HealthKit
//

import SwiftUI

struct CompletedWorkoutEditor: View {
    let workout: CompletedWorkout
    let isNewWorkout: Bool  // Whether this is a new workout being created

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    @State private var workoutName: String = ""
    @State private var entries: [WorkoutEntry] = []
    @State private var showingExercisePicker = false
    @State private var editingEntry: WorkoutEntry? = nil
    @State private var hasChanges = false

    init(workout: CompletedWorkout, isNewWorkout: Bool = false) {
        self.workout = workout
        self.isNewWorkout = isNewWorkout
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Workout name (editable)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout Name")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        TextField("e.g., Upper Body, Leg Day", text: $workoutName)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .onChange(of: workoutName) { _, _ in
                                hasChanges = true
                            }
                    }

                    // Date (read-only)
                    HStack {
                        Text("Date")
                            .foregroundStyle(DS.Semantic.textPrimary)
                        Spacer()
                        Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    // HealthKit badge (if matched)
                    if workout.matchedHealthKitUUID != nil {
                        Label("Synced with Apple Watch", systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(DS.Theme.accent)
                    }
                } header: {
                    Text("Workout Details")
                } footer: {
                    Text("If left blank, workout name will be auto-classified based on exercises")
                        .font(.caption2)
                }

                Section {
                    if entries.isEmpty {
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add First Exercise", systemImage: "plus.circle.fill")
                                .foregroundStyle(DS.Theme.accent)
                        }
                    } else {
                        ForEach(entries) { entry in
                            WorkoutExerciseRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingEntry = entry
                                }
                        }
                        .onDelete(perform: deleteExercise)

                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle")
                                .foregroundStyle(DS.Theme.accent)
                        }
                    }
                } header: {
                    Text("Exercises (\(entries.count))")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Semantic.surface)
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!hasChanges)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(onSelect: addExercise)
                    .environmentObject(repo)
                    .environmentObject(FavoritesStore())
            }
            .sheet(item: $editingEntry) { entry in
                RetrospectiveSetEditor(entry: binding(for: entry))
                    .environmentObject(store)
            }
            .onAppear {
                workoutName = workout.workoutName ?? ""
                entries = workout.entries
            }
            .onChange(of: entries) { _, _ in
                hasChanges = true
            }
        }
    }

    // MARK: - Entry Management

    private func addExercise(_ exercise: Exercise) {
        // Get suggested starting weight from history
        let suggestedWeight: Double = {
            if let lastSet = store.lastWorkingSet(exercise: exercise) {
                return lastSet.weightKg
            }
            return 0
        }()

        let newEntry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles,
            sets: [
                SetInput(reps: 10, weight: suggestedWeight, isCompleted: true),
                SetInput(reps: 10, weight: suggestedWeight, isCompleted: true),
                SetInput(reps: 10, weight: suggestedWeight, isCompleted: true)
            ]
        )

        entries.append(newEntry)
        Haptics.light()
    }

    private func deleteExercise(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        hasChanges = true
    }

    private func binding(for entry: WorkoutEntry) -> Binding<WorkoutEntry> {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            fatalError("Entry not found")
        }
        return $entries[index]
    }

    // MARK: - Save

    private func saveChanges() {
        var updatedWorkout = workout
        updatedWorkout.entries = entries
        // Only set workoutName if it's not empty, otherwise keep it nil for auto-classification
        updatedWorkout.workoutName = workoutName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : workoutName.trimmingCharacters(in: .whitespaces)

        if isNewWorkout {
            // Add as a new workout
            store.addWorkout(updatedWorkout)
        } else {
            // Update existing workout
            store.updateWorkout(updatedWorkout)
        }

        Haptics.success()
        dismiss()
    }
}

// MARK: - Workout Exercise Row

private struct WorkoutExerciseRow: View {
    let entry: WorkoutEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.exerciseName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)

                // Sets preview
                HStack(spacing: 4) {
                    ForEach(Array(entry.sets.prefix(3).enumerated()), id: \.offset) { _, set in
                        Text("\(set.reps)×\(set.weight.safeInt)kg")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Theme.accent.opacity(0.1), in: Capsule())
                    }

                    if entry.sets.count > 3 {
                        Text("+\(entry.sets.count - 3)")
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
