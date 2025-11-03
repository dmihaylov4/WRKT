//
//  ExerciseIconUtilities.swift
//  WRKT
//
//  Icon and color mapping utilities for exercises
//

import SwiftUI

// MARK: - Equipment Icon

enum EquipmentIcon {
    static func symbol(for equipment: String) -> String {
        switch equipment.lowercased() {
        case "kettlebell":                   return "dumbbell.fill"      // use "kettlebell" if your iOS target has it
        case "dumbbell":                     return "dumbbell.fill"
        case "barbell", "ez bar", "trap bar":return "dumbbell.fill"
        case "cable", "cable machine":       return "cable.connector.horizontal" // generic-ish
        case "band", "resistance band":      return "bandage.fill"       // closest neutral icon
        case "machine":                      return "rectangle.compress.vertical"
        case "smith machine":                return "square.3.layers.3d"
        case "bodyweight", "none":           return "figure.walk"
        default:                             return "hammer.fill"         // generic tool fallback
        }
    }

    static func label(for equipment: String) -> String {
        let s = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Bodyweight" : s
    }

    static func color(for equipment: String) -> Color {
        switch equipment.lowercased() {
        case "kettlebell": return Color(hex: "#F97316") // orange-ish
        case "dumbbell":   return Color(hex: "#60A5FA") // blue
        case "barbell", "ez bar", "trap bar": return Color(hex: "#A3A3A3")
        case "cable", "cable machine": return Color(hex: "#34D399") // green
        case "band", "resistance band": return Color(hex: "#F59E0B") // amber
        case "machine", "smith machine": return Color(hex: "#A78BFA") // violet
        case "bodyweight", "none": return Color.secondary
        default: return DS.Palette.marone
        }
    }
}

// MARK: - Category Icon

enum CategoryIcon {
    static func symbol(for category: String) -> String {
        switch category.lowercased() {
        case "bodybuilding", "hypertrophy":
            return "figure.strengthtraining.traditional"
        case "powerlifting", "strength":
            return "scalemass" // if unavailable, fallback below
        case "conditioning", "hiit", "metcon":
            return "flame.fill"
        case "mobility", "rehab", "prehab":
            return "figure.mind.and.body" // fallback below if needed
        case "plyometrics":
            return "arrow.up.forward.circle.fill"
        default:
            return "bolt.heart" // generic training category
        }
    }

    static func color(for category: String) -> Color {
        switch category.lowercased() {
        case "bodybuilding", "hypertrophy": return Color(hex: "#F472B6") // pink-ish
        case "powerlifting", "strength":    return Color(hex: "#FB923C") // orange
        case "conditioning", "hiit":        return Color(hex: "#22D3EE") // cyan
        case "mobility", "rehab", "prehab": return Color(hex: "#4ADE80") // green
        case "plyometrics":                 return Color(hex: "#C084FC") // violet
        default:                            return DS.Palette.marone
        }
    }
}
