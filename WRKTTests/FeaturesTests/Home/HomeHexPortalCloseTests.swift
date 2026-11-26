import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// After the way back, nothing moves: the window is at rest in its corner from the close's last
/// frame on. The cover is let go with a UIKit dismissal that slides it down even inside a
/// transaction without animations; a cover still drawing its cell then showed a second hexagon
/// coming down from the top of the screen onto the window (the cell is placed in the cover's own
/// coordinates, which jump to the slide's end). Runs the close scrubbed, without the live room.
@MainActor
@Suite(.serialized)
struct HomeHexPortalCloseTests {
    @Test func nothingMovesAboveTheWindowAfterTheClose() async throws {
        await HexPortalFixture.waitForScene()
        let fixture = try HexPortalFixture()
        let host = try CloseHarness(fixture: fixture)
        defer { host.close() }
        let portal = host.coordinator
        try await waitUntil(5) { portal.latestSourceFrame != .zero }
        try await Task.sleep(for: .milliseconds(300))
        let rest = portal.latestSourceFrame
        try #require(rest.minY > 40, "window not laid out: \(rest)")

        portal.scrubMode = true
        portal.open(reduceMotion: false)
        try await waitUntil(5) { portal.timeline.contains { $0.0 == "zoomStart" } }
        try await waitUntil(5) { host.cover.map { !$0.isBeingPresented } ?? false }
        try await Task.sleep(for: .milliseconds(300))
        try #require(host.cover != nil, "the cover did not open")

        portal.close()
        try await waitUntil(5) { portal.phase.stage == .closing }
        portal.finishScrubbedClose()

        // The column above the window, from the top of the screen to just above the window: what
        // came down through it is the stray hexagon.
        let column = CGRect(x: rest.minX, y: 0, width: rest.width, height: rest.minY - 2)
        var frames: [[UInt8]] = []
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 0.8 {
            frames.append(host.pixels(in: column))
            _ = await HomeTiming.nextFrame()
        }
        try await waitUntil(3) { host.cover == nil }
        try await Task.sleep(for: .milliseconds(300))
        let settled = host.pixels(in: column)
        let changed = frames.map { CloseHarness.changedPixels($0, settled) }
        #expect(changed.allSatisfy { $0 < 20 }, "pixels changed above the window after the close, per frame: \(changed)")
    }

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async throws {
        let start = CACurrentMediaTime()
        while !condition() {
            guard CACurrentMediaTime() - start < seconds else { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// The Train view with the portal in its own window, like the app's Home. No still is rendered
/// (a workout counts as busy), so the window shows its placeholder.
@MainActor
private final class CloseHarness {
    let coordinator = HomeHexPortalCoordinator()
    let window: UIWindow
    private let previous: UIWindow?

    init(fixture: HexPortalFixture) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        window = UIWindow(windowScene: scene)
        let coordinator = coordinator
        let home = TabView {
            CutTrainView(model: CutTrainFixtures.model(.planned(name: "Upper Body", exerciseCount: 6))) {
                HomeHexPortalHost(coordinator: coordinator, workoutBusy: true)
            }
            .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
        }
        .modelContainer(fixture.container)
        .preferredColorScheme(.dark)
        window.rootViewController = UIHostingController(rootView: home)
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
    }

    var cover: UIViewController? { window.rootViewController?.presentedViewController }

    /// What is on screen in a rect of the window, as RGBA bytes at 1x.
    func pixels(in rect: CGRect) -> [UInt8] {
        let width = Int(rect.width), height = Int(rect.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            window.drawHierarchy(in: window.bounds.offsetBy(dx: -rect.minX, dy: -rect.minY), afterScreenUpdates: false)
            UIGraphicsPopContext()
        }
        return bytes
    }

    static func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return Int.max }
        var count = 0
        for i in stride(from: 0, to: a.count, by: 4)
        where abs(Int(a[i]) - Int(b[i])) > 24 || abs(Int(a[i + 1]) - Int(b[i + 1])) > 24 || abs(Int(a[i + 2]) - Int(b[i + 2])) > 24 {
            count += 1
        }
        return count
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previous?.isHidden = false
        previous?.makeKey()
    }
}
