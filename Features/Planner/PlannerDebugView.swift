//
//  PlannerDebugView.swift
//  WRKT
//
//  Debug interface for testing workout planner

import SwiftUI
import SwiftData

struct PlannerDebugView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dependencies) private var dependencies

    @State private var message: String = ""
    @State private var showMessage = false

    private var planner: PlannerStore { dependencies.plannerStore }
    private var repo: ExerciseRepository { dependencies.exerciseRepository }

    var body: some View {
        Form {
      

            Section("Generate Workouts") {
        
                Button("Clear All Plans & Workouts") {
                    clearPlannedWorkouts()
                }
            }

          

            if showMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Planner Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func createPPLSplit() {
        do {
            // Get some sample exercises
            let benchPress = repo.exercises.first { $0.name.lowercased().contains("bench press") }
            let squat = repo.exercises.first { $0.name.lowercased().contains("squat") }
            let deadlift = repo.exercises.first { $0.name.lowercased().contains("deadlift") }
            let pullUp = repo.exercises.first { $0.name.lowercased().contains("pull") && $0.name.lowercased().contains("up") }

            // Push day
            let pushBlock = PlanBlock(dayName: "Push", exercises: [
                PlanBlockExercise(
                    exerciseID: benchPress?.id ?? "bench-press",
                    exerciseName: benchPress?.name ?? "Bench Press",
                    sets: 3, reps: 10, startingWeight: 60,
                    progressionStrategy: .linear(increment: 2.5),
                    order: 0
                ),
                PlanBlockExercise(
                    exerciseID: "shoulder-press",
                    exerciseName: "Shoulder Press",
                    sets: 3, reps: 8, startingWeight: 30,
                    progressionStrategy: .linear(increment: 2.5),
                    order: 1
                )
            ])

            // Pull day
            let pullBlock = PlanBlock(dayName: "Pull", exercises: [
                PlanBlockExercise(
                    exerciseID: pullUp?.id ?? "pull-up",
                    exerciseName: pullUp?.name ?? "Pull-ups",
                    sets: 3, reps: 8, startingWeight: 0, // Bodyweight
                    progressionStrategy: .autoregulated,
                    order: 0
                ),
                PlanBlockExercise(
                    exerciseID: "barbell-row",
                    exerciseName: "Barbell Row",
                    sets: 3, reps: 10, startingWeight: 50,
                    progressionStrategy: .linear(increment: 2.5),
                    order: 1
                )
            ])

            // Legs day
            let legsBlock = PlanBlock(dayName: "Legs", exercises: [
                PlanBlockExercise(
                    exerciseID: squat?.id ?? "squat",
                    exerciseName: squat?.name ?? "Squat",
                    sets: 3, reps: 10, startingWeight: 80,
                    progressionStrategy: .linear(increment: 5),
                    order: 0
                ),
                PlanBlockExercise(
                    exerciseID: deadlift?.id ?? "deadlift",
                    exerciseName: deadlift?.name ?? "Deadlift",
                    sets: 3, reps: 8, startingWeight: 100,
                    progressionStrategy: .linear(increment: 5),
                    order: 1
                )
            ])

            context.insert(pushBlock)
            context.insert(pullBlock)
            context.insert(legsBlock)

            try planner.createSplit(
                name: "PPL",
                planBlocks: [pushBlock, pullBlock, legsBlock],
                policy: .strict
            )

            showSuccess("✅ Created PPL split with 3 days")
        } catch {
            showError("❌ Failed to create split: \(error.localizedDescription)")
        }
    }

    private func createUpperLowerSplit() {
        do {
            let upperBlock = PlanBlock(dayName: "Upper Body", exercises: [
                PlanBlockExercise(
                    exerciseID: "bench-press",
                    exerciseName: "Bench Press",
                    sets: 4, reps: 8, startingWeight: 60,
                    progressionStrategy: .linear(increment: 2.5),
                    order: 0
                ),
                PlanBlockExercise(
                    exerciseID: "pull-up",
                    exerciseName: "Pull-ups",
                    sets: 3, reps: 10, startingWeight: 0,
                    progressionStrategy: .autoregulated,
                    order: 1
                )
            ])

            let lowerBlock = PlanBlock(dayName: "Lower Body", exercises: [
                PlanBlockExercise(
                    exerciseID: "squat",
                    exerciseName: "Squat",
                    sets: 4, reps: 8, startingWeight: 80,
                    progressionStrategy: .linear(increment: 5),
                    order: 0
                ),
                PlanBlockExercise(
                    exerciseID: "deadlift",
                    exerciseName: "Romanian Deadlift",
                    sets: 3, reps: 10, startingWeight: 60,
                    progressionStrategy: .linear(increment: 5),
                    order: 1
                )
            ])

            context.insert(upperBlock)
            context.insert(lowerBlock)

            try planner.createSplit(
                name: "Upper/Lower",
                planBlocks: [upperBlock, lowerBlock],
                policy: .rolling
            )

            showSuccess("✅ Created Upper/Lower split")
        } catch {
            showError("❌ Failed to create split: \(error.localizedDescription)")
        }
    }

    private func createFullBodySplit() {
        do {
            let fullBodyBlock = PlanBlock(dayName: "Full Body", exercises: [
                PlanBlockExercise(
                    exerciseID: "squat",
                    exerciseName: "Squat",
                    sets: 3, reps: 10, startingWeight: 70,
                    progressionStrategy: .linear(increment: 5),
                    order: 0
                ),
                PlanBlockExercise(
                    exerciseID: "bench-press",
                    exerciseName: "Bench Press",
                    sets: 3, reps: 10, startingWeight: 50,
                    progressionStrategy: .linear(increment: 2.5),
                    order: 1
                ),
                PlanBlockExercise(
                    exerciseID: "pull-up",
                    exerciseName: "Pull-ups",
                    sets: 3, reps: 8, startingWeight: 0,
                    progressionStrategy: .autoregulated,
                    order: 2
                )
            ])

            context.insert(fullBodyBlock)

            try planner.createSplit(
                name: "Full Body",
                planBlocks: [fullBodyBlock],
                policy: .strict
            )

            showSuccess("✅ Created Full Body split")
        } catch {
            showError("❌ Failed to create split: \(error.localizedDescription)")
        }
    }

    private func generateWorkouts() {
        do {
            guard let activeSplit = try planner.activeSplit() else {
                showError("⚠️ No active split found. Create a split first.")
                return
            }

            try planner.generatePlannedWorkouts(for: activeSplit, days: 30)
            showSuccess("✅ Generated 30 days of planned workouts")
        } catch {
            showError("❌ Failed to generate workouts: \(error.localizedDescription)")
        }
    }

    private func clearPlannedWorkouts() {
        do {
            // Delete all planned workouts
            let workoutsDescriptor = FetchDescriptor<PlannedWorkout>()
            let workouts = try context.fetch(workoutsDescriptor)

            for workout in workouts {
                context.delete(workout)
            }

            // Delete all workout splits (this should cascade delete planBlocks)
            let splitsDescriptor = FetchDescriptor<WorkoutSplit>()
            let splits = try context.fetch(splitsDescriptor)

            for split in splits {
                context.delete(split)
            }

            // Explicitly delete all plan blocks to be safe
            let blocksDescriptor = FetchDescriptor<PlanBlock>()
            let blocks = try context.fetch(blocksDescriptor)

            for block in blocks {
                context.delete(block)
            }

            try context.save()
            showSuccess("✅ Cleared \(workouts.count) workouts, \(splits.count) splits, and \(blocks.count) blocks")
        } catch {
            showError("❌ Failed to clear workouts: \(error.localizedDescription)")
        }
    }

    private func showSuccess(_ msg: String) {
        message = msg
        showMessage = true
       
    }

    private func showError(_ msg: String) {
        message = msg
        showMessage = true
       
    }
}

// MARK: - Planned Workouts List

private struct PlannedWorkoutsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedWorkout.scheduledDate) private var plannedWorkouts: [PlannedWorkout]

    var body: some View {
        List {
            if plannedWorkouts.isEmpty {
                ContentUnavailableView(
                    "No Planned Workouts",
                    systemImage: "calendar.badge.clock",
                    description: Text("Generate planned workouts from the debug menu")
                )
            } else {
                ForEach(plannedWorkouts) { planned in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(planned.splitDayName)
                                .font(.headline)
                            Spacer()
                            Text(planned.workoutStatus.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(statusColor(planned.workoutStatus))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }

                        Text(planned.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(planned.exercises.count) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let completion = planned.completionPercentage {
                            Text("Completion: \(Int(completion))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteWorkouts)
            }
        }
        .navigationTitle("Planned Workouts (\(plannedWorkouts.count))")
    }

    private func statusColor(_ status: WorkoutStatus) -> Color {
        switch status {
        case .scheduled: return .blue
        case .completed: return .green
        case .partial: return .yellow
        case .skipped: return .gray
        case .rescheduled: return .orange
        }
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            context.delete(plannedWorkouts[index])
        }
    }
}

// MARK: - Splits List

private struct SplitsListView: View {
    @Environment(\.modelContext) private var context
    @Query private var splits: [WorkoutSplit]

    var body: some View {
        List {
            if splits.isEmpty {
                ContentUnavailableView(
                    "No Splits",
                    systemImage: "calendar.badge.plus",
                    description: Text("Create a split from the debug menu")
                )
            } else {
                ForEach(splits) { split in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(split.name)
                                .font(.headline)
                            Spacer()
                            if split.isActive {
                                Text("ACTIVE")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }

                        Text("\(split.planBlocks.count) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Policy: \(split.policy.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Cursor: \(split.cursor)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteSplits)
            }
        }
        .navigationTitle("Splits (\(splits.count))")
    }

    private func deleteSplits(at offsets: IndexSet) {
        for index in offsets {
            context.delete(splits[index])
        }
    }
}
