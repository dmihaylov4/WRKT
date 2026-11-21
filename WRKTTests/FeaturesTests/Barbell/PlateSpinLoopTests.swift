import Foundation
import Testing
@testable import WRKT

/// The SpinningPlateView loop must end when its task is cancelled (the view went away).
@MainActor
@Suite struct PlateSpinLoopTests {
    @Test(.timeLimit(.minutes(1)))
    func loopEndsWhenTheTaskIsCancelled() async {
        var steps = 0
        let task = Task { @MainActor in
            await PlateSpinLoop.run(interval: .milliseconds(5)) { steps += 1 }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        // Returns only if the loop stopped; a loop that swallowed the cancellation would hang here.
        await task.value
        let stepsAtEnd = steps
        #expect(stepsAtEnd > 0)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(steps == stepsAtEnd, "no step may run after cancellation")
    }

    @Test func loopNeverStepsWhenStartedCancelled() async {
        var steps = 0
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await PlateSpinLoop.run { steps += 1 }
        }
        await task.value
        #expect(steps == 0)
    }
}
