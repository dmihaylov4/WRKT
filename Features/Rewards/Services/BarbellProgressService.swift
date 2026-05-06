// Features/Rewards/Services/BarbellProgressService.swift
import Foundation
import Observation
import SwiftData
import UIKit
import AVFoundation
import Supabase

enum BarbellRemoteSyncState: Equatable {
    case available
    case syncUnavailable
}

enum BarbellSyncError: Error, Equatable {
    case notConfigured
    case notAuthenticated
    case suspiciousEmptyRemote(localCount: Int)
}

enum BarbellShowcaseLoadError: Error, Equatable {
    case cancelled
}

@Observable @MainActor
final class BarbellProgressService {
    static let shared = BarbellProgressService()

    private var context: ModelContext?
    private var clinkPlayer: AVAudioPlayer?
    private var remoteSyncTask: Task<Void, Never>?

    var needsWelcomeScreen = false
    var remoteSyncState: BarbellRemoteSyncState = .available

    private init() {}

    // MARK: - Configuration

    func configure(context: ModelContext) {
        self.context = context
        ensureBarbellConfig()
        ensureStarterPlates()
        updateDisplayLoadoutFromRackedPlates(context: context)
        preloadClinkSound()   // must be called on MainActor, after init completes
        Task { @MainActor in
            try? await pullEarnedPlatesFromSupabase()
            try? await pullBarbellCosmeticUnlocksFromSupabase()
        }
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

    private func updateDisplayLoadoutFromRackedPlates(context: ModelContext) {
        let plateDescriptor = FetchDescriptor<EarnedPlate>()
        let plates = (try? context.fetch(plateDescriptor)) ?? []
        let rackedIDs = plates
            .filter(\.isRacked)
            .sorted {
                let leftPosition = $0.rackPosition ?? Int.max
                let rightPosition = $1.rackPosition ?? Int.max
                if leftPosition != rightPosition { return leftPosition < rightPosition }
                return $0.earnedAt > $1.earnedAt
            }
            .map(\.id)

        let wallIDs = plates
            .filter { !$0.isRacked && $0.earnedByEvent != "starter" }
            .sorted { $0.earnedAt > $1.earnedAt }
            .map(\.id)

        let earnedIDs = Set(plates.map(\.id))
        let loadout = DisplayLoadout(onBar: rackedIDs, onWall: wallIDs)
            .sanitized(earnedPlateIDs: earnedIDs, maximumBarPlateCount: 4)

        let config = fetchOrCreateConfig(context: context)
        guard config.displayLoadout != loadout else { return }

        config.setDisplayLoadout(loadout)
        config.needsSupabaseSync = true
        do {
            try context.save()
            BarbellCustomizationService.shared.enqueueSyncCurrentSettingsToSupabase()
        } catch {
            context.rollback()
        }
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

    enum RackError: Error {
        case barIsFull
        case notConfigured
        case plateAlreadyRacked
        case plateNotRacked
        case invalidSlot
        case slotOccupied
        case staleReplacement
    }

    /// Racks a plate into the next available slot (0-3), or into `requestedSlot` when callers
    /// (the WinScreen animation) need the persisted slot to match the slot they animated to.
    ///
    /// Bilateral rendering contract: `rackPosition` stores a slot index 0-3 only.
    /// The scene builder is responsible for rendering every racked plate on BOTH sides of the
    /// bar simultaneously. There is no separate right-side position: one EarnedPlate row = one
    /// visual pair. Positions 4-7 are reserved and unused.
    func rackPlate(_ plate: EarnedPlate, at requestedSlot: Int? = nil) throws {
        try addToBar(plate: plate, replacing: nil, requestedSlot: requestedSlot)
    }

    func addToBar(plate: EarnedPlate, replacing existing: EarnedPlate?) throws {
        try addToBar(plate: plate, replacing: existing, requestedSlot: nil)
    }

    private func addToBar(plate: EarnedPlate, replacing existing: EarnedPlate?, requestedSlot: Int?) throws {
        guard let context else { throw RackError.notConfigured }
        guard !plate.isRacked else { throw RackError.plateAlreadyRacked }

        let validPositions = [0, 1, 2, 3]   // innermost to outermost
        let fd = FetchDescriptor<EarnedPlate>(predicate: #Predicate { $0.isRacked == true })
        let racked = (try? context.fetch(fd)) ?? []
        let occupied = racked.compactMap(\.rackPosition).filter { validPositions.contains($0) }

        let nextSlot: Int
        if let existing {
            guard existing.isRacked, let existingSlot = existing.rackPosition else {
                throw RackError.staleReplacement
            }
            guard validPositions.contains(existingSlot) else { throw RackError.invalidSlot }
            nextSlot = existingSlot
        } else if let requestedSlot {
            guard validPositions.contains(requestedSlot), !occupied.contains(requestedSlot) else {
                throw RackError.barIsFull
            }
            nextSlot = requestedSlot
        } else {
            guard occupied.count < 4 else { throw RackError.barIsFull }
            nextSlot = validPositions.filter { !occupied.contains($0) }.min()!
        }
        if existing == nil, occupied.contains(nextSlot) {
            throw RackError.slotOccupied
        }

        existing?.isRacked = false
        existing?.rackPosition = nil
        plate.isRacked = true
        plate.rackPosition = nextSlot
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        updateDisplayLoadoutFromRackedPlates(context: context)
        playClinkHaptic()
        let plateSnapshot = RackedPlateMutation(
            earnedByEvent: plate.earnedByEvent,
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            earnedAt: plate.earnedAt,
            sourceWorkoutID: plate.sourceWorkoutID,
            isRacked: true,
            rackPosition: nextSlot,
            liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID),
            currentTier: plate.currentTier,
            workoutsUsedCount: plate.workoutsUsedCount,
            prCount: plate.prCount,
            chalkUseCount: plate.chalkUseCount,
            gripWearCount: plate.gripWearCount,
            pressUseCount: plate.pressUseCount,
            firstEarnedAt: plate.effectiveFirstEarnedAt,
            lastUsedAt: plate.lastUsedAt
        )
        let displacedSnapshot = existing.map {
            RackedPlateMutation(
                earnedByEvent: $0.earnedByEvent,
                tierID: $0.tierID,
                weightKg: $0.weightKg,
                engravingText: $0.engravingText,
                earnedAt: $0.earnedAt,
                sourceWorkoutID: $0.sourceWorkoutID,
                isRacked: false,
                rackPosition: nil,
                liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID($0.liftTypeID),
                currentTier: $0.currentTier,
                workoutsUsedCount: $0.workoutsUsedCount,
                prCount: $0.prCount,
                chalkUseCount: $0.chalkUseCount,
                gripWearCount: $0.gripWearCount,
                pressUseCount: $0.pressUseCount,
                firstEarnedAt: $0.effectiveFirstEarnedAt,
                lastUsedAt: $0.lastUsedAt
            )
        }
        enqueueRemoteSync { [weak self] userID in
            guard let self else { return }
            await self.syncEarnedPlateMutationToSupabase(plateSnapshot, userID: userID)
            if let displacedSnapshot {
                await self.syncEarnedPlateMutationToSupabase(displacedSnapshot, userID: userID)
            }
            await self.syncRackedPlateToSupabase(
                tierID: plateSnapshot.tierID,
                weightKg: plateSnapshot.weightKg,
                engravingText: plateSnapshot.engravingText,
                rackPosition: nextSlot,
                userID: userID
            )
        }
    }

    func unrackPlate(_ plate: EarnedPlate) {
        removeFromBar(plate: plate)
    }

    func removeFromBar(plate: EarnedPlate) {
        guard let context else { return }
        let pos = plate.rackPosition
        plate.isRacked = false
        plate.rackPosition = nil
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        updateDisplayLoadoutFromRackedPlates(context: context)
        let snapshot = RackedPlateMutation(
            earnedByEvent: plate.earnedByEvent,
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            earnedAt: plate.earnedAt,
            sourceWorkoutID: plate.sourceWorkoutID,
            isRacked: false,
            rackPosition: nil,
            liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID),
            currentTier: plate.currentTier,
            workoutsUsedCount: plate.workoutsUsedCount,
            prCount: plate.prCount,
            chalkUseCount: plate.chalkUseCount,
            gripWearCount: plate.gripWearCount,
            pressUseCount: plate.pressUseCount,
            firstEarnedAt: plate.effectiveFirstEarnedAt,
            lastUsedAt: plate.lastUsedAt
        )
        enqueueRemoteSync { [weak self, pos] userID in
            guard let self else { return }
            await self.syncEarnedPlateMutationToSupabase(snapshot, userID: userID)
            if let pos {
                await self.deleteRackedPlateFromSupabase(rackPosition: pos, userID: userID)
            }
        }
    }

    func moveOnBar(plate: EarnedPlate, toSlot newSlot: Int) throws {
        guard let context else { throw RackError.notConfigured }
        guard plate.isRacked, plate.rackPosition != nil else { throw RackError.plateNotRacked }
        guard (0...3).contains(newSlot) else { throw RackError.invalidSlot }

        let fd = FetchDescriptor<EarnedPlate>(predicate: #Predicate { $0.isRacked == true })
        let racked = (try? context.fetch(fd)) ?? []
        guard !racked.contains(where: { $0.id != plate.id && $0.rackPosition == newSlot }) else {
            throw RackError.slotOccupied
        }

        plate.rackPosition = newSlot
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        updateDisplayLoadoutFromRackedPlates(context: context)

        let snapshot = RackedPlateMutation(
            earnedByEvent: plate.earnedByEvent,
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            earnedAt: plate.earnedAt,
            sourceWorkoutID: plate.sourceWorkoutID,
            isRacked: true,
            rackPosition: newSlot,
            liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID),
            currentTier: plate.currentTier,
            workoutsUsedCount: plate.workoutsUsedCount,
            prCount: plate.prCount,
            chalkUseCount: plate.chalkUseCount,
            gripWearCount: plate.gripWearCount,
            pressUseCount: plate.pressUseCount,
            firstEarnedAt: plate.effectiveFirstEarnedAt,
            lastUsedAt: plate.lastUsedAt
        )
        enqueueRemoteSync { [weak self] userID in
            guard let self else { return }
            await self.syncEarnedPlateMutationToSupabase(snapshot, userID: userID)
        }
    }

    func applyDisplayLoadoutToRackedPlates(_ loadout: DisplayLoadout) {
        guard let context else { return }

        let plates = ((try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? [])
            .filter { $0.earnedByEvent != "starter" }
        let validPlateIDs = Set(plates.map(\.id))
        let sanitizedLoadout = loadout.sanitized(
            earnedPlateIDs: validPlateIDs,
            maximumBarPlateCount: 4
        )
        let onBarPositions = Dictionary(
            uniqueKeysWithValues: sanitizedLoadout.onBar.enumerated().map { ($0.element, $0.offset) }
        )

        var changedSnapshots: [RackedPlateMutation] = []
        for plate in plates {
            let nextIsRacked = onBarPositions[plate.id] != nil
            let nextRackPosition = onBarPositions[plate.id]
            guard plate.isRacked != nextIsRacked || plate.rackPosition != nextRackPosition else {
                continue
            }

            plate.isRacked = nextIsRacked
            plate.rackPosition = nextIsRacked ? nextRackPosition : nil
            changedSnapshots.append(RackedPlateMutation(
                earnedByEvent: plate.earnedByEvent,
                tierID: plate.tierID,
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                earnedAt: plate.earnedAt,
                sourceWorkoutID: plate.sourceWorkoutID,
                isRacked: plate.isRacked,
                rackPosition: plate.rackPosition,
                liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID),
                currentTier: plate.currentTier,
                workoutsUsedCount: plate.workoutsUsedCount,
                prCount: plate.prCount,
                chalkUseCount: plate.chalkUseCount,
                gripWearCount: plate.gripWearCount,
                pressUseCount: plate.pressUseCount,
                firstEarnedAt: plate.effectiveFirstEarnedAt,
                lastUsedAt: plate.lastUsedAt
            ))
        }

        guard !changedSnapshots.isEmpty else { return }

        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }

        enqueueRemoteSync { [weak self] userID in
            guard let self else { return }
            for snapshot in changedSnapshots {
                await self.syncEarnedPlateMutationToSupabase(snapshot, userID: userID)
            }
        }
    }

    func syncEarnedPlateAwardsToSupabase(
        _ awards: [EarnedPlateSyncPayload],
        eventPayloads: [BarbellPlateEventSyncPayload] = []
    ) {
        guard !awards.isEmpty || !eventPayloads.isEmpty else { return }
        enqueueRemoteSync { [weak self] userID in
            guard let self else { return }
            for award in awards {
                let mutation = RackedPlateMutation(
                    earnedByEvent: award.earnedByEvent,
                    tierID: award.tierID,
                    weightKg: award.weightKg,
                    engravingText: award.engravingText,
                    earnedAt: award.earnedAt,
                    sourceWorkoutID: award.sourceWorkoutID,
                    isRacked: award.isRacked,
                    rackPosition: award.rackPosition,
                    liftTypeID: award.liftTypeID,
                    currentTier: award.currentTier,
                    workoutsUsedCount: award.workoutsUsedCount,
                    prCount: award.prCount,
                    chalkUseCount: award.chalkUseCount,
                    gripWearCount: award.gripWearCount,
                    pressUseCount: award.pressUseCount,
                    firstEarnedAt: award.firstEarnedAt,
                    lastUsedAt: award.lastUsedAt
                )
                await self.syncEarnedPlateMutationToSupabase(mutation, userID: userID)
            }
            for event in eventPayloads {
                await self.syncPlateEventToSupabase(event, userID: userID)
            }
        }
    }

    func syncBarbellCosmeticUnlocksToSupabase(_ unlocks: [BarbellCosmeticUnlockSyncPayload]) {
        guard !unlocks.isEmpty else { return }
        enqueueRemoteSync { [weak self] userID in
            guard let self else { return }
            for unlock in unlocks {
                await self.syncBarbellCosmeticUnlockToSupabase(unlock, userID: userID)
            }
        }
    }

    func resetConfigInPlaceForUserChange() {
        guard let context else { return }
        let config = fetchOrCreateConfig(context: context)
        config.resetMutableFieldsToDefaults()
        try? context.save()
    }

    func markSuspiciousEmptyRemoteDetected() {
        remoteSyncState = .syncUnavailable
    }

    func cancelAndAwaitRemoteSyncForAuthenticatedUserChange(to newUserID: UUID?) async {
        let task = remoteSyncTask
        remoteSyncTask = nil
        task?.cancel()
        await task?.value
        remoteSyncState = .available
        resetConfigInPlaceForUserChange()
        AppLogger.info(
            "Barbell remote sync queue cancelled for auth user change. nextUser=\(newUserID?.uuidString ?? "none")",
            category: AppLogger.rewards
        )
    }

    // MARK: - Haptic + Sound

    func playClinkHaptic() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        clinkPlayer?.stop()
        clinkPlayer?.currentTime = 0
        clinkPlayer?.play()
    }

    func playCosmeticEquipFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        clinkPlayer?.stop()
        clinkPlayer?.currentTime = 0
        clinkPlayer?.play()
    }

    func playTierUpFeedback() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

    private func enqueueRemoteSync(_ operation: @escaping @MainActor (UUID) async -> Void) {
        guard let userID = SupabaseAuthService.shared.currentUser?.id else { return }
        let previousTask = remoteSyncTask
        remoteSyncTask = Task { @MainActor [weak self, previousTask, userID] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
            await operation(userID)
            guard !Task.isCancelled else { return }
            guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
            self?.remoteSyncState = .available
        }
    }

    func rackedPlatesForFriend(userID: UUID) async throws -> [EarnedPlateInfo] {
        try await friendBarbellShowcase(userID: userID).plates
    }

    func friendBarbellShowcase(userID: UUID) async throws -> BarbellFriendShowcase {
        let client = SupabaseClientWrapper.shared.client

        do {
            let rows: [FriendBarbellShowcaseRemoteRow] = try await client
                .rpc("get_friend_barbell_showcase", params: ["owner_id": userID.uuidString])
                .execute()
                .value

            guard let first = rows.first else { return BarbellFriendShowcase() }
            let plates = rows.compactMap { row -> EarnedPlateInfo? in
                guard let tierID = row.tierID,
                      let weightKg = row.weightKg,
                      let earnedByEvent = row.earnedByEvent else {
                    return nil
                }
                return EarnedPlateInfo(
                    tierID: tierID,
                    weightKg: weightKg,
                    engravingText: row.engravingText ?? "",
                    earnedByEvent: earnedByEvent,
                    liftTypeID: row.liftTypeID
                )
            }

            return BarbellFriendShowcase(
                barSkinID: first.barSkinID ?? BarbellCustomizationDefaults.barSkinID,
                roomThemeID: first.roomThemeID ?? BarbellCustomizationDefaults.roomThemeID,
                rackStyleID: first.rackStyleID ?? BarbellCustomizationDefaults.rackStyleID,
                collarID: first.collarID,
                bannerID: first.bannerID,
                showPlateEngravings: first.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings,
                roomName: first.roomName,
                roomMotto: first.roomMotto,
                plates: plates
            )
        } catch {
            if Self.isCancelledRequestError(error) {
                throw BarbellShowcaseLoadError.cancelled
            }
            AppLogger.error("Failed to load friend barbell showcase via RPC: \(error)", category: AppLogger.rewards)
            throw error
        }
    }

    nonisolated static func isCancelledRequestError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    func pullEarnedPlatesFromSupabase() async throws {
        guard let context else { throw BarbellSyncError.notConfigured }
        guard let userID = SupabaseAuthService.shared.currentUser?.id else {
            throw BarbellSyncError.notAuthenticated
        }

        let client = SupabaseClientWrapper.shared.client
        let rows: [EarnedPlateRemoteRow] = try await client
            .from("earned_plates")
            .select("earned_by_event, tier_id, weight_kg, engraving_text, earned_at, source_workout_id, is_racked, rack_position, updated_at, lift_type_id, current_tier, workouts_used_count, pr_count, chalk_use_count, grip_wear_count, press_use_count, first_earned_at, last_used_at")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        let localPlates = (try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? []
        let localEarnedCount = localPlates.filter { $0.earnedByEvent != "starter" }.count
        if Self.shouldTreatRemoteAsSuspiciousEmpty(remoteCount: rows.count, localEarnedCount: localEarnedCount) {
            remoteSyncState = .syncUnavailable
            throw BarbellSyncError.suspiciousEmptyRemote(localCount: localEarnedCount)
        }

        mergeRemoteEarnedPlateRows(rows, into: localPlates, context: context)
        await pullPlateEventsFromSupabase(userID: userID, context: context)
        updateDisplayLoadoutFromRackedPlates(context: context)
        do {
            try context.save()
            remoteSyncState = .available
        } catch {
            context.rollback()
            throw error
        }
    }

    func pullBarbellCosmeticUnlocksFromSupabase() async throws {
        guard let context else { throw BarbellSyncError.notConfigured }
        guard let userID = SupabaseAuthService.shared.currentUser?.id else {
            throw BarbellSyncError.notAuthenticated
        }

        let client = SupabaseClientWrapper.shared.client
        let rows: [BarbellCosmeticUnlockRemoteRow] = try await client
            .from("barbell_cosmetic_unlocks")
            .select("cosmetic_id, unlocked_at, source, source_workout_id, catalog_version")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        mergeRemoteCosmeticUnlockRows(rows, context: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func mergeRemoteEarnedPlateRows(
        _ rows: [EarnedPlateRemoteRow],
        into localPlates: [EarnedPlate],
        context: ModelContext
    ) {
        var localByEvent: [String: EarnedPlate] = [:]
        for plate in localPlates {
            if let survivor = localByEvent[plate.earnedByEvent] {
                mergeDuplicateLocalPlate(plate, into: survivor)
                context.delete(plate)
                AppLogger.warning(
                    "Merged duplicate local earned plate for event=\(plate.earnedByEvent)",
                    category: AppLogger.rewards
                )
            } else {
                localByEvent[plate.earnedByEvent] = plate
            }
        }

        for row in rows {
            if row.earnedByEvent == "starter" { continue }
            let plate = localByEvent[row.earnedByEvent] ?? EarnedPlate(
                tierID: row.tierID,
                weightKg: row.weightKg,
                engravingText: row.engravingText,
                earnedAt: row.earnedAtDate,
                earnedByEvent: row.earnedByEvent,
                sourceWorkoutID: row.sourceWorkoutID
            )
            if localByEvent[row.earnedByEvent] == nil {
                context.insert(plate)
                localByEvent[row.earnedByEvent] = plate
            }

            if row.tierID < plate.tierID {
                AppLogger.warning(
                    "Ignored remote earned plate tier downgrade for event=\(row.earnedByEvent) local=\(plate.tierID) remote=\(row.tierID)",
                    category: AppLogger.rewards
                )
            }
            plate.tierID = Self.monotonicTier(stored: plate.tierID, recomputed: row.tierID)
            plate.weightKg = row.weightKg
            plate.engravingText = row.engravingText
            plate.earnedAt = row.earnedAtDate
            plate.sourceWorkoutID = row.sourceWorkoutID
            plate.isRacked = row.isRacked
            plate.rackPosition = row.isRacked ? row.rackPosition : nil
            plate.displayOrder = Int(row.earnedAtDate.timeIntervalSince1970)
            plate.liftTypeID = BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID ?? row.liftTypeID)
            mergeProgressionFields(from: row, into: plate)
        }
    }

    private func mergeProgressionFields(from row: EarnedPlateRemoteRow, into plate: EarnedPlate) {
        let remoteTier = row.currentTier
        if remoteTier.rank < plate.currentTier.rank {
            AppLogger.warning(
                "Ignored remote progression tier downgrade for event=\(row.earnedByEvent) local=\(plate.currentTier.rawValue) remote=\(remoteTier.rawValue)",
                category: AppLogger.rewards
            )
        } else {
            plate.currentTier = remoteTier
        }
        plate.workoutsUsedCount = max(plate.workoutsUsedCount, row.workoutsUsedCount ?? 0)
        plate.prCount = max(plate.prCount, row.prCount ?? 0)
        plate.chalkUseCount = max(plate.chalkUseCount, row.chalkUseCount ?? 0)
        plate.gripWearCount = max(plate.gripWearCount, row.gripWearCount ?? 0)
        plate.pressUseCount = max(plate.pressUseCount, row.pressUseCount ?? 0)
        if let remoteFirstEarnedAt = row.firstEarnedAtDate {
            plate.firstEarnedAt = min(plate.effectiveFirstEarnedAt, remoteFirstEarnedAt)
        }
        if let remoteLastUsedAt = row.lastUsedAtDate {
            plate.lastUsedAt = max(plate.lastUsedAt ?? remoteLastUsedAt, remoteLastUsedAt)
        }
    }

    private func mergeDuplicateLocalPlate(_ duplicate: EarnedPlate, into survivor: EarnedPlate) {
        survivor.tierID = Self.monotonicTier(stored: survivor.tierID, recomputed: duplicate.tierID)
        survivor.weightKg = survivor.weightKg > 0 ? survivor.weightKg : duplicate.weightKg
        if survivor.engravingText.isEmpty {
            survivor.engravingText = duplicate.engravingText
        }
        survivor.earnedAt = min(survivor.earnedAt, duplicate.earnedAt)
        survivor.sourceWorkoutID = survivor.sourceWorkoutID ?? duplicate.sourceWorkoutID
        if !survivor.isRacked, duplicate.isRacked {
            survivor.isRacked = true
            survivor.rackPosition = duplicate.rackPosition
        }
        survivor.displayOrder = min(survivor.displayOrder, duplicate.displayOrder)
        survivor.currentTier = survivor.currentTier.rank >= duplicate.currentTier.rank ? survivor.currentTier : duplicate.currentTier
        survivor.workoutsUsedCount = max(survivor.workoutsUsedCount, duplicate.workoutsUsedCount)
        survivor.prCount = max(survivor.prCount, duplicate.prCount)
        survivor.chalkUseCount = max(survivor.chalkUseCount, duplicate.chalkUseCount)
        survivor.gripWearCount = max(survivor.gripWearCount, duplicate.gripWearCount)
        survivor.pressUseCount = max(survivor.pressUseCount, duplicate.pressUseCount)
        survivor.firstEarnedAt = min(survivor.effectiveFirstEarnedAt, duplicate.effectiveFirstEarnedAt)
        if let duplicateLastUsedAt = duplicate.lastUsedAt {
            survivor.lastUsedAt = max(survivor.lastUsedAt ?? duplicateLastUsedAt, duplicateLastUsedAt)
        }
    }

    nonisolated static func shouldTreatRemoteAsSuspiciousEmpty(remoteCount: Int, localEarnedCount: Int) -> Bool {
        remoteCount == 0 && localEarnedCount > 0
    }

    nonisolated static func monotonicTier(stored: Int, recomputed: Int) -> Int {
        max(stored, recomputed)
    }

    private func syncRackedPlateToSupabase(
        tierID: Int,
        weightKg: Double,
        engravingText: String,
        rackPosition: Int,
        userID: UUID
    ) async {
        guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
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
            remoteSyncState = .syncUnavailable
            AppLogger.error("Failed to sync racked plate to Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func deleteRackedPlateFromSupabase(rackPosition: Int, userID: UUID) async {
        guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
        let client = SupabaseClientWrapper.shared.client
        do {
            try await client
                .from("barbell_racked_plates")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("rack_position", value: rackPosition)
                .execute()
        } catch {
            remoteSyncState = .syncUnavailable
            AppLogger.error("Failed to delete racked plate from Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func syncEarnedPlateMutationToSupabase(_ mutation: RackedPlateMutation, userID: UUID) async {
        guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
        let client = SupabaseClientWrapper.shared.client

        let row = EarnedPlateUpsertRow(
            userID: userID.uuidString,
            earnedByEvent: mutation.earnedByEvent,
            tierID: mutation.tierID,
            weightKg: mutation.weightKg,
            engravingText: mutation.engravingText,
            earnedAt: ISO8601DateFormatter().string(from: mutation.earnedAt),
            sourceWorkoutID: mutation.sourceWorkoutID,
            isRacked: mutation.isRacked,
            rackPosition: mutation.rackPosition,
            liftTypeID: mutation.liftTypeID,
            currentTier: mutation.currentTier.rawValue,
            workoutsUsedCount: mutation.workoutsUsedCount,
            prCount: mutation.prCount,
            chalkUseCount: mutation.chalkUseCount,
            gripWearCount: mutation.gripWearCount,
            pressUseCount: mutation.pressUseCount,
            firstEarnedAt: ISO8601DateFormatter().string(from: mutation.firstEarnedAt),
            lastUsedAt: mutation.lastUsedAt.map { ISO8601DateFormatter().string(from: $0) },
            updatedAt: ISO8601DateFormatter().string(from: .now)
        )

        do {
            try await client
                .from("earned_plates")
                .upsert(row, onConflict: "user_id,earned_by_event")
                .execute()
        } catch {
            remoteSyncState = .syncUnavailable
            AppLogger.error("Failed to sync earned plate to Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func syncPlateEventToSupabase(_ event: BarbellPlateEventSyncPayload, userID: UUID) async {
        guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
        let client = SupabaseClientWrapper.shared.client

        let row = BarbellPlateEventUpsertRow(
            userID: userID.uuidString,
            stableKey: event.stableKey,
            earnedByEvent: event.earnedByEvent,
            kind: event.kind.rawValue,
            occurredAt: ISO8601DateFormatter().string(from: event.occurredAt),
            workoutID: event.workoutID,
            tier: event.tier?.rawValue,
            milestoneID: event.milestoneID,
            summary: event.summary,
            isSilent: event.isSilent
        )

        do {
            try await client
                .from("barbell_plate_events")
                .upsert(row, onConflict: "user_id,stable_key")
                .execute()
        } catch {
            remoteSyncState = .syncUnavailable
            AppLogger.error("Failed to sync barbell plate event to Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func syncBarbellCosmeticUnlockToSupabase(_ unlock: BarbellCosmeticUnlockSyncPayload, userID: UUID) async {
        guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
        let client = SupabaseClientWrapper.shared.client

        let row = BarbellCosmeticUnlockUpsertRow(
            userID: userID.uuidString,
            cosmeticID: unlock.cosmeticID,
            unlockedAt: ISO8601DateFormatter().string(from: unlock.unlockedAt),
            source: unlock.source.rawValue,
            sourceWorkoutID: unlock.sourceWorkoutID,
            catalogVersion: unlock.catalogVersion
        )

        do {
            try await client
                .from("barbell_cosmetic_unlocks")
                .upsert(row, onConflict: "user_id,cosmetic_id")
                .execute()
        } catch {
            remoteSyncState = .syncUnavailable
            AppLogger.error("Failed to sync barbell cosmetic unlock to Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func pullPlateEventsFromSupabase(userID: UUID, context: ModelContext) async {
        guard SupabaseAuthService.shared.currentUser?.id == userID else { return }
        let client = SupabaseClientWrapper.shared.client

        do {
            let rows: [BarbellPlateEventRemoteRow] = try await client
                .from("barbell_plate_events")
                .select("stable_key, earned_by_event, kind, occurred_at, workout_id, tier, milestone_id, summary, is_silent")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
            mergeRemotePlateEventRows(rows, context: context)
        } catch {
            AppLogger.error("Failed to pull barbell plate events from Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    private func mergeRemotePlateEventRows(_ rows: [BarbellPlateEventRemoteRow], context: ModelContext) {
        guard !rows.isEmpty else { return }
        let plates = (try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? []
        let plateIDByEarnedEvent = plates.reduce(into: [String: String]()) { result, plate in
            result[plate.earnedByEvent] = result[plate.earnedByEvent] ?? plate.id
        }
        let existingEvents = (try? context.fetch(FetchDescriptor<BarbellPlateEvent>())) ?? []
        var existingKeys = Set(existingEvents.map(\.stableKey))

        for row in rows where !existingKeys.contains(row.stableKey) {
            guard let plateID = plateIDByEarnedEvent[row.earnedByEvent] else { continue }
            context.insert(BarbellPlateEvent(
                stableKey: row.stableKey,
                plateID: plateID,
                kind: row.kind,
                occurredAt: row.occurredAtDate,
                workoutID: row.workoutID,
                tier: row.tier,
                milestoneID: row.milestoneID,
                summary: row.summary,
                isSilent: row.isSilent
            ))
            existingKeys.insert(row.stableKey)
        }
    }

    private func mergeRemoteCosmeticUnlockRows(_ rows: [BarbellCosmeticUnlockRemoteRow], context: ModelContext) {
        guard !rows.isEmpty else { return }
        let existingUnlocks = (try? context.fetch(FetchDescriptor<BarbellCosmeticUnlock>())) ?? []
        var existingByCosmeticID = Dictionary(uniqueKeysWithValues: existingUnlocks.map { ($0.cosmeticID, $0) })

        for row in rows {
            if let existing = existingByCosmeticID[row.cosmeticID] {
                existing.unlockedAt = min(existing.unlockedAt, row.unlockedAtDate)
                existing.sourceRaw = existing.sourceRaw.isEmpty ? row.source.rawValue : existing.sourceRaw
                existing.sourceWorkoutID = existing.sourceWorkoutID ?? row.sourceWorkoutID
                existing.catalogVersion = existing.catalogVersion ?? row.catalogVersion
            } else {
                let unlock = BarbellCosmeticUnlock(
                    cosmeticID: row.cosmeticID,
                    unlockedAt: row.unlockedAtDate,
                    sourceRaw: row.source.rawValue,
                    sourceWorkoutID: row.sourceWorkoutID,
                    catalogVersion: row.catalogVersion
                )
                context.insert(unlock)
                existingByCosmeticID[row.cosmeticID] = unlock
            }
        }
    }

    // MARK: - Backfill for existing users

    func evaluateAndAwardFunctionalHK(run: Run) async {
        guard let context else { return }
        guard run.countsAsStrengthDay, let hkUUID = run.healthKitUUID else { return }

        let uuid = hkUUID.uuidString
        let processedDescriptor = FetchDescriptor<BarbellProcessedHKWorkout>(
            predicate: #Predicate { $0.healthKitUUID == uuid }
        )
        guard (try? context.fetch(processedDescriptor).isEmpty) == true else { return }

        let config = fetchOrCreateConfig(context: context)
        config.totalFunctionalHKWorkouts += 1
        context.insert(BarbellProcessedHKWorkout(healthKitUUID: uuid, processedAt: run.date))

        let existingEvents = ((try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? [])
            .map(\.earnedByEvent)
        let plates = BarbellUnlockRules.evaluateFunctionalHK(
            config: config,
            existingEvents: existingEvents
        )

        var syncPayloads: [EarnedPlateSyncPayload] = []
        for info in plates {
            let plate = EarnedPlate(
                tierID: info.tierID,
                weightKg: info.weightKg,
                engravingText: info.engravingText,
                earnedAt: run.date,
                earnedByEvent: info.earnedByEvent,
                sourceWorkoutID: uuid,
                liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(info.liftTypeID)
            )
            context.insert(plate)
            syncPayloads.append(EarnedPlateSyncPayload(
                info: info,
                earnedAt: run.date,
                sourceWorkoutID: uuid
            ))
        }

        do {
            try context.save()
            if !plates.isEmpty {
                needsWelcomeScreen = true
                syncEarnedPlateAwardsToSupabase(syncPayloads)
            }
        } catch {
            context.rollback()
            AppLogger.error("Failed to award HealthKit functional strength barbell plate: \(error)", category: AppLogger.rewards)
        }
    }

    func backfillFunctionalHKPlatesIfNeeded(runs: [Run]) async {
        let sorted = runs
            .filter { $0.countsAsStrengthDay && $0.healthKitUUID != nil }
            .sorted { $0.date < $1.date }

        for run in sorted {
            await evaluateAndAwardFunctionalHK(run: run)
        }
    }

    func runBackfillIfNeeded(completedWorkouts: [CompletedWorkout]) {
        // Guard before consuming the flag: if the store has not finished loading yet
        // this returns without touching backfillCompletedV1, allowing a retry on next launch.
        guard !completedWorkouts.isEmpty else { return }
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

        // Fetch existing events once before the loop to avoid N full-table SwiftData fetches.
        let existingPlates = (try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? []
        let existingEarnedCount = existingPlates.filter { $0.earnedByEvent != "starter" }.count
        var existingEvents = existingPlates.map(\.earnedByEvent)

        for workout in sorted where !workout.isCardioWorkout {
            config.totalStrengthWorkouts += 1
            let plates = BarbellUnlockRules.evaluate(workout: workout, config: config, existingEvents: existingEvents)
            for info in plates {
                let plate = EarnedPlate(
                    tierID: info.tierID, weightKg: info.weightKg,
                    engravingText: info.engravingText, earnedAt: workout.date,
                    earnedByEvent: info.earnedByEvent,
                    sourceWorkoutID: workout.id.uuidString,
                    liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(info.liftTypeID)
                )
                context.insert(plate)
                existingEvents.append(info.earnedByEvent)
            }
        }

        try? context.save()
        let updatedEarnedCount = ((try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? [])
            .filter { $0.earnedByEvent != "starter" }
            .count
        if updatedEarnedCount > existingEarnedCount {
            needsWelcomeScreen = true
        }
        rebuildProgressionProjection(completedWorkouts: completedWorkouts)
    }

    func backfillMissingLiftSpecificPlates(completedWorkouts: [CompletedWorkout]) {
        guard !completedWorkouts.isEmpty else { return }
        guard let context else { return }

        let sorted = completedWorkouts
            .filter { !$0.isCardioWorkout }
            .sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return }

        let existingPlates = (try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? []
        var existingEvents = Set(existingPlates.map(\.earnedByEvent))
        var insertedCount = 0

        for workout in sorted {
            for lift in BarbellUnlockRules.firstTrackedLiftTypes(in: workout) {
                let event = BarbellUnlockRules.liftFirstEventKey(for: lift.id)
                guard existingEvents.insert(event).inserted else { continue }

                context.insert(EarnedPlate(
                    tierID: 0,
                    weightKg: 5,
                    engravingText: lift.engravingText,
                    earnedAt: workout.date,
                    earnedByEvent: event,
                    sourceWorkoutID: workout.id.uuidString,
                    liftTypeID: lift.id
                ))
                insertedCount += 1
            }
        }

        guard insertedCount > 0 else { return }

        do {
            try context.save()
            rebuildProgressionProjection(completedWorkouts: completedWorkouts)
            AppLogger.info("Backfilled \(insertedCount) missing lift-specific barbell plates", category: AppLogger.rewards)
        } catch {
            context.rollback()
            AppLogger.error("Failed to backfill lift-specific barbell plates: \(error)", category: AppLogger.rewards)
        }
    }

    func rebuildProgressionProjection(completedWorkouts: [CompletedWorkout]) {
        guard let context else { return }
        Self.applyProgressionProjection(completedWorkouts: completedWorkouts, context: context)

        do {
            try context.save()
            syncLocalBarbellStateToSupabase()
        } catch {
            context.rollback()
            AppLogger.error("Failed to rebuild barbell progression projection: \(error)", category: AppLogger.rewards)
        }
    }

    func syncLocalBarbellStateToSupabase() {
        guard let context else { return }
        let plates = ((try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? [])
            .filter { $0.earnedByEvent != "starter" }
        let platePayloads = plates.map(EarnedPlateSyncPayload.init(plate:))
        let earnedEventByPlateID = plates.reduce(into: [String: String]()) { result, plate in
            result[plate.id] = plate.earnedByEvent
        }
        let eventPayloads = ((try? context.fetch(FetchDescriptor<BarbellPlateEvent>())) ?? [])
            .compactMap { event -> BarbellPlateEventSyncPayload? in
                guard let earnedByEvent = earnedEventByPlateID[event.plateID] else { return nil }
                return BarbellPlateEventSyncPayload(event: event, earnedByEvent: earnedByEvent)
            }
        syncEarnedPlateAwardsToSupabase(platePayloads, eventPayloads: eventPayloads)
    }

    nonisolated static func applyProgressionProjection(
        completedWorkouts: [CompletedWorkout],
        context: ModelContext
    ) {
        let plates = ((try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? [])
            .filter { $0.earnedByEvent != "starter" }
        guard !plates.isEmpty else { return }

        let existingEvents = (try? context.fetch(FetchDescriptor<BarbellPlateEvent>())) ?? []
        var existingKeys = Set(existingEvents.map(\.stableKey))

        for plate in plates {
            let projection = BarbellPlateProjectionRules.rebuildProjection(
                for: plate,
                workouts: completedWorkouts
            )
            plate.applyProjection(projection)
            for draft in projection.eventDrafts where !existingKeys.contains(draft.stableKey) {
                context.insert(draft.toModel())
                existingKeys.insert(draft.stableKey)
            }
        }
    }

    // MARK: - RewardsEngine reset hook

    func resetAll() {
        guard let context else { return }
        let plateFetch = FetchDescriptor<EarnedPlate>()
        if let plates = try? context.fetch(plateFetch) {
            for p in plates { context.delete(p) }
        }
        let eventFetch = FetchDescriptor<BarbellPlateEvent>()
        if let events = try? context.fetch(eventFetch) {
            for event in events { context.delete(event) }
        }
        let configFetch = FetchDescriptor<BarbellConfig>()
        if let configs = try? context.fetch(configFetch) {
            for c in configs { context.delete(c) }
        }
        let processedHKFetch = FetchDescriptor<BarbellProcessedHKWorkout>()
        if let processedWorkouts = try? context.fetch(processedHKFetch) {
            for processed in processedWorkouts { context.delete(processed) }
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

private struct FriendBarbellShowcaseRemoteRow: Decodable {
    let barSkinID: String?
    let roomThemeID: String?
    let rackStyleID: String?
    let collarID: String?
    let bannerID: String?
    let showPlateEngravings: Bool?
    let roomName: String?
    let roomMotto: String?
    let tierID: Int?
    let weightKg: Double?
    let engravingText: String?
    let earnedByEvent: String?
    let liftTypeID: String?

    enum CodingKeys: String, CodingKey {
        case barSkinID = "bar_skin_id"
        case roomThemeID = "room_theme_id"
        case rackStyleID = "rack_style_id"
        case collarID = "collar_id"
        case bannerID = "banner_id"
        case showPlateEngravings = "show_plate_engravings"
        case roomName = "room_name"
        case roomMotto = "room_motto"
        case tierID = "tier_id"
        case weightKg = "weight_kg"
        case engravingText = "engraving_text"
        case earnedByEvent = "earned_by_event"
        case liftTypeID = "lift_type_id"
    }
}

private struct RackedPlateMutation {
    let earnedByEvent: String
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedAt: Date
    let sourceWorkoutID: String?
    let isRacked: Bool
    let rackPosition: Int?
    let liftTypeID: String?
    let currentTier: BarbellPlateProgressionTier
    let workoutsUsedCount: Int
    let prCount: Int
    let chalkUseCount: Int
    let gripWearCount: Int
    let pressUseCount: Int
    let firstEarnedAt: Date
    let lastUsedAt: Date?
}

private struct EarnedPlateRemoteRow: Decodable {
    let earnedByEvent: String
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedAt: String?
    let sourceWorkoutID: String?
    let isRacked: Bool
    let rackPosition: Int?
    let updatedAt: String?
    let liftTypeID: String?
    let currentTierRaw: String?
    let workoutsUsedCount: Int?
    let prCount: Int?
    let chalkUseCount: Int?
    let gripWearCount: Int?
    let pressUseCount: Int?
    let firstEarnedAt: String?
    let lastUsedAt: String?

    var earnedAtDate: Date {
        guard let earnedAt else { return .now }
        return ISO8601DateFormatter().date(from: earnedAt) ?? .now
    }

    var currentTier: BarbellPlateProgressionTier {
        currentTierRaw.flatMap(BarbellPlateProgressionTier.init(rawValue:)) ?? .iron
    }

    var firstEarnedAtDate: Date? {
        guard let firstEarnedAt else { return nil }
        return ISO8601DateFormatter().date(from: firstEarnedAt)
    }

    var lastUsedAtDate: Date? {
        guard let lastUsedAt else { return nil }
        return ISO8601DateFormatter().date(from: lastUsedAt)
    }

    enum CodingKeys: String, CodingKey {
        case earnedByEvent = "earned_by_event"
        case tierID = "tier_id"
        case weightKg = "weight_kg"
        case engravingText = "engraving_text"
        case earnedAt = "earned_at"
        case sourceWorkoutID = "source_workout_id"
        case isRacked = "is_racked"
        case rackPosition = "rack_position"
        case updatedAt = "updated_at"
        case liftTypeID = "lift_type_id"
        case currentTierRaw = "current_tier"
        case workoutsUsedCount = "workouts_used_count"
        case prCount = "pr_count"
        case chalkUseCount = "chalk_use_count"
        case gripWearCount = "grip_wear_count"
        case pressUseCount = "press_use_count"
        case firstEarnedAt = "first_earned_at"
        case lastUsedAt = "last_used_at"
    }
}

private struct EarnedPlateUpsertRow: Encodable {
    let userID: String
    let earnedByEvent: String
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedAt: String
    let sourceWorkoutID: String?
    let isRacked: Bool
    let rackPosition: Int?
    let liftTypeID: String?
    let currentTier: String
    let workoutsUsedCount: Int
    let prCount: Int
    let chalkUseCount: Int
    let gripWearCount: Int
    let pressUseCount: Int
    let firstEarnedAt: String
    let lastUsedAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case earnedByEvent = "earned_by_event"
        case tierID = "tier_id"
        case weightKg = "weight_kg"
        case engravingText = "engraving_text"
        case earnedAt = "earned_at"
        case sourceWorkoutID = "source_workout_id"
        case isRacked = "is_racked"
        case rackPosition = "rack_position"
        case liftTypeID = "lift_type_id"
        case currentTier = "current_tier"
        case workoutsUsedCount = "workouts_used_count"
        case prCount = "pr_count"
        case chalkUseCount = "chalk_use_count"
        case gripWearCount = "grip_wear_count"
        case pressUseCount = "press_use_count"
        case firstEarnedAt = "first_earned_at"
        case lastUsedAt = "last_used_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(earnedByEvent, forKey: .earnedByEvent)
        try container.encode(tierID, forKey: .tierID)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(engravingText, forKey: .engravingText)
        try container.encode(earnedAt, forKey: .earnedAt)
        try container.encodeIfPresent(sourceWorkoutID, forKey: .sourceWorkoutID)
        try container.encode(isRacked, forKey: .isRacked)
        if isRacked {
            try container.encode(rackPosition, forKey: .rackPosition)
        } else {
            try container.encodeNil(forKey: .rackPosition)
        }
        try container.encodeIfPresent(liftTypeID, forKey: .liftTypeID)
        try container.encode(currentTier, forKey: .currentTier)
        try container.encode(workoutsUsedCount, forKey: .workoutsUsedCount)
        try container.encode(prCount, forKey: .prCount)
        try container.encode(chalkUseCount, forKey: .chalkUseCount)
        try container.encode(gripWearCount, forKey: .gripWearCount)
        try container.encode(pressUseCount, forKey: .pressUseCount)
        try container.encode(firstEarnedAt, forKey: .firstEarnedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct BarbellPlateEventRemoteRow: Decodable {
    let stableKey: String
    let earnedByEvent: String
    let kindRaw: String
    let occurredAt: String
    let workoutID: String?
    let tierRaw: String?
    let milestoneID: String?
    let summary: String
    let isSilent: Bool

    var kind: BarbellPlateEvent.Kind {
        BarbellPlateEvent.Kind(rawValue: kindRaw) ?? .earned
    }

    var tier: BarbellPlateProgressionTier? {
        tierRaw.flatMap(BarbellPlateProgressionTier.init(rawValue:))
    }

    var occurredAtDate: Date {
        ISO8601DateFormatter().date(from: occurredAt) ?? .now
    }

    enum CodingKeys: String, CodingKey {
        case stableKey = "stable_key"
        case earnedByEvent = "earned_by_event"
        case kindRaw = "kind"
        case occurredAt = "occurred_at"
        case workoutID = "workout_id"
        case tierRaw = "tier"
        case milestoneID = "milestone_id"
        case summary
        case isSilent = "is_silent"
    }
}

private struct BarbellCosmeticUnlockRemoteRow: Decodable {
    let cosmeticID: String
    let unlockedAt: String?
    let sourceRaw: String
    let sourceWorkoutID: String?
    let catalogVersion: String?

    var unlockedAtDate: Date {
        guard let unlockedAt else { return .now }
        return ISO8601DateFormatter().date(from: unlockedAt) ?? .now
    }

    var source: BarbellCosmeticUnlockSource {
        BarbellCosmeticUnlockSource(rawValue: sourceRaw) ?? .workout
    }

    enum CodingKeys: String, CodingKey {
        case cosmeticID = "cosmetic_id"
        case unlockedAt = "unlocked_at"
        case sourceRaw = "source"
        case sourceWorkoutID = "source_workout_id"
        case catalogVersion = "catalog_version"
    }
}

private struct BarbellCosmeticUnlockUpsertRow: Encodable {
    let userID: String
    let cosmeticID: String
    let unlockedAt: String
    let source: String
    let sourceWorkoutID: String?
    let catalogVersion: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case cosmeticID = "cosmetic_id"
        case unlockedAt = "unlocked_at"
        case source
        case sourceWorkoutID = "source_workout_id"
        case catalogVersion = "catalog_version"
    }
}

private struct BarbellPlateEventUpsertRow: Encodable {
    let userID: String
    let stableKey: String
    let earnedByEvent: String
    let kind: String
    let occurredAt: String
    let workoutID: String?
    let tier: String?
    let milestoneID: String?
    let summary: String
    let isSilent: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case stableKey = "stable_key"
        case earnedByEvent = "earned_by_event"
        case kind
        case occurredAt = "occurred_at"
        case workoutID = "workout_id"
        case tier
        case milestoneID = "milestone_id"
        case summary
        case isSilent = "is_silent"
    }
}
