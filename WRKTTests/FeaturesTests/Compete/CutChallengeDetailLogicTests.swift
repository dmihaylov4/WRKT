import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutChallengeDetailLogicTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static var facts: CutChallengeFacts { .init(id: UUID(), title: "Fixture Challenge", description: "Fixture description", type: .workoutCount,
        metric: "workouts", goal: 10, start: now, end: now.addingTimeInterval(14 * 86400), evergreen: false, difficulty: "Beginner", participantCount: 12,
        current: 6, percentage: 60, completed: false, participants: []) }
    func model(_ facts: CutChallengeFacts) -> CutChallengeDetailModel { CutChallengeDetailLogic.model(facts, unit: .kg, locale: Locale(identifier: "en_US"), now: Self.now) }
    @Test func notJoinedHasJoinAndNoProgress() {
        var f = Self.facts; f.current = nil
        let m = model(f)
        #expect(m.state == .notJoined); #expect(m.action == "Join Challenge"); #expect(!m.leaves); #expect(m.progress == nil)
    }
    @Test func joinedProgressAndLeave() {
        let m = model(Self.facts)
        #expect(m.state == .joined); #expect(m.action == "Leave Challenge"); #expect(m.leaves)
        #expect(m.progress == "6 / 10 workouts"); #expect(m.fraction == 0.6)
    }
    @Test func completedRetainsLeaveContract() {
        var f = Self.facts; f.completed = true; f.current = 10; f.percentage = 100
        let m = model(f)
        #expect(m.state == .completed); #expect(m.leaves); #expect(m.time == "Completed"); #expect(m.fraction == 1)
    }
    @Test func endedDoesNotInventNewActionRestrictions() {
        var f = Self.facts; f.end = Self.now.addingTimeInterval(-1)
        #expect(model(f).state == .ended); #expect(model(f).action == "Leave Challenge")
        f.current = nil
        #expect(model(f).action == "Join Challenge"); #expect(model(f).time == "Ended")
    }
    @Test func evergreenIsOngoing() {
        var f = Self.facts; f.evergreen = true; f.end = Self.now.addingTimeInterval(-1)
        #expect(model(f).state == .joined); #expect(model(f).time == "Ongoing")
        #expect(model(f).about.first(where: { $0.label == "Duration" })?.value == "Ongoing")
    }
    @Test func volumeAndLocale() {
        var f = Self.facts; f.type = .totalVolume; f.goal = 10000; f.current = 1500
        let m = CutChallengeDetailLogic.model(f, unit: .lb, locale: Locale(identifier: "de_DE"), now: Self.now)
        #expect(m.progress == "3,3k / 22,0k lb")
    }
    @Test func leaderboardKeepsOrderAndHighlightsViewer() {
        var f = Self.facts
        let first = CutChallengeFacts.Participant(id: UUID(), name: "fixture_leader", progress: 15, isViewer: false)
        let second = CutChallengeFacts.Participant(id: UUID(), name: "fixture_viewer", progress: 6, isViewer: true)
        f.participants = [first, second]
        let m = model(f)
        #expect(m.leaders.map(\.id) == [first.id, second.id]); #expect(m.leaders.map(\.rank) == ["1", "2"])
        #expect(m.leaders[0].percentage == "100%"); #expect(m.leaders[1].isViewer); #expect(m.leaders[1].progress == "6 / 10 workouts")
    }
    @Test func challengeUnits() {
        var f = Self.facts; f.type = .custom; f.metric = "conditioning_minutes"
        #expect(model(f).progress == "6 / 10 min")
        f.type = .streak; #expect(model(f).progress == "6 / 10 days")
        f.type = .specificExercise; #expect(model(f).progress == "6 / 10 reps")
        f.type = .custom; f.metric = "fixture_metric"; #expect(model(f).progress == "6 / 10 fixture_metric")
    }
    @Test func descriptionDifficultyAndRewardArePreserved() {
        var f = Self.facts; f.reward = .plate(id: 24, name: "Fixture Plate")
        let m = model(f)
        #expect(m.description == "Fixture description"); #expect(m.reward == f.reward)
        #expect(m.about.first(where: { $0.label == "Difficulty" })?.value == "Beginner")
        #expect(m.about.first(where: { $0.label == "Participants" })?.value == "12")
    }
}
