import SwiftUI
import UIKit

struct StorageRecoveryView: View {
    let recoveryCopy: URL?
    let retry: () -> Void
    /// Why storage could not open, when known. A history saved by a newer version of the app
    /// (a per-workout history needing a newer reader) shows an update action instead of a plain retry.
    var error: Error? = nil
    /// Opens the App Store's updates page. Replace with the app's own App Store link once its id
    /// is recorded in the project.
    static let updateURL = URL(string: "itms-apps://apps.apple.com/updates")!

    private var needsNewerApp: Bool { (error as? StorageError)?.needsNewerApp == true }
    @State private var showingExport = false
    /// The copy is offered only once it verifies here: a launch may have skipped hashing it.
    @State private var verifiedCopy: URL?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(DS.Semantic.brand)
            Text(needsNewerApp ? "Update Volia to open your history" : "Your saved data needs attention")
                .font(DS.Typography.font(.title))
                .foregroundStyle(DS.Semantic.textPrimary)
            Text(needsNewerApp
                 ? "Your workout history was saved by a newer version of Volia. Update the app to open it. Nothing has been changed."
                 : "Volia couldn’t open your saved data. Changes are paused to protect it. Keep the app installed, unlock your device, and try again.")
                .font(DS.Typography.font(.body))
                .foregroundStyle(DS.Semantic.textSecondary)
            if needsNewerApp {
                Button("Update Volia") { UIApplication.shared.open(Self.updateURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Semantic.brand)
                Button("Try Again") { retry() }
                    .foregroundStyle(DS.Semantic.brand)
            } else {
                Button("Try Again") { retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Semantic.brand)
            }
            if verifiedCopy != nil {
                Button("Save a Recovery Copy") { showingExport = true }
                    .foregroundStyle(DS.Semantic.brand)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Semantic.surface)
        .sheet(isPresented: $showingExport) {
            if let copy = verifiedCopy { RecoveryCopyExporter(url: copy) }
        }
        .task(id: recoveryCopy) {
            let copy = recoveryCopy
            verifiedCopy = await Task.detached(priority: .userInitiated) {
                UpgradeBackup.verifiedRecoveryCopy(copy)
            }.value
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
            StorageRecoveryView(recoveryCopy: recoveryCopy, retry: store.retryStorageLoad, error: store.storageLoadError)
                .onAppear { LaunchSplashState.shared.isContentReady = true }
        } else {
            LaunchHoldView()
        }
    }
}

/// The launch screen's still mark on black, under the clap while the store opens and history loads.
struct LaunchHoldView: View {
    var body: some View {
        ZStack {
            Color.black
            LaunchClapMark(elapsed: 0, reduceMotion: false)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening your history")
    }
}
