//
//  WeightSuggestionHelper.swift
//  WRKT
//
//  Helper for suggesting weights:
//  1. Initial weights for beginners based on bodyweight
//  2. Progressive overload suggestions based on workout history
//

import Foundation

// MARK: - Models

struct ProgressionSuggestion {
    let suggestedWeight: Double
    let suggestedReps: Int
    let previousWeight: Double  // For showing diff in UI
    let reason: String

    enum ProgressionType {
        case increaseWeight
        case increaseReps
        case maintain
    }

    let type: ProgressionType
}

// MARK: - Weight Suggestion Helper

struct WeightSuggestionHelper {

    /// Suggest initial weight for an exercise based on user's bodyweight
    /// - Parameters:
    ///   - exercise: The exercise to suggest weight for
    ///   - bodyweightKg: User's bodyweight in kg (from UserDefaults if not provided)
    /// - Returns: Suggested weight in kg, or 0 if no suggestion can be made
    static func suggestInitialWeight(for exercise: Exercise, bodyweightKg: Double? = nil) -> Double {
        // Get user's bodyweight
        let weight = bodyweightKg ?? UserDefaults.standard.double(forKey: "user_bodyweight_kg")
        guard weight > 0 else { return 0 }

        // Check if this is a bodyweight exercise
        let equipment = exercise.equipment?.lowercased() ?? ""
        let isBodyweight = equipment.contains("bodyweight") || equipment.contains("body weight") || equipment == "body only"

        if isBodyweight {
            // For bodyweight exercises, use the user's bodyweight
            return weight
        }

        // For weighted exercises with no history, check exercise category for rough estimates
        let category = exercise.category.lowercased()
        let name = exercise.name.lowercased()

        // Upper body pushing (bench, overhead press, etc.)
        if category.contains("chest") || name.contains("bench") || name.contains("press") && !name.contains("leg") {
            return weight * 0.5  // ~50% bodyweight
        }

        // Pulling movements (rows, pull-ups with weight, etc.)
        if category.contains("back") || name.contains("row") || name.contains("pull") {
            return weight * 0.4  // ~40% bodyweight
        }

        // Leg movements (squat, leg press, etc.)
        if category.contains("legs") || category.contains("quadriceps") || category.contains("hamstrings") || name.contains("squat") || name.contains("leg") {
            return weight * 0.75  // ~75% bodyweight
        }

        // Shoulders and arms
        if category.contains("shoulders") || category.contains("biceps") || category.contains("triceps") {
            return weight * 0.25  // ~25% bodyweight
        }

        // Default: no suggestion for unknown exercises
        return 0
    }

    /// Suggest initial reps for an exercise based on its category
    /// - Parameter exercise: The exercise to suggest reps for
    /// - Returns: Suggested reps (typically 8-12 for hypertrophy)
    static func suggestInitialReps(for exercise: Exercise) -> Int {
        let category = exercise.category.lowercased()
        let mechanics = exercise.mechanic?.lowercased() ?? ""

        // Compound movements: lower reps
        if mechanics.contains("compound") {
            return 5
        }

        // Isolation movements: moderate reps
        if mechanics.contains("isolation") {
            return 10
        }

        // Leg exercises: can handle more volume
        if category.contains("legs") || category.contains("quadriceps") || category.contains("hamstrings") {
            return 10
        }

        // Default hypertrophy range
        return 8
    }

    // MARK: - Progressive Overload

    /// Analyzes workout history and suggests progression for the next set
    /// - Parameters:
    ///   - exercise: The exercise to analyze
    ///   - lastSetWeight: The weight used in the previous set (fallback)
    ///   - lastSetReps: The reps used in the previous set (fallback)
    ///   - workoutStore: Access to workout history
    /// - Returns: Suggested weight and reps, or nil if no progression detected
    static func suggestProgression(
        for exercise: Exercise,
        lastSetWeight: Double,
        lastSetReps: Int,
        workoutStore: WorkoutStoreV2
    ) -> ProgressionSuggestion? {

        // Get last 3 workouts with this exercise
        let recentWorkouts = workoutStore.completedWorkouts
            .filter { workout in
                workout.entries.contains(where: { $0.exerciseID == exercise.id })
            }
            .prefix(3)

        AppLogger.info("[Progression] Checking \(exercise.name) - Found \(recentWorkouts.count) recent workouts", category: AppLogger.workout)

        guard recentWorkouts.count >= 2 else {
            // Not enough history for progression analysis
            AppLogger.info("[Progression] Not enough history (\(recentWorkouts.count) workouts)", category: AppLogger.workout)
            return nil
        }

        // Extract the working sets from each workout (filter out warm-ups)
        let workoutSets: [[SetInput]] = recentWorkouts.compactMap { workout in
            guard let entry = workout.entries.first(where: { $0.exerciseID == exercise.id }) else {
                return nil
            }
            return entry.sets.filter { $0.tag == .working }
        }

        guard workoutSets.count >= 2 else { return nil }

        // Analyze the pattern
        let lastWorkoutSets = workoutSets[0]
        let secondLastWorkoutSets = workoutSets[1]

        // Check if weights are similar across last 2 workouts (within 1kg tolerance)
        let lastWeights = lastWorkoutSets.map { $0.weight }
        let secondLastWeights = secondLastWorkoutSets.map { $0.weight }

        guard let avgLastWeight = average(lastWeights),
              let avgSecondLastWeight = average(secondLastWeights) else {
            return nil
        }

        // Check if user is plateaued (same weight for 2+ workouts)
        let isPlateaued = abs(avgLastWeight - avgSecondLastWeight) < 1.0

        AppLogger.info("[Progression] Last: \(formatWeight(avgLastWeight)), Previous: \(formatWeight(avgSecondLastWeight)), Plateaued: \(isPlateaued)", category: AppLogger.workout)

        guard isPlateaued else {
            // User is already progressing, don't interfere
            AppLogger.info("[Progression] User already progressing naturally, no suggestion needed", category: AppLogger.workout)
            return nil
        }

        // Check if user completed all reps successfully in last workout
        let completedAllReps = lastWorkoutSets.allSatisfy { $0.isCompleted }

        AppLogger.info("[Progression] All sets completed: \(completedAllReps)", category: AppLogger.workout)

        guard completedAllReps else {
            // User struggled, maintain current weight
            AppLogger.info("[Progression] User didn't complete all reps, maintaining weight", category: AppLogger.workout)
            return nil
        }

        // Get average reps from last workout
        let lastReps = lastWorkoutSets.map { $0.reps }
        guard let avgLastReps = average(lastReps) else { return nil }

        // Decide progression strategy
        if avgLastReps >= 10 {
            // User is hitting high reps - suggest weight increase
            let increment = calculateWeightIncrement(currentWeight: avgLastWeight)
            return ProgressionSuggestion(
                suggestedWeight: avgLastWeight + increment,
                suggestedReps: Int(avgLastReps),
                previousWeight: avgLastWeight,
                reason: "You've completed \(Int(avgLastReps)) reps at \(formatWeight(avgLastWeight)) for 2 workouts. Time to add weight!",
                type: .increaseWeight
            )
        } else if avgLastReps >= 6 && avgLastReps < 10 {
            // User is in moderate rep range - suggest adding 1 rep
            return ProgressionSuggestion(
                suggestedWeight: avgLastWeight,
                suggestedReps: Int(avgLastReps) + 1,
                previousWeight: avgLastWeight,
                reason: "You've completed \(Int(avgLastReps)) reps at \(formatWeight(avgLastWeight)) for 2 workouts. Try adding 1 rep!",
                type: .increaseReps
            )
        }

        // Default: maintain current weight
        return nil
    }

    // MARK: - Private Helpers

    /// Calculate appropriate weight increment based on current weight
    private static func calculateWeightIncrement(currentWeight: Double) -> Double {
        if currentWeight < 20 {
            return 1.0  // Small increment for light weights (dumbbells, etc.)
        } else if currentWeight < 60 {
            return 2.5  // Standard increment for moderate weights
        } else {
            return 5.0  // Larger increment for heavy weights
        }
    }

    /// Calculate average of array, handling empty arrays
    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Calculate average of int array
    private static func average(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    /// Format weight for display
    private static func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0fkg", weight)
        } else {
            return String(format: "%.1fkg", weight)
        }
    }
}
