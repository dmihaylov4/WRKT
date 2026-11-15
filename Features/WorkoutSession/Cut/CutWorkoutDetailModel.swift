//
//  CutWorkoutDetailModel.swift
//  WRKT
//
//  The plain values behind the Cut workout records: a logged strength workout
//  (WorkoutDetailView) and an Apple Health strength workout (HealthKitStrengthDetailView).
//  Everything the legacy screens listed keeps a place: title, date and time, the watch note,
//  the time and count stats, heart rate with min, average and max, zones, and every exercise
//  with its sets. All formatting is here, so the views only lay values out.
//

import Foundation

// MARK: - Workout detail model

struct CutWorkoutDetailModel: Equatable {
    struct SetRow: Equatable, Identifiable {
        var id: Int
        /// "1"
        var number: String
        /// "100 kg × 5", "12 reps", "1:30", "2.50 km"
        var value: String
        /// Only a set that is not a working set is labelled: "Warm-up", "Back-off".
        var tag: String?
        /// "Work 0:45, rest 1:30"
        var timing: String?
    }

    struct Exercise: Equatable, Identifiable {
        var id: UUID
        var exerciseID: String
        var name: String
        /// "4 sets, 20 reps, 1.6K kg"
        var summary: String
        /// "Total 12:30, work 3:00, rest 9:30" when the sets carry timing.
        var timing: String?
        var sets: [SetRow]
        /// The exercise belongs to the workout still running: tapping it opens the live session.
        var opensSession: Bool
    }

    struct HeartRate: Equatable {
        /// Min, average and max, in that order, each only when recorded.
        var stats: [CutStatColumn]
        /// Bucketed samples, 0...1 (see `CutCardioLogic.heartRateBars`).
        var bars: [Double]
        /// First and last sample times, "17:54".
        var startLabel: String?
        var endLabel: String?
        /// "142 samples"
        var sampleCount: String
    }

    struct Zones: Equatable {
        /// Empty when the samples fall in no zone: the section says so.
        var rows: [CutCardioDetailModel.Zone]
        /// "Zones: Default (190 bpm)"
        var method: String?
    }

    var title: String
    /// "Friday 13 Nov, 17:54 to 18:42" or "Friday 13 Nov, ended 18:42"
    var dateLine: String
    /// The workout was matched to an Apple Watch workout.
    var isEnhanced: Bool
    /// Time stats (duration, calories, average rest) then count stats (exercises, sets, reps,
    /// volume). A row with one column is padded so the column keeps half the width.
    var statRows: [[CutStatColumn]]
    var heartRate: HeartRate?
    var zones: Zones?
    var exercises: [Exercise]
    /// "Upper Body Workout, 13 Nov"
    var deleteTitle: String
}

// MARK: - Apple Health strength model

struct CutHealthStrengthModel: Equatable {
    enum Details: Equatable {
        /// No exercises yet: the one lime action on the page adds them.
        case canAdd
        /// The workout was converted into a detailed workout.
        case added
    }

    var title: String
    /// "Friday 13 Nov, 07:10 to 07:51"
    var dateLine: String
    /// "Apple Watch, Traditional Strength Training"
    var sourceLine: String
    var hero: CutCardioHero
    var stats: [CutStatColumn]
    var details: Details
    var notes: String?
    /// "Edit workout" once details exist, else "Add exercise details".
    var editTitle: String
    var deleteTitle: String
}

// MARK: - Logic

enum CutWorkoutDetailLogic {
    // MARK: Workout detail

    static func detail(
        _ workout: CompletedWorkout,
        zones: [HRZoneSummary],
        zoneMethod: String?,
        unit: WeightUnit,
        sessionExerciseIDs: Set<String> = [],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> CutWorkoutDetailModel {
        let title = title(workout)
        let samples = workout.matchedHealthKitHeartRateSamples ?? []
        return CutWorkoutDetailModel(
            title: title,
            dateLine: dateLine(workout, now: now, calendar: calendar, locale: locale),
            isEnhanced: workout.matchedHealthKitUUID != nil,
            statRows: statRows(workout, unit: unit),
            heartRate: heartRate(workout, calendar: calendar, locale: locale),
            zones: samples.count > 5 ? zoneSection(zones, method: zoneMethod) : nil,
            exercises: workout.entries.map { exercise($0, unit: unit, opensSession: sessionExerciseIDs.contains($0.exerciseID)) },
            deleteTitle: "\(title), \(shortDate(workout.date, now: now, calendar: calendar, locale: locale))"
        )
    }

    /// The custom name, else the muscle-group title ("Upper Body Workout").
    static func title(_ workout: CompletedWorkout) -> String {
        if let name = workout.workoutName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return MuscleGroupClassifier.classify(workout)
    }

    /// When the workout started: the recorded start, else the end less the watch duration, else
    /// the end less the duration estimated from set timing. Nil when nothing tells.
    static func startTime(_ workout: CompletedWorkout) -> Date? {
        if let started = workout.startedAt { return started }
        if let seconds = workout.matchedHealthKitDuration { return workout.date.addingTimeInterval(-TimeInterval(seconds)) }
        if let estimate = workout.estimatedDuration { return workout.date.addingTimeInterval(-estimate) }
        return nil
    }

    /// "Friday 13 Nov, 17:54 to 18:42", or "Friday 13 Nov, ended 18:42" without a start.
    static func dateLine(_ workout: CompletedWorkout, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: workout.date) == calendar.component(.year, from: now)
        let day = formatter(sameYear ? "EEEE d MMM" : "EEEE d MMM yyyy", locale: locale, calendar: calendar).string(from: workout.date)
        let time = formatter("HH:mm", locale: locale, calendar: calendar)
        let end = time.string(from: workout.date)
        if let start = startTime(workout) {
            return "\(day), \(time.string(from: start)) to \(end)"
        }
        return "\(day), ended \(end)"
    }

    /// The legacy sums: volume from weighted sets only, reps from bodyweight sets only.
    struct Totals: Equatable {
        var weightedVolumeKg: Double
        var bodyweightReps: Int
        var sets: Int
    }

    static func totals(_ entries: [WorkoutEntry]) -> Totals {
        var totals = Totals(weightedVolumeKg: 0, bodyweightReps: 0, sets: 0)
        for entry in entries {
            totals.sets += entry.sets.count
            for set in entry.sets {
                switch set.trackingMode {
                case .weighted: totals.weightedVolumeKg += Double(set.reps) * set.weight
                case .bodyweight: totals.bodyweightReps += set.reps
                case .timed, .distance: break
                }
            }
        }
        return totals
    }

    /// Duration in seconds: the watch's, else the estimate from the start or the set timing.
    static func durationSeconds(_ workout: CompletedWorkout) -> Int? {
        if let seconds = workout.matchedHealthKitDuration { return seconds }
        if let estimate = workout.estimatedDuration { return Int(estimate) }
        return nil
    }

    /// Average rest between sets: all rest over the gaps between sets (sets less exercises).
    static func averageRestSeconds(_ entries: [WorkoutEntry]) -> Int? {
        let totalRest = entries.reduce(0.0) { $0 + $1.totalRestTime }
        guard totalRest > 0 else { return nil }
        let sets = entries.reduce(0) { $0 + $1.sets.count }
        let average = totalRest / Double(max(1, sets - entries.count))
        return average > 0 ? Int(average) : nil
    }

    static func statRows(_ workout: CompletedWorkout, unit: WeightUnit) -> [[CutStatColumn]] {
        var time: [CutStatColumn] = []
        if let seconds = durationSeconds(workout) {
            time.append(CutStatColumn(value: duration(seconds), label: "Duration", unit: seconds >= 3600 ? "h" : nil))
        }
        if let kcal = workout.matchedHealthKitCalories {
            time.append(CutStatColumn(value: "\(kcal.safeInt)", label: "kcal"))
        }
        if let rest = averageRestSeconds(workout.entries) {
            time.append(CutStatColumn(value: duration(rest), label: "Avg rest"))
        }

        let totals = totals(workout.entries)
        var counts = [
            CutStatColumn(value: "\(workout.entries.count)", label: workout.entries.count == 1 ? "Exercise" : "Exercises"),
            CutStatColumn(value: "\(totals.sets)", label: totals.sets == 1 ? "Set" : "Sets")
        ]
        if totals.bodyweightReps > 0 {
            counts.append(CutStatColumn(value: "\(totals.bodyweightReps)", label: "Reps"))
        }
        if totals.weightedVolumeKg > 0 {
            counts.append(CutStatColumn(value: unit.formatVolumeValue(totals.weightedVolumeKg), label: "\(unit.label) volume"))
        }
        return [time, counts].filter { !$0.isEmpty }.map { padded($0) }
    }

    /// Rows split so none holds more than `maxColumns` (two at accessibility text sizes, where
    /// four labels no longer fit), each short row padded.
    static func columnRows(_ rows: [[CutStatColumn]], maxColumns: Int) -> [[CutStatColumn]] {
        let limit = max(1, maxColumns)
        var result: [[CutStatColumn]] = []
        for row in rows {
            let real = row.filter { !($0.value.isEmpty && $0.label.isEmpty) }
            guard real.count > limit else {
                result.append(row)
                continue
            }
            var start = 0
            while start < real.count {
                let chunk = Array(real[start..<min(start + limit, real.count)])
                result.append(chunk.count < limit && limit > 1 ? padded(chunk) : chunk)
                start += limit
            }
        }
        return result
    }

    /// One column keeps half the width instead of the whole row.
    static func padded(_ row: [CutStatColumn]) -> [CutStatColumn] {
        row.count == 1 ? row + [CutStatColumn(value: "", label: "")] : row
    }

    static func heartRate(_ workout: CompletedWorkout, calendar: Calendar, locale: Locale) -> CutWorkoutDetailModel.HeartRate? {
        guard let samples = workout.matchedHealthKitHeartRateSamples, !samples.isEmpty else { return nil }
        var stats: [CutStatColumn] = []
        if let min = workout.matchedHealthKitMinHeartRate, min > 0 { stats.append(CutStatColumn(value: "\(Int(min.rounded()))", label: "Min")) }
        if let avg = workout.matchedHealthKitHeartRate, avg > 0 { stats.append(CutStatColumn(value: "\(Int(avg.rounded()))", label: "Average")) }
        if let max = workout.matchedHealthKitMaxHeartRate, max > 0 { stats.append(CutStatColumn(value: "\(Int(max.rounded()))", label: "Max")) }
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        let bars = CutCardioLogic.heartRateBars(ordered)
        let time = formatter("HH:mm", locale: locale, calendar: calendar)
        return CutWorkoutDetailModel.HeartRate(
            stats: stats,
            bars: bars,
            startLabel: bars.isEmpty ? nil : ordered.first.map { time.string(from: $0.timestamp) },
            endLabel: bars.isEmpty ? nil : ordered.last.map { time.string(from: $0.timestamp) },
            sampleCount: samples.count == 1 ? "1 sample" : "\(samples.count) samples"
        )
    }

    /// The legacy zone list: zones with time in them, lowest first.
    static func zoneSection(_ zones: [HRZoneSummary], method: String?) -> CutWorkoutDetailModel.Zones {
        let present = zones.filter { $0.minutes > 0 }.sorted { $0.zone < $1.zone }
        let total = present.reduce(0) { $0 + $1.minutes }
        let rows: [CutCardioDetailModel.Zone] = total > 0
            ? present.map { .init(id: $0.zone, label: "Zone \($0.zone)", time: duration(Int(($0.minutes * 60).rounded())), fraction: $0.minutes / total) }
            : []
        return CutWorkoutDetailModel.Zones(rows: rows, method: method.map { "Zones: \($0)" })
    }

    /// The legacy summaries, built from HRZoneCalculator's boundaries and per-zone seconds.
    static func zoneSummaries(boundaries: [(zone: Int, name: String, range: String)], durations: [Int: TimeInterval]) -> [HRZoneSummary] {
        boundaries.compactMap { boundary in
            let seconds = durations[boundary.zone] ?? 0
            guard seconds > 0 else { return nil }
            return HRZoneSummary(zone: boundary.zone, name: boundary.name, minutes: seconds / 60,
                                 rangeDisplay: boundary.range, colorHex: "")
        }
        .sorted { $0.zone < $1.zone }
    }

    // MARK: Exercises

    static func exercise(_ entry: WorkoutEntry, unit: WeightUnit, opensSession: Bool) -> CutWorkoutDetailModel.Exercise {
        let reps = entry.sets.reduce(0) { $0 + $1.reps }
        let volume = entry.sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }
        var parts = [entry.sets.count == 1 ? "1 set" : "\(entry.sets.count) sets", reps == 1 ? "1 rep" : "\(reps) reps"]
        if volume > 0 { parts.append(unit.formatVolume(volume)) }

        var timing: String?
        if entry.totalDuration > 0 {
            timing = joinedTiming([("Total", entry.totalDuration), ("work", entry.totalWorkTime), ("rest", entry.totalRestTime)])
        }

        return CutWorkoutDetailModel.Exercise(
            id: entry.id,
            exerciseID: entry.exerciseID,
            name: entry.exerciseName,
            summary: parts.joined(separator: ", "),
            timing: timing,
            sets: entry.sets.enumerated().map { index, set in setRow(set, index: index, unit: unit) },
            opensSession: opensSession
        )
    }

    static func setRow(_ set: SetInput, index: Int, unit: WeightUnit) -> CutWorkoutDetailModel.SetRow {
        var parts: [(String, TimeInterval)] = []
        if let work = set.workDuration, work >= 1 { parts.append(("Work", work)) }
        if let rest = set.restAfterSeconds, rest > 0 { parts.append((parts.isEmpty ? "Rest" : "rest", TimeInterval(rest))) }
        return CutWorkoutDetailModel.SetRow(
            id: index,
            number: "\(index + 1)",
            value: setValue(set, unit: unit),
            tag: set.tag == .working ? nil : set.tag.label,
            timing: parts.isEmpty ? nil : joinedTiming(parts)
        )
    }

    /// The set as it was logged, in the user's unit.
    static func setValue(_ set: SetInput, unit: WeightUnit) -> String {
        switch set.trackingMode {
        case .weighted: return "\(unit.format(set.weight)) × \(set.reps)"
        case .bodyweight: return set.reps == 1 ? "1 rep" : "\(set.reps) reps"
        case .timed: return duration(set.durationSeconds)
        case .distance:
            return set.distanceMeters >= 1000
                ? String(format: "%.2f km", set.distanceMeters / 1000)
                : String(format: "%.0f m", set.distanceMeters)
        }
    }

    /// "Total 12:30, work 3:00, rest 9:30": zero parts are left out.
    private static func joinedTiming(_ parts: [(String, TimeInterval)]) -> String? {
        let shown = parts.filter { $0.1 >= 1 }.map { "\($0.0) \(duration(Int($0.1)))" }
        return shown.isEmpty ? nil : shown.joined(separator: ", ")
    }

    /// The legacy rule: an exercise opens the live session only while the viewed workout is the
    /// one still running (started within a minute of it, with the same exercises).
    static func opensLiveSession(workoutDate: Date, workoutExerciseIDs: [String],
                                 currentStartedAt: Date?, currentExerciseIDs: [String]) -> Bool {
        guard let currentStartedAt else { return false }
        guard abs(workoutDate.timeIntervalSince(currentStartedAt)) <= 60 else { return false }
        return Set(workoutExerciseIDs) == Set(currentExerciseIDs)
    }

    // MARK: Apple Health strength

    static func healthStrength(
        _ run: Run,
        existing: CompletedWorkout?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> CutHealthStrengthModel {
        let title = healthStrengthTitle(run, existing: existing)
        let start = run.date.addingTimeInterval(-TimeInterval(max(0, run.durationSec)))
        let sameYear = calendar.component(.year, from: run.date) == calendar.component(.year, from: now)
        let day = formatter(sameYear ? "EEEE d MMM" : "EEEE d MMM yyyy", locale: locale, calendar: calendar).string(from: start)
        let time = formatter("HH:mm", locale: locale, calendar: calendar)
        let dateLine = run.durationSec > 0
            ? "\(day), \(time.string(from: start)) to \(time.string(from: run.date))"
            : "\(day), \(time.string(from: run.date))"

        var stats: [CutStatColumn] = []
        if let kcal = run.calories, kcal > 0 { stats.append(CutStatColumn(value: "\(Int(kcal))", label: "kcal")) }
        if let avg = run.avgHeartRate, avg > 0 { stats.append(CutStatColumn(value: "\(Int(avg))", label: "Avg bpm")) }

        let type = run.workoutType?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CutHealthStrengthModel(
            title: title,
            dateLine: dateLine,
            sourceLine: [Optional("Apple Watch"), type?.isEmpty == false ? type : nil].compactMap { $0 }.joined(separator: ", "),
            hero: CutCardioHero(value: duration(run.durationSec), unit: run.durationSec >= 3600 ? "h" : "min"),
            stats: stats.count == 1 ? padded(stats) : stats,
            details: existing == nil ? .canAdd : .added,
            notes: run.notes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
            editTitle: existing == nil ? "Add exercise details" : "Edit workout",
            deleteTitle: "\(title), \(shortDate(run.date, now: now, calendar: calendar, locale: locale))"
        )
    }

    /// The converted workout's name or muscle-group title, else the Health name, else the type.
    static func healthStrengthTitle(_ run: Run, existing: CompletedWorkout?) -> String {
        if let existing { return title(existing) }
        if let name = run.workoutName, !name.isEmpty { return name }
        return run.workoutType ?? "Strength Workout"
    }

    /// The new workout the editor starts from when details are added to a Health workout.
    static func workout(from run: Run) -> CompletedWorkout {
        var workout = CompletedWorkout(
            date: run.date,
            startedAt: run.date.addingTimeInterval(-TimeInterval(run.durationSec)),
            entries: [],
            plannedWorkoutID: nil
        )
        workout.matchedHealthKitUUID = run.healthKitUUID
        workout.matchedHealthKitCalories = run.calories
        workout.matchedHealthKitHeartRate = run.avgHeartRate
        workout.matchedHealthKitDuration = run.durationSec
        return workout
    }

    // MARK: Formats

    /// "34:12" under an hour, "1:05" (h:mm) from an hour.
    static func duration(_ seconds: Int) -> String {
        CutCardioLogic.duration(seconds)
    }

    /// "13 Nov", or "13 Nov 2025" in another year.
    static func shortDate(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "d MMM" : "d MMM yyyy", locale: locale, calendar: calendar).string(from: date)
    }

    static func formatter(_ format: String, locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
