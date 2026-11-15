import Foundation
import Testing
@testable import WRKT

struct CutEditPostLogicTests {
    private func model(_ caption: String = "Original", visibility: PostVisibility = .friends,
                       original: String? = "Original", route: CutEditPostModel.RouteStatus = .unknown,
                       own: Bool = true, cardio: Bool = true, linked: Bool = true, images: Bool = false,
                       saving: Bool = false, backfilling: Bool = false) -> CutEditPostModel {
        CutEditPostLogic.model(draft: .init(caption: caption, visibility: visibility), originalCaption: original, originalVisibility: .friends,
                              isOwn: own, isCardio: cardio, healthKitLinked: linked, hasImages: images, route: route,
                              saving: saving, backfilling: backfilling)
    }
    @Test func unchangedPostCannotSaveAndCaptionOrVisibilityChangesCan() {
        #expect(!model().canSave)
        #expect(model("Edited").canSave)
        #expect(model(visibility: .publicPost).canSave)
        #expect(!model(" Edited ", original: "Edited").canSave)
    }
    @Test func clearedCaptionIsAChangeAndSendsNilToTheExistingNullEncoder() {
        #expect(model(" \n").canSave)
        #expect(CutEditPostLogic.savedCaption(" \n") == nil)
        #expect(!model("", original: nil).canSave)
    }
    @Test func nonemptyCaptionIsTrimmedWithoutChangingInteriorWhitespace() {
        #expect(CutEditPostLogic.savedCaption(" \nFixture  caption\nNext line ") == "Fixture  caption\nNext line")
    }
    @Test func originalWhitespaceComparisonKeepsTheLegacySemantics() {
        #expect(model("Original ", original: "Original ").canSave)
    }
    @Test func routeControlsRequireOwnCardioLinkedToHealthKit() {
        #expect(model().showsRoute)
        #expect(!model(own: false).showsRoute)
        #expect(!model(cardio: false).showsRoute)
        #expect(!model(linked: false).showsRoute)
    }
    @Test func everyRouteStatusKeepsItsMessageAndRebuildRule() {
        #expect(model().routeLine == "No map yet")
        #expect(model(images: true).routeLine == "Map attached")
        #expect(model(route: .hasMap).routeLine == "Map attached")
        #expect(model(route: .noMap).routeLine == "No route data in HealthKit yet")
        #expect(model(route: .building, backfilling: true).routeLine == "Building...")
        #expect(model(route: .building, backfilling: true).isBackfilling)
        #expect(model(route: .failed).routeLine == "Could not build route: try again later")
        #expect(model(route: .failed).showsRebuild)
        #expect(!model(route: .success).showsRebuild)
        #expect(model(route: .success).routeLine == "Route map added")
    }
    @Test func successfulRouteBackfillEnablesSaveWithoutTextEdits() {
        #expect(model(route: .success).canSave)
        #expect(!model(route: .failed).canSave)
    }
    @Test func savingDisablesSaveButBackfillAloneDoesNotChangeTheRule() {
        #expect(!model("Edited", saving: true).canSave)
        #expect(model("Edited", route: .building, backfilling: true).canSave)
        #expect(model("Edited", saving: true).isSaving)
    }
}
