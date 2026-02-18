//
//  SmartCardCarousel.swift
//  WRKT
//
//  Swipeable card carousel showing ONE card at a time
//

import SwiftUI

struct SmartCardCarousel: View {
    let cards: [HomeCardType]
    var onCardTap: ((HomeCardType) -> Void)? = nil
    var onWorkoutTap: ((CompletedWorkout) -> Void)? = nil  // NEW: For RecentActivityCard
    var onCardioTap: ((Run) -> Void)? = nil  // NEW: For RecentActivityCard
    @State private var selectedIndex: Int = 0

    var body: some View {
        // Only show carousel if cards exist
        if !cards.isEmpty {
            VStack(spacing: 0) {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        cardView(for: card)
                            .padding(.horizontal, 16)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 180)

                // Custom page indicator
                if cards.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<cards.count, id: \.self) { index in
                            Circle()
                                .fill(index == selectedIndex ? DS.tint : Color.secondary.opacity(0.3))
                                .frame(width: index == selectedIndex ? 8 : 6, height: index == selectedIndex ? 8 : 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedIndex)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func cardView(for card: HomeCardType) -> some View {
        // RecentActivityCard has its own internal tap handlers, so don't add arrow or whole-card tap
        let shouldAddArrowAndTap: Bool = {
            if case .recentActivity = card {
                return false
            }
            return onCardTap != nil
        }()

        if shouldAddArrowAndTap, let handler = onCardTap {
            cardContent(for: card)
                .overlay(alignment: .topLeading) {
                    // Visual indicator that card is tappable
                    Image(systemName: "arrow.up.left")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.Palette.marone)
                        .padding(6)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.light()
                    handler(card)
                }
        } else {
            cardContent(for: card)
        }
    }

    @ViewBuilder
    private func cardContent(for card: HomeCardType) -> some View {
        switch card {
        case .lastWorkout(let workout):
            LastWorkoutCard(workout: workout)

        case .friendActivity(let summary):
            FriendActivityCard(summary: summary)

        case .lastCardio(let run):
            LastCardioCard(run: run)

        case .recentActivity(let summary):
            RecentActivityCard(
                summary: summary,
                onWorkoutTap: onWorkoutTap,
                onCardioTap: onCardioTap
            )

        case .weeklyProgress(let progress):
            WeeklyProgressCard(progress: progress)

        case .activeCompetition(let competition):
            ActiveCompetitionCard(competition: competition)

        case .recentPR(let pr):
            RecentPRCard(pr: pr)

        case .recommendation(let recommendation):
            RecommendationCard(recommendation: recommendation)

        case .comparativeStats(let stats):
            ComparativeStatsCard(stats: stats)
        }
    }
}

// MARK: - Preview

#Preview("Multiple Cards") {
    let mockWorkout = CompletedWorkout(
        date: Date().addingTimeInterval(-86400), // Yesterday
        entries: [
            WorkoutEntry(
                exerciseID: "bench-press",
                exerciseName: "Bench Press",
                muscleGroups: ["Chest"],
                sets: [
                    SetInput(reps: 10, weight: 100, tag: .working, autoWeight: false, isCompleted: true)
                ]
            )
        ]
    )

    let mockProgress = WeeklyProgressData(
        completedDays: 2,
        targetDays: 4,
        percentage: 50,
        daysRemaining: 3
    )

    let mockPR = PRSummary(
        exerciseName: "Squat",
        weight: 225,
        reps: 5,
        date: Date().addingTimeInterval(-172800) // 2 days ago
    )

    return VStack {
        SmartCardCarousel(cards: [
            .lastWorkout(mockWorkout),
            .weeklyProgress(mockProgress),
            .recentPR(mockPR)
        ])
        Spacer()
    }
    .background(Color.black)
}

#Preview("Single Card") {
    let mockProgress = WeeklyProgressData(
        completedDays: 3,
        targetDays: 4,
        percentage: 75,
        daysRemaining: 2
    )

    return VStack {
        SmartCardCarousel(cards: [
            .weeklyProgress(mockProgress)
        ])
        Spacer()
    }
    .background(Color.black)
}

#Preview("Empty State") {
    VStack {
        SmartCardCarousel(cards: [])
        Text("No cards to show")
            .foregroundStyle(.secondary)
        Spacer()
    }
    .background(Color.black)
}
