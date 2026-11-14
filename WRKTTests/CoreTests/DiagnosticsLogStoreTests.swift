import Foundation
import Testing
@testable import WRKT

struct DiagnosticsLogStoreTests {

    @Test func exportFlushesQueuedLinesInOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticsLogStore(directory: directory)
        for index in 0..<500 { store.append("event=\(index)", category: "Order") }
        let contents = try String(contentsOf: store.exportFileURL(), encoding: .utf8)
        let messages = contents.split(separator: "\n").map { String($0.split(separator: " ").last!) }
        #expect(messages == (0..<500).map { "event=\($0)" })
    }

    @Test func rotationRetainsCompleteUnicodeLinesAndHandleKeepsWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticsLogStore(directory: directory, maxBytes: 180)
        for index in 0..<20 { store.append("line=\(index) café") }
        store.append("last")
        let contents = try String(contentsOf: store.exportFileURL(), encoding: .utf8)
        #expect(contents.utf8.count <= 180)
        #expect(contents.hasSuffix("[App] last\n"))
        #expect(contents.split(separator: "\n").allSatisfy { $0.contains("[App]") })
        try store.clear()
        store.append("after clear")
        let cleared = try String(contentsOf: store.exportFileURL(), encoding: .utf8)
        #expect(!cleared.contains("café"))
        #expect(cleared.hasSuffix("after clear\n"))
    }

    @Test func appendExportAndClearUseOneFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-log-store-\(UUID().uuidString)", isDirectory: true)
        let store = DiagnosticsLogStore(directory: directory, fileName: "test.log")

        try store.clear()
        store.append("first event", category: "Test")
        store.append("second event", category: "Barbell")

        let exportURL = try store.exportFileURL()
        let contents = try String(contentsOf: exportURL, encoding: .utf8)

        #expect(exportURL.lastPathComponent == "test.log")
        #expect(contents.contains("[Test] first event"))
        #expect(contents.contains("[Barbell] second event"))

        try store.clear()
        let clearedContents = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(clearedContents.isEmpty)
    }
}
