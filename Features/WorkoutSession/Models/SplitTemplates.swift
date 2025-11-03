//
//  SplitTemplates.swift
//  WRKT
//
//  Predefined workout split templates

import Foundation

/// Predefined split template for user selection
struct SplitTemplate: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let shortName: String
    let description: String
    let days: [DayTemplate]
    let recommendedFrequency: Int // days per week
    let difficulty: Difficulty
    let focus: String
    let icon: String

    // Custom split metadata
    let isCustom: Bool
    let createdBy: String? // "user" or future trainer ID
    let createdAt: Date?
    let lastModified: Date?

    // Future: Import/export
    let shareableID: String? // UUID for sharing
    let version: Int // Schema version for compatibility

    enum Difficulty: String, Codable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
    }

    // Default initializer for predefined splits
    init(id: String, name: String, shortName: String, description: String,
         days: [DayTemplate], recommendedFrequency: Int, difficulty: Difficulty,
         focus: String, icon: String,
         isCustom: Bool = false, createdBy: String? = nil,
         createdAt: Date? = nil, lastModified: Date? = nil,
         shareableID: String? = nil, version: Int = 1) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.description = description
        self.days = days
        self.recommendedFrequency = recommendedFrequency
        self.difficulty = difficulty
        self.focus = focus
        self.icon = icon
        self.isCustom = isCustom
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.shareableID = shareableID
        self.version = version
    }
}

/// A single day in a split template
struct DayTemplate: Identifiable, Hashable, Codable {
    let id: String
    let name: String // "Push", "Pull", "Legs", "Upper", "Lower", etc.
    let exercises: [ExerciseTemplate]
    let isRestDay: Bool
}

/// Exercise template with default sets/reps/weight
struct ExerciseTemplate: Identifiable, Hashable, Codable {
    let id: String
    let exerciseID: String // ID to look up in ExerciseRepository
    let exerciseName: String
    let sets: Int
    let reps: Int
    let startingWeight: Double?
    let progressionStrategy: ProgressionStrategy
    let notes: String?

    init(exerciseID: String, exerciseName: String, sets: Int, reps: Int,
         startingWeight: Double? = nil,
         progressionStrategy: ProgressionStrategy = .linear(increment: 2.5),
         notes: String? = nil) {
        self.id = UUID().uuidString
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.startingWeight = startingWeight
        self.progressionStrategy = progressionStrategy
        self.notes = notes
    }
}

// MARK: - Split Templates Collection

enum SplitTemplates {

    /// Push/Pull/Legs - Classic 3 or 6 day split
    static let ppl = SplitTemplate(
        id: "ppl",
        name: "Push/Pull/Legs",
        shortName: "PPL",
        description: "Classic 3-day split focusing on pushing movements, pulling movements, and legs separately. Can be run 3x or 6x per week.",
        days: [pushDay, pullDay, legsDay],
        recommendedFrequency: 3,
        difficulty: .intermediate,
        focus: "Balanced hypertrophy",
        icon: "figure.strengthtraining.traditional"
    )

    /// Upper/Lower - 4 day split
    static let upperLower = SplitTemplate(
        id: "upper-lower",
        name: "Upper/Lower",
        shortName: "U/L",
        description: "Split upper and lower body workouts. Perfect for 4 days per week with balanced recovery.",
        days: [upperDay, lowerDay],
        recommendedFrequency: 4,
        difficulty: .beginner,
        focus: "Strength & size",
        icon: "figure.arms.open"
    )

    /// Full Body - 3 day split
    static let fullBody = SplitTemplate(
        id: "full-body",
        name: "Full Body",
        shortName: "FB",
        description: "Hit all major muscle groups each session. Ideal for beginners or time-constrained lifters.",
        days: [fullBodyDay],
        recommendedFrequency: 3,
        difficulty: .beginner,
        focus: "Overall strength",
        icon: "figure.walk"
    )

    /// Bro Split - 5 day body part split
    static let broSplit = SplitTemplate(
        id: "bro-split",
        name: "Bro Split",
        shortName: "Bro",
        description: "One muscle group per day. Classic bodybuilding approach for dedicated lifters.",
        days: [chestDay, backDay, shouldersDay, armsDay, legsBroDay],
        recommendedFrequency: 5,
        difficulty: .intermediate,
        focus: "Hypertrophy",
        icon: "figure.strengthtraining.traditional"
    )

    // MARK: - All Templates

    static let all: [SplitTemplate] = [ppl, upperLower, fullBody, broSplit]

    // MARK: - Day Templates

    private static let pushDay = DayTemplate(
        id: "push",
        name: "Push",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", sets: 4, reps: 6, startingWeight: 60),
            ExerciseTemplate(exerciseID: "barbell-incline-bench-press", exerciseName: "Barbell Incline Bench Press", sets: 4 , reps: 8, startingWeight: 30 ),
            ExerciseTemplate(exerciseID: "barbell-overhead-press", exerciseName: "Barbell Overhead Press", sets: 4 , reps: 6, startingWeight: 30 ),
            ExerciseTemplate(exerciseID: "bodyweight-dips", exerciseName: "Bodyweights Dips", sets: 3 , reps: 10, startingWeight: 0 ),
            ExerciseTemplate(exerciseID: "double-dumbbell-lateral-raise", exerciseName: "Double Dumbbell Lateral Raise", sets: 4, reps: 15, startingWeight: 10),
            ExerciseTemplate(exerciseID: "cable-rope-tricep-pushdown", exerciseName: "Cable Rope Tricep Pushdown", sets: 3, reps: 12, startingWeight: 10),
            ExerciseTemplate(exerciseID: "cable-rope-overhead-tricep-extension", exerciseName: "Cable Rope Overhead Tricep Extension", sets: 3, reps: 15, startingWeight: 10)
          
        ],
        isRestDay: false
    )

    private static let pullDay = DayTemplate(
        id: "pull",
        name: "Pull",
        exercises: [
            ExerciseTemplate(exerciseID: "bar-eccentric-pull-up", exerciseName: "Pull-ups", sets: 4, reps: 8, startingWeight: 0, progressionStrategy: .autoregulated),
            ExerciseTemplate(exerciseID: "dumbbell-chest-supported-row", exerciseName: "Dumbbell Chest Supported Row", sets: 4, reps: 10, startingWeight: 50),
            ExerciseTemplate(exerciseID: "double-dumbbell-bent-over-reverse-fly", exerciseName: "Bent Over Reverse Fly", sets: 3, reps: 12, startingWeight: 12),
            ExerciseTemplate(exerciseID: "cable-face-pull", exerciseName: "Cable Face Pull", sets: 3, reps: 15, startingWeight: 20),
            ExerciseTemplate(exerciseID: "single-arm-barbell-bicep-curl", exerciseName: "Barbell Bicep Curl", sets: 3, reps: 8, startingWeight: 25)
        ],
        isRestDay: false
    )

    private static let legsDay = DayTemplate(
        id: "legs",
        name: "Legs",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-back-squat", exerciseName: "Squat", sets: 4, reps: 6, startingWeight: 20, progressionStrategy: .linear(increment: 5)),
            ExerciseTemplate(exerciseID: "barbell-romanian-deadlift", exerciseName: "Romanian Deadlift", sets: 3, reps: 10, startingWeight: 60),
            ExerciseTemplate(exerciseID: "machine-seated-leg-curl", exerciseName: "Machine Seated Leg Curl", sets: 3, reps: 12, startingWeight: 100),
            ExerciseTemplate(exerciseID: "machine-45-degree-leg-press", exerciseName: "Machine Leg Press", sets: 3, reps: 12, startingWeight: 100),
            ExerciseTemplate(exerciseID: "barbell-overhead-bulgarian-split-squat", exerciseName: "Bulgarian Split Squat", sets: 3, reps: 10, startingWeight: 35),
            ExerciseTemplate(exerciseID: "double-dumbbell-suitcase-calf-raise", exerciseName: "Dumbbell Calf Raise", sets: 4, reps: 15, startingWeight: 40)
        ],
        isRestDay: false
    )

    private static let upperDay = DayTemplate(
        id: "upper",
        name: "Upper Body",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-bench-press", exerciseName: "Barbell Bench Press", sets: 4, reps: 6, startingWeight: 60),
            ExerciseTemplate(exerciseID: "dumbbell-chest-supported-row", exerciseName: "Dumbbell Chest Supported Row", sets: 4, reps: 6, startingWeight: 50),
            ExerciseTemplate(exerciseID: "barbell-overhead-press", exerciseName: "Barbell Overhead Press", sets: 3, reps: 8, startingWeight: 40),
            ExerciseTemplate(exerciseID: "bar-eccentric-pull-up", exerciseName: "Pull-ups", sets: 4, reps: 8, startingWeight: 0, progressionStrategy: .autoregulated),
            ExerciseTemplate(exerciseID: "alternating-double-dumbbell-bicep-curl", exerciseName: "Alternating Dumbbell Curl", sets: 2, reps: 12, startingWeight: 12),
            ExerciseTemplate(exerciseID: "dumbbell-seated-overhead-tricep-extension", exerciseName: "Tricep Extension", sets: 2, reps: 12, startingWeight: 15)
        ],
        isRestDay: false
    )

    private static let lowerDay = DayTemplate(
        id: "lower",
        name: "Lower Body",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-back-squat", exerciseName: "Barbell Squat", sets: 4, reps: 6, startingWeight: 80, progressionStrategy: .linear(increment: 5)),
            ExerciseTemplate(exerciseID: "barbell-romanian-deadlift", exerciseName: "Romanian Deadlift", sets: 3, reps: 8, startingWeight: 60),
            ExerciseTemplate(exerciseID: "machine-45-degree-leg-press", exerciseName: " Machine Leg Press", sets: 3, reps: 10, startingWeight: 100),
            ExerciseTemplate(exerciseID: "machine-seated-leg-curl", exerciseName: "Machine Leg Curl", sets: 3, reps: 12, startingWeight: 35),
            ExerciseTemplate(exerciseID: "double-dumbbell-suitcase-calf-raise", exerciseName: "Dumbbell Calf Raise", sets: 3, reps: 15, startingWeight: 40)
        ],
        isRestDay: false
    )

    private static let fullBodyDay = DayTemplate(
        id: "full-body",
        name: "Full Body",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-back-squat", exerciseName: "Barbell Back Squat", sets: 3, reps: 8, startingWeight: 70, progressionStrategy: .linear(increment: 5)),
            ExerciseTemplate(exerciseID: "barbell-bench-press", exerciseName: "Bench Press", sets: 3, reps: 8, startingWeight: 50),
            ExerciseTemplate(exerciseID: "dumbbell-chest-supported-row", exerciseName: "Dumbbell Chest Supported Row", sets: 3, reps: 8, startingWeight: 45),
            ExerciseTemplate(exerciseID: "barbell-overhead-press", exerciseName: "Barbell Overhead Press", sets: 3, reps: 8, startingWeight: 35),
            ExerciseTemplate(exerciseID: "barbell-romanian-deadlift", exerciseName: "Barbell Romanian Deadlift", sets: 2, reps: 10, startingWeight: 50),
            ExerciseTemplate(exerciseID: "bar-eccentric-pull-up", exerciseName: "Pull-ups", sets: 2, reps: 8, startingWeight: 0, progressionStrategy: .autoregulated)
        ],
        isRestDay: false
    )

    // Bro split days
    private static let chestDay = DayTemplate(
        id: "chest",
        name: "Chest",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-bench-press", exerciseName: "Bench Press", sets: 4, reps: 8, startingWeight: 60),
            ExerciseTemplate(exerciseID: "double-dumbbell-incline-bench-press", exerciseName: "Incline Dumbbell Press", sets: 3, reps: 10, startingWeight: 20),
            ExerciseTemplate(exerciseID: "double-cable-chest-fly", exerciseName: "Cable Fly", sets: 3, reps: 12, startingWeight: 15),
            ExerciseTemplate(exerciseID: "bodyweight-dips", exerciseName: "Dips", sets: 3, reps: 10, startingWeight: 0, progressionStrategy: .autoregulated)
        ],
        isRestDay: false
    )

    private static let backDay = DayTemplate(
        id: "back",
        name: "Back",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-romanian-deadlift", exerciseName: "Deadlift", sets: 3, reps: 5, startingWeight: 100, progressionStrategy: .linear(increment: 5)),
            ExerciseTemplate(exerciseID: "bar-eccentric-pull-up", exerciseName: "Pull-ups", sets: 3, reps: 8, startingWeight: 0, progressionStrategy: .autoregulated),
            ExerciseTemplate(exerciseID: "dumbbell-chest-supported-row", exerciseName: "Dumbbell Chest Supported Row", sets: 4, reps: 8, startingWeight: 50),
            ExerciseTemplate(exerciseID: "cable-wide-grip-lat-pulldown", exerciseName: "Lat Pulldown", sets: 3, reps: 10, startingWeight: 45)
        ],
        isRestDay: false
    )

    private static let shouldersDay = DayTemplate(
        id: "shoulders",
        name: "Shoulders",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-overhead-press", exerciseName: "Barbell Overhead Press", sets: 4, reps: 8, startingWeight: 40),
            ExerciseTemplate(exerciseID: "double-dumbbell-lateral-raise", exerciseName: "Lateral Raise", sets: 4, reps: 12, startingWeight: 10),
            ExerciseTemplate(exerciseID: "alternating-double-dumbbell-front-raise", exerciseName: "Front Raise", sets: 3, reps: 12, startingWeight: 10),
            ExerciseTemplate(exerciseID: "cable-face-pull", exerciseName: "Face Pull", sets: 3, reps: 15, startingWeight: 20)
        ],
        isRestDay: false
    )

    private static let armsDay = DayTemplate(
        id: "arms",
        name: "Arms",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-bicep-curl", exerciseName: "Barbell Curl", sets: 3, reps: 10, startingWeight: 25),
            ExerciseTemplate(exerciseID: "cable-rope-tricep-pushdown", exerciseName: "Tricep Pushdown", sets: 3, reps: 12, startingWeight: 25),
            ExerciseTemplate(exerciseID: "double-dumbbell-hammer-curl", exerciseName: "Hammer Curl", sets: 3, reps: 10, startingWeight: 15),
            ExerciseTemplate(exerciseID: "ez-bar-overhead-tricep-extension", exerciseName: "EZ Bar Overhead Tricep Extension", sets: 3, reps: 12, startingWeight: 20)
        ],
        isRestDay: false
    )

    private static let legsBroDay = DayTemplate(
        id: "legs-bro",
        name: "Legs",
        exercises: [
            ExerciseTemplate(exerciseID: "barbell-back-squat", exerciseName: "Barbell Squat", sets: 4, reps: 8, startingWeight: 80, progressionStrategy: .linear(increment: 5)),
            ExerciseTemplate(exerciseID: "machine-45-degree-leg-press", exerciseName: "Leg Press", sets: 4, reps: 12, startingWeight: 100),
            ExerciseTemplate(exerciseID: "leg-extension", exerciseName: "Leg Extension", sets: 3, reps: 12, startingWeight: 40),
            ExerciseTemplate(exerciseID: "machine-seated-leg-curl", exerciseName: "Leg Curl", sets: 3, reps: 12, startingWeight: 35),
            ExerciseTemplate(exerciseID: "double-dumbbell-suitcase-calf-raise", exerciseName: "Calf Raise", sets: 4, reps: 15, startingWeight: 40)
        ],
        isRestDay: false
    )
}
