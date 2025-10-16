//
//  ExercisePR.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 14.10.25.
//


// WRKT/Features/Rewards/Models/ExercisePR.swift
import SwiftData

// WRKT/Features/Rewards/Models/ExercisePR.swift
import Foundation       // ← add this
import SwiftData

@Model
final class ExercisePR {
    // This is the domain key we want to use for dex stamping.
    var exerciseId: String
    var exerciseName: String
    var bestE1RM: Double
    var bestWeightKg: Double
    var bestReps: Int
    var updatedAt: Date

    init(id exerciseId: String,
         name exerciseName: String,
         e1rm: Double,
         weightKg: Double,
         reps: Int) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.bestE1RM = e1rm
        self.bestWeightKg = weightKg
        self.bestReps = reps
        self.updatedAt = .now
    }
}
