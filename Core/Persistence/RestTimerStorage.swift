import Foundation

struct RestTimerRecord: Codable, Equatable {
    var schemaVersion = 1
    var id = UUID()
    var revision: UInt64 = 0
    var state: RestTimerState = .idle
    var startedAt: Date?
    var nextRestDuration: TimeInterval = 90
    var isManualStart = false
    var workoutID: UUID?
    var entryID: UUID?
    var appliedOperationIDs: [UUID]?

    func validate() throws {
        guard schemaVersion == 1 else { throw RestTimerStorageError.unsupportedVersion }
        guard nextRestDuration.isFinite, nextRestDuration > 0, nextRestDuration <= 86_400 else {
            throw RestTimerStorageError.invalidRecord
        }
        switch state {
        case .idle:
            break
        case .running(let endDate, let id, _, let duration, _):
            guard endDate.timeIntervalSince1970.isFinite, !id.isEmpty,
                  duration.isFinite, duration >= 0, duration <= 86_400 else {
                throw RestTimerStorageError.invalidRecord
            }
        case .paused(let remaining, let id, _, let duration, _):
            guard remaining.isFinite, remaining >= 0, remaining <= 86_400, !id.isEmpty,
                  duration.isFinite, duration >= 0, duration <= 86_400 else {
                throw RestTimerStorageError.invalidRecord
            }
        case .completed(let id, _):
            guard !id.isEmpty else { throw RestTimerStorageError.invalidRecord }
        }
    }
}

enum RestTimerStorageError: Error {
    case unsupportedVersion, invalidRecord, staleRevision
}

/// The host process commits a whole timer record before publishing a transition.
/// Revision checks prevent an older in-memory session from replacing a later stop.
struct RestTimerStorage {
    let fileURL: URL

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RestTimer/state.json")) {
        self.fileURL = fileURL
    }

    func load() throws -> RestTimerRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let record = try JSONDecoder().decode(RestTimerRecord.self, from: Data(contentsOf: fileURL))
        try record.validate()
        return record
    }

    func save(_ record: RestTimerRecord) throws {
        try record.validate()
        let previousRevision = try load()?.revision ?? 0
        guard previousRevision < UInt64.max, record.revision == previousRevision + 1 else {
            throw RestTimerStorageError.staleRevision
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(record).write(to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
