import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import WRKT

/// Captures of the real Cut rack host over an in-memory container holding a realistic 90-plate
/// inventory (CutRackRealisticInventory): three plates loaded, 87 in storage, with the duplicates
/// a long-time owner collects. Nothing is written to the account's store.
/// TEST_RUNNER_VOLIA_CAPTURE_HOST=1, TEST_RUNNER_VOLIA_CAPTURE_DIR=<directory>,
/// TEST_RUNNER_VOLIA_CAPTURE_HOLD=<seconds> writes <name>.ready and holds the window for an outside
/// simctl screenshot (the Metal layer is not in drawHierarchy). TEST_RUNNER_VOLIA_CAPTURE_TAG names
/// the files (for example "before-small"). TEST_RUNNER_VOLIA_CAPTURE_AX=1 also captures at
/// accessibility text size 5.
@MainActor
@Suite(.serialized)
struct CutRackHostCaptureTests {
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-rack-host")
    }
    private var hold: Double { Double(ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HOLD"] ?? "") ?? 0 }
    private var tag: String { ProcessInfo.processInfo.environment["VOLIA_CAPTURE_TAG"] ?? "host" }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HOST"] == "1"))
    func captureHost() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Provisional notification permission is granted without a prompt, so the app's own
        // request on launch does not put a system alert over the capture (on later runs).
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.provisional])
        let inventory = try CutRackRealisticInventory()
        // Rail states load and drop plates: saves go to the in-memory inventory, never the store.
        let previous = BarbellProgressService.shared.swapContextForTesting(inventory.container.mainContext, remoteSyncOff: true)
        defer { _ = BarbellProgressService.shared.swapContextForTesting(previous, remoteSyncOff: false) }
        currentInventory = inventory
        var sizes: [DynamicTypeSize] = [.large]
        if ProcessInfo.processInfo.environment["VOLIA_CAPTURE_AX"] == "1" { sizes.append(.accessibility5) }
        for size in sizes {
            let name = "\(tag)\(size == .large ? "" : "-ax5")"
            try await show(CutRackHost().modelContainer(inventory.container).environment(\.dynamicTypeSize, size), name: name)
        }
    }

    private var currentInventory: CutRackRealisticInventory? {
        get { Self.inventory }
        nonmutating set { Self.inventory = newValue }
    }
    private static var inventory: CutRackRealisticInventory?

    private func ready(_ name: String) async throws {
        guard hold > 0 else { return }
        try Data().write(to: root.appendingPathComponent(name + ".ready"))
        try await Task.sleep(for: .seconds(hold))
    }

    /// TEST_RUNNER_VOLIA_CAPTURE_RAIL=1: the rail's states, after the rest and tray captures: a group
    /// lifted face on, the readout flashing after a load, the loaded slot, plates dropped on the
    /// floor. Only on the rail (debug default).
    private func captureRail(name: String, window: UIWindow) async throws {
        guard ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RAIL"] == "1", CutRackTrayStyle.current == .rail,
              let rail = CutRackHost.testRail, let toggle = CutRackHost.testToggle, let inventory = currentInventory else { return }
        if let tray = Self.horizontalScroll(in: window) { tray.setContentOffset(.zero, animated: false) }
        // The engraved "75 Workouts" Rose Gold plate is on the bar; lift the red 20 kg bumpers.
        let groups = rail.groupIDs()
        if let red = groups.first(where: { $0.hasPrefix("look:14|") }) {
            rail.lift(red)
            try await Task.sleep(for: .seconds(4))
            if let page = Self.verticalScroll(in: window) {
                page.setContentOffset(CGPoint(x: 0, y: max(0, page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom)), animated: false)
                try await Task.sleep(for: .seconds(1))
            }
            try await ready(name + "-lifted")
            rail.lift(nil)
            try await Task.sleep(for: .seconds(1))
        }
        // Load a blue bumper: the readout flashes as it seats, then its slot stays on the rail.
        if let blue = inventory.plates.first(where: { $0.tierID == 15 && !$0.isRacked }) {
            toggle(blue.id)
            try await Task.sleep(for: .milliseconds(950))
            try await ready(name + "-flash")
            try await Task.sleep(for: .seconds(2))
            try await ready(name + "-loaded")
        }
        rail.drop()
        try await Task.sleep(for: .seconds(7))
        try await ready(name + "-dropped")
    }

    private func show<Content: View>(_ content: Content, name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: content.preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        // A cold simulator takes a while to build the studio light and the first faces.
        try await Task.sleep(for: .seconds(Double(ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WAIT"] ?? "") ?? 15))
        if hold > 0 {
            try Data().write(to: root.appendingPathComponent(name + ".ready"))
            try await Task.sleep(for: .seconds(hold))
        }
        // TEST_RUNNER_VOLIA_CAPTURE_TRAY=<points,...>: the tray scrolled to each offset, as <name>-tray-<n>.
        for (index, value) in (ProcessInfo.processInfo.environment["VOLIA_CAPTURE_TRAY"] ?? "").split(separator: ",").enumerated() {
            guard let x = Double(value), let tray = Self.horizontalScroll(in: window) else { continue }
            tray.setContentOffset(CGPoint(x: min(x, max(0, tray.contentSize.width - tray.bounds.width)), y: 0), animated: false)
            try await Task.sleep(for: .seconds(2))
            if hold > 0 {
                try Data().write(to: root.appendingPathComponent("\(name)-tray-\(index + 1).ready"))
                try await Task.sleep(for: .seconds(hold))
            }
        }
        // Large text: the page scrolls; the bottom shows the tray.
        if let page = Self.verticalScroll(in: window) {
            page.setContentOffset(CGPoint(x: 0, y: max(0, page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(for: .seconds(1))
            try await ready(name + "-bottom")
        }
        try await captureRail(name: name, window: window)
    }

    private static func verticalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 1 { return scroll }
        for child in view.subviews { if let found = verticalScroll(in: child) { return found } }
        return nil
    }

    private static func horizontalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 { return scroll }
        for child in view.subviews { if let found = horizontalScroll(in: child) { return found } }
        return nil
    }
}

/// 90 earned plates the way the unlock rules hand them out to someone with about 90 workouts,
/// plus the identical plain bumpers the owner reports: a Rose Gold "75 Workouts" and two red 20 kg
/// bumpers on the bar (150 kg), and in storage piles of red, blue and black 20 kg bumpers, 18
/// "Personal Record" competition plates, battle plates, milestone and lift plates, a few colour
/// drops and the 90-day streak gold. In memory only.
@MainActor
struct CutRackRealisticInventory {
    let container: ModelContainer
    let plates: [EarnedPlate]

    struct Spec {
        var tier: Int
        var kg: Double
        var engraving = ""
        var count = 1
        var progression: BarbellPlateProgressionTier = .iron
        var lift: String?
        var slots: [Int] = []
    }

    static let specs: [Spec] = [
        Spec(tier: 8, kg: 25, engraving: "75 Workouts", progression: .steel, slots: [0]),
        Spec(tier: 14, kg: 20, count: 12, slots: [1, 2]),
        Spec(tier: 14, kg: 20, count: 2, progression: .steel),
        Spec(tier: 15, kg: 20, count: 7),
        Spec(tier: 2, kg: 20, count: 6),
        Spec(tier: 4, kg: 20, engraving: "Personal Record", count: 18, progression: .steel),
        Spec(tier: 0, kg: 5, engraving: "Session 3"),
        Spec(tier: 0, kg: 5, engraving: "Session 6"),
        Spec(tier: 0, kg: 5, engraving: "Session 9"),
        Spec(tier: 0, kg: 5, engraving: "Session 12"),
        Spec(tier: 0, kg: 2.5, engraving: "First Lift"),
        Spec(tier: 0, kg: 5, engraving: "Squat", lift: "squat"),
        Spec(tier: 0, kg: 5, engraving: "Bench Press", lift: "bench-press"),
        Spec(tier: 0, kg: 5, engraving: "Deadlift", lift: "deadlift"),
        Spec(tier: 0, kg: 5, engraving: "Overhead Press", lift: "overhead-press"),
        Spec(tier: 0, kg: 5, engraving: "Row", lift: "row"),
        Spec(tier: 1, kg: 5, engraving: "5 Workouts", progression: .chrome),
        Spec(tier: 16, kg: 10, engraving: "15 Workouts", progression: .steel),
        Spec(tier: 3, kg: 15, engraving: "25 Workouts", progression: .steel),
        Spec(tier: 5, kg: 25, engraving: "50 Workouts"),
        Spec(tier: 25, kg: 20, engraving: "Volume Battle", count: 4),
        Spec(tier: 27, kg: 20, engraving: "Exercise Battle", count: 4),
        Spec(tier: 29, kg: 20, engraving: "Distance Duel", count: 3),
        Spec(tier: 26, kg: 35, engraving: "Volume Champion", count: 2),
        Spec(tier: 28, kg: 35, engraving: "Exercise Champion"),
        Spec(tier: 1, kg: 5, engraving: "5 Sessions"),
        Spec(tier: 2, kg: 10, engraving: "15 Sessions"),
        Spec(tier: 3, kg: 15, engraving: "25 Sessions"),
        Spec(tier: 22, kg: 20, count: 2),
        Spec(tier: 19, kg: 20, count: 3),
        Spec(tier: 23, kg: 20, count: 2),
        Spec(tier: 17, kg: 10),
        Spec(tier: 18, kg: 25),
        Spec(tier: 21, kg: 15),
        Spec(tier: 20, kg: 20, count: 2),
        Spec(tier: 6, kg: 45, engraving: "90-Day Streak")
    ]

    init() throws {
        container = try ModelContainer(for: EarnedPlate.self, BarbellConfig.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        var made: [EarnedPlate] = []
        var index = 0
        for spec in Self.specs {
            for copy in 0..<spec.count {
                let slot = copy < spec.slots.count ? spec.slots[copy] : nil
                let plate = EarnedPlate(id: "real-\(index)", tierID: spec.tier, weightKg: spec.kg, engravingText: spec.engraving,
                                        earnedAt: day.addingTimeInterval(Double(index) * 86_400 * 3), earnedByEvent: "fixture-\(index)",
                                        isRacked: slot != nil, rackPosition: slot, liftTypeID: spec.lift,
                                        currentTier: spec.progression, workoutsUsedCount: index % 23, prCount: index % 4)
                container.mainContext.insert(plate)
                made.append(plate)
                index += 1
            }
        }
        try container.mainContext.save()
        plates = made
    }
}
