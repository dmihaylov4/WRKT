import Foundation

struct BattlePostStats: Codable, Sendable, Equatable, Hashable {
    let battleId: UUID
    let battleType: BattleType
    let myScore: Decimal
    let opponentScore: Decimal
    let myName: String?         // display name of the person who shared; nil for old posts
    let opponentName: String
    let opponentAvatarUrl: String?
    let scoreUnit: String
    let isWinner: Bool
    let durationDays: Int
    let endDate: Date

    enum CodingKeys: String, CodingKey {
        case battleId = "battle_id"
        case battleType = "battle_type"
        case myScore = "my_score"
        case opponentScore = "opponent_score"
        case myName = "my_name"
        case opponentName = "opponent_name"
        case opponentAvatarUrl = "opponent_avatar_url"
        case scoreUnit = "score_unit"
        case isWinner = "is_winner"
        case durationDays = "duration_days"
        case endDate = "end_date"
    }
}
