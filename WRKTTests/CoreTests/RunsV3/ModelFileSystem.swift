import Foundation
@testable import WRKT

/// Thrown by every call after a simulated kill: the process is gone.
struct SimulatedKill: Error {}

/// An in-memory file system that models what survives a kill and what survives a power loss.
///
/// Kill: every call that returned has happened; the next call and all later ones do not run.
/// Power loss: only what was made durable survives. A file's data is durable once `fsync`ed and
/// then followed by `F_FULLFSYNC`. A directory change (create, rename, unlink) is durable once
/// every directory it touches was `fsync`ed after it and then `F_FULLFSYNC` ran. Everything else
/// may or may not survive: the "random" cut keeps each pending directory change (atomically, in
/// order) or drops it, and gives each file with unsynced data its new data, its durable data,
/// nothing, or a torn prefix (the drive may write out of order: fsync(2)).
nonisolated final class ModelFileSystem: DurableFileSystem, @unchecked Sendable {
    enum CutStrategy {
        /// Exactly the durable state.
        case durableOnly
        /// Each pending change and each unsynced file decided by a seeded generator.
        case random(UInt64)
        /// Like a kill: everything that happened stays.
        case keepAll
    }

    private struct FileNode {
        var data = Data()
        var synced: Data?
        var durable: Data?
    }

    private enum Change {
        case link(dir: Int, name: String, node: Int)
        case unlink(dir: Int, name: String)
        case rename(fromDir: Int, fromName: String, toDir: Int, toName: String)

        var dirs: Set<Int> {
            switch self {
            case .link(let dir, _, _), .unlink(let dir, _): return [dir]
            case .rename(let from, _, let to, _): return [from, to]
            }
        }
    }

    private struct Pending {
        let change: Change
        var synced: Set<Int> = []
    }

    private let lock = NSRecursiveLock()
    private let caseInsensitive: Bool
    private var nextNode = 1
    private var files: [Int: FileNode] = [:]
    private var directories: Set<Int> = [0]
    private var entries: [Int: [String: Int]] = [0: [:]]
    private var durableEntries: [Int: [String: Int]] = [0: [:]]
    private var pending: [Pending] = []
    private var descriptors: [Int32: Int] = [:]
    private var nextDescriptor: Int32 = 100

    // Fault injection
    private(set) var callCount = 0
    /// After this many calls, the process is killed: that call and every later one throws.
    var killAfterCalls: Int?
    private(set) var killed = false
    /// The call with this index (0-based) fails with this errno and does nothing.
    var failCall: (index: Int, code: Int32)?
    /// The next call with this name (as in `log`, for example "write", "F_FULLFSYNC",
    /// "createExclusive") fails with this errno and does nothing.
    var failNext: (name: String, target: String?, code: Int32)?
    /// Reads fail with EPERM, as before the first unlock.
    var protectedDataUnavailable = false
    /// Every path read, for "never read" checks.
    private(set) var readPaths: [String] = []
    private(set) var log: [String] = []

    init(caseInsensitive: Bool = false) {
        self.caseInsensitive = caseInsensitive
    }

    // MARK: - Copies and cuts

    func copy() -> ModelFileSystem {
        lock.withLock {
            let other = ModelFileSystem(caseInsensitive: caseInsensitive)
            other.nextNode = nextNode
            other.files = files
            other.directories = directories
            other.entries = entries
            other.durableEntries = durableEntries
            other.pending = pending
            return other
        }
    }

    /// Makes the current state durable, as if a long time had passed with every cache flushed.
    func settle() {
        lock.withLock {
            for (id, node) in files { files[id] = FileNode(data: node.data, synced: nil, durable: node.data) }
            durableEntries = entries
            pending = []
        }
    }

    /// A fresh process after a power loss: a new file system holding what the disk kept.
    func afterPowerLoss(_ strategy: CutStrategy) -> ModelFileSystem {
        lock.withLock {
            let other = ModelFileSystem(caseInsensitive: caseInsensitive)
            var generator = SplitMix(seed: { if case .random(let seed) = strategy { return seed } else { return 0 } }())
            other.nextNode = nextNode
            other.directories = directories
            switch strategy {
            case .keepAll:
                other.entries = entries
                other.files = files.mapValues { FileNode(data: $0.data, synced: nil, durable: $0.data) }
            case .durableOnly, .random:
                var tree = durableEntries
                for item in pending {
                    if case .random = strategy, generator.next() % 2 == 0 { Self.apply(item.change, to: &tree) }
                }
                other.entries = tree
                other.files = files.mapValues { node in
                    let kept: Data
                    if case .random = strategy, node.data != (node.durable ?? Data()) {
                        switch generator.next() % 4 {
                        case 0: kept = node.data
                        case 1: kept = node.durable ?? Data()
                        case 2: kept = Data()
                        default: kept = node.data.prefix(Int(generator.next() % UInt64(max(1, node.data.count))))
                        }
                    } else {
                        kept = node.durable ?? Data()
                    }
                    return FileNode(data: kept, synced: nil, durable: kept)
                }
            }
            other.durableEntries = other.entries
            return other
        }
    }

    /// A fresh process after a kill: everything that happened stays, nothing is lost.
    func afterKill() -> ModelFileSystem { afterPowerLoss(.keepAll) }

    private static func apply(_ change: Change, to tree: inout [Int: [String: Int]]) {
        switch change {
        case .link(let dir, let name, let node):
            guard tree[dir] != nil else { return }
            tree[dir]![name] = node
        case .unlink(let dir, let name):
            tree[dir]?[name] = nil
        case .rename(let fromDir, let fromName, let toDir, let toName):
            guard let node = tree[fromDir]?[fromName], tree[toDir] != nil else { return }
            tree[fromDir]![fromName] = nil
            tree[toDir]![toName] = node
        }
    }

    // MARK: - Path resolution

    private func components(_ url: URL) -> [String] {
        url.standardizedFileURL.path.split(separator: "/").map(String.init)
    }

    private func lookup(_ name: String, in dir: Int) -> (key: String, node: Int)? {
        guard let table = entries[dir] else { return nil }
        if let node = table[name] { return (name, node) }
        guard caseInsensitive else { return nil }
        return table.first { $0.key.lowercased() == name.lowercased() }.map { ($0.key, $0.value) }
    }

    private func resolve(_ url: URL) -> Int? {
        var current = 0
        for part in components(url) {
            guard directories.contains(current), let found = lookup(part, in: current) else { return nil }
            current = found.node
        }
        return current
    }

    private func parent(_ url: URL) throws -> (dir: Int, name: String) {
        let parts = components(url)
        guard let name = parts.last else { throw error(EINVAL, url) }
        guard let dir = resolve(url.deletingLastPathComponent()), directories.contains(dir) else { throw error(ENOENT, url) }
        return (dir, name)
    }

    private func error(_ code: Int32, _ url: URL, _ operation: String = "model") -> DurableFileError {
        DurableFileError(operation: operation, path: url.path, code: code)
    }

    private func record(_ change: Change) {
        Self.apply(change, to: &entries)
        pending.append(Pending(change: change))
    }

    /// Counts the call and applies kills and injected failures.
    private func step(_ name: String, _ url: URL? = nil) throws {
        if killed { throw SimulatedKill() }
        let index = callCount
        callCount += 1
        if let limit = killAfterCalls, index >= limit {
            killed = true
            throw SimulatedKill()
        }
        log.append("\(name) \(url?.lastPathComponent ?? "")")
        if let fail = failCall, fail.index == index { throw error(fail.code, url ?? URL(fileURLWithPath: "/"), name) }
        if let fail = failNext, fail.name == name, fail.target.map({ $0 == url?.lastPathComponent }) ?? true {
            failNext = nil
            throw error(fail.code, url ?? URL(fileURLWithPath: "/"), name)
        }
    }

    // MARK: - Test setup (not counted)

    func makeDirectories(_ url: URL) {
        lock.withLock {
            var current = 0
            for part in components(url) {
                if let found = lookup(part, in: current) { current = found.node; continue }
                let node = nextNode; nextNode += 1
                directories.insert(node)
                entries[node] = [:]
                durableEntries[node] = [:]
                record(.link(dir: current, name: part, node: node))
                current = node
            }
        }
    }

    func put(_ data: Data, at url: URL) {
        lock.withLock {
            makeDirectories(url.deletingLastPathComponent())
            let (dir, name) = try! parent(url)
            let node = nextNode; nextNode += 1
            files[node] = FileNode(data: data)
            record(.link(dir: dir, name: name, node: node))
        }
    }

    func names(in url: URL) -> [String] {
        lock.withLock {
            guard let dir = resolve(url), let table = entries[dir] else { return [] }
            return table.keys.sorted()
        }
    }

    func contents(of url: URL) -> Data? {
        lock.withLock { resolve(url).flatMap { files[$0]?.data } }
    }

    func exists(_ url: URL) -> Bool { lock.withLock { resolve(url) != nil } }

    func clearLog() { lock.withLock { log = []; readPaths = [] } }

    // MARK: - DurableFileSystem

    func createExclusive(_ url: URL) throws -> Int32 {
        try lock.withLock {
            try step("createExclusive", url)
            let (dir, name) = try parent(url)
            guard lookup(name, in: dir) == nil else { throw error(EEXIST, url) }
            let node = nextNode; nextNode += 1
            files[node] = FileNode()
            record(.link(dir: dir, name: name, node: node))
            let descriptor = nextDescriptor; nextDescriptor += 1
            descriptors[descriptor] = node
            return descriptor
        }
    }

    func setProtection(_ protection: FileProtectionType, at url: URL) throws {
        try lock.withLock {
            try step("setProtection", url)
            guard resolve(url) != nil else { throw error(ENOENT, url) }
        }
    }

    func write(_ data: Data, to descriptor: Int32) throws {
        try lock.withLock {
            try step("write")
            guard let node = descriptors[descriptor] else { throw error(EBADF, URL(fileURLWithPath: "/")) }
            files[node]?.data.append(data)
        }
    }

    func synchronize(_ descriptor: Int32) throws {
        try lock.withLock {
            try step("fsync")
            guard let node = descriptors[descriptor] else { throw error(EBADF, URL(fileURLWithPath: "/")) }
            let current = files[node]?.data
            files[node]?.synced = current
        }
    }

    func close(_ descriptor: Int32) throws {
        try lock.withLock {
            try step("close")
            descriptors[descriptor] = nil
        }
    }

    func rename(_ source: URL, to destination: URL) throws {
        try lock.withLock {
            try step("rename", destination)
            try move(source, to: destination, exclusive: false)
        }
    }

    func renameExclusive(_ source: URL, to destination: URL) throws {
        try lock.withLock {
            try step("renameExclusive", destination)
            try move(source, to: destination, exclusive: true)
        }
    }

    private func move(_ source: URL, to destination: URL, exclusive: Bool) throws {
        let (fromDir, fromName) = try parent(source)
        guard let found = lookup(fromName, in: fromDir) else { throw error(ENOENT, source) }
        let (toDir, toName) = try parent(destination)
        if let existing = lookup(toName, in: toDir) {
            if exclusive { throw error(EEXIST, destination) }
            if directories.contains(existing.node) {
                guard directories.contains(found.node) else { throw error(EISDIR, destination) }
                guard entries[existing.node]?.isEmpty == true else { throw error(ENOTEMPTY, destination) }
            }
            if existing.key != toName || caseInsensitive { record(.unlink(dir: toDir, name: existing.key)) }
        }
        record(.rename(fromDir: fromDir, fromName: found.key, toDir: toDir, toName: toName))
    }

    func synchronizeDirectory(_ url: URL) throws {
        try lock.withLock {
            try step("fsyncDirectory", url)
            guard let dir = resolve(url), directories.contains(dir) else { throw error(ENOENT, url) }
            for index in pending.indices where pending[index].change.dirs.contains(dir) {
                pending[index].synced.insert(dir)
            }
        }
    }

    func flushDevice(at url: URL) throws {
        try lock.withLock {
            try step("F_FULLFSYNC", url)
            for (id, node) in files where node.synced != nil {
                var updated = node
                updated.durable = node.synced
                files[id] = updated
            }
            var remaining: [Pending] = []
            for item in pending {
                if item.synced.isSuperset(of: item.change.dirs) {
                    Self.apply(item.change, to: &durableEntries)
                } else {
                    remaining.append(item)
                }
            }
            pending = remaining
        }
    }

    func remove(_ url: URL) {
        lock.withLock {
            guard (try? step("unlink", url)) != nil else { return }
            guard let (dir, name) = try? parent(url), let found = lookup(name, in: dir),
                  !directories.contains(found.node) else { return }
            record(.unlink(dir: dir, name: found.key))
        }
    }

    func contentsOfDirectory(_ url: URL) throws -> [String] {
        try lock.withLock {
            try step("list", url)
            guard let dir = resolve(url) else { throw error(ENOENT, url) }
            guard directories.contains(dir) else { throw error(ENOTDIR, url) }
            return Array(entries[dir]!.keys)
        }
    }

    func readFile(_ url: URL) throws -> Data {
        try lock.withLock {
            try step("read", url)
            readPaths.append(url.path)
            if protectedDataUnavailable { throw error(EPERM, url) }
            guard let node = resolve(url) else { throw error(ENOENT, url) }
            guard let file = files[node] else { throw error(EISDIR, url) }
            return file.data
        }
    }

    func itemInfo(_ url: URL) throws -> DurableItemInfo? {
        try lock.withLock {
            try step("stat", url)
            guard let node = resolve(url) else { return nil }
            if directories.contains(node) { return DurableItemInfo(kind: .directory, size: 0) }
            return DurableItemInfo(kind: .file, size: files[node]?.data.count ?? 0)
        }
    }

    func createDirectory(_ url: URL, protection: FileProtectionType?) throws {
        try lock.withLock {
            try step("mkdir", url)
            let (dir, name) = try parent(url)
            guard lookup(name, in: dir) == nil else { throw error(EEXIST, url) }
            let node = nextNode; nextNode += 1
            directories.insert(node)
            entries[node] = [:]
            durableEntries[node] = [:]
            record(.link(dir: dir, name: name, node: node))
        }
    }

    func removeTree(_ url: URL) throws {
        try lock.withLock {
            try step("removeTree", url)
            let (dir, name) = try parent(url)
            guard let found = lookup(name, in: dir) else { return }
            record(.unlink(dir: dir, name: found.key))
        }
    }
}

/// A small deterministic generator for tests.
nonisolated struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(_ bound: Int) -> Int { Int(next() % UInt64(max(1, bound))) }
}
