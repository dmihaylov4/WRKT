//
//  CutSetLoggingModel.swift
//  WRKT
//
//  Cut set logging: the plain values the screen shows, and the pure edits its controls make.
//  The edits reproduce the legacy set rows (SetRowUnified, BodyweightSetRow, TimedSetRow)
//  exactly, so the same input leaves the same SetInput behind under either look.
//

import Foundation

/// How the exercise is tracked, as AdaptiveSetRow decides it.
enum CutSetMode: Equatable {
    case weighted, bodyweight, timed

    /// AdaptiveSetRow.determineTrackingMode: the exercise first, then the set's own mode.
    static func resolve(isTimed: Bool, isBodyweight: Bool, isWeighted: Bool, fallback: TrackingMode) -> CutSetMode {
        if isTimed { return .timed }
        if isBodyweight { return .bodyweight }
        if isWeighted { return .weighted }
        return from(fallback)
    }

    static func from(_ mode: TrackingMode) -> CutSetMode {
        switch mode {
        case .timed: .timed
        case .bodyweight: .bodyweight
        case .weighted, .distance: .weighted
        }
    }

    var trackingMode: TrackingMode {
        switch self {
        case .weighted: .weighted
        case .bodyweight: .bodyweight
        case .timed: .timed
        }
    }
}

/// Rest advice under the inputs (the legacy rest recommendation banner).
enum CutRestZone: Equatable {
    case strength, pump

    var tip: String { self == .strength ? "4 min rest for strength sets" : "1 min rest for high-rep sets" }
    var dismissKey: String { self == .strength ? "rest_rec_strength_dismiss_count" : "rest_rec_pump_dismiss_count" }
}

/// What the action bar does.
enum CutSetLoggingBar: Equatable {
    /// Logs the active set. `restLine` is "Rest 2:00 starts after", or nil when no rest follows.
    case logSet(restLine: String?)
    /// Every set is logged and another exercise is unfinished.
    case nextExercise(name: String)
    /// Every set is logged and nothing else is open: closes the screen like Done.
    case done
    /// A timed hold is running: the bar is hidden, as the legacy log button was.
    case hidden
    /// The exercise has no sets yet (an entry added without any): the bar adds the first.
    case addSet
}

/// Everything the Cut set logging screen shows, apart from the editable sets.
struct CutSetLoggingModel: Equatable {
    var exerciseName: String
    var mode: CutSetMode
    var unit: WeightUnit
    /// "Exercise 1 of 6, set 3 of 4", or "Set 3 of 4" outside a workout.
    var metaLine: String
    /// The hero's one supporting line: target, record, last.
    var supportLine: String?
    /// Exercise position in the workout, when it is part of one.
    var exercisePosition: (index: Int, count: Int)?
    var canSuperset: Bool
    var isInSuperset: Bool
    /// Planned rest after a set, in seconds; nil when the rest timer is off.
    var restSeconds: Int?
    /// Sessions in a row at the same weight; the plateau row shows from 3.
    var plateauSessions: Int
    /// The next unfinished exercise in the workout, if any.
    var nextExercise: (id: UUID, name: String)?
    /// Weight step in the display unit.
    var weightStep: Double
    /// The weight step setting in kg (the plateau row adds it as is, as the legacy banner did).
    var weightStepKg: Double
    /// The exercise's rest duration whether or not the timer is on, for the rest advice row.
    var adviceRestSeconds: Int
    /// The legacy timed row's default duration for new sets.
    var defaultDurationSeconds: Int?

    static func == (lhs: CutSetLoggingModel, rhs: CutSetLoggingModel) -> Bool {
        lhs.exerciseName == rhs.exerciseName && lhs.mode == rhs.mode && lhs.unit == rhs.unit
            && lhs.metaLine == rhs.metaLine && lhs.supportLine == rhs.supportLine
            && lhs.exercisePosition?.index == rhs.exercisePosition?.index
            && lhs.exercisePosition?.count == rhs.exercisePosition?.count
            && lhs.canSuperset == rhs.canSuperset && lhs.isInSuperset == rhs.isInSuperset
            && lhs.restSeconds == rhs.restSeconds && lhs.plateauSessions == rhs.plateauSessions
            && lhs.nextExercise?.id == rhs.nextExercise?.id && lhs.weightStep == rhs.weightStep
            && lhs.weightStepKg == rhs.weightStepKg && lhs.adviceRestSeconds == rhs.adviceRestSeconds
            && lhs.defaultDurationSeconds == rhs.defaultDurationSeconds
    }
}

// MARK: - Copy

enum CutSetLoggingLogic {
    static func metaLine(setIndex: Int, setCount: Int, exercise position: (index: Int, count: Int)?) -> String {
        let set = setCount == 0 ? "no sets yet" : "set \(min(setIndex + 1, setCount)) of \(setCount)"
        guard let position, position.count > 1 else { return "S" + set.dropFirst() }
        return "Exercise \(position.index + 1) of \(position.count), \(set)"
    }

    /// One line under the exercise name, from what the legacy header and rows showed:
    /// weighted: the progression target and the estimated one-rep max ("PR"),
    /// bodyweight: the rep record and the last working set.
    static func supportLine(
        mode: CutSetMode,
        unit: WeightUnit,
        progression: (weightKg: Double, reps: Int)?,
        bestE1RMKg: Double?,
        prReps: Int?,
        lastReps: Int?
    ) -> String? {
        var parts: [String] = []
        switch mode {
        case .weighted:
            if let progression {
                parts.append("Target \(nb(unit.format(progression.weightKg)))\u{00A0}x\u{00A0}\(progression.reps)")
            }
            if let bestE1RMKg, bestE1RMKg > 0 {
                let display = unit == .kg ? bestE1RMKg : bestE1RMKg * 2.20462
                parts.append("PR \(String(format: "%.0f", display))\u{00A0}\(unit.rawValue)")
            }
        case .bodyweight:
            if let prReps, prReps > 0 { parts.append("Record \(prReps) reps") }
            if prReps != nil, let lastReps, lastReps > 0 { parts.append("last \(lastReps) reps") }
        case .timed:
            break
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    /// "Rest 2:00 starts after", or nil when the rest timer is off.
    static func restLine(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "Rest \(clock(seconds)) starts after"
    }

    static func bar(
        sets: [SetInput],
        activeSetIndex: Int,
        restSeconds: Int?,
        nextExerciseName: String?,
        holdRunning: Bool
    ) -> CutSetLoggingBar {
        if holdRunning { return .hidden }
        if sets.isEmpty { return .addSet }
        let allDone = !sets.isEmpty && sets.allSatisfy(\.isCompleted)
        if allDone {
            if let nextExerciseName { return .nextExercise(name: nextExerciseName) }
            return .done
        }
        if let active = sets[safe: activeSetIndex], active.isGhost && !active.isCompleted {
            // The legacy rows hid the log button on ghost sets.
            return .done
        }
        return .logSet(restLine: restLine(seconds: restSeconds))
    }

    /// The label under a set segment: a done set's values, "Now", or "Set 4".
    static func segmentLabel(_ set: SetInput, index: Int, isActive: Bool, mode: CutSetMode, unit: WeightUnit) -> String {
        if set.isCompleted { return compactValue(set, mode: mode, unit: unit) }
        if isActive { return "Now" }
        return "Set \(index + 1)"
    }

    /// "85 x 6", "12 reps", "0:45": a set's values without the unit.
    static func compactValue(_ set: SetInput, mode: CutSetMode, unit: WeightUnit) -> String {
        switch mode {
        case .weighted:
            return "\(number(unit.displayValue(set.weight))) x \(set.reps)"
        case .bodyweight:
            return "\(set.reps) reps"
        case .timed:
            return clock(set.durationSeconds)
        }
    }

    /// A set row's value: "85 kg x 6", "12 reps", "0:45".
    static func rowValue(_ set: SetInput, mode: CutSetMode, unit: WeightUnit) -> String {
        switch mode {
        case .weighted:
            return "\(nb(unit.format(set.weight)))\u{00A0}x\u{00A0}\(set.reps)"
        case .bodyweight, .timed:
            return compactValue(set, mode: mode, unit: unit)
        }
    }

    /// One sentence for VoiceOver on the set segments.
    static func segmentsAccessibilityValue(sets: [SetInput], activeSetIndex: Int) -> String {
        let done = sets.filter(\.isCompleted).count
        var text = "\(done) of \(sets.count) done"
        if sets.indices.contains(activeSetIndex), !sets[activeSetIndex].isCompleted {
            text += ", set \(activeSetIndex + 1) current"
        }
        return text
    }

    /// The next unfinished exercise after the current one, wrapping to the start.
    static func nextExercise(in entries: [WorkoutEntry], after currentID: UUID?) -> WorkoutEntry? {
        let open = { (entry: WorkoutEntry) in entry.id != currentID && !(!entry.sets.isEmpty && entry.sets.allSatisfy(\.isCompleted)) }
        guard let currentID, let index = entries.firstIndex(where: { $0.id == currentID }) else {
            return entries.first(where: open)
        }
        let ordered = entries[(index + 1)...] + entries[..<index]
        return ordered.first(where: open)
    }

    /// Weight value in the display unit, as the legacy steppers printed it ("85", "87.5").
    static func weightNumeral(_ kg: Double, unit: WeightUnit) -> String {
        number(unit.displayValue(kg))
    }

    static func number(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    /// m:ss for durations under an hour, h:mm from an hour.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total >= 3600 { return String(format: "%d:%02d", total / 3600, (total % 3600) / 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The plateau row's button: the step in the display unit ("+2.5 kg", "+5.512 lb").
    static func plateauButtonTitle(stepKg: Double, unit: WeightUnit) -> String {
        "+\(String(format: "%.4g", unit == .kg ? stepKg : stepKg * 2.20462))\u{00A0}\(unit.rawValue)"
    }

    static func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    /// No-break spaces keep a value and its unit together when a line wraps.
    static func nb(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

// MARK: - Edits (mirroring the legacy set rows)

enum CutSetEditing {
    /// The legacy RPE chips.
    static let rpeValues: [Double] = [6.0, 7.0, 8.0, 8.5, 9.0, 9.5, 10.0]

    /// SetRowUnified.step: the weight step in the display unit.
    static func weightStep(unit: WeightUnit, weightStepKg: Double) -> Double {
        if unit == .kg { return weightStepKg }
        switch weightStepKg {
        case 0.5: return 1.25
        case 1.0: return 2.5
        default: return 5.0
        }
    }

    static func canDecrementReps(_ set: SetInput) -> Bool { !set.isGhost && set.reps > 1 }
    static func canIncrement(_ set: SetInput) -> Bool { !set.isGhost }
    static func canDecrementWeight(_ set: SetInput, unit: WeightUnit) -> Bool {
        !set.isGhost && unit.displayValue(set.weight) > 0
    }

    static func decrementReps(_ set: inout SetInput, mode: CutSetMode) {
        guard set.reps > 1 else { return }
        set.reps -= 1
        if mode == .weighted { set.autoWeight = false }
        set.isAutoGeneratedPlaceholder = false
    }

    static func incrementReps(_ set: inout SetInput, mode: CutSetMode) {
        set.reps += 1
        if mode == .weighted { set.autoWeight = false }
        set.isAutoGeneratedPlaceholder = false
    }

    /// Typed reps. The weighted row cleared autoWeight; the bodyweight row only the placeholder flag.
    static func setReps(_ set: inout SetInput, to reps: Int, mode: CutSetMode) {
        set.reps = reps
        if mode == .weighted { set.autoWeight = false }
        set.isAutoGeneratedPlaceholder = false
    }

    static func stepWeight(_ set: inout SetInput, by delta: Double, unit: WeightUnit) {
        let display = unit.displayValue(set.weight)
        let newWeight = delta < 0 ? max(0, display + delta) : display + delta
        set.weight = unit == .kg ? newWeight : newWeight / 2.20462
        set.autoWeight = false
        set.isAutoGeneratedPlaceholder = false
    }

    /// Typed weight in the display unit.
    static func setWeight(_ set: inout SetInput, displayValue: Double, unit: WeightUnit) {
        let kg = unit == .kg ? displayValue : displayValue / 2.20462
        set.weight = max(0, kg)
        set.autoWeight = false
        set.isAutoGeneratedPlaceholder = false
    }

    /// The timed row's quick buttons: -15, -5, +5, +15 seconds.
    static let durationSteps: [Int] = [-15, -5, 5, 15]

    static func canStepDuration(_ set: SetInput, by delta: Int) -> Bool {
        delta > 0 || set.durationSeconds >= -delta
    }

    static func stepDuration(_ set: inout SetInput, by delta: Int) {
        set.durationSeconds = max(0, set.durationSeconds + delta)
        set.isAutoGeneratedPlaceholder = false
    }

    static func toggleRPE(_ set: inout SetInput, _ value: Double) {
        set.rpe = set.rpe == value ? nil : value
    }

    /// The legacy rows activated a set on tap: the weighted row only when it was not already active,
    /// the bodyweight and timed rows whenever the set was not completed.
    static func canActivate(_ set: SetInput, isActive: Bool, mode: CutSetMode) -> Bool {
        guard !set.isCompleted else { return false }
        return mode == .weighted ? !isActive : true
    }

    /// AdaptiveSetRow.syncTrackingMode, then the row's own seeding on appear.
    static func prepare(
        _ set: inout SetInput,
        mode: CutSetMode,
        defaultDurationSeconds: Int?,
        lastWorkingSet: (reps: Int, weightKg: Double)?,
        suggestedWeightKg: (Int) -> Double?,
        unit: WeightUnit,
        weightStep: Double
    ) {
        // syncTrackingMode
        if set.trackingMode != mode.trackingMode {
            set.trackingMode = mode.trackingMode
            switch mode {
            case .timed:
                if set.durationSeconds == 0, let defaultDurationSeconds { set.durationSeconds = defaultDurationSeconds }
            case .bodyweight:
                set.weight = 0
                if set.reps == 0 { set.reps = 10 }
            case .weighted:
                break
            }
        }
        switch mode {
        case .timed:
            // TimedSetRow.seedFromDefaultIfNeeded
            if set.durationSeconds == 0, let defaultDurationSeconds { set.durationSeconds = defaultDurationSeconds }
        case .bodyweight:
            // BodyweightSetRow.seedFromMemoryIfNeeded
            guard set.tag == .working, !set.didSeedFromMemory, set.reps == 0, set.weight == 0 else { return }
            set.reps = lastWorkingSet?.reps ?? 10
            set.weight = 0
            set.didSeedFromMemory = true
        case .weighted:
            // SetRowUnified.seedFromMemoryIfNeeded
            if set.tag == .working, set.autoWeight, !set.didSeedFromMemory, set.reps == 0, set.weight == 0 {
                if let last = lastWorkingSet {
                    set.reps = last.reps
                    set.weight = last.weightKg
                } else {
                    set.reps = 10
                }
                set.didSeedFromMemory = true
            }
            // SetRowUnified.applyWeightSuggestion (working sets only)
            guard set.tag == .working, set.autoWeight else { return }
            if set.reps <= 0 { set.reps = 10 }
            if let w = suggestedWeightKg(set.reps) {
                let snapped: Double
                if unit == .kg {
                    snapped = (w / weightStep).rounded() * weightStep
                } else {
                    let lb = w * 2.20462
                    snapped = ((lb / weightStep).rounded() * weightStep) / 2.20462
                }
                set.weight = max(0, snapped)
            }
        }
    }

    /// SetRowUnified.evaluateRestZone: advice when the planned rest does not suit the reps.
    static func restZone(reps: Int, currentRestSeconds: Int, tag: SetTag, isGhost: Bool, isActive: Bool,
                         strengthDismissCount: Int, pumpDismissCount: Int) -> CutRestZone? {
        guard tag == .working, !isGhost, isActive else { return nil }
        let zone: CutRestZone?
        if reps <= 5, abs(currentRestSeconds - 240) > 30 {
            zone = .strength
        } else if reps > 12, abs(currentRestSeconds - 60) > 30 {
            zone = .pump
        } else {
            zone = nil
        }
        guard let zone else { return nil }
        let count = zone == .strength ? strengthDismissCount : pumpDismissCount
        return count < 3 ? zone : nil
    }
}
