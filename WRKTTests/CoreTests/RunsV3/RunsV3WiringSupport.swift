import Foundation
import XCTest
@testable import WRKT

/// Real-disk helpers for the store-level runs_v3 tests. Nothing here derives from user data.
nonisolated enum V3Disk {
    /// A test-only stand-in for the migration (batch 3): the directories, format.json, one file
    /// per run at revision 1 with `seq = n - i`, and the index, written directly.
    static func seed(_ directory: URL, _ runs: [Run], format: RunsV3FormatV1? = nil, index: Bool = true) throws {
        let layout = RunsV3Layout(storage: directory)
        let fm = FileManager.default
        for url in [layout.runs, layout.trash, layout.tmp] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        let encoder = RunsV3.makeEncoder()
        var entries: [RunsV3IndexV1.Entry] = []
        for (i, run) in runs.enumerated() {
            let seq = Int64(runs.count - i)
            let data = try encoder.encode(RunFileV1(format: 1, id: run.id, rev: 1, seq: seq, run: StoredRun(run)))
            try data.write(to: layout.runFile(RunsV3FileName(id: run.id, rev: 1)))
            entries.append(.init(id: run.id, rev: 1, seq: seq, size: data.count, sha256: RunsV3Store.sha256(data),
                                 summary: RunSummary(run)))
        }
        try encoder.encode(format ?? RunsV3FormatV1(formatVersion: 1, minimumReaderVersion: 1, minimumWriterVersion: 1,
                                                    createdAt: V3.start, createdByBuild: "seed", migratedFrom: nil))
            .write(to: layout.format)
        if index {
            try encoder.encode(RunsV3IndexV1(formatVersion: 1, minimumReaderVersion: 1, generation: 1, entries: entries))
                .write(to: layout.index)
        }
    }

    /// Every name below `directory`, relative, sorted.
    static func tree(_ directory: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let base = directory.standardizedFileURL.path
        return walker.compactMap { ($0 as? URL)?.standardizedFileURL.path }
            .map { String($0.dropFirst(base.count + 1)) }.sorted()
    }
}

/// The real file system with injectable delays and failures, for store-level tests.
nonisolated final class FaultyFileSystem: DurableFileSystem, @unchecked Sendable {
    private let real = POSIXDurableFileSystem()
    private let lock = NSLock()
    private var _readDelay: TimeInterval = 0
    private var _failFlushes = 0
    private var _flushes = 0
    private var _calls = 0
    private var _killAfter: Int?
    private var _failReadsContaining: String?
    private var _failWritesContaining: String?
    private var _createDelay: TimeInterval = 0

    /// Every call counted, as a kill point.
    var calls: Int { lock.withLock { _calls } }
    /// After this many calls every call throws, as after a kill.
    var killAfter: Int? { get { lock.withLock { _killAfter } } set { lock.withLock { _killAfter = newValue } } }
    /// Reads of paths containing this fail with EIO.
    var failReadsContaining: String? { get { lock.withLock { _failReadsContaining } } set { lock.withLock { _failReadsContaining = newValue } } }
    /// Creating files whose path contains this fails with EIO.
    var failWritesContaining: String? { get { lock.withLock { _failWritesContaining } } set { lock.withLock { _failWritesContaining = newValue } } }
    /// Each file creation waits this long: a slow disk, to act while a migration runs.
    var createDelay: TimeInterval { get { lock.withLock { _createDelay } } set { lock.withLock { _createDelay = newValue } } }

    private func count(_ url: URL? = nil) throws {
        try lock.withLock {
            _calls += 1
            if let limit = _killAfter, _calls > limit { throw DurableFileError(operation: "killed", path: url?.path ?? "", code: EIO) }
        }
    }

    /// Reads of workout files (under runs/) wait this long: a slow disk.
    var readDelay: TimeInterval { get { lock.withLock { _readDelay } } set { lock.withLock { _readDelay = newValue } } }
    /// The next this many `F_FULLFSYNC` calls fail with EIO.
    var failFlushes: Int { get { lock.withLock { _failFlushes } } set { lock.withLock { _failFlushes = newValue } } }
    var flushes: Int { lock.withLock { _flushes } }

    func createExclusive(_ url: URL) throws -> Int32 {
        try count(url)
        let delay = createDelay
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if let part = failWritesContaining, url.path.contains(part) { throw DurableFileError(operation: "open", path: url.path, code: EIO) }
        return try real.createExclusive(url)
    }
    func setProtection(_ protection: FileProtectionType, at url: URL) throws { try count(url); try real.setProtection(protection, at: url) }
    func write(_ data: Data, to descriptor: Int32) throws { try count(); try real.write(data, to: descriptor) }
    func synchronize(_ descriptor: Int32) throws { try count(); try real.synchronize(descriptor) }
    func close(_ descriptor: Int32) throws { try count(); try real.close(descriptor) }
    func rename(_ source: URL, to destination: URL) throws { try count(destination); try real.rename(source, to: destination) }
    func synchronizeDirectory(_ url: URL) throws { try count(url); try real.synchronizeDirectory(url) }
    func flushDevice(at url: URL) throws {
        try count(url)
        let fail: Bool = lock.withLock {
            _flushes += 1
            guard _failFlushes > 0 else { return false }
            _failFlushes -= 1
            return true
        }
        if fail { throw DurableFileError(operation: "F_FULLFSYNC", path: url.path, code: EIO) }
        try real.flushDevice(at: url)
    }
    func remove(_ url: URL) { if (try? count(url)) != nil { real.remove(url) } }
    func renameExclusive(_ source: URL, to destination: URL) throws { try count(destination); try real.renameExclusive(source, to: destination) }
    func contentsOfDirectory(_ url: URL) throws -> [String] { try count(url); return try real.contentsOfDirectory(url) }
    func readFile(_ url: URL) throws -> Data {
        try count(url)
        if let part = failReadsContaining, url.path.contains(part) { throw DurableFileError(operation: "read", path: url.path, code: EIO) }
        let delay = readDelay
        if delay > 0, url.path.contains("/runs_v3/runs/") { Thread.sleep(forTimeInterval: delay) }
        return try real.readFile(url)
    }
    func itemInfo(_ url: URL) throws -> DurableItemInfo? { try count(url); return try real.itemInfo(url) }
    func createDirectory(_ url: URL, protection: FileProtectionType?) throws { try count(url); try real.createDirectory(url, protection: protection) }
    func removeTree(_ url: URL) throws { try count(url); try real.removeTree(url) }
}
