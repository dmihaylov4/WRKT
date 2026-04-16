//
//  DataPortabilityService.swift
//  WRKT
//
//  Handles export, import, import history, and snapshot-based restore.
//  @MainActor because all SwiftData (ModelContext) access must be on MainActor.
//

import Foundation
import SwiftData

// MARK: - Supporting types

enum ImportStrategy: String {
    case merge    // keep existing, append items not already present
    case replace  // discard existing, use imported data as-is
}

enum PortabilityError: LocalizedError {
    case notConfigured
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "DataPortabilityService has not been configured with a ModelContext."
        case .unsupportedVersion(let v):
            return "Backup version \(v) is newer than this app supports. Update the app and try again."
        }
    }
}

struct ImportSummary {
    let record: ImportRecord
    let workoutsAdded: Int
    let platesAdded: Int
}

// MARK: - Service

@Observable @MainActor
final class DataPortabilityService {

    var isExporting = false
    var isImporting = false

    private var context: ModelContext?

    // Snapshot directory: Documents/volia-snapshots/
    private var snapshotDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("volia-snapshots", isDirectory: true)
    }

    // Import records file: Documents/volia-import-records.json
    private var importRecordsURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("volia-import-records.json")
    }

    private let maxSnapshots = 10

    func configure(context: ModelContext) {
        self.context = context
    }

    // MARK: - Export

    func makeExportURL() async throws -> URL {
        isExporting = true
        defer { isExporting = false }
        guard let context else { throw PortabilityError.notConfigured }

        let bundle = try await buildBundle(context: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("volia-backup-\(formatter.string(from: Date())).json")
        try data.write(to: url)
        return url
    }

    private func buildBundle(context: ModelContext) async throws -> ExportBundle {
        let (workouts, _) = try await WorkoutStorage.shared.loadWorkouts()
        let plates = try context.fetch(FetchDescriptor<EarnedPlate>())

        return ExportBundle(
            version: ExportBundle.currentVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            exportedAt: Date(),
            completedWorkouts: workouts,
            earnedPlates: plates.map(EarnedPlateExport.init)
        )
    }

    // MARK: - Import

    func importBundle(from url: URL, strategy: ImportStrategy) async throws -> ImportSummary {
        isImporting = true
        defer { isImporting = false }
        guard let context else { throw PortabilityError.notConfigured }

        // Read the file (handles security-scoped URLs from .fileImporter)
        let data: Data
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            data = try Data(contentsOf: url)
        } else {
            data = try Data(contentsOf: url)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        guard bundle.version <= ExportBundle.currentVersion else {
            throw PortabilityError.unsupportedVersion(bundle.version)
        }

        // Snapshot current state before making any changes
        let snapshotID = UUID()
        let snapshotFileName = "snapshot-\(snapshotID.uuidString).json"
        try await saveSnapshot(fileName: snapshotFileName, context: context)

        // Apply import -- clean up orphaned snapshot if it fails
        let workoutsAdded: Int
        let platesAdded: Int
        do {
            (workoutsAdded, platesAdded) = try await applyBundle(bundle, strategy: strategy, context: context)
        } catch {
            try? FileManager.default.removeItem(
                at: snapshotDirectory.appendingPathComponent(snapshotFileName)
            )
            throw error
        }

        // Record the import
        let record = ImportRecord(
            id: snapshotID,
            importedAt: Date(),
            sourceFileName: url.lastPathComponent,
            strategy: strategy.rawValue,
            workoutsAdded: workoutsAdded,
            platesAdded: platesAdded,
            snapshotFileName: snapshotFileName
        )
        try await appendImportRecord(record)
        try await pruneSnapshotsIfNeeded()

        return ImportSummary(record: record, workoutsAdded: workoutsAdded, platesAdded: platesAdded)
    }

    private func applyBundle(
        _ bundle: ExportBundle,
        strategy: ImportStrategy,
        context: ModelContext
    ) async throws -> (workoutsAdded: Int, platesAdded: Int) {
        // --- CompletedWorkouts ---
        let (existingWorkouts, prIndex) = try await WorkoutStorage.shared.loadWorkouts()
        let finalWorkouts: [CompletedWorkout]
        let workoutsAdded: Int
        switch strategy {
        case .merge:
            let existingIDs = Set(existingWorkouts.map(\.id))
            let newOnly = bundle.completedWorkouts.filter { !existingIDs.contains($0.id) }
            finalWorkouts = existingWorkouts + newOnly
            workoutsAdded = newOnly.count
        case .replace:
            finalWorkouts = bundle.completedWorkouts
            workoutsAdded = bundle.completedWorkouts.count
        }
        try await WorkoutStorage.shared.saveWorkouts(finalWorkouts, prIndex: prIndex)

        // --- EarnedPlates ---
        let existingPlates = try context.fetch(FetchDescriptor<EarnedPlate>())
        var platesAdded = 0
        switch strategy {
        case .replace:
            // Delete all current plates, then insert from bundle
            for plate in existingPlates { context.delete(plate) }
            for export in bundle.earnedPlates {
                context.insert(export.toModel())
                platesAdded += 1
            }
        case .merge:
            // Insert only plates not already present
            let existingPlateIDs = Set(existingPlates.map(\.id))
            for export in bundle.earnedPlates where !existingPlateIDs.contains(export.id) {
                context.insert(export.toModel())
                platesAdded += 1
            }
        }
        try context.save()

        return (workoutsAdded, platesAdded)
    }

    // MARK: - Snapshot

    private func saveSnapshot(fileName: String, context: ModelContext) async throws {
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let bundle = try await buildBundle(context: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let url = snapshotDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
    }

    private func pruneSnapshotsIfNeeded() async throws {
        var records = try await loadImportRecords()
        guard records.count > maxSnapshots else { return }
        let toRemove = records.prefix(records.count - maxSnapshots)
        for record in toRemove {
            let url = snapshotDirectory.appendingPathComponent(record.snapshotFileName)
            try? FileManager.default.removeItem(at: url)
        }
        records = Array(records.suffix(maxSnapshots))
        try await saveImportRecords(records)
    }

    // MARK: - Import History

    func loadImportRecords() async throws -> [ImportRecord] {
        guard FileManager.default.fileExists(atPath: importRecordsURL.path) else { return [] }
        let data = try Data(contentsOf: importRecordsURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ImportRecord].self, from: data)
    }

    private func appendImportRecord(_ record: ImportRecord) async throws {
        var records = try await loadImportRecords()
        records.append(record)
        try await saveImportRecords(records)
    }

    private func saveImportRecords(_ records: [ImportRecord]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: importRecordsURL, options: .atomic)
    }

    // MARK: - Restore

    /// Restores state to immediately before `record` was applied.
    /// Also removes `record` and all records applied after it.
    func restore(to record: ImportRecord, context: ModelContext) async throws {
        isImporting = true
        defer { isImporting = false }

        // Load snapshot
        let snapshotURL = snapshotDirectory.appendingPathComponent(record.snapshotFileName)
        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(ExportBundle.self, from: data)

        // Apply as replace (full restore)
        _ = try await applyBundle(snapshot, strategy: .replace, context: context)

        // Remove this record and all records applied after it, plus their snapshots
        var records = try await loadImportRecords()
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        let toDelete = records[idx...]
        for r in toDelete {
            let url = snapshotDirectory.appendingPathComponent(r.snapshotFileName)
            try? FileManager.default.removeItem(at: url)
        }
        records = Array(records.prefix(idx))
        try await saveImportRecords(records)
    }

    // MARK: - Pure merge helpers (static so tests call without MainActor)

    static func mergedWorkouts(existing: [CompletedWorkout], incoming: [CompletedWorkout]) -> [CompletedWorkout] {
        let existingIDs = Set(existing.map(\.id))
        return existing + incoming.filter { !existingIDs.contains($0.id) }
    }
}
