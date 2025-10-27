//
//  WinScreenCoordinator.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// WinScreenCoordinator.swift
import SwiftUI
import Combine

final class WinScreenCoordinator: ObservableObject {
    static let shared = WinScreenCoordinator()

    @Published var summary: RewardSummary? = nil
    private var queue: [RewardSummary] = []
    private let incoming = PassthroughSubject<RewardSummary, Never>()
    private var bag = Set<AnyCancellable>()

    private init() {
        // Batch everything that arrives within 0.4s into one array, then merge.
        incoming
            .collect(.byTime(DispatchQueue.main, .milliseconds(400)))
            .sink { [weak self] batch in
                guard let self, !batch.isEmpty else { return }
                print("🎉 WinScreenCoordinator: Merging \(batch.count) summaries")
                for (idx, summary) in batch.enumerated() {
                    print("  Summary[\(idx)]: \(summary.xpLineItems.count) line items, \(summary.xp) total XP")
                    for item in summary.xpLineItems {
                        print("    - \(item.source) +\(item.xp)")
                    }
                }
                // Fix: Use dropFirst() to avoid merging batch[0] with itself
                let merged = batch.dropFirst().reduce(batch[0]) { $0.merged(with: $1) }
                print("  Merged result: \(merged.xpLineItems.count) line items, \(merged.xp) total XP")
                for item in merged.xpLineItems {
                    print("    - \(item.source) +\(item.xp)")
                }
                self.enqueueMerged(merged)
            }
            .store(in: &bag)
    }

    /// Call this from AppShell when you receive `rewardsDidSummarize`
    @MainActor func enqueue(_ s: RewardSummary) {
        incoming.send(s)
    }

    @MainActor private func enqueueMerged(_ s: RewardSummary) {
        guard s.shouldPresent else { return }
        if summary == nil {
            summary = s
        } else if queue.last != s {
            queue.append(s)
        }
    }

    @MainActor func dismissCurrent() {
        summary = queue.isEmpty ? nil : queue.removeFirst()
    }
}
