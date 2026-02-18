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

        var displayName: String {
            switch self {
            case .ageBased: return "Age-based (220 - age)"
            case .defaultMax: return "Default (190 bpm)"
            }
        }

        var description: String {
            switch self {
            case .ageBased:
                return "Using age-based formula (220 - age)"
            case .defaultMax:
                return "Set your age in Profile to get personalized zones"
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
    private let ageKey = "user_age"

    private init() {
        loadOrCreateConfig()
    }

    // MARK: - Public API

    /// Get/set user age (stored in UserDefaults)
    var userAge: Int? {
        get {
            let age = UserDefaults.standard.integer(forKey: ageKey)
            return age > 0 ? age : nil
        }
        set {
            if let age = newValue, age > 0 {
                UserDefaults.standard.set(age, forKey: ageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ageKey)
            }
            recalculate()
        }
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

        AppLogger.info("HR Zone config updated: method=\(newConfig.method.rawValue), maxHR=\(Int(newConfig.maxHR)), age=\(newConfig.age.map { String($0) } ?? "nil")", category: AppLogger.health)
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

    /// Get all zone boundaries (simple percentage of max HR)
    func zoneBoundaries() -> [HRZoneBoundary] {
        let cfg = config ?? HRZoneConfig(maxHR: 190, restingHR: nil, age: nil, method: .defaultMax, lastUpdated: Date())

        let zoneData: [(Int, String, Double, Double, Color)] = [
            (1, "Light", 0.50, 0.60, .blue),
            (2, "Moderate", 0.60, 0.70, .green),
            (3, "Aerobic", 0.70, 0.80, .yellow),
            (4, "Threshold", 0.80, 0.90, .orange),
            (5, "Max", 0.90, 1.00, .red)
        ]

        return zoneData.map { (zone, name, lower, upper, color) in
            // Simple percentage of max HR
            let lowerBPM = Int(cfg.maxHR * lower)
            let upperBPM = Int(cfg.maxHR * upper)
            return HRZoneBoundary(zone: zone, name: name, lowerBPM: lowerBPM, upperBPM: upperBPM, color: color)
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
        UserDefaults.standard.removeObject(forKey: ageKey)
        recalculate()
    }
}
