import Foundation
import Testing
@testable import WRKT

/// The Cut new program flow: step mapping, validation, and proof that the merged days screen
/// saves the same plan as the legacy frequency and rest steps.
@MainActor
@Suite struct CutPlanSetupLogicTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }
    /// Monday 16 November 2026, UTC.
    static var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))! }
    static func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    static func config(_ template: SplitTemplate? = SplitTemplates.fullBody, start: Date? = nil) -> PlanConfig {
        let config = PlanConfig()
        config.selectedTemplate = template
        config.startDate = start ?? monday
        return config
    }

    // MARK: Steps

    @Test func predefinedPathIsFourScreensWithCustomiseOnlyFromTheReview() {
        #expect(CutPlanSetupLogic.path(isCustom: false) == [.split, .days, .review])
        #expect(CutPlanSetupLogic.step(.split, isCustom: false) == (1, 4))
        #expect(CutPlanSetupLogic.step(.days, isCustom: false) == (2, 4))
        #expect(CutPlanSetupLogic.step(.customize("push"), isCustom: false) == (3, 4))
        #expect(CutPlanSetupLogic.step(.review, isCustom: false) == (4, 4))
        #expect(CutPlanSetupLogic.next(after: .days, isCustom: false) == .review)
        #expect(CutPlanSetupLogic.next(after: .customize("push"), isCustom: false) == .review)
        #expect(CutPlanSetupLogic.back(from: .customize("push"), isCustom: false) == .review)
        #expect(CutPlanSetupLogic.back(from: .review, isCustom: false) == .days)
        #expect(CutPlanSetupLogic.back(from: .split, isCustom: false) == nil)
    }

    @Test func customPathKeepsNameExercisesAndDaysScreens() {
        #expect(CutPlanSetupLogic.path(isCustom: true) == [.split, .customName, .customExercises, .days, .review])
        #expect(CutPlanSetupLogic.step(.customExercises, isCustom: true) == (3, 5))
        #expect(CutPlanSetupLogic.step(.review, isCustom: true) == (5, 5))
        #expect(CutPlanSetupLogic.next(after: .split, isCustom: true) == .customName)
        #expect(CutPlanSetupLogic.back(from: .days, isCustom: true) == .customExercises)
    }

    /// Every legacy carousel step is covered by exactly one Cut screen (step 4, customise, is optional
    /// on the predefined path and decided on leaving the days screen).
    @Test func everyLegacyStepIsCovered() {
        let predefined = [CutPlanSetupScreen.split, .days, .review].flatMap { CutPlanSetupLogic.legacySteps($0, isCustom: false) }
        #expect(Set(predefined).union([3]) == Set(0...5))
        #expect(predefined.count == Set(predefined).count)
        let custom = CutPlanSetupLogic.path(isCustom: true).flatMap { CutPlanSetupLogic.legacySteps($0, isCustom: true) }
        #expect(custom.sorted() == [0, 1, 2, 3, 4, 5])
    }

    @Test func frequenciesMatchTheLegacyStep() {
        #expect(CutPlanSetupLogic.frequencies(for: SplitTemplates.ppl) == [3, 6])
        #expect(CutPlanSetupLogic.frequencies(for: SplitTemplates.upperLower) == [2, 4])
        #expect(CutPlanSetupLogic.frequencies(for: SplitTemplates.fullBody) == [2, 3, 4])
        #expect(CutPlanSetupLogic.frequencies(for: SplitTemplates.broSplit) == [5, 6])
        #expect(CutPlanSetupLogic.frequencies(for: nil) == [3, 4, 5, 6])
        let custom = PlanConfig(); custom.isCreatingCustom = true
        #expect(CutPlanSetupLogic.frequencies(custom) == [3, 4, 5, 6])
        #expect(CutPlanSetupLogic.weekOptions == [4, 6, 8, 12])
        #expect(CutPlanSetupLogic.frequencyText([3, 6]) == "3 or 6 days")
        #expect(CutPlanSetupLogic.frequencyText([2, 3, 4]) == "2 to 4 days")
        #expect(CutPlanSetupLogic.frequencyText([5]) == "5 days")
    }

    // MARK: Rest patterns

    /// The pure cycle the review reads is the one RestDayStrategyFactory builds.
    @Test func cyclePatternMatchesEveryStrategy() {
        let workouts = ["A", "B", "C"].map { PlanBlock(dayName: $0, exercises: [], isRestDay: false) }
        let placements: [PlanConfig.RestDayPlacement] = [.afterEachWorkout, .afterEverySecondWorkout, .weekends,
                                                         .custom([]), .custom([5, 6]), .custom([1, 3, 5, 6]), .custom([0, 2]), .custom([6])]
        for placement in placements {
            for days in 0...7 {
                let legacy = RestDayStrategyFactory.strategy(for: placement).generateWeek(workoutBlocks: workouts, trainingDaysPerWeek: days)
                #expect(CutPlanSetupLogic.cyclePattern(placement, trainingDays: days) == legacy.map { !$0.isRestDay },
                        "\(placement) \(days)")
            }
        }
    }

    /// For every choice the legacy flow offered (split, frequency, rest placement) and every start
    /// weekday, tapping the same weekdays in the Cut flow saves the same blocks and the same start.
    @Test func tappedDaysSaveTheSamePlanAsTheLegacyChoices() {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!)
        for template in SplitTemplates.all {
            for frequency in CutPlanSetupLogic.frequencies(for: template) {
                for placement in [PlanConfig.RestDayPlacement.afterEachWorkout, .weekends] {
                    for offset in 0..<7 {
                        let start = calendar.date(byAdding: .day, value: offset, to: base)!
                        let legacy = Self.config(template, start: start)
                        legacy.trainingDaysPerWeek = frequency
                        legacy.restDayPlacement = placement
                        legacy.programWeeks = 8
                        legacy.wantsToCustomize = false

                        let cut = Self.config(template, start: start)
                        cut.programWeeks = 8
                        var draft = CutPlanSetupDraft()
                        let weekdays = CutPlanSetupLogic.weekdays(legacy, draft: CutPlanSetupDraft(), calendar: calendar)
                        CutPlanSetupLogic.setWeekdays(weekdays, config: cut, draft: &draft, calendar: calendar)
                        #expect(CutPlanSetupLogic.canProceed(.days, config: cut, draft: draft))
                        CutPlanSetupLogic.prepareForReview(cut)
                        #expect(cut.isValid)

                        let a = Self.saved(legacy, calendar: calendar)
                        let b = Self.saved(cut, calendar: calendar)
                        #expect(a.names == b.names, "\(template.id) \(frequency) \(placement) \(offset)")
                        #expect(a.anchor == b.anchor)
                        #expect(a.schedule == b.schedule)
                        #expect(cut.trainingDaysPerWeek == frequency)
                    }
                }
            }
        }
    }

    /// The blocks, anchor and first four weeks of the plan the legacy generatePlan would save.
    static func saved(_ config: PlanConfig, calendar: Calendar) -> (names: [String], anchor: Date, schedule: [String]) {
        let workouts = CutPlanSetupLogic.workoutDays(config).map { day in
            PlanBlock(dayName: day.name, exercises: day.exercises.enumerated().map { index, exercise in
                PlanBlockExercise(exerciseID: exercise.exerciseID, exerciseName: exercise.exerciseName, sets: exercise.sets, reps: exercise.reps,
                                  startingWeight: exercise.startingWeight, progressionStrategy: exercise.progressionStrategy, order: index)
            }, isRestDay: false)
        }
        let blocks = RestDayStrategyFactory.strategy(for: config.restDayPlacement!).generateWeek(workoutBlocks: workouts, trainingDaysPerWeek: config.trainingDaysPerWeek)
        let start = calendar.startOfDay(for: config.startDate)
        let split = WorkoutSplit(name: "Fixture", planBlocks: blocks, anchorDate: start)
        split.anchorDate = split.anchorDateAligningFirstWorkout(to: start)
        let schedule = (0..<28).map { offset -> String in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return split.planBlock(for: date, cursor: 0)?.dayName ?? "none"
        }
        return (blocks.map(\.dayName), split.anchorDate, schedule)
    }

    @Test func weekdaysLandOnTheirWeekdayFromAnyStart() {
        let config = Self.config()
        var draft = CutPlanSetupDraft()
        // Wednesday start, Monday, Wednesday and Friday chosen: the first workout is that Wednesday.
        config.startDate = Self.day(2)
        CutPlanSetupLogic.setWeekdays([0, 2, 4], config: config, draft: &draft, calendar: Self.calendar)
        #expect(config.startDate == Self.day(2))
        #expect(config.restDayPlacement == .custom([1, 3, 4, 6]))
        #expect(config.trainingDaysPerWeek == 3)
        // Tuesday start: the first workout moves to Wednesday.
        CutPlanSetupLogic.setStart(Self.day(1), config: config, draft: &draft, calendar: Self.calendar)
        #expect(config.startDate == Self.day(2))
        // Adding Tuesday brings it back to the chosen start.
        CutPlanSetupLogic.toggle(1, config: config, draft: &draft, calendar: Self.calendar)
        #expect(config.startDate == Self.day(1))
        #expect(CutPlanSetupLogic.weekdays(config, draft: draft, calendar: Self.calendar) == [0, 1, 2, 4])
    }

    @Test func clearingEveryDayBlocksNext() {
        let config = Self.config()
        config.programWeeks = 8
        var draft = CutPlanSetupDraft()
        CutPlanSetupLogic.setWeekdays([0], config: config, draft: &draft, calendar: Self.calendar)
        CutPlanSetupLogic.toggle(0, config: config, draft: &draft, calendar: Self.calendar)
        #expect(config.trainingDaysPerWeek == 0)
        #expect(config.restDayPlacement == nil)
        #expect(config.startDate == Self.monday)
        #expect(!CutPlanSetupLogic.canProceed(.days, config: config, draft: draft))
        #expect(CutPlanSetupLogic.daysModel(config, draft: draft, calendar: Self.calendar).countLine == "No training days yet.")
    }

    @Test func daysScreenNeedsACountTheSplitRunsAtAndALength() {
        let config = Self.config(SplitTemplates.ppl)
        var draft = CutPlanSetupDraft()
        CutPlanSetupLogic.setWeekdays([0, 1, 2, 3], config: config, draft: &draft, calendar: Self.calendar)
        config.programWeeks = 8
        var model = CutPlanSetupLogic.daysModel(config, draft: draft, calendar: Self.calendar)
        #expect(!model.canProceed)
        #expect(model.countIsWarning)
        #expect(model.countLine == "Push/Pull/Legs runs 3 or 6 days a week.")
        CutPlanSetupLogic.setWeekdays([0, 2, 4], config: config, draft: &draft, calendar: Self.calendar)
        model = CutPlanSetupLogic.daysModel(config, draft: draft, calendar: Self.calendar)
        #expect(model.canProceed)
        #expect(model.countLine == "3 training days, 4 rest days")
        #expect(model.tiles.map(\.short) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(model.tiles.map(\.isTraining) == [true, false, true, false, true, false, false])
        #expect(model.tiles[1].spoken == "Tuesday, rest")
        #expect(model.selectedWeeks == 8)
        config.programWeeks = 0
        #expect(!CutPlanSetupLogic.canProceed(.days, config: config, draft: draft))
    }

    /// The legacy flow made the user choose a length; the Cut flow does not preselect one either.
    @Test func lengthIsNotPreselectedOnCreate() {
        let model = CutPlanSetupLogic.daysModel(Self.config(), draft: .init(), calendar: Self.calendar)
        #expect(model.selectedWeeks == nil)
        #expect(model.tiles.allSatisfy { !$0.isTraining })
        #expect(!model.canProceed)
    }

    // MARK: Launch modes

    /// Edit mode: the carousel loads the active plan into PlanConfig. Untouched, the days screen shows
    /// that pattern on its real weekdays and leaves the loaded rest placement and start alone.
    @Test func editKeepsTheLoadedPatternUntilADayIsTapped() {
        let config = Self.config(SplitTemplates.upperLower, start: Self.day(-14))
        config.trainingDaysPerWeek = 4
        config.restDayPlacement = .afterEverySecondWorkout
        config.programWeeks = 12
        let draft = CutPlanSetupDraft()
        // W W R W W R R from a Monday anchor.
        #expect(CutPlanSetupLogic.weekdays(config, draft: draft, calendar: Self.calendar) == [0, 1, 3, 4])
        #expect(CutPlanSetupLogic.canProceed(.days, config: config, draft: draft))
        CutPlanSetupLogic.prepareForReview(config)
        #expect(config.restDayPlacement == .afterEverySecondWorkout)
        #expect(config.startDate == Self.day(-14))
        #expect(config.isValid)
        let review = CutPlanSetupLogic.reviewModel(config, purpose: .edit, replacesPlan: true, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(review.buttonTitle == "Save program")
        #expect(review.replaceLine == "It replaces your current plan.")
        #expect(review.days.map(\.title) == ["Monday, Upper Body", "Tuesday, Lower Body", "Thursday, Upper Body", "Friday, Lower Body"])
    }

    /// An imported plan may load with a frequency the split's own options do not list: untouched it
    /// proceeds, as the legacy step did; tapping days applies the split's options again.
    @Test func editWithAnUnlistedFrequencyStillProceedsUntouched() {
        let config = Self.config(SplitTemplates.ppl)
        config.trainingDaysPerWeek = 4
        config.restDayPlacement = .custom([2, 5, 6])
        config.programWeeks = 12
        #expect(CutPlanSetupLogic.canProceed(.days, config: config, draft: .init()))
        var draft = CutPlanSetupDraft()
        CutPlanSetupLogic.toggle(6, config: config, draft: &draft, calendar: Self.calendar)
        #expect(!CutPlanSetupLogic.canProceed(.days, config: config, draft: draft))
    }

    @Test func createAndReplaceReviewLines() {
        let config = Self.config()
        config.programWeeks = 8
        var draft = CutPlanSetupDraft()
        CutPlanSetupLogic.setWeekdays([0, 2, 4], config: config, draft: &draft, calendar: Self.calendar)
        #expect(!config.isValid) // wantsToCustomize is still undecided
        CutPlanSetupLogic.prepareForReview(config)
        #expect(config.wantsToCustomize == false)
        let create = CutPlanSetupLogic.reviewModel(config, purpose: .create, replacesPlan: false, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(create.title == "Full Body")
        #expect(create.line == "3 days a week for 8 weeks")
        #expect(create.buttonTitle == "Start program")
        #expect(create.replaceLine == nil)
        #expect(create.canStart)
        #expect(create.startLine == "Starts Monday, November 16.")
        #expect(create.days.map(\.title) == ["Monday, Full Body A", "Wednesday, Full Body B", "Friday, Full Body C"])
        #expect(create.days.map(\.dayID) == ["full-body-a", "full-body-b", "full-body-c"])
        let replace = CutPlanSetupLogic.reviewModel(config, purpose: .create, replacesPlan: true, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(replace.replaceLine == "It replaces your current plan.")
        #expect(replace.buttonTitle == "Start program")
    }

    @Test func reviewOrdersDaysFromTheFirstWorkout() {
        let config = Self.config(SplitTemplates.ppl, start: Self.day(3))
        config.programWeeks = 4
        var draft = CutPlanSetupDraft()
        CutPlanSetupLogic.setWeekdays([0, 2, 4], config: config, draft: &draft, calendar: Self.calendar)
        CutPlanSetupLogic.prepareForReview(config)
        let review = CutPlanSetupLogic.reviewModel(config, purpose: .create, replacesPlan: false, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(review.days.map(\.title) == ["Friday, Push", "Monday, Pull", "Wednesday, Legs"])
        #expect(review.startLine == "Starts Friday, November 20.")
    }

    // MARK: Customise

    @Test func customisingADayFollowsTheLegacyEdits() {
        let config = Self.config()
        let day = SplitTemplates.fullBody.days[0]
        CutPlanSetupLogic.addExercise(id: "fixture-curl", name: "Fixture Curl", dayID: day.id, config: config)
        var list = config.customizedDays[day.id]!
        #expect(list.count == day.exercises.count + 1)
        #expect(list.last?.exerciseName == "Fixture Curl")
        #expect(list.last?.sets == 3); #expect(list.last?.reps == 10); #expect(list.last?.startingWeight == nil)
        #expect(list.last?.progressionStrategy == .linear(increment: 2.5))
        #expect(config.wantsToCustomize == true)
        CutPlanSetupLogic.updateExercise(at: 0, dayID: day.id, sets: 5, reps: 5, weight: 100, config: config)
        list = config.customizedDays[day.id]!
        #expect(list[0].sets == 5); #expect(list[0].reps == 5); #expect(list[0].startingWeight == 100)
        #expect(list[0].exerciseID == day.exercises[0].exerciseID)
        #expect(list[0].progressionStrategy == day.exercises[0].progressionStrategy)
        CutPlanSetupLogic.removeExercise(at: 0, dayID: day.id, config: config)
        #expect(config.customizedDays[day.id]!.count == day.exercises.count)
        #expect(CutPlanSetupLogic.workoutDays(config)[0].exercises.map(\.exerciseName) == config.customizedDays[day.id]!.map(\.exerciseName))
        // Out of range and unknown days change nothing.
        CutPlanSetupLogic.removeExercise(at: 99, dayID: day.id, config: config)
        CutPlanSetupLogic.addExercise(id: "x", name: "X", dayID: "absent", config: config)
        #expect(config.customizedDays["absent"] == nil)
        let model = CutPlanSetupLogic.customizeModel(dayID: day.id, config: config, unit: .kg)
        #expect(model.title == day.name)
        #expect(model.rows.count == config.customizedDays[day.id]!.count)
    }

    @Test func exerciseLines() {
        #expect(CutPlanSetupLogic.exerciseSummary([]) == "No exercises")
        #expect(CutPlanSetupLogic.exerciseSummary(["A", "B"]) == "A, B")
        #expect(CutPlanSetupLogic.exerciseSummary(["A", "B", "C", "D", "E"]) == "A, B, C and 2 more")
        #expect(CutPlanSetupLogic.exerciseLine(sets: 3, reps: 10, weight: nil, unit: .kg) == "3 sets, 10 reps")
        #expect(CutPlanSetupLogic.exerciseLine(sets: 1, reps: 1, weight: 0, unit: .kg) == "1 set, 1 rep")
        #expect(CutPlanSetupLogic.exerciseLine(sets: 3, reps: 8, weight: 60, unit: .kg).hasPrefix("3 sets, 8 reps, 60"))
    }

    // MARK: Split screen

    @Test func splitChoices() {
        let config = Self.config(nil)
        var model = CutPlanSetupLogic.splitModel(config, saved: [])
        #expect(!model.canProceed)
        #expect(model.templates.map(\.title) == SplitTemplates.all.map(\.name))
        #expect(model.templates.first { $0.id == "full-body" }?.line == "Everything each session. 2 to 4 days.")
        #expect(model.templates.first { $0.id == "ppl" }?.line == "One movement group a day. 3 or 6 days.")
        CutPlanSetupLogic.choose(SplitTemplates.ppl, config: config)
        model = CutPlanSetupLogic.splitModel(config, saved: [])
        #expect(model.canProceed)
        #expect(model.templates.filter(\.isSelected).map(\.id) == ["ppl"])
        CutPlanSetupLogic.chooseBuildOwn(config)
        #expect(config.isCreatingCustom); #expect(config.selectedTemplate == nil)
        model = CutPlanSetupLogic.splitModel(config, saved: [])
        #expect(model.buildOwn.isSelected); #expect(model.canProceed)
        #expect(model.templates.allSatisfy { !$0.isSelected })
        let saved = SplitTemplate(id: "mine", name: "Fixture Split", shortName: "FIX", description: "", days: SplitTemplates.ppl.days,
                                  recommendedFrequency: 3, difficulty: .intermediate, focus: "", icon: "", isCustom: true)
        #expect(CutPlanSetupLogic.splitModel(config, saved: [saved]).saved.first?.line == "3 parts, made by you. 3 to 6 days.")
    }

    // MARK: Custom path

    @Test func customNameAndParts() {
        let config = PlanConfig()
        CutPlanSetupLogic.chooseBuildOwn(config)
        #expect(!CutPlanSetupLogic.customNameModel(config).canProceed)
        config.customSplitName = "Fixture Split"
        CutPlanSetupLogic.setPartCount(3, config: config)
        #expect(config.partNames == ["", "", ""])
        CutPlanSetupLogic.quickFill(config)
        #expect(config.partNames == ["Push", "Pull", "Legs"])
        #expect(CutPlanSetupLogic.customNameModel(config).canProceed)
        // The same count keeps the names; another count starts over, as the legacy step did.
        CutPlanSetupLogic.setPartCount(3, config: config)
        #expect(config.partNames == ["Push", "Pull", "Legs"])
        config.partExercises = ["Push": []]
        CutPlanSetupLogic.setPartCount(2, config: config)
        #expect(config.partNames == ["", ""]); #expect(config.partExercises.isEmpty)
        CutPlanSetupLogic.setPartName("Upper", at: 0, config: config)
        CutPlanSetupLogic.setPartName("Upper", at: 1, config: config)
        CutPlanSetupLogic.setPartName("Ignored", at: 5, config: config)
        let model = CutPlanSetupLogic.customNameModel(config)
        #expect(model.hint == "Each part needs its own name.")
        #expect(!model.canProceed)
        #expect(!model.showsQuickFill)
    }

    @Test func customExercisesAndTheFullCustomPlan() {
        let config = PlanConfig()
        CutPlanSetupLogic.chooseBuildOwn(config)
        config.customSplitName = "Fixture Split"
        CutPlanSetupLogic.setPartCount(2, config: config)
        CutPlanSetupLogic.setPartName("Upper", at: 0, config: config)
        CutPlanSetupLogic.setPartName("Lower", at: 1, config: config)
        let three = (1...3).map { ExerciseTemplate(exerciseID: "e\($0)", exerciseName: "Fixture \($0)", sets: 3, reps: 10) }
        config.partExercises = ["Upper": three, "Lower": Array(three.prefix(1))]
        var model = CutPlanSetupLogic.customExercisesModel(config)
        #expect(!model.canProceed)
        #expect(model.rows.map(\.isComplete) == [true, false])
        #expect(model.rows[1].line == "Fixture 1. Add 2 more.")
        config.partExercises["Lower"] = three
        model = CutPlanSetupLogic.customExercisesModel(config)
        #expect(model.canProceed)
        config.programWeeks = 6
        config.startDate = Self.monday
        var draft = CutPlanSetupDraft()
        // Six days: the legacy weekends option could not save six days; tapped days always can.
        CutPlanSetupLogic.setWeekdays([0, 1, 2, 3, 4, 5], config: config, draft: &draft, calendar: Self.calendar)
        #expect(CutPlanSetupLogic.canProceed(.days, config: config, draft: draft))
        CutPlanSetupLogic.prepareForReview(config)
        #expect(config.isValid)
        let review = CutPlanSetupLogic.reviewModel(config, purpose: .create, replacesPlan: false, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(review.title == "Fixture Split")
        #expect(Array(review.days.map(\.title).prefix(3)) == ["Monday, Upper", "Tuesday, Lower", "Wednesday, Upper"])
        #expect(review.days.first?.dayID == "Upper")
    }
}
