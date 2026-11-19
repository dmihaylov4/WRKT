import Foundation
import SwiftData
import Combine

/// Owns the user store. Failure leaves it closed; no temporary replacement is exposed.
/// The open runs off the main thread so it does not hold back the first frame. While it runs,
/// `container` is nil and `isOpening` is true, and nothing may read or write app data.
@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var error: Error?
    /// True from the start of an open until it succeeds or fails.
    @Published private(set) var isOpening = false
    private(set) var recoveryCopy: URL?
    /// nil means the default location, resolved off the main thread (it builds the schema).
    private let storeURL: URL?
    private let documents: URL
    private let preferences: () -> [String: Any]
    private let handOffHistory: (ValidatedHistory) async -> Void
    private var openTask: Task<Void, Never>?

    nonisolated static var defaultStoreURL: URL {
        ModelConfiguration(schema: Schema(AppStoreSchema.models), groupContainer: .none, cloudKitDatabase: .none).url
    }

    /// `handOffHistory` receives what validation decoded, before the container is published,
    /// so the first history load can use it instead of decoding the same files again.
    init(storeURL: URL? = nil,
         documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
         preferences: @escaping () -> [String: Any] = {
             UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.dmihaylov.trak") ?? [:]
         },
         handOffHistory: @escaping (ValidatedHistory) async -> Void = { _ in }) {
        self.storeURL = storeURL
        self.documents = documents
        self.preferences = preferences
        self.handOffHistory = handOffHistory
        retry()
    }

    /// Starts an open unless the store is already open or an open is running.
    func retry() {
        guard container == nil, openTask == nil else { return }
        isOpening = true
        let storeURL = storeURL
        let documents = documents
        // Property list values from UserDefaults are immutable.
        nonisolated(unsafe) let preferences = preferences()
        openTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.open(storeURL: storeURL, documents: documents, preferences: preferences)
            }.value
            if let copy = result.recoveryCopy { recoveryCopy = copy }
            switch result.outcome {
            case .success(let opened):
                if let history = opened.history { await handOffHistory(history) }
                container = opened.container
                error = nil
            case .failure(let failure):
                error = failure
                AppLogger.error("User storage remains closed to preserve existing data", error: failure, category: AppLogger.storage)
            }
            isOpening = false
            openTask = nil
        }
    }

    /// The container once any open in progress has finished, or nil if the store is closed.
    func openedContainer() async -> ModelContainer? {
        await openTask?.value
        return container
    }

    private struct OpenResult: @unchecked Sendable {
        let recoveryCopy: URL?
        let outcome: Result<(container: ModelContainer, history: ValidatedHistory?), Error>
    }

    /// The backup is created or verified and existing data validated before any database is opened.
    nonisolated private static func open(storeURL: URL?, documents: URL, preferences: [String: Any]) -> OpenResult {
        let storeURL = storeURL ?? defaultStoreURL
        let support = storeURL.deletingLastPathComponent()
        let backup = UpgradeBackup(applicationSupport: support, documents: documents,
            destination: support.appendingPathComponent("UpgradeBackups/before-schema-v2"))
        var recoveryCopy: URL?
        do {
            recoveryCopy = try backup.createIfNeeded(preferences: preferences)
            let history = try WorkoutStorage.validateExistingData(applicationSupport: backup.applicationSupport,
                                                                  documents: backup.documents)
            let schema = Schema(versionedSchema: AppStoreSchema.self)
            let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: AppStoreMigration.self, configurations: config)
            return OpenResult(recoveryCopy: recoveryCopy, outcome: .success((container, history)))
        } catch {
            return OpenResult(recoveryCopy: recoveryCopy, outcome: .failure(error))
        }
    }
}
