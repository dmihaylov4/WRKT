import Foundation
import UIKit
import Testing
@testable import WRKT

enum CutPostComposeFixtures {
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let now = Date(timeIntervalSince1970: 1_794_960_000)
    static var strength: CutPostComposeWorkoutFacts {
        .init(id: firstID, title: "Upper Body", date: now, icon: "dumbbell", exercises: 5, sets: 16)
    }
    static var cardio: CutPostComposeWorkoutFacts {
        .init(id: secondID, title: "Morning Run", date: now, icon: "figure.run", isCardio: true, durationSeconds: 1800, calories: 350)
    }
    static var weekly: CutPostComposeWeeklyFacts {
        .init(volumeKg: 12000, exercises: 18, sets: 55, strengthDone: 3, strengthTarget: 3, activeDone: 160, activeTarget: 150, streak: 4, superStreak: 2)
    }
    static var partner: CutPostComposeModel.Partner {
        .init(id: secondID, name: "Fixture Friend", handle: "@fixture_friend", initials: "FF")
    }
    static var completed: CompletedWorkout { .init(date: now, entries: [], workoutName: "Fixture workout") }
}

@MainActor
struct CutPostComposeLogicTests {
    private typealias F = CutPostComposeFixtures
    @Test func sharingRequiresAWorkoutAndIsDisabledWhileUploading() {
        #expect(!CutPostComposeLogic.canShare(selectedCount: 0, uploading: false))
        #expect(!CutPostComposeLogic.canShare(selectedCount: 1, uploading: true))
        #expect(CutPostComposeLogic.canShare(selectedCount: 2, uploading: false))
        let map = CutPostComposeLogic.model(title: "Share Workout", selected: [F.cardio], available: [], generatingMap: true)
        #expect(map.canShare && map.overlay == "Preparing map...")
    }
    @Test func workoutStatesPreservePreselectionDuringLoading() {
        #expect(CutPostComposeLogic.model(title: "Share", selected: [], available: [], loadingWorkouts: true).workoutState == .loading)
        #expect(CutPostComposeLogic.model(title: "Share", selected: [], available: []).workoutState == .empty)
        #expect(CutPostComposeLogic.model(title: "Share", selected: [], available: [F.strength]).workoutState == .choose)
        #expect(CutPostComposeLogic.model(title: "Share", selected: [F.strength], available: [], loadingWorkouts: true).workoutState == .selected)
    }
    @Test func attachedImageIsFirstPublicAndNotRemovable() {
        let photos = CutPostComposeLogic.photos(attached: true, pickedPrivacy: [false, true], map: true)
        #expect(photos.map(\.kind) == [.attached, .picked(0), .picked(1), .map])
        #expect(photos.map(\.canRemove) == [false, true, true, false])
        #expect(photos.map(\.privacy) == [true, false, true, true])
    }
    @Test func anAttachedAwardSaysWhichWorkoutItGoesOutWith() {
        let award = CutPostComposeLogic.model(title: "Share Award", selected: [F.cardio], available: [], attached: true)
        #expect(award.workoutNote == CutPostComposeLogic.attachedWorkoutNote)
        #expect(CutPostComposeLogic.workoutSectionTitle(award) == "Posted with")
        let plain = CutPostComposeLogic.model(title: "Share Workout", selected: [F.cardio], available: [])
        #expect(plain.workoutNote == nil && CutPostComposeLogic.workoutSectionTitle(plain) == "Workout")
        let session = CutPostComposeLogic.model(title: "Share", selected: [F.cardio, F.strength], available: [])
        #expect(CutPostComposeLogic.workoutSectionTitle(session) == "Session")
        let weekly = CutPostComposeLogic.model(title: "Share", selected: [F.strength], available: [], weekly: F.weekly, attached: true)
        #expect(weekly.workoutNote == nil && CutPostComposeLogic.workoutSectionTitle(weekly) == "Weekly Progress")
    }
    @Test func theAwardPictureIsRecognisedByItsFileNameAndIsNotAMap() {
        let award = PostImage(storagePath: "workout-images-public/u/year_award_1794960000_0.jpg", isPublic: true)
        #expect(award.isYearAwardImage && !award.isGeneratedMapImage)
        #expect(!PostImage(storagePath: "workout-images-public/u/workout_1794960000_0.jpg", isPublic: true).isYearAwardImage)
        #expect(!PostImage(storagePath: "workout-images-public/u/route_map_1794960000_0.jpg", isPublic: true).isYearAwardImage)
    }
    @Test func missingPrivacyMetadataDoesNotHideAPickedPhoto() {
        let photos = CutPostComposeLogic.photos(attached: false, pickedPrivacy: [nil, false], map: false)
        #expect(photos.count == 2 && photos[0].privacy == nil)
        #expect(photos[0].canRemove)
    }
    @Test func publicAwardInitializerKeepsImageCaptionWorkoutAndTitle() {
        let image = UIImage()
        let workout = F.completed
        let view = PostCreationView(attachedImage: image, caption: " Fixture year\nSecond line ", workout: workout, title: "Share year")
        #expect(view.attachedImage === image)
        #expect(view.initialCaption == " Fixture year\nSecond line " && view.navigationTitle == "Share year")
        #expect(view.initialWorkouts.map(\.id) == [workout.id])
        #expect(view.initialMapImage == nil && view.weeklyStats == nil)
    }
    @Test func publicWorkoutAndWeeklyInitializersRemainAvailable() {
        let workout = F.completed
        let image = UIImage()
        #expect(PostCreationView(workout: workout, mapImage: image).initialMapImage === image)
        let stats = WeeklyProgressStats(weekStart: F.now, totalVolumeKg: 12000, totalExercises: 18, totalSets: 55,
            strengthDaysDone: 3, strengthTarget: 3, activeMinutesDone: 160, activeMinutesTarget: 150, streak: 4, superStreak: 2)
        let view = PostCreationView(workouts: [workout], stats: stats)
        #expect(view.initialWorkouts.map(\.id) == [workout.id])
        #expect(view.navigationTitle == "Share Progress" && view.weeklyStats?.streak == 4)
    }
    @Test func multiSelectionTogglesAndCommitsInAvailableOrder() {
        let first = F.firstID, second = F.secondID
        var ids = CutPostComposeLogic.toggledSelection([], id: second)
        ids = CutPostComposeLogic.toggledSelection(ids, id: first)
        #expect(CutPostComposeLogic.committedSelection(availableIDs: [first, second], pending: ids) == [first, second])
        ids = CutPostComposeLogic.toggledSelection(ids, id: first)
        #expect(ids == [second])
        #expect(!CutPostComposeLogic.canFinishSelection([]))
    }
    @Test func unavailablePreselectionPreservesTheLegacyPickerEdgeCase() {
        #expect(CutPostComposeLogic.canFinishSelection([F.firstID]))
        #expect(CutPostComposeLogic.committedSelection(availableIDs: [F.secondID], pending: [F.firstID]).isEmpty)
    }
    @Test func weeklySummaryKeepsEveryMetricAndHidesPartnerTagging() {
        let model = CutPostComposeLogic.model(title: "Share Progress", selected: [F.strength, F.cardio], available: [], weekly: F.weekly, partner: F.partner)
        #expect(model.weeklyStats.flatMap { $0 }.map(\.label) == ["Tonnage", "Exercises", "Sets", "Strength", "Active min", "Wk streak"])
        #expect(model.superStreak == "Super Streak: 2 weeks" && model.sessionHint == "2 sessions included")
        #expect(!model.showsPartner)
    }
    @Test func partnerTaggingRequiresSelectedWorkoutsAndKeepsTheChosenPerson() {
        #expect(!CutPostComposeLogic.model(title: "Share", selected: [], available: []).showsPartner)
        let model = CutPostComposeLogic.model(title: "Share", selected: [F.strength], available: [], partner: F.partner, loadingFriends: true)
        #expect(model.showsPartner && model.partner == F.partner && model.isLoadingFriends)
    }
    @Test func workoutRowsKeepStrengthCardioAndHealthKitOnlyStats() {
        #expect(CutPostComposeLogic.workout(F.strength).stats == "5 exercises · 16 sets")
        #expect(CutPostComposeLogic.workout(F.cardio).stats == "350 cal · 30 min")
        var health = F.strength; health.isHealthKitOnlyStrength = true; health.durationSeconds = 3600; health.calories = 400; health.heartRate = 128
        #expect(CutPostComposeLogic.workout(health).stats == "60 min · 400 cal · 128 bpm")
    }
    @Test func visibilityDescriptionsStayExact() {
        #expect(CutPostComposeLogic.visibilityDescription(.publicPost) == "Anyone can see this post")
        #expect(CutPostComposeLogic.visibilityDescription(.friends) == "Only your friends can see this")
        #expect(CutPostComposeLogic.visibilityDescription(.privatePost) == "Only you can see this")
    }
    @Test func mapGenerationKeepsCallerAndAwardGuards() {
        #expect(CutPostComposeLogic.shouldGenerateMaps(initialWorkoutProvided: false, attached: false, selection: [F.firstID]))
        #expect(!CutPostComposeLogic.shouldGenerateMaps(initialWorkoutProvided: true, attached: false, selection: [F.firstID]))
        #expect(!CutPostComposeLogic.shouldGenerateMaps(initialWorkoutProvided: false, attached: true, selection: [F.firstID]))
        #expect(!CutPostComposeLogic.shouldGenerateMaps(initialWorkoutProvided: false, attached: false, selection: []))
    }
    @Test func uploadOverlayTakesPrecedenceAndErrorsKeepRetryability() {
        let model = CutPostComposeLogic.model(title: "Share", selected: [F.strength], available: [], uploading: true, generatingMap: true,
                                              errorTitle: "Photo Load Failed", errorMessage: "Fixture failure", errorIsRetryable: false)
        #expect(model.overlay == "Sharing workout...")
        #expect(model.errorTitle == "Photo Load Failed" && model.errorMessage == "Fixture failure" && !model.errorIsRetryable)
    }
}
