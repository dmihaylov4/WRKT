import Testing
@testable import WRKT

struct CommitmentPostTests {

    @Test func captionWithProgressMentionsGoalAndCompleted() {
        let caption = makeCommitmentCaption(targetWorkouts: 4, completed: 2)
        #expect(caption.contains("4"))
        #expect(caption.contains("2"))
    }

    @Test func captionWithZeroCompletedMentionsGoal() {
        let caption = makeCommitmentCaption(targetWorkouts: 3, completed: 0)
        #expect(caption.contains("3"))
        #expect(!caption.contains("0/"))
    }

    @Test func weeklyProgressCaptionIncludesAllStats() {
        let caption = makeWeeklyProgressCaption(
            strengthDone: 2,
            strengthTarget: 3,
            minutesDone: 120,
            minutesTarget: 183,
            streak: 5,
            superStreak: 0
        )
        #expect(caption.contains("2/3"))
        #expect(caption.contains("120/183"))
        #expect(caption.contains("5"))
        #expect(!caption.contains("Super"))
    }

    @Test func weeklyProgressCaptionShowsSuperStreakWhenNonZero() {
        let caption = makeWeeklyProgressCaption(
            strengthDone: 3,
            strengthTarget: 3,
            minutesDone: 183,
            minutesTarget: 183,
            streak: 8,
            superStreak: 3
        )
        #expect(caption.contains("Super streak"))
        #expect(caption.contains("3"))
    }
}
