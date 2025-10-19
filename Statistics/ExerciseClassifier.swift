//
//  ExerciseClassifier.swift
//  WRKT
//
//  Exercise classification for balance analytics

import Foundation

/// Helper to classify exercises into categories for balance tracking
enum ExerciseClassifier {

    // MARK: - Push/Pull Classification

    static func isPush(exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()
        let muscles = (exercise.primaryMuscles + exercise.secondaryMuscles).map { $0.lowercased() }
        let force = exercise.force?.lowercased()

        // Force-based classification (most reliable)
        if force == "push" { return true }
        if force == "pull" { return false }

        // Muscle-based classification
        let pushMuscles = ["chest", "pectoralis", "tricep", "shoulder", "delt", "quad"]
        let hasPushMuscle = muscles.contains { muscle in
            pushMuscles.contains { muscle.contains($0) }
        }

        // Name-based patterns
        let pushPatterns = ["press", "push", "fly", "flye", "raise", "extension", "squat", "lunge"]
        let hasPushPattern = pushPatterns.contains { name.contains($0) }

        return hasPushMuscle || hasPushPattern
    }

    static func isPull(exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()
        let muscles = (exercise.primaryMuscles + exercise.secondaryMuscles).map { $0.lowercased() }
        let force = exercise.force?.lowercased()

        // Force-based classification
        if force == "pull" { return true }
        if force == "push" { return false }

        // Muscle-based classification
        let pullMuscles = ["back", "lat", "trap", "rhomboid", "bicep", "hamstring", "glute"]
        let hasPullMuscle = muscles.contains { muscle in
            pullMuscles.contains { muscle.contains($0) }
        }

        // Name-based patterns
        let pullPatterns = ["pull", "row", "curl", "deadlift", "shrug", "chin", "lat"]
        let hasPullPattern = pullPatterns.contains { name.contains($0) }

        return hasPullMuscle || hasPullPattern
    }

    // MARK: - Horizontal/Vertical Classification

    static func isHorizontalPush(exercise: Exercise) -> Bool {
        guard isPush(exercise: exercise) else { return false }
        let name = exercise.name.lowercased()
        let horizontal = ["bench", "press", "push-up", "pushup", "fly", "flye", "dip"]
        let vertical = ["overhead", "shoulder", "military", "arnold"]

        let hasHorizontal = horizontal.contains { name.contains($0) }
        let hasVertical = vertical.contains { name.contains($0) }

        // If explicitly vertical, return false
        if hasVertical && !hasHorizontal { return false }
        // Otherwise if horizontal or ambiguous bench-like, return true
        return hasHorizontal || name.contains("chest")
    }

    static func isVerticalPush(exercise: Exercise) -> Bool {
        guard isPush(exercise: exercise) else { return false }
        let name = exercise.name.lowercased()
        let vertical = ["overhead", "shoulder", "military", "arnold", "lateral raise", "front raise"]
        return vertical.contains { name.contains($0) }
    }

    static func isHorizontalPull(exercise: Exercise) -> Bool {
        guard isPull(exercise: exercise) else { return false }
        let name = exercise.name.lowercased()
        let horizontal = ["row", "reverse fly", "face pull", "rear delt"]
        return horizontal.contains { name.contains($0) }
    }

    static func isVerticalPull(exercise: Exercise) -> Bool {
        guard isPull(exercise: exercise) else { return false }
        let name = exercise.name.lowercased()
        let vertical = ["pull-up", "pullup", "chin-up", "chinup", "lat pulldown", "pulldown"]
        return vertical.contains { name.contains($0) }
    }

    // MARK: - Compound/Isolation Classification

    static func isCompound(exercise: Exercise) -> Bool {
        let mechanic = exercise.mechanic?.lowercased()
        if mechanic == "compound" { return true }
        if mechanic == "isolation" { return false }

        let name = exercise.name.lowercased()
        let compound = ["squat", "deadlift", "press", "row", "pull-up", "pullup", "chin-up", "lunge", "clean", "snatch"]

        // Flies, raises, curls are typically isolation
        let isolation = ["fly", "flye", "raise", "curl", "extension", "kickback"]
        let hasIsolation = isolation.contains { name.contains($0) }

        if hasIsolation { return false }
        return compound.contains { name.contains($0) }
    }

    static func isIsolation(exercise: Exercise) -> Bool {
        !isCompound(exercise: exercise)
    }

    // MARK: - Bilateral/Unilateral Classification

    static func isUnilateral(exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()
        let unilateral = ["single", "one", "alternating", "dumbbell", "kettlebell"]

        // If explicitly says "single-arm", "one-leg", etc.
        if name.contains("single") || name.contains("one-arm") || name.contains("one-leg") {
            return true
        }

        // Alternating exercises are unilateral
        if name.contains("alternating") { return true }

        // Most dumbbell exercises are bilateral unless machine/barbell
        if name.contains("dumbbell") && !name.contains("both") { return true }

        return false
    }

    static func isBilateral(exercise: Exercise) -> Bool {
        !isUnilateral(exercise: exercise)
    }

    // MARK: - Lower Body Hinge/Squat Classification

    static func isHinge(exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()
        let hinge = ["deadlift", "rdl", "romanian", "good morning", "hip thrust", "glute bridge", "swing"]
        return hinge.contains { name.contains($0) }
    }

    static func isSquat(exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()
        let squat = ["squat", "lunge", "step-up", "leg press"]
        return squat.contains { name.contains($0) }
    }

    // MARK: - Muscle Group Extraction

    static func primaryMuscleGroups(for exercise: Exercise) -> [String] {
        // Normalize muscle groups to consistent naming
        var groups = Set<String>()

        for muscle in exercise.primaryMuscles {
            let normalized = normalizeMuscleGroup(muscle)
            if !normalized.isEmpty { groups.insert(normalized) }
        }

        // If no primary muscles, infer from exercise characteristics
        if groups.isEmpty {
            if isPush(exercise: exercise) && !isPull(exercise: exercise) {
                if exercise.name.lowercased().contains("chest") || exercise.name.lowercased().contains("bench") {
                    groups.insert("Chest")
                } else if exercise.name.lowercased().contains("shoulder") || exercise.name.lowercased().contains("press") {
                    groups.insert("Shoulders")
                }
            }
            if isPull(exercise: exercise) && !isPush(exercise: exercise) {
                if exercise.name.lowercased().contains("back") || exercise.name.lowercased().contains("row") {
                    groups.insert("Back")
                }
            }
        }

        return Array(groups)
    }

    private static func normalizeMuscleGroup(_ muscle: String) -> String {
        let lower = muscle.lowercased()

        // Map specific muscles to general groups
        if lower.contains("chest") || lower.contains("pectoral") { return "Chest" }
        if lower.contains("back") || lower.contains("lat") || lower.contains("trap") { return "Back" }
        if lower.contains("shoulder") || lower.contains("delt") { return "Shoulders" }
        if lower.contains("bicep") { return "Biceps" }
        if lower.contains("tricep") { return "Triceps" }
        if lower.contains("quad") { return "Quadriceps" }
        if lower.contains("hamstring") { return "Hamstrings" }
        if lower.contains("glute") { return "Glutes" }
        if lower.contains("calf") || lower.contains("calves") { return "Calves" }
        if lower.contains("abs") || lower.contains("abdominal") || lower.contains("core") { return "Abs" }
        if lower.contains("forearm") { return "Forearms" }

        // Return capitalized version of unrecognized muscles
        return muscle.capitalized
    }
}
