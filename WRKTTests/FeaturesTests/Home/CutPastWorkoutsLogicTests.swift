import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutPastWorkoutsLogicTests {
    private typealias L = CutPastWorkoutsLogic

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Wednesday 11 November 2026, 10:00 UTC.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10))! }

    private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }

    private func set(_ reps: Int, _ kg: Double, tag: SetTag = .working, mode: TrackingMode = .weighted,
                     seconds: Int = 0, meters: Double = 0, done: Bool = true) -> SetInput {
        SetInput(reps: reps, weight: kg, tag: tag, isCompleted: done,
                 durationSeconds: seconds, distanceMeters: meters, trackingMode: mode)
    }

    private func entry(_ id: String, _ sets: [SetInput], muscles: [String] = ["Chest"],
                       group: UUID? = nil, order: Int? = nil) -> WorkoutEntry {
        WorkoutEntry(exerciseID: id, exerciseName: id.capitalized, muscleGroups: muscles, sets: sets,
                     supersetGroupID: group, orderInSuperset: order)
    }

    private func workout(_ days: Int, _ entries: [WorkoutEntry], name: String? = nil) -> CompletedWorkout {
        CompletedWorkout(date: daysAgo(days), entries: entries, workoutName: name)
    }

    // MARK: Which workouts qualify

    @Test func onlyWorkoutsWithAnExerciseWithASetQualifyNewestFirstAtMostThree() {
        let healthImport = CompletedWorkout(date: daysAgo(0), entries: [])
        var matched = healthImport
        matched.matchedHealthKitUUID = UUID()
        let noSets = workout(1, [entry("bench", [])])
        let a = workout(2, [entry("bench", [set(8, 100)])])
        let b = workout(3, [entry("squat", [set(5, 120)])])
        let c = workout(5, [entry("row", [set(10, 60)])])
        let d = workout(9, [entry("press", [set(8, 40)])])
        // The store keeps history oldest first.
        let history = [d, c, b, a, noSets, matched]
        #expect(L.repeatable(history).map(\.id) == [a.id, b.id, c.id])
        #expect(L.repeatable([healthImport, noSets]).isEmpty)
        #expect(L.repeatable([]).isEmpty)
        #expect(L.repeatable([b, a]).map(\.id) == [a.id, b.id])
    }

    @Test func aWorkoutWhoseExercisesAreAllGoneDoesNotQualify() {
        let gone = workout(1, [entry("custom_deleted", [set(8, 50)])])
        let kept = workout(2, [entry("bench", [set(8, 100)])])
        let result = L.repeatable([kept, gone]) { $0 != "custom_deleted" }
        #expect(result.map(\.id) == [kept.id])
    }

    // MARK: Name and day

    @Test func nameAndDayMatchTheLastWorkoutRow() {
        let named = workout(3, [entry("bench", [set(8, 100)])], name: "Push Day")
        let classified = workout(1, [entry("bench", [set(8, 100)], muscles: ["Chest"]),
                                     entry("squat", [set(5, 120)], muscles: ["Quads"])])
        let model = L.model([classified, named], unit: .kg, now: now, calendar: calendar)
        let row = CutTrainLogic.rows(battle: nil, streakWeeks: nil, lastWorkout: (CutTrainLogic.displayName(for: classified), classified.date),
                                     now: now, calendar: calendar)
        #expect(model.workouts.map(\.name) == ["Full Body", "Push Day"])
        #expect(row.first?.value == "Full Body, Yesterday")
        #expect(model.workouts.map(\.day) == ["Yesterday", "Sun"])
        #expect(L.model([workout(0, [entry("bench", [set(1, 1)])])], unit: .kg, now: now, calendar: calendar).workouts.first?.day == "Today")
        #expect(L.model([workout(20, [entry("bench", [set(1, 1)])])], unit: .kg, now: now, calendar: calendar).workouts.first?.day == "Oct 22")
    }

    @Test func longNamesWrapAtAWordAndShortOnesStayOnOneLine() {
        #expect(L.nameLines("Full Body") == "Full Body")
        #expect(L.nameLines("Legs and Conditioning") == "Legs and\nConditioning")
    }

    // MARK: Set summary

    @Test func weightedSetsThatAreAllAlikeReadSetsTimesRepsAndWeight() {
        let summary = L.setSummary([set(8, 100), set(8, 100), set(8, 100)], unit: .kg)
        #expect(summary.text == "3 × 8, 100 kg")
        #expect(summary.spoken == "3 sets of 8 reps, 100 kg")
        #expect(L.setSummary([set(5, 82.5)], unit: .kg).text == "1 × 5, 82.5 kg")
    }

    @Test func weightedSetsInTheUsersUnit() {
        #expect(L.setSummary([set(8, 100), set(8, 100)], unit: .lb).text == "2 × 8, 220.5 lb")
        #expect(L.setSummary([set(8, 80), set(6, 100)], unit: .lb).text == "2 sets, top 220.5 lb × 6")
    }

    @Test func mixedWeightedSetsShowTheCountAndTheTopSet() {
        let summary = L.setSummary([set(8, 80), set(6, 85), set(5, 87.5)], unit: .kg)
        #expect(summary.text == "3 sets, top 87.5 kg × 5")
        #expect(summary.spoken == "3 sets, top set 87.5 kg for 5 reps")
        // Same weight: the set with more reps is the top set.
        #expect(L.setSummary([set(6, 100), set(8, 100), set(5, 100)], unit: .kg).text == "3 sets, top 100 kg × 8")
    }

    @Test func warmUpsAreLeftOutOfTheSummaryUnlessThatIsAllThereIs() {
        let sets = [set(5, 60, tag: .warmup), set(8, 110), set(8, 110), set(8, 110)]
        #expect(L.setSummary(sets, unit: .kg).text == "3 × 8, 110 kg")
        #expect(L.setSummary([set(10, 40, tag: .warmup), set(10, 40, tag: .warmup)], unit: .kg).text == "2 × 10, 40 kg")
        #expect(L.setSummary([set(8, 100), set(6, 90, tag: .backoff)], unit: .kg).text == "2 sets, top 100 kg × 8")
    }

    @Test func bodyweightSetsShowRepsOrARange() {
        let alike = L.setSummary([set(12, 0, mode: .bodyweight), set(12, 0, mode: .bodyweight)], unit: .kg)
        #expect(alike.text == "2 × 12")
        #expect(alike.spoken == "2 sets of 12 reps")
        let mixed = L.setSummary([set(12, 0, mode: .bodyweight), set(10, 0, mode: .bodyweight), set(8, 0, mode: .bodyweight)], unit: .kg)
        #expect(mixed.text == "3 sets, 8-12 reps")
        #expect(mixed.spoken == "3 sets, 8 to 12 reps")
        // A weighted set logged without weight reads as reps only.
        #expect(L.setSummary([set(15, 0), set(15, 0)], unit: .kg).text == "2 × 15")
    }

    @Test func timedSetsUseTheSetRowsDurations() {
        let alike = L.setSummary([set(0, 0, mode: .timed, seconds: 45), set(0, 0, mode: .timed, seconds: 45)], unit: .kg)
        #expect(alike.text == "2 × 0:45")
        #expect(alike.spoken == "2 sets of 45 seconds")
        let mixed = L.setSummary([set(0, 0, mode: .timed, seconds: 30), set(0, 0, mode: .timed, seconds: 90)], unit: .kg)
        #expect(mixed.text == "2 sets, 0:30-1:30")
        #expect(mixed.spoken == "2 sets, 30 seconds to 1 minute, 30 seconds")
    }

    @Test func distanceSetsUseTheSetRowsDistances() {
        #expect(L.setSummary([set(0, 0, mode: .distance, meters: 400), set(0, 0, mode: .distance, meters: 400)], unit: .kg).text == "2 × 400 m")
        #expect(L.setSummary([set(0, 0, mode: .distance, meters: 1000), set(0, 0, mode: .distance, meters: 500)], unit: .kg).text
            == "2 sets, 1.50 km total")
    }

    @Test func mixedTrackingModesShowTheCountOnly() {
        #expect(L.setSummary([set(8, 50), set(0, 0, mode: .timed, seconds: 30)], unit: .kg).text == "2 sets")
        #expect(L.setSummary([], unit: .kg).text == "")
    }

    @Test func exerciseRowsReadAsOnePhrase() {
        let model = L.model([workout(1, [entry("bench", [set(8, 100), set(8, 100), set(8, 100)])])], unit: .kg, now: now, calendar: calendar)
        let row = model.workouts[0].exercises[0]
        #expect(row.name == "Bench")
        #expect(row.summary == "3 × 8, 100 kg")
        #expect(row.accessibilityLabel == "Bench, 3 sets of 8 reps, 100 kg")
    }

    // MARK: What gets pre-filled

    @Test func completedSetsArePreFilledEditableWithTheirValuesAndTags() {
        var logged = set(8, 100, tag: .warmup)
        logged.rpe = 8; logged.completionTime = now; logged.restAfterSeconds = 90; logged.didSeedFromMemory = true
        let source = workout(1, [entry("bench", [logged, set(5, 120), set(5, 120, done: false)])])
        let entries = L.entriesToRepeat(source)
        #expect(entries.count == 1)
        let sets = entries[0].sets
        #expect(sets.map(\.reps) == [8, 5])
        #expect(sets.map(\.weight) == [100, 120])
        #expect(sets.map(\.tag) == [.warmup, .working])
        #expect(sets.allSatisfy { !$0.isCompleted && !$0.isGhost && !$0.autoWeight })
        #expect(sets.allSatisfy { $0.rpe == nil && $0.completionTime == nil && $0.restAfterSeconds == nil })
        #expect(entries[0].id != source.entries[0].id)
        #expect(entries[0].exerciseName == "Bench")
        #expect(entries[0].muscleGroups == ["Chest"])
        #expect(entries[0].plannedExerciseID == nil)
    }

    @Test func timedAndDistanceValuesArePreFilled() {
        let source = workout(1, [entry("plank", [set(0, 0, mode: .timed, seconds: 60)]),
                                 entry("rower", [set(0, 0, mode: .distance, seconds: 240, meters: 1000)])])
        let entries = L.entriesToRepeat(source)
        #expect(entries[0].sets[0].trackingMode == .timed)
        #expect(entries[0].sets[0].durationSeconds == 60)
        #expect(entries[1].sets[0].trackingMode == .distance)
        #expect(entries[1].sets[0].distanceMeters == 1000)
        #expect(entries[1].sets[0].durationSeconds == 240)
    }

    @Test func exercisesWithNothingDoneArePutAside() {
        let source = workout(1, [entry("bench", [set(8, 100)]), entry("fly", [set(12, 20, done: false)])])
        #expect(L.entriesToRepeat(source).map(\.exerciseID) == ["bench"])
    }

    @Test func olderHistoryWithoutCompletionKeepsItsLoggedSets() {
        let legacy = workout(30, [entry("bench", [set(8, 100, done: false), set(8, 100, done: false)])])
        #expect(L.entriesToRepeat(legacy).first?.sets.count == 2)
        #expect(L.repeatable([legacy]).count == 1)
    }

    @Test func placeholdersAndEmptySetsAreNeverPreFilled() {
        var placeholder = set(8, 100)
        placeholder.isAutoGeneratedPlaceholder = true
        let source = workout(1, [entry("bench", [set(8, 100), placeholder, set(0, 0)])])
        #expect(L.entriesToRepeat(source).first?.sets.count == 1)
        #expect(L.repeatable([workout(1, [entry("bench", [set(0, 0)])])]).isEmpty)
    }

    @Test func missingExercisesAreLeftOut() {
        let source = workout(1, [entry("custom_deleted", [set(8, 50)]), entry("bench", [set(8, 100)])])
        let entries = L.entriesToRepeat(source) { $0 != "custom_deleted" }
        #expect(entries.map(\.exerciseID) == ["bench"])
        let model = L.model([source], unit: .kg, isAvailable: { $0 != "custom_deleted" }, now: now, calendar: calendar)
        #expect(model.workouts[0].exercises.map(\.name) == ["Bench"])
    }

    @Test func supersetsKeepTheirGroupingUnderNewIds() {
        let group = UUID(), lone = UUID()
        let source = workout(1, [
            entry("bench", [set(8, 100)], group: group, order: 0),
            entry("row", [set(10, 60)], group: group, order: 1),
            entry("curl", [set(10, 15)], group: lone, order: 0),
            entry("pushdown", [set(12, 20, done: false)], group: lone, order: 1)
        ])
        let entries = L.entriesToRepeat(source)
        #expect(entries.map(\.exerciseID) == ["bench", "row", "curl"])
        #expect(entries[0].supersetGroupID != nil)
        #expect(entries[0].supersetGroupID == entries[1].supersetGroupID)
        #expect(entries[0].supersetGroupID != group)
        #expect(entries.map(\.orderInSuperset) == [0, 1, nil])
        // Its partner was not done, so curl is no longer a superset.
        #expect(entries[2].supersetGroupID == nil)
    }

    // MARK: Paging

    @Test func arrowsStopAtTheNewestAndOldest() {
        #expect(!L.canGoNewer(index: 0, count: 3))
        #expect(L.canGoOlder(index: 0, count: 3))
        #expect(L.canGoNewer(index: 1, count: 3) && L.canGoOlder(index: 1, count: 3))
        #expect(L.canGoNewer(index: 2, count: 3))
        #expect(!L.canGoOlder(index: 2, count: 3))
        #expect(!L.canGoOlder(index: 0, count: 1) && !L.canGoNewer(index: 0, count: 1))
        #expect(L.stepped(0, by: 1, count: 3) == 1)
        #expect(L.stepped(2, by: 1, count: 3) == 2)
        #expect(L.stepped(0, by: -1, count: 3) == 0)
        #expect(L.stepped(5, by: 0, count: 2) == 1)
    }

    @Test func onlyMostlyHorizontalSwipesPage() {
        #expect(L.swipeStep(dx: -80, dy: 10) == -1)
        #expect(L.swipeStep(dx: 80, dy: -10) == 1)
        #expect(L.swipeStep(dx: 30, dy: 0) == nil)
        #expect(L.swipeStep(dx: 80, dy: 70) == nil)
        #expect(L.swipeStep(dx: 5, dy: 200) == nil)
    }

    // MARK: Train row and hero

    @Test func lastWorkoutRowShowsAChevronOnlyWhenItOpensPastWorkouts() {
        let date = daysAgo(4)
        let opens = CutTrainLogic.rows(battle: nil, streakWeeks: nil, lastWorkout: ("Full Body", date),
                                       lastWorkoutOpensPastWorkouts: true, now: now, calendar: calendar)
        #expect(opens.first?.showsChevron == true)
        #expect(opens.first?.accessibilityHint == L.rowHint)
        #expect(opens.first?.value == "Full Body, Sat")
        let plain = CutTrainLogic.rows(battle: nil, streakWeeks: nil, lastWorkout: ("Full Body", date), now: now, calendar: calendar)
        #expect(plain.first?.showsChevron == false)
        #expect(plain.first?.accessibilityHint == nil)
        #expect(plain.first?.value == "Full Body, Sat")
    }

    @Test func onlyTheNoPlanHeroSaysNewWorkout() {
        #expect(CutTrainLogic.noPlanStartTitle == "New workout")
        #expect(CutStartSheetLogic.title("Start Workout") == "Start a workout")
    }
}
