//
//  WeeklyGoal.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 17.10.25.
//

import SwiftData
import Foundation

enum ActivityTrackingMode: String, Codable {
    case exerciseMinutes  // Apple Watch users - tracks Apple Exercise Time (MVPA)
    case steps            // iPhone-only users - tracks daily steps
}

@Model final class WeeklyGoal {
    @Attribute(.unique) var id: String = "weekly.goal"
    var isSet: Bool
    var targetActiveMinutes: Int
    var targetDailySteps: Int = 10000          // Default value for backward compatibility
    var targetStrengthDays: Int
    var anchorWeekday: Int
    var trackingMode: String = "exerciseMinutes"  // Default to exercise minutes
    var createdAt: Date
    var updatedAt: Date

    init(isSet: Bool = false,
         targetActiveMinutes: Int = 150,
         targetDailySteps: Int = 10000,
         targetStrengthDays: Int = 2,
         anchorWeekday: Int = 2,
         trackingMode: ActivityTrackingMode = .exerciseMinutes,
         createdAt: Date = Date.now,
         updatedAt: Date = Date.now) {
        self.isSet = isSet
        self.targetActiveMinutes = targetActiveMinutes
        self.targetDailySteps = targetDailySteps
        self.targetStrengthDays = targetStrengthDays
        self.anchorWeekday = anchorWeekday
        self.trackingMode = trackingMode.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Computed property for easy access
    var mode: ActivityTrackingMode {
        get { ActivityTrackingMode(rawValue: trackingMode) ?? .exerciseMinutes }
        set { trackingMode = newValue.rawValue }
    }
}
extension Calendar {
    func startOfWeek(for date: Date, anchorWeekday: Int = 2) -> Date {
        var cal = self
        cal.firstWeekday = anchorWeekday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        // Return computed date or fallback to start of day if calculation fails
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }
    func daysBetween(_ a: Date, _ b: Date) -> Int {
        let sA = startOfDay(for: a)
        let sB = startOfDay(for: b)
        return dateComponents([.day], from: sA, to: sB).day ?? 0
    }
}
