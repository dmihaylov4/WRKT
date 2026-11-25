import Foundation
import Testing
@testable import WRKT

/// Fixture-only tests for the Cut rack's plain values. No SwiftData container, no services.
@Suite struct CutRackModelTests {
    private static let locale = Locale(identifier: "en_US")
    private static let day = Date(timeIntervalSince1970: 1_790_000_000)

    private static func plate(_ id: String, tier: String = "Lime Bumper", engraving: String = "", kg: Double = 20,
                              slot: Int? = nil, order: Int = 0, earned: Date = day) -> CutRackPlateFacts {
        CutRackPlateFacts(id: id, tierName: tier, engraving: engraving, weightKg: kg, isLoaded: slot != nil,
                          rackPosition: slot, displayOrder: order, earnedAt: earned)
    }

    private static func model(_ plates: [CutRackPlateFacts], occupied: Int? = nil, unit: WeightUnit = .kg,
                              notice: CutRackNotice? = nil) -> CutRackModel {
        CutRackLogic.model(CutRackFacts(plates: plates, occupiedSlots: occupied ?? plates.filter(\.isLoaded).count,
                                        unit: unit, notice: notice), locale: locale)
    }

    // MARK: Totals and units

    @Test func totalIsTheBarPlusEveryLoadedPlateOnBothSides() {
        let plates = [Self.plate("a", kg: 20, slot: 0), Self.plate("b", kg: 20, slot: 1),
                      Self.plate("c", kg: 35, slot: 2), Self.plate("d", kg: 45)]
        #expect(CutRackLogic.totalKg(plates) == 170)
        let m = Self.model(plates)
        #expect(m.totalValue == "170")
        #expect(m.totalUnit == "kg on the bar")
        #expect(m.totalAccessibilityLabel == "170 kilograms on the bar")
    }

    @Test func totalMatchesTheLegacyFormulaAndIgnoresTheStarter() {
        let starter = EarnedPlate.makeStarter(position: 3)
        let earned = EarnedPlate(tierID: 22, weightKg: 20, engravingText: "", earnedByEvent: "pr_bench", isRacked: true, rackPosition: 0)
        let facts = [CutRackPlateFacts(id: "earned", tierName: "Lime Bumper", engraving: "", weightKg: 20, isLoaded: true,
                                       rackPosition: 0, displayOrder: 0, earnedAt: Self.day)]
        #expect(CutRackLogic.totalKg(facts) == plateWallTotalWeight(rackedPlates: [starter, earned]))
        // The starter is never a tray plate and never takes a slot: one plate loaded, three slots left.
        let m = Self.model(facts, occupied: 1)
        #expect(m.summary == "1 plate loaded")
        #expect(m.tiles.count == 1)
    }

    @Test func emptyBarWeighsTheBarAlone() {
        let m = Self.model([])
        #expect(m.totalValue == "20")
        #expect(CutRackLogic.totalKg([]) == 20)
    }

    @Test func poundsConvertTheTotalAndEveryPlate() {
        let plates = [Self.plate("a", kg: 20, slot: 0), Self.plate("b", kg: 2.5)]
        let m = Self.model(plates, unit: .lb)
        #expect(m.totalValue == "132.3")          // 60 kg
        #expect(m.totalUnit == "lb on the bar")
        #expect(m.totalAccessibilityLabel == "132.3 pounds on the bar")
        #expect(m.tiles.map(\.weight) == ["44.1 lb", "5.5 lb"])
        #expect(m.tiles[0].accessibilityLabel == "Lime Bumper, 44.1 pounds, on the bar")
    }

    @Test func numbersStayWholeOrUseOneDecimal() {
        #expect(CutRackLogic.number(150, locale: Self.locale) == "150")
        #expect(CutRackLogic.number(2.5, locale: Self.locale) == "2.5")
        #expect(CutRackLogic.number(1_102.31, locale: Self.locale) == "1102.3")
        #expect(CutRackLogic.number(.nan, locale: Self.locale) == "0")
        #expect(CutRackLogic.weight(5, unit: .kg, locale: Self.locale) == "5 kg")
        #expect(CutRackLogic.number(2.5, locale: Locale(identifier: "de_DE")) == "2,5")
    }

    // MARK: Counts and the summary line

    @Test func summaryCountsLoadedAndStoragePlates() {
        let plates = [Self.plate("a", slot: 0), Self.plate("b", slot: 1), Self.plate("c"), Self.plate("d"), Self.plate("e")]
        #expect(Self.model(plates).summary == "2 plates loaded, 3 in storage")
        #expect(CutRackLogic.summary(loaded: 1, storage: 1) == "1 plate loaded, 1 in storage")
    }

    @Test func summaryWhenEverythingIsLoaded() {
        let plates = (0..<4).map { Self.plate("p\($0)", slot: $0) }
        let m = Self.model(plates)
        #expect(m.summary == "4 plates loaded")
        #expect(m.tiles.filter { !$0.isLoaded }.isEmpty)
        #expect(m.allTitle == "All 4")
    }

    @Test func summaryWhenNothingIsLoaded() {
        let m = Self.model([Self.plate("a"), Self.plate("b")])
        #expect(m.summary == "Nothing loaded, 2 in storage")
        #expect(m.hint == "Tap a plate below to load it.")
    }

    @Test func noPlatesAtAll() {
        let m = Self.model([])
        #expect(m.summary == "No plates yet")
        #expect(m.tiles.isEmpty)
        #expect(m.allTitle == nil)
        #expect(m.hint == nil)
        #expect(m.emptyTray == "Finish a strength workout to earn your first plate.")
    }

    // MARK: Hint and notices

    @Test func hintTeachesTheSwipeWhileAPlateIsLoaded() {
        #expect(Self.model([Self.plate("a", slot: 0), Self.plate("b")]).hint == "Swipe the bar to drop the outer plate.")
        #expect(Self.model((0..<4).map { Self.plate("p\($0)", slot: $0) }).hint == "Swipe the bar to drop the outer plate.")
    }

    @Test func hintAsksForATapWhenNothingIsLoaded() {
        // The starter plate on the bar does not count as loaded (app run: "Nothing loaded, 3 in storage").
        let m = Self.model([Self.plate("a"), Self.plate("b"), Self.plate("c")], occupied: 1)
        #expect(m.summary == "Nothing loaded, 3 in storage")
        #expect(m.hint == "Tap a plate below to load it.")
    }

    @Test func noHintWhenNoPlateIsEarned() {
        // Only the starter on the bar: the tray's empty line says how to earn a plate.
        #expect(Self.model([], occupied: 1).hint == nil)
        #expect(Self.model([], occupied: 0).hint == nil)
    }

    @Test func noticesReplaceTheHint() {
        let plates = [Self.plate("a", slot: 0)]
        #expect(Self.model(plates, notice: .barFull).hint == "The bar is full. Take a plate off first.")
        #expect(Self.model(plates, notice: .loadFailed).hint == "That plate could not be loaded. Try again.")
    }

    @Test func barIsFullAtFourSlots() {
        #expect(!CutRackLogic.isBarFull(occupiedSlots: 3))
        #expect(CutRackLogic.isBarFull(occupiedSlots: 4))
    }

    // MARK: Tray order and tiles

    @Test func trayShowsLoadedPlatesInBarOrderThenStorageNewestFirst() {
        let plates = [
            Self.plate("store-old", order: 10),
            Self.plate("bar-2", slot: 2),
            Self.plate("store-new", order: 30),
            Self.plate("bar-0", slot: 0),
            Self.plate("store-tie-b", order: 20, earned: Self.day),
            Self.plate("store-tie-a", order: 20, earned: Self.day),
            Self.plate("store-tie-newer", order: 20, earned: Self.day.addingTimeInterval(60))
        ]
        // The full list (and the load order inside a tray group) keeps the legacy wall order.
        #expect(CutRackLogic.trayOrder(plates).map(\.id) == [
            "bar-0", "bar-2", "store-new", "store-tie-newer", "store-tie-a", "store-tie-b", "store-old"
        ])
        // The tray: the loaded plates one tile each, then these five identical stored plates as
        // one tile whose tap loads the newest copy.
        let tiles = Self.model(plates).tiles
        #expect(tiles.map(\.plateID) == ["bar-0", "bar-2", "store-new"])
        #expect(tiles.last?.badge == "×5")
    }

    @Test func tilesCarryWeightStateAndVoiceOverText() {
        let m = Self.model([Self.plate("a", kg: 20, slot: 0), Self.plate("b", tier: "Dark Chrome", engraving: "Bench 100", kg: 35)])
        #expect(m.tiles[0].weight == "20 kg")
        #expect(m.tiles[0].accessibilityLabel == "Lime Bumper, 20 kilograms, on the bar")
        #expect(m.tiles[0].accessibilityHint == "Takes it off the bar.")
        #expect(m.tiles[1].accessibilityLabel == "Bench 100, 35 kilograms, in storage")
        #expect(m.tiles[1].accessibilityHint == "Loads it onto the bar.")
        #expect(m.allAccessibilityLabel == "Show all 2 plates")
    }

    @Test func sceneValueListsLoadedPlatesInsideOut() {
        let plates = [Self.plate("store", tier: "Gold", kg: 45), Self.plate("outer", tier: "Dark Chrome", engraving: "Bench 100", kg: 35, slot: 2),
                      Self.plate("inner", kg: 20, slot: 0), Self.plate("mid", tier: "Blue Bumper", kg: 20, slot: 1)]
        #expect(Self.model(plates).sceneAccessibilityValue
            == "Each side, inside out: Lime Bumper 20 kilograms, Blue Bumper 20 kilograms, Bench 100 35 kilograms")
    }

    @Test func sceneValueUsesTheUserUnit() {
        let m = Self.model([Self.plate("a", kg: 20, slot: 0)], unit: .lb)
        #expect(m.sceneAccessibilityValue.hasSuffix("Lime Bumper 44.1 pounds"))
    }

    @Test func sceneValueForAnEmptyBar() {
        #expect(Self.model([]).sceneAccessibilityValue == "Empty bar")
        #expect(Self.model([Self.plate("store")]).sceneAccessibilityValue == "Empty bar")
    }

    @Test func blankEngravingFallsBackToTheTierName() {
        #expect(CutRackLogic.name(Self.plate("a", engraving: "   ")) == "Lime Bumper")
    }

    // MARK: Scene reconciliation

    @Test func onlyPlatesThatLeftTheSavedBarAreReleased() {
        let released = CutRackLogic.sceneReleases(
            previouslyLoaded: ["a", "b", "c"], loaded: ["a"],
            barEntities: ["a", "b", "c", "dragged-in"], unloading: ["c"])
        // "b" left the bar; "c" is already sliding off; "dragged-in" was never saved on the bar.
        #expect(released == ["b"])
    }

    @Test func nothingIsReleasedWhenTheSceneAlreadyDroppedThePlate() {
        #expect(CutRackLogic.sceneReleases(previouslyLoaded: ["a"], loaded: [], barEntities: [], unloading: []).isEmpty)
    }

    // MARK: Detail and collection

    @Test func detailForAStoragePlate() {
        let facts = CutRackPlateDetailFacts(plate: Self.plate("a", engraving: "Bench 100", kg: 20), source: "Push Day",
                                            progressionTier: "Steel", workoutsUsed: 1, prCount: 2, barIsFull: false, unit: .kg)
        let m = CutRackPlateDetailLogic.model(facts, locale: Self.locale)
        #expect(m.title == "Bench 100")
        #expect(m.subtitle == "20 kg, Lime Bumper")
        #expect(m.rows.map(\.label) == ["Earned", "Earned for", "Tier", "Used in", "Records", "Where"])
        #expect(m.rows.map(\.value) == ["Sep 21, 2026", "Push Day", "Steel", "1 workout", "2 PRs", "In storage"])
        #expect(m.actionTitle == "Load onto the bar")
        #expect(m.isActionEnabled)
    }

    @Test func detailWhenTheBarIsFullOrThePlateIsLoaded() {
        var facts = CutRackPlateDetailFacts(plate: Self.plate("a"), source: "Lime Bumper", progressionTier: "Iron",
                                            workoutsUsed: 0, prCount: 0, barIsFull: true, unit: .kg)
        var m = CutRackPlateDetailLogic.model(facts, locale: Self.locale)
        #expect(m.title == "Lime Bumper")
        #expect(m.subtitle == "20 kg")
        // A source equal to the title and a zero PR count are left out.
        #expect(m.rows.map(\.label) == ["Earned", "Tier", "Used in", "Where"])
        #expect(m.actionTitle == "The bar is full")
        #expect(!m.isActionEnabled)
        facts.plate = Self.plate("a", slot: 1)
        m = CutRackPlateDetailLogic.model(facts, locale: Self.locale)
        #expect(m.actionTitle == "Take off the bar")
        #expect(m.isActionEnabled)
        #expect(m.rows.last?.value == "On the bar")
    }

    @Test func collectionListsEveryPlateInTrayOrder() {
        let m = CutRackCollectionLogic.model(plates: [Self.plate("b", kg: 5), Self.plate("a", kg: 20, slot: 0)],
                                             unit: .kg, locale: Self.locale)
        #expect(m.subtitle == "2 plates, 1 on the bar")
        #expect(m.rows.map(\.id) == ["a", "b"])
        #expect(m.rows.map(\.line) == ["20 kg, on the bar", "5 kg, in storage"])
        #expect(m.rows[1].accessibilityLabel == "Lime Bumper, 5 kilograms, in storage")
        let empty = CutRackCollectionLogic.model(plates: [], unit: .kg, locale: Self.locale)
        #expect(empty.subtitle == nil)
        #expect(empty.rows.isEmpty)
    }

    @Test func copyHasNoEmDashes() {
        let m = Self.model([Self.plate("a", slot: 0), Self.plate("b")], notice: .barFull)
        let text = [m.title, m.totalUnit, m.summary, m.hint ?? "", m.trayTitle, m.emptyTray, m.sceneAccessibilityValue] + m.tiles.map(\.accessibilityLabel)
        #expect(!text.joined().contains("\u{2014}"))
    }
}
