import Combine
import Foundation
import QuartzCore
import RealityKit
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// The rack throw-smoothness harness: opens the real CutRackHost (rail or card tray) over an
/// in-memory inventory (90 plates, two on the bar), drops the outer bar plate to the floor, then
/// picks it up, drags it for a second and throws it through the same SceneState calls the drag
/// gesture makes, and watches it land. Records, from the pick-up to two seconds after the throw:
/// scene frame intervals (SceneEvents.Update) and main run loop frame intervals (CADisplayLink)
/// as p50, p95, max and counts over 16.7 and 33 ms; the scene frame update's main-thread time;
/// SwiftUI body evaluations of the host, the rail, its row and its pictures; and the rail picture
/// and thumbnail renders that ran meanwhile. BarbellProgressService runs on the in-memory context
/// with remote sync off; nothing reaches the account's store or backend.
///
/// TEST_RUNNER_VOLIA_RACK_THROW=1 enables it. TEST_RUNNER_VOLIA_RACK_SPRITES=cold forgets every rail
/// picture first, so the picture queue renders while the plate is thrown (a fresh install);
/// otherwise the harness waits for the queue to go idle. TEST_RUNNER_VOLIA_RACK_TRAY=card,
/// VOLIA_RACK_CCD=0, VOLIA_RACK_COLLIDER=box, VOLIA_RACK_DISC_SIDES=<n> and VOLIA_RACK_PLATES pick
/// the variant; TEST_RUNNER_VOLIA_RACK_OPEN_OUT=<directory> also writes the report there.
@MainActor
@Suite(.serialized)
struct CutRackThrowFPSTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_THROW"] == "1"))
    func measureAThrow() async throws {
        let environment = ProcessInfo.processInfo.environment
        // cold: no pictures on disk; busy: also every look requested, as scrolling the row does,
        // so the picture queue is still rendering when the plate is thrown.
        let busySprites = environment["VOLIA_RACK_SPRITES"] == "busy"
        let coldSprites = busySprites || environment["VOLIA_RACK_SPRITES"] == "cold"
        let inventory = try RackOpenInventory(count: 90, onBar: 2)
        if coldSprites { RackRailSpriteService.shared.removeAllForTesting() }
        let previous = BarbellProgressService.shared.swapContextForTesting(inventory.container.mainContext, remoteSyncOff: true)
        defer { _ = BarbellProgressService.shared.swapContextForTesting(previous, remoteSyncOff: false) }

        let windowScene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = windowScene.windows.first { $0.isKeyWindow }
        previousWindow?.isHidden = true
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: CutRackHost().modelContainer(inventory.container).preferredColorScheme(.dark))
        window.windowLevel = .alert + 1
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.isHidden = false
            previousWindow?.makeKey()
        }
        RackOpenTrace.begin("open")
        let opened = CACurrentMediaTime()
        window.makeKeyAndVisible()
        while RackOpenTrace.time(of: "firstFrame") == nil, CACurrentMediaTime() - opened < 60 {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .seconds(2))
        if !coldSprites {
            let start = CACurrentMediaTime()
            while !RackRailSpriteService.shared.isIdleForTesting, CACurrentMediaTime() - start < 120 {
                try await Task.sleep(for: .milliseconds(200))
            }
            try await Task.sleep(for: .seconds(1))
        }

        if busySprites {
            for request in latheFirstFrameRequests(inventory.plates) { RackRailSpriteService.shared.requestStand(request) }
        }
        let state = try #require(CutRackHost.testScene)
        let outer = try #require(inventory.plates.filter(\.isRacked).max { ($0.rackPosition ?? 0) < ($1.rackPosition ?? 0) })
        #expect(await state.releaseBarPlateToFloor(plateID: outer.id))
        try await Task.sleep(for: .seconds(2.5))
        let entity = try #require(state.entityMap[outer.id])

        let recorder = try #require(RackFrameRecorder(scene: state.sceneRoot.scene))
        let before = RackWorkCounters.snapshot()
        let spriteBusyAtStart = !RackRailSpriteService.shared.isIdleForTesting
        recorder.start()

        // Pick up, carry up and to the right for a second, throw up and to the side.
        #expect(state.transition(to: .draggingPlate(entity, plateID: outer.id, originRole: .floor)))
        state.beginHold(entity: entity, plateID: outer.id, barSlot: nil)
        for step in 1...60 {
            let t = CGFloat(step) / 60
            state.updateHold(translation: CGSize(width: 120 * t, height: -160 * t), maxAbsX: 0.64)
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(state.transition(to: .idle))
        state.endHold()
        state.releaseLoose(entity: entity, plateID: outer.id, fingerVelocity: CGSize(width: 900, height: -1400), maxAbsX: 0.64)
        let released = CACurrentMediaTime()
        var asleepAfter: Double?
        while CACurrentMediaTime() - released < 2 || (asleepAfter == nil && CACurrentMediaTime() - released < 8) {
            if asleepAfter == nil, state.floorSettles.isEmpty { asleepAfter = CACurrentMediaTime() - released }
            try await Task.sleep(for: .milliseconds(16))
        }

        recorder.stop()
        let after = RackWorkCounters.snapshot()
        func delta(_ work: RackWork) -> Int { (after[work] ?? 0) - (before[work] ?? 0) }
        let updates = max(1, delta(.sceneFrameUpdates))
        var report = "tray=\(CutRackTrayStyle.current) plates=\(RackPlateStyle.current.rawValue) sprites=\(busySprites ? "busy" : coldSprites ? "cold" : "warm")"
        report += " ccd=\(RackPhysicsDebug.ccdEnabled) collider=\(RackPhysicsDebug.usesBoxCollider ? "box" : "disc\(RackPhysicsDebug.discSides)")\n"
        report += "scene frames: " + RackFrameRecorder.summary(recorder.sceneIntervals) + "\n"
        report += "main frames:  " + RackFrameRecorder.summary(recorder.mainIntervals) + "\n"
        report += String(format: "frame update: %d calls, %.1f us mean\n", delta(.sceneFrameUpdates),
                         Double(delta(.sceneFrameUpdateMicros)) / Double(updates))
        report += "bodies: host=\(delta(.hostBodies)) rail=\(delta(.railScreenBodies)) row=\(delta(.railRowBodies)) pictures=\(delta(.railPictureBodies))\n"
        report += String(format: "since open: %.1f s, rail pictures rendered in all: %d, row picture bodies in all: %d\n",
                         CACurrentMediaTime() - opened, after[.railSpritesRendered] ?? 0, after[.railPictureBodies] ?? 0)
        report += "asleep after the throw: " + (asleepAfter.map { String(format: "%.2f s", $0) } ?? "not within 8 s") + "\n"
        report += "renders: railSprites=\(delta(.railSpritesRendered)) thumbnails=\(delta(.thumbnailsRendered)) busyAtStart=\(spriteBusyAtStart) busyAtEnd=\(!RackRailSpriteService.shared.isIdleForTesting)\n"
        print(report)
        // Nothing in the screen re-evaluates per frame while a plate is held and thrown, and no
        // offscreen render starts during it.
        #expect(delta(.hostBodies) + delta(.railScreenBodies) + delta(.railRowBodies) <= 4)
        #expect(delta(.railPictureBodies) <= 8)
        #expect(delta(.railSpritesRendered) == 0 && delta(.thumbnailsRendered) == 0)
        if let out = environment["VOLIA_RACK_OPEN_OUT"] {
            let name = "throw-\(Int(Date().timeIntervalSince1970 * 10)).txt"
            try report.write(to: URL(fileURLWithPath: out).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}

/// Frame intervals from the scene's updates and from a display link on the main run loop.
@MainActor
final class RackFrameRecorder {
    private let scene: RealityKit.Scene
    private var subscription: (any Cancellable)?
    private var link: CADisplayLink?
    private var lastScene: CFTimeInterval?
    private var lastMain: CFTimeInterval?
    private(set) var sceneIntervals: [Double] = []
    private(set) var mainIntervals: [Double] = []

    init?(scene: RealityKit.Scene?) {
        guard let scene else { return nil }
        self.scene = scene
    }

    func start() {
        subscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickScene() }
        }
        let link = CADisplayLink(target: RackFrameRecorderTarget { [weak self] in self?.tickMain() }, selector: #selector(RackFrameRecorderTarget.fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        subscription?.cancel()
        link?.invalidate()
    }

    private func tickScene() {
        let now = CACurrentMediaTime()
        if let lastScene { sceneIntervals.append((now - lastScene) * 1000) }
        lastScene = now
    }

    private func tickMain() {
        let now = CACurrentMediaTime()
        if let lastMain { mainIntervals.append((now - lastMain) * 1000) }
        lastMain = now
    }

    nonisolated static func summary(_ intervals: [Double]) -> String {
        guard !intervals.isEmpty else { return "none" }
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        // At 60 Hz a frame on time is 16.7 ms give or take a few; over 20 ms is at least one frame
        // missed, over 36 ms at least two.
        return String(format: "n=%d p50=%.1f p95=%.1f max=%.1f over16.7(>20ms)=%d over33(>36ms)=%d", sorted.count, percentile(0.5),
                      percentile(0.95), sorted.last ?? 0, sorted.filter { $0 > 20 }.count, sorted.filter { $0 > 36 }.count)
    }
}

/// CADisplayLink's target (it needs an Objective-C selector).
private final class RackFrameRecorderTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ link: CADisplayLink) { action() }
}
