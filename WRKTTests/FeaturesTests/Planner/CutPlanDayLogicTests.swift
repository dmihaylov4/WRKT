import Foundation
import Testing
@testable import WRKT

/// Fixtures for the Cut "View day" page: November 2026, UTC, en_GB (24 hour clock).
enum CutPlanDayFixtures {
    static var calendar: Calendar { CutPlanFixtures.calendar }
    static let locale = Locale(identifier: "en_GB")
    static var today: Date { CutPlanFixtures.today }

    static func day(_ day: Int, hour: Int = 0, minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func workout(_ name: String = "Lower Body", day: Int = 11, hour: Int = 21, minute: Int = 19,
                        health: Bool = false, exercises: Int = 5, sets: Int = 18, reps: Int = 140) -> CutPlanDayInput.Workout {
        .init(id: UUID(), name: name, ended: Self.day(day, hour: hour, minute: minute), isHealthMatched: health,
              exerciseCount: exercises, setCount: sets, repCount: reps)
    }

    static func watch(_ name: String = "Traditional Strength", day: Int = 11) -> CutPlanDayInput.WatchStrength {
        .init(id: UUID(), name: name, ended: Self.day(day, hour: 7, minute: 5))
    }

    static func cardio(_ name: String = "Running", day: Int = 11, km: Double = 7.24, seconds: Int = 2_052) -> CutPlanDayInput.Cardio {
        .init(id: UUID(), name: name, start: Self.day(day, hour: 18, minute: 40), distanceKm: km, durationSeconds: seconds)
    }

    static func exercises(_ count: Int) -> [CutPlanDayInput.PlannedExercise] {
        let names = ["Bench Press", "Incline Dumbbell Press", "Cable Fly", "Overhead Press", "Lateral Raise", "Triceps Pushdown"]
        return (0..<count).map { .init(name: names[$0 % names.count], setCount: 3 + $0 % 2, firstReps: 10 - $0 % 3) }
    }

    static func planned(_ name: String = "Upper Body", status: WorkoutStatus = .scheduled, exercises count: Int = 6,
                        completedID: UUID? = nil, logged: Bool = false) -> CutPlanDayInput.Planned {
        .init(id: UUID(), name: name, status: status, exercises: exercises(count),
              completedWorkoutID: completedID, isLogged: logged)
    }

    static func model(_ date: Date, _ input: CutPlanDayInput = CutPlanDayInput()) -> CutPlanDayModel {
        CutPlanDayLogic.model(date: date, input: input, today: today, calendar: calendar, locale: locale)
    }
}

struct CutPlanDayLogicTests {
    private typealias F = CutPlanDayFixtures

    // MARK: Title

    @Test func titleIsWeekdayOverDate() {
        let model = F.model(F.day(11))
        #expect(model.title == "Wednesday\n11 November")
        #expect(model.accessibilityTitle == "Wednesday 11 November")
        #expect(model.line == "Today")
        #expect(F.model(F.day(10)).line == nil)
    }

    @Test func titleAddsTheYearWhenNotThisYear() {
        #expect(F.model(F.day(3, year: 2025)).title == "Monday\n3 November 2025")
    }

    // MARK: Actions by day

    @Test func todayWithoutPlanStartsAWorkout() {
        let model = F.model(F.day(11))
        #expect(model.actions == [.startWorkout])
        #expect(model.plan == nil)
        #expect(model.completedPlan == nil)
        #expect(model.showsNoActivity)
    }

    @Test func pastDayLogsAWorkout() {
        let model = F.model(F.day(5))
        #expect(model.actions == [.logWorkout])
        #expect(model.showsNoActivity)
    }

    @Test func futureDayWithoutPlanPlansOne() {
        let model = F.model(F.day(14))
        #expect(model.actions == [.planWorkout])
        #expect(model.plan == nil)
    }

    @Test func todayPlannedStartsAndEditsInThePlan() {
        let planned = F.planned()
        let model = F.model(F.day(11), CutPlanDayInput(planned: planned))
        #expect(model.actions.isEmpty)
        let plan = try! #require(model.plan)
        #expect(plan.sectionTitle == "Today's plan")
        #expect(plan.name == "Upper Body")
        #expect(plan.statusLine == "Planned, 6 exercises")
        #expect(plan.actions == [.startPlanned(planned.id), .editPlanned(planned.id)])
        #expect(plan.menu.isEmpty)
        #expect(!model.showsNoActivity)
    }

    @Test func todayRescheduledAndSkippedStillShowTodaysPlan() {
        for status in [WorkoutStatus.rescheduled, .skipped] {
            let planned = F.planned(status: status)
            let plan = F.model(F.day(11), CutPlanDayInput(planned: planned)).plan
            #expect(plan?.actions == [.startPlanned(planned.id), .editPlanned(planned.id)])
        }
    }

    @Test func todayCompletedOrPartialPlanOpensTheWorkout() {
        let workoutID = UUID()
        for status in [WorkoutStatus.completed, .partial] {
            let model = F.model(F.day(11), CutPlanDayInput(planned: F.planned(status: status, completedID: workoutID)))
            #expect(model.plan == nil)
            #expect(model.actions.isEmpty)
            #expect(model.completedPlan == .init(subtitle: "6 exercises, Upper Body", workoutID: workoutID))
        }
    }

    @Test func todayCompletedPlanWithoutLinkDoesNothing() {
        let model = F.model(F.day(11), CutPlanDayInput(planned: F.planned(status: .completed)))
        #expect(model.completedPlan?.workoutID == nil)
    }

    @Test func futurePlannedShowsOnlyThePlan() {
        let planned = F.planned("Lower Body")
        let model = F.model(F.day(13), CutPlanDayInput(planned: planned))
        #expect(model.actions.isEmpty)
        let plan = try! #require(model.plan)
        #expect(plan.sectionTitle == "Planned")
        #expect(plan.statusLine == "Planned, 6 exercises")
        #expect(plan.actions == [.editPlanned(planned.id)])
        #expect(plan.menu == [.startNow, .delete])
    }

    @Test func pastPlannedLogsAndShowsThePlan() {
        let planned = F.planned("Pull day", status: .skipped)
        let model = F.model(F.day(10), CutPlanDayInput(planned: planned))
        #expect(model.actions == [.logWorkout])
        #expect(model.plan?.statusLine == "Skipped, 6 exercises")
        // Skipped plans had no Start on the legacy card, only edit and delete.
        #expect(model.plan?.menu == [.delete])
    }

    @Test func statusWordsFollowTheLegacyCard() {
        #expect(CutPlanDayLogic.statusWord(F.planned(status: .scheduled)) == "Planned")
        #expect(CutPlanDayLogic.statusWord(F.planned(status: .partial)) == "Partially completed")
        #expect(CutPlanDayLogic.statusWord(F.planned(status: .skipped)) == "Skipped")
        #expect(CutPlanDayLogic.statusWord(F.planned(status: .rescheduled)) == "Rescheduled")
        #expect(CutPlanDayLogic.statusWord(F.planned(status: .rescheduled, logged: true)) == "Completed")
    }

    @Test func rescheduledFuturePlanHasNoStart() {
        let model = F.model(F.day(16), CutPlanDayInput(planned: F.planned(status: .rescheduled)))
        #expect(model.plan?.statusLine == "Rescheduled, 6 exercises")
        #expect(model.plan?.menu == [.delete])
    }

    @Test func loggedPlanOnAnotherDayStartsAgain() {
        let model = F.model(F.day(9), CutPlanDayInput(planned: F.planned(status: .scheduled, logged: true)))
        #expect(model.plan?.statusLine == "Completed, 6 exercises")
        #expect(model.plan?.menu == [.startAgain, .delete])
    }

    @Test func completedPlanOnAnotherDayHidesThePlan() {
        let past = F.model(F.day(9), CutPlanDayInput(planned: F.planned(status: .completed)))
        #expect(past.plan == nil)
        #expect(past.actions == [.logWorkout])
        #expect(!past.showsNoActivity)
        let future = F.model(F.day(14), CutPlanDayInput(planned: F.planned(status: .completed)))
        #expect(future.plan == nil)
        // The legacy action card hid on a future day with any plan.
        #expect(future.actions.isEmpty)
    }

    // MARK: Plan exercises

    @Test func planShowsThreeExercisesThenTheRest() {
        let plan = F.model(F.day(13), CutPlanDayInput(planned: F.planned(exercises: 6))).plan!
        #expect(plan.exercises.map(\.name) == ["Bench Press", "Incline Dumbbell Press", "Cable Fly"])
        #expect(plan.exercises.map(\.detail) == ["3 × 10", "4 × 9", "3 × 8"])
        #expect(plan.moreLine == "+3 more exercises")
        #expect(CutPlanDayLogic.moreLine(4) == "+1 more exercise")
        #expect(CutPlanDayLogic.moreLine(3) == nil)
    }

    @Test func planWithoutExercises() {
        let plan = F.model(F.day(13), CutPlanDayInput(planned: F.planned(exercises: 0))).plan!
        #expect(plan.exercises.isEmpty)
        #expect(plan.statusLine == "Planned, 0 exercises")
        #expect(plan.moreLine == nil)
        #expect(CutPlanDayLogic.planExercises([.init(name: "Squat", setCount: 0, firstReps: 0)]).first?.detail == "0 × 0")
    }

    // MARK: Summary

    @Test func summaryCountsAppWorkoutsOnly() {
        let input = CutPlanDayInput(workouts: [F.workout(exercises: 5, sets: 18, reps: 140),
                                               F.workout("Arms", exercises: 2, sets: 6, reps: 60)],
                                    watchStrength: [F.watch()], runCount: 1)
        let summary = F.model(F.day(11), input).summary
        #expect(summary?.map(\.value) == ["2", "7", "24", "200"])
        #expect(summary?.map(\.label) == ["Workouts", "Exercises", "Sets", "Reps"])
        #expect(F.model(F.day(11), CutPlanDayInput(watchStrength: [F.watch()], runCount: 1)).summary == nil)
    }

    // MARK: Rows

    @Test func workoutRowsAppThenWatch() {
        let app = F.workout(health: true)
        let plain = F.workout("Arms", hour: 9, minute: 3)
        let watch = F.watch()
        let section = F.model(F.day(11), CutPlanDayInput(workouts: [app, plain], watchStrength: [watch], runCount: 1)).workouts!
        #expect(section.title == "Workouts")
        #expect(section.count == 3)
        #expect(section.rows.map(\.target) == [.app(app.id), .app(plain.id), .healthKitStrength(watch.id)])
        #expect(section.rows.map(\.subtitle) == ["Ended: 21:19", "Ended: 09:03", "Ended: 07:05"])
        #expect(section.rows.map(\.isHealthMatched) == [true, false, true])
        #expect(section.rows[0].accessibilityLabel == "Lower Body, Ended: 21:19, Apple Health")
    }

    @Test func cardioRowsCarryTimeDurationAndDistance() {
        let run = F.cardio(km: 7.24, seconds: 2_052)
        let long = F.cardio("Long ride", km: 41.3, seconds: 5_460)
        let indoor = F.cardio("Rowing", km: 0, seconds: 900)
        let section = F.model(F.day(11), CutPlanDayInput(cardio: [run, long, indoor], runCount: 3)).cardio!
        #expect(section.title == "Cardio")
        #expect(section.rows.map(\.subtitle) == ["18:40, 34:12", "18:40, 1:31", "18:40, 15:00"])
        #expect(section.rows.map(\.value) == ["7.2 km", "41.3 km", nil])
        #expect(section.rows.map(\.target) == [.cardio(run.id), .cardio(long.id), .cardio(indoor.id)])
        #expect(section.rows.allSatisfy { !$0.isHealthMatched })
    }

    @Test func timeFollowsTheLocaleClock() {
        let us = CutPlanDayLogic.time(F.day(11, hour: 21, minute: 19), calendar: F.calendar, locale: Locale(identifier: "en_US"))
        #expect(us.contains("9:19"))
        #expect(us.contains("PM"))
    }

    // MARK: No activity

    @Test func hiddenWatchWorkoutsStillCountAsActivity() {
        // A discarded or matched Watch strength workout is not listed, but the legacy page
        // did not call the day empty either.
        let model = F.model(F.day(5), CutPlanDayInput(runCount: 1))
        #expect(!model.showsNoActivity)
        #expect(model.workouts == nil)
        #expect(model.cardio == nil)
    }

    @Test func aPlanIsActivity() {
        #expect(!F.model(F.day(14), CutPlanDayInput(planned: F.planned())).showsNoActivity)
    }

    // MARK: Labels shared with the Plan panel

    @Test func pillsUseThePanelLabels() {
        #expect(CutPlanLogic.label(for: .logWorkout) == "Log a workout")
        #expect(CutPlanLogic.label(for: .planWorkout) == "Plan a workout")
        #expect(CutPlanLogic.label(for: .startWorkout) == "Start workout")
        #expect(CutPlanDayLogic.menuLabel(.startNow) == "Start now")
        #expect(CutPlanDayLogic.menuLabel(.startAgain) == "Start again")
        #expect(CutPlanDayLogic.menuLabel(.delete) == "Delete planned workout")
    }
}
