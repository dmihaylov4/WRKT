import Foundation

// MARK: - Challenge Types

enum ChallengeType: String, Codable, Sendable, Hashable {
    case workoutCount = "workout_count"
    case totalVolume = "total_volume"
    case specificExercise = "specific_exercise"
    case streak = "streak"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .workoutCount: return "Workout Count"
        case .totalVolume: return "Total Volume"
        case .specificExercise: return "Exercise Challenge"
        case .streak: return "Streak Challenge"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .workoutCount: return "figure.run"
        case .totalVolume: return "scalemass.fill"
        case .specificExercise: return "dumbbell.fill"
        case .streak: return "flame.fill"
        case .custom: return "star.fill"
        }
    }
}

enum ChallengeDifficulty: String, Codable, Sendable, Hashable {
    case beginner
    case intermediate
    case advanced

    var displayName: String { rawValue.capitalized }

    var color: String {
        switch self {
        case .beginner: return "green"
        case .intermediate: return "orange"
        case .advanced: return "red"
        }
    }
}

// MARK: - Challenge Model

struct Challenge: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var title: String
    var description: String?
    let challengeType: ChallengeType
    let goalMetric: String
    let goalValue: Decimal
    let startDate: Date
    let endDate: Date
    let creatorId: UUID
    var isPublic: Bool
    var isPreset: Bool
    var difficulty: ChallengeDifficulty?
    var participantLimit: Int?
    var participantCount: Int
    var completionCount: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case challengeType = "challenge_type"
        case goalMetric = "goal_metric"
        case goalValue = "goal_value"
        case startDate = "start_date"
        case endDate = "end_date"
        case creatorId = "creator_id"
        case isPublic = "is_public"
        case isPreset = "is_preset"
        case difficulty
        case participantLimit = "participant_limit"
        case participantCount = "participant_count"
        case completionCount = "completion_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    var isUpcoming: Bool {
        Date() < startDate
    }

    var isCompleted: Bool {
        Date() > endDate
    }

    var daysRemaining: Int {
        let calendar = Calendar.current
        let now = Date()
        if now > endDate { return 0 }
        return calendar.dateComponents([.day], from: now, to: endDate).day ?? 0
    }

    var hoursRemaining: Int {
        let now = Date()
        if now > endDate { return 0 }
        return Int(endDate.timeIntervalSince(now) / 3600)
    }

    var duration: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    var progressText: String {
        let value = Int(truncating: goalValue as NSDecimalNumber)
        switch challengeType {
        case .workoutCount:
            return "\(value) workouts"
        case .totalVolume:
            return "\(formatNumber(goalValue)) kg total"
        case .specificExercise:
            return "\(value) \(goalMetric)"
        case .streak:
            return "\(value) day streak"
        case .custom:
            return "\(value) \(goalMetric)"
        }
    }

    private func formatNumber(_ decimal: Decimal) -> String {
        let double = NSDecimalNumber(decimal: decimal).doubleValue
        if double >= 1000 {
            return String(format: "%.1fk", double / 1000)
        }
        return String(format: "%.0f", double)
    }
}

// MARK: - Challenge Participant

struct ChallengeParticipant: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let challengeId: UUID
    let userId: UUID
    var currentProgress: Decimal
    var progressPercentage: Int
    var completed: Bool
    var completionDate: Date?
    var lastActivityDate: Date?
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case challengeId = "challenge_id"
        case userId = "user_id"
        case currentProgress = "current_progress"
        case progressPercentage = "progress_percentage"
        case completed
        case completionDate = "completion_date"
        case lastActivityDate = "last_activity_date"
        case joinedAt = "joined_at"
    }
}

// MARK: - Challenge with Participant Info

struct ChallengeWithProgress: Identifiable, Sendable, Hashable {
    let id: UUID
    let challenge: Challenge
    let participation: ChallengeParticipant?
    let topParticipants: [ChallengeParticipantProfile]

    var isParticipating: Bool {
        participation != nil
    }

    var userProgress: Decimal {
        participation?.currentProgress ?? 0
    }

    var userProgressPercentage: Int {
        participation?.progressPercentage ?? 0
    }

    var isCompleted: Bool {
        participation?.completed ?? false
    }

    var userRank: Int? {
        guard let participation = participation else { return nil }
        return topParticipants.firstIndex(where: { $0.participant.id == participation.id }).map { $0 + 1 }
    }

    static func == (lhs: ChallengeWithProgress, rhs: ChallengeWithProgress) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Challenge Participant with Profile

struct ChallengeParticipantProfile: Identifiable, Sendable, Hashable {
    let id: UUID
    let participant: ChallengeParticipant
    let profile: UserProfile

    var rank: Int = 0 // Set externally based on leaderboard position

    static func == (lhs: ChallengeParticipantProfile, rhs: ChallengeParticipantProfile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Challenge Activity

struct ChallengeActivity: Codable, Identifiable, Sendable {
    let id: UUID
    let challengeId: UUID
    let userId: UUID
    let activityType: ActivityType
    let activityData: ActivityData?
    let createdAt: Date

    enum ActivityType: String, Codable, Sendable {
        case joined
        case progress
        case milestone
        case completed
    }

    struct ActivityData: Codable, Sendable {
        let workoutName: String?
        let progressAmount: Decimal?
        let milestonePercent: Int?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case challengeId = "challenge_id"
        case userId = "user_id"
        case activityType = "activity_type"
        case activityData = "activity_data"
        case createdAt = "created_at"
    }
}
