import Foundation

struct PresetChallenge {
    let title: String
    let description: String
    let challengeType: ChallengeType
    let goalMetric: String
    let goalValue: Decimal
    let difficulty: ChallengeDifficulty
    let duration: Int
    let icon: String
}

extension PresetChallenge {
    static let all: [PresetChallenge] = [
        PresetChallenge(
            title: "30-Day Warrior",
            description: "Complete 20 workouts in 30 days. That is 5 per week — consistent without being excessive.",
            challengeType: .workoutCount,
            goalMetric: "workouts",
            goalValue: 20,
            difficulty: .intermediate,
            duration: 30,
            icon: "figure.run"
        ),
        PresetChallenge(
            title: "Weekend Warrior",
            description: "Work out 6 weekends this month. Two sessions per weekend — build the habit without weekday pressure.",
            challengeType: .workoutCount,
            goalMetric: "workouts",
            goalValue: 6,
            difficulty: .beginner,
            duration: 30,
            icon: "sun.max.fill"
        ),
        PresetChallenge(
            title: "21-Day Habit Builder",
            description: "Complete 12 workouts in 21 days. Four per week — enough to build a real habit.",
            challengeType: .workoutCount,
            goalMetric: "workouts",
            goalValue: 12,
            difficulty: .intermediate,
            duration: 21,
            icon: "calendar.badge.checkmark"
        ),
        PresetChallenge(
            title: "50K Club",
            description: "Lift 50,000 kg total volume this month. Around 12,500 kg per week across all strength workouts.",
            challengeType: .totalVolume,
            goalMetric: "kg",
            goalValue: 50000,
            difficulty: .advanced,
            duration: 30,
            icon: "scalemass.fill"
        ),
        PresetChallenge(
            title: "Volume Starter",
            description: "Lift 15,000 kg total this month. Around 500 kg per workout — achievable in just a few sets.",
            challengeType: .totalVolume,
            goalMetric: "kg",
            goalValue: 15000,
            difficulty: .beginner,
            duration: 30,
            icon: "scalemass"
        ),
        PresetChallenge(
            title: "Volume Builder",
            description: "Lift 30,000 kg total this month. A solid monthly volume target for consistent strength training.",
            challengeType: .totalVolume,
            goalMetric: "kg",
            goalValue: 30000,
            difficulty: .intermediate,
            duration: 30,
            icon: "flame.fill"
        ),
        PresetChallenge(
            title: "Pull-Up Progression",
            description: "Log 50 pull-up reps in 7 days. Around 7 per day — hit it in 2-3 sessions.",
            challengeType: .specificExercise,
            goalMetric: "pull-ups",
            goalValue: 50,
            difficulty: .intermediate,
            duration: 7,
            icon: "figure.climbing"
        ),
        PresetChallenge(
            title: "Push-Up Builder",
            description: "Log 100 push-up reps in 7 days. Around 14 per day — 3 sets of 5 twice a day.",
            challengeType: .specificExercise,
            goalMetric: "push-ups",
            goalValue: 100,
            difficulty: .beginner,
            duration: 7,
            icon: "figure.strengthtraining.traditional"
        ),
        PresetChallenge(
            title: "Squat Month",
            description: "Log 300 squat reps this month. Around 10 per day — 3 sets of 10 three times a week.",
            challengeType: .specificExercise,
            goalMetric: "squats",
            goalValue: 300,
            difficulty: .intermediate,
            duration: 30,
            icon: "figure.roll"
        ),
        PresetChallenge(
            title: "Bench Month",
            description: "Log 80 bench press reps this month. Around 3 sets of 8, twice a week.",
            challengeType: .specificExercise,
            goalMetric: "bench-press",
            goalValue: 80,
            difficulty: .intermediate,
            duration: 30,
            icon: "dumbbell.fill"
        ),
        PresetChallenge(
            title: "7-Day Streak",
            description: "Work out 7 days in a row. Build the habit.",
            challengeType: .streak,
            goalMetric: "days",
            goalValue: 7,
            difficulty: .beginner,
            duration: 7,
            icon: "flame.fill"
        ),
        PresetChallenge(
            title: "14-Day Streak",
            description: "Work out 14 days in a row. Two full weeks — no rest days.",
            challengeType: .streak,
            goalMetric: "days",
            goalValue: 14,
            difficulty: .advanced,
            duration: 14,
            icon: "flame.fill"
        ),
    ]

    static var featured: [PresetChallenge] {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: Date())
        let startIndex = weekOfYear % all.count
        let count = min(3, all.count - startIndex)
        return Array(all[startIndex..<(startIndex + count)])
    }

    static func challenges(forDifficulty difficulty: ChallengeDifficulty) -> [PresetChallenge] {
        all.filter { $0.difficulty == difficulty }
    }

    static func challenges(forType type: ChallengeType) -> [PresetChallenge] {
        all.filter { $0.challengeType == type }
    }
}
