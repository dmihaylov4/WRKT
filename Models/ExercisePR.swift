// WRKT/Features/Rewards/Models/ExercisePR.swift
import SwiftData

@Model final class ExercisePR {
    @Attribute(.unique) var exerciseId: String
    var exerciseName: String
    var bestE1RM: Double
    var bestWeightKg: Double
    var bestReps: Int
    var updatedAt: Date

    init(id: String, name: String, e1rm: Double, weightKg: Double, reps: Int, updatedAt: Date = .now) {
        self.exerciseId = id
        self.exerciseName = name
        self.bestE1RM = e1rm
        self.bestWeightKg = weightKg
        self.bestReps = reps
        self.updatedAt = updatedAt
    }
}