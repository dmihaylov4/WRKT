import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only rendering of the Cut onboarding pages: no host, no stored settings.
/// Opt in with TEST_RUNNER_VOLIA_CAPTURE_WELCOME=1 (and TEST_RUNNER_VOLIA_CAPTURE_STATE for one state).
@MainActor
@Suite(.serialized)
struct CutOnboardingCaptureTests {
    nonisolated static let names = [
        "onboarding-1", "onboarding-2", "onboarding-3", "onboarding-1-ax", "onboarding-1-ax-bottom",
        "bodyweight-kg", "bodyweight-lb", "bodyweight-min", "bodyweight-ax", "bodyweight-ax-bottom"
    ]
    nonisolated static var selectedNames: [String] {
        guard let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"], names.contains(selected) else { return names }
        return [selected]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WELCOME"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        try await CutWelcomeCapture.render(name: name, settle: 2) { makeScene(name) }
    }

    private func makeScene(_ name: String) -> some View {
        let page: Int
        switch name {
        case "onboarding-2": page = 1
        case "onboarding-3": page = 2
        case _ where name.hasPrefix("bodyweight"): page = 3
        default: page = 0
        }
        let unit: WeightUnit = name == "bodyweight-lb" ? .lb : .kg
        let kg = name == "bodyweight-min" ? 30 : 78.5
        return CutOnboardingView(page: .constant(page), bodyweight: CutOnboardingLogic.bodyweight(kg: kg, unit: unit))
    }
}

/// Shared by the welcome capture suites: renders a fixture scene in its own window and writes a PNG.
@MainActor
enum CutWelcomeCapture {
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-welcome")
    }

    static func render<Content: View>(name: String, settle: Double, @ViewBuilder scene: () -> Content) async throws {
        let windowScene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = windowScene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: windowScene)
        let size: DynamicTypeSize = name.contains("-ax") ? .accessibility5 : .large
        window.rootViewController = UIHostingController(rootView: scene().environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(settle))
        if name.hasSuffix("-bottom"), let scroll = verticalScroll(in: window) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }

    /// The tallest scroll view that can scroll; inside a sheet, the sheet's own.
    private static func verticalScroll(in view: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ v: UIView) {
            // Only a scroll view on screen: a paged TabView keeps its other pages loaded beside it.
            if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height + 1, s.bounds.height > 0,
               let window = s.window, s.convert(s.bounds, to: window).intersects(window.bounds) { candidates.append(s) }
            v.subviews.forEach(visit)
        }
        visit(view)
        return candidates.max { $0.bounds.height < $1.bounds.height }
    }
}
