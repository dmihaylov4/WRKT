//
//  RestTimerAppIntents.swift
//  WRKT
//
//  App Intents for interactive Live Activity buttons
//  These allow users to control the rest timer from the lock screen
//
//  Communication Strategy:
//  Widget Extension cannot directly access main app code, so we use:
//  1. UserDefaults with App Groups to send commands
//  2. Main app's RestTimerManager observes these commands
//  3. URL scheme as fallback to wake app if needed
//

import Foundation
import AppIntents

// MARK: - Shared Constants

/// App Group identifier for sharing data between main app and widget extension
private let appGroupIdentifier = "group.com.dmihaylov.trak.shared"

/// Keys for UserDefaults commands
private enum CommandKey {
    static let adjustTime = "restTimer.command.adjustTime"
    static let pause = "restTimer.command.pause"
    static let resume = "restTimer.command.resume"
    static let skip = "restTimer.command.skip"
    static let stop = "restTimer.command.stop"
    static let startNextSet = "restTimer.command.startNextSet"
    static let timestamp = "restTimer.command.timestamp"
}

/// Helper to post commands to the main app
private func postCommand(_ key: String, value: Any? = nil) {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        print("⚠️ [Widget] Failed to access shared UserDefaults with suite: \(appGroupIdentifier)")
        return
    }

    print("📱 [Widget] Posting command: \(key) with value: \(value ?? "true")")

    // Set command value
    if let value = value {
        sharedDefaults.set(value, forKey: key)
    } else {
        sharedDefaults.set(true, forKey: key)
    }

    // Set timestamp to ensure main app sees the update
    let timestamp = Date().timeIntervalSince1970
    sharedDefaults.set(timestamp, forKey: CommandKey.timestamp)

    // Force synchronization
    let didSync = sharedDefaults.synchronize()
    print("📱 [Widget] Command posted. Sync result: \(didSync), timestamp: \(timestamp)")
}

// MARK: - Adjust Time Intent

/// Adjust the rest timer by adding or subtracting seconds
struct AdjustRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Rest Timer"
    static var description: IntentDescription = "Add or subtract time from the rest timer"

    @Parameter(title: "Seconds to Add", default: 15)
    var seconds: Int

    init() {
        self.seconds = 15
    }

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        postCommand(CommandKey.adjustTime, value: seconds)
        return .result()
    }
}

// MARK: - Pause/Resume Intent

/// Pause the rest timer
struct PauseRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Rest Timer"
    static var description: IntentDescription = "Pause the rest timer"

    func perform() async throws -> some IntentResult {
        postCommand(CommandKey.pause)
        return .result()
    }
}

/// Resume the rest timer
struct ResumeRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Rest Timer"
    static var description: IntentDescription = "Resume the rest timer"

    func perform() async throws -> some IntentResult {
        postCommand(CommandKey.resume)
        return .result()
    }
}

// MARK: - Skip Intent

/// Skip the rest timer and go to the next set
struct SkipRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    static var description: IntentDescription = "Skip the remaining rest time"

    func perform() async throws -> some IntentResult {
        postCommand(CommandKey.skip)
        return .result()
    }
}

// MARK: - Start Next Set Intent

/// Start the rest timer for the next set
struct StartNextSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Next Set"
    static var description: IntentDescription = "Log the completed set and start rest timer for next set"

    func perform() async throws -> some IntentResult {
        postCommand(CommandKey.startNextSet)
        return .result()
    }
}

// MARK: - Stop Intent

/// Stop/cancel the rest timer
struct StopRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Rest Timer"
    static var description: IntentDescription = "Stop and cancel the rest timer"

    func perform() async throws -> some IntentResult {
        postCommand(CommandKey.stop)
        return .result()
    }
}

// MARK: - Open App Intent

/// Open the main app
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open WRKT"
    static var description: IntentDescription = "Open the WRKT app"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
