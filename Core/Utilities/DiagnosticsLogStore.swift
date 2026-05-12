import Foundation

final class DiagnosticsLogStore {
    static let shared = DiagnosticsLogStore()

    private let directory: URL
    private let fileName: String
    private let maxBytes: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        directory: URL? = nil,
        fileName: String = "wrkt-diagnostics.log",
        maxBytes: Int = 256_000,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileName = fileName
        self.maxBytes = maxBytes

        if let directory {
            self.directory = directory
        } else if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.directory = support.appendingPathComponent("Diagnostics", isDirectory: true)
        } else {
            self.directory = fileManager.temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        }
    }

    var logFileURL: URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    func append(_ message: String, category: String = "App") {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureLogFileExists()
            let line = "\(Self.timestamp()) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()

            try trimIfNeeded()
        } catch {
            AppLogger.warning("Diagnostics log append failed: \(error.localizedDescription)", category: AppLogger.app)
        }
    }

    func exportFileURL() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try ensureLogFileExists()
        return logFileURL
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: logFileURL, options: .atomic)
    }

    private func ensureLogFileExists() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logFileURL.path) {
            try Data().write(to: logFileURL, options: .atomic)
        }
    }

    private func trimIfNeeded() throws {
        let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue > maxBytes else {
            return
        }

        let data = try Data(contentsOf: logFileURL)
        let suffix = data.suffix(maxBytes)
        try Data(suffix).write(to: logFileURL, options: .atomic)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
