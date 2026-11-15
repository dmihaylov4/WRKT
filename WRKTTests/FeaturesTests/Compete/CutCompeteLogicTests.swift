import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
@Suite struct CutCompeteLogicTests {
    static let en = Locale(identifier: "en_US")
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func item(_ kind: CutCompeteItem.Kind = .battle) -> CutCompeteItem { .init(id: .battle(UUID()), kind: kind, title: "Fixture Opponent", line: "Fixture line") }
    func challenge(_ kind: CutCompeteItem.Kind = .challenge) -> CutCompeteItem { .init(id: .challenge(UUID()), kind: kind, title: "Fixture Challenge", line: "Fixture line") }

    @Test func sectionsAndLimits() {
        let incoming = (0..<5).map { _ in item(.invitation) }, outgoing = item(.sent)
        let battles = (0..<7).map { _ in item() }, challenges = (0..<7).map { _ in challenge() }
        let m = CutCompeteLogic.model(pending: incoming + [outgoing], battles: battles, challenges: challenges, available: challenges,
            completedBattles: battles, completedChallenges: challenges, loading: false, error: nil)
        #expect(m.invitations.count == 3); #expect(m.invitationCount == 5); #expect(m.showsAllInvitations)
        #expect(m.battles.count == 5); #expect(m.challenges.count == 5)
        #expect(m.recommended.count == 3); #expect(m.completed.count == 4); #expect(m.summary.count == 4)
        #expect(m.battlesPanel == .rows); #expect(m.challengesPanel == .rows)
    }
    @Test func outgoingInvitationsStayOffTheTab() {
        let m = CutCompeteLogic.model(pending: [item(.sent)], battles: [], challenges: [], available: [], completedBattles: [], completedChallenges: [], loading: false, error: nil)
        #expect(m.invitations.isEmpty); #expect(!m.showsAllInvitations)
    }
    @Test func emptyLoadingAndErrorPanels() {
        func model(loading: Bool, error: String?) -> CutCompeteModel {
            CutCompeteLogic.model(pending: [], battles: [], challenges: [], available: [], completedBattles: [], completedChallenges: [], loading: loading, error: error)
        }
        #expect(model(loading: true, error: nil).battlesPanel == .loading)
        #expect(model(loading: false, error: "Fixture failure").challengesPanel == .hidden)
        #expect(model(loading: false, error: nil).battlesPanel == .empty(title: "No active battles", line: "Challenge a friend to start one."))
        #expect(model(loading: false, error: nil).challengesPanel == .empty(title: "No active challenges", line: "Browse all to find one to join."))
        let m = model(loading: true, error: "Fixture failure")
        #expect(m.loading); #expect(m.error == "Fixture failure"); #expect(m.summary.isEmpty)
    }
    @Test func recommendedChallengesKeepTheChallengesPanelFilled() {
        let m = CutCompeteLogic.model(pending: [], battles: [], challenges: [], available: [challenge(.available)], completedBattles: [], completedChallenges: [], loading: false, error: nil)
        #expect(m.challengesPanel == .rows); #expect(m.battlesPanel != .rows)
    }
    @Test func singleSummaryHidden() {
        let m = CutCompeteLogic.model(pending: [], battles: [item()], challenges: [], available: [], completedBattles: [], completedChallenges: [], loading: false, error: nil)
        #expect(m.summary.isEmpty)
    }
    @Test func failedRefreshRetainsLoadedDataButEmptySuccessClears() {
        let retained: [Int] = CutCompeteLogic.refreshed([1], candidate: [], failed: true)
        #expect(retained == [1])
        let cleared: [Int] = CutCompeteLogic.refreshed([1], candidate: [], failed: false)
        #expect(cleared.isEmpty)
    }
    func row(_ facts: CutBattleFacts) -> CutCompeteItem {
        CutCompeteLogic.battle(facts, unit: .kg, locale: Self.en, now: CutBattleDetailLogicTests.now, calendar: Self.calendar)
    }
    @Test func activeBattleRowLeadsInLime() {
        var f = CutBattleDetailLogicTests.facts; f.ownScore = 12400; f.otherScore = 9800; f.end = CutBattleDetailLogicTests.now.addingTimeInterval(5 * 86400)
        let r = row(f)
        #expect(r.kind == .battle); #expect(r.line == "You lead, 5 days left"); #expect(r.lineIsLime)
        #expect(r.score == "12.4k"); #expect(r.scoreRest == ": 9.8k kg"); #expect(r.initials == "FO")
        #expect(r.spokenValue == "You 12.4k, Fixture Opponent 9.8k kg")
        f.ownScore = 100; #expect(row(f).line == "Fixture Opponent leads, 5 days left"); #expect(!row(f).lineIsLime)
        f.ownScore = f.otherScore; #expect(row(f).line == "Tied, 5 days left")
    }
    @Test func invitationRowsNameWhatAndHowLong() {
        var f = CutBattleDetailLogicTests.facts; f.status = .pending; f.isChallenger = false; f.isOpponent = true; f.type = .workoutCount
        let r = row(f)
        #expect(r.id == .battle(f.id)); #expect(r.incoming); #expect(r.kind == .invitation)
        #expect(r.line == "Invited you, 7 days of workouts"); #expect(r.score == nil)
        f.isChallenger = true; f.isOpponent = false
        #expect(row(f).kind == .sent); #expect(row(f).line == "Invite sent, 7 days of workouts")
    }
    @Test func finishedBattleRows() {
        var f = CutBattleDetailLogicTests.facts; f.status = .completed
        #expect(row(f).line == "You won"); #expect(row(f).lineIsLime); #expect(row(f).score == "2.0k")
        f.ownScore = 500; #expect(row(f).line == "You lost"); #expect(!row(f).lineIsLime)
        f.status = .declined; #expect(row(f).line == "Invitation declined"); #expect(row(f).score == nil)
        f.status = .active; f.end = CutBattleDetailLogicTests.now; f.ownScore = 3000
        #expect(row(f).line == "Ended, you lead")
    }
    @Test func joinedChallengeRowShowsProgressBarAndOneLine() {
        let r = CutCompeteLogic.challenge(CutChallengeDetailLogicTests.facts, unit: .kg, locale: Self.en, now: CutChallengeDetailLogicTests.now, calendar: Self.calendar)
        #expect(r.kind == .challenge); #expect(r.score == "6"); #expect(r.scoreRest == "/ 10"); #expect(r.fraction == 0.6)
        #expect(r.line == "Workouts, 14 days left"); #expect(r.spokenValue == "6 of 10 workouts, 60 percent")
    }
    @Test func availableAndCompletedChallengeRows() {
        var facts = CutChallengeDetailLogicTests.facts
        facts.current = nil; facts.type = .custom; facts.metric = "conditioning_minutes"; facts.goal = 120
        let available = CutCompeteLogic.challenge(facts, unit: .kg, locale: Self.en, now: CutChallengeDetailLogicTests.now, calendar: Self.calendar)
        #expect(available.kind == .available); #expect(available.line == "120 min, beginner"); #expect(available.score == nil); #expect(available.fraction == nil)
        facts.difficulty = nil
        #expect(CutCompeteLogic.challenge(facts, unit: .kg, locale: Self.en, now: CutChallengeDetailLogicTests.now, calendar: Self.calendar).line == "120 min, 14 days left")
        var done = CutChallengeDetailLogicTests.facts; done.completed = true; done.current = 10; done.percentage = 100
        let completed = CutCompeteLogic.challenge(done, unit: .kg, locale: Self.en, now: CutChallengeDetailLogicTests.now, calendar: Self.calendar)
        #expect(completed.kind == .completedChallenge); #expect(completed.line == "Workouts, completed"); #expect(completed.score == "10"); #expect(completed.fraction == nil)
    }
    @Test func challengeRowsFormatProgressInTheRequestedUnitAndLocale() {
        var facts = CutChallengeDetailLogicTests.facts
        facts.type = .totalVolume; facts.goal = 10000; facts.current = 1500
        let row = CutCompeteLogic.challenge(facts, unit: .lb, locale: Locale(identifier: "de_DE"), now: CutChallengeDetailLogicTests.now)
        #expect(row.score == "3,3k"); #expect(row.scoreRest == "/ 22,0k"); #expect(row.line.hasPrefix("Volume, "))
    }
    @Test func listAndDetailScoreFormattingStayConsistent() {
        for type in [BattleType.volume, .workoutCount, .consistency, .pr, .exercise, .runningDistance] {
            var facts = CutBattleDetailLogicTests.facts; facts.type = type
            for unit in [WeightUnit.kg, .lb] {
                let locale = Locale(identifier: "de_DE")
                let detail = CutBattleDetailLogic.model(facts, unit: unit, locale: locale, now: CutBattleDetailLogicTests.now)
                let row = CutCompeteLogic.battle(facts, unit: unit, locale: locale, now: CutBattleDetailLogicTests.now)
                let measured = [BattleType.volume, .pr, .runningDistance].contains(type)
                #expect(row.score == detail.own.score); #expect(row.scoreRest == ": " + detail.other.score + (measured ? " " + detail.unit : ""))
                #expect(row.spokenValue.hasSuffix(detail.unit))
            }
        }
    }
    @Test func sheetFitsItsContentUntilItWouldPassTheStatusBar() {
        #expect(CutSheetSizing.resolve(parts: [80, 400.2, 34], screen: 844) == .fitted(515))
        #expect(CutSheetSizing.resolve(parts: [80, 700, 34], screen: 844) == .large)
        #expect(CutSheetSizing.resolve(parts: [0, 0, 0, 0], screen: 844) == .large)
        #expect(CutSheetSizing.resolve(parts: [80, 600, -5], screen: 844) == .fitted(680))
        #expect(CutSheetSizing.fitted(500).detent == .height(500)); #expect(CutSheetSizing.large.detent == .large)
    }
}
