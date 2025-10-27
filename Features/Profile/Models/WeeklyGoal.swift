//
//  WeeklyGoal.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 17.10.25.
//

import SwiftData
import Foundation

@Model final class WeeklyGoal {
    @Attribute(.unique) var id: String = "weekly.goal"
    var isSet: Bool
    var targetActiveMinutes: Int
    var targetStrengthDays: Int
    var anchorWeekday: Int
    var createdAt: Date
    var updatedAt: Date

    init(isSet: Bool = false,
         targetActiveMinutes: Int = 150,
         targetStrengthDays: Int = 2,
         anchorWeekday: Int = 2,
         createdAt: Date = Date.now,
         updatedAt: Date = Date.now) {
        self.isSet = isSet
        self.targetActiveMinutes = targetActiveMinutes
        self.targetStrengthDays = targetStrengthDays
        self.anchorWeekday = anchorWeekday
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
extension Calendar {
    func startOfWeek(for date: Date, anchorWeekday: Int = 2) -> Date {
        var cal = self
        cal.firstWeekday = anchorWeekday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps)!        // safe in practice
    }
    func daysBetween(_ a: Date, _ b: Date) -> Int {
        let sA = startOfDay(for: a)
        let sB = startOfDay(for: b)
        return dateComponents([.day], from: sA, to: sB).day ?? 0
    }
}
