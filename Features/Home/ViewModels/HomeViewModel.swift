//
//  HomeViewModel.swift
//  WRKT
//
//  Centralized data fetching and card priority logic for Home screen
//

import Foundation
import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class HomeViewModel {
    // MARK: - Dependencies
    private let workoutStore: WorkoutStoreV2
    private let plannerStore: PlannerStore
    private let recommendationEngine: RecommendationEngine
    private var weeklyGoal: WeeklyGoal?

    // Observe rest timer to update hero when timer changes
    private let restTimerManager = RestTimerManager.shared

    // Optional competitive features
    weak var battleRepository: BattleRepository?
    weak var challengeRepository: ChallengeRepository?

    // Optional social features
    weak var postRepository: PostRepository?
    weak var authService: SupabaseAuthService?

    // MARK: - State
    var carouselCards: [HomeCardType] = []
    var hasActivePlan: Bool = false
    var todaysPlan: PlannedWorkout?

    // MARK: - Init
    init(workoutStore: WorkoutStoreV2, plannerStore: PlannerStore, weeklyGoal: WeeklyGoal? = nil) {
        self.workoutStore = workoutStore
        self.plannerStore = plannerStore
        self.weeklyGoal = weeklyGoal
        self.recommendationEngine = RecommendationEngine(
            workoutStore: workoutStore,
            plannerStore: plannerStore,
            weeklyGoal: weeklyGoal
        )
    }

    // MARK: - Public Methods

    /// Refresh all data and rebuild card priority
    func refresh() async {
        checkTodaysPlan()
        await rebuildCarousel()
    }

    /// Set weekly goal (called from dependency injection)
    func setWeeklyGoal(_ goal: WeeklyGoal?) {
        self.weeklyGoal = goal
        recommendationEngine.setWeeklyGoal(goal)
        Task {
            await rebuildCarousel()
        }
    }

    // MARK: - Private Helpers

    /// Check if there's a planned workout for today
    private func checkTodaysPlan() {
        todaysPlan = try? plannerStore.plannedWorkout(for: .now)
        hasActivePlan = todaysPlan != nil
    }

    /// Rebuild carousel based on priority system (MAX 3 CARDS)
    private func rebuildCarousel() async {
        var cards: [HomeCardType] = []
        let maxCards = 3 // Prevent overcrowding

        // Priority 1: Friend Activity Card - HIGHEST IMPACT (social accountability)
        if cards.count < maxCards, let friendActivity = await getFriendActivityToday() {
            cards.append(.friendActivity(friendActivity))
        }

        // Priority 2: Recent PR Card - Celebrate wins immediately
        if cards.count < maxCards, let recentPR = getRecentPR(within: 7) {
            cards.append(.recentPR(recentPR))
        }

        // Priority 3: Combined Recent Activity Card - Shows both strength AND cardio
        if cards.count < maxCards {
            let lastWorkout = getLastWorkout()
            let lastCardio = getLastCardio()

            // Get within 7 days only
            let validWorkout: CompletedWorkout? = {
                guard let workout = lastWorkout else { return nil }
                let daysSince = Calendar.current.dateComponents([.day], from: workout.date, to: .now).day ?? 0
                return daysSince <= 7 ? workout : nil
            }()

            let validCardio: Run? = {
                guard let cardio = lastCardio else { return nil }
                let daysSince = Calendar.current.dateComponents([.day], from: cardio.date, to: .now).day ?? 0
                return daysSince <= 7 ? cardio : nil
            }()

            // Only show if at least one activity exists
            if validWorkout != nil || validCardio != nil {
                let summary = RecentActivitySummary(
                    lastWorkout: validWorkout,
                    lastCardio: validCardio
                )
                cards.append(.recentActivity(summary))
            }
        }

        // Priority 4: Recommendation Card - Only if space available
        if cards.count < maxCards, let recommendation = generateRecommendation() {
            cards.append(.recommendation(recommendation))
        }

        // Priority 5: Active Competition Card - if active battle OR challenge
        if cards.count < maxCards, let competition = getTopCompetition() {
            cards.append(.activeCompetition(competition))
        }

        // NOTE: Comparative Stats removed from carousel (redundant with Weekly Stats Card)
        // Weekly comparison data is already visible in UnifiedWeeklyStatsCard

        self.carouselCards = cards
    }

    // MARK: - Data Fetching Methods

    /// Get last completed workout
    func getLastWorkout() -> CompletedWorkout? {
        workoutStore.completedWorkouts.last
    }

    /// Get last cardio activity (run/walk/cycle)
    func getLastCardio() -> Run? {
        let validRuns = workoutStore.validRuns
        // Get the most recent run by date (not just .last which depends on array order)
        return validRuns.max(by: { $0.date < $1.date })
    }

    /// Get weekly progress (completed days, goal days, percentage)
    func getWeeklyProgress() -> WeeklyProgressData? {
        guard let goal = weeklyGoal, goal.isSet else { return nil }

        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

        // Count workouts in current week
        let workoutsThisWeek = workoutStore.completedWorkouts.filter { workout in
            workout.date >= weekStart && workout.date < weekEnd
        }

        let completedDays = workoutsThisWeek.count
        let targetDays = goal.targetStrengthDays
        let percentage = targetDays > 0 ? (Double(completedDays) / Double(targetDays)) * 100.0 : 0.0

        // Calculate days remaining in week
        let daysRemaining = calendar.dateComponents([.day], from: .now, to: weekEnd).day ?? 0

        return WeeklyProgressData(
            completedDays: completedDays,
            targetDays: targetDays,
            percentage: percentage,
            daysRemaining: max(0, daysRemaining)
        )
    }

    /// Get most recent PR within specified days
    func getRecentPR(within days: Int) -> PRSummary? {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now

        // Look through recent workouts for any PRs
        let recentWorkouts = workoutStore.completedWorkouts.filter { $0.date >= cutoffDate }

        for workout in recentWorkouts.reversed() {
            for entry in workout.entries {
                // Check if any set in this entry is a PR
                if let prInfo = checkForPR(entry: entry, workoutDate: workout.date) {
                    return prInfo
                }
            }
        }

        return nil
    }

    /// Check if an entry contains a PR
    private func checkForPR(entry: WorkoutEntry, workoutDate: Date) -> PRSummary? {
        guard let exercise = ExerciseRepository.shared.exercise(byID: entry.exerciseID) else { return nil }

        // Get historical best for this exercise
        let historicalBest = workoutStore.bestWeightForExactReps(exercise: exercise, reps: 10) ?? 0

        // Check if any set beats the historical best
        for set in entry.sets where set.tag == .working && set.isCompleted {
            if set.weight > historicalBest && set.weight > 0 {
                return PRSummary(
                    exerciseName: entry.exerciseName,
                    weight: set.weight,
                    reps: set.reps,
                    date: workoutDate
                )
            }
        }

        return nil
    }

    /// Get top active competition (battle or challenge)
    func getTopCompetition() -> CompetitionSummary? {
        // Check for active battles
        // TODO: Implement when battle/challenge repositories are injected
        // For now, return nil
        return nil
    }

    /// Generate workout recommendation based on history and patterns
    func generateRecommendation() -> WorkoutRecommendation? {
        // Delegate to recommendation engine for smart logic
        return recommendationEngine.generate()
    }

    /// Get friend activity for today
    func getFriendActivityToday() async -> FriendActivitySummary? {
        guard let postRepository = postRepository,
              let authService = authService,
              let currentUserId = authService.currentUser?.id else {
            AppLogger.warning("Missing dependencies for friend activity", category: AppLogger.app)
            return nil // No mock data - only show real friend activity
        }

        AppLogger.info("Fetching friend activity for user: \(currentUserId)", category: AppLogger.app)

        do {
            // Fetch friends' recent posts (last 3 days for better visibility)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today) ?? today
            AppLogger.debug("Fetching friend activity from last 3 days (since \(threeDaysAgo))", category: AppLogger.app)

            // Fetch feed which includes friends' posts
            let result = try await postRepository.fetchFeed(
                userId: currentUserId,
                limit: 50,
                cursor: nil
            )

            AppLogger.success("Fetched \(result.posts.count) total posts from feed", category: AppLogger.app)

            // Debug: Log all posts
            for post in result.posts.prefix(5) {
                AppLogger.debug("Post: \(post.author.username) - \(post.post.createdAt)", category: AppLogger.app)
            }

            // Filter to recent posts from friends (last 3 days, not self)
            let friendPostsRecent = result.posts.filter { postWithAuthor in
                let postDate = postWithAuthor.post.createdAt
                let isRecent = postDate >= threeDaysAgo
                let isNotSelf = postWithAuthor.author.id != currentUserId
                AppLogger.debug("Post by \(postWithAuthor.author.username): date=\(postDate), isRecent=\(isRecent), isNotSelf=\(isNotSelf)", category: AppLogger.app)
                return isRecent && isNotSelf
            }

            AppLogger.success("Found \(friendPostsRecent.count) friend posts from last 3 days out of \(result.posts.count) total", category: AppLogger.app)

            // Check if user worked out today
            let userPostsToday = result.posts.filter { postWithAuthor in
                let postDate = calendar.startOfDay(for: postWithAuthor.post.createdAt)
                return postDate == today && postWithAuthor.author.id == currentUserId
            }
            let userWorkedOutToday = !userPostsToday.isEmpty

            // Convert to FriendWorkoutActivity
            let activities: [FriendActivitySummary.FriendWorkoutActivity] = friendPostsRecent.map { postWithAuthor in
                let workoutData = postWithAuthor.post.workoutData

                // Calculate duration if available
                var duration: Int?
                if let startedAt = workoutData.startedAt {
                    let durationInSeconds = postWithAuthor.post.createdAt.timeIntervalSince(startedAt)
                    duration = max(1, Int(durationInSeconds / 60)) // minutes
                }

                return FriendActivitySummary.FriendWorkoutActivity(
                    id: postWithAuthor.post.id,
                    friendId: postWithAuthor.author.id,
                    friendName: postWithAuthor.author.displayName ?? postWithAuthor.author.username,
                    friendUsername: postWithAuthor.author.username,
                    friendAvatarUrl: postWithAuthor.author.avatarUrl,
                    workoutName: workoutData.workoutName ?? "Workout",
                    duration: duration,
                    completedAt: postWithAuthor.post.createdAt
                )
            }
            .sorted { $0.completedAt > $1.completedAt } // Most recent first

            // Trigger smart nudge notifications if enabled and user hasn't worked out
            if !userWorkedOutToday && !activities.isEmpty {
                await triggerSmartNudges(activities: activities)
            }

            // Only show card if there's friend activity OR user hasn't worked out
            if activities.isEmpty && userWorkedOutToday {
                return nil // Don't show card if user worked out and no friends did
            }

            // Only return if we have actual activities
            if activities.isEmpty {
                AppLogger.info("No friend activity found in last 3 days", category: AppLogger.app)
                return nil
            }

            return FriendActivitySummary(
                activities: activities,
                userWorkedOutToday: userWorkedOutToday
            )
        } catch {
            AppLogger.error("Failed to fetch friend activity", error: error, category: AppLogger.app)
            return nil // Don't show mock data on error
        }
    }

    /// Get comparative stats (You vs. Friends) for this week
    func getComparativeStats() async -> ComparativeStats? {
        guard let postRepository = postRepository,
              let authService = authService,
              let currentUserId = authService.currentUser?.id,
              let weeklyGoal = weeklyGoal else {
            return nil
        }

        do {
            // Get current week range
            let calendar = Calendar.current
            let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: weeklyGoal.anchorWeekday)
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

            // Count user's workouts this week
            let userWorkoutsThisWeek = workoutStore.completedWorkouts.filter { workout in
                workout.date >= weekStart && workout.date < weekEnd
            }.count

            // Fetch friends' posts from this week
            let result = try await postRepository.fetchFeed(
                userId: currentUserId,
                limit: 100, // Get more to ensure we have all friends' data
                cursor: nil
            )

            // Group posts by author (friends only, not self)
            var friendWorkoutCounts: [UUID: Int] = [:]
            for postWithAuthor in result.posts {
                let postDate = postWithAuthor.post.createdAt
                let isThisWeek = postDate >= weekStart && postDate < weekEnd
                let isNotSelf = postWithAuthor.author.id != currentUserId

                if isThisWeek && isNotSelf {
                    friendWorkoutCounts[postWithAuthor.author.id, default: 0] += 1
                }
            }

            // Calculate friends average
            let totalFriendWorkouts = friendWorkoutCounts.values.reduce(0, +)
            let friendCount = friendWorkoutCounts.count

            guard friendCount > 0 else { return nil } // Don't show card if no friends

            let friendsAverage = Double(totalFriendWorkouts) / Double(friendCount)

            // Format week range (e.g., "Dec 18-24")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let startStr = dateFormatter.string(from: weekStart)
            dateFormatter.dateFormat = "d"
            let endDate = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let endStr = dateFormatter.string(from: endDate)
            let weekRange = "\(startStr)-\(endStr)"

            return ComparativeStats(
                userWorkouts: userWorkoutsThisWeek,
                friendsAverage: friendsAverage,
                friendCount: friendCount,
                weekRange: weekRange
            )
        } catch {
            AppLogger.error("Failed to fetch comparative stats", error: error, category: AppLogger.app)
            return nil
        }
    }

    /// Trigger smart nudge notifications based on friend activity
    private func triggerSmartNudges(activities: [FriendActivitySummary.FriendWorkoutActivity]) async {
        // Only send notifications if user hasn't worked out and there's friend activity
        guard !activities.isEmpty else { return }

        // Get most recent friend activity (already sorted)
        if let mostRecent = activities.first {
            // Check if this is a recent workout (within last hour) to avoid old notifications
            let hoursSince = Date.now.timeIntervalSince(mostRecent.completedAt) / 3600
            if hoursSince <= 1.0 {
                // Send friend activity nudge
                await SmartNudgeManager.shared.sendFriendActivityNudge(
                    friendName: mostRecent.friendName,
                    workoutName: mostRecent.workoutName
                )
            }
        }

        // Send comparative nudge if 2+ friends worked out TODAY (not from last 3 days)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let activitiesToday = activities.filter { activity in
            calendar.startOfDay(for: activity.completedAt) == today
        }

        if activitiesToday.count >= 2 {
            await SmartNudgeManager.shared.sendComparativeNudge(activeCount: activitiesToday.count)
        }
    }

    // MARK: - Hero Button Data

    /// Get hero button content based on whether plan exists or workout is active
    func getHeroButtonContent() -> HeroButtonContent {
        // Priority 1: Check for active workout FIRST
        if let currentWorkout = workoutStore.currentWorkout,
           !currentWorkout.entries.isEmpty {

            // Calculate stats
            let exercises = currentWorkout.entries.count
            let completedSets = currentWorkout.entries.reduce(0) { total, entry in
                total + entry.sets.filter { $0.isCompleted }.count
            }
            let duration = Date.now.timeIntervalSince(currentWorkout.startedAt)

            // Check if rest timer is RUNNING (not just active - excludes completed state)
            if restTimerManager.isRunning,
               case .running(_, _, let exerciseName, _, _) = restTimerManager.state {

                return HeroButtonContent(
                    icon: "timer",
                    mainText: "Live Workout",
                    secondaryText: "",  // Won't be used in dynamic view
                    hasPlan: false,
                    workoutState: .activeWorkoutWithRest(
                        exercises: exercises,
                        completedSets: completedSets,
                        duration: duration,
                        startDate: currentWorkout.startedAt,
                        restTimeRemaining: restTimerManager.remainingSeconds,
                        restExerciseName: exerciseName
                    )
                )
            } else {
                return HeroButtonContent(
                    icon: "dumbbell.fill",
                    mainText: "Live Workout",
                    secondaryText: "",  // Won't be used in dynamic view
                    hasPlan: false,
                    workoutState: .activeWorkout(
                        exercises: exercises,
                        completedSets: completedSets,
                        duration: duration,
                        startDate: currentWorkout.startedAt
                    )
                )
            }
        }

        // Priority 2: Check for today's plan
        if let plan = todaysPlan {
            return HeroButtonContent(
                icon: "calendar.badge.checkmark",
                mainText: "Follow Today's Plan",
                secondaryText: "\(plan.exercises.count) exercises • \(plan.splitDayName)",
                hasPlan: true
            )
        }

        // Default: No workout, no plan
        return HeroButtonContent(
            icon: "dumbbell.fill",
            mainText: "Start Workout",
            secondaryText: getMotivationalMessage(),
            hasPlan: false
        )
    }

    /// Get motivational message based on streak
    private func getMotivationalMessage() -> String {
        let streak = workoutStore.streak()

        if streak >= 7 {
            return "\(streak) day streak! Keep it going"
        } else if streak >= 3 {
            return "Great momentum! Let's keep building"
        } else {
            return "Let's get stronger today"
        }
    }

    // MARK: - Cardio Stats

    /// Get active minutes for this week
    func getActiveMinutesThisWeek() -> (active: Int, target: Int) {
        guard let goal = weeklyGoal else { return (0, 150) } // Default 150 min target

        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return (0, goal.targetActiveMinutes)
        }

        // Get cardio runs from this week
        let runsThisWeek = workoutStore.validRuns.filter { run in
            run.date >= weekStart && run.date < weekEnd
        }

        // Sum up duration in minutes
        let totalMinutes = runsThisWeek.reduce(0) { sum, run in
            sum + (run.durationSec / 60)
        }

        return (totalMinutes, goal.targetActiveMinutes)
    }

    /// Get unified weekly stats (both strength and cardio)
    func getUnifiedWeeklyStats() -> UnifiedWeeklyStats? {
        guard let goal = weeklyGoal, goal.isSet else { return nil }

        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

        // Count strength workouts in current week
        let workoutsThisWeek = workoutStore.completedWorkouts.filter { workout in
            workout.date >= weekStart && workout.date < weekEnd
        }

        // Count cardio minutes in current week
        let runsThisWeek = workoutStore.validRuns.filter { run in
            run.date >= weekStart && run.date < weekEnd
        }

        let totalCardioMinutes = runsThisWeek.reduce(0) { sum, run in
            sum + (run.durationSec / 60)
        }

        // Calculate days remaining in week
        let daysRemaining = calendar.dateComponents([.day], from: .now, to: weekEnd).day ?? 0

        return UnifiedWeeklyStats(
            strengthCompleted: workoutsThisWeek.count,
            strengthTarget: goal.targetStrengthDays,
            cardioMinutes: totalCardioMinutes,
            cardioTarget: goal.targetActiveMinutes,
            daysRemaining: max(0, daysRemaining)
        )
    }

    /// Get unified weekly stats with streak data and urgency warnings
    func getUnifiedWeeklyStatsWithStreak(context: ModelContext) -> UnifiedWeeklyStatsWithStreak? {
        guard let goal = weeklyGoal, goal.isSet else { return nil }

        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

        // USE CONSISTENT CALCULATION: Get week progress from WorkoutStoreV2
        // This ensures HomeView shows the same MVPA minutes as ProfileView, CalendarView, and streak validation
        let weekProgress = workoutStore.currentWeekProgress(goal: goal, context: context)

        // Calculate days remaining
        let daysRemaining = calendar.dateComponents([.day], from: .now, to: weekEnd).day ?? 0

        // Get current streak
        let currentStreak = RewardsEngine.shared.weeklyGoalStreak()

        // Calculate milestone
        let (nextMilestone, milestoneProgress) = calculateStreakMilestone(currentStreak: currentStreak)

        // Calculate urgency
        let (urgencyLevel, urgencyMessage) = calculateStreakUrgency(
            strengthCompleted: weekProgress.strengthDaysDone,
            strengthTarget: goal.targetStrengthDays,
            cardioMinutes: weekProgress.mvpaDone,
            cardioTarget: goal.targetActiveMinutes,
            daysRemaining: max(0, daysRemaining),
            currentStreak: currentStreak
        )

        return UnifiedWeeklyStatsWithStreak(
            strengthCompleted: weekProgress.strengthDaysDone,
            strengthTarget: goal.targetStrengthDays,
            cardioMinutes: weekProgress.mvpaDone,
            cardioTarget: goal.targetActiveMinutes,
            daysRemaining: max(0, daysRemaining),
            currentStreak: currentStreak,
            nextMilestone: nextMilestone,
            milestoneProgress: milestoneProgress,
            urgencyLevel: urgencyLevel,
            urgencyMessage: urgencyMessage
        )
    }

    /// Calculate streak urgency level based on current progress
    private func calculateStreakUrgency(
        strengthCompleted: Int,
        strengthTarget: Int,
        cardioMinutes: Int,
        cardioTarget: Int,
        daysRemaining: Int,
        currentStreak: Int
    ) -> (level: StreakUrgencyLevel, message: String?) {
        // Only show urgency if user has streak to protect (>= 2 weeks)
        guard currentStreak >= 2 else { return (.safe, nil) }

        // Check if either goal met (OR logic - existing pattern)
        let strengthGoalMet = strengthCompleted >= strengthTarget
        let mvpaGoalMet = cardioTarget > 0 ? (cardioMinutes >= cardioTarget) : true

        if strengthGoalMet || mvpaGoalMet {
            return (.safe, nil)  // Week goal already met
        }

        let strengthNeeded = strengthTarget - strengthCompleted

        // Critical: Less than 2 days remaining
        if daysRemaining <= 1 && strengthNeeded > daysRemaining {
            return (.critical, "Need \(strengthNeeded) workouts in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") to maintain \(currentStreak)-week streak")
        }

        // Caution: Need more than 1 workout per remaining day
        let workoutsPerDay = daysRemaining > 0 ? Double(strengthNeeded) / Double(daysRemaining) : Double(strengthNeeded)
        if workoutsPerDay > 1.0 {
            return (.caution, "Need \(strengthNeeded) workouts in \(daysRemaining) days to stay on track")
        }

        return (.safe, nil)
    }

    /// Calculate next milestone and progress toward it
    private func calculateStreakMilestone(currentStreak: Int) -> (next: Int?, progress: Double) {
        let milestones = [2, 4, 8, 12, 26, 52]

        guard let nextMilestone = milestones.first(where: { $0 > currentStreak }) else {
            return (nil, 1.0)  // Past all milestones
        }

        let previousMilestone = milestones.last(where: { $0 < currentStreak }) ?? 0
        let rangeSize = nextMilestone - previousMilestone
        let progress = Double(currentStreak - previousMilestone) / Double(rangeSize)

        return (nextMilestone, max(0, min(1, progress)))
    }

    // MARK: - Header Data

    /// Get user's display name from profile (first name only for greeting)
    func getUserDisplayName() -> String {
        // Try to get display name from auth service
        if let displayName = authService?.currentUser?.profile?.displayName, !displayName.isEmpty {
            // Use only first name for a cleaner greeting
            let firstName = displayName.split(separator: " ").first.map(String.init) ?? displayName
            return firstName
        }

        // Fallback to username if no display name
        if let username = authService?.currentUser?.profile?.username, !username.isEmpty {
            return username
        }

        // Final fallback
        return "there"
    }

    /// Get greeting based on time of day
    func getGreeting(userName: String = "there") -> String {
        let hour = Calendar.current.component(.hour, from: .now)

        switch hour {
        case 0..<12:
            return "Good morning, \(userName)"
        case 12..<17:
            return "Good afternoon, \(userName)"
        case 17..<22:
            return "Good evening, \(userName)"
        default:
            return "Hey, \(userName)"
        }
    }

    /// Get current weekly streak
    func getCurrentStreak() -> Int {
        RewardsEngine.shared.weeklyGoalStreak()
    }
}

// MARK: - Supporting Types

enum HomeCardType: Identifiable {
    case lastWorkout(CompletedWorkout)
    case lastCardio(Run)
    case recentActivity(RecentActivitySummary) // NEW: Combined strength + cardio
    case weeklyProgress(WeeklyProgressData)
    case activeCompetition(CompetitionSummary)
    case recentPR(PRSummary)
    case recommendation(WorkoutRecommendation)
    case friendActivity(FriendActivitySummary)
    case comparativeStats(ComparativeStats)

    var id: String {
        switch self {
        case .lastWorkout: return "lastWorkout"
        case .lastCardio: return "lastCardio"
        case .recentActivity: return "recentActivity"
        case .weeklyProgress: return "weeklyProgress"
        case .activeCompetition: return "activeCompetition"
        case .recentPR: return "recentPR"
        case .recommendation: return "recommendation"
        case .friendActivity: return "friendActivity"
        case .comparativeStats: return "comparativeStats"
        }
    }
}

struct WeeklyProgressData {
    let completedDays: Int
    let targetDays: Int
    let percentage: Double
    let daysRemaining: Int
}

struct PRSummary {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let date: Date

    var relativeDateString: String {
        let calendar = Calendar.current
        let daysSince = calendar.dateComponents([.day], from: date, to: .now).day ?? 0

        if daysSince == 0 {
            return "Today"
        } else if daysSince == 1 {
            return "Yesterday"
        } else {
            return "\(daysSince) days ago"
        }
    }
}

struct CompetitionSummary {
    let name: String
    let type: CompetitionType
    let status: String
    let daysLeft: Int

    enum CompetitionType {
        case battle
        case challenge
    }
}

struct WorkoutRecommendation {
    let icon: String
    let title: String
    let reason: String
    let action: RecommendationAction?

    struct RecommendationAction {
        let label: String
        let handler: () -> Void
    }
}

struct FriendActivitySummary {
    let activities: [FriendWorkoutActivity]
    let userWorkedOutToday: Bool

    struct FriendWorkoutActivity: Identifiable {
        let id: UUID
        let friendId: UUID
        let friendName: String
        let friendUsername: String
        let friendAvatarUrl: String?
        let workoutName: String
        let duration: Int? // minutes
        let completedAt: Date

        var timeAgoText: String {
            let calendar = Calendar.current
            let now = Date()
            let components = calendar.dateComponents([.day, .hour, .minute], from: completedAt, to: now)

            if let days = components.day, days > 0 {
                return days == 1 ? "Yesterday" : "\(days)d ago"
            } else if let hours = components.hour, hours > 0 {
                return "\(hours)h ago"
            } else if let minutes = components.minute, minutes > 0 {
                return "\(minutes)m ago"
            } else {
                return "Just now"
            }
        }

        var durationText: String? {
            guard let duration = duration else { return nil }
            if duration < 60 {
                return "\(duration) min"
            } else {
                let hours = duration / 60
                let mins = duration % 60
                if mins == 0 {
                    return "\(hours)h"
                } else {
                    return "\(hours)h \(mins)m"
                }
            }
        }
    }
}

enum HeroWorkoutState: Equatable {
    case noWorkout
    case activeWorkout(
        exercises: Int,
        completedSets: Int,
        duration: TimeInterval,
        startDate: Date
    )
    case activeWorkoutWithRest(
        exercises: Int,
        completedSets: Int,
        duration: TimeInterval,
        startDate: Date,
        restTimeRemaining: TimeInterval,
        restExerciseName: String
    )
}

struct HeroButtonContent {
    let icon: String
    let mainText: String
    let secondaryText: String
    let hasPlan: Bool
    let workoutState: HeroWorkoutState

    init(icon: String, mainText: String, secondaryText: String, hasPlan: Bool, workoutState: HeroWorkoutState = .noWorkout) {
        self.icon = icon
        self.mainText = mainText
        self.secondaryText = secondaryText
        self.hasPlan = hasPlan
        self.workoutState = workoutState
    }
}

struct UnifiedWeeklyStats {
    let strengthCompleted: Int
    let strengthTarget: Int
    let cardioMinutes: Int
    let cardioTarget: Int
    let daysRemaining: Int
}

// MARK: - Streak Urgency Types

enum StreakUrgencyLevel {
    case safe       // On track or ahead
    case caution    // Need to pick up pace
    case critical   // At risk of losing streak

    var color: Color {
        switch self {
        case .safe: return DS.Semantic.success
        case .caution: return DS.Semantic.warning
        case .critical: return DS.Semantic.danger
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

struct UnifiedWeeklyStatsWithStreak {
    // Existing fields
    let strengthCompleted: Int
    let strengthTarget: Int
    let cardioMinutes: Int
    let cardioTarget: Int
    let daysRemaining: Int

    // NEW: Streak data
    let currentStreak: Int
    let nextMilestone: Int?
    let milestoneProgress: Double  // 0.0 to 1.0

    // NEW: Urgency data
    let urgencyLevel: StreakUrgencyLevel
    let urgencyMessage: String?
}

struct ComparativeStats {
    let userWorkouts: Int
    let friendsAverage: Double
    let friendCount: Int
    let weekRange: String // e.g., "Dec 18-24"

    var performanceStatus: PerformanceStatus {
        let diff = Double(userWorkouts) - friendsAverage
        if diff > 1.0 {
            return .crushing // User is 2+ workouts ahead
        } else if diff > 0.5 {
            return .ahead // User is ahead
        } else if diff > -0.5 {
            return .onPar // Within range
        } else if diff > -1.0 {
            return .behind // Slightly behind
        } else {
            return .wayBehind // 2+ workouts behind
        }
    }

    enum PerformanceStatus {
        case crushing    // User is way ahead
        case ahead      // User is ahead
        case onPar      // About equal
        case behind     // User is behind
        case wayBehind  // User is way behind

        var icon: String {
            switch self {
            case .crushing: return "flame.fill"
            case .ahead: return "arrow.up.circle.fill"
            case .onPar: return "equal.circle.fill"
            case .behind: return "arrow.down.circle.fill"
            case .wayBehind: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .crushing: return DS.Palette.marone
            case .ahead: return .green
            case .onPar: return .blue
            case .behind: return .orange
            case .wayBehind: return .red
            }
        }

        var message: String {
            switch self {
            case .crushing: return "You're crushing it!"
            case .ahead: return "Ahead of the pack"
            case .onPar: return "Keeping pace"
            case .behind: return "Time to catch up"
            case .wayBehind: return "Don't get left behind"
            }
        }
    }
}

struct RecentActivitySummary {
    let lastWorkout: CompletedWorkout?
    let lastCardio: Run?

    var hasStrength: Bool { lastWorkout != nil }
    var hasCardio: Bool { lastCardio != nil }
    var hasBoth: Bool { hasStrength && hasCardio }

    // Get most recent date for sorting
    var mostRecentDate: Date {
        let workoutDate = lastWorkout?.date
        let cardioDate = lastCardio?.date

        if let w = workoutDate, let c = cardioDate {
            return max(w, c)
        }
        return workoutDate ?? cardioDate ?? .distantPast
    }
}
