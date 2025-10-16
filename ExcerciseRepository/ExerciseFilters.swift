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
    case kettlebell = "Kettlebell"
    case pullupbar = "Pullup Bar"
    case bodyweight = "Bodyweight"
    case cable = "Cable"
    case other = "Other"

    func matches(_ equipment: String?) -> Bool {
        guard self != .all else { return true }
        let e = (equipment ?? "").lowercased()
        switch self {
        case .barbell:     return e.contains("barbell") || e.contains("ez bar") || e.contains("trap bar")
        case .kettlebell:  return e.contains("kettlebell")
        case .pullupbar:   return e.contains("pullup") || e.contains("pull-up") || e.contains("pull up") || e.contains("bar")
        case .bodyweight:  return e.isEmpty || e == "none" || e.contains("bodyweight")
        case .cable:       return e.contains("cable")
        case .other:       return !EquipBucket.allCases.dropFirst().contains(where: { $0.matches(equipment) })
        case .all:         return true
        }
    }
}

enum MoveBucket: String, CaseIterable {
    case all = "All"
    case push = "Push"
    case pull = "Pull"
    case unsorted = "Unsorted"
    case other = "Other"

    // Use your Exercise properties. If you store `.force` or `.mechanic`, check them here.
    func matches(_ ex: Exercise) -> Bool {
        guard self != .all else { return true }
        let f = (ex.force ?? "").lowercased()
        let m = (ex.mechanic ?? "").lowercased()

        switch self {
        case .push:     return f.contains("push")
        case .pull:     return f.contains("pull")
        case .unsorted: return f.isEmpty && m.isEmpty       // neither set
        case .other:    return !(MoveBucket.push.matches(ex) || MoveBucket.pull.matches(ex) || MoveBucket.unsorted.matches(ex))
        case .all:      return true
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
        self.primaryMuscles = prim
        self.secondaryMuscles = sec
        self.tertiaryMuscles = tert
        self.instructions = []
        self.images = nil
        self.category = category
        self.subregionTags = []
    }

    /// Canonical difficulty from `level`
    var difficultyLevel: DifficultyLevel? { DifficultyLevel(level) }

    // MARK: - Normalization helpers

    private var _equipLC: String {
        (equipment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var _forceLC: String {
        (force ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var _mechLC: String {
        (mechanic ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Buckets

    var equipBucket: EquipBucket {
        switch true {
        case _equipLC.contains("barbell"), _equipLC.contains("ez bar"), _equipLC.contains("trap bar"), _equipLC.contains("smith"):
            return .barbell
        case _equipLC.contains("kettlebell"):
            return .kettlebell
        case _equipLC.contains("pull-up"), _equipLC.contains("pullup"), _equipLC.contains("chin-up"), _equipLC.contains("chinup"):
            return .pullupbar
        case _equipLC.isEmpty, _equipLC == "none", _equipLC.contains("bodyweight"):
            return .bodyweight
        case _equipLC.contains("cable"):
            return .cable
        default:
            return .other
        }
    }

    var moveBucket: MoveBucket {
        if _forceLC.contains("push") { return .push }
        if _forceLC.contains("pull") { return .pull }
        if _mechLC.contains("isometric") || _mechLC.contains("carry") || _mechLC.contains("hold") {
            return .other
        }
        return .unsorted
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
