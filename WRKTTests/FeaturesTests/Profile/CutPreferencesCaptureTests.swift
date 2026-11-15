import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// Opt-in captures of the Cut Preferences page and its two wheels, from fixtures. Runs only with
/// VOLIA_CAPTURE_SETTINGS=1; see CutSettingsCaptureTests for the output folder.
@MainActor
struct CutPreferencesCaptureTests {
    private typealias F = CutPreferencesFixtures

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SETTINGS"] == "1"))
    func capturePreferencesStates() async throws {
        let signedIn = CutPreferencesLogic.model(F.signedIn)
        let local = CutPreferencesLogic.model(F.local)
        try await settingsCapture(
            CutPreferencesView(model: signedIn, controls: .constant(smartNudges: true), startsWithZonesOpen: true),
            name: "preferences-signed-in")
        try await settingsCapture(
            CutPreferencesView(model: signedIn, controls: .constant(smartNudges: true)),
            name: "preferences-workout", offsets: [700])
        try await settingsCapture(
            CutPreferencesView(model: local, controls: .constant(weightUnit: .lb, restTimer: false)),
            name: "preferences-local")
        try await settingsCapture(
            CutPreferencesView(model: signedIn, controls: .constant(smartNudges: true)),
            name: "preferences-signed-in-ax5", dynamicType: .accessibility5)
        try await settingsCapture(
            CutSettingsSheetShell { CutAgePickerView(saved: 34) },
            name: "preferences-age-sheet", pushed: false)
        try await settingsCapture(
            CutSettingsSheetShell { CutWeightPickerView(kg: 82.5, unit: .kg) },
            name: "preferences-weight-sheet", pushed: false)
        try await settingsCapture(
            CutSettingsSheetShell { CutWeightPickerView(kg: 82.5, unit: .lb) },
            name: "preferences-weight-sheet-lb", pushed: false)
    }
}
