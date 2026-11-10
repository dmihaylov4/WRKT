import Foundation
import CryptoKit

/// Called before opening any database or starting services that write app data.
/// The original SQLite database, journals and external files are copied together.
struct UpgradeBackup {
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
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: destination.appendingPathComponent("manifest.json")))
        guard manifest.formatVersion == 1, try checksums(in: destination, excludingManifest: true) == manifest.files else {
            throw StorageError.backupFailed("The upgrade recovery copy could not be verified")
        }
    }

    private func checksums(in directory: URL, excludingManifest: Bool = false) throws -> [String: String] {
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
