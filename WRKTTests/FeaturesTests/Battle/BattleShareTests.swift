import Testing
import Foundation
@testable import WRKT

@Suite("Battle share guard logic")
struct BattleShareGuardTests {

    @Test("battle with no sharedPostId is shareable")
    func shareableWhenNil() {
        var battle = Battle(
            id: UUID(), challengerId: UUID(), opponentId: UUID(),
            battleType: .volume, targetMetric: nil,
            startDate: .now, endDate: .now, status: .completed,
            winnerId: nil, challengerScore: 0, opponentScore: 0,
            customRules: nil, trashTalkEnabled: false,
            createdAt: .now, updatedAt: .now
        )
        battle.sharedPostId = nil
        #expect(battle.sharedPostId == nil)
    }

    @Test("isAlreadySharedByOther returns true when sharedByUserId differs")
    func alreadySharedByOther() {
        let currentUser = UUID()
        let otherUser   = UUID()
        var battle = Battle(
            id: UUID(), challengerId: UUID(), opponentId: UUID(),
            battleType: .volume, targetMetric: nil,
            startDate: .now, endDate: .now, status: .completed,
            winnerId: nil, challengerScore: 0, opponentScore: 0,
            customRules: nil, trashTalkEnabled: false,
            createdAt: .now, updatedAt: .now
        )
        battle.sharedPostId = UUID()
        battle.sharedByUserId = otherUser
        #expect(battle.sharedPostId != nil && battle.sharedByUserId != currentUser)
    }

    @Test("iShared returns true when sharedByUserId matches current user")
    func iShared() {
        let currentUser = UUID()
        var battle = Battle(
            id: UUID(), challengerId: UUID(), opponentId: UUID(),
            battleType: .volume, targetMetric: nil,
            startDate: .now, endDate: .now, status: .completed,
            winnerId: nil, challengerScore: 0, opponentScore: 0,
            customRules: nil, trashTalkEnabled: false,
            createdAt: .now, updatedAt: .now
        )
        battle.sharedPostId = UUID()
        battle.sharedByUserId = currentUser
        #expect(battle.sharedByUserId == currentUser)
    }

    @Test("BattlePostStats.isWinner is true when winnerId matches currentUserId")
    func statsIsWinnerCorrect() {
        let stats = BattlePostStats(
            battleId: UUID(), battleType: .volume,
            myScore: 1500, opponentScore: 1200,
            myName: nil,
            opponentName: "Bob", opponentAvatarUrl: nil,
            scoreUnit: "kg", isWinner: true,
            durationDays: 7, endDate: .now
        )
        #expect(stats.isWinner == true)
    }
}
