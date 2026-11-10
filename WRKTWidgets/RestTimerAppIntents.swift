import Foundation
import AppIntents
#if !WRKT_WIDGET_EXTENSION
import SwiftData
#endif

enum RestTimerAction: Sendable {
    case adjust(Int), pause, resume, skip, nextSet, stop
}

struct RestTimerIntentError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private func performTimerAction(_ action: RestTimerAction, timerID: String) async throws {
    #if WRKT_WIDGET_EXTENSION
    throw RestTimerIntentError("Open your workout in the app to update the timer.")
    #else
    guard let id = UUID(uuidString: timerID) else {
        throw RestTimerIntentError("Open your workout in the app to restore this timer.")
    }
    // Bootstrap the same container even when no AppShellView has appeared.
    let storage = WRKTApp.storage
    guard let container = storage.container else {
        throw RestTimerIntentError("Workout storage is unavailable. Open the app to recover it.")
    }
    RewardsEngine.shared.configure(context: container.mainContext)
    try await RestTimerManager.shared.perform(action, timerID: id, operationID: UUID(),
        using: AppDependencies.shared.workoutStore)
    #endif
}

struct AdjustRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust Rest Timer"

    @Parameter(title: "Timer", default: "") var timerID: String
    @Parameter(title: "Seconds to Add", default: 15) var seconds: Int

    init() { }
    init(timerID: UUID?, seconds: Int) {
        self.timerID = timerID?.uuidString ?? ""
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        try await performTimerAction(.adjust(seconds), timerID: timerID)
        return .result()
    }
}

struct PauseRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Rest Timer"
    @Parameter(title: "Timer", default: "") var timerID: String

    init() { }
    init(timerID: UUID?) { self.timerID = timerID?.uuidString ?? "" }

    func perform() async throws -> some IntentResult {
        try await performTimerAction(.pause, timerID: timerID)
        return .result()
    }
}

struct ResumeRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume Rest Timer"
    @Parameter(title: "Timer", default: "") var timerID: String

    init() { }
    init(timerID: UUID?) { self.timerID = timerID?.uuidString ?? "" }

    func perform() async throws -> some IntentResult {
        try await performTimerAction(.resume, timerID: timerID)
        return .result()
    }
}

struct SkipRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    @Parameter(title: "Timer", default: "") var timerID: String

    init() { }
    init(timerID: UUID?) { self.timerID = timerID?.uuidString ?? "" }

    func perform() async throws -> some IntentResult {
        try await performTimerAction(.skip, timerID: timerID)
        return .result()
    }
}

struct StartNextSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log Next Set"
    @Parameter(title: "Timer", default: "") var timerID: String

    init() { }
    init(timerID: UUID?) { self.timerID = timerID?.uuidString ?? "" }

    func perform() async throws -> some IntentResult {
        try await performTimerAction(.nextSet, timerID: timerID)
        return .result()
    }
}

struct StopRestTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Rest Timer"
    @Parameter(title: "Timer", default: "") var timerID: String

    init() { }
    init(timerID: UUID?) { self.timerID = timerID?.uuidString ?? "" }

    func perform() async throws -> some IntentResult {
        try await performTimerAction(.stop, timerID: timerID)
        return .result()
    }
}

struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open WRKT"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult { .result() }
}
