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
        // Batch reward events from the same user action into one summary.
        // Keep this short so PR workouts do not feel delayed after the finish tap.
        incoming
            .collect(.byTime(DispatchQueue.main, .milliseconds(150)))
            .sink { [weak self] batch in
                guard let self, !batch.isEmpty else { return }
                guard let firstSummary = batch.first else {
                    AppLogger.warning("Unexpected: batch is empty after guard check", category: AppLogger.rewards)
                    return
                }
                let merged = batch.dropFirst().reduce(firstSummary) { $0.merged(with: $1) }
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

        if var current = summary, currentWorkout != nil {
            current = current.merged(with: finalSummary)
            summary = current
        } else if summary == nil {
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
