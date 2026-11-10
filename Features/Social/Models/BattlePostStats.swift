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

extension BattlePostStats {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Older battle posts stored decimal scores as JSON strings.
        func score(_ key: CodingKeys) throws -> Decimal {
            if let number = try? values.decode(Decimal.self, forKey: key) { return number }
            let text = try values.decode(String.self, forKey: key)
            guard let number = try? JSONDecoder().decode(Decimal.self, from: Data(text.utf8)) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Expected a decimal score")
            }
            return number
        }
        battleId = try values.decode(UUID.self, forKey: .battleId)
        battleType = try values.decode(BattleType.self, forKey: .battleType)
        myScore = try score(.myScore)
        opponentScore = try score(.opponentScore)
        myName = try values.decodeIfPresent(String.self, forKey: .myName)
        opponentName = try values.decode(String.self, forKey: .opponentName)
        opponentAvatarUrl = try values.decodeIfPresent(String.self, forKey: .opponentAvatarUrl)
        scoreUnit = try values.decode(String.self, forKey: .scoreUnit)
        isWinner = try values.decode(Bool.self, forKey: .isWinner)
        durationDays = try values.decode(Int.self, forKey: .durationDays)
        endDate = try values.decode(Date.self, forKey: .endDate)
    }
}
