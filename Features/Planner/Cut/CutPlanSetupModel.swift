//
//  CutPlanSetupModel.swift
//  WRKT
//
//  The Cut new program flow: which screen collects what, and the pure rules behind each one.
//  Every value still lands in the legacy PlanConfig, every rule comes from PlanConfigValidator,
//  and the plan is built by the legacy generate path, so a Cut plan saves exactly like a legacy one.
//
//  Predefined path, four screens: 1 split, 2 days and length (legacy steps 2, 3 and 5),
//  3 one day's exercises (legacy step 4, only when opened from the review), 4 review (legacy step 6).
//  Custom path, five screens: 1 split, 2 name and parts, 3 exercises, 4 days and length
//  (legacy steps 4 and 5), 5 review.
//

import Foundation

/// The screens of the Cut new program flow.
enum CutPlanSetupScreen: Hashable {
    case split
    /// Custom path: the split's name and its parts.
    case customName
    /// Custom path: the exercises of every part.
    case customExercises
    case days
    /// Predefined path: one template day's exercises, opened from the review.
    case customize(String)
    case review
}

/// What the days screen holds beyond PlanConfig.
struct CutPlanSetupDraft: Equatable {
    /// Weekdays the user trains on, 0 Monday to 6 Sunday. Nil until a day is tapped, so an edited
    /// plan keeps its loaded rest pattern untouched unless the user changes it.
    var weekdays: Set<Int>? = nil
    /// The date the first training day is counted from, captured when the days are first touched.
    var baseStart: Date? = nil
}

/// How the flow was opened: changes the button and the replace line on the review.
enum CutPlanSetupPurpose: Equatable {
    case create, edit
}

// MARK: - Screen models

struct CutPlanSplitModel: Equatable {
    struct Option: Equatable, Identifiable {
        enum Kind: Equatable { case template, buildOwn, saved }
        var id: String
        var title: String
        var line: String
        var isSelected: Bool
        var kind: Kind
    }
    var templates: [Option]
    var buildOwn: Option
    /// The user's saved custom splits, shown under "Your splits".
    var saved: [Option]
    var canProceed: Bool
}

struct CutPlanDaysModel: Equatable {
    struct Tile: Equatable, Identifiable {
        var id: Int
        var short: String
        var spoken: String
        var isTraining: Bool
    }
    var tiles: [Tile]
    var countLine: String
    /// The count is not one this split runs at.
    var countIsWarning: Bool
    var weekOptions: [Int]
    var selectedWeeks: Int?
    var canProceed: Bool
}

struct CutPlanReviewModel: Equatable {
    struct Day: Equatable, Identifiable {
        var id: Int
        /// The template day id (predefined) or the part name (custom) the row edits.
        var dayID: String
        var title: String
        var line: String
    }
    var title: String
    var line: String
    var days: [Day]
    var startLine: String
    var replaceLine: String?
    var buttonTitle: String
    var canStart: Bool
}

struct CutPlanCustomizeModel: Equatable {
    struct Row: Equatable, Identifiable {
        var id: Int
        var name: String
        var line: String
    }
    var title: String
    var rows: [Row]
}

struct CutPlanCustomNameModel: Equatable {
    var name: String
    var partCount: Int
    var partNames: [String]
    var showsQuickFill: Bool
    var hint: String?
    var canProceed: Bool
}

struct CutPlanCustomExercisesModel: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String { name }
        var name: String
        var line: String
        var isComplete: Bool
    }
    var rows: [Row]
    var canProceed: Bool
}

// MARK: - Logic

enum CutPlanSetupLogic {
    /// Step5ProgramLength's options.
    nonisolated static let weekOptions = [4, 6, 8, 12]
    /// CustomSplitStep3FrequencyAndRest's options.
    nonisolated static let customFrequencies = [3, 4, 5, 6]
    nonisolated static let partOptions = [2, 3, 4]

    /// Step2TrainingFrequency's options for a template.
    static func frequencies(for template: SplitTemplate?) -> [Int] {
        guard let template else { return [3, 4, 5, 6] }
        switch template.id {
        case "ppl": return [3, 6]
        case "upper-lower": return [2, 4]
        case "full-body": return [2, 3, 4]
        case "bro-split": return [5, 6]
        default: return [3, 4, 5, 6]
        }
    }

    static func frequencies(_ config: PlanConfig) -> [Int] {
        config.isCreatingCustom ? customFrequencies : frequencies(for: config.selectedTemplate)
    }

    // MARK: Steps

    static func path(isCustom: Bool) -> [CutPlanSetupScreen] {
        isCustom ? [.split, .customName, .customExercises, .days, .review] : [.split, .days, .review]
    }

    /// "n of N" for the header. Customising a day is step 3 of 4 on the predefined path.
    static func step(_ screen: CutPlanSetupScreen, isCustom: Bool) -> (number: Int, total: Int) {
        if isCustom {
            let order: [CutPlanSetupScreen] = [.split, .customName, .customExercises, .days, .review]
            return ((order.firstIndex(of: screen) ?? 0) + 1, 5)
        }
        switch screen {
        case .split: return (1, 4)
        case .days: return (2, 4)
        case .customize: return (3, 4)
        default: return (4, 4)
        }
    }

    /// The legacy carousel steps a screen covers. Their PlanConfigValidator rules decide Next.
    static func legacySteps(_ screen: CutPlanSetupScreen, isCustom: Bool) -> [Int] {
        switch (screen, isCustom) {
        case (.split, _): return [0]
        case (.customName, _): return [1]
        case (.customExercises, _): return [2]
        case (.days, true): return [3, 4]
        case (.days, false): return [1, 2, 4]
        case (.customize, _): return []
        case (.review, _): return [5]
        }
    }

    static func next(after screen: CutPlanSetupScreen, isCustom: Bool) -> CutPlanSetupScreen? {
        if case .customize = screen { return .review }
        let order = path(isCustom: isCustom)
        guard let index = order.firstIndex(of: screen), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    /// Nil on the first screen: the header button closes the flow there.
    static func back(from screen: CutPlanSetupScreen, isCustom: Bool) -> CutPlanSetupScreen? {
        if case .customize = screen { return .review }
        let order = path(isCustom: isCustom)
        guard let index = order.firstIndex(of: screen), index > 0 else { return nil }
        return order[index - 1]
    }

    static func canProceed(_ screen: CutPlanSetupScreen, config: PlanConfig, draft: CutPlanSetupDraft) -> Bool {
        if screen == .review { return config.isValid }
        let rules = legacySteps(screen, isCustom: config.isCreatingCustom)
            .allSatisfy { PlanConfigValidator.canProceedFromStep($0, config: config) }
        guard screen == .days else { return rules }
        // Tapped days must give a count this split runs at, as the legacy frequency step offered.
        if let weekdays = draft.weekdays { return rules && frequencies(config).contains(weekdays.count) }
        return rules
    }

    /// Leaving the days screen: the exercises stay the template's unless a day is customised,
    /// which the legacy flow asked as "Use default exercises".
    static func prepareForReview(_ config: PlanConfig) {
        if !config.isCreatingCustom && config.wantsToCustomize == nil { config.wantsToCustomize = false }
    }

    // MARK: Weekdays

    /// 0 Monday to 6 Sunday.
    static func weekdayIndex(_ date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// The seven-day cycle a rest placement produces: true for a training day. The same layout
    /// as RestDayStrategyFactory's strategies (proved in tests); workouts fill training days in order.
    static func cyclePattern(_ placement: PlanConfig.RestDayPlacement?, trainingDays: Int) -> [Bool] {
        guard let placement else { return Array(repeating: false, count: 7) }
        let n = max(0, trainingDays)
        switch placement {
        case .afterEachWorkout:
            var pattern: [Bool] = []
            var added = 0
            let totalRest = 7 - n
            while pattern.count < 7 {
                if added < n {
                    pattern.append(true)
                    added += 1
                    if pattern.count - added < totalRest && pattern.count < 7 { pattern.append(false) }
                } else {
                    pattern.append(false)
                }
            }
            return pattern
        case .afterEverySecondWorkout:
            var pattern: [Bool] = []
            var added = 0
            var sinceRest = 0
            while pattern.count < 7 && added < n {
                pattern.append(true)
                added += 1
                sinceRest += 1
                if sinceRest >= 2 && pattern.count < 7 {
                    pattern.append(false)
                    sinceRest = 0
                }
            }
            return pattern + Array(repeating: false, count: 7 - pattern.count)
        case .weekends:
            let training: Set<Int>
            switch n {
            case 2: training = [0, 3]
            case 3: training = [0, 2, 4]
            case 4: training = [0, 1, 3, 4]
            case 5: training = [0, 1, 2, 3, 4]
            default: training = Set(0..<min(n, 6))
            }
            return (0..<7).map { training.contains($0) }
        case .custom(let rest):
            var workouts = 0
            return (0..<7).map { day in
                if rest.contains(day) { return false }
                guard workouts < n else { return false }
                workouts += 1
                return true
            }
        }
    }

    /// The weekdays shown as training days. Untouched, they come from the loaded rest pattern:
    /// the legacy save puts the first workout on the start date.
    static func weekdays(_ config: PlanConfig, draft: CutPlanSetupDraft, calendar: Calendar) -> Set<Int> {
        if let weekdays = draft.weekdays { return weekdays }
        let pattern = cyclePattern(config.restDayPlacement, trainingDays: config.trainingDaysPerWeek)
        guard let first = pattern.firstIndex(of: true) else { return [] }
        let start = weekdayIndex(config.startDate, calendar: calendar)
        return Set(pattern.indices.filter { pattern[$0] }.map { ((start - first + $0) % 7 + 7) % 7 })
    }

    /// The first date on or after `start` that falls on one of `weekdays`.
    static func firstTrainingDate(from start: Date, weekdays: Set<Int>, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: start)
        return (0..<7).lazy
            .compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            .first { weekdays.contains(weekdayIndex($0, calendar: calendar)) }
    }

    /// Writes tapped weekdays into PlanConfig as the legacy custom rest pattern. The cycle starts on
    /// the first training day on or after the chosen start, so each workout lands on its weekday.
    static func setWeekdays(_ weekdays: Set<Int>, config: PlanConfig, draft: inout CutPlanSetupDraft, calendar: Calendar) {
        if draft.baseStart == nil { draft.baseStart = config.startDate }
        draft.weekdays = weekdays
        apply(draft, to: config, calendar: calendar)
    }

    static func toggle(_ weekday: Int, config: PlanConfig, draft: inout CutPlanSetupDraft, calendar: Calendar) {
        var days = self.weekdays(config, draft: draft, calendar: calendar)
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        setWeekdays(days, config: config, draft: &draft, calendar: calendar)
    }

    static func setStart(_ date: Date, config: PlanConfig, draft: inout CutPlanSetupDraft, calendar: Calendar) {
        let day = calendar.startOfDay(for: date)
        if draft.weekdays == nil {
            config.startDate = day
        } else {
            draft.baseStart = day
            apply(draft, to: config, calendar: calendar)
        }
    }

    private static func apply(_ draft: CutPlanSetupDraft, to config: PlanConfig, calendar: Calendar) {
        guard let weekdays = draft.weekdays, let base = draft.baseStart else { return }
        guard !weekdays.isEmpty, let start = firstTrainingDate(from: base, weekdays: weekdays, calendar: calendar) else {
            config.trainingDaysPerWeek = 0
            config.restDayPlacement = nil
            config.startDate = calendar.startOfDay(for: base)
            return
        }
        let first = weekdayIndex(start, calendar: calendar)
        config.trainingDaysPerWeek = weekdays.count
        config.restDayPlacement = .custom((0..<7).filter { !weekdays.contains((first + $0) % 7) })
        config.startDate = start
    }

    /// The date the first workout falls on: the legacy save aligns the first workout to the start date.
    static func firstWorkoutDate(_ config: PlanConfig) -> Date { config.startDate }

    // MARK: Split screen

    static func splitModel(_ config: PlanConfig, saved: [SplitTemplate], templates: [SplitTemplate] = SplitTemplates.all) -> CutPlanSplitModel {
        let selected = config.selectedTemplate?.id
        func option(_ template: SplitTemplate, kind: CutPlanSplitModel.Option.Kind) -> CutPlanSplitModel.Option {
            .init(id: template.id, title: template.name, line: splitLine(template), isSelected: !config.isCreatingCustom && selected == template.id, kind: kind)
        }
        return .init(
            templates: templates.map { option($0, kind: .template) },
            buildOwn: .init(id: "build-your-own", title: "Build your own", line: "Name the days and pick every exercise.",
                            isSelected: config.isCreatingCustom, kind: .buildOwn),
            saved: saved.map { option($0, kind: .saved) },
            canProceed: PlanConfigValidator.canProceedFromStep(0, config: config)
        )
    }

    static func splitLine(_ template: SplitTemplate) -> String {
        let lead: String
        switch template.id {
        case "full-body": lead = "Everything each session."
        case "upper-lower": lead = "Alternate halves."
        case "ppl": lead = "One movement group a day."
        case "bro-split": lead = "One muscle group a day."
        default:
            let parts = template.days.filter { !$0.isRestDay }.count
            lead = "\(parts) \(parts == 1 ? "part" : "parts"), made by you."
        }
        return lead + " " + frequencyText(frequencies(for: template)) + "."
    }

    /// "3 or 6 days", "2 to 4 days", "5 days".
    static func frequencyText(_ options: [Int]) -> String {
        let sorted = options.sorted()
        guard let low = sorted.first, let high = sorted.last else { return "" }
        if sorted.count == 1 { return "\(low) \(low == 1 ? "day" : "days")" }
        if sorted.count == 2 { return "\(low) or \(high) days" }
        let consecutive = zip(sorted, sorted.dropFirst()).allSatisfy { $1 == $0 + 1 }
        if consecutive { return "\(low) to \(high) days" }
        return sorted.dropLast().map(String.init).joined(separator: ", ") + " or \(high) days"
    }

    // MARK: Days screen

    static func daysModel(_ config: PlanConfig, draft: CutPlanSetupDraft, calendar: Calendar) -> CutPlanDaysModel {
        let selected = weekdays(config, draft: draft, calendar: calendar)
        let short = calendar.shortWeekdaySymbols
        let full = calendar.weekdaySymbols
        let tiles = (0..<7).map { day -> CutPlanDaysModel.Tile in
            let symbol = (day + 1) % 7
            let training = selected.contains(day)
            return .init(id: day, short: short[symbol], spoken: full[symbol] + (training ? ", training" : ", rest"), isTraining: training)
        }
        let count = selected.count
        let options = frequencies(config)
        let warning = draft.weekdays != nil && count > 0 && !options.contains(count)
        let line: String
        if count == 0 {
            line = "No training days yet."
        } else if warning {
            line = "\(splitName(config)) runs \(frequencyText(options)) a week."
        } else {
            line = "\(count) training \(count == 1 ? "day" : "days"), \(7 - count) rest \(7 - count == 1 ? "day" : "days")"
        }
        return .init(tiles: tiles, countLine: line, countIsWarning: warning, weekOptions: weekOptions,
                     selectedWeeks: config.programWeeks > 0 ? config.programWeeks : nil,
                     canProceed: canProceed(.days, config: config, draft: draft))
    }

    static func splitName(_ config: PlanConfig) -> String {
        if config.isCreatingCustom {
            let name = config.customSplitName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Your split" : name
        }
        return config.selectedTemplate?.name ?? "This split"
    }

    // MARK: Review

    /// The workout days in the order the legacy save cycles them, with the exercises it will save.
    static func workoutDays(_ config: PlanConfig) -> [(dayID: String, name: String, exercises: [ExerciseTemplate])] {
        if config.isCreatingCustom {
            return config.partNames.map { ($0, $0, config.partExercises[$0] ?? []) }
        }
        guard let template = config.selectedTemplate else { return [] }
        return template.days.filter { !$0.isRestDay }.map { ($0.id, $0.name, config.customizedDays[$0.id] ?? $0.exercises) }
    }

    static func reviewModel(_ config: PlanConfig, purpose: CutPlanSetupPurpose, replacesPlan: Bool, calendar: Calendar, locale: Locale) -> CutPlanReviewModel {
        let pattern = cyclePattern(config.restDayPlacement, trainingDays: config.trainingDaysPerWeek)
        let workouts = workoutDays(config)
        let first = pattern.firstIndex(of: true) ?? 0
        let start = weekdayIndex(config.startDate, calendar: calendar)
        var formatCalendar = calendar
        formatCalendar.locale = locale
        var days: [CutPlanReviewModel.Day] = []
        if !workouts.isEmpty {
            var k = 0
            for index in pattern.indices where pattern[index] {
                let weekday = ((start - first + index) % 7 + 7) % 7
                let workout = workouts[k % workouts.count]
                days.append(.init(id: index, dayID: workout.dayID,
                                  title: formatCalendar.weekdaySymbols[(weekday + 1) % 7] + ", " + workout.name,
                                  line: exerciseSummary(workout.exercises.map(\.exerciseName))))
                k += 1
            }
        }
        let perWeek = config.trainingDaysPerWeek
        let date = config.startDate.formatted(Date.FormatStyle(locale: locale, calendar: formatCalendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide))
        return .init(
            title: splitName(config),
            line: "\(perWeek) \(perWeek == 1 ? "day" : "days") a week for \(config.programWeeks) \(config.programWeeks == 1 ? "week" : "weeks")",
            days: days,
            startLine: "Starts \(date).",
            replaceLine: replacesPlan ? "It replaces your current plan." : nil,
            buttonTitle: purpose == .edit ? "Save program" : "Start program",
            canStart: config.isValid
        )
    }

    /// "Bench Press, Overhead Press, Incline Press and 2 more".
    static func exerciseSummary(_ names: [String], shown: Int = 3) -> String {
        guard !names.isEmpty else { return "No exercises" }
        let head = names.prefix(shown).joined(separator: ", ")
        return names.count > shown ? head + " and \(names.count - shown) more" : head
    }

    /// "3 sets, 10 reps, 60 kg".
    static func exerciseLine(sets: Int, reps: Int, weight: Double?, unit: WeightUnit) -> String {
        var parts = ["\(sets) \(sets == 1 ? "set" : "sets")", "\(reps) \(reps == 1 ? "rep" : "reps")"]
        if let weight, weight > 0 { parts.append(unit.format(weight)) }
        return parts.joined(separator: ", ")
    }

    // MARK: Customise one day (legacy Step4CustomizeExercises)

    static func exercises(dayID: String, config: PlanConfig) -> [ExerciseTemplate] {
        guard let day = config.selectedTemplate?.days.first(where: { $0.id == dayID }) else { return [] }
        return config.customizedDays[dayID] ?? day.exercises
    }

    static func customizeModel(dayID: String, config: PlanConfig, unit: WeightUnit) -> CutPlanCustomizeModel {
        let day = config.selectedTemplate?.days.first { $0.id == dayID }
        return .init(title: day?.name ?? "Exercises", rows: exercises(dayID: dayID, config: config).enumerated().map { index, exercise in
            .init(id: index, name: exercise.exerciseName, line: exerciseLine(sets: exercise.sets, reps: exercise.reps, weight: exercise.startingWeight, unit: unit))
        })
    }

    /// Marks the plan customised, as choosing "Customize exercises" did in the legacy flow.
    private static func write(_ exercises: [ExerciseTemplate], dayID: String, config: PlanConfig) {
        config.customizedDays[dayID] = exercises
        config.wantsToCustomize = true
    }

    static func addExercise(id: String, name: String, dayID: String, config: PlanConfig) {
        guard config.selectedTemplate?.days.contains(where: { $0.id == dayID }) == true else { return }
        var list = exercises(dayID: dayID, config: config)
        list.append(ExerciseTemplate(exerciseID: id, exerciseName: name, sets: 3, reps: 10, startingWeight: nil, progressionStrategy: .linear(increment: 2.5)))
        write(list, dayID: dayID, config: config)
    }

    static func removeExercise(at index: Int, dayID: String, config: PlanConfig) {
        var list = exercises(dayID: dayID, config: config)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        write(list, dayID: dayID, config: config)
    }

    static func updateExercise(at index: Int, dayID: String, sets: Int, reps: Int, weight: Double?, config: PlanConfig) {
        var list = exercises(dayID: dayID, config: config)
        guard list.indices.contains(index) else { return }
        let old = list[index]
        list[index] = ExerciseTemplate(exerciseID: old.exerciseID, exerciseName: old.exerciseName, sets: sets, reps: reps,
                                       startingWeight: weight, progressionStrategy: old.progressionStrategy, notes: old.notes)
        write(list, dayID: dayID, config: config)
    }

    // MARK: Custom path

    static func customNameModel(_ config: PlanConfig) -> CutPlanCustomNameModel {
        let names = config.partNames
        let filled = names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let hint: String?
        if config.numberOfParts > 0 && filled.count == names.count && Set(names).count != names.count {
            hint = "Each part needs its own name."
        } else {
            hint = nil
        }
        return .init(name: config.customSplitName, partCount: config.numberOfParts, partNames: names,
                     showsQuickFill: config.numberOfParts == 3, hint: hint,
                     canProceed: PlanConfigValidator.canProceedFromStep(1, config: config))
    }

    /// Choosing a part count starts the names and exercises over, as the legacy step did.
    /// Tapping the count already chosen keeps them.
    static func setPartCount(_ count: Int, config: PlanConfig) {
        guard count != config.numberOfParts else { return }
        config.numberOfParts = count
        config.partNames = Array(repeating: "", count: count)
        config.partExercises = [:]
    }

    static func setPartName(_ name: String, at index: Int, config: PlanConfig) {
        guard config.partNames.indices.contains(index) else { return }
        config.partNames[index] = name
    }

    static func quickFill(_ config: PlanConfig) {
        guard config.numberOfParts == 3 else { return }
        config.partNames = ["Push", "Pull", "Legs"]
    }

    static func customExercisesModel(_ config: PlanConfig) -> CutPlanCustomExercisesModel {
        let minimum = PlannerConstants.ExerciseLimits.minPerPart
        let maximum = PlannerConstants.ExerciseLimits.maxPerPart
        let rows = config.partNames.map { name -> CutPlanCustomExercisesModel.Row in
            let list = config.partExercises[name] ?? []
            let complete = (minimum...maximum).contains(list.count)
            let line: String
            if list.isEmpty { line = "Pick \(minimum) to \(maximum) exercises" }
            else if list.count < minimum { line = exerciseSummary(list.map(\.exerciseName)) + ". Add \(minimum - list.count) more." }
            else { line = exerciseSummary(list.map(\.exerciseName)) }
            return .init(name: name, line: line, isComplete: complete)
        }
        return .init(rows: rows, canProceed: PlanConfigValidator.canProceedFromStep(2, config: config))
    }

    // MARK: Split choice (legacy Step1ChooseSplit)

    static func choose(_ template: SplitTemplate, config: PlanConfig) {
        config.selectedTemplate = template
        config.isCreatingCustom = false
    }

    static func chooseBuildOwn(_ config: PlanConfig) {
        config.isCreatingCustom = true
        config.selectedTemplate = nil
    }
}
