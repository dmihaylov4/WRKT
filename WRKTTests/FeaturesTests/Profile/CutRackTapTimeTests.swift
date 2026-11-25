import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// The rack tap-latency harness: opens the real CutRackHost over an in-memory inventory (90 plates,
/// one on the bar), then taps tray plates through the host's own toggle and records, per tap, the
/// time from the tap to each RackOpenTrace mark (haptic, sound, plate built, first moving frame,
/// seated, clink), the longest main-thread stall and the face work done. Then taps the same plate
/// again to take it off and records the release. BarbellProgressService runs on the in-memory
/// context with remote sync off for the duration; nothing reaches the account's store or backend.
///
/// Cases (lathe plates): faces already in memory, faces on disk only, faces never drawn. Legacy
/// plates: a tier whose material is loaded, a tier never loaded in this process.
/// TEST_RUNNER_VOLIA_RACK_TAP_TIME=1 enables it; TEST_RUNNER_VOLIA_RACK_OPEN_OUT=<directory> also
/// writes the report there; TEST_RUNNER_VOLIA_RACK_PLATES=legacy measures the Release plates.
@MainActor
@Suite(.serialized)
struct CutRackTapTimeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_TAP_TIME"] == "1"))
    func measureTaps() async throws {
        let inventory = try RackOpenInventory(count: 90, onBar: 1)
        let lathe = RackPlateStyle.current == .lathe
        let tray = inventory.plates.filter { !$0.isRacked }
        let barTier = inventory.plates.first { $0.isRacked }?.tierID ?? 0
        let tag = UUID().uuidString.prefix(6)

        // Three tray plates with weights no other plate has, so each case's faces are its own.
        var cases: [(label: String, plate: EarnedPlate)] = []
        if lathe {
            let memory = tray[10], disk = tray[20], never = tray[30]
            memory.weightKg = 31; disk.weightKg = 32; never.weightKg = 33
            for plate in [memory, disk, never] { plate.engravingText = "Tap \(tag) \(plate.weightKg)" }
            cases = [("memory", memory), ("disk", disk), ("never", never)]
        } else {
            let warm = try #require(tray.first { $0.tierID == barTier })
            // A textured tier (bundle textures) that nothing has loaded in this process.
            let cold = try #require(tray.first { [1, 3].contains($0.tierID) && $0.tierID != barTier })
            cases = [("tier loaded", warm), ("tier new", cold)]
        }
        try inventory.container.mainContext.save()

        let previous = BarbellProgressService.shared.swapContextForTesting(inventory.container.mainContext, remoteSyncOff: true)
        defer { _ = BarbellProgressService.shared.swapContextForTesting(previous, remoteSyncOff: false) }

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        previousWindow?.isHidden = true
        let window = UIWindow(windowScene: scene)
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
        try await Task.sleep(for: .seconds(3))

        if lathe {
            let (memory, disk) = (cases[0].plate, cases[1].plate)
            await prepareLathePlates(latheFirstFrameRequests([memory]) + latheLaterRequests([memory]))
            for request in latheFirstFrameRequests([disk]) + latheLaterRequests([disk]) {
                let tier = try #require(PlateTier.all.first { $0.id == request.tierID })
                let spec = latheFaceSpec(tier: tier, weightKg: request.weightKg, engravingText: request.engravingText,
                                         projection: request.projection, showEngravings: true)
                LatheFaceDiskCache.store(try #require(LatheFaceArt.images(for: spec)), for: spec)
            }
            try await Task.sleep(for: .seconds(1))
        }

        var report = "style=\(RackPlateStyle.current.rawValue) plates=90 onBar=1\n"
        let toggle = try #require(CutRackHost.testToggle)
        for (label, plate) in cases {
            for (action, until) in [("load", "load.clink"), ("release", "release.drop")] {
                let before = RackWorkCounters.snapshot()
                RackOpenTrace.begin("t0")
                let stalls = MainThreadStallMonitor()
                stalls.start()
                let start = CACurrentMediaTime()
                toggle(plate.id)
                while RackOpenTrace.time(of: until) == nil, CACurrentMediaTime() - start < 8 {
                    try await Task.sleep(for: .milliseconds(2))
                }
                // And the save and re-layout after it.
                try await Task.sleep(for: .milliseconds(300))
                stalls.stop()
                let after = RackWorkCounters.snapshot()
                let tap = RackOpenTrace.time(of: "tap") ?? start
                report += "\n[\(label) \(action)]\n"
                report += RackOpenTrace.marks.filter { $0.name != "t0" }
                    .map { String(format: "  %-16@ %7.1f ms", $0.name as NSString, ($0.time - tap) * 1000) }
                    .joined(separator: "\n")
                report += String(format: "\n  longest main stall %.1f ms; stalls over 30 ms: ", stalls.longest * 1000)
                report += stalls.gaps.map { String(format: "%.0f/%.0f", ($0.end - tap) * 1000, $0.length * 1000) }.joined(separator: " ")
                report += "\n  work " + RackWork.allCases.compactMap { kind in
                    let n = (after[kind] ?? 0) - (before[kind] ?? 0)
                    return n == 0 ? nil : "\(kind.rawValue)=\(n)"
                }.joined(separator: " ") + "\n"
                try await Task.sleep(for: .seconds(1.5))
            }
        }
        print(report)
        if let out = ProcessInfo.processInfo.environment["VOLIA_RACK_OPEN_OUT"] {
            let name = "tap-\(RackPlateStyle.current.rawValue)-\(Int(Date().timeIntervalSince1970)).txt"
            try report.write(to: URL(fileURLWithPath: out).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}
