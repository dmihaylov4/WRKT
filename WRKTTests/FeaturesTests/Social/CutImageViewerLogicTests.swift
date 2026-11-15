import Testing
@testable import WRKT

struct CutImageViewerLogicTests {
    @Test func photosKeepTheCallersPageOrderAndIndices() {
        let model = CutImageViewerLogic.model(["fixture-first", "fixture-second", "fixture-third"])
        #expect(model.photos.map(\.id) == [0, 1, 2])
        #expect(model.photos.map(\.url) == ["fixture-first", "fixture-second", "fixture-third"])
    }
    @Test func duplicateURLsRemainSeparatePages() {
        let model = CutImageViewerLogic.model(["fixture", "fixture"])
        #expect(model.photos.count == 2)
        #expect(model.photos[0].id != model.photos[1].id)
    }
    @Test func unresolvedURLsAreNotDroppedOrReindexed() {
        let model = CutImageViewerLogic.model(["", "not a remote URL", "fixture"])
        #expect(model.photos.map(\.id) == [0, 1, 2])
        #expect(model.photos[0].url == "")
    }
    @Test func emptyViewerKeepsNoPages() {
        #expect(CutImageViewerLogic.model([]).photos.isEmpty)
    }
}
