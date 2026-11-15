import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutBattleDetailLogicTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static var facts: CutBattleFacts { .init(id: UUID(), type: .volume, status: .active, opponent: "Fixture Opponent", ownScore: 2000, otherScore: 1000,
        isChallenger: true, isOpponent: false, start: now, end: now.addingTimeInterval(7 * 86400)) }
    static func model(_ facts: CutBattleFacts) -> CutBattleDetailModel { CutBattleDetailLogic.model(facts, unit: .kg, locale: Locale(identifier: "en_US"), now: now) }
    @Test func activeLeadAndSplit() {
        let m = Self.model(Self.facts)
        #expect(m.state == .active); #expect(m.headline == "You lead by 1.0k kg with 7 days left"); #expect(m.headlineIsLime)
        #expect(m.split == 2.0 / 3); #expect(m.exit == "Leave battle"); #expect(!m.accepts); #expect(m.showsScores)
    }
    @Test func incomingAndOutgoing() {
        var f = Self.facts; f.status = .pending
        #expect(Self.model(f).state == .pending); #expect(Self.model(f).exit == "Cancel battle"); #expect(!Self.model(f).showsScores)
        #expect(Self.model(f).headline == "Waiting for Fixture Opponent to accept")
        f.isChallenger = false; f.isOpponent = true
        #expect(Self.model(f).state == .incoming); #expect(Self.model(f).accepts); #expect(Self.model(f).exit == "Decline battle"); #expect(Self.model(f).exitLabel == "Decline")
        #expect(Self.model(f).headline == "Fixture Opponent invited you")
    }
    @Test func completedResults() {
        var f = Self.facts; f.status = .completed
        #expect(Self.model(f).state == .won)
        #expect(Self.model(f).headline == "You won by 1.0k kg"); #expect(Self.model(f).headlineIsLime)
        f.ownScore = 500; #expect(Self.model(f).state == .lost); #expect(Self.model(f).headline == "Fixture Opponent won by 500 kg"); #expect(!Self.model(f).headlineIsLime)
        f.ownScore = 1000; #expect(Self.model(f).state == .tied); #expect(Self.model(f).exit == nil); #expect(Self.model(f).headline == "Tied at 1.0k kg")
    }
    @Test func inactiveAndExpired() {
        var f = Self.facts; f.end = Self.now
        #expect(Self.model(f).state == .expired); #expect(Self.model(f).headline == "Ended. You lead by 1.0k kg, final result soon")
        f.status = .declined; #expect(Self.model(f).state == .declined); #expect(Self.model(f).exit == nil)
        f.status = .cancelled; #expect(Self.model(f).state == .cancelled)
    }
    @Test func spectatorHasNoActions() {
        var f = Self.facts; f.isChallenger = false
        #expect(Self.model(f).exit == nil); #expect(!Self.model(f).accepts)
    }
    @Test func weightAndLocale() {
        let en = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        #expect(CutCompeteFormat.score(1000, type: .volume, unit: .lb, locale: en) == "2.2k")
        #expect(CutCompeteFormat.score(1000, type: .volume, unit: .lb, locale: de) == "2,2k")
        #expect(CutCompeteFormat.score(12.5, type: .runningDistance, unit: .lb, locale: de) == "12,5")
        #expect(CutCompeteFormat.score(12, type: .workoutCount, unit: .lb, locale: en) == "12")
    }
    @Test func timeWording() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        func time(_ seconds: Double) -> String { CutCompeteFormat.remaining(end: Self.now.addingTimeInterval(seconds), now: Self.now, calendar: c) }
        #expect(time(86400) == "1 day left"); #expect(time(2*86400) == "2 days left")
        #expect(time(3600) == "1 hour left"); #expect(time(7200) == "2 hours left")
        #expect(time(5) == "Less than 1 hour left"); #expect(time(-1) == "Ended")
    }
    @Test func exerciseRewardsRetainLiftAndEngraving() {
        var f = Self.facts; f.type = .exercise; f.targetMetric = "bench_press"
        let rewards = Self.model(f).rewards
        #expect(rewards.map(\.id) == [27,28]); #expect(rewards[0].liftID == "bench_press"); #expect(rewards[1].liftID == nil)
        #expect(rewards.map(\.xp) == ["+200 XP", "+400 XP"])
    }
    @Test func scoreUnitsPreserveEveryLegacyMetric() {
        let expected: [BattleType: String] = [.volume: "lb", .pr: "lb", .workoutCount: "workouts", .consistency: "days", .exercise: "reps", .runningDistance: "km"]
        for (type, label) in expected { #expect(CutCompeteFormat.unit(type, weight: .lb) == label) }
        // The legacy PR label uses the weight unit, although its score is a count.
        // Preserve that existing contract in this restyle and report the inconsistency.
        for type in [BattleType.pr, .consistency, .exercise, .workoutCount] {
            #expect(CutCompeteFormat.score(5, type: type, unit: .lb, locale: Locale(identifier: "en_US")) == "5")
        }
    }

    @Test func zeroScoreTieHasANeutralSplitLikeTheArena() {
        var facts = Self.facts; facts.ownScore = 0; facts.otherScore = 0
        let m = Self.model(facts)
        #expect(m.headline == "Tied with 7 days left"); #expect(m.split == 0.5); #expect(!m.headlineIsLime)
    }

    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    @Test func titleSubtitleAndSides() {
        var f = Self.facts; f.ownName = "Fixture Viewer"; f.opponentAvatarURL = "https://example.invalid/a.png"
        f.end = Self.now.addingTimeInterval(3 * 86400)
        let m = CutBattleDetailLogic.model(f, unit: .kg, locale: Locale(identifier: "en_US"), now: Self.now, calendar: Self.utc)
        #expect(m.title == "You vs Fixture Opponent")
        let weekday = f.end.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en_US"), calendar: Self.utc, timeZone: Self.utc.timeZone).weekday(.wide))
        #expect(m.subtitle == "Volume lifted, ends " + weekday)
        #expect(m.own.initials == "FV"); #expect(m.own.score == "2.0k"); #expect(m.other.initials == "FO"); #expect(m.other.avatarURL == f.opponentAvatarURL)
        f.end = Self.now.addingTimeInterval(20 * 86400)
        #expect(CutBattleDetailLogic.model(f, unit: .kg, locale: Locale(identifier: "en_US"), now: Self.now, calendar: Self.utc).subtitle.hasPrefix("Volume lifted, ends "))
        f.status = .pending
        #expect(CutBattleDetailLogic.model(f, unit: .kg, locale: Locale(identifier: "en_US"), now: Self.now, calendar: Self.utc).subtitle == "Volume lifted, 20 days")
    }
    @Test func datesAndRewardsAreVisibleRows() {
        let m = CutBattleDetailLogic.model(Self.facts, unit: .kg, locale: Locale(identifier: "en_US"), now: Self.now, calendar: Self.utc)
        #expect(m.details.map(\.label) == ["Runs", "Winner earns", "Finishing earns"])
        #expect(m.details[0].value.contains(" to "))
        #expect(m.details[1].value == "\(m.rewards[1].name), 35 kg, 400 XP")
        #expect(m.details[2].value == "\(m.rewards[0].name), 20 kg, 200 XP")
    }
    @Test func declinedAndCancelledHeadlines() {
        var f = Self.facts; f.status = .declined
        #expect(Self.model(f).headline == "Invitation declined"); #expect(!Self.model(f).showsScores)
        f.status = .cancelled; #expect(Self.model(f).headline == "Battle cancelled")
    }
    @Test func namesInitialsAndTheSingleNameRule() {
        #expect(CutCompeteFormat.initials("Yulia") == "YU"); #expect(CutCompeteFormat.initials("Fixture Opponent") == "FO")
        #expect(CutCompeteFormat.initials("fixture_alias") == "FA"); #expect(CutCompeteFormat.initials("") == "")
        #expect(CutCompeteFormat.shortName("Fixture Opponent") == "Fixture"); #expect(CutCompeteFormat.shortName("fixture_alias") == "fixture_alias")
    }
}
