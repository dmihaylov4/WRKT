import Foundation

struct WeeklyProgressStats {
    let weekStart: Date
    let totalVolumeKg: Double
    let totalExercises: Int
    let totalSets: Int
    let strengthDaysDone: Int
    let strengthTarget: Int
    let activeMinutesDone: Int
    let activeMinutesTarget: Int
    let streak: Int
    let superStreak: Int
}

/// Holds pending data for the cross-tab "Share Progress" flow.
/// ProfileView writes here, FeedView reads here when openProgressShareSheet fires.
@MainActor
final class ProgressShareCoordinator {
    static let shared = ProgressShareCoordinator()
    private init() {}

    var pendingWorkouts: [CompletedWorkout] = []
    var pendingStats: WeeklyProgressStats?

    func set(workouts: [CompletedWorkout], stats: WeeklyProgressStats) {
        pendingWorkouts = workouts
        pendingStats = stats
    }

    func consume() -> (workouts: [CompletedWorkout], stats: WeeklyProgressStats?) {
        let result = (pendingWorkouts, pendingStats)
        pendingWorkouts = []
        pendingStats = nil
        return result
    }
}
