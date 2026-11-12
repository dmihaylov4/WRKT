import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in capture of the Cut gallery. Runs only with VOLIA_CAPTURE_CUT=1
/// (pass TEST_RUNNER_VOLIA_CAPTURE_CUT=1 to xcodebuild). Writes to
/// /private/tmp/volia-cut-foundations, or to VOLIA_CAPTURE_DIR when set:
///   cut-gallery-1.png ... cut-gallery-N.png  the gallery on screen, a page at a time
@MainActor
struct CutGalleryCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT"] == "1"))
    func captureGallery() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-foundations")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // A window of its own above the app, removed afterwards.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: NavigationStack { CutGalleryView() })
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        try save(window: window, to: root.appendingPathComponent("cut-gallery-1.png"))

        // Further pages: scroll the gallery a screen at a time.
        let scrollView = try #require(firstScrollView(in: window))
        let page = scrollView.bounds.height - 260
        var index = 2
        while scrollView.contentOffset.y + scrollView.bounds.height < scrollView.contentSize.height + scrollView.adjustedContentInset.bottom, index <= 6 {
            let maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
            scrollView.setContentOffset(CGPoint(x: 0, y: min(scrollView.contentOffset.y + page, maxOffset)), animated: false)
            try await Task.sleep(for: .seconds(1))
            try save(window: window, to: root.appendingPathComponent("cut-gallery-\(index).png"))
            index += 1
        }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private func save(window: UIWindow, to url: URL) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }
}
