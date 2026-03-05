//
//  HRZoneHelper.swift
//  WRKT Watch
//
//  Lightweight HR zone helper for watchOS
//  Zone thresholds match iOS HRZoneCalculator
//

import SwiftUI

struct HRZone {
    let number: Int      // 1-5 (0 = below zone 1 / no data)
    let name: String     // "Light", "Moderate", "Aerobic", "Threshold", "Max"
    let color: Color
}

enum HRZoneHelper {
    // Zone boundaries as fraction of maxHR (matching iOS HRZoneCalculator)
    private static let zones: [(number: Int, name: String, lower: Double, color: Color)] = [
        (1, "Light",     0.50, .blue),
        (2, "Moderate",  0.60, .green),
        (3, "Aerobic",   0.70, .yellow),
        (4, "Threshold", 0.80, .orange),
        (5, "Max",       0.90, .red)
    ]

    /// Returns the HR zone for a given heart rate.
    /// When restingHR > 0, uses the Karvonen method (HRR-based) to match iOS HRZoneCalculator.
    static func zone(for hr: Int, maxHR: Int, restingHR: Int = 0) -> HRZone {
        guard hr > 0, maxHR > 0 else {
            return HRZone(number: 0, name: "", color: .clear)
        }

        let fraction: Double
        if restingHR > 0, maxHR > restingHR {
            // Karvonen: fraction of heart rate reserve
            fraction = Double(hr - restingHR) / Double(maxHR - restingHR)
        } else {
            fraction = Double(hr) / Double(maxHR)
        }

        // Walk backwards to find the highest matching zone
        for z in zones.reversed() {
            if fraction >= z.lower {
                return HRZone(number: z.number, name: z.name, color: z.color)
            }
        }

        // Below zone 1
        return HRZone(number: 0, name: "", color: .clear)
    }

    static func zoneColor(for hr: Int, maxHR: Int, restingHR: Int = 0) -> Color {
        zone(for: hr, maxHR: maxHR, restingHR: restingHR).color
    }
}
