//
//  CutRackModel.swift
//  WRKT
//
//  What the Cut rack ("Your bar") shows, as plain values: the total on the bar in the user's
//  unit, one summary line, the hint under the 3D scene and the tray of earned plates. The tray
//  shows the loaded plates first, one tile each in bar order, then the stored plates grouped by
//  look: identical plates (CutRackLogic.look) share one tile with a count, in family sections
//  (engraved, metal, bumpers, iron). Also the play action (drop every stored plate into the
//  room, then tidy up), the plate detail sheet, the full collection sheet and the scene
//  reconciliation the host runs when the saved bar changes. The starter plate is never a tray
//  plate and adds no weight, as in the legacy rack.
//

import Foundation

// MARK: - Facts

/// The tray's sections for stored plates, rarest first: one-off engraved plates, then metal
/// (brass, steel, chrome, gold), rubber bumpers and competition plates, and iron.
enum CutRackPlateFamily: Int, CaseIterable, Comparable {
    case engraved
    case metal
    case bumper
    case iron

    var title: String {
        switch self {
        case .engraved: return "Engraved"
        case .metal: return "Metal"
        case .bumper: return "Bumpers"
        case .iron: return "Iron"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

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
    /// PlateTier.id.
    var tierID: Int = 0
    /// The plate's progression tier ("iron" to "cosmic"): its face rings and thumbnail differ.
    var progressionTier: String = BarbellPlateProgressionTier.iron.rawValue
    /// The lift a lift plate was earned for; nil and "global" are the same.
    var liftTypeID: String?
    /// The tier's material family, used when the plate has no engraving.
    var material: CutRackPlateFamily = .bumper
    /// The tier's rarity, 0 (common) to 4 (legendary).
    var rarity: Int = 0
}

/// Everything that makes two plates look the same in the tray and in the scene: the tier, the
/// weight, the engraving (case and spacing aside), the progression tier and the lift. Plates
/// with equal looks are interchangeable copies; anything else stays its own tile.
struct CutRackPlateLook: Hashable {
    var tierID: Int
    var tierName: String
    var weightKg: Double
    var engraving: String
    var progressionTier: String
    var liftTypeID: String

    /// Stable text for SwiftUI identity.
    var key: String {
        "\(tierID)|\(tierName)|\(weightKg)|\(engraving)|\(progressionTier)|\(liftTypeID)"
    }
}

/// The stored copies of one look, in the order they load (the legacy wall order), plus how many
/// copies of the same look are on the bar.
struct CutRackPlateGroup: Equatable {
    var look: CutRackPlateLook
    var family: CutRackPlateFamily
    var stored: [CutRackPlateFacts]
    var loadedCount: Int
}

/// The room's play state: idle, plates raining in, or dropped plates lying loose.
enum CutRackPlayPhase: Equatable {
    case idle
    case raining
    case loose
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
    var playPhase: CutRackPlayPhase = .idle
}

// MARK: - Model

struct CutRackModel: Equatable {
    struct Tile: Identifiable, Equatable {
        /// A loaded plate's id, or "look:" and the look's key for a stored group (stable while
        /// copies come and go).
        var id: String
        /// The plate a tap acts on: the loaded plate (takes it off) or the group's next copy (loads it).
        var plateID: String
        /// "20 kg"
        var weight: String
        var isLoaded: Bool
        /// Copies in storage this tile stands for (1 for a single plate, 0 for a loaded plate).
        var storedCount: Int
        /// "×12" on a group of more than one, nil otherwise.
        var badge: String?
        /// Copies of this look on the bar, shown as a small lime mark on a stored group.
        var onBarCount: Int
        /// "Lime Bumper, 20 kg, on the bar"
        var accessibilityLabel: String
        var accessibilityHint: String
    }

    struct Section: Identifiable, Equatable {
        var id: String
        /// "On the bar", "Bumpers"; nil when the tray has one section only.
        var title: String?
        var tiles: [Tile]
    }

    /// Drop every stored plate into the room, or tidy the dropped plates away.
    struct PlayAction: Equatable {
        var title: String
        var accessibilityLabel: String
        var accessibilityHint: String
        var isTidy: Bool
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
    /// The header read as one: "150 kilograms on the bar. 3 plates loaded, 87 in storage"
    var headerAccessibilityLabel: String
    /// VoiceOver value of the 3D scene: the loaded plates, innermost first, or "Empty bar".
    var sceneAccessibilityValue: String
    /// One quiet line under the scene; nil when there is nothing to do.
    var hint: String?
    var trayTitle = "Your plates"
    /// "All 12", nil when no plate has been earned. Opens the full list.
    var allTitle: String?
    var allAccessibilityLabel: String
    var playAction: PlayAction?
    var sections: [Section]
    /// Shown in the tray when no plate has been earned.
    var emptyTray: String

    /// Every tile, in tray order.
    var tiles: [Tile] { sections.flatMap(\.tiles) }
}

enum CutRackLogic {
    static let barCapacity = 4
    static let barWeightKg = 20.0
    static let emptyTrayLine = "Finish a strength workout to earn your first plate."

    static func model(_ facts: CutRackFacts, locale: Locale = .current) -> CutRackModel {
        let tray = trayOrder(facts.plates)
        let loadedPlates = tray.filter(\.isLoaded)
        let loaded = loadedPlates.count
        let storage = tray.count - loaded
        let total = totalKg(facts.plates)
        let unitWord = facts.unit.rawValue
        let totalValue = number(facts.unit.displayValue(total), locale: locale)
        let totalLabel = "\(totalValue) \(spokenUnit(facts.unit)) on the bar"
        let summary = summary(loaded: loaded, storage: storage)
        return CutRackModel(
            totalValue: totalValue,
            totalUnit: "\(unitWord) on the bar",
            totalAccessibilityLabel: totalLabel,
            summary: summary,
            headerAccessibilityLabel: "\(totalLabel). \(summary)",
            sceneAccessibilityValue: sceneAccessibilityValue(loadedPlates, unit: facts.unit, locale: locale),
            hint: hint(facts, loaded: loaded),
            allTitle: tray.isEmpty ? nil : "All \(tray.count)",
            allAccessibilityLabel: "Show all \(tray.count) plates",
            playAction: playAction(phase: facts.playPhase, storage: storage),
            sections: sections(facts.plates, unit: facts.unit, locale: locale),
            emptyTray: emptyTrayLine
        )
    }

    // MARK: Identical plates and groups

    /// The one definition of "identical": two plates with the same look are interchangeable
    /// copies (same tier, weight, engraving, progression tier and lift). The engraving is
    /// compared trimmed, with runs of spaces folded and case ignored, the way the plate face
    /// prints it in capitals.
    static func look(_ plate: CutRackPlateFacts) -> CutRackPlateLook {
        let engraving = plate.engraving
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .uppercased()
        return CutRackPlateLook(
            tierID: plate.tierID,
            tierName: plate.tierName,
            weightKg: plate.weightKg,
            engraving: engraving,
            progressionTier: plate.progressionTier,
            liftTypeID: BarbellPlateProgressionScope.normalizedLiftTypeID(plate.liftTypeID)
        )
    }

    static func areIdentical(_ a: CutRackPlateFacts, _ b: CutRackPlateFacts) -> Bool {
        look(a) == look(b)
    }

    /// An engraved plate (a milestone, a lift, a record) sits with the engraved plates; any
    /// other plate in its material's section.
    static func family(_ plate: CutRackPlateFacts) -> CutRackPlateFamily {
        look(plate).engraving.isEmpty ? plate.material : .engraved
    }

    /// The stored plates grouped by look. Order: family (engraved, metal, bumpers, iron), then
    /// heaviest, then rarest, then the bigger pile, then name, then the higher progression tier.
    /// Heaviest first because a heavy plate is what someone browsing to load the bar looks for,
    /// and within a family weight is the plain thing that tells similar plates apart. Inside a
    /// group, copies load in the legacy wall order (newest first).
    static func storageGroups(_ plates: [CutRackPlateFacts]) -> [CutRackPlateGroup] {
        let ordered = trayOrder(plates)
        var groups: [CutRackPlateLook: CutRackPlateGroup] = [:]
        var loadedByLook: [CutRackPlateLook: Int] = [:]
        for plate in ordered {
            let key = look(plate)
            if plate.isLoaded {
                loadedByLook[key, default: 0] += 1
            } else if groups[key] != nil {
                groups[key]?.stored.append(plate)
            } else {
                groups[key] = CutRackPlateGroup(look: key, family: family(plate), stored: [plate], loadedCount: 0)
            }
        }
        for key in groups.keys { groups[key]?.loadedCount = loadedByLook[key] ?? 0 }
        return groups.values.sorted(by: groupPrecedes)
    }

    private static func groupPrecedes(_ a: CutRackPlateGroup, _ b: CutRackPlateGroup) -> Bool {
        if a.family != b.family { return a.family < b.family }
        if a.look.weightKg != b.look.weightKg { return a.look.weightKg > b.look.weightKg }
        let rarityA = a.stored.first?.rarity ?? 0, rarityB = b.stored.first?.rarity ?? 0
        if rarityA != rarityB { return rarityA > rarityB }
        if a.stored.count != b.stored.count { return a.stored.count > b.stored.count }
        let nameA = name(a.stored[0]), nameB = name(b.stored[0])
        if nameA != nameB { return nameA < nameB }
        let rankA = BarbellPlateProgressionTier(rawValue: a.look.progressionTier)?.rank ?? 0
        let rankB = BarbellPlateProgressionTier(rawValue: b.look.progressionTier)?.rank ?? 0
        if rankA != rankB { return rankA > rankB }
        return a.look.key < b.look.key
    }

    /// The tray: "On the bar" (one tile per loaded plate, in bar order), then one section per
    /// family with a tile per look. Titles only when there is more than one section.
    static func sections(_ plates: [CutRackPlateFacts], unit: WeightUnit, locale: Locale) -> [CutRackModel.Section] {
        var sections: [CutRackModel.Section] = []
        let loaded = trayOrder(plates).filter(\.isLoaded)
        if !loaded.isEmpty {
            sections.append(.init(id: "bar", title: "On the bar", tiles: loaded.map { tile($0, unit: unit, locale: locale) }))
        }
        let groups = storageGroups(plates)
        for family in CutRackPlateFamily.allCases {
            let tiles = groups.filter { $0.family == family }.map { tile($0, unit: unit, locale: locale) }
            if !tiles.isEmpty { sections.append(.init(id: "family-\(family.rawValue)", title: family.title, tiles: tiles)) }
        }
        if sections.count == 1 { sections[0].title = nil }
        return sections
    }

    /// The plate a tap on a stored group loads: its first copy in load order.
    static func nextToLoad(_ group: CutRackPlateGroup) -> CutRackPlateFacts? {
        group.stored.first
    }

    // MARK: Play: drop them all

    static func playAction(phase: CutRackPlayPhase, storage: Int) -> CutRackModel.PlayAction? {
        switch phase {
        case .raining, .loose:
            return .init(title: "Tidy up", accessibilityLabel: "Tidy up",
                         accessibilityHint: "Clears the dropped plates from the floor. Nothing is taken off your bar.",
                         isTidy: true)
        case .idle:
            guard storage > 0 else { return nil }
            return .init(title: "Drop all", accessibilityLabel: "Drop all \(storage == 1 ? "1 stored plate" : "\(storage) stored plates")",
                         accessibilityHint: "Drops your stored plates onto the floor to play with. Drag one to a sleeve end to load it.",
                         isTidy: false)
        }
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
        if facts.playPhase != .idle { return "Drag a plate to a sleeve end to load it." }
        if loaded == 0 { return "Tap a plate below to load it." }
        return "Swipe the bar to drop the outer plate."
    }

    static func isBarFull(occupiedSlots: Int) -> Bool {
        occupiedSlots >= barCapacity
    }

    /// A loaded plate's tile: tapping it takes it off.
    static func tile(_ plate: CutRackPlateFacts, unit: WeightUnit, locale: Locale) -> CutRackModel.Tile {
        let weight = weight(plate.weightKg, unit: unit, locale: locale)
        return CutRackModel.Tile(
            id: plate.id,
            plateID: plate.id,
            weight: weight,
            isLoaded: plate.isLoaded,
            storedCount: plate.isLoaded ? 0 : 1,
            badge: nil,
            onBarCount: 0,
            accessibilityLabel: "\(name(plate)), \(spokenWeight(plate.weightKg, unit: unit, locale: locale)), \(status(plate))",
            accessibilityHint: plate.isLoaded ? "Takes it off the bar." : "Loads it onto the bar."
        )
    }

    /// A stored group's tile: tapping it loads its next copy.
    static func tile(_ group: CutRackPlateGroup, unit: WeightUnit, locale: Locale) -> CutRackModel.Tile {
        let first = group.stored[0]
        let count = group.stored.count
        let spoken = "\(name(first)), \(spokenWeight(first.weightKg, unit: unit, locale: locale))"
        var label = count == 1 ? "\(spoken), in storage" : "\(spoken), \(count) in storage"
        if group.loadedCount > 0 { label += ", \(group.loadedCount) on the bar" }
        return CutRackModel.Tile(
            id: "look:" + group.look.key,
            plateID: first.id,
            weight: weight(first.weightKg, unit: unit, locale: locale),
            isLoaded: false,
            storedCount: count,
            badge: count > 1 ? "×\(count)" : nil,
            onBarCount: group.loadedCount,
            accessibilityLabel: label,
            accessibilityHint: count == 1 ? "Loads it onto the bar." : "Loads one onto the bar."
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

// MARK: - Drop them all

/// Which stored plates fall into the room when the owner drops them all, and what VoiceOver
/// says once they have. The scene caps how many plates and distinct faces it shows at once
/// (RackPlateRain.limits); this picks within the caps.
enum CutRackRainLogic {
    /// Variety first: the first `maxLooks` looks in tray order (engraved, metal, bumpers, iron;
    /// heaviest first), one plate of each, then a second copy of each, and so on, up to `cap`.
    /// Plates already lying in the room (`exclude`) are skipped. Identical copies share a face,
    /// so the faces drawn never exceed `maxLooks`.
    static func selection(_ plates: [CutRackPlateFacts], cap: Int, maxLooks: Int, exclude: Set<String> = []) -> [String] {
        let groups = CutRackLogic.storageGroups(plates)
            .map { $0.stored.filter { !exclude.contains($0.id) } }
            .filter { !$0.isEmpty }
            .prefix(max(0, maxLooks))
        var picked: [String] = []
        var round = 0
        while picked.count < cap {
            var added = false
            for copies in groups where round < copies.count {
                picked.append(copies[round].id)
                added = true
                if picked.count == cap { break }
            }
            guard added else { break }
            round += 1
        }
        return picked
    }

    /// Read once when the plates have landed.
    static func announcement(dropped: Int, stored: Int) -> String {
        guard dropped > 0 else { return "No plates to drop." }
        let plates = dropped == 1 ? "1 plate" : "\(dropped) plates"
        if dropped < stored {
            return "Dropped \(plates) of \(stored) onto the floor. Drag one to a sleeve end to load it."
        }
        return "Dropped \(plates) onto the floor. Drag one to a sleeve end to load it."
    }

    static let tidyAnnouncement = "Floor tidied."
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
