//
//  VirtualRunFileLogger.swift
//  WRKT Watch
//
//  Writes structured JSON Lines logs during virtual runs for debugging.
//  Logs are stored on-device and can be transferred to iPhone via WCSession.
//

import Foundation

@MainActor
final class VirtualRunFileLogger {
    static let shared = VirtualRunFileLogger()

    enum Category: String {
        case connectivity
        case healthkit
        case snapshotOut = "snapshot_out"
        case snapshotIn = "snapshot_in"
        case partner
        case phase
        case error
    }

    private var fileHandle: FileHandle?
    private var currentFilePath: URL?
    private var buffer: [String] = []
    private var flushTimer: Timer?

    private let maxLogFiles = 5
    private let flushInterval: TimeInterval = 2.0

    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    // MARK: - Session Lifecycle

    func startSession() {
        let dir = logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ts = dateFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let fileName = "vr_log_\(ts).jsonl"
        let path = dir.appendingPathComponent(fileName)

        FileManager.default.createFile(atPath: path.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: path)
        fileHandle?.seekToEndOfFile()
        currentFilePath = path

        startFlushTimer()
        pruneOldLogs()

        log(category: .phase, message: "Log session started", data: ["file": fileName])
    }

    func endSession() {
        log(category: .phase, message: "Log session ended")
        flush()
        fileHandle?.closeFile()
        fileHandle = nil
        flushTimer?.invalidate()
        flushTimer = nil
    }

    /// Path to the current log file (for transfer)
    var currentLogFileURL: URL? { currentFilePath }

    /// All log files sorted newest-first
    var allLogFiles: [URL] {
        let dir = logDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
    }

    // MARK: - Logging

    func log(category: Category, message: String, data: [String: Any]? = nil) {
        var entry: [String: Any] = [
            "ts": dateFormatter.string(from: Date()),
            "cat": category.rawValue,
            "msg": message
        ]
        if let data { entry["data"] = data }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: jsonData, encoding: .utf8) else { return }

        buffer.append(line)
    }

    // MARK: - Flush

    private func flush() {
        guard !buffer.isEmpty, let fh = fileHandle else { return }
        let joined = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll()
        if let data = joined.data(using: .utf8) {
            fh.write(data)
        }
    }

    private func startFlushTimer() {
        flushTimer?.invalidate()
        let timer = Timer(timeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    // MARK: - Housekeeping

    private var logDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VRLogs", isDirectory: true)
    }

    private func pruneOldLogs() {
        let files = allLogFiles
        guard files.count > maxLogFiles else { return }
        for file in files.dropFirst(maxLogFiles) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
