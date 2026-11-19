import XCTest
@testable import WRKT

/// A run summary carries the run's light fields unchanged, and each fact about the detail arrays
/// equals what today's helpers compute from the arrays themselves, for every combination of
/// absent, empty, single-point and populated arrays.
@MainActor
final class RunSummaryFactTests: XCTestCase {
    private static let start = Date(timeIntervalSinceReferenceDate: 785_000_000)

    private static func points(_ heartRates: [Double?]) -> [RoutePoint] {
        heartRates.enumerated().map { i, hr in
            RoutePoint(lat: 48.2 + Double(i) * 0.001, lon: 16.3, t: start.addingTimeInterval(Double(i) * 5), hr: hr)
        }
    }

    private static let routes: [[Coordinate]?] = [
        nil, [], [Coordinate(lat: 48.2, lon: 16.3)],
        [Coordinate(lat: 48.2, lon: 16.3), Coordinate(lat: 48.21, lon: 16.3), Coordinate(lat: 48.22, lon: 16.3)]
    ]
    private static let routesWithHR: [[RoutePoint]?] = [
        nil, [], points([150]), points([140, 152, 147]), points([nil, nil, nil]),
        points([nil, 0, 131.5, nil]), points([-0.0, 0])
    ]
    private static let sampleSets: [[HeartRateSample]?] = [
        nil, [], [HeartRateSample(timestamp: start, bpm: 120), HeartRateSample(timestamp: start.addingTimeInterval(5), bpm: 125)]
    ]
    private static let splitSets: [[KilometerSplit]?] = [
        nil, [], [KilometerSplit(number: 1, distanceKm: 1, durationSec: 330), KilometerSplit(number: 2, distanceKm: 0.4, durationSec: 140)]
    ]

    /// Scalar variants: type, distance, duration, Health id, stored heart rate, dynamics.
    private static let scalars: [(type: String?, km: Double, sec: Int, hk: Bool, avg: Double?, max: Double?, min: Double?, cadence: Double?)] = [
        ("Running", 5.2, 1800, true, nil, nil, nil, nil),
        ("Running", 5.2, 1800, true, 151, nil, nil, 172),
        ("Walking", 2.1, 1500, true, 0, 0, 0, nil),
        ("Cycling", 0, 0, true, nil, 160, 90, nil),
        ("Indoor Run", 3, 900, false, nil, nil, nil, nil),
        ("Traditional Strength Training", 0, 2700, true, 118, 151, 72, nil),
        ("High Intensity Interval Training", 0, 1200, true, nil, nil, nil, nil),
        ("Elliptical", 0, 1200, true, nil, nil, nil, nil),
        ("Yoga", 0, 1800, true, nil, nil, nil, nil),
        (nil, 0, 600, true, nil, nil, nil, nil),
        (nil, 4, 600, false, nil, nil, nil, nil)
    ]

    static var allCases: [Run] {
        var runs: [Run] = []
        for scalar in scalars {
            for route in routes {
                for routeWithHR in routesWithHR {
                    for samples in sampleSets {
                        for splits in splitSets {
                            runs.append(Run(
                                date: start, distanceKm: scalar.km, durationSec: scalar.sec, notes: "n",
                                healthKitUUID: scalar.hk ? UUID() : nil, avgHeartRate: scalar.avg,
                                maxHeartRate: scalar.max, minHeartRate: scalar.min, hrSamples: samples,
                                calories: 321.5, route: route, routeWithHR: routeWithHR, splits: splits,
                                workoutType: scalar.type, workoutName: "Morning", avgCadence: scalar.cadence))
                        }
                    }
                }
            }
        }
        return runs
    }

    func testEveryFactMatchesTodaysHelpersForEveryCombination() {
        let runs = Self.allCases
        XCTAssertEqual(runs.count, 11 * 4 * 7 * 3 * 3)
        for run in runs {
            let differences = LegacyRunHelpers.differences(RunSummary(run), from: run)
            XCTAssertTrue(differences.isEmpty, "\(differences) for \(run)")
        }
    }

    /// Empty arrays are not missing arrays: the legacy splits tab and the auto-post fetch test
    /// `splits == nil`, and an empty `routeWithHR` is stored by the route queue.
    func testEmptyIsNotAbsent() {
        let id = UUID()
        let empty = Run(id: id, date: Self.start, distanceKm: 3, durationSec: 900, route: [], routeWithHR: [], splits: [])
        let absent = Run(id: id, date: Self.start, distanceKm: 3, durationSec: 900)
        let emptySummary = RunSummary(empty)
        let absentSummary = RunSummary(absent)
        XCTAssertEqual(emptySummary.splitCount, 0)
        XCTAssertNil(absentSummary.splitCount)
        XCTAssertFalse(emptySummary.splitsAbsent)
        XCTAssertTrue(absentSummary.splitsAbsent)
        XCTAssertEqual(emptySummary.routeWithHRPointCount, 0)
        XCTAssertNil(absentSummary.routeWithHRPointCount)
        XCTAssertNotEqual(emptySummary, absentSummary)
    }

    /// The route's heart rate stands in for a missing stored max and min, exactly as
    /// `toCompletedWorkout` does: the 32 of the owner's runs in that state post these values.
    func testRouteHeartRateFillsMissingMaxAndMin() {
        let run = Run(distanceKm: 5, durationSec: 1500, routeWithHR: Self.points([nil, 151, 139, 163, nil]),
                      workoutType: "Running")
        let summary = RunSummary(run)
        XCTAssertEqual(summary.effectiveMaxHeartRate, 163)
        XCTAssertEqual(summary.effectiveMinHeartRate, 139)
        XCTAssertNil(summary.maxHeartRate)
        let stored = Run(distanceKm: 5, durationSec: 1500, maxHeartRate: 170, minHeartRate: 120,
                         routeWithHR: Self.points([151, 139]), workoutType: "Running")
        XCTAssertEqual(RunSummary(stored).effectiveMaxHeartRate, 170)
        XCTAssertEqual(RunSummary(stored).effectiveMinHeartRate, 120)
    }

    func testSummaryOfASummaryRunIsStable() {
        for run in Self.allCases.prefix(200) {
            XCTAssertEqual(run.summary, RunSummary(run))
        }
    }

    // MARK: - Coding

    /// The keys are part of a format a later version may store: pinned here.
    func testEncodedKeysArePinned() throws {
        let run = Run(id: UUID(uuidString: "6F0C2A9E-5D7B-4C1A-9F3E-2B8D4E6A1C70")!,
                      date: Date(timeIntervalSince1970: 1_763_000_000), distanceKm: 5.25, durationSec: 1800,
                      notes: "Easy", healthKitUUID: UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!,
                      avgHeartRate: 150, maxHeartRate: nil, minHeartRate: nil,
                      hrSamples: [HeartRateSample(timestamp: Date(timeIntervalSince1970: 1_763_000_000), bpm: 120)],
                      calories: 400, route: nil, routeWithHR: Self.points([140, nil, 160]),
                      splits: [], workoutType: "Running", workoutName: "Morning Run", avgRunningPower: 250,
                      avgCadence: 170, avgStrideLength: 1.1, avgGroundContactTime: 240, avgVerticalOscillation: 8.5)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(RunSummary(run)), as: UTF8.self)
        XCTAssertEqual(json, """
        {"avgCadence":170,"avgGroundContactTime":240,"avgHeartRate":150,"avgRunningPower":250,"avgStrideLength":1.1,\
        "avgVerticalOscillation":8.5,"calories":400,"date":"2025-11-13T02:13:20Z","distanceKm":5.25,"durationSec":1800,\
        "healthKitUUID":"0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D","heartRateSampleCount":1,\
        "id":"6F0C2A9E-5D7B-4C1A-9F3E-2B8D4E6A1C70","notes":"Easy","routeHasHeartRate":true,"routeMaxHeartRate":160,\
        "routeMinHeartRate":140,"routeWithHRPointCount":3,"splitCount":0,"workoutName":"Morning Run","workoutType":"Running"}
        """)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(RunSummary.self, from: Data(json.utf8)), RunSummary(run))
    }
}
