//
//  WeightSuggestionHelper.swift
//  WRKT
//
//  Helper for suggesting initial weights based on bodyweight and exercise type
//

import Foundation

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
}
