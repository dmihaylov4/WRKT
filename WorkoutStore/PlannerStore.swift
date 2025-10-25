//
//  PlannerStore.swift
//  WRKT
//
//  Manages workout planning, scheduling, and completion tracking

import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class PlannerStore {
    static let shared = PlannerStore()

    private var container: ModelContainer?
    private var context: ModelContext?
    private var workoutStore: WorkoutStoreV2?

    private init() {}

    func configure(container: ModelContainer, context: ModelContext, workoutStore: WorkoutStoreV2) {
        self.container = container
        self.context = context
        self.workoutStore = workoutStore
    }

    // MARK: - Split Management

    /// Create a new workout split
    func createSplit(name: String, planBlocks: [PlanBlock], policy: ReschedulePolicy = .strict) throws {
        guard let context = context else { return }

        let split = WorkoutSplit(name: name, planBlocks: planBlocks, anchorDate: .now, reschedulePolicy: policy)
        context.insert(split)
        try context.save()

        // Generate planned workouts for the next 30 days
        try generatePlannedWorkouts(for: split, days: 30)
    }

    /// Generate planned workouts from a split for the specified number of days
    func generatePlannedWorkouts(for split: WorkoutSplit, days: Int) throws {
        guard let context = context else { return }

        let calendar = Calendar.current
        // Start from the split's anchor date, not today
        let startDate = calendar.startOfDay(for: split.anchorDate)
        let splitID = split.id // Capture outside predicate

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }

            // Check if planned workout already exists for this date
            let existingPredicate = #Predicate<PlannedWorkout> { planned in
                planned.scheduledDate == date && planned.splitID == splitID
            }
            let existing = try context.fetch(FetchDescriptor(predicate: existingPredicate))
            if !existing.isEmpty { continue }

            // Get plan block for this date
            guard let block = split.planBlock(for: date, cursor: split.cursor),
                  !block.isRestDay else { continue }

            // Create planned exercises with ghost sets
            let plannedExercises = try block.exercises.sorted(by: { $0.order < $1.order }).map { blockEx in
                try createPlannedExercise(from: blockEx, exerciseID: blockEx.exerciseID)
            }

            // Create planned workout
            let planned = PlannedWorkout(
                scheduledDate: date,
                splitDayName: block.dayName,
                splitID: split.id,
                exercises: plannedExercises
            )

            context.insert(planned)
        }

        try context.save()
        print("📅 Generated planned workouts for \(days) days")
    }

    /// Create a PlannedExercise from a PlanBlockExercise with last performance context
    private func createPlannedExercise(from blockEx: PlanBlockExercise, exerciseID: String) throws -> PlannedExercise {
        // Fetch last completed performance for this exercise
        let lastPerformance = try fetchLastPerformance(exerciseID: exerciseID)

        // Determine base weight for ghost sets
        let baseWeight: Double
        let baseReps: Int

        // First priority: Use last working set from workout history
        if let workoutStore = workoutStore,
           let exercise = ExerciseRepository.shared.exercise(byID: exerciseID),
           let lastSet = workoutStore.lastWorkingSet(exercise: exercise) {
            baseWeight = lastSet.weightKg
            baseReps = lastSet.reps
            print("📋 Using last workout data for '\(blockEx.exerciseName)': \(baseReps) reps @ \(baseWeight)kg")
        }
        // Second priority: Use explicitly set starting weight
        else if let startingWeight = blockEx.startingWeight, startingWeight > 0 {
            baseWeight = startingWeight
            baseReps = blockEx.reps
            print("📋 Using explicit starting weight for '\(blockEx.exerciseName)': \(baseWeight)kg")
        }
        // Third priority: Suggest based on bodyweight
        else if let exercise = ExerciseRepository.shared.exercise(byID: exerciseID) {
            let suggestedWeight = WeightSuggestionHelper.suggestInitialWeight(for: exercise)
            let suggestedReps = WeightSuggestionHelper.suggestInitialReps(for: exercise)
            baseWeight = suggestedWeight
            baseReps = suggestedReps > 0 ? suggestedReps : blockEx.reps
            if suggestedWeight > 0 {
                print("📋 Using bodyweight-based suggestion for '\(blockEx.exerciseName)': \(baseWeight)kg")
            } else {
                print("📋 No weight data available for '\(blockEx.exerciseName)', starting at 0kg")
            }
        }
        // Fallback: No weight data available
        else {
            baseWeight = 0
            baseReps = blockEx.reps
        }

        // Generate ghost sets with progression
        let ghostSets = generateGhostSets(
            sets: blockEx.sets,
            reps: baseReps,
            baseWeight: baseWeight,
            strategy: blockEx.progressionStrategy,
            lastCompletion: lastPerformance?.completionPercentage
        )

        return PlannedExercise(
            exerciseID: exerciseID,
            exerciseName: blockEx.exerciseName,
            ghostSets: ghostSets,
            progressionStrategy: blockEx.progressionStrategy,
            order: blockEx.order,
            lastPerformance: lastPerformance?.summary
        )
    }

    /// Generate ghost sets with progression logic
    private func generateGhostSets(sets: Int, reps: Int, baseWeight: Double,
                                   strategy: ProgressionStrategy,
                                   lastCompletion: Double?) -> [GhostSet] {
        // Apply progression to base weight
        let progressedWeight = strategy.advance(currentWeight: baseWeight, lastCompletion: lastCompletion)

        // Generate working sets
        return (0..<sets).map { _ in
            GhostSet(reps: reps, weight: progressedWeight, tag: .working)
        }
    }

    /// Fetch last performance summary for an exercise
    private func fetchLastPerformance(exerciseID: String) throws -> (summary: String, completionPercentage: Double?)? {
        guard let workoutStore = workoutStore else { return nil }

        // Find most recent completed workout containing this exercise
        let completedWorkouts = workoutStore.completedWorkouts.sorted(by: { $0.date > $1.date })

        for workout in completedWorkouts {
            if let entry = workout.entries.first(where: { $0.exerciseID == exerciseID }) {
                let workingSets = entry.sets.filter { $0.tag == .working }
                guard !workingSets.isEmpty else { continue }

                let totalVolume = workingSets.reduce(0.0) { sum, set in
                    sum + (Double(set.reps) * set.weight)
                }
                let avgWeight = workingSets.reduce(0.0) { $0 + $1.weight } / Double(workingSets.count)
                let totalReps = workingSets.reduce(0) { $0 + $1.reps }

                let summary = "\(workingSets.count)×\(totalReps/workingSets.count)@\(String(format: "%.1f", avgWeight))kg (\(Int(totalVolume)) vol)"

                // Get completion percentage if this was from a planned workout
                var completionPct: Double?
                if let plannedID = workout.plannedWorkoutID,
                   let context = context {
                    let plannedPredicate = #Predicate<PlannedWorkout> { $0.id == plannedID }
                    if let planned = try? context.fetch(FetchDescriptor(predicate: plannedPredicate)).first {
                        completionPct = planned.completionPercentage
                    }
                }

                return (summary, completionPct)
            }
        }

        return nil
    }

    // MARK: - Workout Completion

    /// Mark a planned workout as completed and calculate completion metrics
    func completePlannedWorkout(_ planned: PlannedWorkout, completed: CompletedWorkout) throws {
        guard let context = context else { return }

        // Calculate actual volume from completed workout
        let actualVolume = completed.entries.reduce(0.0) { sum, entry in
            sum + entry.sets.filter({ $0.tag == .working }).reduce(0.0) { setSum, set in
                setSum + (Double(set.reps) * set.weight)
            }
        }

        // Update planned workout
        planned.completedWorkoutID = completed.id
        planned.actualVolume = actualVolume
        planned.completionPercentage = planned.targetVolume > 0 ? (actualVolume / planned.targetVolume * 100) : 0

        // Determine status
        let allExercisesCompleted = planned.exercises.allSatisfy { plannedEx in
            completed.entries.contains { $0.exerciseID == plannedEx.exerciseID }
        }

        planned.workoutStatus = allExercisesCompleted ? .completed : .partial

        // Update split cursor if using Rolling policy
        if let splitID = planned.splitID,
           let split = try? fetchSplit(id: splitID),
           split.policy == .rolling,
           planned.workoutStatus == .completed {
            split.cursor += 1
        }

        try context.save()
        print("✅ Planned workout completed: \(String(format: "%.1f", planned.completionPercentage ?? 0))%")
    }

    /// Fetch a split by ID
    private func fetchSplit(id: UUID) throws -> WorkoutSplit? {
        guard let context = context else { return nil }
        let predicate = #Predicate<WorkoutSplit> { $0.id == id }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// Mark planned workout as skipped
    func skipPlannedWorkout(_ planned: PlannedWorkout) throws {
        guard let context = context else { return }

        planned.workoutStatus = .skipped
        planned.completionPercentage = 0

        // Update split cursor based on policy
        if let splitID = planned.splitID,
           let split = try? fetchSplit(id: splitID) {
            switch split.policy {
            case .strict:
                // Cursor doesn't move, workout is just marked skipped
                break
            case .rolling:
                // Cursor doesn't advance on skip
                break
            case .flexible:
                // Keep in backlog
                planned.workoutStatus = .rescheduled
            }
        }

        try context.save()
    }

    /// Reschedule a planned workout to a new date
    func reschedulePlannedWorkout(_ planned: PlannedWorkout, to newDate: Date) throws {
        guard let context = context else { return }

        planned.scheduledDate = newDate
        planned.workoutStatus = .rescheduled
        try context.save()
    }

    // MARK: - Query Helpers

    /// Fetch planned workout for a specific date
    func plannedWorkout(for date: Date) throws -> PlannedWorkout? {
        guard let context = context else { return nil }
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        let predicate = #Predicate<PlannedWorkout> { planned in
            planned.scheduledDate == targetDate
        }

        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// Fetch all planned workouts in a date range
    func plannedWorkouts(from start: Date, to end: Date) throws -> [PlannedWorkout] {
        guard let context = context else { return [] }

        let startDate = start
        let endDate = end

        let predicate = #Predicate<PlannedWorkout> { planned in
            planned.scheduledDate >= startDate && planned.scheduledDate <= endDate
        }

        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\PlannedWorkout.scheduledDate)]
        )

        return try context.fetch(descriptor)
    }

    /// Get active split
    func activeSplit() throws -> WorkoutSplit? {
        guard let context = context else { return nil }

        let predicate = #Predicate<WorkoutSplit> { $0.isActive == true }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }
}

