import Foundation
import Testing
@testable import WRKT

/// The grouped tray, the compact header text and the "Drop all" play state of the Cut rack.
/// Plain values only.
@Suite struct CutRackTrayModelTests {
    private static let locale = Locale(identifier: "en_US")
    private static let day = Date(timeIntervalSince1970: 1_790_000_000)

    private static func plate(_ id: String, tier: Int = 14, name: String = "Red Bumper", engraving: String = "",
                              kg: Double = 20, slot: Int? = nil, order: Int = 0, progression: String = "iron",
                              lift: String? = nil, material: CutRackPlateFamily = .bumper, rarity: Int = 2) -> CutRackPlateFacts {
        CutRackPlateFacts(id: id, tierName: name, engraving: engraving, weightKg: kg, isLoaded: slot != nil,
                          rackPosition: slot, displayOrder: order, earnedAt: day, tierID: tier,
                          progressionTier: progression, liftTypeID: lift, material: material, rarity: rarity)
    }

    private static func model(_ plates: [CutRackPlateFacts], unit: WeightUnit = .kg,
                              phase: CutRackPlayPhase = .idle) -> CutRackModel {
        CutRackLogic.model(CutRackFacts(plates: plates, occupiedSlots: plates.filter(\.isLoaded).count, unit: unit,
                                        notice: nil, playPhase: phase), locale: locale)
    }

    // MARK: Identical

    @Test func identicalMeansSameTierWeightEngravingProgressionAndLift() {
        let a = Self.plate("a", engraving: "Bench  100 ")
        #expect(CutRackLogic.areIdentical(a, Self.plate("b", engraving: "BENCH 100", slot: 2, order: 9)))
        #expect(!CutRackLogic.areIdentical(a, Self.plate("c", tier: 15, engraving: "Bench 100")))
        #expect(!CutRackLogic.areIdentical(a, Self.plate("d", engraving: "Bench 100", kg: 25)))
        #expect(!CutRackLogic.areIdentical(a, Self.plate("e", engraving: "Bench 110")))
        #expect(!CutRackLogic.areIdentical(a, Self.plate("f", engraving: "Bench 100", progression: "steel")))
        #expect(!CutRackLogic.areIdentical(a, Self.plate("g", engraving: "Bench 100", lift: "bench-press")))
        // No lift and the legacy "global" scope are the same plate.
        #expect(CutRackLogic.areIdentical(Self.plate("h", lift: nil), Self.plate("i", lift: "global")))
        #expect(CutRackLogic.areIdentical(Self.plate("j", lift: ""), Self.plate("k", lift: nil)))
    }

    @Test func engravedPlatesSitWithTheEngravedOnesWhateverTheirMaterial() {
        #expect(CutRackLogic.family(Self.plate("a", engraving: "75 Workouts", material: .metal)) == .engraved)
        #expect(CutRackLogic.family(Self.plate("b", engraving: "  ", material: .iron)) == .iron)
        #expect(CutRackLogic.family(Self.plate("c", material: .metal)) == .metal)
    }

    // MARK: Groups and counts

    @Test func identicalStoredPlatesShareOneTileWithACount() {
        let reds = (0..<12).map { Self.plate("red\($0)", order: $0) }
        let m = Self.model(reds + [Self.plate("blue", tier: 15, name: "Blue Bumper")])
        #expect(m.tiles.count == 2)
        let red = m.tiles.first { $0.plateID.hasPrefix("red") }
        #expect(red?.badge == "×12")
        #expect(red?.storedCount == 12)
        #expect(red?.accessibilityLabel == "Red Bumper, 20 kilograms, 12 in storage")
        #expect(red?.accessibilityHint == "Loads one onto the bar.")
        let blue = m.tiles.first { $0.plateID == "blue" }
        #expect(blue?.badge == nil)
        #expect(blue?.accessibilityLabel == "Blue Bumper, 20 kilograms, in storage")
        #expect(blue?.accessibilityHint == "Loads it onto the bar.")
    }

    @Test func aTapOnAGroupLoadsItsNewestCopyFirst() {
        // The legacy wall order inside a group: the highest display order first.
        let plates = [Self.plate("old", order: 1), Self.plate("new", order: 7), Self.plate("mid", order: 4)]
        let group = CutRackLogic.storageGroups(plates)[0]
        #expect(group.stored.map(\.id) == ["new", "mid", "old"])
        #expect(CutRackLogic.nextToLoad(group)?.id == "new")
        #expect(Self.model(plates).tiles[0].plateID == "new")
    }

    @Test func loadingOneCopyDecrementsTheBadgeAndShowsItOnTheBar() {
        var plates = (0..<3).map { Self.plate("red\($0)", order: $0) }
        var m = Self.model(plates)
        let tileID = m.tiles[0].id
        #expect(m.tiles[0].badge == "×3")
        // The host saves the tapped copy as loaded (slot 0); the tile keeps its identity.
        let loadedID = m.tiles[0].plateID
        plates = plates.map { $0.id == loadedID ? Self.plate($0.id, slot: 0, order: $0.displayOrder) : $0 }
        m = Self.model(plates)
        #expect(m.sections.map(\.title) == ["On the bar", "Bumpers"])
        #expect(m.sections[0].tiles.map(\.plateID) == [loadedID])
        #expect(m.sections[0].tiles[0].isLoaded)
        let group = m.sections[1].tiles[0]
        #expect(group.id == tileID)
        #expect(group.badge == "×2")
        #expect(group.onBarCount == 1)
        #expect(group.accessibilityLabel == "Red Bumper, 20 kilograms, 2 in storage, 1 on the bar")
        #expect(m.summary == "1 plate loaded, 2 in storage")
    }

    @Test func theLastCopyLeavesASingleTileAndAFullyLoadedLookLeavesNone() {
        let two = [Self.plate("a", slot: 0), Self.plate("b", order: 1)]
        let m = Self.model(two)
        #expect(m.sections.last?.tiles.map(\.badge) == [nil])
        #expect(m.sections.last?.tiles.first?.accessibilityLabel == "Red Bumper, 20 kilograms, in storage, 1 on the bar")
        let all = Self.model([Self.plate("a", slot: 0), Self.plate("b", slot: 1)])
        #expect(all.sections.count == 1)
        #expect(all.sections[0].title == nil)
        #expect(all.tiles.allSatisfy { $0.isLoaded })
    }

    @Test func loadedPlatesStayOneTileEachInBarOrder() {
        let plates = [Self.plate("outer", slot: 3), Self.plate("inner", slot: 0), Self.plate("mid", slot: 1)]
        let m = Self.model(plates)
        #expect(m.tiles.map(\.plateID) == ["inner", "mid", "outer"])
        #expect(m.tiles.allSatisfy { $0.badge == nil && $0.accessibilityHint == "Takes it off the bar." })
    }

    @Test func storageIsSortedByFamilyThenHeaviestThenRarest() {
        let plates = [
            Self.plate("iron", tier: 1, name: "Cast Iron", kg: 25, material: .iron, rarity: 0),
            Self.plate("bump10", tier: 2, name: "Black Bumper", kg: 10, rarity: 1),
            Self.plate("bump20-rare", tier: 14, name: "Red Bumper", kg: 20, rarity: 2),
            Self.plate("bump20-epic", tier: 22, name: "Lime Bumper", kg: 20, rarity: 3),
            Self.plate("gold", tier: 6, name: "Gold", kg: 45, material: .metal, rarity: 4),
            Self.plate("bench", tier: 26, name: "Dark Chrome", engraving: "Bench 100", kg: 35, material: .metal, rarity: 3),
            Self.plate("first", tier: 0, name: "Rusty Iron", engraving: "First Lift", kg: 2.5, material: .iron, rarity: 0)
        ]
        let m = Self.model(plates)
        // Everyday plates first (where the piles are), the one-off engraved plates last.
        #expect(m.sections.map(\.title) == ["Bumpers", "Iron", "Metal", "Engraved"])
        #expect(m.tiles.map(\.plateID) == ["bump20-epic", "bump20-rare", "bump10", "iron", "gold", "bench", "first"])
    }

    @Test func aBiggerPileComesFirstAmongEquals() {
        let plates = [Self.plate("blue", tier: 15, name: "Blue Bumper")] + (0..<4).map { Self.plate("red\($0)") }
        #expect(Self.model(plates).tiles.map(\.badge) == ["×4", nil])
    }

    @Test func aRealisticNinetyPlateInventoryBrowsesAsAboutThirtyFiveTiles() {
        // The shape of CutRackRealisticInventory: piles of plain bumpers and record plates, many
        // one-off engraved plates.
        var plates: [CutRackPlateFacts] = []
        func add(_ count: Int, _ make: (Int) -> CutRackPlateFacts) { plates += (0..<count).map(make) }
        add(14) { Self.plate("red\($0)", slot: $0 < 2 ? $0 + 1 : nil, order: $0) }
        add(7) { Self.plate("blue\($0)", tier: 15, name: "Blue Bumper", order: $0) }
        add(18) { Self.plate("pr\($0)", tier: 4, name: "Competition", engraving: "Personal Record", order: $0, progression: "steel") }
        add(51) { Self.plate("one-off\($0)", tier: 0, name: "Rusty Iron", engraving: "Session \($0)", kg: 5, order: $0, material: .iron) }
        let m = Self.model(plates)
        #expect(plates.count == 90)
        #expect(m.summary == "2 plates loaded, 88 in storage")
        #expect(m.tiles.count == 2 + 1 + 1 + 1 + 51)
        #expect(m.tiles.map(\.storedCount).reduce(0, +) == 88)
    }

    // MARK: Header

    @Test func headerReadsAsOneLabel() {
        let m = Self.model([Self.plate("a", kg: 25, slot: 0), Self.plate("b", slot: 1), Self.plate("c", slot: 2)]
                           + (0..<87).map { Self.plate("s\($0)", tier: 15, name: "Blue Bumper") })
        #expect(m.totalValue == "150")
        #expect(m.totalUnit == "kg on the bar")
        #expect(m.summary == "3 plates loaded, 87 in storage")
        #expect(m.headerAccessibilityLabel == "150 kilograms on the bar. 3 plates loaded, 87 in storage")
        let lb = Self.model([Self.plate("a", slot: 0)], unit: .lb)
        #expect(lb.headerAccessibilityLabel == "132.3 pounds on the bar. 1 plate loaded")
    }

    // MARK: Drop all and tidy up

    @Test func dropAllIsOfferedOnlyWithStoredPlates() {
        let idle = Self.model([Self.plate("a", slot: 0), Self.plate("b"), Self.plate("c", tier: 15)])
        #expect(idle.playAction?.title == "Drop all")
        #expect(idle.playAction?.accessibilityLabel == "Drop all 2 stored plates")
        #expect(idle.playAction?.isTidy == false)
        #expect(Self.model([Self.plate("a", slot: 0)]).playAction == nil)
        #expect(Self.model([]).playAction == nil)
    }

    @Test func aCappedDropSaysHowManyFall() {
        let stored = (0..<20).map { Self.plate("red\($0)") }
        let capped = CutRackLogic.model(CutRackFacts(plates: stored, occupiedSlots: 0, unit: .kg, notice: nil, rainCap: 16),
                                        locale: Self.locale)
        #expect(capped.playAction?.title == "Drop 16")
        #expect(capped.playAction?.accessibilityLabel == "Drop 16 of 20 stored plates")
        #expect(capped.playAction?.accessibilityHint.hasPrefix("Up to 16 fit on the floor at once.") == true)
        let fits = CutRackLogic.model(CutRackFacts(plates: Array(stored.prefix(16)), occupiedSlots: 0, unit: .kg, notice: nil,
                                                   rainCap: 16), locale: Self.locale)
        #expect(fits.playAction?.title == "Drop all")
    }

    @Test func tidyUpReplacesDropAllWhilePlatesAreDownAndTheHintTeachesTheLoad() {
        for phase in [CutRackPlayPhase.raining, .loose] {
            let m = Self.model([Self.plate("a", slot: 0), Self.plate("b")], phase: phase)
            #expect(m.playAction?.title == "Tidy up")
            #expect(m.playAction?.isTidy == true)
            #expect(m.hint == "Drag a plate to a sleeve end to load it.")
            // The data does not change: counts stay as saved.
            #expect(m.summary == "1 plate loaded, 1 in storage")
        }
    }

    @Test func rainPicksVarietyFirstWithinTheCaps() {
        let plates = (0..<5).map { Self.plate("red\($0)", order: 10 - $0) }
            + (0..<3).map { Self.plate("blue\($0)", tier: 15, name: "Blue Bumper", order: 10 - $0) }
            + [Self.plate("gold", tier: 6, name: "Gold", kg: 45, material: .metal, rarity: 4),
               Self.plate("loaded", tier: 6, name: "Gold", kg: 45, slot: 0, material: .metal, rarity: 4)]
        // One of each look, then second copies, up to the plate cap.
        #expect(CutRackRainLogic.selection(plates, cap: 5, maxLooks: 10) == ["red0", "blue0", "gold", "red1", "blue1"])
        // At most two distinct looks (faces): only red and blue fall.
        #expect(CutRackRainLogic.selection(plates, cap: 4, maxLooks: 2) == ["red0", "blue0", "red1", "blue1"])
        // Everything fits: every stored plate once, never a loaded one.
        let all = CutRackRainLogic.selection(plates, cap: 100, maxLooks: 100)
        #expect(all.count == 9)
        #expect(!all.contains("loaded"))
        #expect(Set(all).count == all.count)
        // Plates already lying in the room are skipped.
        #expect(!CutRackRainLogic.selection(plates, cap: 100, maxLooks: 100, exclude: ["red0"]).contains("red0"))
        #expect(CutRackRainLogic.selection(plates, cap: 0, maxLooks: 10).isEmpty)
    }

    @Test func rainIsAnnouncedOnce() {
        #expect(CutRackRainLogic.announcement(dropped: 40, stored: 87)
            == "Dropped 40 plates of 87 onto the floor. Drag one to a sleeve end to load it.")
        #expect(CutRackRainLogic.announcement(dropped: 1, stored: 1)
            == "Dropped 1 plate onto the floor. Drag one to a sleeve end to load it.")
        #expect(CutRackRainLogic.announcement(dropped: 0, stored: 0) == "No plates to drop.")
    }

    @Test func newCopyHasNoEmDashes() {
        let m = Self.model([Self.plate("a", slot: 0), Self.plate("b"), Self.plate("c")], phase: .loose)
        let text = [m.headerAccessibilityLabel, m.playAction?.accessibilityHint ?? "", m.hint ?? "",
                    CutRackRainLogic.announcement(dropped: 3, stored: 9), CutRackRainLogic.tidyAnnouncement]
            + m.sections.compactMap(\.title) + m.tiles.map(\.accessibilityLabel)
        #expect(!text.joined().contains("\u{2014}"))
    }
}
