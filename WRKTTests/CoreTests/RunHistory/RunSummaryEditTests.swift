import XCTest
@testable import WRKT

/// The per-workout history shows an edit at once from the summary alone: for every run and
/// edit, `RunSummary(run).updated(by: edit)` must equal `RunSummary(edit.applied(to: run))`.
@MainActor
final class RunSummaryEditTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    private static func points(_ count: Int, hr: (Int) -> Double?) -> [RoutePoint] {
        (0..<count).map { RoutePoint(lat: 48 + Double($0) * 0.001, lon: 16, t: start.addingTimeInterval(Double($0)), hr: hr($0)) }
    }

    private static func runs() -> [Run] {
        var result: [Run] = []
        for routeCount in [nil, 0, 1, 5] as [Int?] {
            for withHR in [nil, 0, 3] as [Int?] {
                for samples in [nil, 0, 2] as [Int?] {
                    for splits in [nil, 0, 2] as [Int?] {
                        result.append(Run(id: UUID(), date: start, distanceKm: 4, durationSec: 900, avgHeartRate: 140,
                                          maxHeartRate: withHR == 3 ? nil : 160,
                                          hrSamples: samples.map { n in (0..<n).map { HeartRateSample(timestamp: start, bpm: 100 + Double($0)) } },
                                          route: routeCount.map { n in (0..<n).map { Coordinate(lat: Double($0), lon: 1) } },
                                          routeWithHR: withHR.map { n in points(n) { $0 == 1 ? nil : 130 + Double($0) } },
                                          splits: splits.map { n in (0..<n).map { KilometerSplit(number: $0 + 1, distanceKm: 1, durationSec: 300) } },
                                          workoutType: "Running"))
                    }
                }
            }
        }
        return result
    }

    private static func edits(for id: UUID) -> [RunEdit] {
        let light: (inout RunSummary) -> Void = { $0.workoutName = "x"; $0.distanceKm += 1; $0.maxHeartRate = nil }
        let none: (inout RunSummary) -> Void = { _ in }
        var result: [RunEdit] = [RunEdit(id: id, light: light), RunEdit(id: id, light: none)]
        for route in [nil, .some(nil), .some([Coordinate(lat: 1, lon: 1)]), .some([])] as [[Coordinate]??] {
            for withHR in [nil, .some(nil), .some(points(4) { $0 == 0 ? nil : 150 }), .some([])] as [[RoutePoint]??] {
                for splits in [nil, .some(nil), .some([KilometerSplit(number: 1, distanceKm: 1, durationSec: 1)])] as [[KilometerSplit]??] {
                    for samples in [nil, .some([HeartRateSample(timestamp: start, bpm: 99)])] as [[HeartRateSample]??] {
                        result.append(RunEdit(id: id, light: light, route: route, routeWithHR: withHR, splits: splits, hrSamples: samples))
                    }
                }
            }
        }
        return result
    }

    func testAnEditOnTheSummaryEqualsTheSummaryOfTheEditedRun() {
        var checked = 0
        for run in Self.runs() {
            let summary = RunSummary(run)
            for edit in Self.edits(for: run.id) {
                XCTAssertEqual(summary.updated(by: edit), RunSummary(edit.applied(to: run)))
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10_000)
    }

    func testReplacesDetailIsTrueExactlyWhenAnArrayIsGiven() {
        let id = UUID()
        XCTAssertFalse(RunSummary.replacesDetail(RunEdit(id: id)))
        XCTAssertTrue(RunSummary.replacesDetail(RunEdit(id: id, splits: .some(nil))))
        XCTAssertTrue(RunSummary.replacesDetail(RunEdit(id: id, hrSamples: .some([]))))
    }
}
