import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering of the Cut What's New sheet. Opt in with TEST_RUNNER_VOLIA_CAPTURE_WELCOME=1.
@MainActor
@Suite(.serialized)
struct CutWhatsNewCaptureTests {
    nonisolated static let names = ["whatsnew-rack", "whatsnew-plain", "whatsnew-ax", "whatsnew-ax-bottom"]
    nonisolated static var selectedNames: [String] {
        guard let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"], names.contains(selected) else { return names }
        return [selected]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WELCOME"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        let release = WhatsNewRelease(
            version: "5.1.1", title: "Barbell Rewards",
            bullets: ["Earn plates based on your workout history", "Build and display your barbell rack",
                      "Plates backfilled from all past workouts automatically"],
            destination: name == "whatsnew-plain" ? nil : .rack)
        try await CutWelcomeCapture.render(name: name, settle: 3) {
            Color.black.ignoresSafeArea().sheet(isPresented: .constant(true)) {
                // A sheet does not inherit the window's text size here, so it is set again inside.
                CutWhatsNewView(model: CutWhatsNewLogic.model(release: release, currentVersion: "5.1.1"))
                    .environment(\.dynamicTypeSize, name.contains("-ax") ? .accessibility5 : .large)
            }
        }
    }
}
