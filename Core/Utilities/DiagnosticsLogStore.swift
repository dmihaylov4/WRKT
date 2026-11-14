import Foundation

nonisolated final class DiagnosticsLogStore: @unchecked Sendable {
    static let shared = DiagnosticsLogStore()

    private let directory: URL
    private let fileName: String
    private let maxBytes: Int
    private let fileManager: FileManager
    // All mutable file state is confined to this queue. Enqueue order is line order.
    private let queue = DispatchQueue(label: "app.diagnostics.file", qos: .utility)
    private let formatter = ISO8601DateFormatter()
    private var handle: FileHandle?
    private var byteCount = 0

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
        let timestamp = Date()
        queue.async { [self] in
            do {
                let handle = try openHandle()
                let data = Data("\(formatter.string(from: timestamp)) [\(category)] \(message)\n".utf8)
                try handle.write(contentsOf: data)
                byteCount += data.count
                try trimIfNeeded()
            } catch {
                try? handle?.close()
                handle = nil
                AppLogger.warning("Diagnostics log append failed: \(error.localizedDescription)", category: AppLogger.app)
            }
        }
    }

    func exportFileURL() throws -> URL {
        try queue.sync {
            let handle = try openHandle()
            try handle.synchronize()
            return logFileURL
        }
    }

    func clear() throws {
        try queue.sync {
            try handle?.close()
            handle = nil
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: logFileURL, options: .atomic)
            byteCount = 0
        }
    }

    deinit { try? handle?.close() }

    private func openHandle() throws -> FileHandle {
        if let handle { return handle }
        try ensureLogFileExists()
        let opened = try FileHandle(forWritingTo: logFileURL)
        byteCount = Int(try opened.seekToEnd())
        handle = opened
        return opened
    }

    private func ensureLogFileExists() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logFileURL.path) {
            try Data().write(to: logFileURL, options: .atomic)
        }
    }

    private func trimIfNeeded() throws {
        guard byteCount > maxBytes else { return }
        try handle?.close()
        handle = nil
        let data = try Data(contentsOf: logFileURL)
        // Keep complete UTF-8 lines instead of cutting through a character or timestamp.
        let suffix = data.suffix(maxBytes)
        let retained = suffix.firstIndex(of: 10).map { Data(suffix.suffix(from: suffix.index(after: $0))) } ?? Data()
        try retained.write(to: logFileURL, options: .atomic)
        _ = try openHandle()
    }
}
