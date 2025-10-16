//
//  Persistence.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//
import SwiftUI
import Combine
import Foundation

actor Persistence {
    static let shared = Persistence()
    private let workoutsURL: URL
    private let runsURL: URL
    private let currentWorkoutURL: URL
    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        workoutsURL = dir.appendingPathComponent("workouts.json")
        runsURL = dir.appendingPathComponent("runs.json")
        currentWorkoutURL = dir.appendingPathComponent("current_workout.json")
    }
    func loadWorkouts() async -> [CompletedWorkout] {
        (try? Data(contentsOf: workoutsURL)).flatMap { try? JSONDecoder().decode([CompletedWorkout].self, from: $0) } ?? []
    }
    func saveWorkouts(_ items: [CompletedWorkout]) async {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: workoutsURL, options: [.atomic])
    }
    func loadRuns() async -> [RunLog] {
        (try? Data(contentsOf: runsURL)).flatMap { try? JSONDecoder().decode([RunLog].self, from: $0) } ?? []
    }
    func saveRuns(_ items: [RunLog]) async {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: runsURL, options: [.atomic])
    }
    func loadCurrentWorkout() async -> CurrentWorkout? {
        guard let data = try? Data(contentsOf: currentWorkoutURL) else { return nil }
        return try? JSONDecoder().decode(CurrentWorkout.self, from: data)
    }

    func saveCurrentWorkout(_ current: CurrentWorkout?) async {
        guard let current else {
            try? FileManager.default.removeItem(at: currentWorkoutURL)
            return
        }
        guard let data = try? JSONEncoder().encode(current) else { return }
        try? data.write(to: currentWorkoutURL, options: [.atomic])
    }

    func deleteCurrentWorkout() async {
        try? FileManager.default.removeItem(at: currentWorkoutURL)
    }
}


extension Persistence {
    func wipeAllDevOnly() async {
        try? FileManager.default.removeItem(at: workoutsURL)
        try? FileManager.default.removeItem(at: runsURL)
        try? FileManager.default.removeItem(at: currentWorkoutURL)
    }
}
