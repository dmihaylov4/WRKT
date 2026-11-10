import Foundation
import SwiftData
import Combine

/// Owns the user store. Failure leaves it closed; no temporary replacement is exposed.
@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var error: Error?
    private(set) var recoveryCopy: URL?
    let storeURL: URL
    private let backup: UpgradeBackup
    private let preferences: () -> [String: Any]

    static var defaultStoreURL: URL {
        ModelConfiguration(schema: Schema(AppStoreSchema.models), groupContainer: .none, cloudKitDatabase: .none).url
    }

    init(storeURL: URL? = nil,
         documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
         preferences: @escaping () -> [String: Any] = {
             UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.dmihaylov.trak") ?? [:]
         }) {
        let storeURL = storeURL ?? Self.defaultStoreURL
        self.storeURL = storeURL
        self.preferences = preferences
        let support = storeURL.deletingLastPathComponent()
        self.backup = UpgradeBackup(applicationSupport: support, documents: documents,
            destination: support.appendingPathComponent("UpgradeBackups/before-schema-v2"))
        retry()
    }

    func retry() {
        guard container == nil else { return }
        do {
            recoveryCopy = try backup.createIfNeeded(preferences: preferences())
            try WorkoutStorage.validateExistingData(applicationSupport: backup.applicationSupport, documents: backup.documents)
            let schema = Schema(versionedSchema: AppStoreSchema.self)
            let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, migrationPlan: AppStoreMigration.self, configurations: config)
            error = nil
        } catch {
            self.error = error
            AppLogger.error("User storage remains closed to preserve existing data", error: error, category: AppLogger.storage)
        }
    }
}
