import Testing
import Foundation
@testable import WRKT

@Suite("BattleType custom icon names")
struct BattleTypeIconTests {

    @Test("volume maps to battle-volume-icon")
    func volumeIcon() {
        #expect(BattleType.volume.customIconName == "battle-volume-icon")
    }

    @Test("consistency maps to battle-consistency-icon")
    func consistencyIcon() {
        #expect(BattleType.consistency.customIconName == "battle-consistency-icon")
    }

    @Test("workoutCount maps to battle-workout-count-icon")
    func workoutCountIcon() {
        #expect(BattleType.workoutCount.customIconName == "battle-workout-count-icon")
    }

    @Test("pr maps to battle-flags-icon")
    func prIcon() {
        #expect(BattleType.pr.customIconName == "battle-flags-icon")
    }

    @Test("exercise maps to battle-opponent-icon")
    func exerciseIcon() {
        #expect(BattleType.exercise.customIconName == "battle-opponent-icon")
    }

    @Test("runningDistance maps to battle-flags-icon")
    func runningDistanceIcon() {
        #expect(BattleType.runningDistance.customIconName == "battle-flags-icon")
    }
}

@Suite("BattlePostStats Codable")
struct BattlePostStatsCodableTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let fixedId   = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!

    private func makeStats(
        battleType: BattleType = .volume,
        isWinner: Bool = true
    ) -> BattlePostStats {
        BattlePostStats(
            battleId: Self.fixedId,
            battleType: battleType,
            myScore: 1500.5,
            opponentScore: 1200.0,
            opponentName: "Alice",
            opponentAvatarUrl: nil,
            scoreUnit: "kg",
            isWinner: isWinner,
            durationDays: 7,
            endDate: Self.fixedDate
        )
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test("encodes to snake_case JSON keys")
    func encodesCorrectKeys() throws {
        let data = try encoder.encode(makeStats())
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["battle_id"] != nil)
        #expect(json["battle_type"] != nil)
        #expect(json["my_score"] != nil)
        #expect(json["opponent_score"] != nil)
        #expect(json["opponent_name"] != nil)
        #expect(json["score_unit"] != nil)
        #expect(json["is_winner"] != nil)
        #expect(json["duration_days"] != nil)
        #expect(json["end_date"] != nil)
        #expect(json["opponent_avatar_url"] == nil)
    }

    @Test("round-trips through encode/decode for all BattleTypes")
    func roundTripAllTypes() throws {
        for type_ in [BattleType.volume, .consistency, .workoutCount, .pr, .exercise, .runningDistance] {
            let original = makeStats(battleType: type_)
            let decoded  = try decoder.decode(BattlePostStats.self, from: try encoder.encode(original))
            #expect(decoded == original, "Failed for \(type_.rawValue)")
        }
    }

    @Test("round-trips winner=false")
    func roundTripLoser() throws {
        let original = makeStats(isWinner: false)
        let decoded  = try decoder.decode(BattlePostStats.self, from: try encoder.encode(original))
        #expect(decoded == original)
    }
}

@Suite("WorkoutPost battle type decoding")
struct WorkoutPostBattleDecodeTests {

    @Test("WorkoutPost with postType=battle decodes battleStats")
    func decodesWithBattleStats() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "user_id": "12345678-1234-1234-1234-123456789013",
          "visibility": "public",
          "likes_count": 0,
          "comments_count": 0,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z",
          "post_type": "battle",
          "workout_data": {
            "id": "12345678-1234-1234-1234-123456789014",
            "date": "2025-01-01T00:00:00Z",
            "entries": []
          },
          "battle_stats": {
            "battle_id": "12345678-1234-1234-1234-123456789015",
            "battle_type": "volume",
            "my_score": "1500.5",
            "opponent_score": "1200.0",
            "opponent_name": "Alice",
            "score_unit": "kg",
            "is_winner": true,
            "duration_days": 7,
            "end_date": "2025-01-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(WorkoutPost.self, from: json)

        #expect(post.postType == .battle)
        #expect(post.battleStats != nil)
        #expect(post.battleStats?.isWinner == true)
        #expect(post.battleStats?.opponentName == "Alice")
    }

    @Test("WorkoutPost without battleStats decodes as nil")
    func decodesWithoutBattleStats() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "user_id": "12345678-1234-1234-1234-123456789013",
          "visibility": "public",
          "likes_count": 0,
          "comments_count": 0,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z",
          "post_type": "workout",
          "workout_data": {
            "id": "12345678-1234-1234-1234-123456789014",
            "date": "2025-01-01T00:00:00Z",
            "entries": []
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let post = try decoder.decode(WorkoutPost.self, from: json)

        #expect(post.postType == .workout)
        #expect(post.battleStats == nil)
    }
}
