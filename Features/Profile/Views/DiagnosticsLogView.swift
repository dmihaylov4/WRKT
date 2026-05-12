import SwiftUI
import UIKit

struct DiagnosticsLogView: View {
    @State private var shareItem: DiagnosticsShareItem?
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    exportDiagnostics()
                } label: {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    clearDiagnostics()
                } label: {
                    Label("Clear Diagnostics", systemImage: "trash")
                }
            } footer: {
                Text("Exports a local log used for support debugging. It records app events and barbell interaction state, not passwords or tokens.")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            DiagnosticsShareSheet(url: item.url)
        }
    }

    private func exportDiagnostics() {
        do {
            shareItem = DiagnosticsShareItem(url: try DiagnosticsLogStore.shared.exportFileURL())
            statusMessage = nil
        } catch {
            statusMessage = "Could not prepare diagnostics: \(error.localizedDescription)"
        }
    }

    private func clearDiagnostics() {
        do {
            try DiagnosticsLogStore.shared.clear()
            statusMessage = "Diagnostics cleared."
        } catch {
            statusMessage = "Could not clear diagnostics: \(error.localizedDescription)"
        }
    }
}

private struct DiagnosticsShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DiagnosticsShareSheet: UIViewControllerRepresentable {
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
