//  DateExtensions.swift
//  WRKT
//
//  Date utility extensions for calendar day context detection
//

import Foundation

extension Date {
    /// Represents the temporal context of a date relative to today
    enum DayContext {
        case past
        case today
        case future
    }

    /// Determines if this date is in the past, today, or future
    var dayContext: DayContext {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return .today
        } else if calendar.startOfDay(for: self) < calendar.startOfDay(for: Date()) {
            return .past
        } else {
            return .future
        }
    }

    /// Returns true if this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Returns true if this date is in the past (before today)
    var isPast: Bool {
        dayContext == .past
    }

    /// Returns true if this date is in the future (after today)
    var isFuture: Bool {
        dayContext == .future
    }
}
