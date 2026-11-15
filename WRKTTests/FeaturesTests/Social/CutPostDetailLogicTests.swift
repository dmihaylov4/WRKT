import Foundation
import Testing
@testable import WRKT

/// Fixtures for the Cut post detail. Invented people; times are relative to CutSocialFixtures.now.
enum CutPostDetailFixtures {
    typealias F = CutSocialFixtures
    static let me = UUID()
    static let alex = UUID()

    static func exercise(_ name: String, sets: [(String, SetTag)], volume: Double, timed: Bool = false) -> CutPostDetailFacts.ExerciseFacts {
        CutPostDetailFacts.ExerciseFacts(
            name: name,
            sets: sets.map { .init(value: $0.0, tag: $0.1, workSeconds: timed ? 42 : nil, restSeconds: timed ? 120 : nil) },
            volumeKg: volume,
            workSeconds: timed ? 168 : 0,
            restSeconds: timed ? 480 : 0
        )
    }

    static var strengthWorkout: CutPostDetailFacts.WorkoutFacts {
        .init(
            name: "Lower Body", durationSeconds: 3_130, calories: 410, sets: 24,
            exercises: [
                exercise("Romanian Deadlift", sets: [("60 kg x 10", .warmup), ("90 kg x 8", .working), ("95 kg x 8", .working), ("100 kg x 7", .working)],
                         volume: 2_420, timed: true),
                exercise("Back Squat", sets: [("85 kg x 6", .working), ("85 kg x 6", .working), ("85 kg x 6", .working), ("85 kg x 6", .working)],
                         volume: 2_040),
                exercise("Walking Lunge", sets: [("20 kg x 12", .working), ("20 kg x 12", .working), ("20 kg x 12", .backoff)], volume: 720)
            ],
            averageHeartRate: 128, maxHeartRate: 171, minHeartRate: 84,
            heartRateSamples: (0..<40).map { HeartRateSample(timestamp: F.now.addingTimeInterval(Double($0) * 60), bpm: 100 + Double(($0 * 7) % 60)) }
        )
    }

    static var cardioWorkout: CutPostDetailFacts.WorkoutFacts {
        .init(
            name: "Morning Run", isCardio: true, durationSeconds: 2_642, calories: 610, distanceMeters: 8_400,
            averageHeartRate: 151, maxHeartRate: 178, minHeartRate: 102,
            heartRateSamples: (0..<30).map { HeartRateSample(timestamp: F.now.addingTimeInterval(Double($0) * 80), bpm: 130 + Double(($0 * 5) % 40)) },
            splits: (1...8).map { KilometerSplit(number: $0, distanceKm: 1, durationSec: 300 + ($0 * 13) % 40) }
                + [KilometerSplit(number: 9, distanceKm: 0.4, durationSec: 130)],
            zones: [
                HRZoneSummary(zone: 1, name: "Light", minutes: 3, rangeDisplay: "", colorHex: ""),
                HRZoneSummary(zone: 2, name: "Moderate", minutes: 9, rangeDisplay: "", colorHex: ""),
                HRZoneSummary(zone: 3, name: "Aerobic", minutes: 18, rangeDisplay: "", colorHex: ""),
                HRZoneSummary(zone: 4, name: "Threshold", minutes: 12, rangeDisplay: "", colorHex: ""),
                HRZoneSummary(zone: 5, name: "Max", minutes: 2, rangeDisplay: "", colorHex: "")
            ],
            power: 262, cadence: 172, strideLength: 1.08, groundContact: 241, verticalOscillation: 8.6
        )
    }

    static var comments: [CutPostDetailFacts.CommentFacts] {
        [
            .init(id: UUID(), userId: alex, name: "Alex J.", username: "alex", text: "That RDL number though. @maria see you Thursday.",
                  createdAt: F.now.addingTimeInterval(-38 * 60),
                  replies: [.init(id: UUID(), userId: UUID(), name: "Maria K.", username: "maria", text: "@alex bring your knee sleeves.",
                                  createdAt: F.now.addingTimeInterval(-31 * 60))]),
            .init(id: UUID(), userId: UUID(), name: "Sam P.", username: "samp", text: "Complaint denied. Hamstrings must train.",
                  createdAt: F.now.addingTimeInterval(-20 * 60)),
            .init(id: UUID(), userId: me, name: "Dimitar M.", username: "dimitar", text: "Big session. Saving this split.",
                  createdAt: F.now.addingTimeInterval(-4 * 60))
        ]
    }

    static func strength(comments: [CutPostDetailFacts.CommentFacts] = comments, loading: Bool = false, error: String? = nil) -> CutPostDetailFacts {
        CutPostDetailFacts(post: F.strength(), workouts: [strengthWorkout], currentUserId: me,
                           comments: comments, isLoadingComments: loading, error: error)
    }

    static func cardio(canRefresh: Bool = true) -> CutPostDetailFacts {
        CutPostDetailFacts(post: F.cardio(), workouts: [cardioWorkout], currentUserId: me, canRefreshCardio: canRefresh,
                           comments: Array(comments.prefix(1)))
    }

    static func multi() -> CutPostDetailFacts {
        var post = F.strength("Strength and cardio")
        post.kind = .multi(count: 2, cardioCount: 1, volumeKg: 5_180, sets: 24, durationSeconds: 5_772)
        return CutPostDetailFacts(post: post, workouts: [strengthWorkout, cardioWorkout], currentUserId: me, comments: [])
    }

    static func long() -> CutPostDetailFacts {
        var facts = strength()
        facts.post = F.longPost()
        facts.workouts[0].exercises.insert(
            exercise("Single Leg Romanian Deadlift on a Deficit Platform with Pause", sets: [("24 kg x 10", .working)], volume: 240), at: 0)
        facts.comments.insert(.init(id: UUID(), userId: UUID(), name: "Maximiliana Alexandrova-Fitzgerald Montgomery", username: "maxi",
                                    text: String(repeating: "Unreal pace for a Tuesday, and the hill at the end did not look easy at all. ", count: 3),
                                    createdAt: F.now.addingTimeInterval(-2 * 86_400)), at: 0)
        return facts
    }
}

struct CutPostDetailLogicTests {
    private typealias D = CutPostDetailFixtures
    private typealias F = CutSocialFixtures

    private func model(_ facts: CutPostDetailFacts) -> CutPostDetailModel {
        CutPostDetailLogic.model(facts, now: F.now, weightUnit: .kg, locale: F.locale)
    }

    // MARK: Post

    @Test func detailUsesTheFeedRow() {
        let facts = D.strength()
        let detail = model(facts)
        #expect(detail.post == CutSocialLogic.row(facts.post, now: F.now, weightUnit: .kg, locale: F.locale))
        #expect(detail.post.title == "Lower Body")
    }

    @Test func likesNeverShowBelowOneWhileLiked() {
        #expect(CutPostDetailLogic.displayLikes(0, isLiked: true) == 1)
        #expect(CutPostDetailLogic.displayLikes(5, isLiked: false) == 5)
        #expect(CutPostDetailLogic.likesLabel(0) == nil)
        #expect(CutPostDetailLogic.likesLabel(1) == "1 like")
        #expect(CutPostDetailLogic.likesLabel(12) == "12 likes")
    }

    // MARK: Workout

    @Test func strengthListsExercisesWithSetsVolumeAndTiming() {
        let detail = model(D.strength())
        #expect(detail.workouts.isEmpty)
        #expect(detail.exercises.map(\.title) == ["Romanian Deadlift", "Back Squat", "Walking Lunge"])
        #expect(detail.exercises[0].line == "4 sets, 2,420 kg")
        #expect(detail.exercises[0].sets.map(\.number) == ["1", "2", "3", "4"])
        #expect(detail.exercises[0].sets[0].note == "Warm-up, work 0:42, rest 2:00")
        #expect(detail.exercises[0].sets[1].note == "Work 0:42, rest 2:00")
        #expect(detail.exercises[0].timing == "Work 2:48, rest 8:00")
        #expect(detail.exercises[1].sets[0].note == nil)
        #expect(detail.exercises[1].timing == nil)
        #expect(detail.exercises[2].sets[2].note == "Back-off")
        #expect(detail.splits.isEmpty)
        #expect(detail.refreshTitle == nil)
    }

    @Test func strengthHeartRateAndEnergy() {
        let detail = model(D.strength())
        #expect(detail.heartRate.count == 1)
        #expect(detail.heartRate[0].title == nil)
        #expect(detail.heartRate[0].stats.map(\.value) == ["128", "171", "84"])
        #expect(detail.heartRate[0].bars.count == 16)
        #expect(detail.performance == [[CutStatColumn(value: "410", label: "Energy", unit: "kcal")]])
    }

    @Test func volumeFollowsThePreferredUnit() {
        let detail = CutPostDetailLogic.model(D.strength(), now: F.now, weightUnit: .lb, locale: F.locale)
        #expect(detail.exercises[0].line.hasSuffix("lb"))
    }

    @Test func cardioShowsSplitsZonesAndPerformance() {
        let detail = model(D.cardio())
        #expect(detail.exercises.isEmpty)
        #expect(detail.splits.count == 9)
        #expect(detail.splits.last?.label == "8.4")
        #expect(detail.splits.filter(\.isFastest).count == 1)
        #expect(detail.heartRate[0].zones.map(\.label) == ["Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5"])
        #expect(detail.heartRate[0].zones[2].time == "18:00")
        let labels = detail.performance.flatMap { $0.map(\.label) }
        #expect(labels == ["Energy", "Avg speed", "Power", "Cadence", "Stride", "Ground contact", "Oscillation"])
        #expect(detail.performance.allSatisfy { $0.count <= 2 })
        #expect(detail.refreshTitle == "Refresh details")
    }

    @Test func cardioRefreshOnlyForTheAuthorAndSaysLoadWithoutZones() {
        #expect(model(D.cardio(canRefresh: false)).refreshTitle == nil)
        var facts = D.cardio()
        facts.workouts[0].zones = []
        facts.isRefreshingCardio = true
        let detail = model(facts)
        #expect(detail.refreshTitle == "Load details")
        #expect(detail.isRefreshing)
    }

    @Test func multiWorkoutListsWorkoutsAndHeartRatePerWorkout() {
        let detail = model(D.multi())
        #expect(detail.workouts.map(\.title) == ["Lower Body", "Morning Run"])
        #expect(detail.workouts[0].line == "52:10")
        #expect(detail.workouts[0].value == "410 kcal")
        #expect(detail.workouts[1].line == "8.40 km, 44:02")
        #expect(detail.heartRate.map(\.title) == ["Lower Body", "Morning Run"])
        #expect(detail.splits.isEmpty)
        #expect(detail.performance == [[CutStatColumn(value: "1,020", label: "Energy", unit: "kcal")]])
    }

    @Test func weeklyAndBattlePostsShowNoWorkoutSections() {
        var facts = D.strength()
        facts.post = F.weekly()
        let detail = model(facts)
        #expect(detail.exercises.isEmpty && detail.heartRate.isEmpty && detail.performance.isEmpty)
        facts.post = F.battle()
        #expect(model(facts).exercises.isEmpty)
    }

    @Test func hourLongDurationsDropSeconds() {
        #expect(CutPostDetailLogic.shortDuration(3_725) == "1:02")
        #expect(CutPostDetailLogic.shortDuration(125) == "2:05")
    }

    // MARK: Comments

    @Test func commentsFlattenRepliesAndOnlyOwnTopLevelCanBeDeleted() throws {
        guard case let .list(rows) = model(D.strength()).comments else { Issue.record("Expected comments"); return }
        #expect(rows.map(\.name) == ["Alex J.", "Maria K.", "Sam P.", "You"])
        #expect(rows.map(\.isReply) == [false, true, false, false])
        #expect(rows.map(\.canReply) == [true, false, true, true])
        #expect(rows.map(\.canDelete) == [false, false, false, true])
        #expect(rows[0].initials == "AJ")
        #expect(rows[0].time.contains("38") && rows[0].time.hasSuffix("ago"))
    }

    @Test func commentStates() {
        #expect(model(D.strength(comments: [], loading: true)).comments == .loading)
        #expect(model(D.strength(comments: [], error: "Network down")).comments == .failed("Network down"))
        #expect(model(D.strength(comments: [])).comments == .empty)
        // With comments showing, an error moves to the composer.
        let detail = model(D.strength(error: "Failed to delete comment"))
        #expect(detail.composer.error == "Failed to delete comment")
        if case .list = detail.comments {} else { Issue.record("Comments should still show") }
    }

    @Test func composerSendsOnlyNonEmptyTextAndNamesTheReply() {
        var facts = D.strength()
        #expect(model(facts).composer.canSend == false)
        facts.commentText = "   "
        #expect(model(facts).composer.canSend == false)
        facts.commentText = "Nice"
        #expect(model(facts).composer.canSend)
        facts.isPostingComment = true
        #expect(model(facts).composer.canSend == false)
        facts.replyingTo = .init(id: D.alex, username: "alex", name: "Alex J.")
        #expect(model(facts).composer.replyingTo == "Replying to @alex")
        facts.suggestions = [.init(id: UUID(), username: "maria", name: "Maria K."), .init(id: UUID(), username: "mo")]
        #expect(model(facts).composer.suggestions.map(\.name) == ["Maria K.", "mo"])
        #expect(model(facts).composer.suggestions.map(\.handle) == ["@maria", "@mo"])
    }

    @Test func mentionsSplitIntoSegments() {
        let segments = CutPostDetailLogic.segments("Nice @alex_j, see @maria.")
        #expect(segments.map(\.text) == ["Nice ", "@alex_j", ", see ", "@maria", "."])
        #expect(segments.map(\.isMention) == [false, true, false, true, false])
        #expect(CutPostDetailLogic.segments("plain").map(\.text) == ["plain"])
    }
}
