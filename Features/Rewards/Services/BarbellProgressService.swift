// Features/Rewards/Services/BarbellProgressService.swift
import Foundation
import SwiftData
import UIKit
import AVFoundation

@MainActor
final class BarbellProgressService {
    static let shared = BarbellProgressService()

    private var context: ModelContext?
    private var clinkPlayer: AVAudioPlayer?

    private init() {}

    // MARK: - Configuration

    func configure(context: ModelContext) {
        self.context = context
        ensureBarbellConfig()
        ensureStarterPlates()
        preloadClinkSound()   // must be called on MainActor, after init completes
    }

    // MARK: - Singleton fetch/create

    func fetchOrCreateConfig(context: ModelContext) -> BarbellConfig {
        let fd = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
        if let existing = try? context.fetch(fd).first { return existing }
        let config = BarbellConfig()
        context.insert(config)
        try? context.save()
        return config
    }

    private func ensureBarbellConfig() {
        guard let context else { return }
        _ = fetchOrCreateConfig(context: context)
    }

    // MARK: - Starter plates

    private func ensureStarterPlates() {
        guard let context else { return }
        let fd = FetchDescriptor<EarnedPlate>(predicate: #Predicate { $0.earnedByEvent == "starter" })
        let existing = (try? context.fetch(fd)) ?? []
        guard existing.isEmpty else { return }

        // One starter plate at the outermost slot (position 3).
        // Bilateral rendering: the scene mirrors every racked plate to both sides,
        // so one plate object = a pair visible on both sides of the bar.
        let starter = EarnedPlate.makeStarter(position: 3)
        context.insert(starter)
        try? context.save()
    }

    // MARK: - Rack / Unrack

    enum RackError: Error { case barIsFull }

    /// Racks a plate into the next available slot (0-3).
    ///
    /// Bilateral rendering contract: `rackPosition` stores a slot index 0-3 only.
    /// The scene builder is responsible for rendering every racked plate on BOTH sides of the
    /// bar simultaneously. There is no separate right-side position: one EarnedPlate row = one
    /// visual pair. Positions 4-7 are reserved and unused.
    func rackPlate(_ plate: EarnedPlate) throws {
        guard let context else { return }

        let validPositions = [0, 1, 2, 3]   // innermost to outermost
        let fd = FetchDescriptor<EarnedPlate>(predicate: #Predicate { $0.isRacked == true })
        let racked = (try? context.fetch(fd)) ?? []
        let occupied = racked.compactMap(\.rackPosition).filter { validPositions.contains($0) }

        guard occupied.count < 4 else { throw RackError.barIsFull }

        let nextSlot = validPositions.filter { !occupied.contains($0) }.min()!
        plate.isRacked = true
        plate.rackPosition = nextSlot
        try? context.save()
        playClinkHaptic()
        queueSupabaseSync()
    }

    func unrackPlate(_ plate: EarnedPlate) {
        guard let context else { return }
        plate.isRacked = false
        plate.rackPosition = nil
        try? context.save()
        queueSupabaseSync()
    }

    // MARK: - Haptic + Sound

    func playClinkHaptic() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        clinkPlayer?.stop()
        clinkPlayer?.currentTime = 0
        clinkPlayer?.play()
    }

    private func preloadClinkSound() {
        guard let url = Bundle.main.url(forResource: "plate_clink", withExtension: "caf") else { return }
        clinkPlayer = try? AVAudioPlayer(contentsOf: url)
        clinkPlayer?.prepareToPlay()
    }

    // MARK: - Supabase sync (stub, wired in Phase 4)

    private func queueSupabaseSync() {
        guard let context else { return }
        let fd = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
        if let config = try? context.fetch(fd).first {
            config.needsSupabaseSync = true
            try? context.save()
        }
    }

    // MARK: - RewardsEngine reset hook

    func resetAll() {
        guard let context else { return }
        let plateFetch = FetchDescriptor<EarnedPlate>()
        if let plates = try? context.fetch(plateFetch) {
            for p in plates { context.delete(p) }
        }
        let configFetch = FetchDescriptor<BarbellConfig>()
        if let configs = try? context.fetch(configFetch) {
            for c in configs { context.delete(c) }
        }
        try? context.save()
        ensureBarbellConfig()
        ensureStarterPlates()
    }
}
