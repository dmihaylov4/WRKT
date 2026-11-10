import SwiftUI
import UIKit

struct StorageRecoveryView: View {
    let recoveryCopy: URL?
    let retry: () -> Void
    @State private var showingExport = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(DS.Semantic.brand)
            Text("Your saved data needs attention")
                .font(DS.Typography.font(.title))
                .foregroundStyle(DS.Semantic.textPrimary)
            Text("Volia couldn’t open your saved data. Changes are paused to protect it. Keep the app installed, unlock your device, and try again.")
                .font(DS.Typography.font(.body))
                .foregroundStyle(DS.Semantic.textSecondary)
            Button("Try Again") { retry() }
                .buttonStyle(.borderedProminent)
                .tint(DS.Semantic.brand)
            if recoveryCopy != nil {
                Button("Save a Recovery Copy") { showingExport = true }
                    .foregroundStyle(DS.Semantic.brand)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Semantic.surface)
        .sheet(isPresented: $showingExport) {
            if let copy = recoveryCopy { RecoveryCopyExporter(url: copy) }
        }
    }
}

private struct RecoveryCopyExporter: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
}

/// The main interface is unavailable until history has actually loaded.
struct WorkoutDataGate: View {
    @ObservedObject private var store = AppDependencies.shared.workoutStore
    let recoveryCopy: URL?

    var body: some View {
        if store.isStorageLoaded {
            AppShellView()
        } else if store.storageLoadError != nil {
            StorageRecoveryView(recoveryCopy: recoveryCopy, retry: store.retryStorageLoad)
        } else {
            ProgressView("Opening your history")
                .tint(DS.Semantic.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Semantic.surface)
        }
    }
}
