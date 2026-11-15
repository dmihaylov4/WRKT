import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutChallengesBrowseLogicTests {
    let row = CutCompeteItem(id: .challenge(UUID()), title: "Fixture Challenge", subtitle: "Beginner")
    let preset = CutChallengesBrowseModel.Preset(title: "Fixture Preset", description: "Fixture rule", duration: "7 days", difficulty: "Beginner")
    @Test func eachFilterUsesItsOwnRows() {
        for tab in CutChallengesBrowseModel.Tab.allCases {
            let m = CutChallengesBrowseLogic.model(tab: tab, active: tab == .active ? [row] : [], available: tab == .browse ? [row] : [], completed: tab == .completed ? [row] : [], presets: [], loading: false, error: nil)
            #expect(m.rows == [row]); #expect(m.empty == nil)
        }
    }
    @Test func emptyActiveAndCompletedRecommendThree() {
        for tab in [CutChallengesBrowseModel.Tab.active, .completed] {
            let m = CutChallengesBrowseLogic.model(tab: tab, active: [], available: [], completed: [], presets: Array(repeating: preset, count: 5), loading: false, error: nil)
            #expect(m.presets.count == 3); #expect(m.showsAll); #expect(m.empty != nil)
        }
    }
    @Test func browseHasAllFeaturedAndCommunity() {
        let m = CutChallengesBrowseLogic.model(tab: .browse, active: [], available: [row], completed: [], presets: Array(repeating: preset, count: 5), loading: false, error: nil)
        #expect(m.presets.count == 5); #expect(m.rows == [row]); #expect(!m.showsAll); #expect(m.empty == nil)
    }
    @Test func loadedActiveDoesNotRepeatRecommendations() {
        let m = CutChallengesBrowseLogic.model(tab: .active, active: [row], available: [], completed: [], presets: [preset], loading: false, error: nil)
        #expect(m.presets.isEmpty)
    }
    @Test func browseEmptyIsNotShownWhenFeaturedExists() {
        let m = CutChallengesBrowseLogic.model(tab: .browse, active: [], available: [], completed: [], presets: [preset], loading: false, error: nil)
        #expect(m.empty == nil)
    }
    @Test func loadingErrorAndEmptyAreDistinct() {
        func model(loading: Bool = false, error: String? = nil) -> CutChallengesBrowseModel {
            CutChallengesBrowseLogic.model(tab: .browse, active: [], available: [], completed: [], presets: [], loading: loading, error: error)
        }
        #expect(model().empty == "No challenges available")
        #expect(model(loading: true).empty == nil); #expect(model(error: "Fixture error").empty == nil)
        #expect(model(error: "Fixture error").error == "Fixture error")
    }
}
