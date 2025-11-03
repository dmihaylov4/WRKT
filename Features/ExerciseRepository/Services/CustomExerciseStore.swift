//
//  CustomExerciseStore.swift
//  WRKT
//
//  Manages user-created custom exercises with JSON file persistence
//

import Foundation
import Combine

@MainActor
final class CustomExerciseStore: ObservableObject {
    static let shared = CustomExerciseStore()

    @Published private(set) var customExercises: [Exercise] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let storageURL: URL
    private let backupURL: URL

    // MARK: - Initialization

    init() {
        // Setup encoder/decoder
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Setup file URLs
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not accessible")
        }

        let storageDir = documentsDir.appendingPathComponent("WRKT_Storage", isDirectory: true)
        self.storageURL = storageDir.appendingPathComponent("custom_exercises.json")
        self.backupURL = storageDir.appendingPathComponent("custom_exercises_backup.json")

        // Create directory if needed
        try? fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)

        // Load existing exercises
        load()
    }

    // MARK: - Public API

    /// Add a new custom exercise
    func add(_ exercise: Exercise) {
        guard !customExercises.contains(where: { $0.id == exercise.id }) else {
            AppLogger.warning("Custom exercise already exists: \(exercise.id)", category: AppLogger.app)
            return
        }

        customExercises.append(exercise)
        customExercises.sort { $0.name < $1.name }
        save()

        AppLogger.success("Added custom exercise: \(exercise.name)", category: AppLogger.app)
    }

    /// Update an existing custom exercise
    func update(_ exercise: Exercise) {
        guard let index = customExercises.firstIndex(where: { $0.id == exercise.id }) else {
            AppLogger.warning("Custom exercise not found: \(exercise.id)", category: AppLogger.app)
            return
        }

        customExercises[index] = exercise
        customExercises.sort { $0.name < $1.name }
        save()

        AppLogger.success("Updated custom exercise: \(exercise.name)", category: AppLogger.app)
    }

    /// Delete a custom exercise
    func delete(_ exerciseID: String) {
        guard let index = customExercises.firstIndex(where: { $0.id == exerciseID }) else {
            AppLogger.warning("Custom exercise not found: \(exerciseID)", category: AppLogger.app)
            return
        }

        let name = customExercises[index].name
        customExercises.remove(at: index)
        save()

        AppLogger.success("Deleted custom exercise: \(name)", category: AppLogger.app)
    }

    /// Check if an exercise ID is custom
    func isCustom(_ exerciseID: String) -> Bool {
        exerciseID.hasPrefix("custom_")
    }

    /// Get a custom exercise by ID
    func exercise(byID id: String) -> Exercise? {
        customExercises.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            AppLogger.debug("No custom exercises file found", category: AppLogger.app)
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let exercises = try decoder.decode([Exercise].self, from: data)
            self.customExercises = exercises.sorted { $0.name < $1.name }
            AppLogger.success("Loaded \(exercises.count) custom exercises", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to load custom exercises", error: error, category: AppLogger.app)

            // Try backup
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    let data = try Data(contentsOf: backupURL)
                    let exercises = try decoder.decode([Exercise].self, from: data)
                    self.customExercises = exercises.sorted { $0.name < $1.name }
                    AppLogger.success("Restored \(exercises.count) custom exercises from backup", category: AppLogger.app)
                } catch {
                    AppLogger.error("Failed to restore from backup", error: error, category: AppLogger.app)
                }
            }
        }
    }

    private func save() {
        do {
            // Create backup of current file
            if fileManager.fileExists(atPath: storageURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: storageURL, to: backupURL)
            }

            // Save current exercises
            let data = try encoder.encode(customExercises)
            try data.write(to: storageURL, options: [.atomic])

            // Enable file protection
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: storageURL.path
            )

            AppLogger.debug("Saved \(customExercises.count) custom exercises", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to save custom exercises", error: error, category: AppLogger.app)
        }
    }
}
