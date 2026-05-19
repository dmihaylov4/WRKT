import Testing
import Foundation
@testable import WRKT

@Suite(.serialized)
struct StreakRecoveryTests {

    @Test func flagSetWhenStreakDropsToZero() {
        UserDefaults.standard.removeObject(forKey: "streak_break_detected_at")
        UserDefaults.standard.removeObject(forKey: "streak_break_previous_streak")

        detectStreakBreak(oldStreak: 4, newStreak: 0)

        #expect(UserDefaults.standard.object(forKey: "streak_break_detected_at") != nil)
        #expect(UserDefaults.standard.integer(forKey: "streak_break_previous_streak") == 4)
    }

    @Test func flagNotSetWhenStreakImproves() {
        UserDefaults.standard.removeObject(forKey: "streak_break_detected_at")
        UserDefaults.standard.removeObject(forKey: "streak_break_previous_streak")

        detectStreakBreak(oldStreak: 2, newStreak: 3)

        #expect(UserDefaults.standard.object(forKey: "streak_break_detected_at") == nil)
    }

    @Test func flagNotSetWhenStreakWasAlreadyZero() {
        UserDefaults.standard.removeObject(forKey: "streak_break_detected_at")
        UserDefaults.standard.removeObject(forKey: "streak_break_previous_streak")

        detectStreakBreak(oldStreak: 0, newStreak: 0)

        #expect(UserDefaults.standard.object(forKey: "streak_break_detected_at") == nil)
    }
}
