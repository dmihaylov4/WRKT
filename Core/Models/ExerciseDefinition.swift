//
//  ExerciseDefinition.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 26.10.25.
//

import Foundation

// MARK: - Exercise Domain Model
// NOTE: This no longer decodes your Excel JSON directly.
//       Decode Excel JSON -> ExcelExerciseDTO, then map to Exercise
struct Exercise: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var force: String?
    var level: String?
    var mechanic: String?
    var equipment: String?
    var secondaryEquipment: String?
    var grip: String?

    // Muscles for filtering/search
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var tertiaryMuscles: [String]

    // Optional rich content
    var instructions: [String]
    var images: [String]?
    var category: String
    var subregionTags: [String] = []

    // Custom exercise flag
    var isCustom: Bool = false

    // MARK: - Multi-Modal Tracking Support
    /// Tracking mode: "weighted", "timed", "bodyweight", "distance"
    var trackingMode: String = "weighted"
    /// Default duration in seconds for timed exercises (e.g., plank holds)
    var defaultDurationSeconds: Int?
    /// Recommended rest time in seconds (context-aware)
    var recommendedRestSeconds: Int?

    // MARK: - Computed Properties
    var isTimedExercise: Bool { trackingMode == "timed" }
    var isBodyweightExercise: Bool { trackingMode == "bodyweight" }
    var isWeightedExercise: Bool { trackingMode == "weighted" }
}

// MARK: - Difficulty Level
enum DifficultyLevel: String, CaseIterable, Codable {
    case novice, beginner, intermediate, advanced

    init?(_ raw: String?) {
        guard let s = raw?.trimmedOrNil?.lowercased() else { return nil }
        switch s {
        case "novice":                  self = .novice
        case "beginner":                self = .beginner   // some rows may use Beginner
        case "intermediate":            self = .intermediate
        case "advanced":                self = .advanced
        default:                        return nil
        }
    }

    var label: String {
        switch self {
        case .novice:       return "Novice"
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        }
    }
}

// MARK: - String Extensions for Exercise Parsing
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Treats "", "nan", "null", "none" (any case) as nil.
    var trimmedOrNil: String? {
        let t = trimmed
        if t.isEmpty { return nil }
        let lc = t.lowercased()
        if lc == "nan" || lc == "null" || lc == "none" { return nil }
        return t
    }
}

extension Optional where Wrapped == String {
    /// nil -> nil, "   " -> nil, "nan"/"null"/"none" -> nil, otherwise trimmed string
    var trimmedOrNil: String? {
        guard let s = self else { return nil }
        return s.trimmedOrNil
    }
}


struct ExcelExerciseDTO: Decodable, Identifiable, Hashable {
    let id: String           // = slug
    let slug: String
    let exercise: String
    let difficulty: String?
    let targetMuscleGroup: String?
    let primeMover: String?
    let secondaryMuscle: String?
    let tertiaryMuscle: String?
    let primaryEquipment: String?
    let primaryItemsCount: Int?
    let secondaryEquipment: String?
    let secondaryItemsCount: Int?
    let posture: String?
    let armMode: String?
    let armsPattern: String?
    let grip: String?
    let loadPosition: String?
    let legsPattern: String?
    let footElevation: String?
    let combination: String?
    let movementPattern1: String?
    let movementPattern2: String?
    let movementPattern3: String?
    let planeOfMotion1: String?
    let planeOfMotion2: String?
    let planeOfMotion3: String?
    let bodyRegion: String?
    let forceType: String?
    let mechanics: String?
    let laterality: String?
    let primaryClassification: String?

    // MARK: - Multi-Modal Tracking Support (optional fields for backward compatibility)
    let trackingMode: String?
    let defaultDurationSeconds: Int?
    let recommendedRestSeconds: Int?

    // Convenience alias
    var name: String { exercise }
}

