import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// Opt-in captures of Apple Health, Data portability, Import history, Diagnostics and the streak
/// recovery sheet, from fixtures. Runs only with VOLIA_CAPTURE_SETTINGS=1; see
/// CutSettingsCaptureTests for the output folder.
@MainActor
struct CutSettingsPagesCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SETTINGS"] == "1"))
    func capturePages() async throws {
        let now = Date()
        let health: [(String, ConnectionProvider.Status)] = [
            ("health-not-connected", .notConnected),
            ("health-connected", .connected(lastSync: now.addingTimeInterval(-540))),
            ("health-syncing", .syncing),
            ("health-error", .error("Authorization failed"))
        ]
        for (name, status) in health {
            try await settingsCapture(CutConnectionsView(model: CutConnectionsLogic.model(status, now: now)), name: name)
        }

        let records = CutDataPortabilityFixtures.records
        let last = ImportSummary(record: records[2], workoutsAdded: 12, platesAdded: 2)
        try await settingsCapture(
            CutDataPortabilityView(model: CutDataPortabilityLogic.model(isExporting: false, isImporting: false, last: last),
                                   strategy: .constant("merge")),
            name: "data-last-import")
        try await settingsCapture(
            CutDataPortabilityView(model: CutDataPortabilityLogic.model(isExporting: true, isImporting: true, last: nil),
                                   strategy: .constant("replace")),
            name: "data-busy")
        try await settingsCapture(
            CutImportHistoryView(model: CutDataPortabilityLogic.history(records, isLoading: false)),
            name: "history-rows")
        try await settingsCapture(
            CutImportHistoryView(model: CutDataPortabilityLogic.history([], isLoading: false)),
            name: "history-empty")
        try await settingsCapture(
            CutImportHistoryView(model: CutDataPortabilityLogic.history(records, isLoading: false)),
            name: "history-rows-ax5", dynamicType: .accessibility5)

        try await settingsCapture(CutDiagnosticsView(model: CutDiagnosticsModel()), name: "diagnostics")
        try await settingsCapture(
            CutDiagnosticsView(model: CutDiagnosticsModel(statusMessage: CutDiagnosticsLogic.clearedMessage)),
            name: "diagnostics-cleared")

        try await settingsCapture(
            CutSettingsSheetShell { CutStreakRecoveryView(model: CutStreakRecoveryLogic.model(brokenStreak: 6)) },
            name: "streak-recovery", pushed: false)
        try await settingsCapture(
            CutSettingsSheetShell {
                // A sheet does not inherit the window's text size: set it inside.
                CutStreakRecoveryView(model: CutStreakRecoveryLogic.model(brokenStreak: 12))
                    .environment(\.dynamicTypeSize, .accessibility5)
            },
            name: "streak-recovery-ax5", dynamicType: .accessibility5, pushed: false)
    }
}
