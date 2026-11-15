import Foundation
import Testing
@testable import WRKT

/// Fixture facts for the Cut Preferences logic and capture tests.
enum CutPreferencesFixtures {
    static let zones: [CutPreferencesFacts.Zone] = [
        .init(zone: 1, name: "Light", range: "95-114 bpm"),
        .init(zone: 2, name: "Moderate", range: "114-133 bpm"),
        .init(zone: 3, name: "Aerobic", range: "133-152 bpm"),
        .init(zone: 4, name: "Threshold", range: "152-171 bpm"),
        .init(zone: 5, name: "Max", range: "171-190 bpm")
    ]

    static let customExercises: [CutPreferencesFacts.CustomExercise] = [
        .init(id: "custom-landmine", name: "Landmine Press", primaryMuscle: "Shoulders", mechanic: "compound", equipment: "Barbell"),
        .init(id: "custom-pull", name: "Cable Pull-Through", primaryMuscle: "Glutes", mechanic: nil, equipment: "Cable")
    ]

    static var signedIn: CutPreferencesFacts {
        CutPreferencesFacts(
            age: 34, bodyweightKg: 82.5, unit: .kg,
            restTimerEnabled: true, compoundSeconds: 150, isolationSeconds: 90,
            maxHR: 188, zones: zones, zonesMethodDescription: "Max HR from your age (220 - age).",
            customExercises: customExercises, isSignedIn: true, smartNudgesEnabled: true,
            notificationsAuthorized: false, hasWeeklyGoal: true, shortVersion: "2.4.1", buildNumber: "318")
    }

    static var local: CutPreferencesFacts {
        CutPreferencesFacts(
            age: nil, bodyweightKg: 70, unit: .lb,
            restTimerEnabled: false, zones: zones, zonesMethodDescription: "Set your age in Profile to get personalized zones.",
            customExercises: [], isSignedIn: false, smartNudgesEnabled: false,
            notificationsAuthorized: false, hasWeeklyGoal: false, shortVersion: "2.4.1", buildNumber: "318")
    }
}

@Suite("Cut Preferences logic")
struct CutPreferencesLogicTests {
    private typealias F = CutPreferencesFixtures

    // MARK: Rows per state

    @Test func signedInShowsEveryGroup() {
        let model = CutPreferencesLogic.model(F.signedIn)
        #expect(model.showsSocial)
        #expect(model.showsRestTimerDetails)
        #expect(model.showsResetWeeklyGoal)
        #expect(model.showsNotificationSettingsLink)
        #expect(model.customExercises.count == 2)
        #expect(model.zones.count == 5)
    }

    @Test func localModeHidesSocialTimerDetailsAndGoalReset() {
        let model = CutPreferencesLogic.model(F.local)
        #expect(!model.showsSocial)
        #expect(!model.showsRestTimerDetails)
        #expect(!model.showsResetWeeklyGoal)
        #expect(!model.showsNotificationSettingsLink)
        #expect(model.customExercises.isEmpty)
    }

    @Test func notificationSettingsLinkOnlyWhenNudgesAreOnButNotAllowed() {
        #expect(CutPreferencesLogic.showsNotificationSettingsLink(nudgesEnabled: true, authorized: false))
        #expect(!CutPreferencesLogic.showsNotificationSettingsLink(nudgesEnabled: true, authorized: true))
        #expect(!CutPreferencesLogic.showsNotificationSettingsLink(nudgesEnabled: false, authorized: false))
    }

    @Test func footersFollowTheirSwitches() {
        #expect(CutPreferencesLogic.workoutFooter(restTimerEnabled: true).hasPrefix("Rest timer starts automatically"))
        #expect(CutPreferencesLogic.workoutFooter(restTimerEnabled: false).hasPrefix("Control haptic feedback"))
        #expect(CutPreferencesLogic.notificationsFooter(nudgesEnabled: true).hasPrefix("You'll receive notifications"))
        #expect(CutPreferencesLogic.notificationsFooter(nudgesEnabled: false).hasPrefix("Enable smart nudges"))
        #expect(CutPreferencesLogic.model(F.signedIn).zonesFooter == "Max HR from your age (220 - age).")
    }

    // MARK: Age

    @Test func ageLine() {
        #expect(CutPreferencesLogic.model(F.signedIn).age == "34 years")
        #expect(CutPreferencesLogic.model(F.local).age == "Not set")
    }

    // MARK: Bodyweight

    @Test func bodyweightLineUsesTheUnit() {
        #expect(CutPreferencesLogic.bodyweightLine(kg: 82.5, unit: .kg) == "82.5 kg")
        #expect(CutPreferencesLogic.bodyweightLine(kg: 80, unit: .kg) == "80 kg")
        #expect(CutPreferencesLogic.bodyweightLine(kg: 82.5, unit: .lb) == WeightUnit.lb.format(82.5))
        #expect(CutPreferencesLogic.bodyweightLine(kg: 82.5, unit: nil) == "82.5 kg")
    }

    @Test func bodyweightWheelSplitsAtTheTenth() {
        #expect(CutPreferencesLogic.wholeKg(82.5) == 82)
        #expect(CutPreferencesLogic.tenths(82.5) == 5)
        // 70.3 is stored as 70.29999...; the wheel must show 3, not 2.
        #expect(CutPreferencesLogic.tenths(70.3) == 3)
        #expect(CutPreferencesLogic.wholeKg(70.3) == 70)
        // 79.96 rounds up to the next whole kilogram.
        #expect(CutPreferencesLogic.wholeKg(79.96) == 80)
        #expect(CutPreferencesLogic.tenths(79.96) == 0)
        #expect(CutPreferencesLogic.weight(wholeKg: 82, tenths: 5) == 82.5)
        #expect(CutPreferencesLogic.weight(wholeKg: 70, tenths: 3) == 70.3)
        #expect(CutPreferencesLogic.wholeKgRange == 30...200)
        #expect(CutPreferencesLogic.tenthsRange == 0...9)
    }

    // MARK: Units and increments

    @Test func incrementOptionsPerUnitKeepTheStoredSteps() {
        let kg = CutPreferencesLogic.incrementOptions(unit: .kg)
        #expect(kg.map(\.value) == [0.5, 1.0, 2.5])
        #expect(kg.map(\.label) == ["0.5 kg", "1 kg", "2.5 kg"])
        let lb = CutPreferencesLogic.incrementOptions(unit: .lb)
        #expect(lb.map(\.value) == [0.5, 1.0, 2.5])
        #expect(lb.map(\.label) == ["1.25 lb", "2.5 lb", "5 lb"])
        #expect(CutPreferencesLogic.model(F.local).incrementOptions == lb)
        #expect(CutPreferencesLogic.unitOptions.map(\.value) == ["kg", "lb"])
    }

    // MARK: Rest timer

    @Test func restLinesAndParsing() {
        #expect(CutPreferencesLogic.restLine(150) == "2:30")
        #expect(CutPreferencesLogic.restLine(90) == "1:30")
        #expect(CutPreferencesLogic.restLine(600) == "10:00")
        #expect(CutPreferencesLogic.parseRest("3:00") == 180)
        #expect(CutPreferencesLogic.parseRest(" 2:30 ") == 150)
        #expect(CutPreferencesLogic.parseRest("90") == 90)
        #expect(CutPreferencesLogic.parseRest("1:2:3") == nil)
        #expect(CutPreferencesLogic.parseRest("") == nil)
    }

    @Test func typedRestIsClampedOrIgnored() {
        #expect(CutPreferencesLogic.typedRest("5", current: 120) == 30)
        #expect(CutPreferencesLogic.typedRest("20:00", current: 120) == 600)
        #expect(CutPreferencesLogic.typedRest("2:45", current: 120) == 165)
        #expect(CutPreferencesLogic.typedRest("x", current: 120) == 120)
        #expect(CutPreferencesLogic.filteredRestInput("2:3a0 ") == "2:30")
    }

    @Test func restStepsStopAtTheBounds() {
        #expect(CutPreferencesLogic.bumpedRest(90, by: 30) == 120)
        #expect(CutPreferencesLogic.bumpedRest(90, by: -30) == 60)
        #expect(CutPreferencesLogic.bumpedRest(30, by: -30) == nil)
        #expect(CutPreferencesLogic.bumpedRest(600, by: 30) == nil)
        #expect(CutPreferencesLogic.bumpedRest(45, by: -30) == 30)
    }

    // MARK: Other rows

    @Test func customExerciseDetailLines() {
        let rows = CutPreferencesLogic.model(F.signedIn).customExercises
        #expect(rows.map(\.detail) == ["Shoulders, Compound, Barbell", "Glutes, Cable"])
        #expect(CutPreferencesLogic.customDetail(.init(id: "x", name: "X")) == "Unknown")
    }

    @Test func zoneRowsAndMaxHeartRate() {
        let model = CutPreferencesLogic.model(F.signedIn)
        #expect(model.maxHeartRate == "188 bpm")
        #expect(model.zones.first?.title == "Zone 1, Light")
        #expect(model.zones.first?.range == "95-114 bpm")
    }

    @Test func versionLine() {
        #expect(CutPreferencesLogic.version(short: "2.4.1", build: "318") == "v2.4.1 (318)")
        #expect(CutPreferencesLogic.version(short: nil, build: nil) == "v? (?)")
    }

    @Test func alertCopyKeepsTheCounts() {
        #expect(CutPreferencesLogic.clearPlansButton(4) == "Clear 4 plans")
        #expect(CutPreferencesLogic.clearPlansMessage(plans: 4, splits: 1)
                == "This will permanently delete all 4 planned workouts and 1 workout splits from the planner. This cannot be undone.")
        #expect(!CutPreferencesLogic.resetFooter.contains("\u{26A0}"))
    }

    // MARK: CSV

    @Test func csvMatchesTheLegacyFile() {
        let utc = TimeZone(identifier: "UTC")!
        let early = CompletedWorkout(date: Date(timeIntervalSince1970: 1_794_571_200), entries: [
            WorkoutEntry(exerciseID: "bench", exerciseName: "Bench Press", muscleGroups: ["Chest"], sets: [
                SetInput(reps: 5, weight: 100, tag: .working, autoWeight: false, isCompleted: true),
                SetInput(reps: 8, weight: 80.5, tag: .backoff, autoWeight: false, isCompleted: false)
            ])
        ])
        let late = CompletedWorkout(date: Date(timeIntervalSince1970: 1_794_657_600), entries: [
            WorkoutEntry(exerciseID: "squat", exerciseName: "Squat", muscleGroups: ["Legs"], sets: [
                SetInput(reps: 10, weight: 60, tag: .warmup, autoWeight: false, isCompleted: true)
            ])
        ])
        let csv = CutPreferencesLogic.csv([late, early], timeZone: utc)
        #expect(csv == """
        Date,Exercise,Set Number,Tag,Reps,Weight (kg),Notes
        "2026-11-13 12:00:00","Bench Press",1,"Working",5,100.0,"\u{2713}"
        "2026-11-13 12:00:00","Bench Press",2,"Back-off",8,80.5,""
        "2026-11-14 12:00:00","Squat",1,"Warm-up",10,60.0,"\u{2713}"

        """)
        #expect(CutPreferencesLogic.csv([]) == "Date,Exercise,Set Number,Tag,Reps,Weight (kg),Notes\n")
    }
}
