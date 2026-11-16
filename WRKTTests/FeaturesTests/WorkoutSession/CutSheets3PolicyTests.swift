import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Scene connection and activation are asynchronous during a full test launch.
@MainActor
enum CutSheetsSceneWait {
    static func foregroundScene(timeout: Duration = .seconds(10)) async throws -> UIWindowScene? {
        try await value(timeout: timeout) {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        }
    }

    static func value<Value>(timeout: Duration, poll: Duration = .milliseconds(50), read: () -> Value?) async throws -> Value? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if let value = read() { return value }
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { return nil }
            try await Task.sleep(for: min(poll, remaining))
        }
    }
}

@MainActor
@Suite(.serialized)
struct CutSheets3PolicyTests {
    @Test func waitsForDelayedAvailability() async throws {
        var reads = 0
        let value = try await CutSheetsSceneWait.value(timeout: .seconds(1), poll: .milliseconds(1)) {
            reads += 1
            return reads == 3 ? "foreground fixture" : nil
        }
        #expect(value == "foreground fixture")
        #expect(reads == 3)
    }

    @Test func missingSceneTimesOut() async throws {
        let value: String? = try await CutSheetsSceneWait.value(timeout: .milliseconds(5), poll: .milliseconds(1)) { nil }
        #expect(value == nil)
    }

    @Test func sceneWaitHonorsCancellation() async throws {
        let task = Task { () throws -> String? in
            try await CutSheetsSceneWait.value(timeout: .seconds(10)) { nil }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled scene wait should throw")
        } catch is CancellationError {
        }
    }
}
