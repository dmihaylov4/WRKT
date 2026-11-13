//
//  CutCardioModel.swift
//  WRKT
//
//  The Cardio tab and the cardio workout detail in the Cut language as plain values. Every
//  format and decision is a pure function of the runs the host reads from WorkoutStoreV2 and
//  of the Health connection, so each state can be tested and rendered without HealthKit.
//

import Foundation

// MARK: - Tab model

struct CutCardioTabModel: Equatable {
    enum Content: Equatable {
        /// The workout store has not loaded yet.
        case loading
        /// Nothing of the selected type at all.
        case empty(CutCardioMessage)
        case week(CutCardioWeek)
    }

    var type: CardioType
    var content: Content
    /// Health access is missing while there is data to show: one row offers to connect.
    var showsConnectRow = false
    /// Shown while a Health sync runs.
    var sync: CutCardioSync?
    /// The header menu offers the two sync actions only when Health is connected.
    var canSync = false
    var isSyncing = false
}

struct CutCardioMessage: Equatable {
    var title: String
    var line: String
    /// "Connect Health" when access is missing.
    var showsConnect: Bool
}

struct CutCardioSync: Equatable {
    var title: String
    /// "26%" once the total is known.
    var percent: String?
}

struct CutCardioWeek: Equatable {
    /// "This week", "Last week", "12 to 18 Oct".
    var label: String
    var canGoOlder: Bool
    var canGoNewer: Bool
    var hero: CutCardioHero
    var stats: [CutStatColumn]
    var bars: [CutCardioDayBar]
    /// Streak and the week's best, under the chart.
    var summary: [CutStatColumn]
    var sectionTitle: String
    var rows: [CutCardioRunRow]
    /// Shown in place of rows when the week has none.
    var emptyLine: String
}

struct CutCardioHero: Equatable {
    var value: String
    var unit: String?
}

struct CutCardioDayBar: Equatable, Identifiable {
    var id: Int
    /// "M", "T", ...
    var letter: String
    /// 0...1 of the week's biggest day.
    var fraction: Double
    var isToday: Bool
}

struct CutCardioRunRow: Equatable, Identifiable {
    var id: UUID
    var title: String
    /// "Friday, 34:12"
    var line: String
    /// "6.2 km" or "1:05"
    var value: String
}

// MARK: - Detail model

struct CutCardioDetailModel: Equatable {
    enum Route: Equatable {
        /// No route and nothing to fetch it from.
        case none
        /// A route map is drawn by the host.
        case map
        /// A Health workout without a route yet: "Get route map".
        case canFetch
    }

    struct Split: Equatable, Identifiable {
        var id: Int
        var label: String
        var pace: String
        /// Bar length: the fastest split is 1.
        var fraction: Double
        var isFastest: Bool
    }

    struct Zone: Equatable, Identifiable {
        var id: Int
        var label: String
        var time: String
        var fraction: Double
    }

    struct HeartRate: Equatable {
        var stats: [CutStatColumn]
        /// Bucketed samples, 0...1 between the lowest and highest bucket.
        var bars: [Double]
        var zones: [Zone]
        var isEstimated: Bool
    }

    var title: String
    var dateLine: String
    var hero: CutCardioHero
    var stats: [CutStatColumn]
    var route: Route
    var splits: [Split]
    /// A Health workout without splits: "Load splits".
    var canLoadSplits: Bool
    var heartRate: HeartRate?
    /// A Health workout without per-point heart rate: "Load details".
    var canLoadDetails: Bool
    /// Rows of two columns.
    var performance: [[CutStatColumn]]
    var notes: String?
    /// "Morning Run, 6.2 km"
    var deleteTitle: String
}

// MARK: - Logic

enum CutCardioLogic {
    // MARK: Filtering (the legacy CardioView's rules)

    static let namedTypes: Set<String> = ["Running", "Walking", "Cycling"]
    /// Activities the legacy tab counts as Other. Kept in step with CardioView.eligibleOtherCardioTypes.
    static let eligibleOtherTypes: Set<String> = [
        "Elliptical", "Stair Climbing", "Rowing", "High Intensity Interval Training", "Dance",
        "Kickboxing", "Boxing", "Soccer", "Basketball", "Tennis", "Pickleball", "Badminton",
        "Volleyball", "Handball", "Racquetball", "Squash", "Table Tennis", "Hockey", "Field Hockey",
        "Lacrosse", "Rugby", "Football", "Cricket", "Martial Arts", "Wrestling", "Skating Sports",
        "Snow Sports"
    ]

    static func matches(_ run: Run, type: CardioType) -> Bool {
        guard let workoutType = run.workoutType else {
            return type == .running && run.distanceKm > 0.1
        }
        switch type {
        case .other: return !namedTypes.contains(workoutType) && eligibleOtherTypes.contains(workoutType)
        default: return workoutType == type.rawValue
        }
    }

    static func runs(_ all: [Run], type: CardioType) -> [Run] {
        all.filter { matches($0, type: type) }
    }

    // MARK: Weeks (Monday first)

    static func mondayCalendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        let calendar = mondayCalendar(calendar)
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func weekStart(offset: Int, now: Date, calendar: Calendar) -> Date {
        let current = weekStart(of: now, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7 * offset, to: current) ?? current
    }

    static func runs(_ runs: [Run], inWeek offset: Int, now: Date, calendar: Calendar) -> [Run] {
        let start = weekStart(offset: offset, now: now, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return runs.filter { $0.date >= start && $0.date < end }
    }

    /// How many weeks back the oldest run is; 0 when there are none.
    static func maxWeekOffset(_ runs: [Run], now: Date, calendar: Calendar) -> Int {
        guard let oldest = runs.map(\.date).min() else { return 0 }
        let current = weekStart(of: now, calendar: calendar)
        let first = weekStart(of: oldest, calendar: calendar)
        let days = calendar.dateComponents([.day], from: first, to: current).day ?? 0
        return max(0, Int((Double(days) / 7).rounded()))
    }

    static func clampedOffset(_ offset: Int, runs: [Run], now: Date, calendar: Calendar) -> Int {
        min(max(0, offset), maxWeekOffset(runs, now: now, calendar: calendar))
    }

    static func weekLabel(offset: Int, now: Date, calendar: Calendar, locale: Locale) -> String {
        switch offset {
        case 0: return "This week"
        case 1: return "Last week"
        default:
            let start = weekStart(offset: offset, now: now, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
            let day = formatter("d", locale: locale, calendar: calendar)
            let dayMonth = formatter("d MMM", locale: locale, calendar: calendar)
            let first = sameMonth ? day.string(from: start) : dayMonth.string(from: start)
            return "\(first) to \(dayMonth.string(from: end))"
        }
    }

    // MARK: Tab

    static func tab(
        allRuns: [Run]?,
        type: CardioType,
        weekOffset: Int,
        connection: HealthConnectionState,
        isSyncing: Bool,
        syncProcessed: Int = 0,
        syncTotal: Int = 0,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> CutCardioTabModel {
        let connected = connection == .connected
        let sync = isSyncing ? syncLine(processed: syncProcessed, total: syncTotal) : nil
        guard let allRuns else {
            return CutCardioTabModel(type: type, content: .loading, sync: sync, canSync: connected, isSyncing: isSyncing)
        }
        let typed = runs(allRuns, type: type)
        guard !typed.isEmpty else {
            return CutCardioTabModel(type: type, content: .empty(emptyMessage(type: type, connected: connected)),
                                     sync: sync, canSync: connected, isSyncing: isSyncing)
        }
        let offset = clampedOffset(weekOffset, runs: typed, now: now, calendar: calendar)
        let week = self.week(typed, type: type, offset: offset, now: now, calendar: calendar, locale: locale)
        return CutCardioTabModel(type: type, content: .week(week), showsConnectRow: !connected,
                                 sync: sync, canSync: connected, isSyncing: isSyncing)
    }

    static func syncLine(processed: Int, total: Int) -> CutCardioSync {
        guard total > 0 else { return CutCardioSync(title: "Syncing with Apple Health") }
        let percent = Int((Double(min(processed, total)) / Double(total) * 100).rounded())
        return CutCardioSync(title: "Syncing \(min(processed, total)) of \(total)", percent: "\(percent)%")
    }

    static func emptyMessage(type: CardioType, connected: Bool) -> CutCardioMessage {
        if !connected {
            return CutCardioMessage(title: "Connect Apple Health",
                                    line: "VOLIA reads your runs, walks and rides from Apple Health.",
                                    showsConnect: true)
        }
        return CutCardioMessage(title: "No \(type.activityName.lowercased()) yet",
                                line: "Record one with Apple Watch or iPhone and it shows up here.",
                                showsConnect: false)
    }

    static func week(_ typed: [Run], type: CardioType, offset: Int, now: Date, calendar: Calendar, locale: Locale) -> CutCardioWeek {
        let inWeek = runs(typed, inWeek: offset, now: now, calendar: calendar).sorted { $0.date > $1.date }
        return CutCardioWeek(
            label: weekLabel(offset: offset, now: now, calendar: calendar, locale: locale),
            canGoOlder: offset < maxWeekOffset(typed, now: now, calendar: calendar),
            canGoNewer: offset > 0,
            hero: weekHero(inWeek, type: type),
            stats: weekStats(inWeek, type: type),
            bars: dayBars(inWeek, type: type, weekStart: weekStart(offset: offset, now: now, calendar: calendar),
                          today: offset == 0 ? now : nil, calendar: calendar),
            summary: summary(typed, week: inWeek, type: type, now: now, calendar: calendar),
            sectionTitle: type.activityName,
            rows: inWeek.map { row($0, type: type, now: now, calendar: calendar, locale: locale) },
            emptyLine: "No \(type.activityName.lowercased()) this week."
        )
    }

    /// Distance for the distance types; total time for Other.
    static func weekHero(_ runs: [Run], type: CardioType) -> CutCardioHero {
        if type.showsPace {
            return CutCardioHero(value: String(format: "%.1f", runs.reduce(0) { $0 + $1.distanceKm }), unit: "km")
        }
        let seconds = runs.reduce(0) { $0 + $1.durationSec }
        if seconds >= 3600 {
            return CutCardioHero(value: String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60), unit: "h")
        }
        return CutCardioHero(value: "\(seconds / 60)", unit: "min")
    }

    static func weekStats(_ runs: [Run], type: CardioType) -> [CutStatColumn] {
        let total = runs.reduce(0) { $0 + $1.durationSec }
        let count = CutStatColumn(value: "\(runs.count)", label: type.activityName)
        switch type {
        case .running, .walking:
            return [CutStatColumn(value: duration(total), label: "Time"),
                    CutStatColumn(value: averagePace(runs).map { pace($0) } ?? "--", label: "Avg /km"),
                    count]
        case .cycling:
            return [CutStatColumn(value: duration(total), label: "Time"),
                    CutStatColumn(value: averagePace(runs).map { speed($0) } ?? "--", label: "Avg km/h"),
                    count]
        case .other:
            let longest = runs.map(\.durationSec).max()
            return [count,
                    CutStatColumn(value: runs.isEmpty ? "--" : duration(total / runs.count), label: "Average"),
                    CutStatColumn(value: longest.map { duration($0) } ?? "--", label: "Longest")]
        }
    }

    /// Seven bars, Monday first: distance per day, or time for Other.
    static func dayBars(_ runs: [Run], type: CardioType, weekStart: Date, today: Date?, calendar: Calendar) -> [CutCardioDayBar] {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let values: [Double] = (0..<7).map { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: weekStart) else { return 0 }
            return runs.filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + (type.showsPace ? $1.distanceKm : Double($1.durationSec)) }
        }
        let biggest = values.max() ?? 0
        return (0..<7).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: weekStart)
            let isToday = today.flatMap { today in day.map { calendar.isDate($0, inSameDayAs: today) } } ?? false
            return CutCardioDayBar(id: index, letter: letters[index],
                                   fraction: biggest > 0 ? values[index] / biggest : 0, isToday: isToday)
        }
    }

    /// The week streak, then the week's best pace (or speed), or for Other the all-time count.
    static func summary(_ typed: [Run], week: [Run], type: CardioType, now: Date, calendar: Calendar) -> [CutStatColumn] {
        let streak = CutStatColumn(value: "\(streakWeeks(typed, type: type, now: now, calendar: calendar))", label: "Week streak")
        switch type {
        case .running, .walking:
            return [streak, CutStatColumn(value: bestPace(week).map { pace($0) } ?? "--", label: "Best /km")]
        case .cycling:
            return [streak, CutStatColumn(value: bestPace(week).map { speed($0) } ?? "--", label: "Best km/h")]
        case .other:
            return [streak, CutStatColumn(value: "\(typed.count)", label: "All time")]
        }
    }

    /// Consecutive weeks up to this one with at least one qualifying session: 1 km or more for
    /// the distance types, any time for Other. Zero when this week has none yet.
    static func streakWeeks(_ runs: [Run], type: CardioType, now: Date, calendar: Calendar) -> Int {
        let qualifying = runs.filter { type.showsPace ? $0.distanceKm >= 1.0 : $0.durationSec > 0 }
        let weeks = Set(qualifying.map { weekStart(of: $0.date, calendar: calendar) })
        var week = weekStart(of: now, calendar: calendar)
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -7, to: week) else { break }
            week = weekStart(of: previous, calendar: calendar)
        }
        return streak
    }

    /// Mean of per-session paces in seconds per km, sessions over 200 m only.
    static func averagePace(_ runs: [Run]) -> Double? {
        let paces = runs.filter { $0.distanceKm > 0.2 }.map { Double($0.durationSec) / $0.distanceKm }
        guard !paces.isEmpty else { return nil }
        return paces.reduce(0, +) / Double(paces.count)
    }

    static func bestPace(_ runs: [Run]) -> Double? {
        runs.filter { $0.distanceKm > 0.2 }.map { Double($0.durationSec) / $0.distanceKm }.min()
    }

    static func row(_ run: Run, type: CardioType, now: Date, calendar: Calendar, locale: Locale) -> CutCardioRunRow {
        let day = dayLabel(run.date, now: now, calendar: calendar, locale: locale)
        if type.showsPace {
            return CutCardioRunRow(id: run.id, title: title(run), line: "\(day), \(duration(run.durationSec))",
                                   value: "\(String(format: "%.1f", run.distanceKm)) km")
        }
        return CutCardioRunRow(id: run.id, title: title(run), line: day, value: duration(run.durationSec))
    }

    static func title(_ run: Run) -> String {
        if let name = run.workoutName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let type = run.workoutType, !type.isEmpty { return type }
        return "Run"
    }

    /// "Today", "Yesterday", the weekday within the last week, else "12 Oct".
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday" }
        if days > 1 && days < 7 { return formatter("EEEE", locale: locale, calendar: calendar).string(from: date) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "d MMM" : "d MMM yyyy", locale: locale, calendar: calendar).string(from: date)
    }

    // MARK: Detail

    static func detail(_ run: Run, zones: [HRZoneSummary], hrSamples: [HeartRateSample]?, now: Date,
                       calendar: Calendar = .current, locale: Locale = .current) -> CutCardioDetailModel {
        let hasDistance = run.distanceKm > 0.01
        let isCycling = run.workoutType == "Cycling"
        let paceValue: Double? = run.distanceKm > 0.2 && run.durationSec > 0 ? Double(run.durationSec) / run.distanceKm : nil
        let avgHR = run.avgHeartRate.flatMap { $0 > 0 ? $0 : nil }

        var stats: [CutStatColumn] = []
        let hero: CutCardioHero
        if hasDistance {
            hero = CutCardioHero(value: String(format: "%.2f", run.distanceKm), unit: "km")
            stats.append(CutStatColumn(value: duration(run.durationSec), label: "Duration"))
            if let paceValue {
                stats.append(isCycling ? CutStatColumn(value: speed(paceValue), label: "Avg km/h")
                                       : CutStatColumn(value: pace(paceValue), label: "Avg /km"))
            }
        } else {
            hero = CutCardioHero(value: duration(run.durationSec), unit: nil)
            if let kcal = run.calories, kcal > 0 { stats.append(CutStatColumn(value: "\(Int(kcal.rounded()))", label: "kcal")) }
        }
        if let avgHR { stats.append(CutStatColumn(value: "\(Int(avgHR.rounded()))", label: "Avg bpm")) }

        let routeCount = max(run.routeWithHR?.count ?? 0, run.route?.count ?? 0)
        let route: CutCardioDetailModel.Route = routeCount > 1 ? .map : (run.healthKitUUID != nil ? .canFetch : .none)

        let splits = splitRows(run.splits ?? [])
        return CutCardioDetailModel(
            title: title(run),
            dateLine: dateLine(run.date, now: now, calendar: calendar, locale: locale),
            hero: hero,
            stats: stats,
            route: route,
            splits: splits,
            canLoadSplits: splits.isEmpty && hasDistance && run.healthKitUUID != nil,
            heartRate: heartRate(run, zones: zones, samples: hrSamples),
            canLoadDetails: (run.routeWithHR?.count ?? 0) < 2 && run.healthKitUUID != nil,
            performance: performance(run, hasDistance: hasDistance, showsEnergyInStats: !hasDistance),
            notes: run.notes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
            deleteTitle: hasDistance ? "\(title(run)), \(String(format: "%.1f", run.distanceKm)) km" : title(run)
        )
    }

    /// "Friday 13 Nov, 07:12"
    static func dateLine(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = formatter(sameYear ? "EEEE d MMM" : "EEEE d MMM yyyy", locale: locale, calendar: calendar).string(from: date)
        let time = formatter("HH:mm", locale: locale, calendar: calendar).string(from: date)
        return "\(day), \(time)"
    }

    static func splitRows(_ splits: [KilometerSplit]) -> [CutCardioDetailModel.Split] {
        let valid = splits.filter { $0.paceSecPerKm > 0 }
        guard let fastest = valid.map(\.paceSecPerKm).min() else { return [] }
        let fastestIndex = valid.firstIndex { $0.paceSecPerKm == fastest }
        return valid.enumerated().map { index, split in
            let partial = split.distanceKm < 0.95
            return CutCardioDetailModel.Split(
                id: split.number,
                label: partial ? String(format: "%.1f", Double(split.number - 1) + split.distanceKm) : "\(split.number)",
                pace: pace(Double(split.paceSecPerKm)),
                fraction: Double(fastest) / Double(split.paceSecPerKm),
                isFastest: index == fastestIndex && valid.count > 1
            )
        }
    }

    static func heartRate(_ run: Run, zones: [HRZoneSummary], samples: [HeartRateSample]?) -> CutCardioDetailModel.HeartRate? {
        var stats: [CutStatColumn] = []
        if let avg = run.avgHeartRate, avg > 0 { stats.append(CutStatColumn(value: "\(Int(avg.rounded()))", label: "Average")) }
        if let max = run.maxHeartRate, max > 0 { stats.append(CutStatColumn(value: "\(Int(max.rounded()))", label: "Max")) }
        if let min = run.minHeartRate, min > 0 { stats.append(CutStatColumn(value: "\(Int(min.rounded()))", label: "Min")) }
        let total = zones.reduce(0) { $0 + $1.minutes }
        let zoneRows: [CutCardioDetailModel.Zone] = total > 0
            ? zones.sorted { $0.zone < $1.zone }.map {
                .init(id: $0.zone, label: "Zone \($0.zone)", time: duration(Int(($0.minutes * 60).rounded())), fraction: $0.minutes / total)
            }
            : []
        let bars = heartRateBars(samples ?? [])
        guard !stats.isEmpty || !zoneRows.isEmpty || !bars.isEmpty else { return nil }
        return CutCardioDetailModel.HeartRate(stats: stats, bars: bars, zones: zoneRows,
                                              isEstimated: total > 0 && zones.first?.isEstimated == true)
    }

    /// Samples in time order, averaged into at most `count` equal buckets, scaled 0.15...1
    /// between the lowest and highest bucket so the quietest stretch still shows.
    static func heartRateBars(_ samples: [HeartRateSample], count: Int = 16) -> [Double] {
        let sorted = samples.filter { $0.bpm > 0 }.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > 2, count > 0 else { return [] }
        let buckets = min(count, sorted.count)
        let averages: [Double] = (0..<buckets).map { index in
            let lower = index * sorted.count / buckets
            let upper = max(lower + 1, (index + 1) * sorted.count / buckets)
            let slice = sorted[lower..<min(upper, sorted.count)]
            return slice.reduce(0) { $0 + $1.bpm } / Double(slice.count)
        }
        guard let low = averages.min(), let high = averages.max() else { return [] }
        guard high > low else { return averages.map { _ in 1 } }
        return averages.map { 0.15 + 0.85 * ($0 - low) / (high - low) }
    }

    /// Energy, speed, energy per km and the running dynamics the watch recorded, two per row.
    static func performance(_ run: Run, hasDistance: Bool, showsEnergyInStats: Bool) -> [[CutStatColumn]] {
        var items: [CutStatColumn] = []
        if !showsEnergyInStats, let kcal = run.calories, kcal > 0 {
            items.append(CutStatColumn(value: "\(Int(kcal.rounded()))", label: "Energy", unit: "kcal"))
        }
        if hasDistance, run.durationSec > 0 {
            items.append(CutStatColumn(value: String(format: "%.1f", run.distanceKm / Double(run.durationSec) * 3600),
                                       label: "Avg speed", unit: "km/h"))
            if let kcal = run.calories, kcal > 0 {
                items.append(CutStatColumn(value: "\(Int((kcal / run.distanceKm).rounded()))", label: "Energy per km", unit: "kcal"))
            }
        }
        if let power = run.avgRunningPower { items.append(CutStatColumn(value: String(format: "%.0f", power), label: "Power", unit: "W")) }
        if let cadence = run.avgCadence { items.append(CutStatColumn(value: String(format: "%.0f", cadence), label: "Cadence", unit: "spm")) }
        if let strideLength = run.avgStrideLength { items.append(CutStatColumn(value: String(format: "%.2f", strideLength), label: "Stride", unit: "m")) }
        if let contact = run.avgGroundContactTime {
            items.append(CutStatColumn(value: String(format: "%.0f", contact), label: "Ground contact", unit: "ms"))
        }
        if let oscillation = run.avgVerticalOscillation {
            items.append(CutStatColumn(value: String(format: "%.1f", oscillation), label: "Oscillation", unit: "cm"))
        }
        return stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    // MARK: Formats

    /// "34:12" under an hour, "1:05" (h:mm) from an hour: seconds are dropped once hours show.
    static func duration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%d:%02d", hours, minutes) }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    /// Seconds per km as "5:32".
    static func pace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Seconds per km as km/h, "24.3".
    static func speed(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--" }
        return String(format: "%.1f", 3600 / secondsPerKm)
    }

    /// A fixed day-first format ("12 Oct", "Friday 13 Nov"), names in the given locale.
    private static func formatter(_ format: String, locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
