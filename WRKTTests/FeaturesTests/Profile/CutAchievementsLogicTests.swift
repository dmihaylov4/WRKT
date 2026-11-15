import Foundation
import Testing
@testable import WRKT

enum CutAchievementsFixtures {
    static let date = Date(timeIntervalSince1970: 1_794_571_200)
    static let all: [CutAchievementFacts] = [
        .init(id: "a1", title: "First workout", desc: "Log your first workout", progress: 1, target: 1, unlockedAt: date),
        .init(id: "a2", title: "Ten workouts", desc: "Log 10 workouts", progress: 4, target: 10, unlockedAt: nil),
        .init(id: "a3", title: "Iron week", desc: "Train strength 4 days in a week", progress: 2, target: 4, unlockedAt: nil),
        .init(id: "a4", title: "First PR", desc: "Set a personal record", progress: 1, target: 1, unlockedAt: date)
    ]
}

@Suite("Cut milestones logic")
struct CutAchievementsLogicTests {
    private typealias F = CutAchievementsFixtures
    private let locale = Locale(identifier: "en_US")

    @Test func sectionsAndCount() {
        let model = CutAchievementsLogic.model(F.all, search: "", filter: .all, locale: locale)
        #expect(model.title == "Milestones")
        #expect(model.countLine == "2 of 4 unlocked")
        #expect(model.inProgress.map(\.id) == ["a2", "a3"])
        #expect(model.unlocked.map(\.id) == ["a1", "a4"])
        #expect(model.inProgress[0].value == "4/10")
        #expect(model.inProgress[0].fraction == 0.4)
        #expect(model.unlocked[0].value == "November 13, 2026")
        #expect(model.unlocked[0].fraction == nil)
        #expect(model.filterOptions.map(\.label) == ["All", "In progress", "Unlocked"])
    }

    @Test func filtersAndSearchAsTheLegacyList() {
        #expect(CutAchievementsLogic.model(F.all, search: "", filter: .inProgress, locale: locale).unlocked.isEmpty)
        #expect(CutAchievementsLogic.model(F.all, search: "", filter: .unlocked, locale: locale).inProgress.isEmpty)
        // Title or description, any case.
        let search = CutAchievementsLogic.model(F.all, search: "STRENGTH", filter: .all, locale: locale)
        #expect(search.inProgress.map(\.id) == ["a3"])
        #expect(search.unlocked.isEmpty)
        let none = CutAchievementsLogic.model(F.all, search: "zzz", filter: .all, locale: locale)
        #expect(none.isEmpty)
        #expect(none.emptyTitle == "No achievements")
        #expect(none.emptyMessage == "Log more workouts or adjust your filters.")
    }

    @Test func fractionsStayInRange() {
        #expect(CutAchievementsLogic.fraction(3, of: 0) == 0)
        #expect(CutAchievementsLogic.fraction(12, of: 10) == 1)
    }
}
