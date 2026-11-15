import Foundation
import Testing
@testable import WRKT

enum CutDexFixtures {
    static let unlockedAt = Date(timeIntervalSince1970: 1_794_571_200)

    static var items: [DexItem] {
        let names = ["Barbell Bench Press", "Back Squat", "Deadlift", "Dumbbell Row", "Overhead Press",
                     "Pull-Up", "Romanian Deadlift", "Incline Dumbbell Press"]
        return names.enumerated().map { index, name in
            DexItem(id: "ex\(index)", name: name, short: DexText.shortName(name), ruleId: "ach.pr.ex\(index)",
                    progress: index < 3 ? 1 : 0, target: 1, unlockedAt: index < 3 ? unlockedAt : nil)
        }
    }

    static var detail: CutDexDetailFacts {
        CutDexDetailFacts(
            name: "Barbell Bench Press", unlockedAt: unlockedAt, bestE1RMKg: 112.5, lastWorking: (5, 100),
            ladder: (1...12).map { ($0, $0 <= 5 ? 110 - Double($0) * 2.5 : ($0 == 8 ? 85 : nil)) },
            attempt: (5, 102.5), hasExercise: true, unit: .kg)
    }
}

@Suite("Cut PR Dex logic")
struct CutAchievementsDexLogicTests {
    private typealias F = CutDexFixtures

    @Test func countScopeAndRecords() {
        let model = CutAchievementsDexLogic.model(items: F.items, unlocked: 3, total: 8, isSearching: false)
        #expect(model.title == "PR Dex")
        #expect(model.countLine == "3 of 8 unlocked")
        #expect(model.scopeOptions.map(\.label) == ["All", "Unlocked", "Locked"])
        #expect(model.records.map(\.title) == ["Longest run", "Longest streak"])
        #expect(model.tiles.count == 8)
    }

    @Test func tilesKeepTheShortNameAndTheUnlockState() {
        let tiles = CutAchievementsDexLogic.model(items: F.items, unlocked: 3, total: 8, isSearching: false).tiles
        #expect(tiles[0].title == "BB Bench Press")
        #expect(tiles[0].isUnlocked)
        #expect(tiles[0].status == "Nov 13, 2026")
        #expect(tiles[0].accessibilityLabel == "Barbell Bench Press, unlocked on Nov 13, 2026")
        #expect(!tiles[4].isUnlocked)
        #expect(tiles[4].status == "Locked")
        #expect(tiles[4].accessibilityLabel == "Overhead Press, locked")
    }

    @Test func rowsOfThreeLeaveAShortLastRow() {
        let rows = CutAchievementsDexLogic.rows(Array(1...8), columns: 3)
        #expect(rows == [[1, 2, 3], [4, 5, 6], [7, 8]])
        #expect(CutAchievementsDexLogic.rows([Int](), columns: 3).isEmpty)
        #expect(CutAchievementsDexLogic.rows(Array(1...2), columns: 0) == [[1], [2]])
    }

    @Test func detailRecordsLadderAndAttempt() {
        let model = CutDexDetailLogic.model(F.detail, locale: Locale(identifier: "en_US"))
        #expect(model.title == "Barbell Bench Press")
        #expect(model.unlockLine == "Unlocked Nov 13, 2026")
        #expect(model.records.map(\.title) == ["Best est. 1RM", "Last working"])
        #expect(model.records[0].value == WeightUnit.kg.format(112.5))
        #expect(model.ladder.count == 12)
        #expect(model.ladder[0].label == "1 reps")
        #expect(model.ladder[11].value == "-")
        #expect(model.attempt == WeightUnit.kg.formatSet(reps: 5, weightKg: 102.5))
        #expect(model.showsExerciseActions)
    }

    @Test func lockedDetailWithoutHistory() {
        var facts = F.detail
        facts.unlockedAt = nil
        facts.bestE1RMKg = nil
        facts.attempt = nil
        let model = CutDexDetailLogic.model(facts)
        #expect(model.unlockLine == "Log a working set to unlock")
        #expect(model.records.isEmpty)
        #expect(model.attempt == nil)
        facts.hasExercise = false
        facts.attempt = (5, 100)
        let missing = CutDexDetailLogic.model(facts)
        #expect(missing.attempt == nil)
        #expect(!missing.showsExerciseActions)
    }

    @Test func poundsLadder() {
        var facts = F.detail
        facts.unit = .lb
        #expect(CutDexDetailLogic.model(facts).records[0].value == WeightUnit.lb.format(112.5))
    }
}
