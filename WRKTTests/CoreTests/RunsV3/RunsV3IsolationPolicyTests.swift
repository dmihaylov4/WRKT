import XCTest

/// Until the store is wired in behind its switch, nothing in the app may refer to the runs_v3
/// module, so no device can ever get a runs_v3 directory from this build. The module's own two
/// files are the only app sources that may name it.
final class RunsV3IsolationPolicyTests: XCTestCase {
    static let moduleFiles: Set<String> = ["Core/Persistence/RunsV3Format.swift", "Core/Persistence/RunsV3Store.swift"]
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
                if Self.moduleFiles.contains(relative) { moduleSeen.insert(relative); continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                for token in Self.tokens where text.contains(token) {
                    XCTFail("\(relative) refers to \(token): the runs_v3 module is not wired in yet")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 100, "the scan found too few sources")
        XCTAssertEqual(moduleSeen, Self.moduleFiles, "the module files moved: update this test")
    }
}
