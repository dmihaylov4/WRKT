import Foundation

/// Coalesces observer deliveries without losing a notification received during a sync.
/// The marker contains only an opaque generation, never health data.
@MainActor
final class HealthSyncDelivery {
    private let fileURL: URL
    private var worker: Task<Bool, Error>?

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HealthSync/pending")) {
        self.fileURL = fileURL
    }

    func receive(completion: () -> Void) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try Data(UUID().uuidString.utf8).write(to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        completion()
    }

    func drain(using synchronize: @escaping @MainActor () async -> Bool) async throws -> Bool {
        if let worker { return try await worker.value }
        let task = Task { @MainActor in
            defer { worker = nil }
            // Bound a burst; later delivery, foreground entry or BGProcessing resumes the rest.
            for _ in 0..<3 {
                try Task.checkCancellation()
                guard let generation = try pendingGeneration() else { return true }
                guard await synchronize() else { return false }
                try Task.checkCancellation()
                if try pendingGeneration() == generation {
                    try FileManager.default.removeItem(at: fileURL)
                    return true
                }
            }
            return false
        }
        worker = task
        return try await task.value
    }

    func cancel() { worker?.cancel() }

    private func pendingGeneration() throws -> Data? {
        do {
            return try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }
}

/// Expiration and normal completion can race; only the first outcome reaches iOS.
@MainActor
final class HealthSyncTaskCompletion {
    private var completion: ((Bool) -> Void)?
    var isFinished: Bool { completion == nil }

    init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }

    func finish(success: Bool) {
        let callback = completion
        completion = nil
        callback?(success)
    }
}
