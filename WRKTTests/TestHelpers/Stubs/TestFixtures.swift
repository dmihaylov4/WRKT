//
//  TestFixtures.swift
//  WRKTTests
//
//  Sample data for testing
//

import Foundation
@testable import WRKT

enum TestFixtures {

    // MARK: - Exercises

    static let benchPress = Exercise(
        id: "barbell-bench-press",
        name: "Barbell Bench Press",
        force: "push",
        level: "intermediate",
        mechanic: "compound",
        equipment: "barbell",
        secondaryEquipment: nil,
        grip: "overhand",
        primaryMuscles: ["chest"],
        secondaryMuscles: ["triceps", "shoulders"],
        tertiaryMuscles: [],
        instructions: [
            "Lie on bench with feet flat on floor",
            "Grip bar slightly wider than shoulder width",
            "Lower bar to chest with control",
            "Press bar back up to starting position"
        ],
        images: nil,
        category: "strength",
        subregionTags: ["upper_chest"]
    )

    static let squat = Exercise(
        id: "barbell-squat",
        name: "Barbell Squat",
        force: "push",
        level: "intermediate",
        mechanic: "compound",
        equipment: "barbell",
        secondaryEquipment: nil,
        grip: nil,
        primaryMuscles: ["quadriceps"],
        secondaryMuscles: ["glutes", "hamstrings"],
        tertiaryMuscles: ["calves"],
        instructions: [
            "Position bar on upper back",
            "Stand with feet shoulder width apart",
            "Lower by bending knees and hips",
            "Drive through heels to return to start"
        ],
        images: nil,
        category: "strength",
        subregionTags: ["lower_body"]
    )

    static let deadlift = Exercise(
        id: "barbell-deadlift",
        name: "Barbell Deadlift",
        force: "pull",
        level: "advanced",
        mechanic: "compound",
        equipment: "barbell",
        secondaryEquipment: nil,
        grip: "overhand",
        primaryMuscles: ["lower_back"],
        secondaryMuscles: ["glutes", "hamstrings", "traps"],
        tertiaryMuscles: ["forearms"],
        instructions: [
            "Stand with feet hip width apart",
            "Bend and grip bar at shoulder width",
            "Keep back straight and lift by extending hips",
            "Lower bar with control to ground"
        ],
        images: nil,
        category: "strength",
        subregionTags: ["posterior_chain"]
    )

    // MARK: - Sets

    static let warmupSet = SetInput(
        reps: 10,
        weight: 20,
        tag: .warmup,
        autoWeight: false,
        didSeedFromMemory: false,
        isCompleted: true
    )

    static let workingSet = SetInput(
        reps: 8,
        weight: 60,
        tag: .working,
        autoWeight: false,
        didSeedFromMemory: true,
        isCompleted: true
    )

    static let backoffSet = SetInput(
        reps: 12,
        weight: 50,
        tag: .backoff,
        autoWeight: false,
        didSeedFromMemory: false,
        isCompleted: true
    )

    // MARK: - Workout Entries

    static let benchPressEntry = WorkoutEntry(
        id: UUID(),
        exerciseID: benchPress.id,
        exerciseName: benchPress.name,
        muscleGroups: benchPress.primaryMuscles,
        sets: [warmupSet, workingSet, workingSet, backoffSet],
        activeSetIndex: 0
    )

    static let squatEntry = WorkoutEntry(
        id: UUID(),
        exerciseID: squat.id,
        exerciseName: squat.name,
        muscleGroups: squat.primaryMuscles,
        sets: [
            SetInput(reps: 10, weight: 40, tag: .warmup, isCompleted: true),
            SetInput(reps: 5, weight: 100, tag: .working, isCompleted: true),
            SetInput(reps: 5, weight: 100, tag: .working, isCompleted: true)
        ],
        activeSetIndex: 0
    )

    // MARK: - Workouts

    static func makeCurrentWorkout(
        startedAt: Date = Date(),
        entries: [WorkoutEntry]? = nil
    ) -> CurrentWorkout {
        CurrentWorkout(
            id: UUID(),
            startedAt: startedAt,
            entries: entries ?? [benchPressEntry, squatEntry],
            plannedWorkoutID: nil
        )
    }

    static func makeCompletedWorkout(
        date: Date = Date(),
        entries: [WorkoutEntry]? = nil,
        plannedWorkoutID: UUID? = nil
    ) -> CompletedWorkout {
        CompletedWorkout(
            id: UUID(),
            date: date,
            entries: entries ?? [benchPressEntry, squatEntry],
            plannedWorkoutID: plannedWorkoutID
        )
    }

    // MARK: - PR Data

    static let samplePR = ExercisePRsV2(
        bestPerReps: [
            5: 100.0,
            8: 85.0,
            10: 75.0
        ],
        bestE1RM: 116.0,
        lastWorking: LastSetV2(
            date: Date(),
            reps: 8,
            weightKg: 85.0
        ),
        allTimeBest: 100.0,
        firstRecorded: Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
    )
}
