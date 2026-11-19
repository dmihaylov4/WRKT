//
//  CutYearReviewModel.swift
//  WRKT
//
//  Year in review: the plain numbers for one calendar year, the comparison ladders that turn
//  them into objects ("You lifted the Riesenrad."), and when the pop-up is due.
//  Nothing here reads a service; CutYearReviewCenter feeds it from the workout store.
//

import Foundation

// MARK: - Stats

/// One calendar year of training, as the year in review shows it.
struct CutYearReviewStats: Equatable {
    var year: Int
    /// Weight times reps over every completed weighted set, in kilograms.
    var liftedKg: Double = 0
    var distanceKm: Double = 0
    var longestDistanceKm: Double = 0
    var trainedSeconds: Double = 0
    var workouts: Int = 0
    var records: Int = 0
    var longestStreakWeeks: Int = 0
    var streakStart: Date?
    var streakEnd: Date?
    /// One flag per week of the year, in order: trained that week or not.
    var activeWeeks: [Bool] = []
    /// Where the longest streak starts in `activeWeeks`.
    var streakStartWeek: Int?

    var hasAnything: Bool { workouts > 0 }
}

/// The stat cards between the opening card and the share card.
enum CutYearReviewCard: String, CaseIterable, Identifiable {
    case lifted, distance, time, streak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lifted: "Strength"
        case .distance: "Cardio"
        case .time: "Time"
        case .streak: "Streak"
        }
    }
}

/// One number set against something from the real world.
struct CutYearReviewComparison: Equatable {
    /// "You lifted the Riesenrad."
    let headline: String
    /// The one supporting line under the headline.
    let detail: String
    /// The same claim in the first person, for the share card: "I lifted the Riesenrad."
    let shareLine: String
    /// A few words for the share card's row: "one giant wheel".
    let short: String
}

// MARK: - Weight ladder

/// One rung of the weight ladder. A rung is a line of text: adding one costs nothing to store.
struct CutYearReviewRung: Equatable {
    enum Art: Equatable {
        /// The drawn giant wheel.
        case wheel
        /// An SF Symbol, repeated once per object.
        case symbol(String)
        /// Slanted blocks, one per object.
        case blocks
    }

    let kg: Double
    /// With its article: "a city bus", "the Riesenrad".
    let name: String
    /// Nil for one-of-a-kind objects, which read "the Riesenrad, twice".
    let plural: String?
    let short: String
    let art: Art
}

enum CutYearReviewLadder {
    /// Approximate weights, lightest first. Check each figure before release.
    static let weight: [CutYearReviewRung] = [
        .init(kg: 250, name: "a giant tortoise", plural: "giant tortoises", short: "giant tortoise", art: .symbol("tortoise.fill")),
        .init(kg: 480, name: "a concert grand piano", plural: "concert grand pianos", short: "grand piano", art: .symbol("pianokeys")),
        .init(kg: 1_500, name: "a family car", plural: "family cars", short: "family car", art: .symbol("car.fill")),
        .init(kg: 6_000, name: "an African elephant", plural: "African elephants", short: "elephant", art: .blocks),
        .init(kg: 12_000, name: "a city bus", plural: "city buses", short: "city bus", art: .symbol("bus.fill")),
        .init(kg: 40_000, name: "a tram", plural: "trams", short: "tram", art: .symbol("tram.fill")),
        .init(kg: 90_000, name: "a locomotive", plural: "locomotives", short: "locomotive", art: .symbol("train.side.front.car")),
        .init(kg: 150_000, name: "a blue whale", plural: "blue whales", short: "blue whale", art: .blocks),
        .init(kg: 204_000, name: "the Statue of Liberty", plural: nil, short: "Statue of Liberty", art: .blocks),
        .init(kg: 430_000, name: "the Riesenrad", plural: nil, short: "giant wheel", art: .wheel),
        .init(kg: 575_000, name: "a fully loaded A380", plural: "fully loaded A380s", short: "loaded A380", art: .symbol("airplane")),
        .init(kg: 2_030_000, name: "a Space Shuttle ready for launch", plural: "Space Shuttles ready for launch", short: "Space Shuttle", art: .blocks),
        .init(kg: 7_300_000, name: "the Eiffel Tower's ironwork", plural: nil, short: "Eiffel Tower", art: .blocks)
    ]

    /// The heaviest rung the total reaches and how many of it fit, or nil below the first rung.
    static func rung(forKg kg: Double, ladder: [CutYearReviewRung] = weight) -> (rung: CutYearReviewRung, count: Int)? {
        guard let rung = ladder.last(where: { $0.kg <= kg }) else { return nil }
        return (rung, max(1, Int(kg / rung.kg)))
    }
}

// MARK: - Logic

enum CutYearReviewLogic {
    static let marathonKm = 42.195
    static let seenYearKey = "yearReview.seenYear"
    /// Debug only: show the pop-up on the next launch whatever the date.
    static let forceNextLaunchKey = "debug.yearReview.forceNextLaunch"
    /// Fewer workouts than this and the year is too thin to review.
    static let minimumWorkouts = 5

    // MARK: Building the stats

    static func stats(year: Int, workouts: [CompletedWorkout], runs: [RunSummary],
                      now: Date = .now, calendar: Calendar = .current) -> CutYearReviewStats {
        var stats = CutYearReviewStats(year: year)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return stats }
        let range = start..<end

        let sessions = workouts.filter { range.contains($0.date) && !$0.isCardioWorkout }
        let matched = Set(workouts.compactMap(\.matchedHealthKitUUID))
        // Runs already attached to a logged workout would count the same hour twice.
        let outings = runs.filter { run in
            range.contains(run.date) && !(run.healthKitUUID.map(matched.contains) ?? false)
        }

        stats.liftedKg = sessions.reduce(0) { $0 + liftedKg($1) }
        stats.records = sessions.reduce(0) { $0 + ($1.detectedPRCount ?? 0) }
        stats.distanceKm = outings.reduce(0) { $0 + max(0, $1.distanceKm) }
        stats.longestDistanceKm = outings.map(\.distanceKm).max() ?? 0
        stats.trainedSeconds = sessions.reduce(0) { $0 + duration($1) }
            + outings.reduce(0) { $0 + Double(max(0, $1.durationSec)) }
        stats.workouts = sessions.count + outings.count

        // Weeks of the year, up to this week when the year is still running.
        let lastDay = min(now, end.addingTimeInterval(-1))
        var weekStarts: [Date] = []
        var cursor = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        while cursor <= lastDay, weekStarts.count < 54 {
            weekStarts.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        let trainedWeeks = Set((sessions.map(\.date) + outings.map(\.date)).compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0)?.start
        })
        stats.activeWeeks = weekStarts.map(trainedWeeks.contains)

        let streak = longestRun(stats.activeWeeks)
        stats.longestStreakWeeks = streak.length
        if streak.length > 0 {
            stats.streakStartWeek = streak.start
            stats.streakStart = max(weekStarts[streak.start], start)
            let lastWeek = weekStarts[streak.start + streak.length - 1]
            stats.streakEnd = min(calendar.date(byAdding: .day, value: 6, to: lastWeek) ?? lastWeek, lastDay)
        }
        return stats
    }

    /// Weight times reps over the sets that were done. Workouts saved before sets carried a
    /// completed flag count every set with reps.
    static func liftedKg(_ workout: CompletedWorkout) -> Double {
        let sets = workout.entries.flatMap(\.sets).filter { !$0.isGhost && $0.reps > 0 && $0.weight > 0 }
        let done = sets.filter(\.isCompleted)
        return (done.isEmpty ? sets : done).reduce(0) { $0 + Double($1.reps) * $1.weight }
    }

    /// The matched Apple Health duration, else start to end, capped at six hours.
    static func duration(_ workout: CompletedWorkout) -> Double {
        if let seconds = workout.matchedHealthKitDuration, seconds > 0 { return Double(seconds) }
        guard let started = workout.startedAt else { return 0 }
        return min(max(0, workout.date.timeIntervalSince(started)), 6 * 3600)
    }

    /// The first longest run of `true`.
    static func longestRun(_ flags: [Bool]) -> (start: Int, length: Int) {
        var best = (start: 0, length: 0)
        var current = (start: 0, length: 0)
        for (index, flag) in flags.enumerated() {
            if flag {
                if current.length == 0 { current.start = index }
                current.length += 1
                if current.length > best.length { best = current }
            } else {
                current.length = 0
            }
        }
        return best
    }

    // MARK: Which cards

    static func cards(for stats: CutYearReviewStats) -> [CutYearReviewCard] {
        var cards: [CutYearReviewCard] = []
        if stats.liftedKg >= 1 { cards.append(.lifted) }
        if stats.distanceKm >= 1 { cards.append(.distance) }
        if stats.trainedSeconds >= 3600 { cards.append(.time) }
        if stats.longestStreakWeeks >= 2 { cards.append(.streak) }
        return cards
    }

    // MARK: When it pops up

    /// The year under review: this year from 15 December, last year through January.
    static func reviewYear(now: Date = .now, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12, day >= 15 { return year }
        if month == 1 { return year - 1 }
        return nil
    }

    static func shouldAutoPresent(stats: CutYearReviewStats, seenYear: Int?) -> Bool {
        seenYear != stats.year && stats.workouts >= minimumWorkouts && !cards(for: stats).isEmpty
    }

    // MARK: Numbers as text

    static func grouped(_ value: Double) -> String {
        value.rounded().formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    /// The hero number of the lifted card in the user's unit: "430,000 kg".
    static func liftedText(kg: Double, unit: WeightUnit) -> String {
        unit == .lb ? "\(grouped(kg * 2.20462)) lb" : "\(grouped(kg)) kg"
    }

    /// An object's weight in a sentence: "480 kg", "1.5 tonnes", "430 tonnes" (pounds for lb users).
    static func weightText(kg: Double, unit: WeightUnit) -> String {
        if unit == .lb {
            let pounds = kg * 2.20462
            let step: Double = pounds >= 100_000 ? 1_000 : pounds >= 10_000 ? 100 : 10
            return "\(grouped((pounds / step).rounded() * step)) lb"
        }
        if kg < 1_000 { return "\(grouped(kg)) kg" }
        let tonnes = kg / 1_000
        let text = tonnes.formatted(.number.precision(.fractionLength(tonnes < 10 && tonnes != tonnes.rounded() ? 1 : 0)))
        return "\(text) tonnes"
    }

    static func distanceText(km: Double) -> String { "\(grouped(km)) km" }

    static func hoursText(seconds: Double) -> String {
        let hours = Int((seconds / 3600).rounded())
        return hours == 1 ? "1 hour" : "\(grouped(Double(hours))) hours"
    }

    static func weeksText(_ weeks: Int) -> String { weeks == 1 ? "1 week" : "\(weeks) weeks" }

    private static let words = ["zero", "one", "two", "three", "four", "five", "six", "seven",
                                "eight", "nine", "ten", "eleven", "twelve"]

    /// "two" up to twelve, digits beyond.
    static func word(_ number: Int) -> String {
        words.indices.contains(number) ? words[number] : grouped(Double(number))
    }

    static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "twice", "three times".
    static func times(_ count: Int) -> String {
        count == 2 ? "twice" : "\(word(count)) times"
    }

    // MARK: Comparisons

    /// "the Riesenrad", "two city buses", "the Riesenrad, twice".
    static func objectPhrase(_ rung: CutYearReviewRung, count: Int) -> String {
        guard count > 1 else { return rung.name }
        if let plural = rung.plural { return "\(word(count)) \(plural)" }
        return "\(rung.name), \(times(count))"
    }

    static func lifted(kg: Double, unit: WeightUnit) -> CutYearReviewComparison {
        guard let (rung, count) = CutYearReviewLadder.rung(forKg: kg) else {
            return CutYearReviewComparison(
                headline: "Every kilo counted.",
                detail: "The first rung of the ladder is a giant tortoise at about \(weightText(kg: 250, unit: unit)). Next year.",
                shareLine: "I lifted \(liftedText(kg: kg, unit: unit)).",
                short: "and counting")
        }
        let phrase = objectPhrase(rung, count: count)
        let weighs = "\(capitalised(rung.plural == nil || count == 1 ? rung.name : "one")) weighs about \(weightText(kg: rung.kg, unit: unit))."
        let moved = count == 1 ? "You moved that much iron this year." : "You moved that \(times(count)) over this year."
        return CutYearReviewComparison(
            headline: "You lifted \(phrase).",
            detail: "\(weighs) \(moved)",
            shareLine: "I lifted \(phrase).",
            short: count == 1 ? "one \(rung.short)" : "\(rung.short) x \(count)")
    }

    /// Marathons in halves ("Eleven and a half marathons."), laps of a track below half of one.
    static func distance(km: Double, longestKm: Double) -> CutYearReviewComparison {
        let detail = longestKm >= 1
            ? "Your longest single outing was \(longestKm.formatted(.number.precision(.fractionLength(1)))) km."
            : "Every kilometre on foot or on wheels counts."
        let halves = Int((km / marathonKm * 2).rounded(.down))
        guard halves >= 1 else {
            let laps = max(1, Int(km / 0.4))
            let phrase = "\(word(laps)) laps of a running track"
            return CutYearReviewComparison(headline: "\(capitalised(phrase)).", detail: detail,
                                           shareLine: "I covered \(phrase).", short: "\(laps) track laps")
        }
        let whole = halves / 2
        let half = halves % 2 == 1
        let phrase: String
        switch (whole, half) {
        case (0, _): phrase = "half a marathon"
        case (1, false): phrase = "a full marathon"
        case (1, true): phrase = "a marathon and a half"
        case (_, false): phrase = "\(word(whole)) marathons"
        case (_, true): phrase = "\(word(whole)) and a half marathons"
        }
        let short = half ? "\(whole).5 marathons" : (whole == 1 ? "1 marathon" : "\(whole) marathons")
        return CutYearReviewComparison(headline: "\(capitalised(phrase)).", detail: detail,
                                       shareLine: "I covered \(phrase).", short: whole == 0 ? "half a marathon" : short)
    }

    /// Hours as days without a break: "Almost five days, non-stop."
    static func time(seconds: Double, workouts: Int) -> CutYearReviewComparison {
        let hours = seconds / 3600
        let days = hours / 24
        let whole = Int(days)
        let rest = days - Double(whole)
        let phrase: String
        let short: String
        if days < 1 {
            phrase = "\(word(Int(hours.rounded()))) hours, back to back"
            short = "back to back"
        } else if rest >= 0.85 {
            phrase = "almost \(word(whole + 1)) days, non-stop"
            short = "almost \(whole + 1) full days"
        } else if rest < 0.15 {
            phrase = whole == 1 ? "a full day, non-stop" : "\(word(whole)) full days, non-stop"
            short = whole == 1 ? "1 full day" : "\(whole) full days"
        } else if (0.4...0.6).contains(rest) {
            phrase = whole == 1 ? "a day and a half, non-stop" : "\(word(whole)) and a half days, non-stop"
            short = "\(whole).5 full days"
        } else {
            phrase = whole == 1 ? "more than a day, non-stop" : "more than \(word(whole)) days, non-stop"
            short = whole == 1 ? "over 1 full day" : "over \(whole) full days"
        }
        let detail = workouts == 1 ? "All in one workout." : "Spread over \(grouped(Double(workouts))) workouts."
        return CutYearReviewComparison(headline: "\(capitalised(phrase)).", detail: detail,
                                       shareLine: "I trained for \(phrase).", short: short)
    }

    /// The longest run of weeks with at least one workout.
    static func streak(weeks: Int, start: Date?, end: Date?) -> CutYearReviewComparison {
        let phrase: String
        switch weeks {
        case 52...: phrase = "every single week of the year"
        case 26...: phrase = "half the year, no week off"
        case 13...: phrase = "a full season, no week off"
        case 9...: phrase = "a whole summer break, no week off"
        case 6...: phrase = "a school summer, no week off"
        case 4...: phrase = "a full month, no week off"
        default: phrase = "back to back weeks"
        }
        var detail = "Your longest run of weeks with a workout."
        if let start, let end {
            let format = Date.FormatStyle().day().month(.wide)
            detail = "Your longest streak ran from \(start.formatted(format)) to \(end.formatted(format))."
        }
        return CutYearReviewComparison(headline: "\(capitalised(phrase)).", detail: detail,
                                       shareLine: "I trained \(weeks) weeks in a row.", short: "longest streak")
    }

    static func comparison(_ card: CutYearReviewCard, stats: CutYearReviewStats, unit: WeightUnit) -> CutYearReviewComparison {
        switch card {
        case .lifted: lifted(kg: stats.liftedKg, unit: unit)
        case .distance: distance(km: stats.distanceKm, longestKm: stats.longestDistanceKm)
        case .time: time(seconds: stats.trainedSeconds, workouts: stats.workouts)
        case .streak: streak(weeks: stats.longestStreakWeeks, start: stats.streakStart, end: stats.streakEnd)
        }
    }

    /// The card's big number at its final value.
    static func valueText(_ card: CutYearReviewCard, stats: CutYearReviewStats, unit: WeightUnit) -> String {
        switch card {
        case .lifted: liftedText(kg: stats.liftedKg, unit: unit)
        case .distance: distanceText(km: stats.distanceKm)
        case .time: hoursText(seconds: stats.trainedSeconds)
        case .streak: weeksText(stats.longestStreakWeeks)
        }
    }

    /// The opening card's one line, from up to three things the year has.
    static func teaser(stats: CutYearReviewStats, unit: WeightUnit) -> String {
        var parts: [String] = []
        if let (rung, count) = CutYearReviewLadder.rung(forKg: stats.liftedKg) {
            parts.append("lifted \(objectPhrase(rung, count: count))")
        }
        if stats.distanceKm >= marathonKm / 2 {
            let phrase = distance(km: stats.distanceKm, longestKm: 0).headline.dropLast()
            parts.append("covered \(phrase.prefix(1).lowercased() + phrase.dropFirst())")
        }
        if stats.records > 0 {
            parts.append(stats.records == 1 ? "set 1 record" : "set \(stats.records) records")
        }
        if parts.isEmpty {
            parts.append(stats.workouts == 1 ? "logged 1 workout" : "logged \(grouped(Double(stats.workouts))) workouts")
        }
        switch parts.count {
        case 1: return "You \(parts[0])."
        case 2: return "You \(parts[0]) and \(parts[1])."
        default: return "You \(parts[0]), \(parts[1]) and \(parts[2])."
        }
    }

    /// The share card's last line: "142 workouts, 23 records".
    static func footer(stats: CutYearReviewStats) -> String {
        var parts = [stats.workouts == 1 ? "1 workout" : "\(grouped(Double(stats.workouts))) workouts"]
        if stats.records > 0 { parts.append(stats.records == 1 ? "1 record" : "\(stats.records) records") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Sample

extension CutYearReviewStats {
    /// The mock's numbers, for the Debug trigger and previews.
    static func sample(year: Int) -> CutYearReviewStats {
        var weeks = [Bool](repeating: true, count: 52)
        for index in [0, 1, 2, 3, 4, 14, 18, 21, 26, 28, 29, 31, 32, 37, 43, 47, 50, 51] { weeks[index] = false }
        let calendar = Calendar.current
        return CutYearReviewStats(
            year: year, liftedKg: 430_000, distanceKm: 486, longestDistanceKm: 21.1,
            trainedSeconds: 118 * 3600, workouts: 142, records: 23, longestStreakWeeks: 9,
            streakStart: calendar.date(from: DateComponents(year: year, month: 2, day: 3)),
            streakEnd: calendar.date(from: DateComponents(year: year, month: 4, day: 6)),
            activeWeeks: weeks, streakStartWeek: 5)
    }
}
