//
//  RunsV3Format.swift
//  WRKT
//
//  The per-workout run history format (runs_v3): layout, names and file schemas.
//  Specification: docs/run-storage-v3-format-spec.md, sections 1 and 2. Not used by the app yet.
//

import Foundation

/// Versions, names and coding shared by the runs_v3 reader and writer.
nonisolated enum RunsV3 {
    /// The highest `formatVersion` / `minimumReaderVersion` this build reads.
    static let readerVersion = 1
    /// The highest `minimumWriterVersion` this build may write under.
    static let writerVersion = 1

    static let directoryName = "runs_v3"
    static let stagingDirectoryName = "runs_v3.staging"
    static let retiredDirectoryPrefix = "runs_v3.retired-"

    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    /// The storage encoder: the same configuration `WorkoutStorage` writes `runs_v2.json` with.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Where everything lives, below the storage directory (`Documents/WRKT_Storage`).
nonisolated struct RunsV3Layout: Sendable {
    let storage: URL

    var root: URL { storage.appendingPathComponent(RunsV3.directoryName, isDirectory: true) }
    var runs: URL { root.appendingPathComponent("runs", isDirectory: true) }
    var trash: URL { root.appendingPathComponent("trash", isDirectory: true) }
    var tmp: URL { root.appendingPathComponent("tmp", isDirectory: true) }
    var format: URL { root.appendingPathComponent("format.json") }
    var index: URL { root.appendingPathComponent("index.json") }
    var baseline: URL { root.appendingPathComponent("baseline.json") }

    static let rootFileNames = ["format.json", "index.json", "baseline.json"]

    func runFile(_ name: RunsV3FileName) -> URL { runs.appendingPathComponent(name.string) }
}

// MARK: - Names

/// `runs/<id>.<rev>.json`: lowercase UUID, revision 1 or more without leading zeros.
nonisolated struct RunsV3FileName: Hashable, Sendable {
    let id: UUID
    let rev: Int

    var string: String { "\(id.uuidString.lowercased()).\(rev).json" }

    /// Accepts exactly the names `string` produces. Anything else (uppercase, leading zeros,
    /// revision 0, temporary suffixes, other extensions) is nil.
    static func parse(_ name: String) -> RunsV3FileName? {
        let utf8 = Array(name.utf8)
        guard utf8.count >= 36 + 1 + 1 + 5, utf8.count <= 36 + 1 + 18 + 5,
              name.hasSuffix(".json"), utf8[36] == UInt8(ascii: ".") else { return nil }
        let idPart = String(decoding: utf8[0..<36], as: UTF8.self)
        guard isLowercaseUUID(idPart), let id = UUID(uuidString: idPart) else { return nil }
        let revBytes = utf8[37..<(utf8.count - 5)]
        guard let first = revBytes.first, first >= UInt8(ascii: "1"), first <= UInt8(ascii: "9"),
              revBytes.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
              let rev = Int(String(decoding: revBytes, as: UTF8.self)) else { return nil }
        return RunsV3FileName(id: id, rev: rev)
    }

    static func isLowercaseUUID(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard byte == UInt8(ascii: "-") else { return false }
            } else {
                guard (48...57).contains(byte) || (97...102).contains(byte) else { return false }
            }
        }
        return true
    }
}

/// Why a file is in `trash/`.
nonisolated enum RunsV3TrashReason: String, CaseIterable, Sendable {
    case deleted, superseded, corrupt, merged
}

/// `trash/<id>.<rev>.<reason>.<ms>.<rand>.json`.
nonisolated struct RunsV3TrashName: Hashable, Sendable {
    let id: UUID
    let rev: Int
    let reason: RunsV3TrashReason
    /// Unix milliseconds when the file was moved here.
    let milliseconds: Int64
    /// 4 lowercase hex characters, so two moves in one millisecond do not collide.
    let random: String

    var string: String {
        "\(id.uuidString.lowercased()).\(rev).\(reason.rawValue).\(milliseconds).\(random).json"
    }

    static func parse(_ name: String) -> RunsV3TrashName? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6, parts[5] == "json",
              RunsV3FileName.isLowercaseUUID(parts[0]), let id = UUID(uuidString: parts[0]),
              let rev = Int(parts[1]), rev >= 1, String(rev) == parts[1],
              let reason = RunsV3TrashReason(rawValue: parts[2]),
              let milliseconds = Int64(parts[3]), milliseconds >= 0, String(milliseconds) == parts[3],
              parts[4].utf8.count == 4,
              parts[4].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return RunsV3TrashName(id: id, rev: rev, reason: reason, milliseconds: milliseconds, random: parts[4])
    }
}

// MARK: - Schemas (format version 1)

/// One workout file. `run` is exactly today's `StoredRun` encoding (slim route plus marker);
/// `seq` and the revision live in this envelope, never in `Run`.
nonisolated struct RunFileV1: Codable {
    let format: Int
    let id: UUID
    let rev: Int
    let seq: Int64
    let run: StoredRun

    /// Read first, so a file from a newer format is recognised even if its `run` does not decode.
    struct Header: Decodable {
        let format: Int
        let id: UUID
        let rev: Int
    }
}

/// `index.json`: a cache of the live history. Losing it costs time, never data or order.
nonisolated struct RunsV3IndexV1: Codable {
    let formatVersion: Int
    let minimumReaderVersion: Int
    let generation: Int
    /// `seq` descending.
    let entries: [Entry]

    struct Entry: Codable {
        let id: UUID
        let rev: Int
        let seq: Int64
        let size: Int
        let sha256: String
        let summary: RunSummary
    }

    /// Only `formatVersion` and `minimumReaderVersion`, so an index this build cannot read is
    /// told apart from a damaged one.
    struct Header: Decodable {
        let formatVersion: Int
        let minimumReaderVersion: Int
    }
}

/// `format.json`.
nonisolated struct RunsV3FormatV1: Codable, Equatable {
    let formatVersion: Int
    let minimumReaderVersion: Int
    let minimumWriterVersion: Int
    let createdAt: Date
    let createdByBuild: String
    let migratedFrom: Source?

    struct Source: Codable, Equatable {
        let fileName: String
        let size: Int
        let sha256: String
        let workoutCount: Int
    }
}

/// `baseline.json`: the v2 reconciliation point (written by the migration and the merge,
/// read by the merge; neither is in this module yet).
nonisolated struct RunsV3BaselineV1: Codable, Equatable {
    let formatVersion: Int
    let reconciledAt: Date
    let v2: V2State
    let entries: [Entry]

    struct V2State: Codable, Equatable {
        let present: Bool
        let size: Int?
        let modified: Date?
        let fileNumber: Int?
        let sha256: String?
        let decodable: Bool
    }

    struct Entry: Codable, Equatable {
        let id: UUID
        let hash: String
        let seq: Int64
    }
}

// MARK: - Presence (the switch)

nonisolated enum RunsV3Presence {
    /// Whether an entry named runs_v3 exists in the storage directory, of any kind: one `lstat`,
    /// nothing created. An error other than "not there" counts as present, so a failed check is
    /// never taken for "no runs_v3" (the open that follows then reports it).
    static func exists(in storage: URL, fileSystem: DurableFileSystem) -> Bool {
        do {
            return try fileSystem.itemInfo(RunsV3Layout(storage: storage).root) != nil
        } catch {
            return true
        }
    }
}
