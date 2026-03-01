//
//  WinScreenCoordinator.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// WinScreenCoordinator.swift
import SwiftUI
import Combine
import OSLog

@MainActor
final class WinScreenCoordinator: ObservableObject {
    static let shared = WinScreenCoordinator()

    @Published var summary: RewardSummary? = nil
    @Published var currentWorkout: CompletedWorkout? = nil
    private var queue: [RewardSummary] = []
    private var workoutQueue: [CompletedWorkout?] = []
    private let incoming = PassthroughSubject<RewardSummary, Never>()
    private var bag = Set<AnyCancellable>()

    private init() {
        // Batch everything that arrives within 0.4s into one array, then merge.
        incoming
            .collect(.byTime(DispatchQueue.main, .milliseconds(400)))
            .sink { [weak self] batch in
                guard let self, !batch.isEmpty else { return }

                for (idx, summary) in batch.enumerated() {
                    AppLogger.debug("Summary[\(idx)]: \(summary.xpLineItems.count) line items, \(summary.xp) total XP", category: AppLogger.rewards)
                    for item in summary.xpLineItems {
                        AppLogger.debug("  - \(item.source) +\(item.xp)", category: AppLogger.rewards)
                    }
                }
                // Safely merge all summaries, using first as the starting point
                guard let firstSummary = batch.first else {
                    AppLogger.warning("Unexpected: batch is empty after guard check", category: AppLogger.rewards)
                    return
                }
                let merged = batch.dropFirst().reduce(firstSummary) { $0.merged(with: $1) }
                AppLogger.debug("Merged result: \(merged.xpLineItems.count) line items, \(merged.xp) total XP", category: AppLogger.rewards)
                for item in merged.xpLineItems {
                    AppLogger.debug("  - \(item.source) +\(item.xp)", category: AppLogger.rewards)
                }
                self.enqueueMerged(merged)
            }
            .store(in: &bag)
    }

    /// Call this from AppShell when you receive `rewardsDidSummarize`
    func enqueue(_ s: RewardSummary) {
        incoming.send(s)
    }

    private func enqueueMerged(_ s: RewardSummary) {
        guard s.shouldPresent else { return }

        // Apply lucky bonus check (12% chance of bonus XP)
        let finalSummary = s.withLuckyBonusCheck()

        if finalSummary.gotLuckyBonus {
            AppLogger.info("LUCKY BONUS! \(finalSummary.bonusMultiplier)x multiplier applied!", category: AppLogger.rewards)
        }

        if summary == nil {
            summary = finalSummary
        } else if queue.last != finalSummary {
            queue.append(finalSummary)
        }
    }

    /// Store the completed workout to enable social sharing
    func setCompletedWorkout(_ workout: CompletedWorkout?) {
        if summary == nil {
            currentWorkout = workout
        } else {
            workoutQueue.append(workout)
        }
    }

    func dismissCurrent() {
        summary = queue.isEmpty ? nil : queue.removeFirst()
        currentWorkout = workoutQueue.isEmpty ? nil : workoutQueue.removeFirst()
    }
}
