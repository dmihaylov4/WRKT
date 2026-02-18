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
        // Include primary, secondary, and tertiary muscles for comprehensive tracking
        var groups = Set<String>()

        // Process primary muscles
        for muscle in exercise.primaryMuscles {
            let normalized = normalizeMuscleGroup(muscle)
            if !normalized.isEmpty { groups.insert(normalized) }
        }

        // Process secondary muscles (important for recovery tracking)
        for muscle in exercise.secondaryMuscles {
            let normalized = normalizeMuscleGroup(muscle)
            if !normalized.isEmpty { groups.insert(normalized) }
        }

        // Process tertiary muscles (also important for comprehensive tracking)
        for muscle in exercise.tertiaryMuscles {
            let normalized = normalizeMuscleGroup(muscle)
            if !normalized.isEmpty { groups.insert(normalized) }
        }

        // If no muscles defined, infer from exercise characteristics
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
        // IMPORTANT: Check specific deltoid regions BEFORE general "delt" to allow granular tracking
        if lower.contains("chest") || lower.contains("pectoral") { return "Chest" }

        // Deltoid-specific tracking (granular)
        if lower.contains("anterior") && lower.contains("delt") { return "Anterior Deltoids" }
        if lower.contains("lateral") && lower.contains("delt") { return "Lateral Deltoids" }
        if lower.contains("posterior") && lower.contains("delt") { return "Posterior Deltoids" }
        if lower.contains("rear") && (lower.contains("delt") || lower.contains("shoulder")) { return "Posterior Deltoids" }
        if lower.contains("front") && (lower.contains("delt") || lower.contains("shoulder")) { return "Anterior Deltoids" }
        if lower.contains("side") && (lower.contains("delt") || lower.contains("shoulder")) { return "Lateral Deltoids" }
        if lower.contains("middle") && (lower.contains("delt") || lower.contains("shoulder")) { return "Lateral Deltoids" }
        // Generic shoulder/deltoid (when no specific region mentioned)
        if lower.contains("shoulder") || lower.contains("delt") { return "Shoulders" }

        // Check for full "latissimus" or word boundary "lats" to avoid matching "lateral"
        if lower.contains("back") || lower.contains("latissimus") || lower.contains("trap") || lower == "lats" { return "Back" }
        if lower.contains("bicep") { return "Biceps" }
        if lower.contains("tricep") { return "Triceps" }
        if lower.contains("quad") { return "Quadriceps" }
        if lower.contains("hamstring") { return "Hamstrings" }
        if lower.contains("glute") { return "Glutes" }
        if lower.contains("calf") || lower.contains("calves") { return "Calves" }
        if lower.contains("abs") || lower.contains("abdomin") || lower.contains("core") ||
           lower.contains("oblique") || lower.contains("serratus") { return "Abs" }
        if lower.contains("forearm") { return "Forearms" }

        // Return capitalized version of unrecognized muscles
        return muscle.capitalized
    }

    // MARK: - Bodyweight Percentage Estimation

    /// Returns the estimated percentage of bodyweight used in a bodyweight exercise
    /// Based on biomechanical analysis and research
    static func bodyweightPercentage(for exercise: Exercise) -> Double {
        let name = exercise.name.lowercased()

        // Push-ups and variations (60-75% bodyweight)
        if name.contains("push-up") || name.contains("pushup") || name.contains("push up") {
            if name.contains("decline") { return 0.75 } // Decline = more weight on arms
            if name.contains("incline") { return 0.50 } // Incline = less weight on arms
            if name.contains("diamond") || name.contains("close") { return 0.65 }
            return 0.64 // Standard push-up ~64% bodyweight
        }

        // Pull-ups and variations (100% bodyweight + slight assist from momentum)
        if name.contains("pull-up") || name.contains("pullup") || name.contains("pull up") {
            if name.contains("weighted") { return 1.0 } // User adds weight separately
            if name.contains("assisted") { return 0.5 } // Assume 50% assistance
            return 1.0 // Full bodyweight
        }

        // Chin-ups (100% bodyweight)
        if name.contains("chin-up") || name.contains("chinup") || name.contains("chin up") {
            if name.contains("assisted") { return 0.5 }
            return 1.0
        }

        // Dips (100% bodyweight)
        if name.contains("dip") && !name.contains("dumbbell") {
            if name.contains("assisted") { return 0.5 }
            return 1.0
        }

        // Inverted rows (50-70% bodyweight depending on angle)
        if name.contains("inverted row") || name.contains("body row") {
            return 0.6
        }

        // Muscle-ups (100% bodyweight + dynamic component)
        if name.contains("muscle-up") || name.contains("muscle up") {
            return 1.0
        }

        // Handstand push-ups (100% bodyweight)
        if name.contains("handstand") && (name.contains("push") || name.contains("press")) {
            return 1.0
        }

        // Plank and core (assume full bodyweight resistance)
        if name.contains("plank") || name.contains("l-sit") || name.contains("hollow hold") {
            return 1.0
        }

        // Pistol squats (100% bodyweight on one leg)
        if name.contains("pistol") {
            return 1.0
        }

        // Nordic curls (70-100% bodyweight depending on angle)
        if name.contains("nordic") {
            return 0.85
        }

        // Hanging exercises (100% bodyweight)
        if name.contains("hanging") && (name.contains("leg") || name.contains("knee")) {
            return 1.0
        }

        // Default: if it's clearly a bodyweight exercise but not matched above, use 70%
        return 0.7
    }

    /// Determines if an exercise is a bodyweight exercise (should use bodyweight for volume calculation)
    static func isBodyweightExercise(_ exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()

        let bodyweightKeywords = [
            "push-up", "pushup", "push up",
            "pull-up", "pullup", "pull up",
            "chin-up", "chinup", "chin up",
            "dip",
            "inverted row", "body row",
            "muscle-up", "muscle up",
            "handstand",
            "plank", "l-sit", "hollow hold",
            "pistol",
            "nordic",
            "hanging leg", "hanging knee"
        ]

        return bodyweightKeywords.contains { name.contains($0) }
    }
}
