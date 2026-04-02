// Features/Rewards/Services/BarbellProgressService.swift
import Foundation
import SwiftData
import UIKit
import AVFoundation
import Supabase

@MainActor
final class BarbellProgressService {
    static let shared = BarbellProgressService()

    private var context: ModelContext?
    private var clinkPlayer: AVAudioPlayer?

    private(set) var needsWelcomeScreen = false

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

    enum RackError: Error { case barIsFull, notConfigured }

    /// Racks a plate into the next available slot (0-3).
    ///
    /// Bilateral rendering contract: `rackPosition` stores a slot index 0-3 only.
    /// The scene builder is responsible for rendering every racked plate on BOTH sides of the
    /// bar simultaneously. There is no separate right-side position: one EarnedPlate row = one
    /// visual pair. Positions 4-7 are reserved and unused.
    func rackPlate(_ plate: EarnedPlate) throws {
        guard let context else { throw RackError.notConfigured }

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
        let tierID = plate.tierID
        let weightKg = plate.weightKg
        let engravingText = plate.engravingText
        let rackPosition = nextSlot
        Task.detached { [weak self] in
            guard let self else { return }
            await self.syncRackedPlateToSupabase(
                tierID: tierID,
                weightKg: weightKg,
                engravingText: engravingText,
                rackPosition: rackPosition
            )
        }
    }

    func unrackPlate(_ plate: EarnedPlate) {
        guard let context else { return }
        let pos = plate.rackPosition
        plate.isRacked = false
        plate.rackPosition = nil
        try? context.save()
        Task.detached { [weak self, pos] in
            guard let self, let pos else { return }
            await self.deleteRackedPlateFromSupabase(rackPosition: pos)
        }
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

    // MARK: - Supabase sync

    func rackedPlatesForFriend(userID: UUID) async throws -> [EarnedPlateInfo] {
        let client = SupabaseClientWrapper.shared.client
        let rows: [RackedPlateRow] = try await client
            .from("barbell_racked_plates")
            .select("tier_id, weight_kg, engraving_text")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        return rows.map { row in
            EarnedPlateInfo(
                tierID: row.tierID,
                weightKg: row.weightKg,
                engravingText: row.engravingText,
                earnedByEvent: ""
            )
        }
    }

    private func syncRackedPlateToSupabase(
        tierID: Int,
        weightKg: Double,
        engravingText: String,
        rackPosition: Int
    ) async {
        guard let userID = SupabaseAuthService.shared.currentUser?.id else { return }
        let client = SupabaseClientWrapper.shared.client

        struct RackedPlateUpsert: Encodable {
            let userID: String
            let tierID: Int
            let weightKg: Double
            let engravingText: String
            let rackPosition: Int
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case userID = "user_id"
                case tierID = "tier_id"
                case weightKg = "weight_kg"
                case engravingText = "engraving_text"
                case rackPosition = "rack_position"
                case updatedAt = "updated_at"
            }
        }

        let row = RackedPlateUpsert(
            userID: userID.uuidString,
            tierID: tierID,
            weightKg: weightKg,
            engravingText: engravingText,
            rackPosition: rackPosition,
            updatedAt: ISO8601DateFormatter().string(from: .now)
        )
        do {
            try await client.from("barbell_racked_plates").upsert(row).execute()
        } catch {
            AppLogger.error("Failed to sync racked plate to Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func deleteRackedPlateFromSupabase(rackPosition: Int) async {
        guard let userID = SupabaseAuthService.shared.currentUser?.id else { return }
        let client = SupabaseClientWrapper.shared.client
        do {
            try await client
                .from("barbell_racked_plates")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("rack_position", value: rackPosition)
                .execute()
        } catch {
            AppLogger.error("Failed to delete racked plate from Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    // MARK: - Backfill for existing users

    func runBackfillIfNeeded(completedWorkouts: [CompletedWorkout]) {
        guard let context else { return }
        let config = fetchOrCreateConfig(context: context)
        guard !config.backfillCompletedV1 else { return }

        // Mark complete and save BEFORE inserting any plates.
        // Crash-safe: if the app is killed mid-loop the flag is already
        // written, so the next launch skips re-running and avoids duplicate plates.
        // Trade-off: a crash mid-backfill leaves a partial plate collection, which is
        // preferable to duplicates that require a manual reset.
        config.backfillCompletedV1 = true
        try? context.save()

        // Sort chronologically; skip cardio workouts (same rule as live evaluation)
        let sorted = completedWorkouts.sorted { $0.date < $1.date }

        for workout in sorted where !workout.isCardioWorkout {
            config.totalStrengthWorkouts += 1
            let existingFD = FetchDescriptor<EarnedPlate>()
            let existing = (try? context.fetch(existingFD)) ?? []
            let existingEvents = existing.map(\.earnedByEvent)
            let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: existingEvents)
            for info in plates {
                let plate = EarnedPlate(
                    tierID: info.tierID, weightKg: info.weightKg,
                    engravingText: info.engravingText, earnedAt: workout.date,
                    earnedByEvent: info.earnedByEvent
                )
                context.insert(plate)
            }
        }

        try? context.save()
        let hasStrengthWorkouts = sorted.contains { !$0.isCardioWorkout }
        if hasStrengthWorkouts {
            needsWelcomeScreen = true
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

// MARK: - Private helpers

private struct RackedPlateRow: Decodable {
    let tierID: Int
    let weightKg: Double
    let engravingText: String

    enum CodingKeys: String, CodingKey {
        case tierID = "tier_id"
        case weightKg = "weight_kg"
        case engravingText = "engraving_text"
    }
}
