//
//  Persistence.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//
import SwiftUI
import Combine
import Foundation
import OSLog

actor Persistence {
    static let shared = Persistence()
    private let workoutsURL: URL
    private let runsURL: URL
    private let currentWorkoutURL: URL
    private init() {
        // Safely get documents directory with fallback to temporary directory
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            AppLogger.warning("Documents directory not available, using temporary directory", category: AppLogger.storage)
            let tempDir = FileManager.default.temporaryDirectory
            workoutsURL = tempDir.appendingPathComponent("workouts.json")
            runsURL = tempDir.appendingPathComponent("runs.json")
            currentWorkoutURL = tempDir.appendingPathComponent("current_workout.json")
            return
        }
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
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            AppLogger.warning("Application Support directory not available, skipping old storage cleanup", category: AppLogger.storage)
            return
        }
        let appDir = appSupport.appendingPathComponent("WRKT", isDirectory: true)
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("completed_workouts.json"))
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("current_workout.json"))
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("runs.json"))
        try? FileManager.default.removeItem(at: appDir.appendingPathComponent("pr_index.json"))
    }
}
