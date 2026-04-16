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
                            Label(
                                record.strategy == "replace" ? "\(record.workoutsAdded) workouts" : "+\(record.workoutsAdded) workouts",
                                systemImage: "dumbbell"
                            )
                            Label(
                                record.strategy == "replace" ? "\(record.platesAdded) plates" : "+\(record.platesAdded) plates",
                                systemImage: "scalemass"
                            )
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
            // Sync WorkoutStoreV2 in-memory state from the restored disk data
            try await store.reloadWorkouts()
            records = try await service.loadImportRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
