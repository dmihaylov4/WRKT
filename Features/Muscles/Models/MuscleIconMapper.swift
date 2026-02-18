//
//  MuscleIconMapper.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 18.10.25.
//


//
//  MuscleIconMapper.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 09.10.25.
//


import Foundation

enum MuscleIconMapper {
    struct Highlights {
        let primary: Set<MuscleRegion>
        let secondary: Set<MuscleRegion>
    }

    static func highlights(for ex: Exercise) -> Highlights {
        let nameLC = ex.name.lowercased()
        // Separate primary+secondary from tertiary to maintain muscle priority
        let primarySecondaryLC = (ex.primaryMuscles + ex.secondaryMuscles).map { $0.lowercased() }
        let tertiaryLC = ex.tertiaryMuscles.map { $0.lowercased() }
        let allMusclesLC = primarySecondaryLC + tertiaryLC

        // Start with empty
        var primary = Set<MuscleRegion>()
        var secondary = Set<MuscleRegion>()

        // --- CHEST (use your subregionTags if present) ---
        if ex.category.contains("chest") || primarySecondaryLC.contains(where: { $0.contains("pec") || $0.contains("chest") }) || nameLC.contains("bench") || nameLC.contains("fly") {
            if ex.subregionTags.contains("Upper Chest") || nameLC.contains("incline") || nameLC.contains("clavicular") {
                primary.insert(.chestUpper)
            } else if ex.subregionTags.contains("Lower Chest") || nameLC.contains("decline") || nameLC.contains("dip") {
                primary.insert(.chestLower)
            } else {
                primary.insert(.chestMid)
            }
        }

        // SHOULDERS
        // Check for any deltoid/shoulder involvement first
        let hasAnyDeltoid = ex.category.contains("shoulder") || primarySecondaryLC.contains(where: { $0.contains("deltoid") || $0 == "shoulder" })

        if hasAnyDeltoid {
            // Check for specific deltoid heads in ALL muscle arrays (primary, secondary, tertiary)
            let hasAnterior = allMusclesLC.contains(where: { $0.contains("anterior deltoid") })
            let hasLateral = allMusclesLC.contains(where: { $0.contains("lateral deltoid") })
            let hasPosterior = allMusclesLC.contains(where: { $0.contains("posterior deltoid") || $0.contains("rear delt") })

            // If specific deltoid heads are mentioned, only those get primary highlighting
            // Otherwise, mark all shoulders as primary (generic shoulder exercise)
            if hasAnterior || hasLateral || hasPosterior {
                // Specific deltoid heads mentioned - more targeted coloring
                primary.insert(.shoulders)
            } else {
                // Generic "shoulder" or "deltoid" - color everything
                primary.insert(.shoulders)
            }
        }

        // BICEPS / TRICEPS / FOREARMS (name or muscles)
        if nameLC.contains("bicep") || primarySecondaryLC.contains(where: { $0.contains("bicep") }) { primary.insert(.biceps) }
        if nameLC.contains("tricep") || primarySecondaryLC.contains(where: { $0.contains("tricep") }) { primary.insert(.triceps) }
        if nameLC.contains("forearm") || primarySecondaryLC.contains(where: { $0.contains("brachioradialis") || $0.contains("forearm") }) { primary.insert(.forearms) }

        // ABS / OBLIQUES
        if nameLC.contains("abs") || primarySecondaryLC.contains(where: { $0.contains("rectus abdominis") || $0 == "abs" }) { primary.insert(.abs) }
        if nameLC.contains("oblique") || primarySecondaryLC.contains(where: { $0.contains("oblique") }) { primary.insert(.obliques) }

        // BACK (lats / mid / lower / traps-rear)
        if ex.category.contains("back") || primarySecondaryLC.contains(where: { $0.contains("lat") || $0.contains("back") || $0.contains("trap") || $0.contains("rhomboid") }) {
            if nameLC.contains("pulldown") || nameLC.contains("pull-up") || nameLC.contains("chin") || nameLC.contains("lat") {
                primary.insert(.lats)
            }
            if nameLC.contains("row") || nameLC.contains("t-bar") || nameLC.contains("seated row") || nameLC.contains("retraction") || primarySecondaryLC.contains(where: { $0.contains("rhomboid") }) {
                primary.insert(.midBack)
            }
            if nameLC.contains("hyperextension") || nameLC.contains("good morning") || nameLC.contains("back extension") {
                primary.insert(.lowerBack)
            }
            if nameLC.contains("shrug") || nameLC.contains("face pull") || nameLC.contains("rear delt") || nameLC.contains("upright row") || primarySecondaryLC.contains(where: { $0.contains("trap") }) {
                primary.insert(.trapsRear)
            }
        }

        // LOWER BODY
        if nameLC.contains("glute") || primarySecondaryLC.contains(where: { $0.contains("glute") }) { primary.insert(.glutes) }
        if nameLC.contains("quad") || primarySecondaryLC.contains(where: { $0.contains("quad") || $0.contains("vastus") || $0.contains("rectus femoris") }) { primary.insert(.quads) }
        if nameLC.contains("hamstring") || primarySecondaryLC.contains(where: { $0.contains("hamstring") || $0.contains("biceps femoris") }) { primary.insert(.hamstrings) }
        if nameLC.contains("calf") || primarySecondaryLC.contains(where: { $0.contains("gastrocnemius") || $0.contains("soleus") }) { primary.insert(.calves) }
        if nameLC.contains("adductor") || primarySecondaryLC.contains(where: { $0.contains("adductor") }) { primary.insert(.adductors) }
        if nameLC.contains("abductor") || nameLC.contains("glute med") || primarySecondaryLC.contains(where: { $0.contains("abductor") || $0.contains("glute med") || $0.contains("glute minimus") }) { primary.insert(.abductors) }

        // Secondary: if nothing detected at all, leave empty. Otherwise, add some reasonable companions:
        // (This keeps the pictogram informative without being noisy.)
        if primary.contains(.chestUpper) || primary.contains(.chestMid) || primary.contains(.chestLower) {
            secondary.formUnion([.shoulders, .triceps])
        }
        if primary.contains(.biceps) { secondary.insert(.forearms) }
        if primary.contains(.triceps) { secondary.insert(.shoulders) }
        if primary.contains(.lats) || primary.contains(.midBack) { secondary.formUnion([.biceps, .trapsRear]) }
        if primary.contains(.quads) { secondary.formUnion([.adductors, .abductors]) }
        if primary.contains(.hamstrings) { secondary.insert(.glutes) }
        if primary.contains(.calves) { /* nothing extra */ }

        // Add tertiary muscles as secondary highlights (if not already in primary)
        // This ensures muscles like "Anterior Deltoids" in tertiary still get highlighted
        if tertiaryLC.contains(where: { $0.contains("deltoid") || $0 == "shoulder" }) && !primary.contains(.shoulders) {
            secondary.insert(.shoulders)
        }
        if tertiaryLC.contains(where: { $0.contains("tricep") }) && !primary.contains(.triceps) {
            secondary.insert(.triceps)
        }
        if tertiaryLC.contains(where: { $0.contains("bicep") }) && !primary.contains(.biceps) {
            secondary.insert(.biceps)
        }
        if tertiaryLC.contains(where: { $0.contains("pec") || $0.contains("chest") }) {
            if !primary.contains(.chestUpper) && !primary.contains(.chestMid) && !primary.contains(.chestLower) {
                secondary.insert(.chestMid)  // Default to mid chest
            }
        }
        if tertiaryLC.contains(where: { $0.contains("lat") }) && !primary.contains(.lats) {
            secondary.insert(.lats)
        }
        if tertiaryLC.contains(where: { $0.contains("trap") }) && !primary.contains(.trapsRear) {
            secondary.insert(.trapsRear)
        }
        if tertiaryLC.contains(where: { $0.contains("glute") }) && !primary.contains(.glutes) {
            secondary.insert(.glutes)
        }
        if tertiaryLC.contains(where: { $0.contains("quad") || $0.contains("rectus femoris") }) && !primary.contains(.quads) {
            secondary.insert(.quads)
        }
        if tertiaryLC.contains(where: { $0.contains("hamstring") || $0.contains("biceps femoris") }) && !primary.contains(.hamstrings) {
            secondary.insert(.hamstrings)
        }

        // Prevent overlap: primary wins
        secondary.subtract(primary)
        return Highlights(primary: primary, secondary: secondary)
    }
}
