//
//  MetricExamples.swift
//  WRKT
//
//  Examples of how to create battles and challenges with different metrics
//

import Foundation

// MARK: - Battle Examples

struct BattleExamples {

    // MARK: - Volume Battles

    /// Total volume battle: Most total weight lifted
    static func totalVolumeBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .totalVolume,
            filter: nil,
            goalValue: nil
        )
    }

    /// Leg volume battle: Most volume for leg exercises
    static func legVolumeBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .volumeForMuscleGroup,
            filter: MetricFilter(muscleGroups: ["Quadriceps", "Hamstrings", "Glutes"]),
            goalValue: nil
        )
    }

    /// Bench press volume battle
    static func benchPressVolumeBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .volumeForExercise,
            filter: MetricFilter(exerciseName: "Bench Press"),
            goalValue: nil
        )
    }

    // MARK: - Rep Battles

    /// Pull-ups battle: Most pull-ups completed
    static func pullUpsBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .repsForExercise,
            filter: MetricFilter(exerciseName: "Pull"),  // Matches "Pull-Up", "Pull-ups", etc.
            goalValue: nil
        )
    }

    /// Total reps battle
    static func totalRepsBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .repCount,
            filter: nil,
            goalValue: nil
        )
    }

    // MARK: - Cardio Battles

    /// Distance battle: Most km run
    static func distanceBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .distance,
            filter: nil,
            goalValue: nil
        )
    }

    /// Calories battle: Most calories burned
    static func caloriesBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .calories,
            filter: nil,
            goalValue: nil
        )
    }

    /// Zone 3+ cardio battle: Most time in Zone 3-5 heart rate
    static func zone3PlusCardioTime() -> MetricConfiguration {
        MetricConfiguration(
            type: .timeInHRZone,
            filter: MetricFilter(hrZone: .zone3),
            goalValue: nil
        )
    }

    // MARK: - Intensity Battles

    /// Max weight battle for specific exercise
    static func maxWeightBenchPress() -> MetricConfiguration {
        MetricConfiguration(
            type: .maxWeight,
            filter: MetricFilter(exerciseName: "Bench Press"),
            goalValue: nil
        )
    }

    /// One rep max battle
    static func oneRepMaxSquat() -> MetricConfiguration {
        MetricConfiguration(
            type: .oneRepMax,
            filter: MetricFilter(exerciseName: "Squat"),
            goalValue: nil
        )
    }

    // MARK: - Variety Battles

    /// Exercise variety battle: Most unique exercises
    static func exerciseVarietyBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .uniqueExercises,
            filter: nil,
            goalValue: nil
        )
    }

    // MARK: - Time Battles

    /// Workout duration battle
    static func workoutDurationBattle() -> MetricConfiguration {
        MetricConfiguration(
            type: .workoutDuration,
            filter: nil,
            goalValue: nil
        )
    }
}

// MARK: - Challenge Examples

struct ChallengeExamples {

    // MARK: - Volume Challenges

    /// "100K Club" - Lift 100,000 lbs in a month
    static func hundredKClub() -> MetricConfiguration {
        MetricConfiguration(
            type: .totalVolume,
            filter: nil,
            goalValue: 100_000
        )
    }

    /// "Leg Day Legend" - 50,000 lbs leg volume in 30 days
    static func legDayLegend() -> MetricConfiguration {
        MetricConfiguration(
            type: .volumeForMuscleGroup,
            filter: MetricFilter(muscleGroups: ["Quadriceps", "Hamstrings", "Glutes"]),
            goalValue: 50_000
        )
    }

    // MARK: - Rep Challenges

    /// "Pull-Up Master" - 1,000 pull-ups this month
    static func pullUpMaster() -> MetricConfiguration {
        MetricConfiguration(
            type: .repsForExercise,
            filter: MetricFilter(exerciseNames: ["Pull-Up", "Chin-Up"]),  // OR logic
            goalValue: 1_000
        )
    }

    /// "Push-Up Challenge" - 10,000 push-ups in 30 days
    static func pushUpChallenge() -> MetricConfiguration {
        MetricConfiguration(
            type: .repsForExercise,
            filter: MetricFilter(exerciseName: "Push-Up"),
            goalValue: 10_000
        )
    }

    // MARK: - Workout Count Challenges

    /// "30-Day Warrior" - 30 workouts in 30 days
    static func thirtyDayWarrior() -> MetricConfiguration {
        MetricConfiguration(
            type: .workoutCount,
            filter: nil,
            goalValue: 30
        )
    }

    /// "5x5 Challenge" - 5 workouts per week for 5 weeks (25 total)
    static func fiveByFiveChallenge() -> MetricConfiguration {
        MetricConfiguration(
            type: .workoutCount,
            filter: nil,
            goalValue: 25
        )
    }

    // MARK: - Cardio Challenges

    /// "Run 100K" - Run 100 kilometers in a month
    static func run100K() -> MetricConfiguration {
        MetricConfiguration(
            type: .distance,
            filter: nil,
            goalValue: 100
        )
    }

    /// "Burn 10,000" - Burn 10,000 calories in 2 weeks
    static func burnTenThousand() -> MetricConfiguration {
        MetricConfiguration(
            type: .calories,
            filter: nil,
            goalValue: 10_000
        )
    }

    /// "Zone 3 Master" - 300 minutes in Zone 3+ heart rate
    static func zone3Master() -> MetricConfiguration {
        MetricConfiguration(
            type: .timeInHRZone,
            filter: MetricFilter(hrZone: .zone3),
            goalValue: 300  // 300 minutes = 5 hours
        )
    }

    // MARK: - Strength Challenges

    /// "Bench 225" - Work up to benching 225 lbs for 1 rep
    static func bench225() -> MetricConfiguration {
        MetricConfiguration(
            type: .oneRepMax,
            filter: MetricFilter(exerciseName: "Bench Press"),
            goalValue: 225
        )
    }

    /// "Heavy Hitter" - Average 200 lbs across all sets in a week
    static func heavyHitter() -> MetricConfiguration {
        MetricConfiguration(
            type: .avgWeight,
            filter: MetricFilter(minWeight: 100),  // Only count sets with 100+ lbs
            goalValue: 200
        )
    }

    // MARK: - Variety Challenges

    /// "Exercise Explorer" - Try 50 different exercises in a month
    static func exerciseExplorer() -> MetricConfiguration {
        MetricConfiguration(
            type: .uniqueExercises,
            filter: nil,
            goalValue: 50
        )
    }

    // MARK: - Time Challenges

    /// "Time Under Tension" - 600 minutes TUT in a month
    static func timeUnderTension() -> MetricConfiguration {
        MetricConfiguration(
            type: .timeUnderTension,
            filter: nil,
            goalValue: 600
        )
    }

    /// "Long Haul" - 30 hours of total workout time in a month
    static func longHaul() -> MetricConfiguration {
        MetricConfiguration(
            type: .workoutDuration,
            filter: nil,
            goalValue: 1_800  // 30 hours = 1800 minutes
        )
    }

    // MARK: - Compound Challenges (Multiple Exercises)

    /// "Push King" - 5,000 total reps across push exercises
    static func pushKing() -> MetricConfiguration {
        MetricConfiguration(
            type: .repCount,
            filter: MetricFilter(exerciseNames: ["Bench Press", "Push-Up", "Overhead Press", "Dip"]),
            goalValue: 5_000
        )
    }

    /// "Pull Queen" - 5,000 total reps across pull exercises
    static func pullQueen() -> MetricConfiguration {
        MetricConfiguration(
            type: .repCount,
            filter: MetricFilter(exerciseNames: ["Pull-Up", "Row", "Lat Pulldown", "Chin-Up"]),
            goalValue: 5_000
        )
    }
}

// MARK: - Usage Guide

/*
 How to create a battle with a custom metric:

 ```swift
 let metricConfig = BattleExamples.pullUpsBattle()
 let metricJSON = try JSONEncoder().encode(metricConfig)
 let metricString = String(data: metricJSON, encoding: .utf8)!

 try await battleRepository.createBattle(
     opponentId: friendId,
     battleType: .exercise,  // Keep this for backwards compatibility
     durationDays: 7,
     targetMetric: metricString  // Store JSON config here
 )
 ```

 How to create a challenge with a custom metric:

 ```swift
 let metricConfig = ChallengeExamples.pullUpMaster()
 let metricJSON = try JSONEncoder().encode(metricConfig)
 let metricString = String(data: metricJSON, encoding: .utf8)!

 try await challengeRepository.createChallenge(
     title: "Pull-Up Master",
     description: "Complete 1,000 pull-ups this month!",
     challengeType: .specificExercise,  // Keep for backwards compatibility
     goalMetric: metricString,  // Store JSON config here
     goalValue: metricConfig.goalValue ?? 0,
     durationDays: 30,
     isPublic: true,
     difficulty: .intermediate
 )
 ```

 The system will automatically:
 1. Parse the JSON metric configuration
 2. Calculate progress based on the metric type and filter
 3. Update scores/progress after each workout
 4. Handle all edge cases (no HealthKit data, missing exercises, etc.)
 */
