//
//  RestDayPlacementStrategy.swift
//  WRKT
//
//  Strategy pattern for rest day placement in workout plans

import Foundation

// MARK: - Protocol

protocol RestDayPlacementStrategy {
    func generateWeek(
        workoutBlocks: [PlanBlock],
        trainingDaysPerWeek: Int
    ) -> [PlanBlock]
}

// MARK: - After Each Workout Strategy

struct AfterEachWorkoutStrategy: RestDayPlacementStrategy {
    func generateWeek(workoutBlocks: [PlanBlock], trainingDaysPerWeek: Int) -> [PlanBlock] {
        var blocks: [PlanBlock] = []
        var workoutIndex = 0
        var workoutsAdded = 0
        let totalRestDays = 7 - trainingDaysPerWeek

        while blocks.count < 7 {
            if workoutsAdded < trainingDaysPerWeek {
                // Add workout
                blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
                workoutIndex += 1
                workoutsAdded += 1

                // Add rest after workout if we have rest days remaining and space in the week
                let restDaysAdded = blocks.count - workoutsAdded
                if restDaysAdded < totalRestDays && blocks.count < 7 {
                    blocks.append(createRestBlock())
                }
            } else {
                // Fill remaining days with rest
                blocks.append(createRestBlock())
            }
        }

        return blocks
    }
}

// MARK: - After Every Second Workout Strategy

struct AfterEverySecondWorkoutStrategy: RestDayPlacementStrategy {
    func generateWeek(workoutBlocks: [PlanBlock], trainingDaysPerWeek: Int) -> [PlanBlock] {
        var blocks: [PlanBlock] = []
        var workoutIndex = 0
        var workoutsAdded = 0
        var workoutsSinceRest = 0

        while blocks.count < 7 && workoutsAdded < trainingDaysPerWeek {
            // Add workout
            blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
            workoutIndex += 1
            workoutsAdded += 1
            workoutsSinceRest += 1

            // Add rest after every 2 workouts
            if workoutsSinceRest >= 2 && blocks.count < 7 {
                blocks.append(createRestBlock())
                workoutsSinceRest = 0
            }
        }

        // Fill remaining days with rest
        while blocks.count < 7 {
            blocks.append(createRestBlock())
        }

        return blocks
    }
}

// MARK: - Weekends Strategy

struct WeekendsStrategy: RestDayPlacementStrategy {
    func generateWeek(workoutBlocks: [PlanBlock], trainingDaysPerWeek: Int) -> [PlanBlock] {
        // Spread training evenly across weekdays (0=Mon ... 4=Fri); rest on weekends (5=Sat, 6=Sun)
        let trainingIndices: Set<Int>
        switch trainingDaysPerWeek {
        case 2: trainingIndices = [0, 3]           // Mon, Thu
        case 3: trainingIndices = [0, 2, 4]        // Mon, Wed, Fri
        case 4: trainingIndices = [0, 1, 3, 4]     // Mon, Tue, Thu, Fri
        case 5: trainingIndices = [0, 1, 2, 3, 4]  // Mon-Fri
        default: trainingIndices = Set(0..<min(trainingDaysPerWeek, 6))
        }

        var blocks: [PlanBlock] = []
        var workoutIndex = 0

        for dayIndex in 0..<7 {
            if trainingIndices.contains(dayIndex) {
                blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
                workoutIndex += 1
            } else {
                blocks.append(createRestBlock())
            }
        }

        return blocks
    }
}

// MARK: - Custom Strategy

struct CustomRestDayStrategy: RestDayPlacementStrategy {
    let restDayIndices: [Int]

    func generateWeek(workoutBlocks: [PlanBlock], trainingDaysPerWeek: Int) -> [PlanBlock] {
        var blocks: [PlanBlock] = []
        var workoutIndex = 0

        for dayIndex in 0..<7 {
            if restDayIndices.contains(dayIndex) {
                blocks.append(createRestBlock())
            } else if workoutIndex < trainingDaysPerWeek {
                blocks.append(workoutBlocks[workoutIndex % workoutBlocks.count])
                workoutIndex += 1
            } else {
                // More rest days than planned
                blocks.append(createRestBlock())
            }
        }

        return blocks
    }
}

// MARK: - Helper

private func createRestBlock() -> PlanBlock {
    PlanBlock(dayName: "Rest", exercises: [], isRestDay: true)
}

// MARK: - Strategy Factory

struct RestDayStrategyFactory {
    static func strategy(for placement: PlanConfig.RestDayPlacement) -> RestDayPlacementStrategy {
        switch placement {
        case .afterEachWorkout:
            return AfterEachWorkoutStrategy()

        case .afterEverySecondWorkout:
            return AfterEverySecondWorkoutStrategy()

        case .weekends:
            return WeekendsStrategy()

        case .custom(let indices):
            return CustomRestDayStrategy(restDayIndices: indices)
        }
    }
}
