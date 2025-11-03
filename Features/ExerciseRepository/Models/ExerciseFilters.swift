//
//  ExerciseFilters.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//

// ExerciseFilters.swift
import SwiftUI

// Buckets.swift
import SwiftUI

enum EquipBucket: String, CaseIterable {
    case all = "All"
    case barbell = "Barbell"
    case bodyweight = "Bodyweight"
    case cable = "Cable"
    case dumbbell = "Dumbbell"
    case ezBar = "EZ Bar"
    case kettlebell = "Kettlebell"
    case pullupbar = "Pullup Bar"
    case other = "Other"

    // Note: This matches function is no longer used for filtering - use Exercise.equipBucket instead
    // Keeping for backward compatibility with .other case
    func matches(_ equipment: String?) -> Bool {
        guard self != .all else { return true }
        let e = (equipment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .barbell:     return e.contains("barbell") && !e.contains("ez")
        case .bodyweight:  return e.isEmpty || e == "none" || e.contains("bodyweight") || e.contains("body weight")
        case .cable:       return e.contains("cable")
        case .dumbbell:    return e.contains("dumbbell")
        case .ezBar:       return e.contains("ez bar") || e.contains("ez-bar") || e.contains("ezbar")
        case .kettlebell:  return e.contains("kettlebell")
        case .pullupbar:   return e.contains("pullup") || e.contains("pull-up") || e.contains("pull up") || e.contains("pull up bar")
        case .other:       return !EquipBucket.allCases.dropFirst().contains(where: { $0.matches(equipment) })
        case .all:         return true
        }
    }
}

enum MoveBucket: String, CaseIterable {
    case all = "All"
    case push = "Push"
    case pull = "Pull"
    case hinge = "Hinge"
    case squat = "Squat"
    case core = "Core"
    case other = "Other"

    // Movement pattern classification based on force type and exercise characteristics
    func matches(_ ex: Exercise) -> Bool {
        guard self != .all else { return true }
        let f = (ex.force ?? "").lowercased()
        let m = (ex.mechanic ?? "").lowercased()
        let name = ex.name.lowercased()
        let prim = ex.primaryMuscles.map { $0.lowercased() }

        switch self {
        case .push:
            return f.contains("push")
        case .pull:
            return f.contains("pull")
        case .hinge:
            // Hip-dominant movements: deadlifts, RDLs, good mornings, hip thrusts
            return name.contains("deadlift") || name.contains("rdl") ||
                   name.contains("romanian") || name.contains("good morning") ||
                   name.contains("hip thrust") || name.contains("glute bridge") ||
                   (prim.contains(where: { $0.contains("glute") || $0.contains("hamstring") }) &&
                    !name.contains("curl") && !name.contains("leg curl"))
        case .squat:
            // Knee-dominant movements: squats, lunges, leg press
            return name.contains("squat") || name.contains("lunge") ||
                   name.contains("leg press") || name.contains("step up") ||
                   name.contains("split squat") || name.contains("bulgarian")
        case .core:
            // Core stability and anti-rotation
            return prim.contains(where: { $0.contains("abs") || $0.contains("oblique") || $0.contains("abdominal") }) ||
                   name.contains("plank") || name.contains("crunch") ||
                   name.contains("sit-up") || name.contains("ab") ||
                   name.contains("pallof") || name.contains("dead bug")
        case .other:
            return !MoveBucket.push.matches(ex) &&
                   !MoveBucket.pull.matches(ex) &&
                   !MoveBucket.hinge.matches(ex) &&
                   !MoveBucket.squat.matches(ex) &&
                   !MoveBucket.core.matches(ex)
        case .all:
            return true
        }
    }
}

// Exercise+Extensions.swift

extension Exercise {

    // MARK: - DTO mapping

    init(from dto: ExcelExerciseDTO) {
        let category = (
            dto.primaryClassification?.trimmedOrNil ??
            dto.targetMuscleGroup?.trimmedOrNil ??
            "general"
        ).lowercased()

        var prim: [String] = []
        if let pm = dto.primeMover?.trimmedOrNil { prim.append(pm) }
        if prim.isEmpty, let t = dto.targetMuscleGroup?.trimmedOrNil { prim.append(t) }

        var sec: [String] = []
        if let s1 = dto.secondaryMuscle?.trimmedOrNil { sec.append(s1) }

        var tert: [String] = []
        if let s2 = dto.tertiaryMuscle?.trimmedOrNil  { tert.append(s2) }

        self.id = dto.id
        self.name = dto.exercise
        self.force = dto.forceType?.trimmedOrNil
        self.level = dto.difficulty?.trimmedOrNil
        self.mechanic = dto.mechanics?.trimmedOrNil
        self.equipment = dto.primaryEquipment?.trimmedOrNil
        self.secondaryEquipment = dto.secondaryEquipment?.trimmedOrNil
        self.grip = dto.grip?.trimmedOrNil
        self.primaryMuscles = prim
        self.secondaryMuscles = sec
        self.tertiaryMuscles = tert
        self.instructions = []
        self.images = nil
        self.category = category
        self.subregionTags = []

        // MARK: - Multi-Modal Tracking Support
        self.trackingMode = dto.trackingMode?.trimmedOrNil ?? "weighted"
        self.defaultDurationSeconds = dto.defaultDurationSeconds
        self.recommendedRestSeconds = dto.recommendedRestSeconds
    }

    /// Canonical difficulty from `level`
    var difficultyLevel: DifficultyLevel? { DifficultyLevel(level) }

    // MARK: - Normalization helpers

    private var _equipLC: String {
        (equipment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var _secondaryEquipLC: String {
        (secondaryEquipment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var _forceLC: String {
        (force ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var _mechLC: String {
        (mechanic ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Buckets

    var equipBucket: EquipBucket {
        // Check both primary and secondary equipment
        let primaryLC = _equipLC
        let secondaryLC = _secondaryEquipLC

        // Check most specific patterns first
        if primaryLC.contains("ez bar") || primaryLC.contains("ez-bar") ||
           secondaryLC.contains("ez bar") || secondaryLC.contains("ez-bar") {
            return .ezBar
        }
        if primaryLC.contains("dumbbell") || secondaryLC.contains("dumbbell") {
            return .dumbbell
        }
        if primaryLC.contains("kettlebell") || secondaryLC.contains("kettlebell") {
            return .kettlebell
        }
        if primaryLC.contains("cable") || secondaryLC.contains("cable") {
            return .cable
        }
        if primaryLC.contains("barbell") || primaryLC.contains("trap bar") || primaryLC.contains("smith") ||
           secondaryLC.contains("barbell") || secondaryLC.contains("trap bar") || secondaryLC.contains("smith") {
            return .barbell
        }
        if primaryLC.contains("pull-up") || primaryLC.contains("pullup") || primaryLC.contains("chin-up") || primaryLC.contains("chinup") ||
           secondaryLC.contains("pull-up") || secondaryLC.contains("pullup") || secondaryLC.contains("chin-up") || secondaryLC.contains("chinup") ||
           primaryLC.contains("pull up bar") || secondaryLC.contains("pull up bar") {
            return .pullupbar
        }
        if (primaryLC.isEmpty || primaryLC == "none" || primaryLC.contains("bodyweight") || primaryLC.contains("body weight")) &&
           secondaryLC.isEmpty {
            return .bodyweight
        }
        return .other
    }

    var moveBucket: MoveBucket {
        let nameLC = name.lowercased()
        let prim = primaryMuscles.map { $0.lowercased() }

        // Check force-based first
        if _forceLC.contains("push") { return .push }
        if _forceLC.contains("pull") { return .pull }

        // Check hinge pattern
        if nameLC.contains("deadlift") || nameLC.contains("rdl") ||
           nameLC.contains("romanian") || nameLC.contains("good morning") ||
           nameLC.contains("hip thrust") || nameLC.contains("glute bridge") {
            return .hinge
        }

        // Check squat pattern
        if nameLC.contains("squat") || nameLC.contains("lunge") ||
           nameLC.contains("leg press") || nameLC.contains("step up") ||
           nameLC.contains("split squat") || nameLC.contains("bulgarian") {
            return .squat
        }

        // Check core
        if prim.contains(where: { $0.contains("abs") || $0.contains("oblique") || $0.contains("abdominal") }) ||
           nameLC.contains("plank") || nameLC.contains("crunch") ||
           nameLC.contains("sit-up") || nameLC.contains("ab") {
            return .core
        }

        return .other
    }

    // MARK: - Search

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()

        func norm(_ s: String?) -> String {
            (s ?? "")
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
        }

        let hay = [name, equipment, category, mechanic, force]
            .map(norm)
            .joined(separator: " ")

        let muscles = (primaryMuscles + secondaryMuscles + tertiaryMuscles)
            .map { $0.folding(options: .diacriticInsensitive, locale: .current).lowercased() }
            .joined(separator: " ")

        return hay.contains(q) || muscles.contains(q)
    }

    func contains(muscleGroup: String?) -> Bool {
        guard let g = muscleGroup?.lowercased(), !g.isEmpty else { return true }
        let all = (primaryMuscles + secondaryMuscles + tertiaryMuscles).map { $0.lowercased() }
        return all.contains { $0.contains(g) }
    }
}
