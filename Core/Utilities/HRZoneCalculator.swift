//
//  HRZoneCalculator.swift
//  WRKT
//
//  Heart rate zone calculator using simple formula:
//  - Max HR = 220 - age (if age is set in profile)
//  - Max HR = 190 (fallback if no age set)
//

import SwiftUI
import Combine

// MARK: - Models

struct HRZoneConfig: Codable, Equatable {
    let maxHR: Double
    let restingHR: Double?
    let age: Int?
    let method: CalculationMethod
    let lastUpdated: Date

    enum CalculationMethod: String, Codable {
        case ageBased       // 220 - age
        case defaultMax     // Default 190 bpm (no age set)
        case karvonen       // Karvonen (HRR-based): restingHR + (maxHR − restingHR) × intensity

        var displayName: String {
            switch self {
            case .ageBased: return "Age-based (220 - age)"
            case .defaultMax: return "Default (190 bpm)"
            case .karvonen: return "Karvonen (Heart Rate Reserve)"
            }
        }

        var description: String {
            switch self {
            case .ageBased:
                return "Using age-based formula (220 - age)"
            case .defaultMax:
                return "Set your age in Profile to get personalized zones"
            case .karvonen:
                return "Using resting HR from Apple Health for personalized zones"
            }
        }
    }
}

struct HRZoneBoundary {
    let zone: Int
    let name: String
    let lowerBPM: Int
    let upperBPM: Int
    let color: Color

    var rangeString: String { "\(lowerBPM)-\(upperBPM) bpm" }

    var percentageRange: String {
        let lowerPercent = zone == 1 ? 50 : (zone - 1) * 10 + 50
        let upperPercent = zone * 10 + 50
        return "\(lowerPercent)-\(upperPercent)%"
    }
}

// MARK: - Calculator

@MainActor
final class HRZoneCalculator: ObservableObject {
    static let shared = HRZoneCalculator()

    @Published private(set) var config: HRZoneConfig?

    private let configKey = "hr_zone_config_v2"
    private let birthYearKey = "user_birth_year"

    private init() {
        loadOrCreateConfig()
    }

    // MARK: - Public API

    /// Age derived from stored birth year — auto-updates each calendar year, no manual refresh needed.
    var userAge: Int? {
        get {
            let birthYear = UserDefaults.standard.integer(forKey: birthYearKey)
            guard birthYear > 0 else { return nil }
            let age = Calendar.current.component(.year, from: Date()) - birthYear
            return age > 0 && age < 120 ? age : nil
        }
        set {
            if let age = newValue, age > 0 {
                let birthYear = Calendar.current.component(.year, from: Date()) - age
                UserDefaults.standard.set(birthYear, forKey: birthYearKey)
            } else {
                UserDefaults.standard.removeObject(forKey: birthYearKey)
            }
            recalculate()
        }
    }

    /// Seed birth year directly from Supabase profile (used at launch and on profile update).
    func setBirthYear(_ birthYear: Int) {
        guard birthYear > 1900 else { return }
        UserDefaults.standard.set(birthYear, forKey: birthYearKey)
        AppLogger.info("[HRZones] Birth year set to \(birthYear) → age \(Calendar.current.component(.year, from: Date()) - birthYear)", category: AppLogger.health)
        recalculate()
    }

    /// Update resting HR (from HealthKit) and recalculate zones using Karvonen when available.
    /// Pass nil to remove resting HR and fall back to %maxHR.
    func setRestingHR(_ restingHR: Double?) {
        let age = userAge
        let maxHR: Double = age.map { a in Double(220 - a) } ?? 190
        let method: HRZoneConfig.CalculationMethod = restingHR != nil ? .karvonen : (age != nil ? .ageBased : .defaultMax)

        let newConfig = HRZoneConfig(
            maxHR: maxHR,
            restingHR: restingHR,
            age: age,
            method: method,
            lastUpdated: Date()
        )
        self.config = newConfig
        saveConfig(newConfig)
        AppLogger.info("[HRZones] method=\(method.rawValue), maxHR=\(Int(maxHR)), restingHR=\(restingHR.map { String(Int($0)) } ?? "nil")", category: AppLogger.health)
        logZoneBoundaries()
    }

    /// Recalculate config based on current age setting
    func recalculate() {
        let age = userAge
        let newConfig: HRZoneConfig

        if let age = age, age > 0 && age < 120 {
            // Use 220 - age formula
            let maxHR = Double(220 - age)
            newConfig = HRZoneConfig(
                maxHR: maxHR,
                restingHR: nil,
                age: age,
                method: .ageBased,
                lastUpdated: Date()
            )
        } else {
            // No age set - use default 190
            newConfig = HRZoneConfig(
                maxHR: 190,
                restingHR: nil,
                age: nil,
                method: .defaultMax,
                lastUpdated: Date()
            )
        }

        self.config = newConfig
        saveConfig(newConfig)

        AppLogger.info("[HRZones] method=\(newConfig.method.rawValue), maxHR=\(Int(newConfig.maxHR)), age=\(newConfig.age.map { String($0) } ?? "nil")", category: AppLogger.health)
        logZoneBoundaries()
    }

    /// Get zone for a heart rate value
    func zone(for hr: Double) -> Int {
        let boundaries = zoneBoundaries()
        for boundary in boundaries.reversed() {
            if hr >= Double(boundary.lowerBPM) {
                return boundary.zone
            }
        }
        return 1
    }

    /// Get all zone boundaries. Uses Karvonen (HRR-based) when resting HR is available,
    /// otherwise falls back to simple percentage of max HR.
    func zoneBoundaries() -> [HRZoneBoundary] {
        let cfg = config ?? HRZoneConfig(maxHR: 190, restingHR: nil, age: nil, method: .defaultMax, lastUpdated: Date())

        let zoneData: [(Int, String, Double, Double, Color)] = [
            (1, "Light", 0.50, 0.60, .blue),
            (2, "Moderate", 0.60, 0.70, .green),
            (3, "Aerobic", 0.70, 0.80, .yellow),
            (4, "Threshold", 0.80, 0.90, .orange),
            (5, "Max", 0.90, 1.00, .red)
        ]

        if let restingHR = cfg.restingHR {
            // Karvonen: targetBPM = restingHR + HRR × intensity
            let hrr = cfg.maxHR - restingHR
            return zoneData.map { (zone, name, lower, upper, color) in
                let lowerBPM = Int(restingHR + hrr * lower)
                let upperBPM = Int(restingHR + hrr * upper)
                return HRZoneBoundary(zone: zone, name: name, lowerBPM: lowerBPM, upperBPM: upperBPM, color: color)
            }
        } else {
            return zoneData.map { (zone, name, lower, upper, color) in
                let lowerBPM = Int(cfg.maxHR * lower)
                let upperBPM = Int(cfg.maxHR * upper)
                return HRZoneBoundary(zone: zone, name: name, lowerBPM: lowerBPM, upperBPM: upperBPM, color: color)
            }
        }
    }

    /// Get zone info for a specific zone number
    func zoneInfo(for zoneNumber: Int) -> HRZoneBoundary? {
        zoneBoundaries().first { $0.zone == zoneNumber }
    }

    /// Get the current method display name
    var methodDisplayName: String {
        config?.method.displayName ?? "Not configured"
    }

    /// Get the current method description
    var methodDescription: String {
        config?.method.description ?? "Set your age in Profile to get personalized zones."
    }

    /// Get current max HR
    var maxHR: Int {
        Int(config?.maxHR ?? 190)
    }

    // MARK: - Private

    private func logZoneBoundaries() {
        let boundaries = zoneBoundaries()
        let summary = boundaries.map { "Z\($0.zone):\($0.lowerBPM)-\($0.upperBPM)" }.joined(separator: "  ")
        AppLogger.info("[HRZones] \(summary) bpm", category: AppLogger.health)
    }

    private func loadOrCreateConfig() {
        // Try to load cached config
        if let data = UserDefaults.standard.data(forKey: configKey),
           let cached = try? JSONDecoder().decode(HRZoneConfig.self, from: data) {
            self.config = cached
            return
        }

        // No cached config - create based on current age setting
        recalculate()
    }

    private func saveConfig(_ config: HRZoneConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    /// Reset to defaults
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: birthYearKey)
        recalculate()
    }
}
