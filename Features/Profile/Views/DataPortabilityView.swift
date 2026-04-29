//
//  DataPortabilityView.swift
//  WRKT
//
//  Export and import strength workouts and earned plates.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

// MARK: - Share Sheet bridge

private struct DataPortabilityShareSheet: UIViewControllerRepresentable {
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
                Text("Saves strength workouts and earned plates to a JSON file. Cardio runs are excluded -- re-sync them from Apple Health.")
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
                Text("Merge adds only items not already present. Replace overwrites all existing data -- a snapshot is saved automatically so you can undo.")
            }

            // MARK: Last import result
            if let s = lastSummary {
                Section("Last Import") {
                    LabeledContent(
                        s.record.strategy == "replace" ? "Workouts imported" : "Workouts added",
                        value: "\(s.workoutsAdded)"
                    )
                    LabeledContent(
                        s.record.strategy == "replace" ? "Plates imported" : "Plates added",
                        value: "\(s.platesAdded)"
                    )
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
            if let url = exportURL { DataPortabilityShareSheet(url: url) }
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
