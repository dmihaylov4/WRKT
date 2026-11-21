import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering of the Choose your name step in both designs: no host, no auth service,
/// no requests. Opt in with TEST_RUNNER_VOLIA_CAPTURE_NAME=1 (TEST_RUNNER_VOLIA_CAPTURE_STATE for
/// one state, TEST_RUNNER_VOLIA_CAPTURE_DIR for the folder). "-ax" names render at the largest
/// accessibility text size; "-bottom" scrolls to the end.
@MainActor
@Suite(.serialized)
struct ChooseNameCaptureTests {
    nonisolated static let names = [
        "cut-empty", "cut-apple-name", "cut-taken", "cut-offline", "cut-saving", "cut-sheet",
        "cut-ax", "cut-ax-bottom",
        "legacy-empty", "legacy-apple-name", "legacy-taken", "legacy-offline", "legacy-sheet",
        "legacy-ax", "legacy-ax-bottom"
    ]
    nonisolated static var selectedNames: [String] {
        guard let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"], names.contains(selected) else { return names }
        return [selected]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_NAME"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        try await CutWelcomeCapture.render(name: "choose-name-" + name, settle: 2) { makeScene(name) }
    }

    private static let id = UUID(uuidString: "1a2b3c4d-0000-4000-8000-000000000001")!

    @ViewBuilder private func makeScene(_ name: String) -> some View {
        let (form, failure, saving) = state(name)
        let model = ChooseNameLogic.model(form, id: Self.id, isSaving: saving, failure: failure)
        let close: (() -> Void)? = name.hasSuffix("sheet") ? {} : nil
        if name.hasPrefix("cut") {
            NavigationStack {
                CutChooseNameView(model: model, form: .constant(form), actions: .init(close: close))
                    .toolbar(.hidden, for: .navigationBar)
            }
        } else {
            NavigationStack {
                ChooseNameLegacyForm(model: model, form: .constant(form), actions: .init(close: close))
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private func state(_ name: String) -> (ChooseNameForm, ChooseNameFailure?, Bool) {
        let base = name.split(separator: "-").dropFirst().joined(separator: "-")
        switch base {
        case "apple-name": return (.init(displayName: "Anna Smith", username: ""), nil, false)
        case "taken": return (.init(displayName: "Anna Smith", username: "anna"), .usernameTaken, false)
        case "offline": return (.init(displayName: "Anna Smith", username: "anna_lifts"), .offline, false)
        case "saving": return (.init(displayName: "Anna Smith", username: "anna_lifts"), nil, true)
        case "ax", "ax-bottom": return (.init(displayName: "Anna Smith", username: "anna"), .usernameTaken, false)
        default: return (.init(), nil, false)
        }
    }
}
