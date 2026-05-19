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
}
