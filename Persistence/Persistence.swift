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
        guard let data = try? Data(contentsOf: workoutsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CompletedWorkout].self, from: data)) ?? []
    }
    func saveWorkouts(_ items: [CompletedWorkout]) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CurrentWorkout.self, from: data)
    }

    func saveCurrentWorkout(_ current: CurrentWorkout?) async {
        guard let current else {
            try? FileManager.default.removeItem(at: currentWorkoutURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(current) else { return }
        try? data.write(to: currentWorkoutURL, options: [.atomic])
    }

    func deleteCurrentWorkout() async {
        try? FileManager.default.removeItem(at: currentWorkoutURL)
    }
}


extension Persistence {
    func wipeAllDevOnly() async {
        // Delete new storage (Documents directory)
        try? FileManager.default.removeItem(at: workoutsURL)
        try? FileManager.default.removeItem(at: runsURL)
        try? FileManager.default.removeItem(at: currentWorkoutURL)

        // Delete old storage (Application Support directory)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WRKT", isDirectory: true)
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("completed_workouts.json"))
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("current_workout.json"))
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("runs.json"))
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("pr_index.json"))

        print("✅ All persisted JSON files deleted (both old and new storage)")
    }
}
