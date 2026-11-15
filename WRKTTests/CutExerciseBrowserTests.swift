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
        #expect(CutExerciseBrowserLogic.muscles(for: .fullBody).isEmpty)
        #expect(!CutExerciseBrowserLogic.muscles(for: .lowerBody).isEmpty)
        let row = CutExerciseBrowserLogic.row(CutExerciseFixtures.exercises[0], favorites: ["bench"])
        #expect(row.detail == "Compound")
        #expect(row.isFavorite)
    }

    @Test func tutorialWaitsForAllRealFramesAndKeepsToolbarWorkaround() {
        var frames = CutExerciseTutorialFrames()
        #expect(!frames.isReady)
        let rect = CGRect(x: 24, y: 100, width: 320, height: 50)
        for target in [CutExerciseTutorialFrames.Target.equipment, .movement, .list] { frames.set(rect, for: target) }
        #expect(!frames.isReady)
        frames.set(rect, for: .create)
        #expect(frames.isReady)
        #expect(CutExerciseTutorialLogic.step(0, frames: frames).frame == rect)
        #expect(CutExerciseTutorialLogic.step(3, frames: frames).frame == nil)
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
