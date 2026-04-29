# Data Portability (Export / Import) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users export strength workout data and earned plates to a JSON file, import it back with merge or replace strategies, and view/undo past imports.

**Architecture:** A versioned JSON envelope (`ExportBundle`) holds Codable mirrors of persisted data. A `@MainActor` service (`DataPortabilityService`) reads from `WorkoutStorage` and SwiftData, writes export files, snapshots state before each import, and applies imports with dedup logic. `ImportHistoryView` lists past imports and lets users restore to any prior snapshot.

**Tech Stack:** Swift / SwiftUI, SwiftData (`ModelContext`), `WorkoutStorage` actor, `UIActivityViewController` for sharing

---

## What is exported

| Data | Source | Dedup key on import |
|------|--------|---------------------|
| `[CompletedWorkout]` | `WorkoutStorage.loadWorkouts()` | `id` |
| `[EarnedPlate]` | SwiftData query | `id` |

**Not exported:** Cardio runs (HealthKit — re-sync from Apple Health), `BarbellConfig` (derived counters + internal flags, not worth restoring), Supabase social data (server-side), `PlannedWorkout` (ephemeral planning).

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Core/Models/ExportBundle.swift` | Create | Versioned Codable envelope + mirror structs for SwiftData models |
| `Core/Models/ImportRecord.swift` | Create | Codable record of a past import + snapshot file reference |
| `Core/Services/DataPortabilityService.swift` | Create | `@MainActor` class: export, snapshot, import, import history, restore |
| `Features/Profile/Views/DataPortabilityView.swift` | Create | SwiftUI List with export + import controls |
| `Features/Profile/Views/ImportHistoryView.swift` | Create | List of past imports with restore (undo) action |
| `WRKTTests/CoreTests/DataPortabilityTests.swift` | Create | Unit tests for merge logic and snapshot dedup |
| `Features/Profile/Views/SettingsView.swift` | Modify | Add "Data Portability" NavigationLink in Preferences section |

---

## Task 1: ExportBundle and ImportRecord models

**Files:**
- Create: `Core/Models/ExportBundle.swift`
- Create: `Core/Models/ImportRecord.swift`

- [ ] **Step 1: Write the failing test**

`WRKTTests/CoreTests/DataPortabilityTests.swift`:

```swift
import Testing
import Foundation
@testable import WRKT

@Suite("ExportBundle")
struct ExportBundleTests {
    @Test("round-trips through JSON without data loss")
    func roundTrip() throws {
        let plate = EarnedPlateExport(
            id: "abc", tierID: 1, weightKg: 5.0, engravingText: "First",
            earnedAt: Date(timeIntervalSince1970: 2_000_000), earnedByEvent: "first_workout",
            sourceWorkoutID: nil, isRacked: false, rackPosition: nil, displayOrder: 2_000_000
        )
        var workout = CompletedWorkout(entries: [])
        workout.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let bundle = ExportBundle(
            version: ExportBundle.currentVersion,
            appVersion: "1.0",
            exportedAt: Date(timeIntervalSince1970: 3_000_000),
            completedWorkouts: [workout],
            earnedPlates: [plate]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(ExportBundle.self, from: data)

        #expect(decoded.version == ExportBundle.currentVersion)
        #expect(decoded.completedWorkouts.count == 1)
        #expect(decoded.earnedPlates.count == 1)
        #expect(decoded.earnedPlates[0].id == "abc")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cmd+U in Xcode — expected: compile error "cannot find ExportBundle in scope"
```

- [ ] **Step 3: Create ExportBundle.swift**

`Core/Models/ExportBundle.swift`:

```swift
//
//  ExportBundle.swift
//  WRKT
//
//  Versioned Codable envelope for data export/import.
//  Excluded: cardio runs (HealthKit), BarbellConfig (derived/internal state).
//

import Foundation

// MARK: - Envelope

struct ExportBundle: Codable {
    static let currentVersion = 1

    let version: Int
    let appVersion: String
    let exportedAt: Date
    let completedWorkouts: [CompletedWorkout]
    let earnedPlates: [EarnedPlateExport]
}

// MARK: - EarnedPlate mirror (EarnedPlate is @Model, not Codable)

struct EarnedPlateExport: Codable {
    let id: String
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let earnedAt: Date
    let earnedByEvent: String
    let sourceWorkoutID: String?
    let isRacked: Bool
    let rackPosition: Int?
    let displayOrder: Int
}

extension EarnedPlateExport {
    init(_ plate: EarnedPlate) {
        self.init(
            id: plate.id,
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            earnedAt: plate.earnedAt,
            earnedByEvent: plate.earnedByEvent,
            sourceWorkoutID: plate.sourceWorkoutID,
            isRacked: plate.isRacked,
            rackPosition: plate.rackPosition,
            displayOrder: plate.displayOrder
        )
    }

    func toModel() -> EarnedPlate {
        let plate = EarnedPlate(
            id: id,
            tierID: tierID,
            weightKg: weightKg,
            engravingText: engravingText,
            earnedAt: earnedAt,
            earnedByEvent: earnedByEvent,
            sourceWorkoutID: sourceWorkoutID,
            isRacked: isRacked,
            rackPosition: rackPosition
        )
        plate.displayOrder = displayOrder
        return plate
    }
}
```

- [ ] **Step 4: Create ImportRecord.swift**

`Core/Models/ImportRecord.swift`:

```swift
//
//  ImportRecord.swift
//  WRKT
//
//  Tracks a past import. Each record points to a snapshot file containing
//  the app state immediately before the import was applied — used for restore.
//

import Foundation

struct ImportRecord: Codable, Identifiable {
    let id: UUID
    let importedAt: Date
    let sourceFileName: String      // original filename the user picked
    let strategy: String            // "merge" | "replace"
    let workoutsAdded: Int
    let platesAdded: Int
    let snapshotFileName: String    // filename inside Documents/volia-snapshots/
}
```

- [ ] **Step 5: Run test to verify it passes**

```
cmd+U — expected: PASS
```

- [ ] **Step 6: Commit**

```bash
git add Core/Models/ExportBundle.swift Core/Models/ImportRecord.swift WRKTTests/CoreTests/DataPortabilityTests.swift
git commit -m "feat: add ExportBundle and ImportRecord models"
```

---

## Task 2: DataPortabilityService

**Files:**
- Create: `Core/Services/DataPortabilityService.swift`

- [ ] **Step 1: Write failing tests for merge logic**

Add to `WRKTTests/CoreTests/DataPortabilityTests.swift`:

```swift
@Suite("Merge logic")
struct MergeTests {
    @Test("merge workouts deduplicates by id")
    func mergeWorkoutsByID() {
        let id = UUID()
        var w1 = CompletedWorkout(entries: []); w1.id = id
        var w2 = CompletedWorkout(entries: []); w2.id = id
        var w3 = CompletedWorkout(entries: [])

        let result = DataPortabilityService.mergedWorkouts(
            existing: [w1],
            incoming: [w2, w3]
        )
        #expect(result.count == 2)  // w1 kept, w2 filtered as duplicate, w3 added
    }

    @Test("merge workouts with no overlap appends all incoming")
    func mergeWorkoutsNoOverlap() {
        let w1 = CompletedWorkout(entries: [])
        let w2 = CompletedWorkout(entries: [])

        let result = DataPortabilityService.mergedWorkouts(existing: [w1], incoming: [w2])
        #expect(result.count == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cmd+U — expected: compile error "cannot find DataPortabilityService in scope"
```

- [ ] **Step 3: Create DataPortabilityService.swift**

`Core/Services/DataPortabilityService.swift`:

```swift
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

        // Apply import — clean up orphaned snapshot if it fails
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
```

- [ ] **Step 4: Add reloadWorkouts() to WorkoutStoreV2**

`DataPortabilityService` writes to `WorkoutStorage` on disk but `WorkoutStoreV2` holds a separate in-memory copy that is only populated at app launch. After any import or restore, call this method to sync in-memory state from disk.

In `Features/WorkoutSession/Services/WorkoutStoreV2.swift`, find the `// MARK: - Init` section and add the following method in the public API section (near `clearAllWorkouts()` or `addWorkout(_:)`):

```swift
/// Reloads completed workouts and PR index from disk into in-memory state.
/// Call after any external write to WorkoutStorage (e.g., data import or restore).
func reloadWorkouts() async throws {
    let (workouts, prIndex) = try await storage.loadWorkouts()
    self.completedWorkouts = workouts.sorted(by: { $0.date < $1.date })
    self.prIndex = prIndex
}
```

- [ ] **Step 5: Run tests to verify they pass**

```
cmd+U — expected: all DataPortabilityTests PASS
```

- [ ] **Step 6: Commit**

```bash
git add Core/Services/DataPortabilityService.swift Features/WorkoutSession/Services/WorkoutStoreV2.swift WRKTTests/CoreTests/DataPortabilityTests.swift
git commit -m "feat: add DataPortabilityService and WorkoutStoreV2.reloadWorkouts"
```

---

## Task 3: DataPortabilityView

**Files:**
- Create: `Features/Profile/Views/DataPortabilityView.swift`

- [ ] **Step 1: Create the view**

`Features/Profile/Views/DataPortabilityView.swift`:

```swift
//
//  DataPortabilityView.swift
//  WRKT
//
//  Export and import strength workouts and earned plates.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Share Sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Required on iPad: prevents crash from missing popover anchor
        vc.popoverPresentationController?.sourceView = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - View

struct DataPortabilityView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: WorkoutStoreV2
    @State private var service = DataPortabilityService()

    @State private var exportURL: URL?
    @State private var showShare = false

    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showImportConfirm = false
    @State private var importStrategy: ImportStrategy = .merge

    @State private var lastSummary: ImportSummary?
    @State private var errorMessage: String?

    var body: some View {
        List {
            // MARK: Export
            Section {
                if service.isExporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing export...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await runExport() }
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Saves strength workouts and earned plates to a JSON file. Cardio runs are excluded — re-sync them from Apple Health.")
            }

            // MARK: Import
            Section {
                Picker("Strategy", selection: $importStrategy) {
                    Text("Merge (keep newer)").tag(ImportStrategy.merge)
                    Text("Replace all data").tag(ImportStrategy.replace)
                }

                if service.isImporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importing...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Merge adds only items not already present. Replace overwrites all existing data — a snapshot is saved automatically so you can undo.")
            }

            // MARK: Last import result
            if let s = lastSummary {
                Section("Last Import") {
                    LabeledContent("Workouts added", value: "\(s.workoutsAdded)")
                    LabeledContent("Plates added", value: "\(s.platesAdded)")
                }
            }

            // MARK: Import history link
            Section {
                NavigationLink {
                    ImportHistoryView(service: service)
                } label: {
                    Label("Import History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
            }
        }
        .navigationTitle("Data Portability")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.configure(context: modelContext) }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(url: url) }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                pendingImportURL = urls.first
                showImportConfirm = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            importStrategy == .replace
                ? "Replace all existing data with this backup?"
                : "Add new items from this backup?",
            isPresented: $showImportConfirm,
            titleVisibility: .visible
        ) {
            Button(
                importStrategy == .replace ? "Replace" : "Merge",
                role: importStrategy == .replace ? .destructive : nil
            ) {
                guard let url = pendingImportURL else { return }
                Task { await runImport(from: url) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func runExport() async {
        do {
            exportURL = try await service.makeExportURL()
            showShare = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runImport(from url: URL) async {
        do {
            lastSummary = try await service.importBundle(from: url, strategy: importStrategy)
            // Sync WorkoutStoreV2 in-memory state from the newly written disk data
            try await store.reloadWorkouts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```
cmd+B — expected: BUILD SUCCEEDED
```

- [ ] **Step 3: Commit**

```bash
git add Features/Profile/Views/DataPortabilityView.swift
git commit -m "feat: add DataPortabilityView"
```

---

## Task 4: ImportHistoryView

**Files:**
- Create: `Features/Profile/Views/ImportHistoryView.swift`

- [ ] **Step 1: Create the view**

`Features/Profile/Views/ImportHistoryView.swift`:

```swift
//
//  ImportHistoryView.swift
//  WRKT
//
//  Lists past imports. Restoring an import reverts state to the snapshot
//  taken immediately before that import was applied. All later imports
//  are also removed.
//

import SwiftUI
import SwiftData

struct ImportHistoryView: View {
    let service: DataPortabilityService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: WorkoutStoreV2

    @State private var records: [ImportRecord] = []
    @State private var recordToRestore: ImportRecord?
    @State private var showRestoreConfirm = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Import History",
                    systemImage: "clock",
                    description: Text("Imports you apply will appear here.")
                )
            } else {
                ForEach(records.reversed()) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.sourceFileName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(record.strategy == "replace" ? "Replace" : "Merge")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(record.strategy == "replace" ? .orange : .green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    (record.strategy == "replace" ? Color.orange : Color.green).opacity(0.15),
                                    in: Capsule()
                                )
                        }

                        Text(record.importedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label("\(record.workoutsAdded) workouts", systemImage: "dumbbell")
                            Label("\(record.platesAdded) plates", systemImage: "scalemass")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            recordToRestore = record
                            showRestoreConfirm = true
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .navigationTitle("Import History")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await loadRecords() }
        .confirmationDialog(restoreConfirmTitle, isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                guard let record = recordToRestore else { return }
                Task { await runRestore(record: record) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var restoreConfirmTitle: String {
        guard let record = recordToRestore,
              let idx = records.firstIndex(where: { $0.id == record.id }) else {
            return "Restore to this point?"
        }
        let laterCount = records.count - 1 - idx
        if laterCount > 0 {
            return "Restore to this point? \(laterCount) later import(s) will also be removed."
        }
        return "Restore state to before this import?"
    }

    private func loadRecords() async {
        do {
            records = try await service.loadImportRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runRestore(record: ImportRecord) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.restore(to: record, context: modelContext)
            // Sync WorkoutStoreV2 in-memory state from the newly written disk data
            try await store.reloadWorkouts()
            records = try await service.loadImportRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```
cmd+B — expected: BUILD SUCCEEDED
```

- [ ] **Step 3: Commit**

```bash
git add Features/Profile/Views/ImportHistoryView.swift
git commit -m "feat: add ImportHistoryView with swipe-to-restore"
```

---

## Task 5: Wire into SettingsView

**Files:**
- Modify: `Features/Profile/Views/SettingsView.swift`

- [ ] **Step 1: Add NavigationLink in Preferences section**

In `Features/Profile/Views/SettingsView.swift`, find the Preferences section and add one link:

```swift
// Before:
Section("Preferences") {
    NavigationLink("App Preferences") { PreferencesView() }
    NavigationLink("Apple Health") { ConnectionsView() }
    NavigationLink {
        BarbellPreviewView()
    } label: {
        Label("My Barbell", systemImage: "scalemass.fill")
    }
}

// After:
Section("Preferences") {
    NavigationLink("App Preferences") { PreferencesView() }
    NavigationLink("Apple Health") { ConnectionsView() }
    NavigationLink {
        BarbellPreviewView()
    } label: {
        Label("My Barbell", systemImage: "scalemass.fill")
    }
    NavigationLink {
        DataPortabilityView()
    } label: {
        Label("Data Portability", systemImage: "arrow.up.arrow.down.circle")
    }
}
```

- [ ] **Step 2: Build and run on simulator**

```
cmd+R — Me tab -> Settings -> Preferences -> Data Portability
Verify: export button, import button, strategy picker, Import History link all visible
```

- [ ] **Step 3: Test export**

```
Tap "Export Backup"
Expected: share sheet appears with "volia-backup-YYYY-MM-DD.json"
Save to Files app
Open in text editor: confirm JSON has "version":1, "completedWorkouts":[...], "earnedPlates":[...]
Confirm no "runs" key present
```

- [ ] **Step 4: Test import + history**

```
Import the exported file (strategy: Merge)
Tap Merge
Expected: "Last Import" shows "Workouts added: 0, Plates added: 0" (self-import, all deduplicated)
Tap Import History
Expected: one entry listed with sourceFileName, date, Merge badge
```

- [ ] **Step 5: Test restore**

```
In Import History, swipe left on the entry
Tap Restore
Expected: confirmation dialog mentions the import
Tap Restore (destructive)
Expected: entry removed from history, no crash, data unchanged (snapshot matched live state)
```

- [ ] **Step 6: Commit**

```bash
git add Features/Profile/Views/SettingsView.swift
git commit -m "feat: add Data Portability entry to Settings"
```

---

## Future extensions (out of scope)

- Custom `.volia` UTType so the app opens backup files from Mail/AirDrop directly
- Export progress indicator for very large workout histories (>2000 entries)
- Encrypt exports with user passphrase
