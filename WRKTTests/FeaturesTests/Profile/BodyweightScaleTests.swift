import Foundation
import Testing
@testable import WRKT

@Suite("Bodyweight scale")
struct BodyweightScaleTests {
    // MARK: Conversion at the boundary

    @Test func kilogramsShowAsTheyAre() {
        #expect(BodyweightScale.tenths(kg: 82.5, unit: .kg) == 825)
        // 70.3 is stored as 70.29999...; the wheel must show 70.3, not 70.2.
        #expect(BodyweightScale.tenths(kg: 70.3, unit: .kg) == 703)
        #expect(BodyweightScale.kg(tenths: 703, unit: .kg) == 70.3)
    }

    @Test func poundsShowInPounds() {
        // 82.5 kg is 181.88 lb.
        #expect(BodyweightScale.tenths(kg: 82.5, unit: .lb) == 1819)
        #expect(abs(BodyweightScale.kg(tenths: 1800, unit: .lb) - 81.6467) < 0.0001)
    }

    // MARK: Range

    @Test func rangesCoverThirtyToTwoHundredFiftyKilograms() {
        #expect(BodyweightScale.wholeRange(.kg) == 30...250)
        #expect(BodyweightScale.wholeRange(.lb) == 66...551)
        #expect(BodyweightScale.tenthsSpan(.kg) == 300...2509)
        #expect(BodyweightScale.tenthsSpan(.lb) == 660...5519)
        #expect(BodyweightScale.tenthsRange == 0...9)
    }

    @Test func valuesOutsideTheWheelAreClamped() {
        #expect(BodyweightScale.tenths(kg: 12, unit: .kg) == 300)
        #expect(BodyweightScale.tenths(kg: 400, unit: .kg) == 2509)
        #expect(BodyweightScale.tenths(kg: 12, unit: .lb) == 660)
        #expect(BodyweightScale.tenths(kg: 400, unit: .lb) == 5519)
    }

    // MARK: Round trips

    @Test(arguments: [WeightUnit.kg, .lb])
    func everyWheelValueRoundTrips(unit: WeightUnit) {
        for tenths in BodyweightScale.tenthsSpan(unit) {
            let kg = BodyweightScale.kg(tenths: tenths, unit: unit)
            #expect(BodyweightScale.tenths(kg: kg, unit: unit) == tenths)
        }
    }

    @Test func editingInPoundsReopensOnTheSamePounds() {
        var draft = BodyweightDraft(kg: 80, unit: .lb)
        draft.whole = 180
        draft.tenth = 0
        let stored = try! #require(draft.kgToCommit)
        let reopened = BodyweightDraft(kg: stored, unit: .lb)
        #expect(reopened.whole == 180)
        #expect(reopened.tenth == 0)
        #expect(BodyweightScale.line(kg: stored, unit: .lb) == "180 lb")
    }

    @Test func anUntouchedWheelStoresNothing() {
        let draft = BodyweightDraft(kg: 81.6466, unit: .lb)
        #expect(draft.kgToCommit == nil)
        var turnedBack = draft
        turnedBack.whole += 3
        turnedBack.whole -= 3
        #expect(turnedBack.kgToCommit == nil)
    }

    @Test func wheelsEditWholeAndTenthSeparately() {
        var draft = BodyweightDraft(kg: 82.5, unit: .kg)
        #expect(draft.whole == 82)
        #expect(draft.tenth == 5)
        draft.whole = 90
        #expect(draft.tenths == 905)
        draft.tenth = 2
        #expect(draft.tenths == 902)
        #expect(draft.kgToCommit == 90.2)
    }

    // MARK: Row

    @Test func rowLineInTheUnit() {
        #expect(BodyweightScale.line(kg: 82.5, unit: .kg) == "82.5 kg")
        #expect(BodyweightScale.line(kg: 80, unit: .kg) == "80 kg")
        #expect(BodyweightScale.line(kg: 82.5, unit: .lb) == "181.9 lb")
        #expect(BodyweightScale.line(kg: 82.5, unit: nil) == "82.5 kg")
    }
}
