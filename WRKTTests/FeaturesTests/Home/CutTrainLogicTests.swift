import Foundation
import SwiftData
import Testing
import XCTest
@testable import WRKT

@MainActor
struct CutTrainLogicTests {
    // MARK: Fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Wednesday 11 November 2026, 10:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10))!
    }

    private func entry(_ id: String, _ name: String, done: Int, of total: Int, weight: Double = 85, reps: Int = 6) -> WorkoutEntry {
        WorkoutEntry(exerciseID: id, exerciseName: name, muscleGroups: ["Chest"],
                     sets: (0..<total).map { index in
                         SetInput(reps: reps, weight: weight, tag: .working, autoWeight: false, isCompleted: index < done)
                     })
    }

    private let planID = UUID()

    private func workout(_ entries: [WorkoutEntry], planned: UUID? = nil) -> CutTrainLogic.ActiveWorkout {
        .init(entries: entries, startDate: now.addingTimeInterval(-900), plannedWorkoutID: planned)
    }

    // MARK: Hero state selection

    @Test func noWorkoutNoPlanIsNoPlan() {
        let hero = CutTrainLogic.hero(workout: nil, rest: nil, todaysPlan: nil, outlook: PlanOutlook(), unit: .kg)
        #expect(hero == .noPlan)
    }

    @Test func todaysPlanIsPlanned() {
        let hero = CutTrainLogic.hero(workout: nil, rest: nil,
                                      todaysPlan: .init(id: planID, name: "Upper Body", exerciseCount: 6),
                                      outlook: PlanOutlook(hasActivePlan: true), unit: .kg)
        #expect(hero == .planned(name: "Upper Body", exerciseCount: 6))
    }

    @Test func activePlanWithNothingTodayIsRestDay() {
        let next = PlanOutlook.Session(name: "Lower Body", date: now.addingTimeInterval(86_400))
        let hero = CutTrainLogic.hero(workout: nil, rest: nil, todaysPlan: nil,
                                      outlook: PlanOutlook(hasActivePlan: true, nextSession: next), unit: .kg)
        #expect(hero == .restDay(next: next))
    }

    @Test func completedSessionTodayIsDoneTodayNotRestDay() {
        let next = PlanOutlook.Session(name: "Lower Body", date: now.addingTimeInterval(86_400))
        let hero = CutTrainLogic.hero(workout: nil, rest: nil, todaysPlan: nil,
                                      outlook: PlanOutlook(hasActivePlan: true, completedToday: true, nextSession: next),
                                      unit: .kg)
        #expect(hero == .doneToday(next: next))
        #expect(CutTrainLogic.heroTitle(hero) == "Done today")
        #expect(CutTrainLogic.heroLine(hero, now: now, calendar: calendar) == "Next: Lower Body, tomorrow")
        #expect(CutTrainLogic.heroLine(.doneToday(next: nil)) == nil)
        #expect(!CutTrainLogic.fieldIsLime(hero))
    }

    @Test func workoutInProgressWinsOverDoneToday() {
        let hero = CutTrainLogic.hero(workout: workout([entry("a", "Bench Press", done: 0, of: 1)]), rest: nil,
                                      todaysPlan: nil, outlook: PlanOutlook(hasActivePlan: true, completedToday: true),
                                      unit: .kg)
        guard case .live = hero else { Issue.record("expected live"); return }
    }

    @Test func onlyRestAndDoneDaysUseTheDarkField() {
        #expect(CutTrainLogic.fieldIsLime(.noPlan))
        #expect(CutTrainLogic.fieldIsLime(.planned(name: "A", exerciseCount: 1)))
        #expect(CutTrainLogic.fieldIsLime(.resting(nextLine: nil, countdown: .fixed(1))))
        #expect(!CutTrainLogic.fieldIsLime(.restDay(next: nil)))
        #expect(!CutTrainLogic.fieldIsLime(.doneToday(next: nil)))
    }

    @Test func emptyWorkoutDoesNotCountAsLive() {
        let hero = CutTrainLogic.hero(workout: workout([]), rest: nil, todaysPlan: nil, outlook: PlanOutlook(), unit: .kg)
        #expect(hero == .noPlan)
    }

    @Test func workoutInProgressWinsOverPlanAndCountsDoneExercises() {
        let entries = [entry("a", "Bench Press", done: 3, of: 3), entry("b", "Row", done: 1, of: 3), entry("c", "Curl", done: 0, of: 2)]
        let hero = CutTrainLogic.hero(workout: workout(entries, planned: planID), rest: nil,
                                      todaysPlan: .init(id: planID, name: "Upper Body", exerciseCount: 3),
                                      outlook: PlanOutlook(hasActivePlan: true), unit: .kg)
        #expect(hero == .live(name: "Upper Body", exercisesDone: 1, exerciseCount: 3, startDate: now.addingTimeInterval(-900)))
    }

    @Test func unplannedWorkoutUsesTheLiveWorkoutName() {
        let hero = CutTrainLogic.hero(workout: workout([entry("a", "Bench Press", done: 0, of: 1)]), rest: nil,
                                      todaysPlan: .init(id: planID, name: "Upper Body", exerciseCount: 3),
                                      outlook: PlanOutlook(), unit: .kg)
        guard case .live(let name, _, _, _) = hero else { Issue.record("expected live"); return }
        #expect(name == "Live workout")
    }

    @Test func runningRestWinsAndNamesTheNextOpenSet() {
        let entries = [entry("a", "Bench Press", done: 2, of: 3), entry("b", "Row", done: 0, of: 3)]
        let hero = CutTrainLogic.hero(workout: workout(entries), rest: .init(exerciseID: "a"),
                                      todaysPlan: nil, outlook: PlanOutlook(), unit: .kg, countdown: .fixed(92))
        #expect(hero == .resting(nextLine: "Next: Bench Press, 85\u{00A0}kg\u{00A0}x\u{00A0}6", countdown: .fixed(92)))
    }

    @Test func nextSetMovesOnWhenTheRestedExerciseIsDone() {
        let entries = [entry("a", "Bench Press", done: 3, of: 3), entry("b", "Row", done: 0, of: 3, weight: 60, reps: 10)]
        let next = CutTrainLogic.nextSet(in: entries, restingOn: "a")
        #expect(next?.name == "Row")
        #expect(next.map { CutTrainLogic.nextSetLine(name: $0.name, set: $0.set, unit: .kg) } == "Next: Row, 60\u{00A0}kg\u{00A0}x\u{00A0}10")
    }

    @Test func nextSetIsNilWhenEverythingIsDone() {
        let entries = [entry("a", "Bench Press", done: 3, of: 3)]
        #expect(CutTrainLogic.nextSet(in: entries, restingOn: "a") == nil)
        let hero = CutTrainLogic.hero(workout: workout(entries), rest: .init(exerciseID: "a"),
                                      todaysPlan: nil, outlook: PlanOutlook(), unit: .kg, countdown: .fixed(30))
        #expect(CutTrainLogic.heroLine(hero) == nil)
    }

    @Test func nextSetLineFollowsTheUnitAndBodyweight() {
        let weighted = SetInput(reps: 6, weight: 100, tag: .working, autoWeight: false)
        #expect(CutTrainLogic.nextSetLine(name: "Squat", set: weighted, unit: .lb) == "Next: Squat, 220.5\u{00A0}lb\u{00A0}x\u{00A0}6")
        let bodyweight = SetInput(reps: 8, weight: 0, tag: .working, autoWeight: false)
        #expect(CutTrainLogic.nextSetLine(name: "Pull Up", set: bodyweight, unit: .kg) == "Next: Pull Up, 8 reps")
        let timed = SetInput(reps: 0, weight: 0, tag: .working, autoWeight: false)
        #expect(CutTrainLogic.nextSetLine(name: "Plank", set: timed, unit: .kg) == "Next: Plank")
    }

    // MARK: Copy

    @Test func heroTitlesAndLines() {
        #expect(CutTrainLogic.heroTitle(.restDay(next: nil)) == "Rest day")
        #expect(CutTrainLogic.heroTitle(.noPlan) == "No plan yet")
        #expect(CutTrainLogic.heroLine(.planned(name: "Upper Body", exerciseCount: 6)) == "6 exercises")
        #expect(CutTrainLogic.heroLine(.planned(name: "Upper Body", exerciseCount: 1)) == "1 exercise")
        #expect(CutTrainLogic.heroLine(.planned(name: "Upper Body", exerciseCount: 0)) == nil)
        #expect(CutTrainLogic.heroLine(.noPlan) == nil)
        #expect(CutTrainLogic.heroLine(.restDay(next: nil)) == nil)
        #expect(CutTrainLogic.heroLine(.live(name: "X", exercisesDone: 2, exerciseCount: 6, startDate: now)) == "2 of 6 exercises done")
    }

    @Test func longNamesStepDownTheHeroInsteadOfTruncating() {
        #expect(CutTrainLogic.heroSize(forLines: "Upper\nBody") == .xl)
        #expect(CutTrainLogic.heroSize(forLines: "No plan\nyet") == .xl)
        #expect(CutTrainLogic.heroSize(forLines: "Hypertrophy") == .m)
        let long = CutHeroText.balancedLines("Posterior Chain and Conditioning Superset")
        #expect(CutTrainLogic.heroSize(forLines: long) == .xs)
    }

    @Test func restDayLineNamesTheNextSession() {
        let tomorrow = PlanOutlook.Session(name: "Lower Body", date: now.addingTimeInterval(86_400))
        #expect(CutTrainLogic.heroLine(.restDay(next: tomorrow), now: now, calendar: calendar) == "Next: Lower Body, tomorrow")
        let friday = PlanOutlook.Session(name: "Push", date: now.addingTimeInterval(2 * 86_400))
        #expect(CutTrainLogic.heroLine(.restDay(next: friday), now: now, calendar: calendar) == "Next: Push, Friday")
        let later = PlanOutlook.Session(name: "Pull", date: now.addingTimeInterval(10 * 86_400))
        #expect(CutTrainLogic.heroLine(.restDay(next: later), now: now, calendar: calendar) == "Next: Pull, Nov 21")
    }

    @Test func durationsDropSecondsFromOneHour() {
        #expect(CutTrainLogic.elapsed(0) == "0:00")
        #expect(CutTrainLogic.elapsed(245) == "4:05")
        #expect(CutTrainLogic.elapsed(24 * 60 + 16) == "24:16")
        #expect(CutTrainLogic.elapsed(3599) == "59:59")
        #expect(CutTrainLogic.elapsed(3600) == "1:00")
        #expect(CutTrainLogic.elapsed(3600 + 2 * 60 + 59) == "1:02")
        #expect(CutTrainLogic.elapsed(-5) == "0:00")
        #expect(CutTrainLogic.countdown(92.7) == "1:32")
    }

    @Test func weeklyGoalReadsAsOneSentence() {
        let goal = CutTrainWeeklyGoal(strengthDone: 2, strengthTarget: 4, cardioMinutes: 95, cardioTarget: 150)
        #expect(CutTrainLogic.weeklyGoalAccessibilityLabel(goal)
                == "Weekly goal: strength 2 of 4 days, cardio 95 of 150 minutes")
        #expect(CutTrainLogic.fraction(2, of: 4) == 0.5)
        #expect(CutTrainLogic.fraction(3, of: 0) == 0)
    }

    // MARK: Rows

    @Test func rowsAppearOnlyWithData() {
        #expect(CutTrainLogic.rows(battle: nil, streakWeeks: nil, lastWorkout: nil, now: now, calendar: calendar).isEmpty)
        #expect(CutTrainLogic.rows(battle: nil, streakWeeks: 0, lastWorkout: nil, now: now, calendar: calendar).isEmpty)

        let friday = now.addingTimeInterval(-5 * 86_400)
        let rows = CutTrainLogic.rows(battle: ("Battle with Alex", "Leading by 1,240 kg"), streakWeeks: 6,
                                      lastWorkout: ("Lower Body", friday), now: now, calendar: calendar)
        #expect(rows.map(\.kind) == [.battle, .streak, .lastWorkout])
        #expect(rows.map(\.value) == ["Leading by 1,240 kg", "6 weeks", "Lower Body, Fri"])
    }

    @Test func rowValuesForRecentDays() {
        let today = CutTrainLogic.rows(battle: nil, streakWeeks: 1, lastWorkout: ("Upper Body", now), now: now, calendar: calendar)
        #expect(today.map(\.value) == ["1 week", "Upper Body, Today"])
        let yesterday = CutTrainLogic.rows(battle: nil, streakWeeks: nil,
                                           lastWorkout: ("Upper Body", now.addingTimeInterval(-86_400)), now: now, calendar: calendar)
        #expect(yesterday.map(\.value) == ["Upper Body, Yesterday"])
        let old = CutTrainLogic.rows(battle: nil, streakWeeks: nil,
                                     lastWorkout: ("Upper Body", now.addingTimeInterval(-30 * 86_400)), now: now, calendar: calendar)
        #expect(old.map(\.value) == ["Upper Body, Oct 12"])
    }

    @Test func lastWorkoutNameMatchesTheLegacyCard() {
        let named = CompletedWorkout(date: now, entries: [], workoutName: "Heavy Day")
        #expect(CutTrainLogic.displayName(for: named) == "Heavy Day")
        let legs = CompletedWorkout(date: now, entries: [
            WorkoutEntry(exerciseID: "squat", exerciseName: "Squat", muscleGroups: ["Quads"], sets: [])
        ])
        #expect(CutTrainLogic.displayName(for: legs) == "Lower Body")
        let mixed = CompletedWorkout(date: now, entries: [
            WorkoutEntry(exerciseID: "squat", exerciseName: "Squat", muscleGroups: ["Quads", "Chest"], sets: [])
        ])
        #expect(CutTrainLogic.displayName(for: mixed) == "Full Body")
    }
}

/// The plan outlook drives the rest day hero. XCTest so it runs serially with
/// HomeRefreshCoalescingTests, which also configures the shared PlannerStore.
@MainActor
final class CutTrainPlanOutlookTests: XCTestCase {
    func testOutlookLoadsOnlyWhenRequested() async throws {
        let schema = Schema([
            PlannedWorkout.self, PlannedExercise.self, WorkoutSplit.self,
            PlanBlock.self, PlanBlockExercise.self
        ])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(WorkoutSplit(name: "Upper/Lower", planBlocks: []))
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)))
        context.insert(PlannedWorkout(scheduledDate: tomorrow, splitDayName: "Lower Body", exercises: []))
        try context.save()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "CutTrainPlanOutlookTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        PlannerStore.shared.configure(container: container, context: context, workoutStore: store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        let off = HomeViewModel(workoutStore: store, plannerStore: .shared,
                                friendActivityLoader: { nil }, refreshDelay: {}, loadsPlanOutlook: false)
        await off.refresh(userInitiated: true)
        XCTAssertEqual(off.planOutlook, PlanOutlook(), "The legacy Train tab must not load the outlook")

        let on = HomeViewModel(workoutStore: store, plannerStore: .shared,
                               friendActivityLoader: { nil }, refreshDelay: {}, loadsPlanOutlook: true)
        await on.refresh(userInitiated: true)
        XCTAssertTrue(on.planOutlook.hasActivePlan)
        XCTAssertNil(on.todaysPlan)
        XCTAssertEqual(on.planOutlook.nextSession, PlanOutlook.Session(name: "Lower Body", date: tomorrow))
        XCTAssertFalse(on.planOutlook.completedToday)

        // Today's session completed: the legacy view still sees no plan, the outlook records it.
        let today = PlannedWorkout(scheduledDate: calendar.startOfDay(for: .now), splitDayName: "Upper Body", exercises: [])
        today.workoutStatus = .completed
        context.insert(today)
        try context.save()
        await on.refresh(userInitiated: true)
        XCTAssertNil(on.todaysPlan)
        XCTAssertFalse(on.hasActivePlan)
        XCTAssertTrue(on.planOutlook.completedToday)
        await off.refresh(userInitiated: true)
        XCTAssertNil(off.todaysPlan)
        XCTAssertEqual(off.planOutlook, PlanOutlook())
    }
}
