import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// The rack open-time harness: hosts the real CutRackHost over an in-memory container holding a
/// realistic inventory (90 earned plates of mixed tiers, 4 on the bar) and records, per open, the
/// time from "window shown" to each RackOpenTrace mark up to the scene's first frame, the longest
/// main-thread stall, the process CPU time spent and the RackWork counts. Opens twice: cold (first
/// open in the process) and warm. Nothing is written to the account's store.
/// TEST_RUNNER_VOLIA_RACK_OPEN_TIME=1 enables it; TEST_RUNNER_VOLIA_RACK_OPEN_OUT=<directory> also
/// writes the report there; TEST_RUNNER_VOLIA_RACK_PLATES=legacy measures the Release plates;
/// TEST_RUNNER_VOLIA_RACK_OPEN_THUMBS=cold empties the tray's thumbnail cache first;
/// TEST_RUNNER_VOLIA_RACK_OPEN_PREWARM=1 runs the Me tab's studio prewarm 3 s before the cold open.
@MainActor
@Suite(.serialized)
struct CutRackOpenTimeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_OPEN_TIME"] == "1"))
    func measureOpens() async throws {
        let inventory = try RackOpenInventory()
        if ProcessInfo.processInfo.environment["VOLIA_RACK_OPEN_PREWARM"] == "1" {
            // What the Me tab does when it appears, a few seconds before "Your barbell" is tapped.
            prewarmRackStudioPanorama()
            try await Task.sleep(for: .seconds(3))
        }
        if let delay = Double(ProcessInfo.processInfo.environment["VOLIA_RACK_OPEN_DELAY"] ?? "") {
            // Time to attach a profiler before the cold open.
            try await Task.sleep(for: .seconds(delay))
        }
        if ProcessInfo.processInfo.environment["VOLIA_RACK_OPEN_THUMBS"] == "cold" {
            // The simulator test host's own thumbnail cache, so the tray renders its plates again.
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("plate_snapshots", isDirectory: true)
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }
        var report = "style=\(RackPlateStyle.current.rawValue) plates=\(inventory.plates.count) onBar=\(inventory.plates.filter(\.isRacked).count)\n"
        for label in ["cold", "warm"] {
            let result = try await RackOpenMeasurement.open(container: inventory.container)
            report += "\n[\(label)]\n" + result.description
            try await Task.sleep(for: .seconds(1))
        }
        print(report)
        if let out = ProcessInfo.processInfo.environment["VOLIA_RACK_OPEN_OUT"] {
            let name = "open-\(RackPlateStyle.current.rawValue)-\(Int(Date().timeIntervalSince1970)).txt"
            try report.write(to: URL(fileURLWithPath: out).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}

/// 90 plates over every earnable tier, a mix of weights, engravings and progression tiers, the
/// first four on the bar. In memory only.
@MainActor
struct RackOpenInventory {
    let container: ModelContainer
    let plates: [EarnedPlate]

    init(count: Int = 90, onBar: Int = 4) throws {
        container = try ModelContainer(for: EarnedPlate.self, BarbellConfig.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let tiers = PlateTier.all.map(\.id).filter { $0 != 7 }
        let weights: [Double] = [2.5, 5, 10, 15, 20, 25, 45]
        let engravings = ["", "", "", "75 Workouts", "Bench 100", "", "Squat 140", "", "10 Day Streak"]
        let progression = BarbellPlateProgressionTier.allCases
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        var made: [EarnedPlate] = []
        for index in 0..<count {
            let plate = EarnedPlate(id: "open-\(index)", tierID: tiers[index % tiers.count],
                                    weightKg: weights[(index * 3) % weights.count],
                                    engravingText: engravings[index % engravings.count],
                                    earnedAt: day.addingTimeInterval(Double(index) * 86_400), earnedByEvent: "fixture",
                                    isRacked: index < onBar, rackPosition: index < onBar ? index : nil, liftTypeID: nil,
                                    currentTier: progression[index % progression.count],
                                    workoutsUsedCount: index % 17, prCount: index % 3)
            plate.displayOrder = count - index
            container.mainContext.insert(plate)
            made.append(plate)
        }
        try container.mainContext.save()
        plates = made
    }
}

/// One open of the real rack host in its own window.
@MainActor
enum RackOpenMeasurement {
    struct Result: CustomStringConvertible {
        var marks: [(String, Double)]
        var firstFrameMs: Double?
        var longestStallMs: Double
        var longestStallAfterFrameMs: Double
        var cpuMs: Double
        var work: [RackWork: Int]
        var stalls: [(atMs: Double, ms: Double)]

        var description: String {
            var text = marks.map { String(format: "  %-18@ %8.1f ms", $0.0 as NSString, $0.1) }.joined(separator: "\n")
            text += String(format: "\n  first frame        %8.1f ms\n  longest main stall %8.1f ms (to first frame), %.1f ms (2 s after)\n  process CPU        %8.1f ms\n",
                           firstFrameMs ?? -1, longestStallMs, longestStallAfterFrameMs, cpuMs)
            text += "  stalls over 30 ms (ends at, length): " + stalls.map { String(format: "%.0f/%.0f", $0.atMs, $0.ms) }.joined(separator: " ") + "\n"
            text += "  work " + RackWork.allCases.map { "\($0.rawValue)=\(work[$0] ?? 0)" }.joined(separator: " ") + "\n"
            return text
        }
    }

    static func open(container: ModelContainer, timeout: Double = 90) async throws -> Result {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: CutRackHost().modelContainer(container).preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        let before = RackWorkCounters.snapshot()
        let stalls = MainThreadStallMonitor()
        let cpuStart = processCPUTime()
        RackOpenTrace.begin("open")
        let start = CACurrentMediaTime()
        stalls.start()
        window.makeKeyAndVisible()
        var frame: CFTimeInterval?
        while frame == nil, CACurrentMediaTime() - start < timeout {
            try await Task.sleep(for: .milliseconds(2))
            if let host = RackOpenTrace.time(of: "host.preload"), host >= start,
               let time = RackOpenTrace.time(of: "firstFrame"), time >= start {
                frame = time
            }
        }
        let cpu = (processCPUTime() - cpuStart) * 1000
        let stallToFrame = stalls.longest
        stalls.resetLongest()
        try await Task.sleep(for: .seconds(2))
        let stallAfter = stalls.longest
        stalls.stop()
        let after = RackWorkCounters.snapshot()
        var work: [RackWork: Int] = [:]
        for kind in RackWork.allCases { work[kind] = (after[kind] ?? 0) - (before[kind] ?? 0) }
        return Result(
            marks: RackOpenTrace.marks.map { ($0.name, ($0.time - start) * 1000) },
            firstFrameMs: frame.map { ($0 - start) * 1000 },
            longestStallMs: stallToFrame * 1000,
            longestStallAfterFrameMs: stallAfter * 1000,
            cpuMs: cpu,
            work: work,
            stalls: stalls.gaps.map { (($0.end - start) * 1000, $0.length * 1000) }
        )
    }

    /// User plus system CPU time of every thread in the process, in seconds.
    static func processCPUTime() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
}

/// The longest gap between main run loop timer fires (4 ms period, common modes).
@MainActor
final class MainThreadStallMonitor {
    private var timer: Timer?
    private var last: CFTimeInterval = 0
    private(set) var longest: CFTimeInterval = 0
    /// Every gap over 30 ms: when it ended and how long it was.
    private(set) var gaps: [(end: CFTimeInterval, length: CFTimeInterval)] = []

    func start() {
        last = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.004, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        longest = max(longest, now - last)
        if now - last > 0.030 { gaps.append((now, now - last)) }
        last = now
    }

    func resetLongest() {
        last = CACurrentMediaTime()
        longest = 0
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
