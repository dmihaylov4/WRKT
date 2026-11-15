//
//  CutDataPortabilityHost.swift
//  WRKT
//
//  DataPortabilityView's and ImportHistoryView's state behind the Cut pages: the same
//  DataPortabilityService configured with the model context, export to a JSON file handed to
//  the system share sheet, the JSON file importer, the strategy-worded confirmation, the store
//  reload after an import or restore, the restore confirmation, and the error alerts.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct CutDataPortabilityHost: View {
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
    @State private var showsHistory = false

    var body: some View {
        CutDataPortabilityView(
            model: CutDataPortabilityLogic.model(isExporting: service.isExporting, isImporting: service.isImporting,
                                                 last: lastSummary),
            strategy: Binding(
                get: { importStrategy.rawValue },
                set: { importStrategy = CutDataPortabilityLogic.strategy($0) }
            ),
            actions: CutDataPortabilityActions(
                export: { Task { await runExport() } },
                importBackup: { showImporter = true },
                openHistory: { showsHistory = true }
            )
        )
        .navigationDestination(isPresented: $showsHistory) {
            ImportHistoryView(service: service)
        }
        .onAppear { service.configure(context: modelContext) }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { CutSettingsShareSheet(url: url) }
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
            CutDataPortabilityLogic.confirmTitle(importStrategy),
            isPresented: $showImportConfirm,
            titleVisibility: .visible
        ) {
            Button(
                CutDataPortabilityLogic.confirmButton(importStrategy),
                role: CutDataPortabilityLogic.confirmIsDestructive(importStrategy) ? .destructive : nil
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
            try await store.reloadWorkouts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CutImportHistoryHost: View {
    let service: DataPortabilityService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: WorkoutStoreV2

    @State private var records: [ImportRecord] = []
    @State private var recordToRestore: ImportRecord?
    @State private var showRestoreConfirm = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        CutImportHistoryView(
            model: CutDataPortabilityLogic.history(records, isLoading: isLoading),
            restore: { id in
                recordToRestore = records.first { $0.id == id }
                showRestoreConfirm = recordToRestore != nil
            }
        )
        .task { await loadRecords() }
        .confirmationDialog(CutDataPortabilityLogic.restoreTitle(records: records, restoring: recordToRestore?.id),
                            isPresented: $showRestoreConfirm, titleVisibility: .visible) {
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
            try await store.reloadWorkouts()
            records = try await service.loadImportRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The system share sheet for one file, anchored for iPad as the legacy bridges are.
struct CutSettingsShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
