import Foundation
@testable import WRKT

// Test-only helpers. They reach full runs only through the store's public paths (the detail
// handles, which answer from memory, and edits), so tests keep exercising what the app uses.

extension WorkoutStoreV2 {
    /// Every full run, in history order, read through the detail handles.
    var fullRunsForTesting: [Run] {
        runSummaries.compactMap { runDetail(id: $0.id).run }
    }
}

extension RunEdit {
    /// An edit that makes the stored workout equal to `run`: what the removed
    /// `updateRun(_:)` did with a whole run.
    static func replacing(with run: Run) -> RunEdit {
        RunEdit(id: run.id, light: { $0 = RunSummary(run) }, route: .some(run.route),
                routeWithHR: .some(run.routeWithHR), splits: .some(run.splits), hrSamples: .some(run.hrSamples))
    }
}
