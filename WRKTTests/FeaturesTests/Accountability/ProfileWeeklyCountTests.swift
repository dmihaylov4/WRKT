import Testing
import Foundation
@testable import WRKT

struct ProfileWeeklyCountTests {

    @Test func countOnlyIncludesPostsFromCurrentWeek() {
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: Date(), anchorWeekday: 2)
        let inThisWeek = WorkoutPost.stub(workoutDate: weekStart.addingTimeInterval(3600))
        let beforeThisWeek = WorkoutPost.stub(workoutDate: weekStart.addingTimeInterval(-86400))

        let count = friendWorkoutsThisWeek(posts: [inThisWeek, beforeThisWeek])
        #expect(count == 1)
    }

    @Test func countIsZeroForEmptyPosts() {
        #expect(friendWorkoutsThisWeek(posts: []) == 0)
    }
}
