//
//  BarbellCustomizationService.swift
//  WRKT
//
//  Owns local customization settings lifecycle. Remote sync is wired later in MVP-B.
//

import Foundation
import Supabase
import SwiftData

@MainActor
final class BarbellCustomizationService {
    static let shared = BarbellCustomizationService()

    private var context: ModelContext?
    private weak var authService: SupabaseAuthService?
    private var syncTask: Task<Void, Never>?
    private let client = SupabaseClientWrapper.shared.client

    private init() {}

    func configure(context: ModelContext, supabaseAuthService: SupabaseAuthService) {
        self.context = context
        self.authService = supabaseAuthService
        let config = fetchOrCreateConfig()
        config.migrateLegacyCustomizationFieldsIfNeeded()
        try? context.save()
        Task { @MainActor in
            try? await pullFromSupabase()
        }
    }

    func fetchOrCreateConfig() -> BarbellConfig {
        guard let context else {
            preconditionFailure("BarbellCustomizationService must be configured before use")
        }

        let descriptor = FetchDescriptor<BarbellConfig>(predicate: #Predicate { $0.id == "global" })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let config = BarbellConfig()
        context.insert(config)
        try? context.save()
        return config
    }

    @discardableResult
    func unlockSkin(id: String) -> Bool {
        let config = fetchOrCreateConfig()
        guard !config.unlockedSkinIDs.contains(id) else { return false }
        config.unlockedSkinIDs.append(id)
        try? context?.save()
        Task {
            guard let userID = authService?.currentUser?.id else { return }
            try? await client
                .from("barbell_cosmetic_unlocks")
                .upsert([
                    "user_id": userID.uuidString,
                    "cosmetic_id": id,
                    "source": "challenge"
                ], onConflict: "user_id,cosmetic_id")
                .execute()
        }
        return true
    }

    func pullFromSupabase() async throws {
        guard let context else {
            AppLogger.info(
                "Skipping barbell customization pull before service configuration",
                category: AppLogger.rewards
            )
            return
        }
        guard let userID = authService?.currentUser?.id else { return }

        let rows: [BarbellCustomizationSettingsRemoteRow] = try await client
            .from("barbell_customization_settings")
            .select("user_id, bar_skin_id, room_theme_id, rack_style_id, collar_id, banner_id, show_plate_engravings, room_name, room_motto, display_loadout, updated_at")
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        let config = fetchOrCreateConfig()
        if let row = rows.first {
            applyRemoteSettings(row, to: config)
            config.needsSupabaseSync = false
            do {
                try context.save()
                AppLogger.info("Pulled barbell customization settings from Supabase", category: AppLogger.rewards)
            } catch {
                context.rollback()
                throw error
            }
        } else {
            await syncCurrentSettingsToSupabase()
        }
    }

    func syncCurrentSettingsToSupabase() async {
        guard context != nil else {
            AppLogger.info(
                "Skipping barbell customization sync before service configuration",
                category: AppLogger.rewards
            )
            return
        }
        guard let userID = authService?.currentUser?.id else { return }

        let config = fetchOrCreateConfig()
        config.migrateLegacyCustomizationFieldsIfNeeded()
        let row = BarbellCustomizationSettingsUpsertRow(
            config: config,
            userID: userID,
            remoteDisplayLoadout: remoteDisplayLoadout(for: config)
        )

        do {
            try await client
                .from("barbell_customization_settings")
                .upsert(row, onConflict: "user_id")
                .execute()
            config.needsSupabaseSync = false
            try? context?.save()
            AppLogger.info("Synced barbell customization settings to Supabase", category: AppLogger.rewards)
        } catch {
            config.needsSupabaseSync = true
            try? context?.save()
            AppLogger.error("Failed to sync barbell customization settings to Supabase: \(error)", category: AppLogger.rewards)
        }
    }

    func enqueueSyncCurrentSettingsToSupabase() {
        guard let userID = authService?.currentUser?.id else { return }
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self, userID] in
            // Debounce: coalesce rapid operations (e.g. swiping all plates off the bar)
            // into a single network call instead of N sequential upserts.
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            guard self?.authService?.currentUser?.id == userID else { return }
            await self?.syncCurrentSettingsToSupabase()
        }
    }

    func cancelAndAwaitRemoteSyncForAuthenticatedUserChange(to newUserID: UUID?) async {
        syncTask?.cancel()
        await syncTask?.value
        syncTask = nil

        AppLogger.info(
            "Barbell customization sync queue cancelled for auth user change. nextUser=\(newUserID?.uuidString ?? "none")",
            category: AppLogger.rewards
        )
    }

    private func applyRemoteSettings(_ row: BarbellCustomizationSettingsRemoteRow, to config: BarbellConfig) {
        config.selectedBarSkinIDRaw = row.barSkinID
        config.selectedRoomThemeIDRaw = row.roomThemeID
        config.selectedRackStyleIDRaw = row.rackStyleID
        config.selectedCollarIDRaw = row.collarID
        config.selectedBannerIDRaw = row.bannerID
        config.showPlateEngravingsRaw = row.showPlateEngravings
        config.roomName = barbellNormalizedRoomWallText(row.roomName)
        config.roomMotto = normalizedRemoteText(row.roomMotto, maximumLength: 64)
        config.displayLoadoutData = try? JSONEncoder().encode(localDisplayLoadout(from: row.displayLoadout ?? DisplayLoadout()))
    }

    private func remoteDisplayLoadout(for config: BarbellConfig) -> DisplayLoadout {
        guard let context else { return config.displayLoadout }
        let descriptor = FetchDescriptor<EarnedPlate>()
        let plates = (try? context.fetch(descriptor)) ?? []
        let byLocalID = Dictionary(uniqueKeysWithValues: plates.map { ($0.id, $0.earnedByEvent) })

        func stableKeys(from localIDs: [String]) -> [String] {
            localIDs.compactMap { byLocalID[$0] ?? $0 }
        }

        let loadout = config.displayLoadout
        return DisplayLoadout(
            onBar: stableKeys(from: loadout.onBar),
            onWall: stableKeys(from: loadout.onWall)
        )
    }

    private func localDisplayLoadout(from remoteLoadout: DisplayLoadout) -> DisplayLoadout {
        guard let context else { return remoteLoadout }
        let descriptor = FetchDescriptor<EarnedPlate>()
        let plates = (try? context.fetch(descriptor)) ?? []
        let localIDByStableKey = Dictionary(grouping: plates, by: \.earnedByEvent)
            .compactMapValues { $0.first?.id }
        let localIDs = Set(plates.map(\.id))

        func localKeys(from remoteKeys: [String]) -> [String] {
            remoteKeys.compactMap { key in
                if localIDs.contains(key) { return key }
                return localIDByStableKey[key]
            }
        }

        return DisplayLoadout(
            onBar: localKeys(from: remoteLoadout.onBar),
            onWall: localKeys(from: remoteLoadout.onWall)
        )
    }

    private func normalizedRemoteText(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}

private struct BarbellCustomizationSettingsRemoteRow: Decodable {
    let userID: String
    let barSkinID: String
    let roomThemeID: String
    let rackStyleID: String
    let collarID: String?
    let bannerID: String?
    let showPlateEngravings: Bool
    let roomName: String?
    let roomMotto: String?
    let displayLoadout: DisplayLoadout?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case barSkinID = "bar_skin_id"
        case roomThemeID = "room_theme_id"
        case rackStyleID = "rack_style_id"
        case collarID = "collar_id"
        case bannerID = "banner_id"
        case showPlateEngravings = "show_plate_engravings"
        case roomName = "room_name"
        case roomMotto = "room_motto"
        case displayLoadout = "display_loadout"
        case updatedAt = "updated_at"
    }
}

private struct BarbellCustomizationSettingsUpsertRow: Encodable {
    let userID: String
    let barSkinID: String
    let roomThemeID: String
    let rackStyleID: String
    let collarID: String?
    let bannerID: String?
    let showPlateEngravings: Bool
    let roomName: String?
    let roomMotto: String?
    let displayLoadout: DisplayLoadout
    let updatedAt: String

    init(config: BarbellConfig, userID: UUID, remoteDisplayLoadout: DisplayLoadout) {
        self.userID = userID.uuidString
        self.barSkinID = config.effectiveSelectedBarSkinID
        self.roomThemeID = config.effectiveSelectedRoomThemeID
        self.rackStyleID = config.effectiveSelectedRackStyleID
        self.collarID = config.selectedCollarIDRaw
        self.bannerID = config.selectedBannerIDRaw
        self.showPlateEngravings = config.showPlateEngravings
        self.roomName = barbellNormalizedRoomWallText(config.roomName)
        self.roomMotto = Self.normalizedText(config.roomMotto, maximumLength: 64)
        self.displayLoadout = remoteDisplayLoadout
        self.updatedAt = ISO8601DateFormatter().string(from: .now)
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case barSkinID = "bar_skin_id"
        case roomThemeID = "room_theme_id"
        case rackStyleID = "rack_style_id"
        case collarID = "collar_id"
        case bannerID = "banner_id"
        case showPlateEngravings = "show_plate_engravings"
        case roomName = "room_name"
        case roomMotto = "room_motto"
        case displayLoadout = "display_loadout"
        case updatedAt = "updated_at"
    }

    private static func normalizedText(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}
