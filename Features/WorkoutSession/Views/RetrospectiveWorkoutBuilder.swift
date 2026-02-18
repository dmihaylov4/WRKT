//
//  RetrospectiveWorkoutBuilder.swift
//  WRKT
//
//  Builder for logging past workouts retroactively
//

import SwiftUI

struct RetrospectiveWorkoutBuilder: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    @State private var workoutName: String = ""
    @State private var entries: [WorkoutEntry] = []
    @State private var showingExercisePicker = false
    @State private var editingEntry: WorkoutEntry? = nil
    @State private var startTime: Date
    @State private var endTime: Date

    init(date: Date) {
        self.date = date
        // Default to 1 hour workout ending at the selected date's end of day
        let endOfDay = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date
        _endTime = State(initialValue: endOfDay)
        _startTime = State(initialValue: endOfDay.addingTimeInterval(-3600)) // 1 hour before
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Workout Details Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Workout Details")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .padding(.bottom, 4)

                        // Workout Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Workout Name")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Semantic.textSecondary)
                            TextField("e.g., Upper Body, Leg Day", text: $workoutName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(DS.Semantic.fillSubtle, in: ChamferedRectangle(.small))
                                .overlay(
                                    ChamferedRectangle(.small)
                                        .stroke(DS.Semantic.border, lineWidth: 1)
                                )
                        }

                        // Date Pickers
                        VStack(spacing: 12) {
                            HStack {
                                Text("Started")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Spacer()
                                DatePicker("", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                            }

                            Divider()

                            HStack {
                                Text("Finished")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Spacer()
                                DatePicker("", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                            }
                        }

                        Text("If left blank, workout name will be auto-classified based on exercises")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .padding(16)
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                    .overlay(
                        ChamferedRectangle(.large)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                    // Exercises Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Exercises")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Spacer()

                            Text("\(entries.count)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Semantic.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DS.Theme.accent.opacity(0.1), in: ChamferedRectangle(.micro))
                        }
                        .padding(.horizontal, 16)

                        if entries.isEmpty {
                            // Empty state
                            Button {
                                showingExercisePicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(DS.Theme.accent)

                                    Text("Add First Exercise")
                                        .font(.headline)
                                        .foregroundStyle(DS.Semantic.textPrimary)

                                    Spacer()
                                }
                                .padding(16)
                                .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                                .overlay(
                                    ChamferedRectangle(.large)
                                        .stroke(DS.Semantic.border.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        } else {
                            // Exercise list
                            VStack(spacing: 8) {
                                ForEach(entries) { entry in
                                    Button {
                                        editingEntry = entry
                                        Haptics.light()
                                    } label: {
                                        RetrospectiveExerciseRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)

                            // Add more button
                            Button {
                                showingExercisePicker = true
                                Haptics.light()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(DS.Theme.accent)

                                    Text("Add Exercise")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(DS.Theme.accent)

                                    Spacer()
                                }
                                .padding(12)
                                .background(DS.Theme.accent.opacity(0.05), in: ChamferedRectangle(.medium))
                                .overlay(
                                    ChamferedRectangle(.medium)
                                        .stroke(DS.Theme.accent.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(DS.Semantic.surface)
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRetrospectiveWorkout()
                        Haptics.success()
                    }
                    .disabled(entries.isEmpty || endTime <= startTime)
                    .fontWeight(.semibold)
                    .foregroundStyle(entries.isEmpty || endTime <= startTime ? DS.Semantic.textSecondary : DS.Theme.accent)
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

    private func deleteEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    private func binding(for entry: WorkoutEntry) -> Binding<WorkoutEntry> {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            fatalError("Entry not found")
        }
        return $entries[index]
    }

    // MARK: - Save

    private func saveRetrospectiveWorkout() {
        let trimmedName = workoutName.trimmingCharacters(in: .whitespaces)
        let completed = CompletedWorkout(
            id: UUID(),
            date: endTime,
            startedAt: startTime,
            entries: entries.map { entry in
                // Mark all sets as completed
                var updatedEntry = entry
                updatedEntry.sets = entry.sets.map { set in
                    var updatedSet = set
                    updatedSet.isCompleted = true
                    return updatedSet
                }
                return updatedEntry
            },
            plannedWorkoutID: nil,
            workoutName: trimmedName.isEmpty ? nil : trimmedName
        )

        store.addWorkout(completed)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Retrospective Exercise Row

private struct RetrospectiveExerciseRow: View {
    let entry: WorkoutEntry

    private var completedSets: Int {
        entry.sets.filter { $0.isCompleted }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(DS.Theme.accent.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Theme.accent)
                )

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
                            .background(DS.Theme.accent.opacity(0.1), in: ChamferedRectangle(.micro))
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
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
