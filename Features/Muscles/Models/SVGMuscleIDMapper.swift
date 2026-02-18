// SVGMuscleIDMapper.swift
import Foundation

enum SVGMuscleIDMapper {
    /// Map one region -> (frontIDs, backIDs) in your SVGs.
    static func ids(for region: MuscleRegion) -> (front: [String], back: [String]) {
        switch region {
        case .chestUpper: return (["pec_major_clav_left","pec_major_clav_right"], [])
        case .chestMid:   return (["pec_major_stern_left","pec_major_stern_right"], [])
        case .chestLower: return (["pec_major_costal_left","pec_major_costal_right"], [])

        case .shoulders:  return (["deltoid-anterior","deltoid-lateral"],
                                  ["deltoid-lateral","deltoid-posterior"])
        case .biceps:     return (["biceps_left","biceps_right"], [])
        case .triceps:    return ([], ["triceps_left","triceps_right","triceps-lateral-R", "triceps"])
        case .forearms:   return (["forearm_left","forearm_right"], ["forearm_ext_left","forearm_ext_right"])

        case .abs:        return (["rectus_abdominis"], [])
        case .obliques:   return (["ext_oblique_left","ext_oblique_right"], [])

        case .lats:       return ([], ["lat_left","lat_right"])
        case .midBack:    return ([], ["rhomboids_left","rhomboids_right"])
        case .lowerBack:  return ([], ["erector_spinae"])
        case .trapsRear:  return ([], ["trapezius"])

        case .glutes:     return ([], ["glute_left","glute_right"])
        case .quads:      return (["quads_left","quads_right"], [])
        case .hamstrings: return ([], ["ham_left","ham_right"])
        case .calves:     return (["tibialis_ant_left","tibialis_ant_right"],
                                  ["calf_left_back","calf_right_back"])
        case .adductors:  return (["adductors_left","adductors_right"], [])
        case .abductors:  return (["abductors_left","abductors_right"], [])
        }
    }

    /// Merge many regions while preventing secondary from overriding primary.
    static func mergedIDs(primary: Set<MuscleRegion>, secondary: Set<MuscleRegion>)
        -> (frontPrimary: [String], backPrimary: [String], frontSecondary: [String], backSecondary: [String])
    {
        var fp = Set<String>(), bp = Set<String>(), fs = Set<String>(), bs = Set<String>()

        for r in primary {
            let (f, b) = ids(for: r)
            fp.formUnion(f)
            bp.formUnion(b)
        }
        for r in secondary {
            let (f, b) = ids(for: r)
            fs.formUnion(Set(f).subtracting(fp)) // ← convert to Set first
            bs.formUnion(Set(b).subtracting(bp))
        }
        return (Array(fp), Array(bp), Array(fs), Array(bs))
    }
}
