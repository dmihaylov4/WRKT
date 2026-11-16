//
//  CutStatsFormat.swift
//  WRKT
//
//  Formatting shared by the Cut statistics screens (Trends, Balance, exercise statistics).
//  Pure functions over stored kilograms, seconds and dates; every weight goes through the
//  user's unit.
//

import Foundation

nonisolated enum CutStatsFormat {
    /// Grouped whole number: "26,446".
    static func number(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Whole numbers stay whole, otherwise one decimal ("90", "87.5", "198.4").
    static func decimal(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value.isFinite ? value : 0)) ?? "0"
    }

    /// Stored kilograms in the user's unit (the factor WeightUnit.displayValue uses).
    static func display(_ kg: Double, unit: WeightUnit) -> Double {
        unit == .kg ? kg : kg * 2.20462
    }

    /// "kg" or "lb".
    static func label(_ unit: WeightUnit) -> String {
        unit == .kg ? "kg" : "lb"
    }

    /// A load in the user's unit, as a number only: "90", "198.4".
    static func weightNumber(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        decimal(display(kg, unit: unit), locale: locale)
    }

    /// "90 kg", "198.4 lb".
    static func weight(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(weightNumber(kg, unit: unit, locale: locale)) \(label(unit))"
    }

    /// Spoken: "90 kilograms".
    static func spokenWeight(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(weightNumber(kg, unit: unit, locale: locale)) \(spokenUnit(unit))"
    }

    /// Tonnage in the user's unit, whole and grouped: "6,240".
    static func volumeNumber(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        let value = display(kg, unit: unit)
        return number(Int(value.isFinite ? value.rounded() : 0), locale: locale)
    }

    /// "6,240 kg".
    static func volume(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(volumeNumber(kg, unit: unit, locale: locale)) \(label(unit))"
    }

    static func spokenVolume(_ kg: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(volumeNumber(kg, unit: unit, locale: locale)) \(spokenUnit(unit))"
    }

    static func spokenUnit(_ unit: WeightUnit) -> String {
        unit == .kg ? "kilograms" : "pounds"
    }

    /// "0:45", "1:30", then "1:05" (h:mm) from one hour: seconds are dropped once hours show.
    static func duration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total >= 3600 {
            return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Spoken duration: "1 minute 30 seconds", "1 hour 5 minutes".
    static func spokenDuration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        func part(_ value: Int, _ word: String) -> String { "\(value) \(word)\(value == 1 ? "" : "s")" }
        if total >= 3600 {
            let minutes = (total % 3600) / 60
            return minutes > 0 ? "\(part(total / 3600, "hour")) \(part(minutes, "minute"))" : part(total / 3600, "hour")
        }
        if total >= 60 {
            let rest = total % 60
            return rest > 0 ? "\(part(total / 60, "minute")) \(part(rest, "second"))" : part(total / 60, "minute")
        }
        return part(total, "second")
    }

    /// "800 m", "1.2 km".
    static func distance(_ meters: Double, locale: Locale) -> String {
        meters >= 1000 ? "\(decimal(meters / 1000, locale: locale)) km" : "\(number(Int(meters.rounded()), locale: locale)) m"
    }

    static func date(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// "11 Nov".
    static func dayMonth(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        Self.date(date, template: "d MMM", calendar: calendar, locale: locale)
    }

    /// "Wednesday 11 Nov", with the year when it is not the current one.
    static func sessionDay(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return Self.date(date, template: sameYear ? "EEEE d MMM" : "EEEE d MMM y", calendar: calendar, locale: locale)
            .replacingOccurrences(of: ",", with: "")
    }

    /// Calendar days from `date` to `now` (0 for today, never negative).
    static func daysAgo(_ date: Date, now: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }

    /// The start of the week holding `date`, normalised the way StatsAggregator stores `weekStart`.
    static func weekStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? calendar.startOfDay(for: date)
    }

    /// "1 set", "4 sets".
    static func count(_ value: Int, _ singular: String, _ plural: String, locale: Locale) -> String {
        "\(number(value, locale: locale)) \(value == 1 ? singular : plural)"
    }
}
