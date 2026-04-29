//
//  ProgramSerializer.swift
//  WRKT
//
//  Converts WorkoutSplit models to and from shareable wire payloads.
//

import Foundation

enum ProgramSerializer {
    struct CreatorAttribution: Sendable, Equatable {
        let userID: String
        let username: String?
        let displayName: String?
    }

    static func outgoingAttribution(
        for split: WorkoutSplit,
        currentUserID: String,
        currentUsername: String?,
        currentDisplayName: String?
    ) -> CreatorAttribution {
        CreatorAttribution(
            userID: split.creatorUserID ?? currentUserID,
            username: split.creatorUsername ?? currentUsername,
            displayName: split.creatorDisplayName ?? currentDisplayName
        )
    }

    static func toStructure(
        _ split: WorkoutSplit,
        creator: CreatorAttribution? = nil
    ) -> SharedProgramStructure {
        SharedProgramStructure(
            creator: creator.map {
                .init(userID: $0.userID, username: $0.username, displayName: $0.displayName)
            },
            planBlocks: split.planBlocks
                .enumerated()
                .map { index, block in
                    SharedProgramStructure.Block(
                        dayName: block.dayName,
                        isRestDay: block.isRestDay,
                        order: index,
                        exercises: block.exercises
                            .sorted(by: { $0.order < $1.order })
                            .map { exercise in
                                SharedProgramStructure.Exercise(
                                    exerciseID: exercise.exerciseID,
                                    exerciseName: exercise.exerciseName,
                                    sets: exercise.sets,
                                    reps: exercise.reps,
                                    progressionStrategy: progression(from: exercise.progressionStrategy),
                                    order: exercise.order
                                )
                            }
                    )
                }
        )
    }

    static func fromStructure(
        _ structure: SharedProgramStructure,
        name: String,
        reschedulePolicy: ReschedulePolicy,
        creator: CreatorAttribution? = nil,
        description: String?,
        originProgramID: UUID?
    ) -> WorkoutSplit {
        let effectiveCreator = structure.creator.map {
            CreatorAttribution(userID: $0.userID, username: $0.username, displayName: $0.displayName)
        } ?? creator

        let split = WorkoutSplit(
            name: name,
            planBlocks: structure.planBlocks
                .sorted(by: { $0.order < $1.order })
                .map { block in
                    PlanBlock(
                        dayName: block.dayName,
                        exercises: block.exercises
                            .sorted(by: { $0.order < $1.order })
                            .map { exercise in
                                PlanBlockExercise(
                                    exerciseID: exercise.exerciseID,
                                    exerciseName: exercise.exerciseName,
                                    sets: exercise.sets,
                                    reps: exercise.reps,
                                    progressionStrategy: progression(from: exercise.progressionStrategy),
                                    order: exercise.order
                                )
                            },
                        isRestDay: block.isRestDay
                    )
                },
            anchorDate: .now,
            reschedulePolicy: reschedulePolicy,
            creatorUserID: effectiveCreator?.userID,
            creatorUsername: effectiveCreator?.username,
            creatorDisplayName: effectiveCreator?.displayName,
            originProgramID: originProgramID,
            programDescription: description,
            importedAt: originProgramID == nil ? nil : Date()
        )
        split.isActive = false
        return split
    }

    private static func progression(from strategy: ProgressionStrategy) -> SharedProgramStructure.Progression {
        switch strategy {
        case .linear(let increment):
            return .linear(increment: increment)
        case .percentage(let factor):
            return .percentage(factor: factor)
        case .autoregulated:
            return .autoregulated
        case .static:
            return .static
        }
    }

    private static func progression(from strategy: SharedProgramStructure.Progression) -> ProgressionStrategy {
        switch strategy {
        case .linear(let increment):
            return .linear(increment: increment)
        case .percentage(let factor):
            return .percentage(factor: factor)
        case .autoregulated:
            return .autoregulated
        case .static:
            return .static
        }
    }
}
