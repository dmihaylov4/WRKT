import Foundation
import Testing
@testable import WRKT

@Suite("Age setting")
@MainActor
struct AgeSettingTests {
    private struct SaveFailed: Error {}

    // MARK: Draft: one commit when the sheet closes

    @Test func wheelTurnsCommitNothingUntilTheSheetCloses() {
        var draft = AgeDraft(saved: 34)
        for age in [35, 36, 37, 38] { draft.age = age }
        // Only the closing value is committed, once.
        #expect(draft.ageToCommit(confirmed: true) == 38)
        #expect(draft.ageToCommit(confirmed: false) == 38)
    }

    @Test func closingWithoutAChangeCommitsNothing() {
        let draft = AgeDraft(saved: 34)
        #expect(draft.age == 34)
        #expect(draft.ageToCommit(confirmed: true) == nil)
        #expect(draft.ageToCommit(confirmed: false) == nil)
        var turnedBack = AgeDraft(saved: 34)
        turnedBack.age = 40
        turnedBack.age = 34
        #expect(turnedBack.ageToCommit(confirmed: true) == nil)
    }

    @Test func doneOnTheSuggestedAgeSetsIt() {
        let draft = AgeDraft(saved: nil)
        #expect(draft.age == AgeDraft.suggestedAge)
        #expect(draft.ageToCommit(confirmed: true) == 30)
        // Swiping away an untouched wheel does not invent an age.
        #expect(draft.ageToCommit(confirmed: false) == nil)
    }

    @Test func aSavedAgeStaysEditable() {
        var draft = AgeDraft(saved: 52)
        draft.age = 51
        #expect(draft.ageToCommit(confirmed: true) == 51)
        // The Preferences row is a link for a saved age too.
        let model = CutPreferencesLogic.model(CutPreferencesFacts(age: 52))
        #expect(model.age == "52 years")
    }

    @Test func wheelStartsInsideItsRange() {
        #expect(AgeDraft(saved: 7).age == 10)
        #expect(AgeDraft(saved: 104).age == 100)
        #expect(AgeDraft.range == 10...100)
    }

    @Test func rowLine() {
        #expect(AgeSetting.line(nil) == "Not set")
        #expect(AgeSetting.line(34) == "34 years")
        #expect(AgeSetting.birthYear(age: 36, currentYear: 2026) == 1990)
    }

    // MARK: Commit: local always, profile when signed in

    @Test func signedOutKeepsTheAgeLocally() async throws {
        var local: [Int] = []
        try await AgeSetting.commit(41, currentYear: 2026, setLocal: { local.append($0) }, saveBirthYear: nil)
        #expect(local == [41])
    }

    @Test func signedInSavesTheBirthYearOnce() async throws {
        var local: [Int] = []
        var saved: [Int] = []
        try await AgeSetting.commit(41, currentYear: 2026, setLocal: { local.append($0) },
                                    saveBirthYear: { saved.append($0) })
        #expect(local == [41])
        #expect(saved == [1985])
    }

    @Test func aFailedProfileSaveKeepsTheLocalAge() async {
        var local: [Int] = []
        await #expect(throws: SaveFailed.self) {
            try await AgeSetting.commit(41, currentYear: 2026, setLocal: { local.append($0) },
                                        saveBirthYear: { _ in throw SaveFailed() })
        }
        #expect(local == [41])
    }
}
