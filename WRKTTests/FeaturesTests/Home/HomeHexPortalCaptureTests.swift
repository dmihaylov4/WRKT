import Foundation
import QuartzCore
import RealityKit
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures and timings of the Home hex portal, from fixture values over an in-memory
/// container (nothing reads or writes the account). TEST_RUNNER_VOLIA_HEX_CAPTURE=<mode>:
///   states    Home in every field state with the window (drawn in process), plus large text
///   sequence  the opening and closing held frame by frame (each frame writes <name>.ready and
///             waits for <name>.shot, so a shell loop can take `simctl io screenshot`, which
///             records the live Metal layer); TEST_RUNNER_VOLIA_HEX_RM=1 for Reduce Motion
///   time      the real transition twice (cold, warm): frame gaps, main-thread stalls, Train view
///             body evaluations, hand-off times, teardown
/// TEST_RUNNER_VOLIA_CAPTURE_DIR=<directory> for the output.
@MainActor
@Suite(.serialized)
struct HomeHexPortalCaptureTests {
    private var mode: String { ProcessInfo.processInfo.environment["VOLIA_HEX_CAPTURE"] ?? "" }
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-hex-portal")
    }

    // MARK: States

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HEX_CAPTURE"] == "states"))
    func states() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await HexPortalFixture.waitForScene()
        let fixture = try HexPortalFixture()
        let device = UIScreen.main.bounds.width < 380 ? "small" : UIScreen.main.bounds.width > 420 ? "large" : "medium"
        HexPortalFixture.clearStills()
        // The placeholder: the very first frames, before any still exists.
        do {
            let harness = try HexHarness(fixture: fixture, hero: .planned(name: "Upper Body", exerciseCount: 6))
            try await Task.sleep(for: .milliseconds(300))
            try harness.save(root.appendingPathComponent("\(device)-placeholder.png"))
            let start = CACurrentMediaTime()
            try await harness.waitForStill()
            print("[hex] first still rendered in \(Int((CACurrentMediaTime() - start) * 1000)) ms after first frame")
            harness.close()
        }
        let states: [(String, CutTrainHero, DynamicTypeSize)] = [
            ("planned", .planned(name: "Upper Body", exerciseCount: 6), .large),
            ("rest-day", .restDay(next: PlanOutlook.Session(name: "Lower Body", date: CutTrainFixtures.tomorrow)), .large),
            ("done-today", .doneToday(next: PlanOutlook.Session(name: "Lower Body", date: CutTrainFixtures.tomorrow)), .large),
            ("no-plan", .noPlan, .large),
            ("live", .live(name: "Upper Body", exercisesDone: 2, exerciseCount: 6, startDate: .now.addingTimeInterval(-1456)), .large),
            ("resting", .resting(nextLine: "Next: set 3 of 4, 85\u{00A0}kg\u{00A0}x\u{00A0}6", countdown: .fixed(92), exerciseName: "Bench Press"), .large),
            ("planned-long", .planned(name: "Posterior Chain and Conditioning Superset", exerciseCount: 9), .large),
            ("planned-ax3", .planned(name: "Upper Body", exerciseCount: 6), .accessibility3),
            ("no-plan-ax3", .noPlan, .accessibility3),
            ("rest-day-ax5", .restDay(next: PlanOutlook.Session(name: "Lower Body", date: CutTrainFixtures.tomorrow)), .accessibility5),
        ]
        for (name, hero, size) in states {
            let harness = try HexHarness(fixture: fixture, hero: hero, dynamicType: size)
            if HomeHexPortalLogic.isShown(for: hero) { try await harness.waitForStill() }
            try await Task.sleep(for: .milliseconds(500))
            try harness.save(root.appendingPathComponent("\(device)-\(name).png"))
            if let frame = harness.windowFrame { print("[hex] \(device)-\(name) window \(frame)") }
            harness.close()
        }
        let key = try #require(HexHarness.lastKey)
        print("[hex] still on disk: \(RackRoomStillService.shared.diskBytes(key)) bytes")
    }

    // MARK: Sequence

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HEX_CAPTURE"] == "sequence"))
    func sequence() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await HexPortalFixture.waitForScene()
        let reduceMotion = ProcessInfo.processInfo.environment["VOLIA_HEX_RM"] == "1"
        let prefix = reduceMotion ? "rm" : "seq"
        let fixture = try HexPortalFixture()
        let harness = try HexHarness(fixture: fixture, hero: .planned(name: "Upper Body", exerciseCount: 6))
        defer { harness.close() }
        try await harness.waitForStill()
        try await Task.sleep(for: .milliseconds(500))
        let portal = harness.coordinator
        portal.scrubMode = true
        try await shot("\(prefix)-00-home")

        portal.pressChanged(true)
        portal.open(reduceMotion: reduceMotion)
        portal.pressChanged(false)
        // Wait for the zoom to be armed and the live scene to be up under the still.
        try await waitUntil(20) { portal.timeline.contains { $0.0 == "zoomStart" } }
        try await waitUntil(30) { portal.phase.liveReady }
        try await Task.sleep(for: .milliseconds(800))
        var index = 1
        func frame(_ label: String, _ p: CGFloat, still: Double, controls: Double, veil: Bool, tube: Bool = false,
                   cover: Double = 1) async throws {
            portal.scrub(progress: p, still: still, controls: controls, veil: veil, tube: tube, cover: cover)
            try await Task.sleep(for: .milliseconds(250))
            try await shot(String(format: "%@-%02d-%@", prefix, index, label))
            index += 1
        }
        if reduceMotion {
            for cover in [0.0, 0.33, 0.66, 1.0] {
                try await frame(String(format: "fade-%.2f", cover), 1, still: 1, controls: 0, veil: true, cover: cover)
            }
        } else {
            let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.55, y: 0.05), endControlPoint: UnitPoint(x: 0.25, y: 1))
            // Frames at equal time steps through the 680 ms open (what the eye sees at 60 fps / 4).
            for step in 0...8 {
                let t = Double(step) / 8
                let p = CGFloat(curve.value(at: t))
                // The veil is half in from about 330 ms, the tube fades from 420 to 670 ms.
                try await frame(String(format: "open-t%03d", Int(t * 680)), p, still: 1, controls: 0, veil: t > 0.48,
                                tube: t < 0.8)
            }
        }
        portal.finishScrubbedZoom()
        try await frame("handoff-still-50", 1, still: 0.5, controls: 0, veil: true)
        try await frame("handoff-live", 1, still: 0, controls: 0, veil: true)
        try await frame("controls-50", 1, still: 0, controls: 0.5, veil: true)
        try await frame("controls-in", 1, still: 0, controls: 1, veil: true)

        // Load a plate during the visit (straight into the in-memory store; the rack syncs its
        // scene from its query and swings the plate in), so the way back refreshes the still.
        portal.scrubMode = false
        portal.scrub(progress: 1, still: 0, controls: 1, veil: true, tube: false)
        if let stored = fixture.plates.first(where: { !$0.isRacked }) {
            stored.isRacked = true
            stored.rackPosition = 3
            try fixture.container.mainContext.save()
            try await Task.sleep(for: .seconds(3))
            try await frame("loaded-a-plate", 1, still: 0, controls: 1, veil: true)
        }
        let keyBefore = portal.restKey
        portal.scrubMode = true
        portal.close()
        try await waitUntil(5) { portal.phase.stage == .closing }
        try await Task.sleep(for: .milliseconds(300))
        print("[hex] close captured live frame: \(portal.timeline.contains { $0.0 == "liveCaptured" })")
        if reduceMotion {
            for cover in [1.0, 0.66, 0.33, 0.0] {
                try await frame(String(format: "close-fade-%.2f", cover), 1, still: 1, controls: 0, veil: true, cover: cover)
            }
        } else {
            let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.3, y: 0.8), endControlPoint: UnitPoint(x: 0.25, y: 1))
            for step in 0...8 {
                let t = Double(step) / 8
                let p = 1 - CGFloat(curve.value(at: t))
                try await frame(String(format: "close-t%03d", Int(t * 500)), p, still: 1, controls: 0, veil: t < 0.3,
                                tube: t > 0.2)
            }
        }
        portal.finishScrubbedClose()
        try await Task.sleep(for: .milliseconds(600))
        try await shot("\(prefix)-\(index)-home-after")
        print("[hex] still key changed on close: \(keyBefore != portal.restKey)")
    }

    // MARK: Time

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HEX_CAPTURE"] == "time"))
    func time() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await HexPortalFixture.waitForScene()
        let fixture = try HexPortalFixture()
        HexPortalFixture.clearStills()
        let harness = try HexHarness(fixture: fixture, hero: .planned(name: "Upper Body", exerciseCount: 6))
        defer { harness.close() }
        try await harness.waitForStill()
        try await Task.sleep(for: .seconds(1))
        var report = "hex portal transition (\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height)) pt, style \(RackPlateStyle.current.rawValue))\n"
        if let key = HexHarness.lastKey {
            report += "still on disk \(RackRoomStillService.shared.diskBytes(key)) bytes; rest image \(harness.coordinator.restImage.map { "\(Int($0.size.width * $0.scale))x\(Int($0.size.height * $0.scale)) px" } ?? "-")\n"
        }
        for label in ["cold", "warm"] {
            report += "\n[\(label)]\n" + (try await measureRound(harness))
            try await Task.sleep(for: .seconds(2))
        }
        report += "\n[reference: the same rack in a sheet, as Me opens it]\n" + (try await sheetTeardown(fixture))
        print(report)
        try report.write(to: root.appendingPathComponent("hex-time-\(Int(Date().timeIntervalSince1970)).txt"), atomically: true, encoding: .utf8)
    }

    private func measureRound(_ harness: HexHarness) async throws -> String {
        let portal = harness.coordinator
        portal.timeline.removeAll()
        let recorder = FrameRecorder()
        let stalls = MainThreadStallMonitor()
        let bodies = HomeHexPortalDiagnostics.trainBodies
        recorder.start()
        stalls.start()
        portal.pressChanged(true)
        try await Task.sleep(for: .milliseconds(60))
        portal.open(reduceMotion: false)
        portal.pressChanged(false)
        try await waitUntil(15) { portal.timeline.contains { $0.0 == "controlsIn" } }
        try await Task.sleep(for: .milliseconds(300))
        let openStalls = stalls.gaps
        let openLongest = stalls.longest
        recorder.stop()
        let openFrames = recorder.gaps
        let openBodies = HomeHexPortalDiagnostics.trainBodies - bodies
        let openTimeline = portal.timeline
        weak var scene = portal.liveSceneForTesting
        var text = describe("open", openTimeline, frames: openFrames, stallLongest: openLongest, stalls: openStalls,
                            bodies: openBodies, window: ("zoomStart", 0.68))
        text += "  full still \(portal.fullImage.map { "\(Int($0.size.width * $0.scale))x\(Int($0.size.height * $0.scale)) px, \(Int($0.size.width * $0.scale * $0.size.height * $0.scale * 4) / 1_048_576) MB decoded" } ?? "not loaded")\n"

        try await Task.sleep(for: .seconds(1.5))
        portal.timeline.removeAll()
        let closeRecorder = FrameRecorder()
        let closeStalls = MainThreadStallMonitor()
        let closeBodies = HomeHexPortalDiagnostics.trainBodies
        closeRecorder.start()
        closeStalls.start()
        portal.close()
        try await waitUntil(10) { portal.timeline.contains { $0.0 == "closed" } }
        try await Task.sleep(for: .milliseconds(300))
        closeRecorder.stop()
        text += describe("close", portal.timeline, frames: closeRecorder.gaps, stallLongest: closeStalls.longest,
                         stalls: closeStalls.gaps, bodies: HomeHexPortalDiagnostics.trainBodies - closeBodies, window: ("back", 0.6))
        closeStalls.stop()
        stalls.stop()
        try await Task.sleep(for: .seconds(2))
        text += "  after close: scene released \(scene == nil), rack sceneIsUp \(CutRackWarmUp.sceneIsUp), full still released \(portal.fullImage == nil)\n"
        return text
    }

    /// Whether the rack's scene is released 2 s after a sheet with it closes (the Me path).
    private func sheetTeardown(_ fixture: HexPortalFixture) async throws -> String {
        let box = SheetBox()
        weak var scene: SceneState?
        let built = SheetBox()
        let scenes = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scenes)
        window.rootViewController = UIHostingController(rootView: SheetHarness(box: box) {
            CutRackHost().environment(\.cutRackPortal, CutRackPortalHooks(back: {}, sceneFrame: { _ in },
                                                                        sceneBuilt: { state in scene = state; built.shown = true }))
        }.modelContainer(fixture.container).preferredColorScheme(.dark))
        window.windowLevel = .alert + 2
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        box.shown = true
        try await waitUntil(20) { built.shown }
        try await Task.sleep(for: .seconds(1.5))
        box.shown = false
        try await Task.sleep(for: .seconds(2.5))
        return "  after the sheet closes: scene released \(scene == nil), rack sceneIsUp \(CutRackWarmUp.sceneIsUp)\n"
    }

    private func describe(_ name: String, _ timeline: [(String, CFTimeInterval)], frames: [(CFTimeInterval, Double)],
                          stallLongest: CFTimeInterval, stalls: [(end: CFTimeInterval, length: CFTimeInterval)], bodies: Int,
                          window: (String, Double)) -> String {
        let start = timeline.first?.1 ?? 0
        var text = "  \(name) timeline: " + timeline.map { String(format: "%@ %.0f", $0.0 as NSString, ($0.1 - start) * 1000) }.joined(separator: ", ") + " ms\n"
        if let from = timeline.first(where: { $0.0 == window.0 })?.1 {
            let inWindow = frames.filter { $0.0 >= from && $0.0 <= from + window.1 }.map(\.1)
            let over = inWindow.filter { $0 > 16.7 * 1.25 }
            let stallIn = stalls.filter { $0.end >= from && $0.end - $0.length <= from + window.1 }.map(\.length).max() ?? 0
            text += String(format: "  %@ motion (%.0f ms from %@): %d frames, %d over 20.9 ms, worst %.1f ms, longest main stall over 30 ms in it %.1f ms\n",
                           name as NSString, window.1 * 1000, window.0 as NSString, inWindow.count, over.count, inWindow.max() ?? 0, stallIn * 1000)
        }
        text += String(format: "  %@ whole: worst frame %.1f ms, longest main stall %.1f ms, Train view bodies %d\n",
                       name as NSString, frames.map(\.1).max() ?? 0, stallLongest * 1000, bodies)
        return text
    }

    // MARK: Helpers

    private func shot(_ name: String) async throws {
        let ready = root.appendingPathComponent(name + ".ready")
        let done = root.appendingPathComponent(name + ".shot")
        try Data().write(to: ready)
        let start = CACurrentMediaTime()
        while !FileManager.default.fileExists(atPath: done.path), CACurrentMediaTime() - start < 8 {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async throws {
        let start = CACurrentMediaTime()
        while !condition() {
            guard CACurrentMediaTime() - start < seconds else { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Fixture

/// Three plates on the bar (a deep rose 25 kg "75 Workouts" inside two red 20 kg bumpers) and
/// a few stored ones. In memory only.
@MainActor
struct HexPortalFixture {
    let container: ModelContainer
    let plates: [EarnedPlate]

    init() throws {
        container = try ModelContainer(for: EarnedPlate.self, BarbellConfig.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        func plate(_ id: String, tier: Int, kg: Double, slot: Int?, engraving: String = "", order: Int) -> EarnedPlate {
            let plate = EarnedPlate(id: "hex-\(id)", tierID: tier, weightKg: kg, engravingText: engraving,
                                    earnedAt: day.addingTimeInterval(Double(order) * 86_400), earnedByEvent: "fixture",
                                    isRacked: slot != nil, rackPosition: slot, liftTypeID: nil, currentTier: .steel,
                                    workoutsUsedCount: 9, prCount: 1)
            plate.displayOrder = order
            return plate
        }
        plates = [
            plate("rose", tier: 8, kg: 25, slot: 0, engraving: "75 Workouts", order: 9),
            plate("red1", tier: 14, kg: 20, slot: 1, order: 8),
            plate("red2", tier: 14, kg: 20, slot: 2, order: 7),
            plate("gold", tier: 6, kg: 20, slot: nil, order: 6),
            plate("blue", tier: 15, kg: 20, slot: nil, order: 5),
            plate("iron", tier: 1, kg: 25, slot: nil, order: 4),
        ]
        for plate in plates { container.mainContext.insert(plate) }
        try container.mainContext.save()
    }

    /// The test host's window scene can connect a moment after the tests start.
    static func waitForScene() async {
        for _ in 0..<100 where UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func clearStills() {
        let directory = RackRoomStillService.shared.directory
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent != "scene-band-v2.json" && file.lastPathComponent != "room-drawn" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// The Train view with the portal, in its own window inside a tab bar, like the app's Home.
@MainActor
final class HexHarness {
    static var lastKey: String?
    let coordinator = HomeHexPortalCoordinator()
    let window: UIWindow
    private let previous: UIWindow?

    init(fixture: HexPortalFixture, hero: CutTrainHero, dynamicType: DynamicTypeSize = .large) throws {
        // The harness renders stills: as after a first visit to the room.
        RackRoomStillService.shared.noteRoomDrawn()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        window = UIWindow(windowScene: scene)
        let coordinator = coordinator
        let model = CutTrainFixtures.model(hero)
        let home = TabView {
            CutTrainView(model: model, actions: CutTrainActions(scrollingChanged: { coordinator.isScrolling = $0 })) {
                if HomeHexPortalLogic.isShown(for: hero) {
                    HomeHexPortalHost(coordinator: coordinator, workoutBusy: false)
                }
            }
            .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
            Color.black.tabItem { Label("Me", systemImage: "person") }
        }
        .modelContainer(fixture.container)
        .environment(\.dynamicTypeSize, dynamicType)
        .preferredColorScheme(.dark)
        window.rootViewController = UIHostingController(rootView: home)
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
    }

    var windowFrame: CGRect? {
        coordinator.latestSourceFrame == .zero ? nil : coordinator.latestSourceFrame
    }

    func waitForStill(timeout: Double = 60) async throws {
        let start = CACurrentMediaTime()
        while coordinator.restImage == nil, CACurrentMediaTime() - start < timeout {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(coordinator.restImage != nil, "no still after \(timeout) s")
        Self.lastKey = coordinator.restKey
    }

    func save(_ url: URL) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previous?.isHidden = false
        previous?.makeKey()
    }
}

@Observable
@MainActor
final class SheetBox {
    var shown = false
}

private struct SheetHarness<Content: View>: View {
    @Bindable var box: SheetBox
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.black.sheet(isPresented: $box.shown) { content() }
    }
}

/// Every display refresh's timestamp and the gap before it.
@MainActor
final class FrameRecorder {
    private var link: FrameLink?
    private var last: CFTimeInterval = 0
    private(set) var gaps: [(CFTimeInterval, Double)] = []

    func start() {
        let link = FrameLink { [weak self] time, _ in
            guard let self else { return }
            if self.last > 0 { self.gaps.append((time, (time - self.last) * 1000)) }
            self.last = time
        }
        link.start()
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}
