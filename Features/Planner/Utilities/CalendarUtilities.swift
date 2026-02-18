//  CalendarUtilities.swift
//  WRKT
//
//  Calendar helper functions and utilities for calendar operations
//

import Foundation

/// Formats a date to show only the time component
/// - Parameter date: The date to format
/// - Returns: A formatted time string (e.g., "2:30 PM")
func timeOnly(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

/// Formats seconds into hours:minutes:seconds format
/// - Parameter seconds: The number of seconds to format
/// - Returns: A formatted string in HH:MM:SS format
func hms(_ seconds: Int) -> String {
    String(format: "%02d:%02d:%02d", seconds/3600, (seconds%3600)/60, seconds%60)
}
