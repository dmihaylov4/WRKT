import Testing
@testable import WRKT

struct BarbellEntityBuilderTests {

    @Test func plateTierCatalogHasExpectedIDs() {
        #expect(PlateTier.all.map(\.id) == Array(0...7))
    }

    @Test func starterTierIsLastAndMarkedStarterStyle() throws {
        let starter = try #require(PlateTier.all.last)
        #expect(starter.id == 7)
        #expect(starter.style == .starter)
        #expect(starter.name == "Starter")
    }

    @Test func plateAudioCategoryMapsExpectedTiers() {
        #expect(PlateAudioCategory.from(tierID: 0) == .iron)
        #expect(PlateAudioCategory.from(tierID: 1) == .iron)
        #expect(PlateAudioCategory.from(tierID: 2) == .rubber)
        #expect(PlateAudioCategory.from(tierID: 3) == .brass)
        #expect(PlateAudioCategory.from(tierID: 4) == .iron)
        #expect(PlateAudioCategory.from(tierID: 5) == .iron)
        #expect(PlateAudioCategory.from(tierID: 6) == .brass)
        #expect(PlateAudioCategory.from(tierID: 7) == .starter)
    }

    @Test func barSkinCatalogHasUniqueIDs() {
        let ids = BarSkin.all.map(\.id)
        #expect(Set(ids).count == BarSkin.all.count)
        #expect(ids == Array(0..<(BarSkin.all.count)))
    }

    @Test func barSkinCatalogIncludesChromeDefault() throws {
        let chrome = try #require(BarSkin.all.first)
        #expect(chrome.id == 0)
        #expect(chrome.name == "Chrome")
        #expect(chrome.earnedBy == "Default")
    }

    @Test func stickerCatalogHasNoneOptionFirst() throws {
        let none = try #require(StickerOption.all.first)
        #expect(none.id == 0)
        #expect(none.name == "None")
        #expect(none.emoji == nil)
    }

    @Test func stickerCatalogContainsLegendaryCrown() {
        let crown = StickerOption.all.first(where: { $0.name == "Crown" })
        #expect(crown?.rarity == .legendary)
        #expect(crown?.emoji == "👑")
    }
}
