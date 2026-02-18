import Foundation

struct PresetChallenge {
    let title: String
    let description: String
    let challengeType: ChallengeType
    let goalMetric: String
    let goalValue: Decimal
    let difficulty: ChallengeDifficulty
    let duration: Int // days
    let icon: String
}

extension PresetChallenge {
    static let all: [PresetChallenge] = [
        // MARK: - Workout Count Challenges

        PresetChallenge(
            title: "30-Day Warrior",
            description: "Complete 30 workouts in 30 days. Miss a day? That's okay - just keep going!",
            challengeType: .workoutCount,
            goalMetric: "workouts",
            goalValue: 30,
            difficulty: .intermediate,
            duration: 30,
            icon: "figure.run"
        ),

        PresetChallenge(
            title: "Weekend Warrior",
            description: "Don't skip the weekend! Complete 8 weekend workouts this month.",
            challengeType: .workoutCount,
            goalMetric: "workouts",
            goalValue: 8,
            difficulty: .beginner,
            duration: 30,
            icon: "sun.max.fill"
        ),

        PresetChallenge(
            title: "21-Day Habit Builder",
            description: "They say it takes 21 days to form a habit. Complete 21 workouts in 3 weeks!",
            challengeType: .workoutCount,
            goalMetric: "workouts",
            goalValue: 21,
            difficulty: .intermediate,
            duration: 21,
            icon: "calendar.badge.checkmark"
        ),

        // MARK: - Volume Challenges

        PresetChallenge(
            title: "100K Club",
            description: "Lift 100,000 kg total volume this month. Every rep counts!",
            challengeType: .totalVolume,
            goalMetric: "kg",
            goalValue: 100000,
            difficulty: .advanced,
            duration: 30,
            icon: "scalemass.fill"
        ),

        PresetChallenge(
            title: "Volume Rookie",
            description: "Build the habit. Lift 25,000 kg this month.",
            challengeType: .totalVolume,
            goalMetric: "kg",
            goalValue: 25000,
            difficulty: .beginner,
            duration: 30,
            icon: "scalemass"
        ),

        PresetChallenge(
            title: "50K in 2 Weeks",
            description: "Quick volume blitz! Lift 50,000 kg in just 14 days.",
            challengeType: .totalVolume,
            goalMetric: "kg",
            goalValue: 50000,
            difficulty: .intermediate,
            duration: 14,
            icon: "flame.fill"
        ),

        // MARK: - Exercise-Specific Challenges

        PresetChallenge(
            title: "Pull-Up Master",
            description: "Complete 100 total pull-ups this week. Break it down however you want!",
            challengeType: .specificExercise,
            goalMetric: "pull-ups",
            goalValue: 100,
            difficulty: .intermediate,
            duration: 7,
            icon: "figure.climbing"
        ),

        PresetChallenge(
            title: "Push-Up Hero",
            description: "500 push-ups in 7 days. You got this!",
            challengeType: .specificExercise,
            goalMetric: "push-ups",
            goalValue: 500,
            difficulty: .intermediate,
            duration: 7,
            icon: "figure.strengthtraining.traditional"
        ),

        PresetChallenge(
            title: "Squat Squad",
            description: "1000 total squats this month. Leg day every day!",
            challengeType: .specificExercise,
            goalMetric: "squats",
            goalValue: 1000,
            difficulty: .advanced,
            duration: 30,
            icon: "figure.roll"
        ),

        PresetChallenge(
            title: "Bench Press Beast",
            description: "Hit bench press 50 times this month. Build that chest!",
            challengeType: .specificExercise,
            goalMetric: "bench press",
            goalValue: 50,
            difficulty: .intermediate,
            duration: 30,
            icon: "dumbbell.fill"
        ),

        // MARK: - Streak Challenges

        PresetChallenge(
            title: "7-Day Streak",
            description: "Build the habit. Work out 7 days in a row.",
            challengeType: .streak,
            goalMetric: "days",
            goalValue: 7,
            difficulty: .beginner,
            duration: 7,
            icon: "flame.fill"
        ),

        PresetChallenge(
            title: "Iron Will",
            description: "The ultimate test. 21 days straight. No excuses.",
            challengeType: .streak,
            goalMetric: "days",
            goalValue: 21,
            difficulty: .advanced,
            duration: 21,
            icon: "flame.fill"
        ),
    ]

    // Get featured challenges (rotate weekly)
    static var featured: [PresetChallenge] {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: Date())

        // Rotate featured challenges based on week
        let startIndex = weekOfYear % all.count
        let count = min(3, all.count - startIndex)

        return Array(all[startIndex..<(startIndex + count)])
    }

    // Get challenges by difficulty
    static func challenges(forDifficulty difficulty: ChallengeDifficulty) -> [PresetChallenge] {
        all.filter { $0.difficulty == difficulty }
    }

    // Get challenges by type
    static func challenges(forType type: ChallengeType) -> [PresetChallenge] {
        all.filter { $0.challengeType == type }
    }
}
