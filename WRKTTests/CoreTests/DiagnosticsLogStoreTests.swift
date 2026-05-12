import Foundation
import Testing
@testable import WRKT

struct DiagnosticsLogStoreTests {

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
