//
//  BarbellCatalogTypes.swift
//  WRKT
//
//  Shared barbell catalog primitives used by rewards, profile, and editor surfaces.
//

import SwiftUI
import UIKit

struct PlateTier: Identifiable {
    let id: Int
    let name: String
    let rarity: Rarity
    let earnedBy: String
    let plateColor: UIColor
    let metallic: Float
    let roughness: Float
    let clearcoat: Float
    let clearcoatRoughness: Float
    let style: PlateStyle

    enum PlateStyle { case rawIron, castIron, bumper, brass, competition, polishedSteel, gold, starter }

    enum Rarity: String, Codable, Sendable {
        case common = "Common", uncommon = "Uncommon", rare = "Rare"
        case epic = "Epic", legendary = "Legendary"

        var color: Color {
            switch self {
            case .common:    return .gray
            case .uncommon:  return Color(red: 0.2, green: 0.7, blue: 0.3)
            case .rare:      return Color(red: 0.2, green: 0.4, blue: 0.9)
            case .epic:      return Color(red: 0.6, green: 0.2, blue: 0.9)
            case .legendary: return Color(red: 0.9, green: 0.65, blue: 0.1)
            }
        }
    }

    static let all: [PlateTier] = [
        PlateTier(id: 0, name: "Raw Iron", rarity: .common,
                  earnedBy: "Complete your first workout",
                  plateColor: UIColor(red: 0.40, green: 0.18, blue: 0.07, alpha: 1),
                  metallic: 0.12, roughness: 0.97, clearcoat: 0, clearcoatRoughness: 0,
                  style: .rawIron),
        PlateTier(id: 1, name: "Cast Iron", rarity: .common,
                  earnedBy: "Complete 5 workouts",
                  plateColor: UIColor(red: 0.14, green: 0.14, blue: 0.14, alpha: 1),
                  metallic: 0.06, roughness: 0.94, clearcoat: 0, clearcoatRoughness: 0,
                  style: .castIron),
        PlateTier(id: 2, name: "Black Bumper", rarity: .uncommon,
                  earnedBy: "Complete 15 workouts",
                  plateColor: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1),
                  metallic: 0, roughness: 0.78, clearcoat: 0.3, clearcoatRoughness: 0.25,
                  style: .bumper),
        PlateTier(id: 3, name: "Brass", rarity: .rare,
                  earnedBy: "Complete 25 workouts",
                  plateColor: UIColor(red: 0.75, green: 0.60, blue: 0.25, alpha: 1),
                  metallic: 0.85, roughness: 0.35, clearcoat: 0.2, clearcoatRoughness: 0.15,
                  style: .brass),
        PlateTier(id: 4, name: "Competition", rarity: .rare,
                  earnedBy: "Hit a personal record",
                  plateColor: UIColor(red: 0.82, green: 0.09, blue: 0.09, alpha: 1),
                  metallic: 0, roughness: 0.70, clearcoat: 0.45, clearcoatRoughness: 0.2,
                  style: .competition),
        PlateTier(id: 5, name: "Polished Steel", rarity: .epic,
                  earnedBy: "Complete 50 workouts",
                  plateColor: UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1),
                  metallic: 0.98, roughness: 0.10, clearcoat: 0, clearcoatRoughness: 0,
                  style: .polishedSteel),
        PlateTier(id: 6, name: "Gold", rarity: .legendary,
                  earnedBy: "Complete a 90-day streak",
                  plateColor: UIColor(red: 0.88, green: 0.68, blue: 0.12, alpha: 1),
                  metallic: 1.0, roughness: 0.05, clearcoat: 0.6, clearcoatRoughness: 0.05,
                  style: .gold),
        PlateTier(id: 7, name: "Starter", rarity: .common,
                  earnedBy: "Awarded at account creation",
                  plateColor: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1),
                  metallic: 0, roughness: 0.9, clearcoat: 0, clearcoatRoughness: 0,
                  style: .starter),
    ]
}

struct BarSkin: Identifiable {
    let id: Int
    let name: String
    let rarity: PlateTier.Rarity
    let earnedBy: String
    let barColor: UIColor
    let metallic: Float
    let roughness: Float

    static let all: [BarSkin] = [
        BarSkin(id: 0, name: "Chrome", rarity: .common, earnedBy: "Default",
                barColor: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12),
        BarSkin(id: 1, name: "Matte Black", rarity: .uncommon, earnedBy: "10 workouts",
                barColor: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
                metallic: 0.15, roughness: 0.92),
        BarSkin(id: 2, name: "Gold", rarity: .epic, earnedBy: "100 workouts",
                barColor: UIColor(red: 0.88, green: 0.68, blue: 0.12, alpha: 1),
                metallic: 1.0, roughness: 0.08),
        BarSkin(id: 3, name: "Cerakote", rarity: .rare, earnedBy: "30-day streak",
                barColor: UIColor(red: 0.20, green: 0.28, blue: 0.17, alpha: 1),
                metallic: 0.25, roughness: 0.80),
    ]
}

struct StickerOption: Identifiable {
    let id: Int
    let name: String
    let rarity: PlateTier.Rarity
    let earnedBy: String
    let emoji: String?

    static let all: [StickerOption] = [
        StickerOption(id: 0, name: "None", rarity: .common, earnedBy: "Default", emoji: nil),
        StickerOption(id: 1, name: "Fire", rarity: .uncommon, earnedBy: "5 workouts in a week", emoji: "🔥"),
        StickerOption(id: 2, name: "Lightning", rarity: .rare, earnedBy: "Hit a PR", emoji: "⚡"),
        StickerOption(id: 3, name: "Diamond", rarity: .epic, earnedBy: "50 workouts", emoji: "💎"),
        StickerOption(id: 4, name: "Crown", rarity: .legendary, earnedBy: "90-day streak", emoji: "👑"),
        StickerOption(id: 5, name: "Gains", rarity: .uncommon, earnedBy: "First strength workout", emoji: "💪"),
    ]
}

enum BarbellCosmeticKind: String, Codable, Equatable, Sendable {
    case barSkin
    case roomTheme
    case rackStyle
    case collar
    case banner
}

struct BarbellCosmetic: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: BarbellCosmeticKind
    let name: String
    let rarity: PlateTier.Rarity
    let unlockRequirement: String
    let isDefault: Bool
    let availableFrom: Date?
    let availableUntil: Date?
    let seasonalWorkoutTarget: Int?

    init(
        id: String,
        kind: BarbellCosmeticKind,
        name: String,
        rarity: PlateTier.Rarity,
        unlockRequirement: String,
        isDefault: Bool,
        availableFrom: Date? = nil,
        availableUntil: Date? = nil,
        seasonalWorkoutTarget: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.rarity = rarity
        self.unlockRequirement = unlockRequirement
        self.isDefault = isDefault
        self.availableFrom = availableFrom
        self.availableUntil = availableUntil
        self.seasonalWorkoutTarget = seasonalWorkoutTarget
    }
}

struct BarbellCosmeticCatalog: Codable, Equatable, Sendable {
    let version: String
    let items: [BarbellCosmetic]

    var defaultUnlockIDs: Set<String> {
        Set(items.filter(\.isDefault).map(\.id))
    }

    func item(id: String) -> BarbellCosmetic? {
        items.first { $0.id == id }
    }

    func activeSeasonalItem(for date: Date) -> BarbellCosmetic? {
        items.first { item in
            guard let availableFrom = item.availableFrom,
                  let availableUntil = item.availableUntil,
                  availableFrom <= date,
                  date < availableUntil else {
                return false
            }
            return item.seasonalWorkoutTarget != nil
        }
    }

    static let current = BarbellCosmeticCatalog(
        version: "mvp-c-v1",
        items: [
            BarbellCosmetic(
                id: "steel_default",
                kind: .barSkin,
                name: "Default Steel",
                rarity: .common,
                unlockRequirement: "Default",
                isDefault: true
            ),
            BarbellCosmetic(
                id: "black_oxide",
                kind: .barSkin,
                name: "Black Oxide",
                rarity: .uncommon,
                unlockRequirement: "10 workouts",
                isDefault: false
            ),
            BarbellCosmetic(
                id: "chrome",
                kind: .barSkin,
                name: "Chrome",
                rarity: .common,
                unlockRequirement: "Default",
                isDefault: true
            ),
            BarbellCosmetic(
                id: "brass_accent",
                kind: .barSkin,
                name: "Brass Accent",
                rarity: .rare,
                unlockRequirement: "25 workouts",
                isDefault: false
            ),
            BarbellCosmetic(
                id: "dark_gym",
                kind: .roomTheme,
                name: "Dark Gym",
                rarity: .common,
                unlockRequirement: "Default",
                isDefault: true
            ),
            BarbellCosmetic(
                id: "concrete_room",
                kind: .roomTheme,
                name: "Concrete Room",
                rarity: .uncommon,
                unlockRequirement: "15 workouts",
                isDefault: false
            ),
            BarbellCosmetic(
                id: "competition_platform",
                kind: .roomTheme,
                name: "Competition Platform",
                rarity: .rare,
                unlockRequirement: "Hit a PR",
                isDefault: false
            ),
            BarbellCosmetic(
                id: "matte_black",
                kind: .rackStyle,
                name: "Matte Black",
                rarity: .common,
                unlockRequirement: "Default",
                isDefault: true
            ),
            BarbellCosmetic(
                id: "brushed_steel",
                kind: .rackStyle,
                name: "Brushed Steel",
                rarity: .uncommon,
                unlockRequirement: "10 workouts",
                isDefault: false
            ),
            BarbellCosmetic(
                id: "brass_accent_rack",
                kind: .rackStyle,
                name: "Brass Accent Rack",
                rarity: .rare,
                unlockRequirement: "25 workouts",
                isDefault: false
            ),
            BarbellCosmetic(
                id: "may_2026_brass_accent",
                kind: .barSkin,
                name: "May Brass Accent",
                rarity: .rare,
                unlockRequirement: "Complete a workout in May 2026",
                isDefault: false,
                availableFrom: Self.date("2026-05-01T00:00:00Z"),
                availableUntil: Self.date("2026-06-01T00:00:00Z"),
                seasonalWorkoutTarget: 1
            ),
        ]
    )

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
