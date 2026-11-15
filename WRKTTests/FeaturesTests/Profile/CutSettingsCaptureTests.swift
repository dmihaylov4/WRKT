import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut Settings cluster (batch 8a) from fixture values. Runs only with
/// VOLIA_CAPTURE_SETTINGS=1 (pass TEST_RUNNER_VOLIA_CAPTURE_SETTINGS=1 to xcodebuild). Writes to
/// /private/tmp/volia-cut-settings, or to VOLIA_CAPTURE_DIR when set. Each page is pushed on a
/// navigation stack in the Me tab, as the app shows it, and captured at the top and at its end.
@MainActor
struct CutSettingsCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SETTINGS"] == "1"))
    func captureSettingsStates() async throws {
        let states: [(String, CutSettingsFacts)] = [
            ("settings-signed-in", CutSettingsFacts(isLocalMode: false, isLoggedIn: true, activityCount: 3, friendRequestCount: 2)),
            ("settings-local", CutSettingsFacts(isLocalMode: true, isLoggedIn: false)),
            ("settings-signed-out", CutSettingsFacts(isLocalMode: false, isLoggedIn: false))
        ]
        for (name, facts) in states {
            try await settingsCapture(CutSettingsView(model: CutSettingsLogic.model(facts)), name: name)
        }
        try await settingsCapture(
            CutSettingsView(model: CutSettingsLogic.model(states[0].1)),
            name: "settings-signed-in-ax5", dynamicType: .accessibility5)
    }
}

// MARK: - Capture helpers

private var settingsCaptureRoot: URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-settings")
}

/// A page pushed on the Me tab's navigation stack, under the system tab bar.
struct CutSettingsCaptureShell<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var tab = 4

    var body: some View {
        TabView(selection: $tab) {
            Tab("Train", image: "tab-train-inactive", value: 0) { Color.black }
            Tab("Plan", image: "tab-plan-inactive", value: 1) { Color.black }
            Tab("Social", image: "tab-social-inactive", value: 2) { Color.black }
            Tab("Cardio", image: "tab-cardio-inactive", value: 3) { Color.black }
            Tab("Me", image: "tab-profile", value: 4) {
                NavigationStack {
                    Color.black
                        .navigationDestination(isPresented: .constant(true)) { content() }
                }
            }
        }
        .tint(DS.Palette.marone)
    }
}

/// Renders a pushed page in a dark window at the iPhone's scale, then once more scrolled to the
/// end when the content scrolls. With `pushed: false` the content is the window's root (sheets).
@MainActor
func settingsCapture<V: View>(_ content: V, name: String, dynamicType: DynamicTypeSize = .large,
                              pushed: Bool = true) async throws {
    try FileManager.default.createDirectory(at: settingsCaptureRoot, withIntermediateDirectories: true)
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.overrideUserInterfaceStyle = .dark
    let root: AnyView = pushed ? AnyView(CutSettingsCaptureShell { content }) : AnyView(content)
    window.rootViewController = UIHostingController(rootView: root.environment(\.dynamicTypeSize, dynamicType))
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .seconds(2))
    try settingsCaptureWrite(window, to: name)

    guard let scroll = settingsCaptureTallestScroll(in: window) else { return }
    func maxOffset() -> CGFloat {
        scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
    }
    guard maxOffset() > 40 else { return }
    // A long page also gets its middle.
    if maxOffset() > scroll.bounds.height {
        scroll.setContentOffset(CGPoint(x: 0, y: maxOffset() / 2), animated: false)
        try await Task.sleep(for: .seconds(1))
        try settingsCaptureWrite(window, to: "\(name)-mid")
    }
    // Lists estimate row heights, so the end moves as rows render: settle before capturing.
    for _ in 0..<4 {
        scroll.setContentOffset(CGPoint(x: 0, y: maxOffset()), animated: false)
        try await Task.sleep(for: .seconds(0.5))
    }
    try settingsCaptureWrite(window, to: "\(name)-end")
}

/// A sheet over a dark page, presented the way the app presents it, so detents apply.
struct CutSettingsSheetShell<Sheet: View>: View {
    @ViewBuilder let sheet: () -> Sheet
    @State private var shows = false

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: $shows) { sheet() }
            .onAppear { shows = true }
    }
}

@MainActor
private func settingsCaptureWrite(_ window: UIWindow, to name: String) throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try #require(image.pngData()).write(to: settingsCaptureRoot.appendingPathComponent(name + ".png"))
}

@MainActor
private func settingsCaptureTallestScroll(in view: UIView) -> UIScrollView? {
    var best: UIScrollView?
    func visit(_ view: UIView) {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height,
           scroll.contentSize.height - scroll.bounds.height > (best.map { $0.contentSize.height - $0.bounds.height } ?? 0) {
            best = scroll
        }
        view.subviews.forEach(visit)
    }
    visit(view)
    return best
}
