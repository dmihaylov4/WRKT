import Foundation
import Testing
@testable import WRKT

/// The starter plate is never shown and never takes a bar slot. In-memory plates only: nothing is
/// inserted into a SwiftData container and no service or backend is called.
@MainActor
@Suite struct BarbellStarterPlateTests {
    private static let day = Date(timeIntervalSince1970: 1_790_000_000)

    private static func earned(_ id: String, slot: Int? = nil, order: Double = 0) -> EarnedPlate {
        EarnedPlate(id: id, tierID: 22, weightKg: 20, engravingText: "", earnedAt: day.addingTimeInterval(order),
                    earnedByEvent: "pr_\(id)", isRacked: slot != nil, rackPosition: slot)
    }

    private static func starter(racked: Bool = true) -> EarnedPlate {
        let plate = EarnedPlate.makeStarter(position: 3)
        if !racked {
            plate.isRacked = false
            plate.rackPosition = nil
        }
        return plate
    }

    @Test func onlyAStarterIsAnEmptyBar() {
        let plates = [Self.starter()]
        #expect(BarbellBarSlots.barPlates(plates).isEmpty)
        #expect(BarbellBarSlots.occupiedSlots(plates).isEmpty)
        #expect(BarbellBarSlots.nextFreeSlot(plates) == 0)
    }

    @Test func starterPlusThreeEarnedLeavesTheFourthSlotFree() {
        var plates = [Self.earned("a", slot: 0), Self.earned("b", slot: 1), Self.earned("c", slot: 2), Self.starter()]
        #expect(BarbellBarSlots.occupiedSlots(plates) == [0, 1, 2])
        #expect(BarbellBarSlots.nextFreeSlot(plates) == 3)

        // The fourth earned plate takes slot 3 while the old starter row still claims it.
        plates.append(Self.earned("d", slot: 3))
        let bar = BarbellBarSlots.barPlates(plates)
        #expect(bar.map(\.id) == ["a", "b", "c", "d"])
        #expect(Set(bar.compactMap(\.rackPosition)).count == bar.count, "no two bar plates share a slot")
        #expect(BarbellBarSlots.occupiedSlots(plates) == [0, 1, 2, 3])
        #expect(BarbellBarSlots.nextFreeSlot(plates) == nil)
    }

    @Test func aStarterThatWasTakenOffChangesNothing() {
        let plates = [Self.earned("a", slot: 0), Self.starter(racked: false)]
        #expect(BarbellBarSlots.barPlates(plates).map(\.id) == ["a"])
        #expect(BarbellBarSlots.nextFreeSlot(plates) == 1)
    }

    @Test func noStarterRowAtAll() {
        let plates = [Self.earned("a", slot: 0), Self.earned("b", slot: 2), Self.earned("store")]
        #expect(BarbellBarSlots.barPlates(plates).map(\.id) == ["a", "b"])
        #expect(BarbellBarSlots.occupiedSlots(plates) == [0, 2])
        #expect(BarbellBarSlots.nextFreeSlot(plates) == 1)
        #expect(BarbellBarSlots.nextFreeSlot([]) == 0)
    }

    @Test func slotsOutsideTheBarHoldNothing() {
        let plates = [Self.earned("a", slot: 7)]
        #expect(BarbellBarSlots.occupiedSlots(plates).isEmpty)
        #expect(BarbellBarSlots.nextFreeSlot(plates) == 0)
    }

    @Test func aSavedLoadoutListingTheStarterNeverShowsIt() {
        let starter = Self.starter()
        let plates = [Self.earned("a", slot: 0), Self.earned("b", slot: 1), Self.earned("c", slot: 2),
                      starter, Self.earned("d", slot: 3)]
        let loadout = DisplayLoadout(onBar: ["a", "b", "c", starter.id, "d"], onWall: [])
        let shown = configuredBarbellDisplayPlates(loadout: loadout, earnedPlates: plates)
        #expect(shown?.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func starterIsRecognisedByEventOrTier() {
        #expect(Self.starter().isStarterPlate)
        #expect(!Self.earned("a").isStarterPlate)
        #expect(EarnedPlateInfo(tierID: 7, weightKg: 0, engravingText: "", earnedByEvent: "starter").isStarterPlate)
        #expect(EarnedPlateInfo(tierID: 7, weightKg: 0, engravingText: "", earnedByEvent: "friend_row").isStarterPlate)
        #expect(!EarnedPlateInfo(tierID: 22, weightKg: 20, engravingText: "", earnedByEvent: "pr_bench").isStarterPlate)
    }
}
