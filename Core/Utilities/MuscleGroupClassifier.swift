//
//  MuscleGroupClassifier.swift
//  WRKT
//
//  Classifies workouts by muscle groups for display
//

import Foundation

enum MuscleGroupClassifier {
    /// Classify a workout based on muscles trained, returns title with " Workout" suffix
    /// Examples: "Shoulders Workout", "Upper Body Workout", "Full Body Workout"
    static func classify(_ workout: CompletedWorkout) -> String {
        let bodyPart = classifyBodyPart(workout)
        return "\(bodyPart) Workout"
    }

    /// Classify workout into body part/region without suffix
    /// Used internally and for other utilities that need just the body part name
    static func classifyBodyPart(_ workout: CompletedWorkout) -> String {
        // Get all muscle groups from all exercises
        let allMuscles = workout.entries.flatMap { $0.muscleGroups }
        guard !allMuscles.isEmpty else {
            let exerciseCount = workout.entries.count
            return exerciseCount == 1 ? "Exercise" : "Mixed"
        }

        let uniqueMuscles = Set(allMuscles.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })

        // Define muscle group mappings (matches HomeView structure)
        let muscleGroups: [String: Set<String>] = [
            "Chest": ["chest", "pecs", "pectorals"],
            "Back": ["back", "lats", "latissimus", "rhomboids"],
            "Shoulders": ["shoulders", "delts", "deltoids"],
            "Biceps": ["biceps"],
            "Triceps": ["triceps"],
            "Forearms": ["forearms"],
            "Quads": ["quads", "quadriceps"],
            "Hamstrings": ["hamstrings"],
            "Glutes": ["glutes"],
            "Calves": ["calves"],
            "Abs": ["abs", "abdominals"],
            "Core": ["core", "obliques"]
        ]

        // Find which specific muscle groups are trained
        var trainedGroups: Set<String> = []
        for (groupName, keywords) in muscleGroups {
            for muscle in uniqueMuscles {
                if keywords.contains(muscle) {
                    trainedGroups.insert(groupName)
                    break
                }
            }
        }

        // If single specific muscle group, return it
        if trainedGroups.count == 1, let group = trainedGroups.first {
            return group
        }

        // Classify into regions
        let upperBodyGroups: Set<String> = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms"]
        let lowerBodyGroups: Set<String> = ["Quads", "Hamstrings", "Glutes", "Calves"]
        let coreGroups: Set<String> = ["Abs", "Core"]

        let trainedUpper = trainedGroups.intersection(upperBodyGroups)
        let trainedLower = trainedGroups.intersection(lowerBodyGroups)
        let trainedCore = trainedGroups.intersection(coreGroups)

        // Full body if both upper and lower
        if !trainedUpper.isEmpty && !trainedLower.isEmpty {
            return "Full Body"
        }

        // Upper body if multiple upper muscles
        if trainedUpper.count > 1 {
            return "Upper Body"
        }

        // Lower body if multiple lower muscles
        if trainedLower.count > 1 {
            return "Lower Body"
        }

        // Single region
        if !trainedUpper.isEmpty {
            return "Upper Body"
        }
        if !trainedLower.isEmpty {
            return "Lower Body"
        }
        if !trainedCore.isEmpty {
            return "Core"
        }

        // Fallback
        return "Mixed"
    }

    /// Generate workout title for HealthKit strength workouts (Apple Watch)
    /// Uses custom workout name if available, otherwise returns "Strength Workout"
    static func classifyHealthKitStrength(_ run: Run) -> String {
        if let customName = run.workoutName, !customName.isEmpty {
            return customName
        }
        return "Strength Workout"
    }
}
