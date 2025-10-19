
//
//  Models.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import SwiftUI
import Foundation


private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = Color(hex: "#F4E409")
}

// MARK: - Domain Model used by the UI everywhere
// NOTE: This no longer decodes your Excel JSON directly.
//       Decode Excel JSON -> ExcelExerciseDTO, then map to Exercise
//       (see the convenience init(from:) at the bottom).
struct Exercise: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var force: String?
    var level: String?
    var mechanic: String?
    var equipment: String?
    var grip: String?

    // Muscles for filtering/search
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var tertiaryMuscles: [String]      // 👈 NEW

    // Optional rich content
    var instructions: [String]
    var images: [String]?
    var category: String
    var subregionTags: [String] = []
}

// Models.swift — mapping from ExcelExerciseDTO



// MARK: - App models

enum WeightUnit: String, CaseIterable, Codable {
    case kg, lb
}

enum SetTag: String, Codable, CaseIterable {
    case warmup, working, backoff

    var label: String {
        switch self {
        case .warmup:  return "Warm-up"
        case .working: return "Working"
        case .backoff: return "Back-off"
        }
    }
    var short: String {
        switch self {
        case .warmup:  return "WU"
        case .working: return "WK"
        case .backoff: return "BO"
        }
    }
    var color: Color {
        switch self {
        case .warmup:  return .blue.opacity(0.35)
        case .working: return Theme.accent.opacity(0.35)
        case .backoff: return .purple.opacity(0.35)
        }
    }
    func next() -> SetTag {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + 1) % all.count]
    }
}
// Update your SetInput (keep defaults so existing data still works)
struct SetInput: Hashable, Codable {
    var reps: Int
    var weight: Double
    var tag: SetTag = .working
    // When true, row is allowed to overwrite weight with suggestions.
    // Flip to false as soon as user edits weight manually.
    var autoWeight: Bool = true
    var didSeedFromMemory: Bool = false
}

struct WorkoutEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var exerciseID: String
    var exerciseName: String
    var muscleGroups: [String]
    var sets: [SetInput]
}

struct CompletedWorkout: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date = .now
    var entries: [WorkoutEntry]

    // Matched HealthKit workout data (if found within ±10 min of completion)
    var matchedHealthKitUUID: UUID?
    var matchedHealthKitCalories: Double?
    var matchedHealthKitHeartRate: Double?           // Average HR
    var matchedHealthKitMaxHeartRate: Double?        // Max HR
    var matchedHealthKitMinHeartRate: Double?        // Min HR
    var matchedHealthKitDuration: Int?               // in seconds
    var matchedHealthKitHeartRateSamples: [HeartRateSample]?  // Time-series for graph

    init(id: UUID = UUID(), date: Date = .now, entries: [WorkoutEntry]) {
        self.id = id
        self.date = date
        self.entries = entries
    }
}

// Heart rate sample for time-series graphing
struct HeartRateSample: Codable, Hashable {
    let timestamp: Date      // When this sample was recorded
    let bpm: Double          // Beats per minute
}

struct CurrentWorkout: Identifiable, Codable, Hashable {
    var id = UUID()
    var startedAt: Date = .now
    var entries: [WorkoutEntry] = []
}

struct Coordinate: Codable, Hashable {
    let lat: Double
    let lon: Double
}

struct Run: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var distanceKm: Double
    var durationSec: Int
    var notes: String?

    // HealthKit fields
    var healthKitUUID: UUID?   // to de-duplicate imports
    var avgHeartRate: Double?
    var calories: Double?
    var route: [Coordinate]?   // nil when no route
    var workoutType: String?   // HealthKit workout activity type (e.g., "Running", "Cycling", "Traditional Strength Training")
    var workoutName: String?   // Custom workout name from Apple Fitness/Watch

    init(
        id: UUID = UUID(),
        date: Date = .now,
        distanceKm: Double,
        durationSec: Int,
        notes: String? = nil,
        healthKitUUID: UUID? = nil,
        avgHeartRate: Double? = nil,
        calories: Double? = nil,
        route: [Coordinate]? = nil,
        workoutType: String? = nil,
        workoutName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.durationSec = durationSec
        self.notes = notes
        self.healthKitUUID = healthKitUUID
        self.avgHeartRate = avgHeartRate
        self.calories = calories
        self.route = route
        self.workoutType = workoutType
        self.workoutName = workoutName
    }
}

struct RunLog: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var distanceKm: Double
    var durationSec: Int
    var notes: String?
    init(id: UUID = UUID(), date: Date = .now, distanceKm: Double, durationSec: Int, notes: String? = nil) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.durationSec = durationSec
        self.notes = notes
    }
}

// MARK: - Excel JSON DTO (decoded from exercises_clean.json)
// You can keep this here, or move to Sources/Network/DTO/ExerciseDTO.swift later.
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

    // Convenience alias
    var name: String { exercise }
}




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



// Models.swift — canonical difficulty
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
