import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutExercisePickerTests {
    @Test func regionUsesPrimaryMuscleAndLegacyKeywords() {
        let rows = CutExerciseFixtures.exercises
        #expect(CutExercisePickerLogic.filtered(rows, region: .upper, query: "", favorites: []).map(\.id) == ["bench", "curl"])
        #expect(CutExercisePickerLogic.filtered(rows, region: .lower, query: "", favorites: []).map(\.id) == ["squat"])
        #expect(CutExercisePickerLogic.filtered(rows, region: .all, query: "", favorites: []).count == 3)
    }
    @Test func pickerSearchIsNameSubstringNotBrowserFuzzySearch() {
        let rows = CutExerciseFixtures.exercises
        #expect(CutExercisePickerLogic.filtered(rows, region: .all, query: "BENCH", favorites: []).map(\.id) == ["bench"])
        #expect(CutExercisePickerLogic.filtered(rows, region: .lower, query: "bench", favorites: []).isEmpty)
        #expect(CutExercisePickerLogic.filtered(rows, region: .all, query: "chest", favorites: []).isEmpty)
    }
    @Test func favoritesLeadButCustomDoesNotOverrideAlphabeticalOrder() {
        var custom = CutExerciseFixtures.exercise("custom", "Zulu", muscle: "Chest")
        custom.isCustom = true
        #expect(CutExercisePickerLogic.filtered(CutExerciseFixtures.exercises + [custom], region: .all, query: "", favorites: ["squat"]).map(\.id) == ["squat", "bench", "curl", "custom"])
    }
    @Test func paginationAndSingleSelectionRejectStaleOrHiddenRows() {
        let rows = (0..<120).map { CutExerciseFixtures.exercise("\($0)", String(format: "Exercise %03d", $0), muscle: "Chest") }
        let model = CutExercisePickerLogic.model(exercises: rows, region: .all, query: "", favorites: [], displayedCount: 50)
        #expect(model.rows.count == 50)
        #expect(model.hasMore)
        #expect(CutExercisePickerLogic.nextPage(displayedCount: 100, totalCount: 120) == 120)
        #expect(CutExercisePickerLogic.selection("0", model: model, exercises: rows)?.id == "0")
        #expect(CutExercisePickerLogic.selection("80", model: model, exercises: rows) == nil)
        #expect(CutExercisePickerLogic.selection("0", model: model, exercises: []) == nil)
    }
    @Test func emptyLibraryDiffersFromSearchWithoutResults() {
        let empty = CutExercisePickerLogic.model(exercises: [], region: .all, query: "", favorites: [], displayedCount: 50)
        #expect(empty.isLibraryEmpty)
        #expect(!empty.hasMore)
        let missing = CutExercisePickerLogic.model(exercises: CutExerciseFixtures.exercises, region: .all, query: "xyz", favorites: [], displayedCount: 50)
        #expect(!missing.isLibraryEmpty)
        #expect(missing.rows.isEmpty)
    }
}
