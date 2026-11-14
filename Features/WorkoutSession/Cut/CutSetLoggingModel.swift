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
    /// The tip as the second sentence of the rest line over the pill.
    /// No-break space and hyphen keep "1 min" and "high-rep" whole when the line wraps.
    var followUp: String {
        self == .strength ? "Strength sets do better with 4\u{00A0}min." : "1\u{00A0}min is enough for high\u{2011}rep sets."
    }
    var dismissKey: String { self == .strength ? "rest_rec_strength_dismiss_count" : "rest_rec_pump_dismiss_count" }
}

/// What the bottom action pill does.
enum CutSetLoggingBar: Equatable {
    /// Logs the active set. `restLine` is "Rest 2:00 starts after", or nil when no rest follows.
    case logSet(restLine: String?)
    /// Every set is logged and another exercise is unfinished.
    case nextExercise(name: String)
    /// No pill: a timed hold is running, or the active set is a ghost (the legacy rows hid the
    /// log button in both cases).
    case hidden
    /// Adds a set: the exercise has no sets yet, or every set is logged and nothing else is open
    /// (the top bar's Done finishes the exercise, so the pill offers another set instead).
    case addSet
}

/// What the legacy header said about the exercise, in two parts: the record ("PR 100 kg"), which
/// joins the lime set line, and the rest ("Target 87.5 kg x 6", "Record 15 reps, last 12 reps"),
/// which stays a grey line under the name.
struct CutExerciseSupport: Equatable {
    var detail: String?
    var pr: String?

    static let none = CutExerciseSupport(detail: nil, pr: nil)

    /// Both parts on one line, as the resting state shows them.
    var line: String? {
        let parts = [detail, pr].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Everything the Cut set logging screen shows, apart from the editable sets.
struct CutSetLoggingModel: Equatable {
    var exerciseName: String
    var mode: CutSetMode
    var unit: WeightUnit
    /// What the screen says about the exercise: target, record, last.
    var support: CutExerciseSupport
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

    /// The support on one line: "Target 87.5 kg x 6, PR 100 kg".
    var supportLine: String? { support.line }

    static func == (lhs: CutSetLoggingModel, rhs: CutSetLoggingModel) -> Bool {
        lhs.exerciseName == rhs.exerciseName && lhs.mode == rhs.mode && lhs.unit == rhs.unit
            && lhs.support == rhs.support
            && lhs.canSuperset == rhs.canSuperset && lhs.isInSuperset == rhs.isInSuperset
            && lhs.restSeconds == rhs.restSeconds && lhs.plateauSessions == rhs.plateauSessions
            && lhs.nextExercise?.id == rhs.nextExercise?.id && lhs.weightStep == rhs.weightStep
            && lhs.weightStepKg == rhs.weightStepKg && lhs.adviceRestSeconds == rhs.adviceRestSeconds
            && lhs.defaultDurationSeconds == rhs.defaultDurationSeconds
    }
}

// MARK: - Copy

enum CutSetLoggingLogic {
    /// The lime line over the exercise name while entering a set: "Set 3 of 4" while sets follow
    /// the active one, "Set 4" on the last set (nothing planned beyond it), "No sets yet".
    static func setLine(setIndex: Int, setCount: Int) -> String {
        guard setCount > 0 else { return "No sets yet" }
        let number = min(max(0, setIndex), setCount - 1) + 1
        return number < setCount ? "Set \(number) of \(setCount)" : "Set \(number)"
    }

    /// The lime line while not resting: the active set ("Set 3 of 4", "Set 2"), or how many sets
    /// are logged once every set is ("4 sets logged"), followed by the record when there is one
    /// ("Set 3 of 4, PR 100 kg").
    static func entryLine(sets: [SetInput], activeSetIndex: Int, pr: String? = nil) -> String {
        let line = !sets.isEmpty && sets.allSatisfy(\.isCompleted)
            ? loggedCount(sets.count)
            : setLine(setIndex: activeSetIndex, setCount: sets.count)
        guard let pr, !pr.isEmpty else { return line }
        return "\(line), \(pr)"
    }

    /// "1 set logged", "4 sets logged".
    static func loggedCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "set" : "sets") logged"
    }

    /// The one line at the top while resting: "Bench Press, set 3 of 4" for the set that
    /// follows, or "Dumbbell Curl, 1 set logged" once every set is logged.
    static func restingLine(exerciseName: String, sets: [SetInput], activeSetIndex: Int) -> String {
        if let index = CutRestLogic.nextIndex(sets: sets, activeSetIndex: activeSetIndex) {
            let line = setLine(setIndex: index, setCount: sets.count)
            return "\(exerciseName), \(line.prefix(1).lowercased())\(line.dropFirst())"
        }
        return "\(exerciseName), \(loggedCount(sets.filter(\.isCompleted).count))"
    }

    /// What the legacy header and rows showed about the exercise:
    /// weighted: the progression target (detail) and the estimated one-rep max (PR),
    /// bodyweight: the rep record and the last working set (detail, no PR).
    static func support(
        mode: CutSetMode,
        unit: WeightUnit,
        progression: (weightKg: Double, reps: Int)?,
        bestE1RMKg: Double?,
        prReps: Int?,
        lastReps: Int?
    ) -> CutExerciseSupport {
        switch mode {
        case .weighted:
            let target = progression.map {
                "Target \(nb(unit.format($0.weightKg)))\u{00A0}x\u{00A0}\($0.reps)"
            }
            var pr: String?
            if let bestE1RMKg, bestE1RMKg > 0 {
                let display = unit == .kg ? bestE1RMKg : bestE1RMKg * 2.20462
                pr = "PR \(String(format: "%.0f", display))\u{00A0}\(unit.rawValue)"
            }
            return CutExerciseSupport(detail: target, pr: pr)
        case .bodyweight:
            var parts: [String] = []
            if let prReps, prReps > 0 { parts.append("Record \(prReps) reps") }
            if prReps != nil, let lastReps, lastReps > 0 { parts.append("last \(lastReps) reps") }
            return CutExerciseSupport(detail: parts.isEmpty ? nil : parts.joined(separator: ", "), pr: nil)
        case .timed:
            return .none
        }
    }

    /// The support on one line: "Target 87.5 kg x 6, PR 100 kg".
    static func supportLine(
        mode: CutSetMode,
        unit: WeightUnit,
        progression: (weightKg: Double, reps: Int)?,
        bestE1RMKg: Double?,
        prReps: Int?,
        lastReps: Int?
    ) -> String? {
        support(mode: mode, unit: unit, progression: progression, bestE1RMKg: bestE1RMKg,
                prReps: prReps, lastReps: lastReps).line
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
        if sets.allSatisfy(\.isCompleted) {
            if let nextExerciseName { return .nextExercise(name: nextExerciseName) }
            return .addSet
        }
        if let active = sets[safe: activeSetIndex], active.isGhost && !active.isCompleted {
            // The legacy rows hid the log button on ghost sets.
            return .hidden
        }
        return .logSet(restLine: restLine(seconds: restSeconds))
    }

    /// The pill is filled lime unless a rest runs; then it is a lime outline.
    static func pillTone(isResting: Bool) -> CutActionPillButtonStyle.Tone {
        isResting ? .outline : .filled
    }

    /// The one line above the pill: the rest that logging starts (not while a rest already runs),
    /// or the next exercise's name. A rest tip that joins the line follows as a second sentence:
    /// "Rest 1:45 starts after. 1 min is enough for high-rep sets."
    static func pillLine(_ bar: CutSetLoggingBar, isResting: Bool, tip: CutRestZone? = nil) -> String? {
        let joined = tipJoinsPillLine(bar, isResting: isResting) ? tip : nil
        switch bar {
        case .logSet(let restLine):
            if isResting { return nil }
            guard let joined else { return restLine }
            guard let restLine else { return joined.tip }
            return "\(restLine). \(joined.followUp)"
        case .nextExercise(let name): return name
        case .addSet, .hidden: return nil
        }
    }

    /// The rest tip joins the line over the pill while a set is being entered with Log set;
    /// otherwise (resting, next exercise, add set) it stays an advice row in the list.
    static func tipJoinsPillLine(_ bar: CutSetLoggingBar, isResting: Bool) -> Bool {
        guard !isResting, case .logSet = bar else { return false }
        return true
    }

    /// The RPE pill under the inputs: "RPE" until a value is chosen, then "RPE 8".
    static func rpePillTitle(_ rpe: Double?) -> String {
        guard let rpe else { return "RPE" }
        return "RPE \(formatRPE(rpe))"
    }

    /// The RPE pill's VoiceOver value: the chosen number, or "Not set".
    static func rpeAccessibilityValue(_ rpe: Double?) -> String {
        rpe.map(formatRPE) ?? "Not set"
    }

    /// The RPE pill and its values show where the legacy RPE chips did: weighted working sets
    /// not yet logged.
    static func showsRPE(mode: CutSetMode, set: SetInput?) -> Bool {
        guard mode == .weighted, let set else { return false }
        return set.tag == .working && !set.isCompleted
    }

    /// How many RPE values go in a row: all of them while the widest fits an equal share of the
    /// width, otherwise the fewest rows (two, then three...) whose equal cells hold it.
    static func rpeColumns(count: Int, widestValue: Double, width: Double, spacing: Double) -> Int {
        guard count > 0 else { return 1 }
        for rows in 1...count {
            let columns = Int((Double(count) / Double(rows)).rounded(.up))
            let cell = (width - spacing * Double(columns - 1)) / Double(columns)
            if widestValue <= cell { return columns }
        }
        return 1
    }

    /// The supporting line under the next set while resting: "Working set. Target 87.5 kg x 6".
    static func nextSetSupport(tag: SetTag, supportLine: String?) -> String {
        let kind = "\(tag.label) set."
        guard let supportLine, !supportLine.isEmpty else { return kind }
        return "\(kind) \(supportLine)"
    }

    /// Shown under the last logged set once every set is logged.
    static let allLoggedSupport = "Add a set to go again, or tap Done to finish this exercise."

    /// The label under a set segment: a done set's values, "Now" ("Next" while resting), or "Set 4".
    static func segmentLabel(_ set: SetInput, index: Int, isActive: Bool, mode: CutSetMode, unit: WeightUnit,
                             isResting: Bool = false) -> String {
        if set.isCompleted { return compactValue(set, mode: mode, unit: unit) }
        if isActive { return isResting ? "Next" : "Now" }
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
