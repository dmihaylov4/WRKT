//
//  Utilities.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//
import SwiftUI
import CoreData
import Foundation

extension String {
    var normalized: String {
        self.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}

extension Array where Element == Exercise {
    func allMuscleGroups() -> [String] {
        let muscles = self.flatMap { $0.primaryMuscles + $0.secondaryMuscles }
        let groups = Set(muscles)
        return groups.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct DayStat: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let workoutCount: Int
    let runCount: Int
    let plannedWorkout: PlannedWorkout?

    init(id: UUID = UUID(), date: Date, workoutCount: Int, runCount: Int, plannedWorkout: PlannedWorkout? = nil) {
        self.id = id
        self.date = date
        self.workoutCount = workoutCount
        self.runCount = runCount
        self.plannedWorkout = plannedWorkout
    }

    // Helper computed properties
    var hasPlannedWorkout: Bool { plannedWorkout != nil }
    var isPlannedCompleted: Bool { plannedWorkout?.workoutStatus == .completed }
    var isPlannedPartial: Bool { plannedWorkout?.workoutStatus == .partial }
    var isPlannedSkipped: Bool { plannedWorkout?.workoutStatus == .skipped }
    var isPlannedScheduled: Bool { plannedWorkout?.workoutStatus == .scheduled }

    static func == (lhs: DayStat, rhs: DayStat) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
