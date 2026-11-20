import XCTest

/// Only these app sources may name the runs_v3 module, each for its reason. Until the migration
/// exists (batch 3), nothing in the app creates a runs_v3 directory; the files below only read
/// or write one that already exists. A listed file that no longer refers to the module must
/// leave the list.
final class RunsV3IsolationPolicyTests: XCTestCase {
    static let allowlist: [String: String] = [
        "Core/Persistence/RunsV3Format.swift": "The module: layout, names, schemas and the presence check.",
        "Core/Persistence/RunsV3Store.swift": "The module: reader, repair, drain, purge and wipe.",
        "Core/Persistence/RunsV3Migration.swift": "The module: the migration from runs_v2.json (off unless the gate opens).",
        "Core/Persistence/RunsV3Merge.swift": "The module: the three-way merge of an older build's runs_v2.json into runs_v3 (plans only).",
        "Core/Persistence/WorkoutStorage.swift":
            "The switch (openRunHistory: runs_v3 only when its entry exists), validation skipping runs_v2.json, the storage actor's entry points, and the development wipe.",
        "Features/WorkoutSession/Services/RunsV3History.swift":
            "The store-side state of the per-workout history: cache, queued changes, drains.",
        "Features/WorkoutSession/Services/WorkoutStoreV2.swift":
            "Branches each run method to the per-workout history when the load found it active.",
    ]
    static var moduleFiles: Set<String> { Set(allowlist.keys) }
    static let tokens = ["RunsV3", "RunFileV1", "runs_v3"]
    static let sourceRoots = ["App", "Core", "Features", "Shared", "DesignSystem", "Persistence",
                              "WRKT Watch Watch App", "WRKTWidgets"]

    private static var repositoryRoot: URL {
        // .../WRKTTests/CoreTests/RunsV3/RunsV3IsolationPolicyTests.swift
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testNoAppCodeOutsideTheModuleRefersToIt() throws {
        let root = Self.repositoryRoot
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.appendingPathComponent("Core").path) else {
            throw XCTSkip("Sources are not readable from this test host")
        }
        var scanned = 0
        var moduleSeen: Set<String> = []
        for sourceRoot in Self.sourceRoots {
            let base = root.appendingPathComponent(sourceRoot)
            guard let walker = fileManager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
                scanned += 1
                let text = try String(contentsOf: url, encoding: .utf8)
                if Self.moduleFiles.contains(relative) {
                    XCTAssertTrue(Self.tokens.contains { text.contains($0) }, "\(relative) no longer refers to the module: remove it from the list")
                    moduleSeen.insert(relative)
                    continue
                }
                for token in Self.tokens where text.contains(token) {
                    XCTFail("\(relative) refers to \(token) but is not on the allowlist")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 100, "the scan found too few sources")
        XCTAssertEqual(moduleSeen, Self.moduleFiles, "a listed file moved: update this test")
    }
}
