//
//  PlannerStore.swift
//  WRKT
//
//  Manages workout planning, scheduling, and completion tracking

import Foundation
import SwiftData
import Observation
import OSLog

enum PlannerScheduleError: LocalizedError {
    case conflictingWorkout(date: Date, workoutName: String)
    case missingSplit

    var errorDescription: String? {
        switch self {
        case .conflictingWorkout(let date, let workoutName):
            let formattedDate = date.formatted(date: .abbreviated, time: .omitted)
            return "\"\(workoutName)\" is already planned for \(formattedDate). Choose a different date."
        case .missingSplit:
            return "The active plan for this workout could not be found."
        }
    }
}

struct ActivationCustomization: Sendable {
    var startDate: Date
    var restDayOverrides: [UUID: Bool]
    var startingWeights: [UUID: Double]
}

struct PlanAdherence {
    let plannedSessions: Int
    let completedOnPlan: Int
    let missedSessions: Int
    var rate: Double { plannedSessions > 0 ? Double(completedOnPlan) / Double(plannedSessions) : 1.0 }
}

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
        AppLogger.info("Generated planned workouts for \(days) days", category: AppLogger.app)
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
           
        }
        // Second priority: Use explicitly set starting weight
        else if let startingWeight = blockEx.startingWeight, startingWeight > 0 {
            baseWeight = startingWeight
            baseReps = blockEx.reps
            
        }
        // Third priority: Suggest based on bodyweight
        else if let exercise = ExerciseRepository.shared.exercise(byID: exerciseID) {
            let suggestedWeight = WeightSuggestionHelper.suggestInitialWeight(for: exercise)
            let suggestedReps = WeightSuggestionHelper.suggestInitialReps(for: exercise)
            baseWeight = suggestedWeight
            baseReps = suggestedReps > 0 ? suggestedReps : blockEx.reps
           
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

                let summary = "\(workingSets.count)×\(totalReps/workingSets.count)@\(String(format: "%.1f", avgWeight))kg (\(totalVolume.safeInt) vol)"

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

        // Determine status: a planned exercise is satisfied if the user completed it
        // (via its original or a swapped entry that carries the plannedExerciseID), or
        // intentionally removed it during the session (excused set).
        let allExercisesCompleted = planned.exercises.allSatisfy { plannedEx in
            completed.entries.contains { $0.plannedExerciseID == plannedEx.id }
                || completed.excusedPlannedExerciseIDs.contains(plannedEx.id)
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
 
    }

    /// Fetch and complete a planned workout by ID
    func completePlannedWorkout(id: UUID, completed: CompletedWorkout) {
        do {
            guard let planned = try plannedWorkout(id: id) else {
                AppLogger.warning("Planned workout not found for completion: \(id)", category: AppLogger.storage)
                return
            }

            try completePlannedWorkout(planned, completed: completed)
        } catch {
            AppLogger.error("Failed to complete planned workout \(id): \(error)", category: AppLogger.storage)
        }
    }

    /// Permanently update a planned exercise's target exercise (for "make this swap permanent").
    func updatePlannedExercise(id: UUID, newExerciseID: String, newExerciseName: String) {
        guard let context else { return }
        let predicate = #Predicate<PlannedExercise> { $0.id == id }
        guard let ex = try? context.fetch(FetchDescriptor(predicate: predicate)).first else { return }
        ex.exerciseID = newExerciseID
        ex.exerciseName = newExerciseName
        try? context.save()
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
        let normalizedDate = Calendar.current.startOfDay(for: newDate)

        if let conflict = try conflictingPlannedWorkout(on: normalizedDate, excluding: [planned.id]) {
            throw PlannerScheduleError.conflictingWorkout(
                date: normalizedDate,
                workoutName: conflict.splitDayName
            )
        }

        planned.scheduledDate = normalizedDate
        planned.workoutStatus = .rescheduled
        try context.save()
    }

    /// Shift all upcoming incomplete workouts for a split by a fixed number of days.
    func shiftUpcomingPlannedWorkouts(for splitID: UUID, startingAt startDate: Date, by dayOffset: Int) throws {
        guard let context = context else { return }
        guard dayOffset != 0 else { return }

        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let splitWorkouts = try upcomingPlannedWorkouts(for: splitID, startingAt: normalizedStartDate)
        let movingIDs = Set(splitWorkouts.map(\.id))

        for workout in splitWorkouts {
            guard let shiftedDate = calendar.date(byAdding: .day, value: dayOffset, to: workout.scheduledDate) else {
                continue
            }

            let normalizedShiftedDate = calendar.startOfDay(for: shiftedDate)
            if let conflict = try conflictingPlannedWorkout(on: normalizedShiftedDate, excluding: movingIDs) {
                throw PlannerScheduleError.conflictingWorkout(
                    date: normalizedShiftedDate,
                    workoutName: conflict.splitDayName
                )
            }
        }

        for workout in splitWorkouts {
            guard let shiftedDate = calendar.date(byAdding: .day, value: dayOffset, to: workout.scheduledDate) else {
                continue
            }
            workout.scheduledDate = calendar.startOfDay(for: shiftedDate)
        }

        guard let split = try fetchSplit(id: splitID) else {
            throw PlannerScheduleError.missingSplit
        }
        if let shiftedAnchorDate = calendar.date(byAdding: .day, value: dayOffset, to: split.anchorDate) {
            split.anchorDate = calendar.startOfDay(for: shiftedAnchorDate)
        }

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

    /// Fetch planned workout by ID
    func plannedWorkout(id: UUID) throws -> PlannedWorkout? {
        guard let context = context else { return nil }

        let predicate = #Predicate<PlannedWorkout> { planned in
            planned.id == id
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

    /// Compute plan adherence for a given week (starts at weekStart, spans 7 days)
    func adherence(forWeek weekStart: Date) -> PlanAdherence {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return PlanAdherence(plannedSessions: 0, completedOnPlan: 0, missedSessions: 0)
        }
        let planned = (try? plannedWorkouts(from: weekStart, to: weekEnd)) ?? []
        let completedCount = planned.filter { $0.workoutStatus == .completed }.count
        let now = Date()
        let missedCount = planned.filter { $0.workoutStatus != .completed && $0.scheduledDate < now }.count
        return PlanAdherence(plannedSessions: planned.count, completedOnPlan: completedCount, missedSessions: missedCount)
    }

    /// Compute plan adherence for multiple weeks
    func adherence(forWeeks weekStarts: [Date]) -> [PlanAdherence] {
        weekStarts.map { adherence(forWeek: $0) }
    }

    /// Get active split
    func activeSplit() throws -> WorkoutSplit? {
        guard let context = context else { return nil }

        let predicate = #Predicate<WorkoutSplit> { $0.isActive == true }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    /// All workout splits sorted by newest available timestamp first.
    func splitLibrary() throws -> [WorkoutSplit] {
        guard let context = context else { return [] }

        let splits = try context.fetch(FetchDescriptor<WorkoutSplit>())
        return splits.sorted { lhs, rhs in
            let lhsDate = lhs.createdAt ?? lhs.importedAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? rhs.importedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func insert(_ split: WorkoutSplit) throws {
        guard let context = context else { return }
        context.insert(split)
        try context.save()
    }

    func saveContext() throws {
        try context?.save()
    }

    func activate(_ split: WorkoutSplit, customization: ActivationCustomization) throws {
        guard let context = context else { return }

        let activeSplits = try context.fetch(
            FetchDescriptor<WorkoutSplit>(predicate: #Predicate { $0.isActive == true })
        )
        for other in activeSplits where other.id != split.id {
            other.isActive = false
        }

        for block in split.planBlocks {
            if let override = customization.restDayOverrides[block.id] {
                block.isRestDay = override
            }

            for exercise in block.exercises {
                if let weight = customization.startingWeights[exercise.id] {
                    exercise.startingWeight = weight
                }
            }
        }

        split.anchorDate = split.anchorDateAligningFirstWorkout(to: customization.startDate)
        split.cursor = 0
        split.isActive = true

        try context.save()
        try replanUpcomingWorkouts(for: split, fromDate: split.anchorDate)
    }

    func deleteUpcomingPlannedWorkouts(for split: WorkoutSplit) throws {
        guard let context = context else { return }
        let splitID = split.id
        let cutoff = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate {
                $0.splitID == splitID &&
                $0.scheduledDate >= cutoff &&
                $0.completedWorkoutID == nil
            }
        )
        let workouts = try context.fetch(descriptor)
        for workout in workouts {
            context.delete(workout)
        }
        try context.save()
    }

    func replanUpcomingWorkouts(for split: WorkoutSplit, fromDate: Date = .now) throws {
        guard let context = context else { return }

        let splitID = split.id
        let cutoff = Calendar.current.startOfDay(for: fromDate)
        let descriptor = FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate {
                $0.splitID == splitID &&
                $0.scheduledDate >= cutoff &&
                $0.completedWorkoutID == nil
            }
        )

        let futurePlanned = try context.fetch(descriptor)
        for workout in futurePlanned {
            context.delete(workout)
        }

        try context.save()
        try generatePlannedWorkouts(for: split, days: 30)
    }

    // MARK: - Data Migration Utilities

    /// Migrate exercise IDs in all planned workouts
    /// Use this when you've updated exercise IDs in SplitTemplates
    func migrateExerciseIDs(mapping: [String: String]) throws {
        guard let context = context else { return }

        AppLogger.info("🔄 Starting exercise ID migration for \(mapping.count) mappings", category: AppLogger.storage)

        // Fetch all planned workouts
        let allWorkouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        var updatedCount = 0

        for workout in allWorkouts {
            for exercise in workout.exercises {
                if let newID = mapping[exercise.exerciseID] {
                    AppLogger.debug("   Updating: \(exercise.exerciseID) → \(newID)", category: AppLogger.storage)
                    exercise.exerciseID = newID
                    updatedCount += 1
                }
            }
        }

        try context.save()
        AppLogger.success("✅ Migration complete: Updated \(updatedCount) exercises across \(allWorkouts.count) planned workouts", category: AppLogger.storage)
    }

    /// Delete all planned workouts (useful for resetting)
    func deleteAllPlannedWorkouts() throws {
        guard let context = context else { return }

        let allWorkouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        for workout in allWorkouts {
            context.delete(workout)
        }
        try context.save()

        AppLogger.success("✅ Deleted \(allWorkouts.count) planned workouts", category: AppLogger.storage)
    }

    private func conflictingPlannedWorkout(on date: Date, excluding excludedIDs: Set<UUID>) throws -> PlannedWorkout? {
        guard let context = context else { return nil }

        let normalizedDate = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<PlannedWorkout> { planned in
            planned.scheduledDate == normalizedDate
        }

        return try context.fetch(FetchDescriptor(predicate: predicate))
            .first(where: { !excludedIDs.contains($0.id) })
    }

    private func upcomingPlannedWorkouts(for splitID: UUID, startingAt startDate: Date) throws -> [PlannedWorkout] {
        guard let context = context else { return [] }

        let normalizedStartDate = Calendar.current.startOfDay(for: startDate)
        let descriptor = FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate {
                $0.splitID == splitID &&
                $0.scheduledDate >= normalizedStartDate &&
                $0.completedWorkoutID == nil
            },
            sortBy: [SortDescriptor(\PlannedWorkout.scheduledDate)]
        )

        return try context.fetch(descriptor)
    }
}

@MainActor
protocol PlannerStoreInterface: AnyObject {
    func splitLibrary() throws -> [WorkoutSplit]
    func insert(_ split: WorkoutSplit) throws
    func activate(_ split: WorkoutSplit, customization: ActivationCustomization) throws
    func replanUpcomingWorkouts(for split: WorkoutSplit, fromDate: Date) throws
    func deleteUpcomingPlannedWorkouts(for split: WorkoutSplit) throws
    func deleteAllPlannedWorkouts() throws
    func saveContext() throws
}

extension PlannerStore: PlannerStoreInterface {}
