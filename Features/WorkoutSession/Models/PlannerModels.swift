//
//  PlannerModels.swift
//  WRKT
//
//  Workout planner data models

import Foundation
import SwiftData

// MARK: - Planned Workout

@Model
final class PlannedWorkout {
    @Attribute(.unique) var id: UUID
    var scheduledDate: Date
    var splitDayName: String              // "Push", "Pull", "Legs", "Upper", etc.
    var splitID: UUID?                    // Reference to parent split
    var exercises: [PlannedExercise]
    var completedWorkoutID: UUID?         // Link to CompletedWorkout if done
    var status: String                    // WorkoutStatus raw value
    var notes: String?

    // Completion metrics
    var targetVolume: Double              // Sum of all ghost set volumes
    var actualVolume: Double?             // Volume from completed workout
    var completionPercentage: Double?     // actualVolume / targetVolume * 100

    init(id: UUID = UUID(), scheduledDate: Date, splitDayName: String, splitID: UUID? = nil,
         exercises: [PlannedExercise], status: WorkoutStatus = .scheduled) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.splitDayName = splitDayName
        self.splitID = splitID
        self.exercises = exercises
        self.status = status.rawValue

        // Calculate target volume from ghost sets
        self.targetVolume = exercises.reduce(0.0) { sum, exercise in
            sum + exercise.ghostSets.reduce(0.0) { setSum, ghost in
                setSum + (Double(ghost.reps) * ghost.weight)
            }
        }
    }

    var workoutStatus: WorkoutStatus {
        get { WorkoutStatus(rawValue: status) ?? .scheduled }
        set { status = newValue.rawValue }
    }

    /// Compute completion color based on percentage
    var completionColor: CompletionColor {
        guard let pct = completionPercentage else { return .none }

        switch pct {
        case 90...: return .green    // ≥90% = excellent
        case 70..<90: return .yellow // 70-89% = good effort
        case 50..<70: return .orange // 50-69% = partial
        default: return .red         // <50% = poor adherence
        }
    }
}

// MARK: - Planned Exercise

@Model
final class PlannedExercise {
    var id: UUID
    var exerciseID: String
    var exerciseName: String              // Cached for display
    var ghostSets: [GhostSet]
    var progressionStrategyRaw: String    // ProgressionStrategy encoded
    var order: Int
    var notes: String?

    // Last performance context
    var lastPerformance: String?          // "3×8@47.5kg (1140 vol)"
    var lastCompletedDate: Date?

    init(id: UUID = UUID(), exerciseID: String, exerciseName: String,
         ghostSets: [GhostSet], progressionStrategy: ProgressionStrategy = .static,
         order: Int, lastPerformance: String? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.ghostSets = ghostSets
        self.progressionStrategyRaw = progressionStrategy.encode()
        self.order = order
        self.lastPerformance = lastPerformance
    }

    var progressionStrategy: ProgressionStrategy {
        get { ProgressionStrategy.decode(progressionStrategyRaw) }
        set { progressionStrategyRaw = newValue.encode() }
    }

    /// Calculate target volume for this exercise
    var targetVolume: Double {
        ghostSets.reduce(0.0) { $0 + (Double($1.reps) * $1.weight) }
    }
}

// MARK: - Ghost Set

struct GhostSet: Codable, Identifiable {
    var id: UUID = UUID()
    var reps: Int
    var weight: Double
    var tag: String                       // SetTag raw value

    var setTag: SetTag {
        SetTag(rawValue: tag) ?? .working
    }

    init(reps: Int, weight: Double, tag: SetTag = .working) {
        self.reps = reps
        self.weight = weight
        self.tag = tag.rawValue
    }
}

// MARK: - Progression Strategy

enum ProgressionStrategy: Codable, Equatable, Hashable {
    case linear(increment: Double)        // Add X kg each session
    case percentage(factor: Double)       // Multiply by X% (e.g., 1.05 = +5%)
    case autoregulated                    // Advance only if completion ≥90%
    case `static`                         // Never change

    func encode() -> String {
        let encoder = JSONEncoder()
        return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? "{}"
    }

    static func decode(_ string: String) -> ProgressionStrategy {
        guard let data = string.data(using: .utf8),
              let strategy = try? JSONDecoder().decode(ProgressionStrategy.self, from: data) else {
            return .static
        }
        return strategy
    }

    /// Apply progression based on last completion percentage
    func advance(currentWeight: Double, lastCompletion: Double?) -> Double {
        switch self {
        case .linear(let increment):
            // Only advance if completion ≥70%
            guard let pct = lastCompletion, pct >= 70 else { return currentWeight }
            if pct >= 90 {
                return currentWeight + increment
            } else {
                return currentWeight // Repeat
            }

        case .percentage(let factor):
            guard let pct = lastCompletion, pct >= 70 else { return currentWeight }
            if pct >= 90 {
                return currentWeight * factor
            } else {
                return currentWeight
            }

        case .autoregulated:
            guard let pct = lastCompletion else { return currentWeight }
            if pct >= 90 {
                return currentWeight + 2.5 // Advance
            } else if pct >= 70 {
                return currentWeight // Repeat
            } else {
                return max(currentWeight * 0.9, 0) // Deload 10%
            }

        case .static:
            return currentWeight
        }
    }
}

// MARK: - Workout Status

enum WorkoutStatus: String, Codable {
    case scheduled
    case completed
    case partial                          // Some exercises done
    case skipped
    case rescheduled
}

enum CompletionColor {
    case green, yellow, orange, red, none
}

// MARK: - Workout Split

@Model
final class WorkoutSplit {
    @Attribute(.unique) var id: UUID
    var name: String                      // "PPL", "Upper/Lower", "Custom"
    var planBlocks: [PlanBlock]           // Ordered sequence of workout days
    var anchorDate: Date                  // When this split started
    var cursor: Int                       // Current position (Rolling mode)
    var reschedulePolicy: String          // ReschedulePolicy raw value
    var isActive: Bool

    init(id: UUID = UUID(), name: String, planBlocks: [PlanBlock],
         anchorDate: Date = .now, reschedulePolicy: ReschedulePolicy = .strict) {
        self.id = id
        self.name = name
        self.planBlocks = planBlocks
        self.anchorDate = anchorDate
        self.cursor = 0
        self.reschedulePolicy = reschedulePolicy.rawValue
        self.isActive = true
    }

    var policy: ReschedulePolicy {
        get { ReschedulePolicy(rawValue: reschedulePolicy) ?? .strict }
        set { reschedulePolicy = newValue.rawValue }
    }

    /// Get plan block for a given date based on reschedule policy
    func planBlock(for date: Date, cursor: Int) -> PlanBlock? {
        guard !planBlocks.isEmpty else { return nil }

        switch policy {
        case .strict:
            // Date-based: cycle repeats regardless of completion
            let daysSinceAnchor = Calendar.current.dateComponents([.day], from: anchorDate, to: date).day ?? 0
            // Handle negative indices (dates before anchor) by using positive modulo
            let index = ((daysSinceAnchor % planBlocks.count) + planBlocks.count) % planBlocks.count
            return planBlocks[index]

        case .rolling:
            // Cursor-based: only advances on completion
            let index = ((cursor % planBlocks.count) + planBlocks.count) % planBlocks.count
            return planBlocks[index]

        case .flexible:
            // Show backlog: any incomplete workout from cursor onward
            // This requires more complex logic in PlannerStore
            let index = ((cursor % planBlocks.count) + planBlocks.count) % planBlocks.count
            return planBlocks[index]
        }
    }
}

// MARK: - Plan Block

@Model
final class PlanBlock {
    var id: UUID
    var dayName: String                   // "Push", "Pull", "Legs", "Rest"
    var exercises: [PlanBlockExercise]
    var isRestDay: Bool

    init(id: UUID = UUID(), dayName: String, exercises: [PlanBlockExercise] = [], isRestDay: Bool = false) {
        self.id = id
        self.dayName = dayName
        self.exercises = exercises
        self.isRestDay = isRestDay
    }
}

@Model
final class PlanBlockExercise {
    var id: UUID
    var exerciseID: String
    var exerciseName: String
    var sets: Int
    var reps: Int
    var startingWeight: Double?           // Optional starting weight
    var progressionStrategyRaw: String
    var order: Int

    init(id: UUID = UUID(), exerciseID: String, exerciseName: String,
         sets: Int, reps: Int, startingWeight: Double? = nil,
         progressionStrategy: ProgressionStrategy = .linear(increment: 2.5), order: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.startingWeight = startingWeight
        self.progressionStrategyRaw = progressionStrategy.encode()
        self.order = order
    }

    var progressionStrategy: ProgressionStrategy {
        get { ProgressionStrategy.decode(progressionStrategyRaw) }
        set { progressionStrategyRaw = newValue.encode() }
    }
}

// MARK: - Reschedule Policy

enum ReschedulePolicy: String, Codable {
    case strict                           // Missed = missed (marks as skipped)
    case rolling                          // Cursor advances only on completion
    case flexible                         // Backlog accumulates until caught up
}
