import Foundation
import CryptoKit

/// Called before opening any database or starting services that write app data.
/// The original SQLite database, journals and external files are copied together.
/// Nonisolated so the store can run it off the main thread at launch.
nonisolated struct UpgradeBackup: Sendable {
    let applicationSupport: URL
    let documents: URL
    let destination: URL

    struct Manifest: Codable {
        var formatVersion = 1
        let createdAt: Date
        let files: [String: String]
    }

    func createIfNeeded(preferences: [String: Any] = [:]) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try verify()
            return destination
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".incomplete-" + destination.lastPathComponent)
        // A process termination can leave this unpublished copy behind. Only this
        // reserved staging directory is disposable; completed snapshots stay intact.
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        do {
            for (name, source) in [("Application Support", applicationSupport), ("Documents", documents)] {
                let target = staging.appendingPathComponent(name)
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                guard fm.fileExists(atPath: source.path) else { continue }
                for entry in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    // Never recursively copy this snapshot or previous upgrade snapshots.
                    if entry.standardizedFileURL == destination.deletingLastPathComponent().standardizedFileURL { continue }
                    try fm.copyItem(at: entry, to: target.appendingPathComponent(entry.lastPathComponent))
                }
            }
            let settings = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
            try settings.write(to: staging.appendingPathComponent("Preferences.plist"), options: .atomic)
            let manifest = Manifest(createdAt: .now, files: try checksums(in: staging))
            try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try fm.moveItem(at: staging, to: destination)
            return destination
        } catch {
            // Only our incomplete copy is disposable. Never remove a source or completed backup.
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    func verify() throws {
        try Self.verify(snapshot: destination)
    }

    /// Hashes every file in `snapshot` and compares it with the snapshot's manifest.
    static func verify(snapshot: URL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: snapshot.appendingPathComponent("manifest.json")))
        guard manifest.formatVersion == 1, try checksums(in: snapshot, excludingManifest: true) == manifest.files else {
            throw StorageError.backupFailed("The upgrade recovery copy could not be verified")
        }
    }

    /// `copy` if it verifies now, otherwise nil: a copy is never handed to the user unverified.
    /// Hashes every file, so call it off the main thread.
    static func verifiedRecoveryCopy(_ copy: URL?) -> URL? {
        guard let copy else { return nil }
        do {
            try verify(snapshot: copy)
            return copy
        } catch {
            AppLogger.error("The upgrade recovery copy failed verification and is not offered", error: error,
                            category: AppLogger.storage)
            return nil
        }
    }

    // MARK: - Opened once

    /// Written next to the snapshot, never inside it, after the store first opens following a
    /// snapshot that this process created or verified. It names the manifest it vouches for.
    struct OpenedRecord: Codable {
        var formatVersion = 1
        let manifestSHA256: String
        let recordedAt: Date
    }

    /// What the store open may rely on, and whether a successful open should be recorded.
    struct Readiness {
        /// Where the snapshot is, if it exists. Not necessarily verified in this process:
        /// whoever hands it to the user verifies it first (`verifiedRecoveryCopy`).
        let recoveryCopy: URL?
        /// True when the snapshot was created or verified in this process and no valid record
        /// exists yet, so a successful open must be recorded.
        let recordAfterOpen: Bool
    }

    var openedRecordURL: URL {
        destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".opened.json")
    }

    /// Before the store has ever opened after a created or verified snapshot, this is exactly
    /// `createIfNeeded`: a snapshot that cannot be created or verified throws and keeps the store
    /// closed. Once that open is recorded, the snapshot is not hashed again and a missing or
    /// changed snapshot is logged instead of blocking, since the live data is validated
    /// separately. A record that is missing or cannot be read means verifying as before.
    func prepareForOpen(preferences: [String: Any] = [:]) throws -> Readiness {
        guard let record = openedRecord() else {
            return Readiness(recoveryCopy: try createIfNeeded(preferences: preferences), recordAfterOpen: true)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            AppLogger.warning("The upgrade recovery copy is missing; the store opened after it was made, so opening continues",
                              category: AppLogger.storage)
            return Readiness(recoveryCopy: nil, recordAfterOpen: false)
        }
        if manifestSHA256() != record.manifestSHA256 {
            AppLogger.warning("The upgrade recovery copy changed after the store opened; opening continues and the copy is verified before it is offered",
                              category: AppLogger.storage)
        }
        return Readiness(recoveryCopy: destination, recordAfterOpen: false)
    }

    /// Records that the store opened after this snapshot. Never touches the snapshot itself.
    func recordOpened() throws {
        guard let digest = manifestSHA256() else {
            throw StorageError.backupFailed("The upgrade recovery copy has no readable manifest")
        }
        let data = try JSONEncoder().encode(OpenedRecord(manifestSHA256: digest, recordedAt: .now))
        try data.write(to: openedRecordURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The record, or nil if it is missing, unreadable or of an unknown format.
    func openedRecord() -> OpenedRecord? {
        guard let data = try? Data(contentsOf: openedRecordURL),
              let record = try? JSONDecoder().decode(OpenedRecord.self, from: data),
              record.formatVersion == 1 else { return nil }
        return record
    }

    private func manifestSHA256() -> String? {
        guard let data = try? Data(contentsOf: destination.appendingPathComponent("manifest.json")) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func checksums(in directory: URL, excludingManifest: Bool = false) throws -> [String: String] {
        try Self.checksums(in: directory, excludingManifest: excludingManifest)
    }

    private static func checksums(in directory: URL, excludingManifest: Bool = false) throws -> [String: String] {
        var result: [String: String] = [:]
        let entries = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        for entry in entries {
            if excludingManifest && entry.lastPathComponent == "manifest.json" { continue }
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw StorageError.backupFailed("An unexpected symbolic link prevents a complete recovery copy")
            }
            if values.isDirectory == true {
                for (path, hash) in try checksums(in: entry) { result[entry.lastPathComponent + "/" + path] = hash }
            } else if values.isRegularFile == true {
                let handle = try FileHandle(forReadingFrom: entry)
                defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
                result[entry.lastPathComponent] = hash.finalize().map { String(format: "%02x", $0) }.joined()
            } else {
                throw StorageError.backupFailed("An unsupported file prevents a complete recovery copy")
            }
        }
        return result
    }
}
