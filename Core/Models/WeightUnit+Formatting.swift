// Core/Models/WeightUnit+Formatting.swift

import Foundation

extension WeightUnit {
    // Single source of truth for non-view code (services, models).
    // Views should use @AppStorage("weight_unit") for reactivity.
    static var preferred: WeightUnit {
        let raw = UserDefaults.standard.string(forKey: "weight_unit") ?? "kg"
        return WeightUnit(rawValue: raw) ?? .kg
    }

    // Convert a stored-kg value to the display unit value.
    func displayValue(_ kg: Double) -> Double {
        self == .kg ? kg : kg * 2.20462
    }

    // Convert a value in this unit back to kg (for input field saves).
    func toKg(_ display: Double) -> Double {
        self == .kg ? display : display / 2.20462
    }

    // "82.5 kg" or "182 lb" — smart decimal: no trailing .0
    func format(_ kg: Double) -> String {
        let v = displayValue(kg)
        let s = v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
        return "\(s) \(rawValue)"
    }

    // "82.5kg" or "182lb" — compact, no space (for tight UI chips)
    func formatCompact(_ kg: Double) -> String {
        let v = displayValue(kg)
        let s = v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
        return "\(s)\(rawValue)"
    }

    // "5 × 82.5 kg" or "5 × 182 lb"
    func formatSet(reps: Int, weightKg: Double) -> String {
        "\(reps) × \(format(weightKg))"
    }

    // "5×82kg" or "5×182lb" — compact chip form
    func formatSetCompact(reps: Int, weightKg: Double) -> String {
        "\(reps)×\(formatCompact(weightKg))"
    }

    // Volume (sum of reps×weight): "1.2K kg" or "2.7K lb"; "843 kg" or "1,857 lb"
    func formatVolume(_ kg: Double) -> String {
        let v = displayValue(kg)
        if v >= 1000 { return String(format: "%.1fK \(rawValue)", v / 1000) }
        return String(format: "%.0f \(rawValue)", v)
    }

    // Volume without unit suffix (for callers that append the unit separately)
    func formatVolumeValue(_ kg: Double) -> String {
        let v = displayValue(kg)
        if v >= 1000 { return String(format: "%.1fK", v / 1000) }
        return String(format: "%.0f", v)
    }

    // The unit label only: "kg" or "lb"
    var label: String { rawValue }

    // Static conveniences — use preferred unit, for call sites that don't need reactivity
    static func format(_ kg: Double) -> String { preferred.format(kg) }
    static func formatCompact(_ kg: Double) -> String { preferred.formatCompact(kg) }
    static func formatSet(reps: Int, weightKg: Double) -> String { preferred.formatSet(reps: reps, weightKg: weightKg) }
    static func formatSetCompact(reps: Int, weightKg: Double) -> String { preferred.formatSetCompact(reps: reps, weightKg: weightKg) }
    static func formatVolume(_ kg: Double) -> String { preferred.formatVolume(kg) }
    static func formatVolumeValue(_ kg: Double) -> String { preferred.formatVolumeValue(kg) }
    static var label: String { preferred.label }
}
