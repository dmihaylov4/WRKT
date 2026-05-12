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
    @State private var selectedCardID: String?

    private let cardHeight: CGFloat = 188

    var body: some View {
        // Only show carousel if cards exist
        if !cards.isEmpty {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedCardID) {
                    ForEach(cards) { card in
                        cardView(for: card)
                            .padding(.horizontal, 16)
                            .padding(.bottom, cards.count > 1 ? 14 : 1)
                            .tag(Optional(card.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: cardHeight)
                .onAppear {
                    syncSelection(with: cards.map(\.id))
                }
                .onChange(of: cards.map(\.id)) { _, ids in
                    syncSelection(with: ids)
                }

                // Custom page indicator
                if cards.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(cards) { card in
                            Capsule()
                                .fill(card.id == selectedCardID ? DS.tint : Color.secondary.opacity(0.3))
                                .frame(width: card.id == selectedCardID ? 24 : 8, height: 3)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedCardID)
                        }
                    }
                    .padding(.bottom, 3)
                }
            }
        }
    }

    private func syncSelection(with ids: [String]) {
        guard !ids.isEmpty else {
            selectedCardID = nil
            return
        }

        if let selectedCardID, ids.contains(selectedCardID) {
            return
        }

        selectedCardID = ids[0]
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
        daysRemaining: 3,
        weekEnded: false,
        planAdherence: nil
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
        daysRemaining: 2,
        weekEnded: false,
        planAdherence: nil
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
