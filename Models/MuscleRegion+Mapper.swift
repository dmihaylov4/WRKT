//
//  MuscleRegion.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 09.10.25.
//


// MuscleRegion+Mapper.swift
// WRKT

import Foundation

// MARK: - Regions your pictogram knows how to paint
public enum MuscleRegion: Hashable {
    // Front/upper
    case shoulders
    case chestUpper, chestMid, chestLower
    case biceps, triceps, forearms
    case abs, obliques

    // Back
    case trapsRear, lats, midBack, lowerBack

    // Lower body
    case glutes, quads, hamstrings, calves
    case adductors, abductors
}

// MARK: - Highlights (primary + secondary) the row consumes
enum MuscleIconMapper {
    struct Highlights {
        let primary: Set<MuscleRegion>
        let secondary: Set<MuscleRegion>
    }

    /// Public entry point the row uses.
    static func highlights(for ex: Exercise) -> Highlights {
        var prim = Set<MuscleRegion>()
        var sec  = Set<MuscleRegion>()

        // 1) Map declared muscles
        for m in ex.primaryMuscles { prim.formUnion(map(m, exName: ex.name, tags: ex.subregionTags)) }
        for m in ex.secondaryMuscles { sec.formUnion(map(m, exName: ex.name, tags: ex.subregionTags)) }

        // 2) If still empty, infer from category + name + deep tags
        if prim.isEmpty {
            prim.formUnion(inferFromCategory(ex.category, name: ex.name, tags: ex.subregionTags))
        }

        // 3) Ensure upper/mid/lower chest from tags if chest-related
        if isChest(ex) {
            let chest = chestRegions(ex)
            if !chest.isEmpty { prim.formUnion(chest) }
        }

        // 4) Back deep layers
        if isBack(ex) {
            let back = backRegions(ex)
            if !back.isEmpty { prim.formUnion(back) }
        }

        // 5) Sanity fallback (so the pictogram never looks empty)
        if prim.isEmpty {
            // Bias towards the category
            switch ex.category.lowercased() {
            case "chest": prim.insert(.chestMid)
            case "back":  prim.insert(.lats)
            case "shoulders": prim.insert(.shoulders)
            case "biceps": prim.insert(.biceps)
            case "triceps": prim.insert(.triceps)
            case "forearms": prim.insert(.forearms)
            case "abs": prim.insert(.abs)
            case "obliques": prim.insert(.obliques)
            case "glutes": prim.insert(.glutes)
            case "quads": prim.insert(.quads)
            case "hamstrings": prim.insert(.hamstrings)
            case "calves": prim.insert(.calves)
            case "adductors": prim.insert(.adductors)
            case "abductors": prim.insert(.abductors)
            default: break
            }
        }

        // Avoid promoting a primary into secondary again
        sec.subtract(prim)
        return Highlights(primary: prim, secondary: sec)
    }

    // MARK: - Mappers

    private static func map(_ raw: String, exName: String, tags: [String]) -> Set<MuscleRegion> {
        let s = raw.lowercased()
        var out = Set<MuscleRegion>()

        // Upper body
        if s.containsOne(of: ["shoulder","deltoid","delts"]) { out.insert(.shoulders) }
        if s.containsOne(of: ["bicep","biceps"]) { out.insert(.biceps) }
        if s.containsOne(of: ["tricep","triceps"]) { out.insert(.triceps) }
        if s.containsOne(of: ["forearm","brachioradialis","flexor","extensor"]) { out.insert(.forearms) }
        if s.containsOne(of: ["abs","abdominals","rectus"]) { out.insert(.abs) }
        if s.contains("oblique") { out.insert(.obliques) }

        // Chest — prefer deep tags if present
        if s.containsOne(of: ["chest","pec","pectoralis"]) {
            let deep = chestRegions(name: exName, tags: tags)
            if deep.isEmpty { out.insert(.chestMid) } else { out.formUnion(deep) }
        }

        // Back — deep split
        if s.containsOne(of: ["back","lat","lats","latissimus","trap","trapezius","rhomboid","rear delt"]) {
            let deep = backRegions(name: exName, tags: tags)
            if deep.isEmpty { out.insert(.lats) } else { out.formUnion(deep) }
        }

        // Lower body
        if s.containsOne(of: ["glute","gluteus"]) { out.insert(.glutes) }
        if s.containsOne(of: ["quad","quadriceps","vastus","rectus femoris"]) { out.insert(.quads) }
        if s.containsOne(of: ["hamstring","biceps femoris","semitendinosus","semimembranosus"]) { out.insert(.hamstrings) }
        if s.containsOne(of: ["calf","gastrocnemius","soleus"]) { out.insert(.calves) }
        if s.containsOne(of: ["adductor","inner thigh"]) { out.insert(.adductors) }
        if s.containsOne(of: ["abductor","outer thigh","glute medius","glute minimus"]) { out.insert(.abductors) }

        return out
    }

    private static func inferFromCategory(_ cat: String, name: String, tags: [String]) -> Set<MuscleRegion> {
        let c = cat.lowercased()
        switch c {
        case "chest": return chestRegions(name: name, tags: tags).ifEmpty(.chestMid)
        case "back":  return backRegions(name: name, tags: tags).ifEmpty(.lats)
        case "shoulders": return [.shoulders]
        case "biceps": return [.biceps]
        case "triceps": return [.triceps]
        case "forearms": return [.forearms]
        case "abs": return [.abs]
        case "obliques": return [.obliques]
        case "glutes": return [.glutes]
        case "quads": return [.quads]
        case "hamstrings": return [.hamstrings]
        case "calves": return [.calves]
        case "adductors": return [.adductors]
        case "abductors": return [.abductors]
        default: return []
        }
    }

    // MARK: - Chest deep helpers
    private static func chestRegions(_ ex: Exercise) -> Set<MuscleRegion> {
        chestRegions(name: ex.name, tags: ex.subregionTags)
    }
    private static func chestRegions(name: String, tags: [String]) -> Set<MuscleRegion> {
        let n = name.lowercased()
        var out = Set<MuscleRegion>()
        if tags.contains(where: { $0.lowercased().contains("upper chest") }) || n.contains("incline") || n.contains("clavicular") {
            out.insert(.chestUpper)
        }
        if tags.contains(where: { $0.lowercased().contains("mid chest") }) || n.contains("flat") || n.contains("bench") || n.contains("fly") || n.contains("press") {
            out.insert(.chestMid)
        }
        if tags.contains(where: { $0.lowercased().contains("lower chest") }) || n.contains("decline") || n.contains("dip") {
            out.insert(.chestLower)
        }
        return out
    }
    private static func isChest(_ ex: Exercise) -> Bool {
        ex.category.lowercased() == "chest" ||
        (ex.primaryMuscles + ex.secondaryMuscles).joined(separator: " ").lowercased().containsOne(of: ["chest","pec","pectoralis"])
    }

    // MARK: - Back deep helpers
    private static func backRegions(_ ex: Exercise) -> Set<MuscleRegion> {
        backRegions(name: ex.name, tags: ex.subregionTags)
    }
    private static func backRegions(name: String, tags: [String]) -> Set<MuscleRegion> {
        let n = name.lowercased()
        var out = Set<MuscleRegion>()
        if tags.contains(where: { $0.lowercased().contains("lats") }) || n.containsOne(of: ["lat","pulldown","pull-up","pullup","chin-up","row"]) {
            out.insert(.lats)
        }
        if tags.contains(where: { $0.lowercased().contains("mid-back") }) || n.containsOne(of: ["rhomboid","seated row","t-bar","retraction","row"]) {
            out.insert(.midBack)
        }
        if tags.contains(where: { $0.lowercased().contains("lower back") }) || n.containsOne(of: ["roman chair","hyperextension","back extension","good morning"]) {
            out.insert(.lowerBack)
        }
        if tags.contains(where: { $0.lowercased().contains("trap") || $0.lowercased().contains("rear") || $0.lowercased().contains("delt") }) || n.containsOne(of: ["shrug","face pull","upright row","rear delt"]) {
            out.insert(.trapsRear)
        }
        return out
    }
    private static func isBack(_ ex: Exercise) -> Bool {
        ex.category.lowercased() == "back" ||
        (ex.primaryMuscles + ex.secondaryMuscles).joined(separator: " ").lowercased().containsOne(of: ["back","lat","lats","latissimus","trap","trapezius","rhomboid"])
    }
}

// MARK: - Tiny helpers

private extension String {
    func containsOne(of needles: [String]) -> Bool {
        let hay = self.lowercased()
        for n in needles where hay.contains(n) { return true }
        return false
    }
}

private extension Set where Element == MuscleRegion {
    func ifEmpty(_ fallback: MuscleRegion) -> Set<MuscleRegion> {
        isEmpty ? [fallback] : self
    }
}
