import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutCompeteRefreshTests {
    @Test func failedFetchRetainsLoadedRows() async {
        var rows = [1, 2]
        await CutCompeteRefresh.perform(snapshot: rows, operation: { ([Int](), failed: true) }, apply: { rows = $0 })
        #expect(rows == [1, 2])
    }
    @Test func genuinelyEmptySuccessClearsRows() async {
        var rows = [1, 2]
        await CutCompeteRefresh.perform(snapshot: rows, operation: { ([Int](), failed: false) }, apply: { rows = $0 })
        #expect(rows.isEmpty)
    }
    @Test func cancellingViewOwnedTaskDoesNotCancelRefresh() async {
        var rows = [1]
        var operationWasCancelled = true
        let viewTask = Task { @MainActor in
            await CutCompeteRefresh.perform(snapshot: rows, operation: {
                operationWasCancelled = Task.isCancelled
                return ([2], failed: false)
            }, apply: { rows = $0 })
        }
        viewTask.cancel()
        await viewTask.value
        #expect(!operationWasCancelled); #expect(rows == [2])
    }
}
