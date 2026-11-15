import Foundation
import Testing
@testable import WRKT

@MainActor
struct CutExerciseFilteredBrowserTests {
    @Test func regionListsUseExistingTaxonomyAndOrder() {
        let upper = MuscleTaxonomy.subregions(for: .upper)
        let lower = MuscleTaxonomy.subregions(for: .lower)
        #expect(CutFilteredExerciseBrowserLogic.model(filter: .upperBody, title: "Upper").subregions == upper)
        #expect(CutFilteredExerciseBrowserLogic.model(filter: .lowerBody, title: "Lower").subregions == lower)
        #expect(CutFilteredExerciseBrowserLogic.model(filter: .fullBody, title: "Full").subregions == upper + lower)
        #expect(CutFilteredExerciseBrowserLogic.model(filter: nil, title: "Browse").subregions == upper + lower)
    }

    @Test func callerTitleIsPreserved() {
        #expect(CutFilteredExerciseBrowserLogic.model(filter: nil, title: "Choose a muscle").title == "Choose a muscle")
    }
}
