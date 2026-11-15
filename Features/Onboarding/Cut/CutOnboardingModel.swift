//
//  CutOnboardingModel.swift
//  WRKT
//
//  The Cut onboarding: three intro pages on a lime field and the bodyweight page. Same four steps,
//  same Skip, Next and Get started as OnboardingCarouselView. Bodyweight stays stored in kilograms
//  in "user_bodyweight_kg"; the Kilograms / Pounds switch only changes how it is shown and stepped.
//

import CoreGraphics
import Foundation

struct CutOnboardingPage: Equatable, Identifiable {
    var id: Int
    var title: String
    var line: String
}

/// The progress bar: one segment per step, the current one wide.
struct CutOnboardingProgress: Equatable {
    enum Segment: Equatable { case done, current, upcoming }
    var segments: [Segment]
    /// "Step 2 of 4"
    var spoken: String
}

struct CutOnboardingBodyweightModel: Equatable {
    /// "78.5"
    var number: String
    /// "kg" or "lb"
    var unitLabel: String
    /// "78.5 kilograms", for VoiceOver.
    var spoken: String
    var unit: WeightUnit
    var canDecrease: Bool
    var canIncrease: Bool
}

enum CutOnboardingLogic {
    /// Four steps, as in the legacy carousel: three intro pages and the bodyweight page.
    nonisolated static let stepCount = 4
    nonisolated static let bodyweightIndex = 3

    /// The legacy default when nothing is stored yet.
    nonisolated static let defaultBodyweightKg = 70.0
    /// The legacy page's bounds: 30 to 200 kg.
    nonisolated static let minimumKg = 30.0
    nonisolated static let maximumKg = 200.0

    /// One short line and one calm sentence for each legacy intro page.
    static let pages: [CutOnboardingPage] = [
        // Track Your Progress
        .init(id: 0, title: "Track every set",
              line: "Log weights and reps in one tap, and see each lift move week by week."),
        // Stay Motivated
        .init(id: 1, title: "Keep showing up",
              line: "Build streaks, earn rewards and level up as you train week after week."),
        // Train Smart
        .init(id: 2, title: "Train smart",
              line: "See which muscles have recovered and keep your push and pull in balance.")
    ]

    static let bodyweightTitle = "Your starting point"
    static let bodyweightLine = "Your bodyweight sets the first weight suggestions. You can change it later."

    static func isLast(_ index: Int) -> Bool { index >= stepCount - 1 }

    /// The page Next moves to, or nil on the last page (Get started finishes instead).
    static func next(after index: Int) -> Int? {
        isLast(index) ? nil : max(0, index) + 1
    }

    /// The page the bodyweight page's back button returns to.
    static func back(from index: Int) -> Int? {
        index > 0 ? index - 1 : nil
    }

    /// The page a horizontal swipe lands on: one page forward or back once the swipe passes a
    /// quarter of the width; mostly vertical swipes (scrolling) and swipes past either end stay put.
    static func page(afterSwipe horizontal: CGFloat, vertical: CGFloat, from index: Int, width: CGFloat) -> Int {
        guard abs(horizontal) > abs(vertical), abs(horizontal) > width / 4 else { return index }
        return min(max(index + (horizontal < 0 ? 1 : -1), 0), stepCount - 1)
    }

    /// How far the pages follow a finger: fully between pages, a third of the way past either end.
    static func dragOffset(_ horizontal: CGFloat, at index: Int) -> CGFloat {
        let pastStart = index == 0 && horizontal > 0
        let pastEnd = index >= stepCount - 1 && horizontal < 0
        return pastStart || pastEnd ? horizontal / 3 : horizontal
    }

    static func progress(at index: Int) -> CutOnboardingProgress {
        let current = min(max(index, 0), stepCount - 1)
        let segments: [CutOnboardingProgress.Segment] = (0..<stepCount).map { step in
            step < current ? .done : step == current ? .current : .upcoming
        }
        return .init(segments: segments, spoken: "Step \(current + 1) of \(stepCount)")
    }

    // MARK: Bodyweight

    /// The step bounds in tenths of the display unit: 30 to 200 kg, or 66.2 to 440.9 lb
    /// (the tenths of a pound that stay inside 30 to 200 kg).
    static func tenthsBounds(_ unit: WeightUnit) -> ClosedRange<Int> {
        let low = Int((unit.displayValue(minimumKg) * 10 - 1e-6).rounded(.up))
        let high = Int((unit.displayValue(maximumKg) * 10 + 1e-6).rounded(.down))
        return low...high
    }

    /// Stored kilograms as shown: tenths of the display unit, rounded to the nearest tenth.
    static func tenths(kg: Double, unit: WeightUnit) -> Int {
        Int((unit.displayValue(kg) * 10).rounded())
    }

    /// One step from the stored value, in the display unit. Returns kilograms to store, or nil when
    /// the value is already at the bound in that direction (the legacy page did nothing then).
    /// - Parameter tenthsPerStep: 1 for a tap (0.1 of the unit); larger while the button is held.
    static func step(kg: Double, unit: WeightUnit, up: Bool, tenthsPerStep: Int = 1) -> Double? {
        let bounds = tenthsBounds(unit)
        let current = tenths(kg: kg, unit: unit)
        let amount = max(1, tenthsPerStep)
        let next: Int
        if up {
            guard current < bounds.upperBound else { return nil }
            next = min(current + amount, bounds.upperBound)
        } else {
            guard current > bounds.lowerBound else { return nil }
            next = max(current - amount, bounds.lowerBound)
        }
        return unit.toKg(Double(next) / 10)
    }

    /// How far a held button moves: a tenth for the first ten repeats, then a whole unit.
    static func tenthsPerStep(repeats: Int) -> Int {
        repeats < 10 ? 1 : 10
    }

    static func bodyweight(kg: Double, unit: WeightUnit) -> CutOnboardingBodyweightModel {
        let value = tenths(kg: kg, unit: unit)
        let number = String(format: "%.1f", Double(value) / 10)
        return .init(
            number: number,
            unitLabel: unit.rawValue,
            spoken: "\(number) \(unit == .kg ? "kilograms" : "pounds")",
            unit: unit,
            canDecrease: step(kg: kg, unit: unit, up: false) != nil,
            canIncrease: step(kg: kg, unit: unit, up: true) != nil
        )
    }

    static func unitTitle(_ unit: WeightUnit) -> String {
        unit == .kg ? "Kilograms" : "Pounds"
    }
}
