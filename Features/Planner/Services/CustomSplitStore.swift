//
//  CustomSplitStore.swift
//  WRKT
//
//  Custom workout split persistence and management

import Foundation
import Combine

@MainActor
final class CustomSplitStore: ObservableObject {
    static let shared = CustomSplitStore()

    @Published private(set) var customSplits: [SplitTemplate] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let storageURL: URL
    private let backupURL: URL

    // MARK: - Initialization

    private init() {
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Graceful fallback if documents directory is unavailable
        let documentsDir: URL
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            documentsDir = docDir
        } else {
            // Fallback to temporary directory if documents unavailable
            AppLogger.error("Documents directory not accessible, using temp directory", category: AppLogger.app)
            documentsDir = fileManager.temporaryDirectory
        }

        let storageDir = documentsDir.appendingPathComponent("WRKT_Storage", isDirectory: true)
        self.storageURL = storageDir.appendingPathComponent("custom_splits.json")
        self.backupURL = storageDir.appendingPathComponent("custom_splits_backup.json")

        do {
            try fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.error("Failed to create storage directory", error: error, category: AppLogger.app)
        }

        load()
    }

    // MARK: - Public API

    func add(_ split: SplitTemplate) throws {
        // Check limit
        guard customSplits.count < PlannerConstants.CustomSplit.maxCustomSplits else {
            throw SplitImportError.limitReached(PlannerConstants.CustomSplit.maxCustomSplits)
        }

        guard !customSplits.contains(where: { $0.id == split.id }) else {
            AppLogger.warning("Custom split already exists: \(split.id)", category: AppLogger.app)
            return
        }

        customSplits.append(split)
        customSplits.sort { $0.name < $1.name }
        save()

        AppLogger.success("Added custom split: \(split.name)", category: AppLogger.app)
    }

    func update(_ split: SplitTemplate) {
        guard let index = customSplits.firstIndex(where: { $0.id == split.id }) else {
            AppLogger.warning("Custom split not found: \(split.id)", category: AppLogger.app)
            return
        }

        customSplits[index] = split
        customSplits.sort { $0.name < $1.name }
        save()

        AppLogger.success("Updated custom split: \(split.name)", category: AppLogger.app)
    }

    func delete(_ splitID: String) {
        guard let index = customSplits.firstIndex(where: { $0.id == splitID }) else {
            AppLogger.warning("Custom split not found: \(splitID)", category: AppLogger.app)
            return
        }

        let name = customSplits[index].name
        customSplits.remove(at: index)
        save()

        AppLogger.success("Deleted custom split: \(name)", category: AppLogger.app)
    }

    func export(_ splitID: String) -> URL? {
        guard let split = customSplits.first(where: { $0.id == splitID }) else {
            return nil
        }

        do {
            let data = try encoder.encode(split)
            let tempURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(split.name.replacingOccurrences(of: " ", with: "_")).wrkt")
            try data.write(to: tempURL)
            return tempURL
        } catch {
            AppLogger.error("Failed to export split", error: error, category: AppLogger.app)
            return nil
        }
    }

    func `import`(from url: URL) throws -> SplitTemplate {
        let data = try Data(contentsOf: url)
        let split = try decoder.decode(SplitTemplate.self, from: data)

        // Validate exercises exist
        try validateExercises(split)

        return split
    }

    // MARK: - Validation

    private func validateExercises(_ split: SplitTemplate) throws {
        let repo = ExerciseRepository.shared

        for day in split.days {
            for exercise in day.exercises {
                guard repo.byID[exercise.exerciseID] != nil else {
                    throw SplitImportError.exerciseNotFound(exercise.exerciseName)
                }
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            AppLogger.debug("No custom splits file found", category: AppLogger.app)
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let splits = try decoder.decode([SplitTemplate].self, from: data)
            self.customSplits = splits.sorted { $0.name < $1.name }
            AppLogger.success("Loaded \(splits.count) custom splits", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to load custom splits", error: error, category: AppLogger.app)

            // Try backup
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    let data = try Data(contentsOf: backupURL)
                    let splits = try decoder.decode([SplitTemplate].self, from: data)
                    self.customSplits = splits.sorted { $0.name < $1.name }
                    AppLogger.success("Restored \(splits.count) custom splits from backup", category: AppLogger.app)
                } catch {
                    AppLogger.error("Failed to restore from backup", error: error, category: AppLogger.app)
                }
            }
        }
    }

    private func save() {
        do {
            // Create backup
            if fileManager.fileExists(atPath: storageURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: storageURL, to: backupURL)
            }

            // Save current
            let data = try encoder.encode(customSplits)
            try data.write(to: storageURL, options: [.atomic])

            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: storageURL.path
            )

            AppLogger.debug("Saved \(customSplits.count) custom splits", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to save custom splits", error: error, category: AppLogger.app)
        }
    }
}

enum SplitImportError: LocalizedError {
    case exerciseNotFound(String)
    case invalidFormat
    case incompatibleVersion
    case limitReached(Int)

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound(let name):
            return "Exercise '\(name)' not found in your exercise library"
        case .invalidFormat:
            return "Invalid split file format"
        case .incompatibleVersion:
            return "This split was created with a newer version of the app"
        case .limitReached(let max):
            return "You've reached the maximum of \(max) custom splits. Delete some splits to create new ones."
        }
    }
}
