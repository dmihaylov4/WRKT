import Foundation
@testable import WRKT

/// The real file system calls, recorded in order, with an optional failure injected at one call.
/// A failed call does not run, so the disk shows exactly what a failure at that point leaves.
nonisolated final class RecordingDurableFileSystem: DurableFileSystem, @unchecked Sendable {
    enum Call: String, CaseIterable {
        case createExclusive, setProtection, write, synchronize, close, rename, synchronizeDirectory, flushDevice
    }

    private let real = POSIXDurableFileSystem()
    private let lock = NSLock()
    private var recorded: [(call: Call, path: String)] = []
    private var failing: Set<Call> = []

    var calls: [Call] { lock.withLock { recorded.map(\.call) } }
    var callsWithNames: [String] {
        lock.withLock { recorded.map { "\($0.call.rawValue) \(($0.path as NSString).lastPathComponent)" } }
    }

    func fail(_ call: Call?) { lock.withLock { failing = call.map { [$0] } ?? [] } }
    func reset() { lock.withLock { recorded = [] } }

    private func record(_ call: Call, _ path: String = "") throws {
        try lock.withLock {
            recorded.append((call, path))
            if failing.contains(call) { throw DurableFileError(operation: call.rawValue, path: path, code: EIO) }
        }
    }

    func createExclusive(_ url: URL) throws -> Int32 { try record(.createExclusive, url.path); return try real.createExclusive(url) }
    func setProtection(_ protection: FileProtectionType, at url: URL) throws { try record(.setProtection, url.path); try real.setProtection(protection, at: url) }
    func write(_ data: Data, to descriptor: Int32) throws { try record(.write); try real.write(data, to: descriptor) }
    func synchronize(_ descriptor: Int32) throws { try record(.synchronize); try real.synchronize(descriptor) }
    func close(_ descriptor: Int32) throws { try record(.close); try real.close(descriptor) }
    func rename(_ source: URL, to destination: URL) throws { try record(.rename, destination.path); try real.rename(source, to: destination) }
    func synchronizeDirectory(_ url: URL) throws { try record(.synchronizeDirectory, url.path); try real.synchronizeDirectory(url) }
    func flushDevice(at url: URL) throws { try record(.flushDevice, url.path); try real.flushDevice(at: url) }
    func remove(_ url: URL) { real.remove(url) }
}
