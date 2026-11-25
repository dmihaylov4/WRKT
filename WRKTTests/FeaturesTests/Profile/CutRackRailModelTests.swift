import Foundation
import Testing
@testable import WRKT

/// The storage rail tray of the Cut rack: its switch, groups, slots, counts, stamps, labels, the
/// lifted plate, the tap rules and the readout flash. Plain values only.
@Suite struct CutRackRailModelTests {
    private static let locale = Locale(identifier: "en_US")
    private static let day = Date(timeIntervalSince1970: 1_790_000_000)

    private static func plate(_ id: String, tier: Int = 14, name: String = "Red Bumper", engraving: String = "",
                              kg: Double = 20, slot: Int? = nil, order: Int = 0,
                              material: CutRackPlateFamily = .bumper, rarity: Int = 2) -> CutRackPlateFacts {
        CutRackPlateFacts(id: id, tierName: name, engraving: engraving, weightKg: kg, isLoaded: slot != nil,
                          rackPosition: slot, displayOrder: order, earnedAt: day, tierID: tier,
                          material: material, rarity: rarity)
    }

    private static func rail(_ plates: [CutRackPlateFacts], unit: WeightUnit = .kg, phase: CutRackPlayPhase = .idle,
                             inFlight: Set<String> = [], onFloor: Set<String> = [], notice: CutRackNotice? = nil,
                             tap: CutRackRailTap = .preview) -> CutRackRailModel {
        CutRackRailLogic.model(CutRackRailFacts(plates: plates, unit: unit, notice: notice, playPhase: phase,
                                                inFlight: inFlight, onFloor: onFloor, tap: tap), locale: locale)
    }

    private static let reds = (0..<12).map { plate("red\($0)", order: $0) }

    // MARK: Switch

    @Test func releaseBuildsAlwaysShowTheCardTray() {
        #expect(CutRackTrayStyle.resolve(isDebugBuild: false, environment: [:]) == .card)
        #expect(CutRackTrayStyle.resolve(isDebugBuild: false, environment: [CutRackTrayStyle.overrideKey: "rail"]) == .card)
    }

    @Test func debugBuildsShowTheRailUnlessTheLaunchEnvironmentAsksForTheCard() {
        #expect(CutRackTrayStyle.resolve(isDebugBuild: true, environment: [:]) == .rail)
        #expect(CutRackTrayStyle.resolve(isDebugBuild: true, environment: [CutRackTrayStyle.overrideKey: "card"]) == .card)
        #expect(CutRackTrayStyle.resolve(isDebugBuild: true, environment: [CutRackTrayStyle.overrideKey: "bogus"]) == .rail)
    }

    @Test func aTapLiftsThePlateOutUnlessTheLaunchEnvironmentAsksForLoad() {
        #expect(CutRackRailTap.resolve(environment: [:]) == .preview)
        #expect(CutRackRailTap.resolve(environment: [CutRackRailTap.overrideKey: "load"]) == .load)
    }

    // MARK: Groups

    @Test func identicalPlatesStandTogetherWithTheirCountStampedUnderThem() {
        let m = Self.rail(Self.reds + [Self.plate("blue", tier: 15, name: "Blue Bumper")])
        #expect(m.groups.count == 2)
        let red = try! #require(m.groups.first { $0.tierID == 14 })
        #expect(red.stored == 12)
        #expect(red.platesShown == CutRackRailLogic.maxPlatesShown)
        #expect(red.numeral == "20")
        #expect(red.count == "×12")
        #expect(red.accessibilityLabel == "Red Bumper, 20 kilograms, 12 in storage")
        let blue = try! #require(m.groups.first { $0.tierID == 15 })
        #expect(blue.count == nil)
        #expect(blue.platesShown == 1)
        #expect(blue.accessibilityLabel == "Blue Bumper, 20 kilograms, in storage")
        #expect(m.status == "13 in storage")
    }

    @Test func theRailKeepsTheCardTraysGroupingAndOrder() {
        let plates = Self.reds + [
            Self.plate("iron", tier: 0, name: "Rusty Iron", kg: 5, material: .iron),
            Self.plate("gold", tier: 6, name: "Gold", kg: 45, material: .metal),
            Self.plate("eng", tier: 8, name: "Rose Gold", engraving: "75 Workouts", kg: 25, material: .metal),
            Self.plate("blue25", tier: 15, name: "Blue Bumper", kg: 25)
        ]
        let rail = Self.rail(plates)
        let card = CutRackLogic.storageGroups(plates).map { "look:" + $0.look.key }
        #expect(rail.groups.map(\.id) == card)
        #expect(rail.sections.map(\.title) == ["Bumpers", "Iron", "Metal", "Engraved"])
        // One section only: no title, as in the card tray.
        #expect(Self.rail(Self.reds).sections.map(\.title) == [nil])
    }

    @Test func aLoadedCopyLeavesALimeSlotWhereItStoodAndTheCountDrops() {
        var plates = Self.reds
        plates[11] = Self.plate("red11", slot: 0, order: 11)
        plates[10] = Self.plate("red10", slot: 1, order: 10)
        let red = try! #require(Self.rail(plates).groups.first)
        #expect(red.stored == 10)
        #expect(red.loaded == 2)
        #expect(red.loadedSlots == 2)
        #expect(red.count == "×10")
        #expect(red.accessibilityLabel == "Red Bumper, 20 kilograms, 10 in storage, 2 on the bar")
        // The next load takes the newest stored copy; take-off takes the outermost loaded one.
        #expect(red.nextToLoad == "red9")
        #expect(red.nextToUnload == "red10")
    }

    @Test func aLookWhoseCopiesAreAllOnTheBarKeepsItsPlaceAsSlotsOnly() {
        let plates = [Self.plate("eng", tier: 8, name: "Rose Gold", engraving: "75 Workouts", kg: 25, slot: 0,
                                 material: .metal)] + Self.reds
        let m = Self.rail(plates)
        let engraved = try! #require(m.groups.first { $0.tierID == 8 })
        #expect(engraved.stored == 0)
        #expect(engraved.platesShown == 0)
        #expect(engraved.loadedSlots == 1)
        #expect(engraved.nextToLoad == nil)
        #expect(engraved.nextToUnload == "eng")
        #expect(engraved.count == nil)
        #expect(engraved.accessibilityLabel == "75 Workouts, 25 kilograms, on the bar")
        #expect(m.sections.last?.title == "Engraved")
    }

    @Test func aPlateSwingingInHasAlreadyLeftTheRail() {
        let id = Self.reds[11].id
        let red = try! #require(Self.rail(Self.reds, inFlight: [id]).groups.first)
        #expect(red.stored == 11)
        #expect(red.loadedSlots == 1)
        #expect(red.nextToLoad != id)
    }

    @Test func droppedPlatesLeaveWhiteSlotsAndTheFooterCountsTheFloor() {
        let floor = Set(Self.reds.prefix(5).map(\.id))
        let m = Self.rail(Self.reds, phase: .loose, onFloor: floor)
        let red = try! #require(m.groups.first)
        #expect(red.stored == 7)
        #expect(red.onFloor == 5)
        #expect(red.floorSlots == CutRackRailLogic.maxFloorSlots)
        #expect(red.accessibilityLabel == "Red Bumper, 20 kilograms, 7 in storage, 5 on the floor")
        #expect(!floor.contains(red.nextToLoad ?? ""))
        #expect(m.status == "5 on the floor")
        // Tidied: nothing on the floor any more.
        #expect(Self.rail(Self.reds).status == "12 in storage")
    }

    @Test func stampsUseTheUsersUnitAndKeepOneDecimal() {
        let plates = [Self.plate("a", kg: 2.5), Self.plate("b", tier: 15, kg: 20)]
        #expect(Self.rail(plates).groups.map(\.numeral).sorted() == ["2.5", "20"])
        let pounds = Self.rail(plates, unit: .lb)
        #expect(pounds.unit == "lb")
        #expect(pounds.groups.map(\.numeral).sorted() == ["44.1", "5.5"])
        #expect(Self.rail([]).emptyRail == CutRackLogic.emptyTrayLine)
    }

    @Test func theHintSaysWhatATapDoesUntilSomethingIsLoaded() {
        #expect(Self.rail(Self.reds).hint == "Tap a plate on the rack to lift it out.")
        #expect(Self.rail(Self.reds, tap: .load).hint == "Tap a plate on the rack to load it.")
        #expect(Self.rail([Self.plate("a", slot: 0)] + Self.reds).hint == nil)
        #expect(Self.rail(Self.reds, notice: .barFull).hint == "The bar is full. Take a plate off first.")
        #expect(Self.rail(Self.reds, phase: .loose).hint == "Drag a plate to a sleeve end to load it.")
        #expect(Self.rail([]).hint == nil)
    }

    // MARK: Lifted plate

    @Test func theLiftedPlateNamesItselfAndOffersLoadAndTakeOff() {
        var plates = Self.reds
        plates[11] = Self.plate("red11", slot: 0, order: 11)
        let red = try! #require(Self.rail(plates).groups.first)
        let p = CutRackRailLogic.preview(red, barIsFull: false, unit: .kg, locale: Self.locale)
        #expect(p.title == "Red Bumper")
        #expect(p.engraving == nil)
        #expect(p.weight == "20 kg")
        #expect(p.counts == "11 in storage, 1 on the bar")
        #expect(p.loadTitle == "Load onto the bar")
        #expect(p.canLoad)
        #expect(p.unloadTitle == "Take off the bar")
        #expect(p.accessibilityLabel == "Red Bumper, 20 kilograms, 11 in storage, 1 on the bar")

        let full = CutRackRailLogic.preview(red, barIsFull: true, unit: .kg, locale: Self.locale)
        #expect(full.loadTitle == "The bar is full")
        #expect(!full.canLoad)
    }

    @Test func anEngravedPlateShowsItsEngravingFirst() {
        let eng = Self.plate("eng", tier: 8, name: "Rose Gold", engraving: "75 Workouts", kg: 25, material: .metal)
        let group = try! #require(Self.rail([eng]).groups.first)
        let p = CutRackRailLogic.preview(group, barIsFull: false, unit: .kg, locale: Self.locale)
        #expect(p.engraving == "75 WORKOUTS")
        #expect(p.title == "Rose Gold")
        #expect(p.unloadTitle == nil)
        #expect(p.accessibilityLabel == "75 Workouts, Rose Gold, 25 kilograms, 1 in storage")
    }

    @Test func theBarCountsLoadsStillInFlight() {
        #expect(!CutRackRailLogic.isBarFull(occupiedSlots: 2, inFlight: 1))
        #expect(CutRackRailLogic.isBarFull(occupiedSlots: 3, inFlight: 1))
    }

    // MARK: Taps

    @Test func previewModeLiftsFirstAndLoadsOnASecondTapOfTheSameGroup() {
        var plates = Self.reds
        plates[11] = Self.plate("red11", slot: 0, order: 11)
        let red = try! #require(Self.rail(plates).groups.first)
        #expect(CutRackRailLogic.tap(red, lifted: nil, mode: .preview) == .lift(red.id))
        #expect(CutRackRailLogic.tap(red, lifted: "look:other", mode: .preview) == .lift(red.id))
        #expect(CutRackRailLogic.tap(red, lifted: red.id, mode: .preview) == .load("red10"))
        #expect(CutRackRailLogic.hold(red) == .lift(red.id))
        // Nothing left in the rack: the second tap puts it back.
        let onBar = try! #require(Self.rail([Self.plate("a", slot: 0)]).groups.first)
        #expect(CutRackRailLogic.tap(onBar, lifted: onBar.id, mode: .preview) == .close)
    }

    @Test func loadModeLoadsAtOnceOrTakesOneOffWhenAllAreOnTheBar() {
        let red = try! #require(Self.rail(Self.reds).groups.first)
        #expect(CutRackRailLogic.tap(red, lifted: nil, mode: .load) == .load("red11"))
        let onBar = try! #require(Self.rail([Self.plate("a", slot: 0)]).groups.first)
        #expect(CutRackRailLogic.tap(onBar, lifted: nil, mode: .load) == .unload("a"))
    }

    // MARK: Readout flash

    @Test func theReadoutFlashesTheChangeAndTheNewTotal() {
        let added = try! #require(CutRackRailLogic.flash(fromKg: 150, toKg: 190, unit: .kg, locale: Self.locale))
        #expect(added.delta == "+40")
        #expect(added.total == "190")
        #expect(added.unit == "kg on the bar")
        #expect(added.accessibilityLabel == "Added 40 kilograms. 190 kilograms on the bar")
        let removed = try! #require(CutRackRailLogic.flash(fromKg: 190, toKg: 150, unit: .kg, locale: Self.locale))
        #expect(removed.delta == "\u{2212}40")
        #expect(removed.accessibilityLabel == "Took off 40 kilograms. 150 kilograms on the bar")
        #expect(CutRackRailLogic.flash(fromKg: 150, toKg: 150, unit: .kg, locale: Self.locale) == nil)
    }

    @Test func theReadoutUsesTheUsersUnit() {
        let pounds = try! #require(CutRackRailLogic.flash(fromKg: 20, toKg: 60, unit: .lb, locale: Self.locale))
        #expect(pounds.delta == "+88.2")
        #expect(pounds.total == "132.3")
        #expect(pounds.unit == "lb on the bar")
    }

    @Test func theModelCarriesTheTotalInKilogramsForTheFlash() {
        let m = CutRackLogic.model(CutRackFacts(plates: [Self.plate("a", slot: 0)], occupiedSlots: 1, unit: .lb), locale: Self.locale)
        #expect(m.totalKg == 60)
        #expect(m.unit == .lb)
    }
}
