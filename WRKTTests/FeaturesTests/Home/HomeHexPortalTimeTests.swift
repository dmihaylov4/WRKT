import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Home open and scroll timing for the hex portal (TEST_RUNNER_VOLIA_HOME_HEX_TIME=1;
/// TEST_RUNNER_VOLIA_HOME_HEX_OUT=<directory> also writes the report there). Hosts the Cut Train
/// view with fixture values in its own window: "open" is the time from showing the window to the
/// first display refresh after its first layout, "scroll" drives the scroll view through 90
/// display frames and records the frame gaps. Nothing reads or writes the account.
@MainActor
@Suite(.serialized)
struct HomeHexPortalTimeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HOME_HEX_TIME"] == "1"))
    func measureHome() async throws {
        var report = "home open and scroll (fixture Train view, planned state)\n"
        report += try await HomeTiming.run(label: "train") {
            AnyView(CutTrainView(model: CutTrainFixtures.model(.planned(name: "Upper Body", exerciseCount: 6))))
        }
        report += try await HomeTiming.run(label: "train-ax2 (scrolls)") {
            AnyView(CutTrainView(model: CutTrainFixtures.model(.planned(name: "Upper Body", exerciseCount: 6)))
                .environment(\.dynamicTypeSize, .accessibility2))
        }
        // The same with the hex portal: its still cached (rendered once first), then uncached
        // (the window shows its placeholder; the still would render 1.5 s later, after the run).
        let fixture = try HexPortalFixture()
        let warm = try HexHarness(fixture: fixture, hero: .planned(name: "Upper Body", exerciseCount: 6))
        try await warm.waitForStill()
        warm.close()
        for (label, size) in [("train+portal, still cached", DynamicTypeSize.large), ("train-ax2+portal, still cached", .accessibility2)] {
            report += try await HomeTiming.run(label: label, scrolling: { HomeTiming.portal?.isScrolling = $0 }) {
                AnyView(HomeTiming.portalView(fixture, size))
            }
        }
        HexPortalFixture.clearStills()
        report += try await HomeTiming.run(label: "train-ax2+portal, no still yet", before: { HexPortalFixture.clearStills() },
                                           scrolling: { HomeTiming.portal?.isScrolling = $0 }) {
            AnyView(HomeTiming.portalView(fixture, .accessibility2))
        }
        print(report)
        if let out = ProcessInfo.processInfo.environment["VOLIA_HOME_HEX_OUT"] {
            try report.write(to: URL(fileURLWithPath: out).appendingPathComponent("home-time-\(Int(Date().timeIntervalSince1970)).txt"),
                             atomically: true, encoding: .utf8)
        }
    }
}

@MainActor
enum HomeTiming {
    /// The portal's coordinator in the view being timed.
    static var portal: HomeHexPortalCoordinator?

    static func portalView(_ fixture: HexPortalFixture, _ size: DynamicTypeSize) -> some View {
        let coordinator = HomeHexPortalCoordinator()
        portal = coordinator
        return CutTrainView(model: CutTrainFixtures.model(.planned(name: "Upper Body", exerciseCount: 6))) {
            HomeHexPortalHost(coordinator: coordinator, workoutBusy: false)
        }
        .modelContainer(fixture.container)
        .environment(\.dynamicTypeSize, size)
    }

    static func run(label: String, repeats: Int = 8, before: () -> Void = {}, scrolling: (Bool) -> Void = { _ in },
                    content: @escaping () -> AnyView) async throws -> String {
        var opens: [Double] = []
        var scrollReport = ""
        for index in 0..<repeats {
            before()
            let (window, previous) = try makeWindow(content())
            let start = CACurrentMediaTime()
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            let frame = await nextFrame()
            opens.append((frame - start) * 1000)
            try await Task.sleep(for: .milliseconds(400))
            if index == repeats - 1, let scroll = verticalScroll(in: window) {
                // A finger-driven scroll reports its phase; this programmatic one says so itself.
                scrolling(true)
                scrollReport = await scrollFrames(scroll)
                scrolling(false)
            }
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            try await Task.sleep(for: .milliseconds(200))
        }
        let sorted = opens.sorted()
        return String(format: "[%@] open median %.1f ms, min %.1f, max %.1f (first %.1f)\n", label as NSString,
                      sorted[sorted.count / 2], sorted.first ?? 0, sorted.last ?? 0, opens.first ?? 0) + scrollReport
    }

    static func makeWindow(_ view: AnyView) throws -> (UIWindow, UIWindow?) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        return (window, previous)
    }

    static func nextFrame() async -> CFTimeInterval {
        await withCheckedContinuation { continuation in
            let link = FrameLink { time, link in
                link.invalidate()
                continuation.resume(returning: time)
            }
            link.start()
        }
    }

    /// Scrolls down and back over 90 frames, one step per display refresh.
    static func scrollFrames(_ scroll: UIScrollView) async -> String {
        let maxOffset = max(0, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        let top = -scroll.adjustedContentInset.top
        let travel = max(maxOffset - top, 1)
        var gaps: [Double] = []
        var last: CFTimeInterval = 0
        var step = 0
        let bodiesBefore = HomeHexPortalDiagnostics.trainBodies
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let link = FrameLink { time, link in
                if last > 0 { gaps.append((time - last) * 1000) }
                last = time
                step += 1
                let phase = Double(step) / 45
                let t = phase <= 1 ? phase : 2 - phase
                scroll.setContentOffset(CGPoint(x: 0, y: top + travel * t), animated: false)
                if step >= 90 {
                    link.invalidate()
                    continuation.resume()
                }
            }
            link.start()
        }
        let over = gaps.filter { $0 > 16.7 * 1.5 }.count
        return String(format: "  scroll: %d frames, %d over 25 ms, worst %.1f ms, train bodies %d (travel %.0f pt)\n",
                      gaps.count, over, gaps.max() ?? 0, HomeHexPortalDiagnostics.trainBodies - bodiesBefore, travel)
    }

    static func verticalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.bounds.height > 300 { return scroll }
        for child in view.subviews { if let found = verticalScroll(in: child) { return found } }
        return nil
    }
}

/// A display link with a closure.
@MainActor
final class FrameLink: NSObject {
    private var link: CADisplayLink?
    private let tick: (CFTimeInterval, FrameLink) -> Void

    init(_ tick: @escaping (CFTimeInterval, FrameLink) -> Void) {
        self.tick = tick
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func fire(_ link: CADisplayLink) {
        MainActor.assumeIsolated { tick(link.timestamp, self) }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
