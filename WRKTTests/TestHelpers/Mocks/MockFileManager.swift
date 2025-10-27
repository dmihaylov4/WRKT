//
//  MockFileManager.swift
//  WRKTTests
//
//  Mock file manager for testing storage operations
//

import Foundation

/// Mock file system for testing
class MockFileSystem {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        return files.keys.contains(path)
    }

    func directoryExists(atPath path: String) -> Bool {
        return directories.contains(path)
    }

    func createDirectory(atPath path: String) {
        directories.insert(path)
    }

    func write(_ data: Data, to path: String) {
        files[path] = data
    }

    func read(from path: String) -> Data? {
        return files[path]
    }

    func delete(atPath path: String) {
        files.removeValue(forKey: path)
    }

    func reset() {
        files.removeAll()
        directories.removeAll()
    }

    func allPaths() -> [String] {
        return Array(files.keys)
    }
}
