import Foundation
import CoreGraphics
import Testing
@testable import WRKT

@MainActor
struct CutExerciseBrowserTests {
    @Test func scopedAndSelectedMuscleMembershipIntersectWithRegion() {
        let rows = CutExerciseFixtures.exercises
        let filters = CutExerciseBrowserFilters(muscle: "Chest")
        let result = CutExerciseBrowserLogic.filtered(rows, filters: filters, muscleFilter: .upperBody,
            scopedIDs: ["bench", "curl", "squat"], selectedMuscleIDs: ["bench", "squat"], favorites: [])
        #expect(result.map(\.id) == ["bench"])
        #expect(CutExerciseBrowserLogic.filtered(rows, filters: filters, muscleFilter: .fullBody, scopedIDs: [], favorites: []).isEmpty)
    }

    @Test func equipmentAndMovementFiltersCombineUsingCanonicalBuckets() {
        let filters = CutExerciseBrowserFilters(equipment: .barbell, movement: .push)
        let result = CutExerciseBrowserLogic.filtered(CutExerciseFixtures.exercises, filters: filters, muscleFilter: nil, favorites: [])
        #expect(result.map(\.id) == ["bench"])
        var cable = CutExerciseFixtures.exercise("cable", "Cable pull-through", muscle: "Glutes", equipment: "Cable", force: "pull")
        cable.secondaryEquipment = "Dumbbell"
        #expect(CutExerciseBrowserLogic.filtered([cable], filters: .init(equipment: .dumbbell, movement: .hinge), muscleFilter: nil, favorites: []).count == 1)
    }

    @Test func searchUsesSmartMatchingAndBypassesExtraFiltersButNotMuscleScope() {
        let filters = CutExerciseBrowserFilters(equipment: .kettlebell, movement: .core, isSearching: true, query: "bench")
        #expect(CutExerciseBrowserLogic.filtered(CutExerciseFixtures.exercises, filters: filters, muscleFilter: .upperBody, favorites: []).map(\.id) == ["bench"])
        #expect(CutExerciseBrowserLogic.filtered(CutExerciseFixtures.exercises, filters: filters, muscleFilter: .lowerBody, favorites: []).isEmpty)
    }

    @Test func favoritesThenCustomThenAlphabeticalAndStableNamesMatchLegacy() {
        let a = CutExerciseFixtures.exercise("a", "Alpha", muscle: "Chest")
        let b = CutExerciseFixtures.exercise("b", "Alpha", muscle: "Chest")
        var custom = CutExerciseFixtures.exercise("custom", "Zulu", muscle: "Chest")
        custom.isCustom = true
        let fav = CutExerciseFixtures.exercise("fav", "Zed", muscle: "Chest")
        let rows = CutExerciseBrowserLogic.filtered([a, b, custom, fav], filters: .init(), muscleFilter: nil, favorites: ["fav"])
        #expect(rows.map(\.id) == ["fav", "custom", "a", "b"])
    }

    @Test func distinctEmptyAndNoResultsStates() {
        let empty = CutExerciseBrowserLogic.model(exercises: [], subregion: nil, muscleFilter: nil, filters: .init(), favorites: [])
        #expect(empty.emptyState == .library)
        let filters = CutExerciseBrowserFilters(isSearching: true, query: "unfindable")
        let noResults = CutExerciseBrowserLogic.model(exercises: CutExerciseFixtures.exercises, subregion: "Chest", muscleFilter: nil,
            filters: filters, favorites: [])
        #expect(noResults.emptyState == .search)
        #expect(noResults.emptyMessage.contains("Chest"))
        let filtered = CutExerciseBrowserLogic.model(exercises: CutExerciseFixtures.exercises, subregion: nil, muscleFilter: nil,
            filters: .init(equipment: .kettlebell), favorites: [])
        #expect(filtered.emptyState == .filtered)
    }

    @Test func relatedSuggestionsOnlyForScopedEmptySearchAndKeepLimits() {
        let many = (0..<8).map { CutExerciseFixtures.exercise("curl\($0)", "Curl \($0)", muscle: "Biceps") }
        let related = CutExerciseBrowserLogic.suggestions(exercises: many, query: "curl", excluding: "Chest", favorites: [])
        #expect(related.first?.muscle == "Biceps")
        #expect(related.first?.totalCount == 8)
        #expect(related.first?.rows.count == 5)
        #expect(CutExerciseBrowserLogic.suggestions(exercises: many, query: "curl", excluding: nil, favorites: []).isEmpty)
        #expect(CutExerciseBrowserLogic.suggestions(exercises: many, query: "curl", excluding: "Biceps", favorites: []).isEmpty)
    }

    @Test func titlesMusclesAndPlainTypeText() {
        #expect(CutExerciseBrowserLogic.title(subregion: "Upper Chest", muscleFilter: .lowerBody) == "Upper Chest")
        #expect(CutExerciseBrowserLogic.title(subregion: nil, muscleFilter: .upperBody) == "Upper Body Exercises")
        #expect(CutExerciseBrowserLogic.muscles(for: .fullBody)
            == MuscleTaxonomy.subregions(for: .upper) + MuscleTaxonomy.subregions(for: .lower))
        #expect(!CutExerciseBrowserLogic.muscles(for: .lowerBody).isEmpty)
        let row = CutExerciseBrowserLogic.row(CutExerciseFixtures.exercises[0], favorites: ["bench"])
        #expect(row.detail == "Compound")
        #expect(row.isFavorite)
    }

    @Test func tutorialWaitsForAllRealFramesAndKeepsToolbarWorkaround() {
        var frames = CutExerciseTutorialFrames()
        #expect(!frames.isReady)
        let rect = CGRect(x: 24, y: 100, width: 320, height: 50)
        for target in [CutExerciseTutorialFrames.Target.filters, .list] { frames.set(rect, for: target) }
        #expect(!frames.isReady)
        frames.set(rect, for: .create)
        #expect(frames.isReady)
        #expect(CutExerciseTutorialLogic.step(0, frames: frames).frame == rect)
        #expect(CutExerciseTutorialLogic.step(2, frames: frames).frame == nil)
        #expect(CutExerciseTutorialLogic.step(2, frames: frames).isLast)
    }

    @Test func tutorialStepsPointAtTargetsInTheNewLayout() {
        var frames = CutExerciseTutorialFrames()
        frames.set(CGRect(x: 16, y: 100, width: 358, height: 44), for: .filters)
        frames.set(CGRect(x: 0, y: 200, width: 390, height: 600), for: .list)
        frames.set(CGRect(x: 340, y: 50, width: 44, height: 44), for: .create)
        let steps = (0..<CutExerciseTutorialLogic.stepCount).map { CutExerciseTutorialLogic.step($0, frames: frames) }
        #expect(steps.map(\.index) == [0, 1, 2])
        #expect(steps.map(\.target) == [.filters, .list, nil])
        #expect(steps.allSatisfy { $0.count == CutExerciseTutorialLogic.stepCount })
        for step in steps {
            if let target = step.target {
                #expect(CutExerciseTutorialFrames.Target.allCases.contains(target))
                #expect(step.frame == frames.frame(for: target))
            } else {
                #expect(step.frame == nil)
            }
        }
        // No step talks about the removed chips or More Filters toggle.
        #expect(steps.allSatisfy { !$0.message.contains("chip") && !$0.message.contains("More Filters") })
        #expect(steps[0].message.contains("Clear filters"))
    }

    // MARK: Filter pills

    private func model(subregion: String? = nil, region: MuscleFilter? = nil,
                       filters: CutExerciseBrowserFilters = .init()) -> CutExerciseBrowserModel {
        let exercises = CutExerciseFixtures.exercises
        return CutExerciseBrowserLogic.model(exercises: exercises, subregion: subregion, muscleFilter: region, filters: filters,
            scopedIDs: subregion.map { muscle in Set(exercises.filter { $0.primaryMuscles.contains(muscle) }.map(\.id)) },
            selectedMuscleIDs: filters.muscle.map { muscle in Set(exercises.filter { $0.primaryMuscles.contains(muscle) }.map(\.id)) },
            favorites: [])
    }

    @Test func pillsReadTheGroupNameUntilAChoiceIsMade() {
        let empty = model(region: .upperBody)
        #expect(empty.menus.map(\.kind) == [.muscle, .equipment, .movement])
        #expect(empty.menus.map(\.label) == ["Muscle", "Equipment", "Movement"])
        #expect(empty.menus.allSatisfy { !$0.isActive && $0.selection == nil })
        #expect(empty.menus.map(\.anyTitle) == ["Any muscle", "Any equipment", "Any movement"])

        let chosen = model(region: .upperBody, filters: .init(muscle: "Chest", movement: .push))
        #expect(chosen.menus.map(\.label) == ["Chest", "Equipment", "Push"])
        #expect(chosen.menus.map(\.isActive) == [true, false, true])
        #expect(chosen.menus.map(\.groupName) == ["Muscle", "Equipment", "Movement"])
    }

    @Test func menuOptionsPerList() {
        let upper = MuscleTaxonomy.subregions(for: .upper)
        let lower = MuscleTaxonomy.subregions(for: .lower)
        let equipment = ["Barbell", "Bodyweight", "Cable", "Dumbbell", "EZ Bar", "Kettlebell", "Pullup Bar", "Other"]
        let movement = ["Push", "Pull", "Hinge", "Squat", "Core", "Other"]

        let all = model(region: .fullBody).menus
        #expect(all.map(\.kind) == [.muscle, .equipment, .movement])
        #expect(all[0].options == upper + lower)
        #expect(model(region: nil).menus[0].options == upper + lower)
        #expect(all[1].options == equipment)
        #expect(all[2].options == movement)

        #expect(model(region: .upperBody).menus[0].options == upper)
        #expect(model(region: .lowerBody).menus[0].options == lower)

        let subregion = model(subregion: "Chest", region: .upperBody).menus
        #expect(subregion.map(\.kind) == [.equipment, .movement])
        #expect(subregion.map(\.options) == [equipment, movement])
        #expect(!subregion.contains { $0.options.contains("All") || $0.options.contains("Any") })
    }

    @Test func countIsTheNumberOfRowsAfterFiltering() {
        let all = model(region: .fullBody)
        #expect(all.countText == "3 exercises")
        #expect(all.showsCount)
        let barbell = model(region: .fullBody, filters: .init(equipment: .barbell))
        #expect(barbell.rows.count == 2)
        #expect(barbell.countText == "2 exercises")
        let one = model(region: .fullBody, filters: .init(muscle: "Chest"))
        #expect(one.countText == "1 exercise")
        let none = model(region: .fullBody, filters: .init(equipment: .kettlebell))
        #expect(none.countText == "0 exercises")
        #expect(none.emptyState == .filtered)
        #expect(none.showsCount)
        let library = CutExerciseBrowserLogic.model(exercises: [], subregion: nil, muscleFilter: nil, filters: .init(), favorites: [])
        #expect(!library.showsCount)
        let searching = model(filters: .init(isSearching: true))
        #expect(!searching.showsFilters)
        #expect(model().showsFilters)
    }

    @Test func clearFiltersShowsOnlyWithAChoiceAndResetsEveryGroup() {
        #expect(!model(region: .upperBody).showsClearFilters)
        #expect(model(region: .upperBody, filters: .init(muscle: "Back")).showsClearFilters)
        #expect(model(region: .upperBody, filters: .init(equipment: .cable)).showsClearFilters)
        #expect(model(region: .upperBody, filters: .init(movement: .pull)).showsClearFilters)

        let set = CutExerciseBrowserFilters(muscle: "Back", equipment: .cable, movement: .pull)
        let cleared = CutExerciseBrowserLogic.cleared(set)
        #expect(cleared == CutExerciseBrowserFilters())
        #expect(!model(region: .upperBody, filters: cleared).showsClearFilters)

        let searching = CutExerciseBrowserFilters(equipment: .cable, isSearching: true, query: "row")
        let clearedSearch = CutExerciseBrowserLogic.cleared(searching)
        #expect(clearedSearch.isSearching)
        #expect(clearedSearch.query.isEmpty)
        #expect(clearedSearch.equipment == .all)
    }

    @Test func changingOneFilterLeavesTheOthers() {
        let start = CutExerciseBrowserFilters(muscle: "Chest", equipment: .barbell, movement: .push)
        let muscle = CutExerciseBrowserLogic.selecting("Back", for: .muscle, in: start)
        #expect(muscle == .init(muscle: "Back", equipment: .barbell, movement: .push))
        let equipment = CutExerciseBrowserLogic.selecting("EZ Bar", for: .equipment, in: start)
        #expect(equipment == .init(muscle: "Chest", equipment: .ezBar, movement: .push))
        let movement = CutExerciseBrowserLogic.selecting(nil, for: .movement, in: start)
        #expect(movement == .init(muscle: "Chest", equipment: .barbell, movement: .all))
        #expect(CutExerciseBrowserLogic.selecting(nil, for: .muscle, in: start).muscle == nil)
        #expect(CutExerciseBrowserLogic.selecting(nil, for: .equipment, in: start).equipment == .all)
        // Every listed option maps back onto the filter it labels.
        for menu in model(region: .fullBody).menus {
            for option in menu.options {
                let next = CutExerciseBrowserLogic.selecting(option, for: menu.kind, in: .init())
                let reread = model(region: .fullBody, filters: next).menus.first { $0.kind == menu.kind }
                #expect(reread?.selection == option)
            }
        }
    }

}

enum CutExerciseFixtures {
    static var exercises: [Exercise] {
        [exercise("bench", "Barbell Bench Press", muscle: "Chest", equipment: "Barbell", force: "push"),
         exercise("curl", "Dumbbell Curl", muscle: "Biceps", equipment: "Dumbbell", force: "pull", mechanic: "isolation"),
         exercise("squat", "Squat", muscle: "Quads", equipment: "Barbell")]
    }

    static func exercise(_ id: String, _ name: String, muscle: String, equipment: String? = nil,
                         force: String? = nil, mechanic: String = "compound") -> Exercise {
        Exercise(id: id, name: name, force: force, level: nil, mechanic: mechanic, equipment: equipment,
                 secondaryEquipment: nil, grip: nil, primaryMuscles: [muscle], secondaryMuscles: [],
                 tertiaryMuscles: [], instructions: [], images: nil, category: muscle.lowercased())
    }
}
