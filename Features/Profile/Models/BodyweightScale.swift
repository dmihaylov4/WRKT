//
//  BodyweightScale.swift
//  WRKT
//
//  Bodyweight is stored in kilograms ("user_bodyweight_kg"). The Preferences wheels (legacy and
//  Cut) show and edit it in the user's weight unit, to the tenth. The conversion is the app's
//  WeightUnit pair (displayValue and toKg); this adds the wheel's range and the draft, so the
//  boundary is one pair of pure functions:
//
//    tenths(kg:unit:)  stored kilograms -> the wheel's value, in tenths of the display unit
//    kg(tenths:unit:)  the wheel's value -> kilograms to store
//
//  Range: 30.0 to 250.9 kg, or 66.0 to 551.9 lb (30 and 250 kg, whole numbers in pounds).
//  Reopening shows the same tenth that was picked, and closing an untouched wheel stores nothing,
//  so editing never drifts.
//

import Foundation

enum BodyweightScale {
    /// The whole numbers the first wheel offers, per unit.
    static func wholeRange(_ unit: WeightUnit) -> ClosedRange<Int> {
        switch unit {
        case .kg: 30...250
        case .lb: 66...551
        }
    }

    static let tenthsRange = 0...9

    /// The wheel's span in tenths of the unit, both ends included.
    static func tenthsSpan(_ unit: WeightUnit) -> ClosedRange<Int> {
        let whole = wholeRange(unit)
        return (whole.lowerBound * 10)...(whole.upperBound * 10 + 9)
    }

    /// Stored kilograms as the wheel's value: tenths of the display unit, rounded to the nearest
    /// tenth and kept inside the wheel's span.
    static func tenths(kg: Double, unit: WeightUnit) -> Int {
        let span = tenthsSpan(unit)
        let value = Int((unit.displayValue(kg) * 10).rounded())
        return min(max(value, span.lowerBound), span.upperBound)
    }

    /// The wheel's value back to kilograms to store.
    static func kg(tenths: Int, unit: WeightUnit) -> Double {
        unit.toKg(Double(tenths) / 10)
    }

    /// The Preferences row: "82.5 kg", "182 lb". Rounded to the tenth first, so a value saved in
    /// pounds reads back as picked (180 lb, not 180.0 lb).
    static func line(kg: Double, unit: WeightUnit?) -> String {
        let unit = unit ?? .kg
        let tenths = Int((unit.displayValue(kg) * 10).rounded())
        let number = tenths % 10 == 0 ? "\(tenths / 10)" : String(format: "%.1f", Double(tenths) / 10)
        return "\(number) \(unit.rawValue)"
    }
}

/// The bodyweight wheels' draft, in tenths of the display unit.
struct BodyweightDraft: Equatable {
    let unit: WeightUnit
    private let startTenths: Int
    /// The wheel's value in tenths of `unit`.
    var tenths: Int

    init(kg: Double, unit: WeightUnit) {
        self.unit = unit
        self.startTenths = BodyweightScale.tenths(kg: kg, unit: unit)
        self.tenths = startTenths
    }

    var whole: Int {
        get { tenths / 10 }
        set { tenths = newValue * 10 + tenths % 10 }
    }

    var tenth: Int {
        get { tenths % 10 }
        set { tenths = (tenths / 10) * 10 + newValue }
    }

    /// Kilograms to store when the sheet closes, or nil when the wheel was not changed (the
    /// stored value is then left exactly as it was).
    var kgToCommit: Double? {
        tenths == startTenths ? nil : BodyweightScale.kg(tenths: tenths, unit: unit)
    }
}
