//
//  CutRackModelRail.swift
//  WRKT
//
//  The rail tray of the Cut rack, as plain values: plates standing on edge on a steel floor rail
//  under the scene, one group per look (CutRackLogic.lookGroups, so the grouping, families and
//  order are the card tray's), the weight and count stamped on the rail under each group, a lime
//  dashed slot for each copy on the bar (or swinging onto it) and a white one for each copy lying
//  on the floor after "Drop all". Also the lifted plate (a group shown face on, with its load and
//  take-off actions), the readout that flashes over the scene when the load changes, the slim
//  footer line, and the switch between this tray and the card tray.
//

import Foundation

// MARK: - Switches

/// Which tray the rack shows under its scene: the card of tiles, or the storage rail. The rail
/// also hides the total at rest and flashes it when the load changes. Debug builds show the rail
/// unless VOLIA_RACK_TRAY=card; Release builds always show the card.
enum CutRackTrayStyle: String, Equatable, Sendable {
    case card
    case rail

    /// Launch-environment key that forces a style in debug builds: VOLIA_RACK_TRAY=card|rail.
    static let overrideKey = "VOLIA_RACK_TRAY"

    /// The rule, separated from the build flag so tests can pin both configurations.
    static func resolve(isDebugBuild: Bool, environment: [String: String]) -> CutRackTrayStyle {
        guard isDebugBuild else { return .card }
        if let raw = environment[overrideKey], let forced = CutRackTrayStyle(rawValue: raw) { return forced }
        return .rail
    }

    /// The style this build uses. Release compiles to `.card` without reading the environment.
    static var current: CutRackTrayStyle {
        #if DEBUG
        return resolve(isDebugBuild: true, environment: ProcessInfo.processInfo.environment)
        #else
        return .card
        #endif
    }
}

/// What a tap on a rail group does. `.preview` lifts the plate out face on and a second tap on
/// the same group (or the Load button) loads it; holding loads at once. `.load` loads on a tap,
/// as the card tray does, and holding lifts the plate out. VOLIA_RACK_RAIL_TAP=load|preview.
enum CutRackRailTap: String, Equatable, Sendable {
    case preview
    case load

    static let overrideKey = "VOLIA_RACK_RAIL_TAP"

    static func resolve(environment: [String: String]) -> CutRackRailTap {
        environment[overrideKey].flatMap(CutRackRailTap.init(rawValue:)) ?? .preview
    }

    static var current: CutRackRailTap {
        #if DEBUG
        return resolve(environment: ProcessInfo.processInfo.environment)
        #else
        return .preview
        #endif
    }
}

// MARK: - Facts

struct CutRackRailFacts {
    /// Earned plates only (no starter).
    var plates: [CutRackPlateFacts]
    var unit: WeightUnit
    var notice: CutRackNotice?
    var playPhase: CutRackPlayPhase = .idle
    /// Plates a tap has started swinging onto the bar and that are not saved yet: they have left
    /// the rail already.
    var inFlight: Set<String> = []
    /// Stored plates lying in the room after "Drop all": their slots on the rail stand empty.
    var onFloor: Set<String> = []
    var tap: CutRackRailTap = .preview
}

// MARK: - Model

struct CutRackRailModel: Equatable {
    struct Group: Identifiable, Equatable {
        /// "look:" and the look's key, stable while copies come and go.
        var id: String
        var section: String
        /// The plate the group's art and details stand for.
        var plateID: String
        var tierID: Int
        var tierName: String
        /// The engraving as the plate carries it, empty when none.
        var engraving: String
        var weightKg: Double
        /// The stored copy a load takes (the legacy wall order), nil when none is in the rack.
        var nextToLoad: String?
        /// The outermost copy of this look on the bar, which "Take off" removes.
        var nextToUnload: String?
        /// Copies standing in the rack now.
        var stored: Int
        /// Copies on the bar or swinging onto it.
        var loaded: Int
        /// Copies lying on the floor after "Drop all".
        var onFloor: Int
        /// Plates drawn standing (stored copies, capped so a pile stays short).
        var platesShown: Int
        /// Lime dashed slots drawn, one per loaded copy.
        var loadedSlots: Int
        /// White dashed slots drawn, one per copy on the floor (capped).
        var floorSlots: Int
        /// The weight stamped on the rail: "20", "2.5".
        var numeral: String
        /// "×12" stamped beside the numeral when more than one copy stands in the rack.
        var count: String?
        /// The tier name, or the engraving when the plate has one.
        var name: String
        /// "Red Bumper, 20 kilograms, 10 in storage, 2 on the bar"
        var accessibilityLabel: String
    }

    struct Section: Identifiable, Equatable {
        var id: String
        /// "Bumpers", stamped small over the section; nil when the rail has one section only.
        var title: String?
        var groups: [Group]
    }

    var sections: [Section]
    /// The unit stamped once at the rail's start: "kg".
    var unit: String
    /// The footer's line: "87 in storage", "16 on the floor".
    var status: String
    /// One quiet line, shown over the scene's top edge; nil when there is nothing to say.
    var hint: String?
    /// Shown instead of the rail when no plate has been earned.
    var emptyRail: String?

    var groups: [Group] { sections.flatMap(\.groups) }

    func group(_ id: String) -> Group? { groups.first { $0.id == id } }
}

/// The plate lifted out of the rail, shown face on.
struct CutRackRailPreviewModel: Equatable {
    var groupID: String
    /// "Rose Gold"
    var title: String
    /// "75 WORKOUTS", nil when the plate has no engraving.
    var engraving: String?
    /// "25 kg"
    var weight: String
    /// "10 in storage, 2 on the bar"
    var counts: String
    /// "Load onto the bar", "The bar is full"; nil when no copy is in the rack.
    var loadTitle: String?
    var canLoad: Bool
    /// "Take off the bar" when a copy is on the bar.
    var unloadTitle: String?
    var accessibilityLabel: String
}

/// The short readout over the scene when the load changes: "+40", "190", "kg on the bar".
struct CutRackReadoutFlash: Equatable {
    var delta: String
    var total: String
    var unit: String
    /// "Added 40 kilograms. 190 kilograms on the bar"
    var accessibilityLabel: String
}

// MARK: - Logic

enum CutRackRailLogic {
    /// Standing plates drawn per group; the count stamp says how many there are.
    static let maxPlatesShown = 6
    /// Floor slots drawn per group.
    static let maxFloorSlots = 4

    static func model(_ facts: CutRackRailFacts, locale: Locale = .current) -> CutRackRailModel {
        let plates = facts.plates.map { plate -> CutRackPlateFacts in
            var plate = plate
            if facts.inFlight.contains(plate.id) { plate.isLoaded = true }
            return plate
        }
        let groups = CutRackLogic.lookGroups(plates)
        var sections: [CutRackRailModel.Section] = []
        for family in CutRackPlateFamily.allCases {
            let members = groups.filter { $0.family == family }
                .map { group($0, section: "family-\(family.rawValue)", onFloor: facts.onFloor, unit: facts.unit, locale: locale) }
            if !members.isEmpty {
                sections.append(.init(id: "family-\(family.rawValue)", title: family.title, groups: members))
            }
        }
        if sections.count == 1 { sections[0].title = nil }
        let stored = plates.filter { !$0.isLoaded && !facts.onFloor.contains($0.id) }.count
        let floor = plates.filter { !$0.isLoaded && facts.onFloor.contains($0.id) }.count
        return CutRackRailModel(
            sections: sections,
            unit: facts.unit.rawValue,
            status: status(stored: stored, onFloor: floor, phase: facts.playPhase),
            hint: hint(facts, loaded: plates.filter(\.isLoaded).count),
            emptyRail: plates.isEmpty ? CutRackLogic.emptyTrayLine : nil
        )
    }

    static func group(_ group: CutRackPlateGroup, section: String, onFloor: Set<String>, unit: WeightUnit,
                      locale: Locale) -> CutRackRailModel.Group {
        let first = group.representative ?? group.stored[0]
        let inRack = group.stored.filter { !onFloor.contains($0.id) }
        let floor = group.stored.count - inRack.count
        let stored = inRack.count
        let loaded = group.loaded.count
        let spoken = "\(CutRackLogic.name(first)), \(CutRackLogic.spokenWeight(first.weightKg, unit: unit, locale: locale))"
        var parts: [String] = [spoken]
        if stored > 0 { parts.append(stored == 1 && loaded == 0 && floor == 0 ? "in storage" : "\(stored) in storage") }
        if loaded > 0 { parts.append(loaded == 1 && stored == 0 ? "on the bar" : "\(loaded) on the bar") }
        if floor > 0 { parts.append("\(floor) on the floor") }
        return CutRackRailModel.Group(
            id: "look:" + group.look.key,
            section: section,
            plateID: first.id,
            tierID: first.tierID,
            tierName: first.tierName,
            engraving: first.engraving.trimmingCharacters(in: .whitespacesAndNewlines),
            weightKg: first.weightKg,
            nextToLoad: inRack.first?.id,
            nextToUnload: group.loaded.last?.id,
            stored: stored,
            loaded: loaded,
            onFloor: floor,
            platesShown: min(stored, maxPlatesShown),
            loadedSlots: min(loaded, CutRackLogic.barCapacity),
            floorSlots: min(floor, maxFloorSlots),
            numeral: CutRackLogic.number(unit.displayValue(first.weightKg), locale: locale),
            count: stored > 1 ? "×\(stored)" : nil,
            name: CutRackLogic.name(first),
            accessibilityLabel: parts.joined(separator: ", ")
        )
    }

    /// "87 in storage"; "16 on the floor" while dropped plates lie in the room.
    static func status(stored: Int, onFloor: Int, phase: CutRackPlayPhase) -> String {
        if phase != .idle, onFloor > 0 { return "\(onFloor) on the floor" }
        return stored == 0 ? "Nothing in storage" : "\(stored) in storage"
    }

    /// The card tray's notices, and a first hint that says what a tap on the rail does.
    static func hint(_ facts: CutRackRailFacts, loaded: Int) -> String? {
        switch facts.notice {
        case .barFull: return "The bar is full. Take a plate off first."
        case .loadFailed: return "That plate could not be loaded. Try again."
        case nil: break
        }
        if facts.plates.isEmpty { return nil }
        if facts.playPhase != .idle { return "Drag a plate to a sleeve end to load it." }
        guard loaded == 0 else { return nil }
        switch facts.tap {
        case .preview: return "Tap a plate on the rack to lift it out."
        case .load: return "Tap a plate on the rack to load it."
        }
    }

    // MARK: Lifted plate

    static func preview(_ group: CutRackRailModel.Group, barIsFull: Bool, unit: WeightUnit,
                        locale: Locale = .current) -> CutRackRailPreviewModel {
        var counts: [String] = []
        if group.stored > 0 { counts.append("\(group.stored) in storage") }
        if group.loaded > 0 { counts.append("\(group.loaded) on the bar") }
        if group.onFloor > 0 { counts.append("\(group.onFloor) on the floor") }
        let weight = CutRackLogic.weight(group.weightKg, unit: unit, locale: locale)
        let engraving = group.engraving.isEmpty ? nil : group.engraving.uppercased()
        let canLoad = group.nextToLoad != nil && !barIsFull
        let loadTitle: String? = group.nextToLoad == nil ? nil : (barIsFull ? "The bar is full" : "Load onto the bar")
        var label = "\(group.tierName), \(CutRackLogic.spokenWeight(group.weightKg, unit: unit, locale: locale))"
        if engraving != nil { label = "\(group.engraving), \(label)" }
        if !counts.isEmpty { label += ", " + counts.joined(separator: ", ") }
        return CutRackRailPreviewModel(
            groupID: group.id,
            title: group.tierName,
            engraving: engraving,
            weight: weight,
            counts: counts.isEmpty ? "None left" : counts.joined(separator: ", "),
            loadTitle: loadTitle,
            canLoad: canLoad,
            unloadTitle: group.nextToUnload == nil ? nil : "Take off the bar",
            accessibilityLabel: label
        )
    }

    /// Whether the bar has no free slot, counting loads still in flight.
    static func isBarFull(occupiedSlots: Int, inFlight: Int) -> Bool {
        CutRackLogic.isBarFull(occupiedSlots: occupiedSlots + inFlight)
    }

    // MARK: Taps

    /// What a tap or a hold on a rail group does.
    enum Outcome: Equatable {
        /// Lift the group out and show it face on.
        case lift(String)
        /// Put the lifted plate back.
        case close
        /// Load this plate (CutRackTap: the plate leaves the rail and swings in).
        case load(String)
        /// Take this plate off the bar.
        case unload(String)
    }

    /// `.preview`: the first tap lifts the group out, a second tap on the lifted group loads its
    /// next copy (tap, tap on the same spot is the fast path), or puts it back when none is left.
    /// `.load`: a tap loads the next copy, or takes one off when every copy is on the bar.
    static func tap(_ group: CutRackRailModel.Group, lifted: String?, mode: CutRackRailTap) -> Outcome {
        switch mode {
        case .preview:
            guard lifted == group.id else { return .lift(group.id) }
            return group.nextToLoad.map(Outcome.load) ?? .close
        case .load:
            if let next = group.nextToLoad { return .load(next) }
            if let off = group.nextToUnload { return .unload(off) }
            return .lift(group.id)
        }
    }

    /// Holding always lifts the plate out (in `.load` mode it is the only way to see its face).
    static func hold(_ group: CutRackRailModel.Group) -> Outcome {
        .lift(group.id)
    }

    // MARK: Readout flash

    /// The readout for a change of the total, in the user's unit; nil when the shown total did
    /// not change.
    static func flash(fromKg: Double, toKg: Double, unit: WeightUnit, locale: Locale = .current) -> CutRackReadoutFlash? {
        let from = unit.displayValue(fromKg), to = unit.displayValue(toKg)
        let delta = to - from
        let deltaText = CutRackLogic.number(abs(delta), locale: locale)
        guard deltaText != CutRackLogic.number(0, locale: locale) else { return nil }
        let total = CutRackLogic.number(to, locale: locale)
        let spokenUnit = CutRackLogic.spokenUnit(unit)
        return CutRackReadoutFlash(
            delta: (delta > 0 ? "+" : "\u{2212}") + deltaText,
            total: total,
            unit: "\(unit.rawValue) on the bar",
            accessibilityLabel: "\(delta > 0 ? "Added" : "Took off") \(deltaText) \(spokenUnit). \(total) \(spokenUnit) on the bar"
        )
    }

    /// How long the readout stays before it fades.
    static let flashDuration: Duration = .milliseconds(1600)
}
