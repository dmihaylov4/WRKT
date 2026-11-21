//
//  CutRackModel.swift
//  WRKT
//
//  What the Cut rack ("Your bar") shows, as plain values: the total on the bar in the user's
//  unit, one summary line, the hint under the 3D scene and the tray of earned plates (loaded
//  first, in bar order, then storage in the legacy wall order). Also the plate detail sheet,
//  the full collection sheet and the scene reconciliation the host runs when the saved bar
//  changes. The starter plate is never a tray plate and adds no weight, as in the legacy rack.
//

import Foundation

// MARK: - Facts

/// One earned plate, reduced to what the rack needs.
struct CutRackPlateFacts: Equatable {
    var id: String
    /// The tier name ("Lime Bumper").
    var tierName: String
    /// The engraving, empty when there is none.
    var engraving: String
    var weightKg: Double
    var isLoaded: Bool
    /// Bar slot 0 (innermost) to 3 when loaded.
    var rackPosition: Int?
    /// The legacy wall order: higher shows first.
    var displayOrder: Int
    var earnedAt: Date
}

/// A notice the host raises after a failed load; it replaces the hint until the next change.
enum CutRackNotice: Equatable {
    case barFull
    case loadFailed
}

struct CutRackFacts {
    /// Earned plates only (no starter).
    var plates: [CutRackPlateFacts]
    /// Bar slots in use by earned plates (the bar holds four). The starter plate is never counted.
    var occupiedSlots: Int
    var unit: WeightUnit
    var notice: CutRackNotice?
}

// MARK: - Model

struct CutRackModel: Equatable {
    struct Tile: Identifiable, Equatable {
        var id: String
        /// "20 kg"
        var weight: String
        var isLoaded: Bool
        /// "Lime Bumper, 20 kg, on the bar"
        var accessibilityLabel: String
        var accessibilityHint: String
    }

    var title = "Your bar"
    /// The total as a numeral: "150".
    var totalValue: String
    /// "kg on the bar"
    var totalUnit: String
    /// "150 kilograms on the bar"
    var totalAccessibilityLabel: String
    /// "8 plates loaded, 4 in storage"
    var summary: String
    /// VoiceOver value of the 3D scene: the loaded plates, innermost first, or "Empty bar".
    var sceneAccessibilityValue: String
    /// One quiet line under the scene; nil when there is nothing to do.
    var hint: String?
    var trayTitle = "Your plates"
    /// "All 12", nil when no plate has been earned.
    var allTitle: String?
    var allAccessibilityLabel: String
    var tiles: [Tile]
    /// Shown in the tray when no plate has been earned.
    var emptyTray: String
}

enum CutRackLogic {
    static let barCapacity = 4
    static let barWeightKg = 20.0
    static let emptyTrayLine = "Finish a strength workout to earn your first plate."

    static func model(_ facts: CutRackFacts, locale: Locale = .current) -> CutRackModel {
        let tray = trayOrder(facts.plates)
        let loaded = tray.filter(\.isLoaded).count
        let total = totalKg(facts.plates)
        let unitWord = facts.unit.rawValue
        let totalValue = number(facts.unit.displayValue(total), locale: locale)
        return CutRackModel(
            totalValue: totalValue,
            totalUnit: "\(unitWord) on the bar",
            totalAccessibilityLabel: "\(totalValue) \(spokenUnit(facts.unit)) on the bar",
            summary: summary(loaded: loaded, storage: tray.count - loaded),
            sceneAccessibilityValue: sceneAccessibilityValue(tray.filter(\.isLoaded), unit: facts.unit, locale: locale),
            hint: hint(facts, loaded: loaded),
            allTitle: tray.isEmpty ? nil : "All \(tray.count)",
            allAccessibilityLabel: "Show all \(tray.count) plates",
            tiles: tray.map { tile($0, unit: facts.unit, locale: locale) },
            emptyTray: emptyTrayLine
        )
    }

    /// The legacy formula (plateWallTotalWeight): the 20 kg bar plus every loaded plate on both sides.
    static func totalKg(_ plates: [CutRackPlateFacts]) -> Double {
        barWeightKg + plates.filter(\.isLoaded).reduce(0) { $0 + $1.weightKg } * 2
    }

    /// Loaded plates in bar order (innermost first), then storage by the legacy wall order
    /// (newest display order first), then newest earned, then id so the order is stable.
    static func trayOrder(_ plates: [CutRackPlateFacts]) -> [CutRackPlateFacts] {
        plates.sorted { a, b in
            if a.isLoaded != b.isLoaded { return a.isLoaded }
            if a.isLoaded {
                let pa = a.rackPosition ?? Int.max, pb = b.rackPosition ?? Int.max
                if pa != pb { return pa < pb }
            } else if a.displayOrder != b.displayOrder {
                return a.displayOrder > b.displayOrder
            }
            if a.earnedAt != b.earnedAt { return a.earnedAt > b.earnedAt }
            return a.id < b.id
        }
    }

    /// Counts earned plates, one per tray tile (each renders as a pair on the bar).
    static func summary(loaded: Int, storage: Int) -> String {
        switch (loaded, storage) {
        case (0, 0): return "No plates yet"
        case (_, 0): return "\(plates(loaded)) loaded"
        case (0, _): return "Nothing loaded, \(storage) in storage"
        default: return "\(plates(loaded)) loaded, \(storage) in storage"
        }
    }

    /// "Each side, inside out: Lime Bumper 20 kilograms, Bench 100 35 kilograms". Takes the
    /// loaded plates in bar order; every plate shows as a pair, one on each sleeve.
    static func sceneAccessibilityValue(_ loaded: [CutRackPlateFacts], unit: WeightUnit, locale: Locale) -> String {
        guard !loaded.isEmpty else { return "Empty bar" }
        let plates = loaded.map { "\(name($0)) \(spokenWeight($0.weightKg, unit: unit, locale: locale))" }
        return "Each side, inside out: " + plates.joined(separator: ", ")
    }

    static func hint(_ facts: CutRackFacts, loaded: Int) -> String? {
        switch facts.notice {
        case .barFull: return "The bar is full. Take a plate off first."
        case .loadFailed: return "That plate could not be loaded. Try again."
        case nil: break
        }
        // Keyed on earned plates only: the starter alone never asks for a swipe, and with no
        // plates earned the tray already says how to earn one.
        if facts.plates.isEmpty { return nil }
        if loaded == 0 { return "Tap a plate below to load it." }
        return "Swipe the bar to drop the outer plate."
    }

    static func isBarFull(occupiedSlots: Int) -> Bool {
        occupiedSlots >= barCapacity
    }

    static func tile(_ plate: CutRackPlateFacts, unit: WeightUnit, locale: Locale) -> CutRackModel.Tile {
        let weight = weight(plate.weightKg, unit: unit, locale: locale)
        return CutRackModel.Tile(
            id: plate.id,
            weight: weight,
            isLoaded: plate.isLoaded,
            accessibilityLabel: "\(name(plate)), \(spokenWeight(plate.weightKg, unit: unit, locale: locale)), \(status(plate))",
            accessibilityHint: plate.isLoaded ? "Takes it off the bar." : "Loads it onto the bar."
        )
    }

    /// The tier name, or the engraving when the plate has one ("Bench 100").
    static func name(_ plate: CutRackPlateFacts) -> String {
        let engraving = plate.engraving.trimmingCharacters(in: .whitespacesAndNewlines)
        return engraving.isEmpty ? plate.tierName : engraving
    }

    static func status(_ plate: CutRackPlateFacts) -> String {
        plate.isLoaded ? "on the bar" : "in storage"
    }

    /// "20 kg", "44.1 lb"
    static func weight(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(number(unit.displayValue(kg), locale: locale)) \(unit.rawValue)"
    }

    static func spokenWeight(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(number(unit.displayValue(kg), locale: locale)) \(spokenUnit(unit))"
    }

    static func spokenUnit(_ unit: WeightUnit) -> String {
        unit == .kg ? "kilograms" : "pounds"
    }

    /// Whole numbers stay whole; otherwise one decimal ("2.5", "44.1").
    static func number(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value.isFinite ? value : 0)) ?? "0"
    }

    private static func plates(_ count: Int) -> String {
        count == 1 ? "1 plate" : "\(count) plates"
    }

    // MARK: Scene reconciliation

    /// Plates that were saved on the bar before this change, are not on it now, and still show as
    /// bar plates in the scene. The scene drops them to the floor. A plate the user dragged onto
    /// the bar inside the scene is never released here: it was not on the bar before, and its own
    /// save follows. Plates already sliding off inside the scene are left to that animation.
    static func sceneReleases(previouslyLoaded: Set<String>, loaded: Set<String>,
                              barEntities: Set<String>, unloading: Set<String>) -> [String] {
        previouslyLoaded.subtracting(loaded).intersection(barEntities).subtracting(unloading).sorted()
    }
}

// MARK: - Plate detail

struct CutRackPlateDetailFacts {
    var plate: CutRackPlateFacts
    /// The workout or lift it was earned for, when known ("Push Day").
    var source: String?
    /// The plate's own tier ("Iron").
    var progressionTier: String
    var workoutsUsed: Int
    var prCount: Int
    var barIsFull: Bool
    var unit: WeightUnit
}

struct CutRackPlateDetailModel: Equatable {
    struct Row: Identifiable, Equatable {
        var id: String { label }
        var label: String
        var value: String
    }

    var title: String
    /// "20 kg, Lime Bumper" or "20 kg"
    var subtitle: String
    var rows: [Row]
    var actionTitle: String
    var isLoaded: Bool
    var isActionEnabled: Bool
}

enum CutRackPlateDetailLogic {
    static func model(_ facts: CutRackPlateDetailFacts, locale: Locale = .current) -> CutRackPlateDetailModel {
        let plate = facts.plate
        let title = CutRackLogic.name(plate)
        let weight = CutRackLogic.weight(plate.weightKg, unit: facts.unit, locale: locale)
        let subtitle = title == plate.tierName ? weight : "\(weight), \(plate.tierName)"
        var rows: [CutRackPlateDetailModel.Row] = [.init(label: "Earned", value: date(plate.earnedAt, locale: locale))]
        if let source = facts.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty, source != title {
            rows.append(.init(label: "Earned for", value: source))
        }
        rows.append(.init(label: "Tier", value: facts.progressionTier))
        rows.append(.init(label: "Used in", value: facts.workoutsUsed == 1 ? "1 workout" : "\(facts.workoutsUsed) workouts"))
        if facts.prCount > 0 {
            rows.append(.init(label: "Records", value: facts.prCount == 1 ? "1 PR" : "\(facts.prCount) PRs"))
        }
        rows.append(.init(label: "Where", value: plate.isLoaded ? "On the bar" : "In storage"))
        let canLoad = plate.isLoaded || !facts.barIsFull
        return CutRackPlateDetailModel(
            title: title,
            subtitle: subtitle,
            rows: rows,
            actionTitle: plate.isLoaded ? "Take off the bar" : (canLoad ? "Load onto the bar" : "The bar is full"),
            isLoaded: plate.isLoaded,
            isActionEnabled: canLoad
        )
    }

    static func date(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(locale))
    }
}

// MARK: - Collection

struct CutRackCollectionModel: Equatable {
    struct Row: Identifiable, Equatable {
        var id: String
        var title: String
        /// "20 kg, on the bar"
        var line: String
        var isLoaded: Bool
        var accessibilityLabel: String
    }

    var title = "Your plates"
    /// "12 plates, 4 on the bar"
    var subtitle: String?
    var rows: [Row]
    var empty: String
}

enum CutRackCollectionLogic {
    static func model(plates: [CutRackPlateFacts], unit: WeightUnit, locale: Locale = .current) -> CutRackCollectionModel {
        let ordered = CutRackLogic.trayOrder(plates)
        let loaded = ordered.filter(\.isLoaded).count
        return CutRackCollectionModel(
            subtitle: ordered.isEmpty ? nil : "\(ordered.count == 1 ? "1 plate" : "\(ordered.count) plates"), \(loaded) on the bar",
            rows: ordered.map { plate in
                let name = CutRackLogic.name(plate)
                return .init(
                    id: plate.id,
                    title: name,
                    line: "\(CutRackLogic.weight(plate.weightKg, unit: unit, locale: locale)), \(CutRackLogic.status(plate))",
                    isLoaded: plate.isLoaded,
                    accessibilityLabel: "\(name), \(CutRackLogic.spokenWeight(plate.weightKg, unit: unit, locale: locale)), \(CutRackLogic.status(plate))"
                )
            },
            empty: CutRackLogic.emptyTrayLine
        )
    }
}
