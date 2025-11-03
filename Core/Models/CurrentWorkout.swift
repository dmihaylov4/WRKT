//
//  CurrentWorkout.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 26.10.25.
//

import Foundation

struct CurrentWorkout: Identifiable, Codable, Hashable {
    var id = UUID()
    var startedAt: Date = .now
    var entries: [WorkoutEntry] = []
    var plannedWorkoutID: UUID? = nil  // Link to PlannedWorkout if started from one
    var activeEntryID: UUID? = nil  // Track which exercise user is currently focused on
}
