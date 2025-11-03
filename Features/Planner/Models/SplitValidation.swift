//
//  SplitValidation.swift
//  WRKT
//
//  Split validation helpers and warnings

import Foundation

// MARK: - Split Warnings (Non-blocking)

enum SplitWarning: Identifiable {
    case noLegWork
    case noBackWork
    case noPushWork
    case noPullWork
    case imbalancedPushPull(push: Int, pull: Int)
    case allIsolationExercises(part: String)
    case sessionTooLong(minutes: Int, part: String)
    case lowVolume(sets: Int, part: String)
    case noCompoundMovements(part: String)

    var id: String {
        switch self {
        case .noLegWork: return "no-legs"
        case .noBackWork: return "no-back"
        case .noPushWork: return "no-push"
        case .noPullWork: return "no-pull"
        case .imbalancedPushPull: return "push-pull-ratio"
        case .allIsolationExercises(let part): return "isolation-\(part)"
        case .sessionTooLong(_, let part): return "too-long-\(part)"
        case .lowVolume(_, let part): return "low-volume-\(part)"
        case .noCompoundMovements(let part): return "no-compounds-\(part)"
        }
    }

    var severity: Severity {
        switch self {
        case .noLegWork, .noBackWork, .imbalancedPushPull:
            return .high
        case .sessionTooLong, .allIsolationExercises:
            return .medium
        case .lowVolume, .noCompoundMovements, .noPushWork, .noPullWork:
            return .low
        }
    }

    enum Severity: Int {
        case low = 1, medium = 2, high = 3

        var icon: String {
            switch self {
            case .low: return "info.circle"
            case .medium: return "exclamationmark.triangle"
            case .high: return "exclamationmark.octagon"
            }
        }

        var color: String {
            switch self {
            case .low: return "blue"
            case .medium: return "orange"
            case .high: return "red"
            }
        }
    }

    var message: String {
        switch self {
        case .noLegWork:
            return "No leg exercises detected. Consider adding squats, deadlifts, or leg press for balanced development."
        case .noBackWork:
            return "No back exercises detected. Add rows or pulldowns for posture and balance."
        case .noPushWork:
            return "Limited pushing exercises. Consider adding pressing movements."
        case .noPullWork:
            return "Limited pulling exercises. Consider adding rows or pulldowns."
        case .imbalancedPushPull(let push, let pull):
            return "Push:Pull ratio is \(push):\(pull). For shoulder health, aim for 1:1 or 2:3 (more pulling)."
        case .allIsolationExercises(let part):
            return "'\(part)' contains only isolation exercises. Start with at least one compound movement."
        case .sessionTooLong(let minutes, let part):
            return "'\(part)' estimated at \(minutes) minutes. Consider reducing exercises for better recovery."
        case .lowVolume(let sets, let part):
            return "'\(part)' has only \(sets) total sets. Consider adding 1-2 more exercises for adequate volume."
        case .noCompoundMovements(let part):
            return "'\(part)' has no compound movements. Add exercises like squats, deadlifts, bench press, or rows."
        }
    }

    var suggestion: String {
        switch self {
        case .noLegWork:
            return "Add: Squats, Leg Press, or Romanian Deadlifts"
        case .noBackWork:
            return "Add: Barbell Rows, Pull-ups, or Lat Pulldowns"
        case .noPushWork:
            return "Add: Bench Press, Overhead Press, or Push-ups"
        case .noPullWork:
            return "Add: Rows, Pull-ups, or Face Pulls"
        case .imbalancedPushPull:
            return "Add more pulling exercises or reduce pushing volume"
        case .allIsolationExercises:
            return "Start with a compound movement, then add isolation work"
        case .sessionTooLong:
            return "Remove 1-2 exercises or split into two sessions"
        case .lowVolume:
            return "Add 1-2 more exercises or increase sets"
        case .noCompoundMovements:
            return "Add a heavy compound lift as your first exercise"
        }
    }
}

// MARK: - Validation Logic

@MainActor
struct SplitValidator {
    let repo: ExerciseRepository

    func validateSplit(
        partExercises: [String: [ExerciseTemplate]]
    ) -> [SplitWarning] {
        var warnings: [SplitWarning] = []

        // Collect all exercises
        let allExercises = partExercises.values.flatMap { $0 }
        let exerciseDetails = allExercises.compactMap { repo.byID[$0.exerciseID] }

        // Check major muscle groups
        warnings.append(contentsOf: checkMuscleGroupCoverage(exerciseDetails))

        // Check push/pull balance
        if let balanceWarning = checkPushPullBalance(exerciseDetails) {
            warnings.append(balanceWarning)
        }

        // Check each part individually
        for (partName, exercises) in partExercises {
            warnings.append(contentsOf: validatePart(name: partName, exercises: exercises))
        }

        return warnings.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    private func checkMuscleGroupCoverage(_ exercises: [Exercise]) -> [SplitWarning] {
        var warnings: [SplitWarning] = []

        let primaryMuscles = exercises.flatMap { $0.primaryMuscles.map { $0.lowercased() } }

        // Check legs
        let legMuscles = ["quads", "quadriceps", "hamstrings", "glutes", "calves", "leg"]
        let hasLegs = primaryMuscles.contains { muscle in
            legMuscles.contains { muscle.contains($0) }
        }
        if !hasLegs {
            warnings.append(.noLegWork)
        }

        // Check back
        let backMuscles = ["lats", "latissimus", "traps", "trapezius", "back", "rhomboids"]
        let hasBack = primaryMuscles.contains { muscle in
            backMuscles.contains { muscle.contains($0) }
        }
        if !hasBack {
            warnings.append(.noBackWork)
        }

        return warnings
    }

    private func checkPushPullBalance(_ exercises: [Exercise]) -> SplitWarning? {
        let pushCount = exercises.filter { $0.moveBucket == .push }.count
        let pullCount = exercises.filter { $0.moveBucket == .pull }.count

        guard pullCount > 0 else {
            return .noPullWork
        }

        guard pushCount > 0 else {
            return .noPushWork
        }

        let ratio = Double(pushCount) / Double(pullCount)
        if ratio > 1.5 {
            return .imbalancedPushPull(push: pushCount, pull: pullCount)
        }

        return nil
    }

    private func validatePart(name: String, exercises: [ExerciseTemplate]) -> [SplitWarning] {
        var warnings: [SplitWarning] = []

        let exerciseDetails = exercises.compactMap { repo.byID[$0.exerciseID] }

        // Check for compounds
        let hasCompound = exerciseDetails.contains { $0.mechanic?.lowercased() == "compound" }
        if !hasCompound {
            warnings.append(.noCompoundMovements(part: name))
        }

        // Check if all isolation
        let allIsolation = !exerciseDetails.isEmpty && exerciseDetails.allSatisfy {
            $0.mechanic?.lowercased() == "isolation"
        }
        if allIsolation {
            warnings.append(.allIsolationExercises(part: name))
        }

        // Check volume
        let totalSets = exercises.reduce(0) { $0 + $1.sets }
        if totalSets < 12 {
            warnings.append(.lowVolume(sets: totalSets, part: name))
        }

        // Check duration
        let estimatedMinutes = estimateSessionDuration(exercises)
        if estimatedMinutes > 75 {
            warnings.append(.sessionTooLong(minutes: estimatedMinutes, part: name))
        }

        return warnings
    }

    func estimateSessionDuration(_ exercises: [ExerciseTemplate]) -> Int {
        let exerciseDetails = exercises.compactMap { repo.byID[$0.exerciseID] }

        var totalMinutes = 0

        for (template, exercise) in zip(exercises, exerciseDetails) {
            let isCompound = exercise.mechanic?.lowercased() == "compound"
            let minutesPerSet = isCompound ? 4 : 2.5 // Compound needs more rest
            totalMinutes += Int(Double(template.sets) * minutesPerSet)
        }

        return totalMinutes
    }
}

// MARK: - Name Validation

struct NameValidator {
    static func validateSplitName(
        _ name: String,
        existingNames: [String]
    ) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // Empty check
        guard !trimmed.isEmpty else {
            return .invalid(message: "Name cannot be empty", suggestion: nil)
        }

        // Length check
        guard trimmed.count <= 30 else {
            return .invalid(
                message: "Name too long (max 30 characters)",
                suggestion: String(trimmed.prefix(30))
            )
        }

        // Uniqueness check
        if existingNames.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            return .invalid(
                message: "'\(trimmed)' already exists",
                suggestion: "\(trimmed) (Custom)"
            )
        }

        return .valid
    }
}

enum ValidationResult {
    case valid
    case invalid(message: String, suggestion: String?)
}
