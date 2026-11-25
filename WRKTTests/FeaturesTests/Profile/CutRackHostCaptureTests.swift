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
        var sizes: [DynamicTypeSize] = [.large]
        if ProcessInfo.processInfo.environment["VOLIA_CAPTURE_AX"] == "1" { sizes.append(.accessibility5) }
        for size in sizes {
            let name = "\(tag)\(size == .large ? "" : "-ax5")"
            try await show(CutRackHost().modelContainer(inventory.container).environment(\.dynamicTypeSize, size), name: name)
        }
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
