import Foundation
import Testing
@testable import WRKT

@MainActor
struct HRZoneCalculatorTests {
    private var calculator: HRZoneCalculator {
        HRZoneCalculator(config: HRZoneConfig(maxHR: 190, restingHR: 60, age: nil,
                                             method: .karvonen, lastUpdated: Date(timeIntervalSince1970: 0)))
    }

    private var extractor: CardioDataExtractor { CardioDataExtractor(hrCalculator: calculator) }

    @Test func belowZoneOneHasNoZone() {
        let lower = calculator.zoneBoundaries()[0].lowerBPM
        #expect(calculator.zone(for: Double(lower) - 0.1) == 0)
        #expect(calculator.zone(for: 0) == 0)
    }

    @Test func eachLowerBoundaryStartsItsZone() {
        for boundary in calculator.zoneBoundaries() {
            #expect(calculator.zone(for: Double(boundary.lowerBPM)) == boundary.zone)
        }
    }

    @Test func eachUpperBoundaryStartsTheNextZoneExceptZoneFive() {
        for boundary in calculator.zoneBoundaries() {
            #expect(calculator.zone(for: Double(boundary.upperBPM)) == min(boundary.zone + 1, 5))
        }
    }

    @Test func insideEachZoneAndAboveZoneFive() {
        for boundary in calculator.zoneBoundaries() {
            let midpoint = Double(boundary.lowerBPM + boundary.upperBPM) / 2
            #expect(calculator.zone(for: midpoint) == boundary.zone)
        }
        #expect(calculator.zone(for: Double(calculator.zoneBoundaries()[4].upperBPM) + 50) == 5)
    }

    @Test func allBelowZoneOneWorkoutHasZeroZoneTime() throws {
        let run = Run(distanceKm: 0, durationSec: 60, avgHeartRate: 68,
                      routeWithHR: points([68, 68, 68, 68, 68, 68]))
        let zones = try #require(extractor.calculateHRZones(from: run))
        #expect(zones.allSatisfy { $0.minutes == 0 })
    }

    @Test func belowZoneOneAverageDoesNotEstimateZoneOneTime() {
        let zones = extractor.calculateEstimatedHRZones(avgHR: 68, totalDuration: 60)
        #expect(zones.allSatisfy { $0.minutes == 0 })
    }

    @Test func belowZoneOneTimeIsNotRedistributedAndActualDataWins() throws {
        let lower = Double(calculator.zoneBoundaries()[0].lowerBPM)
        let run = Run(distanceKm: 0, durationSec: 60, avgHeartRate: lower,
                      routeWithHR: points([68, lower]))
        let zones = try #require(extractor.calculateHRZones(from: run))
        #expect(zones.first { $0.zone == 1 }?.minutes == 0.5)
        #expect(zones.reduce(0) { $0 + $1.minutes } == 0.5)

        let belowRun = Run(distanceKm: 0, durationSec: 60, avgHeartRate: lower,
                           routeWithHR: points([68, 68]))
        let belowZones = try #require(extractor.calculateHRZones(from: belowRun))
        #expect(belowZones.allSatisfy { $0.minutes == 0 })
    }

    @Test func percentMaxBoundariesAlsoLeaveBelowZoneOneUnassigned() {
        let calculator = HRZoneCalculator(config: HRZoneConfig(maxHR: 190, restingHR: nil, age: nil,
                                                              method: .defaultMax, lastUpdated: .distantPast))
        #expect(calculator.zone(for: 68) == 0)
        for boundary in calculator.zoneBoundaries() {
            #expect(calculator.zone(for: Double(boundary.lowerBPM)) == boundary.zone)
            #expect(calculator.zone(for: Double(boundary.upperBPM)) == min(boundary.zone + 1, 5))
            #expect(calculator.zone(for: Double(boundary.lowerBPM + boundary.upperBPM) / 2) == boundary.zone)
        }
        #expect(calculator.zone(for: 240) == 5)
    }

    @Test func allBelowZoneOneStrengthSamplesHaveZeroZoneTime() throws {
        let samples = (0...6).map {
            HeartRateSample(timestamp: Date(timeIntervalSince1970: Double($0) * 10), bpm: 68)
        }
        #expect(calculator.zoneDurations(for: samples).isEmpty)
        let run = Run(distanceKm: 0, durationSec: 60, avgHeartRate: 140, hrSamples: samples)
        let zones = try #require(extractor.calculateHRZones(from: run))
        #expect(zones.allSatisfy { $0.minutes == 0 })
    }

    @Test func sampledIntervalsExcludeBelowZoneOneWithoutRedistribution() {
        let values: [Double] = [68, 125, 138, 300]
        let samples = values.enumerated().map { index, bpm in
            HeartRateSample(timestamp: Date(timeIntervalSince1970: Double(index) * 20), bpm: bpm)
        }
        let durations = calculator.zoneDurations(for: samples)
        #expect(durations[0] == nil)
        #expect(durations[1] == 20)
        #expect(durations[2] == 20)
        #expect(durations.values.reduce(0, +) == 40)
        #expect(extractor.calculateHRZones(from: samples).reduce(0) { $0 + $1.minutes } == 40.0 / 60)
    }

    @Test func sampledIntervalsKeepExistingGapCapAndHandleEmptyInput() {
        let samples = [HeartRateSample(timestamp: .distantPast, bpm: 300),
                       HeartRateSample(timestamp: .distantPast.addingTimeInterval(120), bpm: 300)]
        #expect(calculator.zoneDurations(for: samples)[5] == 60)
        #expect(calculator.zoneDurations(for: []).isEmpty)
        #expect(calculator.zoneDurations(for: Array(samples.prefix(1))).isEmpty)
    }

    private func points(_ values: [Double]) -> [RoutePoint] {
        values.enumerated().map { index, hr in
            RoutePoint(lat: 0, lon: 0, t: Date(timeIntervalSince1970: Double(index) * 10), hr: hr)
        }
    }

    // MARK: Config building

    @Test func ageChangeKeepsRestingHeartRateAndKarvonen() {
        let now = Date(timeIntervalSince1970: 0)
        let before = HRZoneCalculator.config(age: 30, restingHR: 58, now: now)
        // The age changes; the resting heart rate already known is passed back in.
        let after = HRZoneCalculator.config(age: 31, restingHR: before.restingHR, now: now)
        #expect(after.restingHR == 58)
        #expect(after.method == .karvonen)
        #expect(after.age == 31)
        #expect(abs(after.maxHR - (208.0 - 0.7 * 31)) < 0.0001)
    }

    @Test func configMethodFollowsWhatIsKnown() {
        let now = Date(timeIntervalSince1970: 0)
        let ageOnly = HRZoneCalculator.config(age: 40, restingHR: nil, now: now)
        #expect(ageOnly.method == .ageBased)
        #expect(ageOnly.restingHR == nil)
        let nothing = HRZoneCalculator.config(age: nil, restingHR: nil, now: now)
        #expect(nothing.method == .defaultMax)
        #expect(nothing.maxHR == 190)
        let restingOnly = HRZoneCalculator.config(age: nil, restingHR: 60, now: now)
        #expect(restingOnly.method == .karvonen)
        #expect(restingOnly.maxHR == 190)
    }

    @Test func ageOutOfRangeCountsAsNotSet() {
        let now = Date(timeIntervalSince1970: 0)
        for age in [0, -5, 120, 400] {
            let config = HRZoneCalculator.config(age: age, restingHR: nil, now: now)
            #expect(config.age == nil)
            #expect(config.maxHR == 190)
            #expect(config.method == .defaultMax)
        }
    }
}
