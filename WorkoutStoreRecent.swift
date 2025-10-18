//
//  WorkoutStoreRecent.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import Foundation
import SwiftUI
import HealthKit

extension WorkoutStore {
    struct ExerciseSummary: Identifiable, Hashable {
        let id: String         // exerciseID
        let name: String
        var lastDate: Date
    }

    /// Unique recent exercises, most recent first.
    func recentExercises(limit: Int = 10) -> [ExerciseSummary] {
        var map: [String: ExerciseSummary] = [:]

        for w in completedWorkouts {
            for e in w.entries {
                if var existing = map[e.exerciseID] {
                    if w.date > existing.lastDate { existing.lastDate = w.date }
                    map[e.exerciseID] = existing
                } else {
                    map[e.exerciseID] = ExerciseSummary(id: e.exerciseID, name: e.exerciseName, lastDate: w.date)
                }
            }
        }

        return map.values.sorted { $0.lastDate > $1.lastDate }.prefix(limit).map { $0 }
    }
    
    
}


