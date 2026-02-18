//
//  RecommendationEngine.swift
//  WRKT
//
//  Generates smart workout recommendations based on user patterns and goals
//

import Foundation

@MainActor
final class RecommendationEngine {
    private let workoutStore: WorkoutStoreV2
    private let plannerStore: PlannerStore
    private var weeklyGoal: WeeklyGoal?

    init(workoutStore: WorkoutStoreV2, plannerStore: PlannerStore, weeklyGoal: WeeklyGoal? = nil) {
        self.workoutStore = workoutStore
        self.plannerStore = plannerStore
        self.weeklyGoal = weeklyGoal
    }

    func setWeeklyGoal(_ goal: WeeklyGoal?) {
        self.weeklyGoal = goal
    }

    /// Generate a recommendation based on user patterns
    /// Returns the highest-priority recommendation, or nil if none
    func generate() -> WorkoutRecommendation? {
        // Priority order of recommendations:
        // 1. Workout streak at risk
        // 2. Weekly goal in danger
        // 3. Comeback encouragement (3+ days inactive)
        // 4. Muscle group balance recommendation
        // 5. PR opportunity recommendation
        // 6. Plan adherence reminder

        if let recommendation = checkStreakAtRisk() { return recommendation }
        if let recommendation = checkWeeklyGoalDanger() { return recommendation }
        if let recommendation = checkComebackNeeded() { return recommendation }
        if let recommendation = checkMuscleBalance() { return recommendation }
        if let recommendation = checkPROpportunity() { return recommendation }
        if let recommendation = checkPlanAdherence() { return recommendation }

        return nil
    }

    // MARK: - Recommendation Checks

    /// Check if workout streak is at risk (active streak, but last workout was 2 days ago)
    private func checkStreakAtRisk() -> WorkoutRecommendation? {
        guard let lastWorkout = workoutStore.completedWorkouts.last else { return nil }

        let calendar = Calendar.current
        let daysSince = calendar.dateComponents([.day], from: lastWorkout.date, to: .now).day ?? 0
        let currentStreak = workoutStore.streak()

        // If user has a streak of 3+ days but hasn't worked out in 2 days
        if currentStreak >= 3 && daysSince == 2 {
            return WorkoutRecommendation(
                icon: "flame.fill",
                title: "Protect your \(currentStreak)-day streak",
                reason: "Don't let it slip away! Work out today to keep it going",
                action: nil
            )
        }

        return nil
    }

    /// Check if weekly goal is in danger
    private func checkWeeklyGoalDanger() -> WorkoutRecommendation? {
        guard let goal = weeklyGoal, goal.isSet else { return nil }

        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: .now, anchorWeekday: goal.anchorWeekday)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

        let workoutsThisWeek = workoutStore.completedWorkouts.filter { workout in
            workout.date >= weekStart && workout.date < weekEnd
        }

        let completed = workoutsThisWeek.count
        let target = goal.targetStrengthDays
        let remaining = target - completed
        let daysLeft = calendar.dateComponents([.day], from: .now, to: weekEnd).day ?? 0

        // Goal in danger: need 2+ workouts but only 1-2 days left
        if remaining >= 2 && daysLeft <= 2 && daysLeft > 0 {
            return WorkoutRecommendation(
                icon: "",
                title: "Weekly goal at risk",
                reason: "Need \(remaining) more workouts in \(daysLeft) day\(daysLeft == 1 ? "" : "s")",
                action: nil
            )
        }

        // Achievable goal: need 1 workout with 1+ days left
        if remaining == 1 && daysLeft >= 1 {
            return WorkoutRecommendation(
                icon: "",
                title: "One workout away!",
                reason: "Complete your weekly goal with one more session",
                action: nil
            )
        }

        return nil
    }

    /// Check if user needs comeback encouragement (3+ days inactive)
    private func checkComebackNeeded() -> WorkoutRecommendation? {
        guard let lastWorkout = workoutStore.completedWorkouts.last else {
            // No workouts ever - encourage first workout
            return WorkoutRecommendation(
                icon: "",
                title: "Start your journey",
                reason: "Your first workout is the hardest - let's do this!",
                action: nil
            )
        }

        let calendar = Calendar.current
        let daysSince = calendar.dateComponents([.day], from: lastWorkout.date, to: .now).day ?? 0

        if daysSince >= 3 && daysSince < 7 {
            return WorkoutRecommendation(
                icon: "",
                title: "Time to get back!",
                reason: "It's been \(daysSince) days - let's rebuild that momentum",
                action: nil
            )
        } else if daysSince >= 7 {
            return WorkoutRecommendation(
                icon: "",
                title: "Welcome back!",
                reason: "Every comeback starts with one workout",
                action: nil
            )
        }

        return nil
    }

    /// Check muscle group balance and suggest underworked muscles
    private func checkMuscleBalance() -> WorkoutRecommendation? {
        let calendar = Calendar.current
        guard let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: .now) else { return nil }

        // Get recent workouts
        let recentWorkouts = workoutStore.completedWorkouts.filter { $0.date >= twoWeeksAgo }
        guard recentWorkouts.count >= 2 else { return nil } // Need at least 2 workouts for pattern

        // Count muscle group frequency
        var muscleGroupCounts: [String: Int] = [:]

        for workout in recentWorkouts {
            for entry in workout.entries {
                for muscle in entry.muscleGroups {
                    muscleGroupCounts[muscle, default: 0] += 1
                }
            }
        }

        // Identify imbalance: upper vs lower body
        let upperMuscles = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms"]
        let lowerMuscles = ["Quads", "Hamstrings", "Glutes", "Calves"]

        let upperCount = upperMuscles.reduce(0) { sum, muscle in
            sum + (muscleGroupCounts[muscle] ?? 0)
        }

        let lowerCount = lowerMuscles.reduce(0) { sum, muscle in
            sum + (muscleGroupCounts[muscle] ?? 0)
        }

        // If upper is 2x lower or more, suggest lower body
        if upperCount > 0 && lowerCount > 0 && upperCount >= lowerCount * 2 {
            return WorkoutRecommendation(
                icon: "",
                title: "Balance your training",
                reason: "You've focused on upper body - time for leg day!",
                action: nil
            )
        }

        // If lower is 2x upper or more, suggest upper body
        if lowerCount > 0 && upperCount > 0 && lowerCount >= upperCount * 2 {
            return WorkoutRecommendation(
                icon: "",
                title: "Balance your training",
                reason: "Your legs are strong - don't skip upper body!",
                action: nil
            )
        }

        return nil
    }

    /// Check if user is close to a PR and suggest chasing it
    private func checkPROpportunity() -> WorkoutRecommendation? {
        guard let lastWorkout = workoutStore.completedWorkouts.last else { return nil }

        // Check recent entries for near-PR performances
        for entry in lastWorkout.entries {
            guard let exercise = ExerciseRepository.shared.exercise(byID: entry.exerciseID) else { continue }

            // Get best historical weight
            guard let bestWeight = workoutStore.bestWeightForExactReps(exercise: exercise, reps: 10) else { continue }

            // Check if any recent set was within 5% of PR
            for set in entry.sets where set.tag == .working {
                let percentOfPR = (set.weight / bestWeight) * 100.0

                if percentOfPR >= 95 && percentOfPR < 100 {
                    return WorkoutRecommendation(
                        icon: "medal.fill",
                        title: "PR opportunity!",
                        reason: "You were close on \(entry.exerciseName) - go for it today!",
                        action: nil
                    )
                }
            }
        }

        return nil
    }

    /// Check plan adherence and remind user if they're drifting
    private func checkPlanAdherence() -> WorkoutRecommendation? {
        guard let todaysPlan = try? plannerStore.plannedWorkout(for: .now) else { return nil }

        // Check if plan exists but hasn't been started
        if todaysPlan.workoutStatus == .scheduled {
            return WorkoutRecommendation(
                icon: "📅",
                title: "Follow today's plan",
                reason: "\(todaysPlan.splitDayName) workout ready • \(todaysPlan.exercises.count) exercises",
                action: nil
            )
        }

        // Check for skipped plans in the last week
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) else { return nil }

        do {
            let recentPlans = try plannerStore.plannedWorkouts(from: weekAgo, to: .now)
            let skippedCount = recentPlans.filter { $0.workoutStatus == .skipped }.count

            if skippedCount >= 2 {
                return WorkoutRecommendation(
                    icon: "📋",
                    title: "Stay on track",
                    reason: "You've skipped \(skippedCount) planned workouts this week",
                    action: nil
                )
            }
        } catch {
            return nil
        }

        return nil
    }
}
