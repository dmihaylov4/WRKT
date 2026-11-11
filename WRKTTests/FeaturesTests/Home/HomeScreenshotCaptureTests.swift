import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
struct HomeScreenshotCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HOME"] == "1"))
    func captureHomeComponents() async throws {
        // Opt-in preparation uses only the dedicated screenshot simulator's data.
        if ProcessInfo.processInfo.environment["VOLIA_HOME_PREPARE_PROGRAM"] == "1" {
            let planner = AppDependencies.shared.plannerStore
            try await Task.sleep(for: .milliseconds(500))
            try planner.createSplit(name: "Train shape capture", planBlocks: [
                PlanBlock(dayName: "Upper Body", exercises: [], isRestDay: false)
            ])
            #expect(try planner.plannedWorkout(for: .now) != nil)
        }

        let mode = DS.Redesign.roundedShapesEnabled ? "rounded" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-03/\(mode)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workout = CompletedWorkout(date: .now, entries: [
            WorkoutEntry(exerciseID: "bench-press", exerciseName: "Bench Press", muscleGroups: ["Chest"],
                         sets: [SetInput(reps: 8, weight: 60, tag: .working, autoWeight: false, isCompleted: true)])
        ])
        let run = Run(distanceKm: 5, durationSec: 1800, avgHeartRate: 145, calories: 320, workoutType: "Running")
        let friend = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let friendActivity = FriendActivitySummary(activities: [
            FriendActivitySummary.FriendWorkoutActivity(id: friend, friendId: friend, friendName: "John",
                friendUsername: "john_doe", friendAvatarUrl: nil, workoutName: "Leg Day", duration: 45, completedAt: .now)
        ], userWorkedOutToday: false)
        let cards: [HomeCardType] = [
            .friendActivity(friendActivity),
            .recentPR(PRSummary(exerciseName: "Squat", weight: 100, reps: 5, date: .now)),
            .recentActivity(RecentActivitySummary(lastWorkout: workout, lastCardio: run)),
            .lastWorkout(workout),
            .lastCardio(run),
            .recommendation(WorkoutRecommendation(icon: "", title: "One workout away!",
                reason: "Complete your weekly goal with one more session",
                action: .init(label: "Start Workout", handler: {}))),
            .weeklyProgress(WeeklyProgressData(completedDays: 2, targetDays: 4, percentage: 50,
                daysRemaining: 3, weekEnded: false,
                planAdherence: PlanAdherence(plannedSessions: 4, completedOnPlan: 2, missedSessions: 0))),
            .activeCompetition(CompetitionSummary(name: "Battle vs John", type: .battle,
                status: "You're ahead by 500 lbs", daysLeft: 3)),
            .comparativeStats(ComparativeStats(userWorkouts: 5, friendsAverage: 2.3, friendCount: 8, weekRange: "Nov 9-15"))
        ]
        for card in cards {
            try save(cardContent(card).frame(height: 174).padding(16),
                     to: root.appendingPathComponent("fixture-card-\(card.id).png"))
        }
        let start = Date.now.addingTimeInterval(-900)
        let states: [(String, HeroButtonContent)] = [
            ("no-program", HeroButtonContent(icon: "dumbbell.fill", mainText: "Start Workout",
                secondaryText: "Let's get stronger today", hasPlan: false)),
            ("program", HeroButtonContent(icon: "calendar.badge.checkmark", mainText: "Start Today's Planned Workout",
                secondaryText: "Upper Body", hasPlan: true)),
            ("active", HeroButtonContent(icon: "dumbbell.fill", mainText: "Live Workout", secondaryText: "", hasPlan: false,
                workoutState: .activeWorkout(exercises: 1, completedSets: 1, duration: 900, startDate: start))),
            ("rest", HeroButtonContent(icon: "timer", mainText: "Live Workout", secondaryText: "", hasPlan: false,
                workoutState: .activeWorkoutWithRest(exercises: 1, completedSets: 1, duration: 900,
                    startDate: start, restTimeRemaining: 75, restExerciseName: "Bench Press")))
        ]
        for (name, content) in states {
            try save(
                VStack(spacing: 0) {
                    HomeHeaderView(greeting: "Good evening, there").padding(.top, 8)
                    HeroStartWorkoutButton(content: content, onTap: {}).padding(.top, 1)
                    UnifiedWeeklyStatsCard(strengthCompleted: 2, strengthTarget: 2,
                        cardioMinutes: 150, cardioTarget: 150, daysRemaining: 3,
                        planAdherence: PlanAdherence(plannedSessions: 2, completedOnPlan: 2, missedSessions: 0))
                        .padding(.horizontal, 16).padding(.top, 8)
                    Spacer(minLength: 0)
                }, to: root.appendingPathComponent("fixture-train-\(name).png")
            )
        }
    }

    @ViewBuilder
    private func cardContent(_ card: HomeCardType) -> some View {
        switch card {
        case .friendActivity(let summary): FriendActivityCard(summary: summary)
        case .recentPR(let pr): RecentPRCard(pr: pr)
        case .recentActivity(let summary): RecentActivityCard(summary: summary, onWorkoutTap: { _ in }, onCardioTap: { _ in })
        case .lastWorkout(let workout): LastWorkoutCard(workout: workout)
        case .lastCardio(let run): LastCardioCard(run: run)
        case .recommendation(let recommendation): RecommendationCard(recommendation: recommendation)
        case .weeklyProgress(let progress): WeeklyProgressCard(progress: progress)
        case .activeCompetition(let competition): ActiveCompetitionCard(competition: competition)
        case .comparativeStats(let stats): ComparativeStatsCard(stats: stats)
        }
    }

    private func save<V: View>(_ content: V, to url: URL) throws {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark)
            .foregroundStyle(.white).frame(width: 402, height: 874, alignment: .topLeading).background(Color.black))
        renderer.scale = 3
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: url)
    }
}
