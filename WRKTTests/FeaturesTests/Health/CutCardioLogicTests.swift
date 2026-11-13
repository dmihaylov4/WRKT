import Foundation
import Testing
@testable import WRKT

/// Shared fixtures for the Cut Cardio logic and capture tests. Dates are relative to `now`.
enum CutCardioFixtures {
    static let locale = Locale(identifier: "en_GB")
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Friday 13 November 2026, 12:00 UTC. Its week runs Monday 9 to Sunday 15 November.
    static let now = Date(timeIntervalSince1970: 1_794_571_200)

    static func day(_ offset: Int, hour: Int = 7) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .hour, value: offset * 24 + hour, to: start)!
    }

    static func run(
        _ name: String? = "Morning Run",
        type: String? = "Running",
        day offset: Int = 0,
        km: Double = 6.2,
        seconds: Int = 2_052,
        heartRate: Double? = 152
    ) -> Run {
        Run(date: day(offset), distanceKm: km, durationSec: seconds, healthKitUUID: UUID(), avgHeartRate: heartRate,
            calories: 412, workoutType: type, workoutName: name)
    }

    /// Three runs this week, two last week, one three weeks ago; walks, a ride and other activities.
    static var runs: [Run] {
        [
            run("Morning Run", day: 0, km: 6.2, seconds: 2_052),
            run("Tempo Run", day: -2, km: 5.0, seconds: 1_490),
            run("Easy Run", day: -4, km: 7.2, seconds: 2_700),
            run("Long Run", day: -8, km: 14.1, seconds: 4_860),
            run(nil, day: -10, km: 4.0, seconds: 1_400),
            run("Hill Repeats", day: -24, km: 8.0, seconds: 2_900),
            run("Evening Walk", type: "Walking", day: -1, km: 3.1, seconds: 2_280),
            run("Commute", type: "Cycling", day: -3, km: 18.6, seconds: 2_760),
            run(nil, type: "Rowing", day: -1, km: 0, seconds: 3_900),
            run("HIIT", type: "High Intensity Interval Training", day: -3, km: 0, seconds: 1_500),
            run("Strength", type: "Traditional Strength Training", day: -2, km: 0, seconds: 3_000)
        ]
    }

    static func tab(
        _ runs: [Run]? = runs,
        type: CardioType = .running,
        week: Int = 0,
        connection: HealthConnectionState = .connected,
        syncing: Bool = false
    ) -> CutCardioTabModel {
        CutCardioLogic.tab(allRuns: runs, type: type, weekOffset: week, connection: connection, isSyncing: syncing,
                           syncProcessed: 12, syncTotal: 46, now: now, calendar: calendar, locale: locale)
    }

    static func splits(_ paces: [Int], lastKm: Double = 0.2) -> [KilometerSplit] {
        paces.enumerated().map { index, pace in
            let isLast = index == paces.count - 1
            let km = isLast ? lastKm : 1.0
            return KilometerSplit(number: index + 1, distanceKm: km, durationSec: Int(Double(pace) * km))
        }
    }

    static func samples(_ bpm: [Double]) -> [HeartRateSample] {
        bpm.enumerated().map { HeartRateSample(timestamp: now.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element) }
    }

    static let zones: [HRZoneSummary] = [
        HRZoneSummary(zone: 1, name: "Light", minutes: 2.67, rangeDisplay: "", colorHex: "#888888"),
        HRZoneSummary(zone: 2, name: "Moderate", minutes: 7.5, rangeDisplay: "", colorHex: "#888888"),
        HRZoneSummary(zone: 3, name: "Aerobic", minutes: 16.33, rangeDisplay: "", colorHex: "#888888"),
        HRZoneSummary(zone: 4, name: "Threshold", minutes: 6.17, rangeDisplay: "", colorHex: "#888888"),
        HRZoneSummary(zone: 5, name: "Max", minutes: 1.53, rangeDisplay: "", colorHex: "#888888")
    ]

    /// A full Health run: route, splits, heart rate, dynamics and a note.
    static var fullRun: Run {
        var run = run("Morning Run", day: 0, km: 6.2, seconds: 2_052)
        run.maxHeartRate = 171
        run.minHeartRate = 118
        run.route = (0..<20).map { Coordinate(lat: 42.69 + Double($0) * 0.001, lon: 23.32) }
        run.splits = splits([342, 328, 319, 333, 324, 306], lastKm: 0.2)
        run.avgCadence = 168
        run.avgRunningPower = 245
        run.avgStrideLength = 1.12
        run.notes = "New shoes. Felt easy until the last hill."
        return run
    }

    static func detail(_ run: Run = fullRun, zones: [HRZoneSummary] = zones, samples: [HeartRateSample]? = nil) -> CutCardioDetailModel {
        CutCardioLogic.detail(run, zones: zones,
                              hrSamples: samples ?? Self.samples([118, 130, 138, 142, 148, 150, 151, 155, 160, 158, 152, 149, 165, 171, 150, 140]),
                              now: now, calendar: calendar, locale: locale)
    }
}

struct CutCardioLogicTests {
    private typealias F = CutCardioFixtures

    // MARK: Filtering and weeks

    @Test func filtersByTypeAsTheLegacyTab() {
        let untyped = Run(distanceKm: 3, durationSec: 900)
        let tiny = Run(distanceKm: 0.05, durationSec: 60)
        #expect(CutCardioLogic.matches(untyped, type: .running))
        #expect(!CutCardioLogic.matches(tiny, type: .running))
        #expect(CutCardioLogic.runs(F.runs, type: .running).count == 6)
        #expect(CutCardioLogic.runs(F.runs, type: .walking).count == 1)
        #expect(CutCardioLogic.runs(F.runs, type: .cycling).count == 1)
        // Rowing and HIIT count as Other; strength training does not.
        #expect(CutCardioLogic.runs(F.runs, type: .other).count == 2)
    }

    @Test func weeksStartOnMondayWhateverTheLocaleCalendar() {
        var sundayFirst = F.calendar
        sundayFirst.firstWeekday = 1
        let sunday = F.day(2) // Sunday 15 November
        let monday = F.calendar.date(byAdding: .day, value: -4, to: F.calendar.startOfDay(for: F.now))!
        #expect(CutCardioLogic.weekStart(of: sunday, calendar: sundayFirst) == monday)
        #expect(CutCardioLogic.weekStart(of: F.now, calendar: F.calendar) == monday)
    }

    @Test func weekLabels() {
        #expect(CutCardioLogic.weekLabel(offset: 0, now: F.now, calendar: F.calendar, locale: F.locale) == "This week")
        #expect(CutCardioLogic.weekLabel(offset: 1, now: F.now, calendar: F.calendar, locale: F.locale) == "Last week")
        #expect(CutCardioLogic.weekLabel(offset: 2, now: F.now, calendar: F.calendar, locale: F.locale) == "26 Oct to 1 Nov")
        #expect(CutCardioLogic.weekLabel(offset: 3, now: F.now, calendar: F.calendar, locale: F.locale) == "19 to 25 Oct")
    }

    @Test func weekOffsetIsClampedToHistory() {
        let running = CutCardioLogic.runs(F.runs, type: .running)
        #expect(CutCardioLogic.maxWeekOffset(running, now: F.now, calendar: F.calendar) == 3)
        #expect(CutCardioLogic.clampedOffset(9, runs: running, now: F.now, calendar: F.calendar) == 3)
        #expect(CutCardioLogic.clampedOffset(-1, runs: running, now: F.now, calendar: F.calendar) == 0)
        #expect(CutCardioLogic.maxWeekOffset([], now: F.now, calendar: F.calendar) == 0)
    }

    // MARK: Formats

    @Test func durationsDropSecondsFromOneHour() {
        #expect(CutCardioLogic.duration(2_052) == "34:12")
        #expect(CutCardioLogic.duration(59) == "0:59")
        #expect(CutCardioLogic.duration(3_600) == "1:00")
        #expect(CutCardioLogic.duration(6_125) == "1:42")
        #expect(CutCardioLogic.duration(-5) == "0:00")
    }

    @Test func paceAndSpeed() {
        #expect(CutCardioLogic.pace(331.6) == "5:32")
        #expect(CutCardioLogic.pace(0) == "--")
        #expect(CutCardioLogic.pace(.infinity) == "--")
        #expect(CutCardioLogic.speed(150) == "24.0")
    }

    // MARK: Tab

    @Test func runningWeek() throws {
        let model = F.tab()
        guard case .week(let week) = model.content else { Issue.record("expected a week"); return }
        #expect(week.label == "This week")
        #expect(week.hero == CutCardioHero(value: "18.4", unit: "km"))
        #expect(week.stats.map(\.label) == ["Time", "Avg /km", "Runs"])
        #expect(week.stats.map(\.value) == ["1:44", "5:35", "3"])
        #expect(week.canGoOlder)
        #expect(!week.canGoNewer)
        #expect(week.rows.map(\.title) == ["Morning Run", "Tempo Run", "Easy Run"])
        #expect(week.rows[0].line == "Today, 34:12")
        #expect(week.rows[0].value == "6.2 km")
        #expect(week.rows[1].line == "Wednesday, 24:50")
        #expect(week.summary.map(\.label) == ["Week streak", "Best /km"])
        #expect(week.summary.map(\.value) == ["2", "4:58"])
        #expect(!model.showsConnectRow)
        #expect(model.canSync)
    }

    @Test func dayBarsMarkToday() {
        guard case .week(let week) = F.tab().content else { Issue.record("expected a week"); return }
        #expect(week.bars.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(week.bars.filter(\.isToday).map(\.id) == [4])
        #expect(week.bars[0].fraction == 1)
        #expect(week.bars[1].fraction == 0)
        #expect(abs(week.bars[4].fraction - 6.2 / 7.2) < 0.0001)
        guard case .week(let last) = F.tab(week: 1).content else { Issue.record("expected a week"); return }
        #expect(last.bars.allSatisfy { !$0.isToday })
    }

    @Test func pastWeekWithoutSessions() {
        guard case .week(let week) = F.tab(week: 2).content else { Issue.record("expected a week"); return }
        #expect(week.rows.isEmpty)
        #expect(week.emptyLine == "No runs this week.")
        #expect(week.hero.value == "0.0")
        #expect(week.stats.map(\.value) == ["0:00", "--", "0"])
        #expect(week.canGoNewer && week.canGoOlder)
    }

    @Test func otherShowsTimeAsTheHero() {
        guard case .week(let week) = F.tab(type: .other).content else { Issue.record("expected a week"); return }
        #expect(week.hero == CutCardioHero(value: "1:30", unit: "h"))
        #expect(week.stats.map(\.label) == ["Activities", "Average", "Longest"])
        #expect(week.stats.map(\.value) == ["2", "45:00", "1:05"])
        #expect(week.rows.first?.title == "Rowing")
        #expect(week.rows.first?.value == "1:05")
        #expect(week.summary.map(\.label) == ["Week streak", "All time"])
        #expect(CutCardioLogic.weekHero([F.run(seconds: 2_520)], type: .other) == CutCardioHero(value: "42", unit: "min"))
    }

    @Test func cyclingShowsSpeed() {
        guard case .week(let week) = F.tab(type: .cycling).content else { Issue.record("expected a week"); return }
        #expect(week.stats.map(\.label) == ["Time", "Avg km/h", "Rides"])
        #expect(week.stats[1].value == "24.3")
        #expect(week.summary[1].label == "Best km/h")
    }

    @Test func streakNeedsThisWeekAndOneKilometre() {
        let running = CutCardioLogic.runs(F.runs, type: .running)
        #expect(CutCardioLogic.streakWeeks(running, type: .running, now: F.now, calendar: F.calendar) == 2)
        let short = [F.run(day: 0, km: 0.8), F.run(day: -7, km: 5)]
        #expect(CutCardioLogic.streakWeeks(short, type: .running, now: F.now, calendar: F.calendar) == 0)
    }

    @Test func loadingEmptyAndHealthStates() {
        #expect(F.tab(nil).content == .loading)

        let off = F.tab([], connection: .disconnected)
        #expect(off.content == .empty(CutCardioMessage(title: "Connect Apple Health",
                                                      line: "VOLIA reads your runs, walks and rides from Apple Health.",
                                                      showsConnect: true)))
        #expect(!off.canSync)

        let none = F.tab([], connection: .connected)
        guard case .empty(let message) = none.content else { Issue.record("expected empty"); return }
        #expect(message.title == "No runs yet")
        #expect(!message.showsConnect)

        let limited = F.tab(connection: .limited)
        #expect(limited.showsConnectRow)
        #expect(!limited.canSync)
    }

    @Test func syncLine() {
        #expect(F.tab(syncing: true).sync == CutCardioSync(title: "Syncing 12 of 46", percent: "26%"))
        #expect(CutCardioLogic.syncLine(processed: 0, total: 0) == CutCardioSync(title: "Syncing with Apple Health"))
        #expect(F.tab().sync == nil)
    }

    @Test func rowTitlesAndDays() {
        #expect(CutCardioLogic.title(F.run(nil)) == "Running")
        #expect(CutCardioLogic.title(F.run("  ", type: nil)) == "Run")
        #expect(CutCardioLogic.dayLabel(F.day(-1), now: F.now, calendar: F.calendar, locale: F.locale) == "Yesterday")
        #expect(CutCardioLogic.dayLabel(F.day(-6), now: F.now, calendar: F.calendar, locale: F.locale) == "Saturday")
        #expect(CutCardioLogic.dayLabel(F.day(-8), now: F.now, calendar: F.calendar, locale: F.locale) == "5 Nov")
        #expect(CutCardioLogic.dayLabel(F.day(-400), now: F.now, calendar: F.calendar, locale: F.locale) == "9 Oct 2025")
    }

    // MARK: Detail

    @Test func detailHeaderAndStats() {
        let model = F.detail()
        #expect(model.title == "Morning Run")
        #expect(model.dateLine == "Friday 13 Nov, 07:00")
        #expect(model.hero == CutCardioHero(value: "6.20", unit: "km"))
        #expect(model.stats == [CutStatColumn(value: "34:12", label: "Duration"),
                                CutStatColumn(value: "5:31", label: "Avg /km"),
                                CutStatColumn(value: "152", label: "Avg bpm")])
        #expect(model.route == .map)
        #expect(model.deleteTitle == "Morning Run, 6.2 km")
        #expect(model.notes == "New shoes. Felt easy until the last hill.")
    }

    @Test func detailSplitsMarkTheFastest() {
        let splits = F.detail().splits
        #expect(splits.map(\.label) == ["1", "2", "3", "4", "5", "5.2"])
        #expect(splits.filter(\.isFastest).map(\.id) == [6])
        #expect(splits.first { $0.isFastest }?.fraction == 1)
        #expect(splits[0].pace == "5:42")
        #expect(CutCardioLogic.splitRows([]).isEmpty)
    }

    @Test func detailHeartRate() throws {
        let heart = try #require(F.detail().heartRate)
        #expect(heart.stats.map(\.value) == ["152", "171", "118"])
        #expect(heart.bars.count == 16)
        #expect(abs((heart.bars.min() ?? 0) - 0.15) < 0.000_001)
        #expect(abs((heart.bars.max() ?? 0) - 1) < 0.000_001)
        #expect(heart.zones.map(\.label) == ["Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5"])
        #expect(heart.zones[2].time == "16:20")
        #expect(!heart.isEstimated)
        #expect(CutCardioLogic.heartRateBars(F.samples([140, 140, 140])) == [1, 1, 1])
        #expect(CutCardioLogic.heartRateBars(F.samples([140, 150])).isEmpty)
    }

    @Test func detailPerformanceInPairs() {
        let rows = F.detail().performance
        #expect(rows.map { $0.map(\.label) } == [["Energy", "Avg speed"], ["Energy per km", "Power"], ["Cadence", "Stride"]])
        #expect(rows[0][1].value == "10.9")
        #expect(rows[0][1].unit == "km/h")
    }

    @Test func detailWithoutRouteOrSplitsOffersToLoad() {
        var run = F.run("Lunch Run", day: -1, km: 5, seconds: 1_600, heartRate: nil)
        run.calories = nil
        let model = CutCardioLogic.detail(run, zones: [], hrSamples: nil, now: F.now, calendar: F.calendar, locale: F.locale)
        #expect(model.route == .canFetch)
        #expect(model.canLoadSplits)
        #expect(model.canLoadDetails)
        #expect(model.heartRate == nil)
        #expect(model.stats.map(\.label) == ["Duration", "Avg /km"])

        var manual = run
        manual.healthKitUUID = nil
        let local = CutCardioLogic.detail(manual, zones: [], hrSamples: nil, now: F.now, calendar: F.calendar, locale: F.locale)
        #expect(local.route == .none)
        #expect(!local.canLoadSplits && !local.canLoadDetails)
    }

    @Test func detailWithoutDistanceShowsTime() {
        let rowing = F.run(nil, type: "Rowing", day: -1, km: 0, seconds: 3_900)
        let model = CutCardioLogic.detail(rowing, zones: [], hrSamples: nil, now: F.now, calendar: F.calendar, locale: F.locale)
        #expect(model.hero == CutCardioHero(value: "1:05", unit: "h"))
        let hiit = F.run("HIIT", type: "High Intensity Interval Training", day: -1, km: 0, seconds: 1_500)
        let short = CutCardioLogic.detail(hiit, zones: [], hrSamples: nil, now: F.now, calendar: F.calendar, locale: F.locale)
        #expect(short.hero == CutCardioHero(value: "25:00", unit: "min"))
        #expect(model.stats.map(\.label) == ["kcal", "Avg bpm"])
        #expect(!model.canLoadSplits)
        #expect(model.deleteTitle == "Rowing")
        #expect(model.performance.flatMap { $0 }.map(\.label).contains("Energy") == false)
    }

    @Test func estimatedZonesAreFlagged() throws {
        let estimated = [HRZoneSummary(zone: 2, name: "Moderate", minutes: 30, rangeDisplay: "", colorHex: "#888888", isEstimated: true)]
        let heart = try #require(F.detail(zones: estimated).heartRate)
        #expect(heart.isEstimated)
    }
}
