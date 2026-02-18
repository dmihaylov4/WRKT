import Foundation

// MARK: - Battle Type

enum BattleType: String, Codable, Sendable, Hashable {
    case volume = "volume"
    case consistency = "consistency"
    case workoutCount = "workout_count"
    case pr = "pr"
    case exercise = "exercise"

    var displayName: String {
        switch self {
        case .volume: return "Total Volume"
        case .consistency: return "Most Workouts"
        case .workoutCount: return "Workout Count"
        case .pr: return "Most PRs"
        case .exercise: return "Exercise Challenge"
        }
    }

    var description: String {
        switch self {
        case .volume: return "Most total weight lifted (sets × reps × weight)"
        case .consistency: return "Most workout days completed"
        case .workoutCount: return "Most total workouts logged"
        case .pr: return "Most personal records set"
        case .exercise: return "Best performance on specific exercise"
        }
    }

    var icon: String {
        switch self {
        case .volume: return "scalemass.fill"
        case .consistency: return "calendar.badge.checkmark"
        case .workoutCount: return "figure.run"
        case .pr: return "trophy.fill"
        case .exercise: return "dumbbell.fill"
        }
    }

    var scoreUnit: String {
        switch self {
        case .volume: return "kg"
        case .consistency: return "days"
        case .workoutCount: return "workouts"
        case .pr: return "PRs"
        case .exercise: return "reps"
        }
    }
}

// MARK: - Battle Status

enum BattleStatus: String, Codable, Sendable, Hashable {
    case pending   // Waiting for opponent to accept
    case active    // Battle is ongoing
    case completed // Battle finished
    case declined  // Opponent declined
    case cancelled // Cancelled by either participant

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Battle Model

struct Battle: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let challengerId: UUID
    let opponentId: UUID
    let battleType: BattleType
    let targetMetric: String?
    let startDate: Date
    let endDate: Date
    var status: BattleStatus
    var winnerId: UUID?
    var challengerScore: Decimal
    var opponentScore: Decimal
    var customRules: String?
    var trashTalkEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case challengerId = "challenger_id"
        case opponentId = "opponent_id"
        case battleType = "battle_type"
        case targetMetric = "target_metric"
        case startDate = "start_date"
        case endDate = "end_date"
        case status
        case winnerId = "winner_id"
        case challengerScore = "challenger_score"
        case opponentScore = "opponent_score"
        case customRules = "custom_rules"
        case trashTalkEnabled = "trash_talk_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    var isActive: Bool {
        status == .active
    }

    var isPending: Bool {
        status == .pending
    }

    var isCompleted: Bool {
        status == .completed
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

    var scoreUnit: String {
        battleType.scoreUnit
    }

    func score(for userId: UUID) -> Decimal {
        if userId == challengerId {
            return challengerScore
        } else if userId == opponentId {
            return opponentScore
        }
        return 0
    }

    func opponentScore(for userId: UUID) -> Decimal {
        if userId == challengerId {
            return opponentScore
        } else if userId == opponentId {
            return challengerScore
        }
        return 0
    }

    func isLeading(userId: UUID) -> Bool {
        score(for: userId) > opponentScore(for: userId)
    }

    func scoreDifference(for userId: UUID) -> Decimal {
        abs(score(for: userId) - opponentScore(for: userId))
    }
}

// MARK: - Battle with Participants

struct BattleWithParticipants: Identifiable, Sendable, Hashable {
    let id: UUID
    let battle: Battle
    let challenger: UserProfile
    let opponent: UserProfile

    var currentUserId: UUID?

    var isUserChallenger: Bool {
        guard let userId = currentUserId else { return false }
        return userId == battle.challengerId
    }

    var userScore: Decimal {
        guard let userId = currentUserId else { return 0 }
        return battle.score(for: userId)
    }

    var opponentScore: Decimal {
        guard let userId = currentUserId else { return 0 }
        return battle.opponentScore(for: userId)
    }

    var isUserLeading: Bool {
        guard let userId = currentUserId else { return false }
        return battle.isLeading(userId: userId)
    }

    var scoreDifference: Decimal {
        guard let userId = currentUserId else { return 0 }
        return battle.scoreDifference(for: userId)
    }

    var opponentProfile: UserProfile {
        isUserChallenger ? opponent : challenger
    }

    var userProfile: UserProfile {
        isUserChallenger ? challenger : opponent
    }

    static func == (lhs: BattleWithParticipants, rhs: BattleWithParticipants) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Battle Activity

struct BattleActivity: Codable, Identifiable, Sendable {
    let id: UUID
    let battleId: UUID
    let userId: UUID
    let activityType: ActivityType
    let activityData: ActivityData?
    let createdAt: Date

    enum ActivityType: String, Codable, Sendable {
        case workoutLogged = "workout_logged"
        case tookLead = "took_lead"
        case milestone = "milestone"
        case accepted = "accepted"
        case completed = "completed"
    }

    struct ActivityData: Codable, Sendable {
        let workoutName: String?
        let scoreChange: Decimal?
        let newScore: Decimal?
        let milestone: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case battleId = "battle_id"
        case userId = "user_id"
        case activityType = "activity_type"
        case activityData = "activity_data"
        case createdAt = "created_at"
    }
}
