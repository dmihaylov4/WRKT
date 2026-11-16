import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutExerciseStatsLogicTests {
    private typealias F = CutStatsFixtures

    private func model(_ stats: ExerciseStatistics = F.bench, unit: WeightUnit = .kg) -> CutExerciseStatsModel {
        CutExerciseStatsLogic.model(stats, unit: unit, now: F.now, calendar: F.calendar, locale: F.locale)
    }

    // MARK: Records

    @Test func threeRecordsForAWeightedLift() {
        let records = model().records
        #expect(records.map(\.label) == ["Heaviest", "Best 1RM", "Most reps"])
        #expect(records.map(\.value) == ["90 kg", "105 kg", "12"])
        #expect(records.map(\.line) == ["x 5, 11 Nov", "estimated", "at 60 kg"])
        #expect(records[0].accessibilityLabel == "Heaviest, 90 kilograms for 5 reps on 11 Nov")
    }

    @Test func recordsInPounds() {
        let records = model(unit: .lb).records
        #expect(records.map(\.value) == ["198.4 lb", "231.5 lb", "12"])
        #expect(records[2].line == "at 132.3 lb")
        #expect(records[1].accessibilityLabel == "Best estimated 1RM, 231.5 pounds")
    }

    @Test func bodyweightRecords() {
        let records = model(F.pullUps).records
        #expect(records.map(\.label) == ["Most reps", "Heaviest"])
        #expect(records[0].value == "27")
        #expect(records[0].line == "in one session")
        #expect(records[1].value == "+10 kg")
        #expect(records[1].line == "x 6, 10 Nov")
    }

    // MARK: Sessions and record detection

    @Test func sessionsNewestFirstWithTheirSummary() {
        let sessions = model().sessions
        #expect(sessions.count == 10)
        #expect(sessions[0].title == "Wednesday 11 Nov")
        #expect(sessions[0].line == "4 sets, top 90 kg x 5")
        #expect(sessions[1].title == "Friday 6 Nov")
        #expect(sessions[1].line == "4 sets, top 87.5 kg x 5")
    }

    @Test func theRowHoldingARecordSaysRecord() {
        let sessions = model().sessions
        // The latest session holds the heaviest set and the best 1RM; the light day holds most reps.
        #expect(sessions[0].isRecord)
        #expect(sessions[0].accessibilityLabel == "Wednesday 11 Nov, 4 sets, top set 90 kilograms for 5 reps, record")
        let lightDay = sessions.first { $0.line == "3 sets, top 60 kg x 12" }
        #expect(lightDay?.isRecord == true)
        #expect(sessions.filter(\.isRecord).count == 2)
    }

    @Test func recordFlagsFollowTheRecordsShown() {
        let stats = F.bench
        let shown = Set(model(stats).records.map(\.workoutID))
        for session in model(stats).sessions {
            #expect(session.isRecord == shown.contains(session.workoutID))
        }
    }

    @Test func sessionsInPounds() {
        #expect(model(unit: .lb).sessions[0].line == "4 sets, top 198.4 lb x 5")
    }

    @Test func olderYearShowsTheYear() {
        let stats = F.statistics([F.workout(daysAgo: 400, sets: [F.set(80, 5)]), F.workout(daysAgo: 3, sets: [F.set(80, 5)])])
        #expect(model(stats).sessions.last?.title == "Thursday 9 Oct 2025")
    }

    // MARK: Chart series

    @Test func weightedSeriesInMockOrder() {
        let model = model()
        #expect(model.series.map(\.title) == ["Weight", "Volume", "1RM"])
        #expect(model.defaultMetric == .weight)
        #expect(model.series.allSatisfy { $0.points.count == 10 })
    }

    @Test func segmentSwitchReadsAPrebuiltSeries() {
        let model = model()
        #expect(model.series(for: .volume)?.metric == .volume)
        #expect(model.series(for: .oneRepMax)?.captionTrailing == "Latest, 105 kg")
        #expect(model.series(for: nil)?.metric == .weight)
    }

    @Test func captionIsStartAndLatest() throws {
        let weight = try #require(model().series(for: .weight))
        // Average weight per session, warm-ups included, as the aggregator computes it.
        #expect(weight.captionLeading == "Aug, 71.2 kg")
        #expect(weight.captionTrailing == "Latest, 82.5 kg")
        let volume = try #require(model().series(for: .volume))
        #expect(volume.captionLeading == "Aug, 1,875 kg")
    }

    @Test func pointsAreNormalised() throws {
        let points = try #require(model().series(for: .oneRepMax)).points
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 1)
        #expect(points.map(\.y).max() == 1)
        #expect(points.map(\.y).min() == 0)
        #expect(points.last?.y == 1)
    }

    @Test func chartLabelStatesTheTrend() throws {
        let label = try #require(model().series(for: .oneRepMax)).accessibilityLabel
        #expect(label == "Best estimated 1RM per session rising from 90 kilograms to 105 kilograms over 3 months")
        #expect(CutExerciseStatsLogic.trend(from: 100, to: 100.5, spoken: { "\(Int($0))" }) == "holding at 100")
        #expect(CutExerciseStatsLogic.trend(from: 100, to: 90, spoken: { "\(Int($0))" }) == "falling from 100 to 90")
    }

    @Test func spanWording() {
        let start = F.daysAgo(10)
        #expect(CutExerciseStatsLogic.spanText(from: start, to: F.daysAgo(5), calendar: F.calendar) == "5 days")
        #expect(CutExerciseStatsLogic.spanText(from: F.daysAgo(30), to: F.now, calendar: F.calendar) == "4 weeks")
        #expect(CutExerciseStatsLogic.spanText(from: F.daysAgo(95), to: F.now, calendar: F.calendar) == "3 months")
        #expect(CutExerciseStatsLogic.spanText(from: F.daysAgo(1), to: F.now, calendar: F.calendar) == "1 day")
    }

    @Test func bodyweightSeriesHaveNoOneRepMax() {
        let model = model(F.pullUps)
        #expect(model.series.map(\.title) == ["Reps per set", "Total reps"])
        #expect(model.series.last?.captionTrailing == "Latest, 15 reps")
    }

    // MARK: Empty states

    @Test func exerciseWithOneSession() {
        let model = model(F.oneSession)
        #expect(model.series.isEmpty)
        #expect(model.chartNote == "Log it once more to see a trend.")
        #expect(model.sessions.count == 1)
        #expect(model.sessions[0].isRecord)
        #expect(model.records.map(\.value) == ["80 kg", "93.3 kg", "10"])
        #expect(model.emptyLine == nil)
    }

    @Test func exerciseNeverLogged() {
        let model = model(F.neverLogged)
        #expect(model.emptyLine == "No sessions logged yet.")
        #expect(model.records.isEmpty)
        #expect(model.series.isEmpty)
        #expect(model.sessions.isEmpty)
        #expect(model.chartNote == nil)
        #expect(model.title == "Bench Press")
    }

    // MARK: Session log

    @Test func sessionLogForARecordSession() throws {
        let stats = F.bench
        let records = model(stats).records
        let entry = try #require(stats.history.allWorkouts.first)
        let log = CutSessionLogLogic.log(entry, exerciseName: "Bench Press", trackingMode: .weighted, records: records,
                                         unit: .kg, now: F.now, calendar: F.calendar, locale: F.locale)
        #expect(log.title == "Bench Press")
        #expect(log.subtitle == "Wednesday 11 Nov, 18:00")
        #expect(log.recordLine == "Record: heaviest, best 1RM")
        #expect(log.stats.map(\.value) == ["4", "24", "1,860"])
        #expect(log.stats.map(\.label) == ["sets", "reps", "kg lifted"])
        #expect(log.sets.map(\.label) == ["Set 1, warm-up", "Set 2", "Set 3", "Set 4"])
        #expect(log.sets.map(\.value) == ["60 kg x 10", "90 kg x 5", "90 kg x 5", "90 kg x 4"])
    }

    @Test func sessionLogInPoundsWithoutRecord() throws {
        let stats = F.bench
        let entry = try #require(stats.history.allWorkouts.dropFirst().first)
        let log = CutSessionLogLogic.log(entry, exerciseName: "Bench Press", trackingMode: .weighted,
                                         records: model(stats).records, unit: .lb, now: F.now,
                                         calendar: F.calendar, locale: F.locale)
        #expect(log.recordLine == nil)
        #expect(log.sets[1].value == "187.4 lb x 6")
        #expect(log.stats.last?.label == "lb lifted")
    }

    // MARK: Formatting

    @Test func durationsDropSecondsFromAnHour() {
        #expect(CutStatsFormat.duration(45) == "0:45")
        #expect(CutStatsFormat.duration(90) == "1:30")
        #expect(CutStatsFormat.duration(3_599) == "59:59")
        #expect(CutStatsFormat.duration(3_900) == "1:05")
        #expect(CutStatsFormat.spokenDuration(90) == "1 minute 30 seconds")
    }

    @Test func timedSessionsUseTheLongestHold() {
        let set = SetPerformance(setNumber: 1, reps: 0, weight: 0, durationSeconds: 75, restAfter: nil, tag: .working,
                                 trackingMode: .timed, isPR: false)
        let summary = CutExerciseStatsLogic.summary([set, set], trackingMode: .timed, unit: .kg, locale: F.locale)
        #expect(summary.shown == "2 sets, longest 1:15")
        #expect(summary.spoken == "2 sets, longest 1 minute 15 seconds")
    }
}
