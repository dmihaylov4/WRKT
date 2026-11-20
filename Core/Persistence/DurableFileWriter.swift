//
//  DurableFileWriter.swift
//  WRKT
//
//  Replaces a file so that a kill leaves the old or the new whole file, and so that, after
//  `barrier`, the new file survives a power loss.
//

import Foundation

/// A failed file system call made by `DurableFileWriter`.
nonisolated struct DurableFileError: LocalizedError, Equatable {
    let operation: String
    let path: String
    let code: Int32

    var errorDescription: String? {
        "\(operation) failed for \((path as NSString).lastPathComponent): \(String(cString: strerror(code)))"
    }

    var isOutOfSpace: Bool { code == ENOSPC }
}

/// The file system calls a durable write makes, one method per call, so a test can record their
/// order and fail any one of them.
nonisolated protocol DurableFileSystem: Sendable {
    /// Creates a new, empty file that must not exist yet, without following symbolic links, and
    /// opens it for writing.
    func createExclusive(_ url: URL) throws -> Int32
    func setProtection(_ protection: FileProtectionType, at url: URL) throws
    func write(_ data: Data, to descriptor: Int32) throws
    /// `fsync`: the file's data leaves the host for the drive.
    func synchronize(_ descriptor: Int32) throws
    func close(_ descriptor: Int32) throws
    /// `rename(2)`: replaces `destination` in one step.
    func rename(_ source: URL, to destination: URL) throws
    /// `fsync` of the directory, so its entries (the rename) leave the host as well.
    func synchronizeDirectory(_ url: URL) throws
    /// `F_FULLFSYNC`: everything synchronized before on this device is on permanent storage
    /// when it returns (fcntl(2)).
    func flushDevice(at url: URL) throws
    func remove(_ url: URL)

    // Used by the per-workout history store (format v3).

    /// `renamex_np(RENAME_EXCL)`: fails with `EEXIST` instead of replacing `destination`.
    func renameExclusive(_ source: URL, to destination: URL) throws
    /// The names in a directory, without `.` and `..`, in no particular order.
    func contentsOfDirectory(_ url: URL) throws -> [String]
    /// The whole file, without following a symbolic link.
    func readFile(_ url: URL) throws -> Data
    /// What is at `url`, without following a symbolic link; nil when nothing is there.
    func itemInfo(_ url: URL) throws -> DurableItemInfo?
    /// Creates one directory; fails if anything exists at `url`.
    func createDirectory(_ url: URL, protection: FileProtectionType?) throws
    /// Removes a directory and everything in it, never following symbolic links.
    func removeTree(_ url: URL) throws
}

/// What `itemInfo` found.
nonisolated struct DurableItemInfo: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case file, directory, other }
    let kind: Kind
    let size: Int
}

extension DurableFileError {
    /// The file or directory is not there.
    var isMissing: Bool { code == ENOENT }
    /// Data Protection keeps the file closed (before the first unlock) or access is denied.
    var isPermission: Bool { code == EPERM || code == EACCES }
}

/// The real calls.
nonisolated struct POSIXDurableFileSystem: DurableFileSystem {
    private func fail(_ operation: String, _ url: URL) -> DurableFileError {
        DurableFileError(operation: operation, path: url.path, code: errno)
    }

    func createExclusive(_ url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw fail("open", url) }
        return descriptor
    }

    func setProtection(_ protection: FileProtectionType, at url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
    }

    func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw DurableFileError(operation: "write", path: "descriptor \(descriptor)", code: errno)
                }
                remaining -= written
                pointer += written
            }
        }
    }

    func synchronize(_ descriptor: Int32) throws {
        guard fsync(descriptor) == 0 else {
            throw DurableFileError(operation: "fsync", path: "descriptor \(descriptor)", code: errno)
        }
    }

    func close(_ descriptor: Int32) throws {
        guard Darwin.close(descriptor) == 0 else {
            throw DurableFileError(operation: "close", path: "descriptor \(descriptor)", code: errno)
        }
    }

    func rename(_ source: URL, to destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else { throw fail("rename", destination) }
    }

    func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw fail("open directory", url) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw fail("fsync directory", url) }
    }

    func flushDevice(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw fail("open directory", url) }
        defer { Darwin.close(descriptor) }
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        // A file system without F_FULLFSYNC: fsync is the strongest flush it offers.
        guard errno == ENOTSUP || errno == EINVAL, fsync(descriptor) == 0 else { throw fail("F_FULLFSYNC", url) }
    }

    func remove(_ url: URL) {
        unlink(url.path)
    }

    func renameExclusive(_ source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw fail("rename", destination) }
    }

    func contentsOfDirectory(_ url: URL) throws -> [String] {
        guard let directory = opendir(url.path) else { throw fail("opendir", url) }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        guard errno == 0 else { throw fail("readdir", url) }
        return names
    }

    func readFile(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw fail("open", url) }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw fail("fstat", url) }
        var data = Data(count: Int(info.st_size))
        var offset = 0
        try data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            while offset < buffer.count {
                let count = Darwin.read(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw fail("read", url)
                }
                if count == 0 { break }
                offset += count
            }
        }
        // A file that shrank while it was read: return what was there.
        if offset < data.count { data.removeSubrange(offset...) }
        return data
    }

    func itemInfo(_ url: URL) throws -> DurableItemInfo? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT || errno == ENOTDIR { return nil }
            throw fail("lstat", url)
        }
        let type = info.st_mode & S_IFMT
        let kind: DurableItemInfo.Kind = type == S_IFREG ? .file : type == S_IFDIR ? .directory : .other
        return DurableItemInfo(kind: kind, size: Int(info.st_size))
    }

    func createDirectory(_ url: URL, protection: FileProtectionType?) throws {
        guard mkdir(url.path, 0o755) == 0 else { throw fail("mkdir", url) }
        if let protection {
            do {
                try setProtection(protection, at: url)
            } catch {
                AppLogger.warning("Could not set file protection on \(url.lastPathComponent): \(error)",
                                  category: AppLogger.storage)
            }
        }
    }

    func removeTree(_ url: URL) throws {
        guard try itemInfo(url) != nil else { return }
        do {
            try FileManager().removeItem(at: url)
        } catch {
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            throw DurableFileError(operation: "remove", path: url.path,
                                   code: underlying?.domain == NSPOSIXErrorDomain ? Int32(underlying!.code) : EIO)
        }
    }
}

/// Writes a whole file the way the history files need it.
///
/// `write` creates `<name>.wrkt-<uuid>.tmp` beside the target, applies the protection class to
/// the empty file, writes the data, `fsync`s and closes it, renames it over the target and
/// `fsync`s the directory. A kill leaves either the old or the new whole file (the rename is one
/// step), plus at most the temporary file, which `isTemporaryLeftover` recognises. Every write
/// creates a new file, so the target's file number changes each time (`FileStamp` relies on it).
/// A failure before the rename removes the temporary file and leaves the target untouched; any
/// failure throws, including a failed directory `fsync` after the rename.
///
/// Durability against power loss needs `barrier` afterwards: `fsync` alone lets the drive keep
/// the data in its cache and reorder it.
nonisolated struct DurableFileWriter: Sendable {
    let fileSystem: DurableFileSystem
    /// Names temporary files; injectable so tests are deterministic.
    private let token: @Sendable () -> UUID

    init(fileSystem: DurableFileSystem = POSIXDurableFileSystem(), token: @escaping @Sendable () -> UUID = { UUID() }) {
        self.fileSystem = fileSystem
        self.token = token
    }

    static let temporaryInfix = ".wrkt-"
    static let temporarySuffix = ".tmp"

    static func temporaryName(for name: String, token: UUID = UUID()) -> String {
        name + temporaryInfix + token.uuidString.lowercased() + temporarySuffix
    }

    /// True only for `<name>.wrkt-<lowercase uuid>.tmp`, the name `write` gives its temporary file.
    static func isTemporaryName(_ candidate: String, for name: String) -> Bool {
        let prefix = name + temporaryInfix
        guard candidate.hasPrefix(prefix), candidate.hasSuffix(temporarySuffix) else { return false }
        let token = candidate.dropFirst(prefix.count).dropLast(temporarySuffix.count)
        guard token.count == 36, let uuid = UUID(uuidString: String(token)) else { return false }
        return uuid.uuidString.lowercased() == token
    }

    /// True only for `<name>.sb-<8 lowercase hex>-<6 letters or digits>`, the temporary file that
    /// Foundation's atomic write (`Data.write(options: .atomic)`) puts beside the target, as seen
    /// on macOS and in the iOS simulator.
    static func isSystemAtomicWriteName(_ candidate: String, for name: String) -> Bool {
        let prefix = name + ".sb-"
        guard candidate.hasPrefix(prefix) else { return false }
        let rest = Array(candidate.dropFirst(prefix.count).utf8)
        guard rest.count == 15, rest[8] == UInt8(ascii: "-") else { return false }
        let hex = rest[0..<8].allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        let random = rest[9..<15].allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
        return hex && random
    }

    func write(_ data: Data, to url: URL, protection: FileProtectionType?) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(Self.temporaryName(for: url.lastPathComponent, token: token()))
        try writeTemporary(data, at: temporary, protection: protection) {
            try fileSystem.rename(temporary, to: url)
        }
        try fileSystem.synchronizeDirectory(directory)
    }

    /// Writes a file that must not exist yet: a temporary file `<uuid>.tmp` in
    /// `temporaryDirectory` (same volume), written and synchronized, then renamed to `url` with
    /// `renameExclusive`, so an existing file is never replaced. Neither directory is
    /// synchronized: the caller's `barrier(directories:)` does that once per batch.
    func writeNew(_ data: Data, to url: URL, temporaryDirectory: URL, protection: FileProtectionType?) throws {
        let temporary = temporaryDirectory.appendingPathComponent(token().uuidString.lowercased() + Self.temporarySuffix)
        try writeTemporary(data, at: temporary, protection: protection) {
            try fileSystem.renameExclusive(temporary, to: url)
        }
    }

    private func writeTemporary(_ data: Data, at temporary: URL, protection: FileProtectionType?,
                                publish: () throws -> Void) throws {
        let descriptor = try fileSystem.createExclusive(temporary)
        var isOpen = true
        do {
            if let protection {
                // Before any data is written, so the data never exists under another class. As
                // before this writer, a class that cannot be set does not fail the write: the
                // file then has the directory's or the system's default class.
                do {
                    try fileSystem.setProtection(protection, at: temporary)
                } catch {
                    AppLogger.warning("Could not set file protection on \(temporary.lastPathComponent): \(error)",
                                      category: AppLogger.storage)
                }
            }
            try fileSystem.write(data, to: descriptor)
            try fileSystem.synchronize(descriptor)
            isOpen = false
            try fileSystem.close(descriptor)
            try publish()
        } catch {
            if isOpen { try? fileSystem.close(descriptor) }
            fileSystem.remove(temporary)
            throw error
        }
    }

    /// Puts every file written before it on this device on permanent storage.
    func barrier(at directory: URL) throws {
        try fileSystem.flushDevice(at: directory)
    }

    /// Synchronizes each directory (so renames into or out of it leave the host), then flushes
    /// the device once, at the last one: everything synchronized before is then on permanent
    /// storage (fcntl(2), F_FULLFSYNC).
    func barrier(directories: [URL]) throws {
        guard let last = directories.last else { return }
        for directory in directories { try fileSystem.synchronizeDirectory(directory) }
        try fileSystem.flushDevice(at: last)
    }
}
