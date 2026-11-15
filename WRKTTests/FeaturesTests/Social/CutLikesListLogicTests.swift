import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutLikesListLogicTests {
    private var people: [CutSocialPersonFacts] { CutSocialPeopleFixtures.searchResults }

    @Test func loadingEmptyAndFailureAreDistinct() {
        #expect(CutLikesListLogic.model(people: nil, error: nil).content == .loading)
        #expect(CutLikesListLogic.model(people: [], error: nil).content == .empty)
        #expect(CutLikesListLogic.model(people: nil, error: "Offline").content == .failed("Offline"))
        #expect(CutLikesListLogic.model(people: [], error: "Offline").content == .failed("Offline"))
    }

    @Test func serverOrderAndNameFallbackArePreserved() {
        let facts = people
        guard case let .people(rows) = CutLikesListLogic.model(people: facts, error: nil).content else {
            Issue.record("Expected people"); return
        }
        #expect(rows.map(\.id) == facts.map(\.id))
        #expect(rows.map(\.name) == ["Nina R.", "Nino T.", "@anina"])
        #expect(rows.map(\.handle) == ["@nina", "@ninot", nil])
    }

    @Test func loadedPeopleStayVisibleOnFailure() async {
        let state = CutLikesListState()
        let facts = people
        await state.load { facts }
        await state.load { throw URLError(.notConnectedToInternet) }
        #expect(state.people == facts)
        #expect(state.error != nil)
        #expect(CutLikesListLogic.model(people: state.people, error: state.error).inlineError == state.error)
    }

    @Test func cancellationNeverClearsLoadedPeopleOrSetsError() async {
        let state = CutLikesListState()
        let facts = people
        await state.load { facts }
        await state.load { throw CancellationError() }
        #expect(state.people == facts)
        #expect(state.error == nil)
        await state.load { throw URLError(.cancelled) }
        #expect(state.people == facts)
        #expect(state.error == nil)
    }

    @Test func successfulEmptyResultReplacesEarlierLikes() async {
        let state = CutLikesListState()
        await state.load { people }
        await state.load { [] }
        #expect(state.people == [])
        #expect(CutLikesListLogic.model(people: state.people, error: state.error).content == .empty)
    }
}
