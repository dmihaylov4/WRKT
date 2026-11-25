import Foundation
import QuartzCore
import Testing
@testable import WRKT

/// What Home pays while the hex portal renders its first still: the main thread's stalls from the
/// window appearing until the still is shown, with no still on disk (run on a fresh install for
/// the first render of an install). TEST_RUNNER_VOLIA_HOME_HEX_STILL_STALLS=1;
/// TEST_RUNNER_VOLIA_HOME_HEX_OUT=<directory> also writes the report there.
@MainActor
@Suite(.serialized)
struct HomeHexStillStallTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HOME_HEX_STILL_STALLS"] == "1"))
    func measureFirstStill() async throws {
        var report = "home hex still render (fixture Train view, planned state, no still on disk)\n"
        for run in ["first in process", "second in process"] {
            HexPortalFixture.clearStills()
            let fixture = try HexPortalFixture()
            RackOpenTrace.begin("still.begin")
            let stalls = MainThreadStallMonitor()
            stalls.start()
            let start = CACurrentMediaTime()
            let harness = try HexHarness(fixture: fixture, hero: .planned(name: "Upper Body", exerciseCount: 6))
            try await harness.waitForStill()
            let shown = (CACurrentMediaTime() - start) * 1000
            stalls.stop()
            harness.close()
            let over = stalls.gaps.filter { $0.length > 0.15 }
            let origin = RackOpenTrace.time(of: "still.begin") ?? start
            report += RackOpenTrace.marks.map { String(format: "  %@ %.0f ms\n", $0.name, ($0.time - origin) * 1000) }.joined()
            report += "  stalls (end, length): " + stalls.gaps.filter { $0.length > 0.05 }
                .map { String(format: "%.0f/%.0f", ($0.end - origin) * 1000, $0.length * 1000) }.joined(separator: " ") + "\n"
            report += String(format: "[%@] still shown after %.0f ms, longest main stall %.0f ms, stalls over 150 ms: %d (%@)\n",
                             run, shown, stalls.longest * 1000, over.count,
                             over.map { String(format: "%.0f", $0.length * 1000) }.joined(separator: ", "))
            try await Task.sleep(for: .seconds(1))
        }
        print(report)
        if let out = ProcessInfo.processInfo.environment["VOLIA_HOME_HEX_OUT"] {
            try report.write(to: URL(fileURLWithPath: out).appendingPathComponent("home-still-\(Int(Date().timeIntervalSince1970)).txt"),
                             atomically: true, encoding: .utf8)
        }
    }
}
