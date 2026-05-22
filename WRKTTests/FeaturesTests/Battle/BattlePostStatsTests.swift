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
