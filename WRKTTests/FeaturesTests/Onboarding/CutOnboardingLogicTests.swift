import Foundation
import Testing
@testable import WRKT

@MainActor
@Suite struct CutOnboardingLogicTests {
    @Test func fourStepsThreeIntroPagesThenBodyweight() {
        #expect(CutOnboardingLogic.stepCount == 4)
        #expect(CutOnboardingLogic.pages.map(\.id) == [0, 1, 2])
        #expect(CutOnboardingLogic.pages.map(\.title) == ["Track every set", "Keep showing up", "Train smart"])
        #expect(CutOnboardingLogic.pages[0].line == "Log weights and reps in one tap, and see each lift move week by week.")
        for page in CutOnboardingLogic.pages {
            #expect(!page.line.isEmpty)
            #expect(!page.line.contains("\u{2014}"))
            #expect(page.title.split(separator: " ").count <= 3)
        }
        #expect(CutOnboardingLogic.bodyweightIndex == 3)
        #expect(CutOnboardingLogic.bodyweightTitle == "Your starting point")
    }

    @Test func nextAdvancesUntilTheLastPageAndBackReturns() {
        #expect(CutOnboardingLogic.next(after: 0) == 1)
        #expect(CutOnboardingLogic.next(after: 2) == 3)
        #expect(CutOnboardingLogic.next(after: 3) == nil)
        #expect(CutOnboardingLogic.isLast(3))
        #expect(!CutOnboardingLogic.isLast(2))
        #expect(CutOnboardingLogic.back(from: 3) == 2)
        #expect(CutOnboardingLogic.back(from: 0) == nil)
    }

    @Test func aSwipeMovesOnePageWithinTheFour() {
        #expect(CutOnboardingLogic.page(afterSwipe: -150, vertical: 10, from: 0, width: 400) == 1)
        #expect(CutOnboardingLogic.page(afterSwipe: 150, vertical: 10, from: 2, width: 400) == 1)
        // Too short, mostly vertical, or past either end: stays.
        #expect(CutOnboardingLogic.page(afterSwipe: -60, vertical: 0, from: 1, width: 400) == 1)
        #expect(CutOnboardingLogic.page(afterSwipe: -150, vertical: 300, from: 1, width: 400) == 1)
        #expect(CutOnboardingLogic.page(afterSwipe: 150, vertical: 0, from: 0, width: 400) == 0)
        #expect(CutOnboardingLogic.page(afterSwipe: -150, vertical: 0, from: 3, width: 400) == 3)
        #expect(CutOnboardingLogic.dragOffset(-90, at: 1) == -90)
        #expect(CutOnboardingLogic.dragOffset(90, at: 0) == 30)
        #expect(CutOnboardingLogic.dragOffset(-90, at: 3) == -30)
    }

    @Test func progressMarksDoneCurrentAndUpcomingAndReadsAsStep() {
        let first = CutOnboardingLogic.progress(at: 0)
        #expect(first.segments == [.current, .upcoming, .upcoming, .upcoming])
        #expect(first.spoken == "Step 1 of 4")
        let third = CutOnboardingLogic.progress(at: 2)
        #expect(third.segments == [.done, .done, .current, .upcoming])
        #expect(third.spoken == "Step 3 of 4")
        let last = CutOnboardingLogic.progress(at: 3)
        #expect(last.segments == [.done, .done, .done, .current])
        #expect(last.spoken == "Step 4 of 4")
        #expect(CutOnboardingLogic.progress(at: 9).spoken == "Step 4 of 4")
        #expect(CutOnboardingLogic.progress(at: -1).spoken == "Step 1 of 4")
    }

    @Test func bodyweightShowsKilogramsAsStoredAndPoundsConverted() {
        let kg = CutOnboardingLogic.bodyweight(kg: 78.5, unit: .kg)
        #expect(kg.number == "78.5")
        #expect(kg.unitLabel == "kg")
        #expect(kg.spoken == "78.5 kilograms")
        let lb = CutOnboardingLogic.bodyweight(kg: 78.5, unit: .lb)
        #expect(lb.number == "173.1")
        #expect(lb.unitLabel == "lb")
        #expect(lb.spoken == "173.1 pounds")
        // The legacy default.
        #expect(CutOnboardingLogic.bodyweight(kg: CutOnboardingLogic.defaultBodyweightKg, unit: .kg).number == "70.0")
    }

    @Test func stepsATenthOfTheDisplayUnitAndStoresKilograms() throws {
        let up = try #require(CutOnboardingLogic.step(kg: 70, unit: .kg, up: true))
        #expect(abs(up - 70.1) < 1e-9)
        let down = try #require(CutOnboardingLogic.step(kg: 70, unit: .kg, up: false))
        #expect(abs(down - 69.9) < 1e-9)
        // In pounds: 70 kg reads 154.3 lb; one step is 154.4 lb, stored back in kilograms.
        let lbUp = try #require(CutOnboardingLogic.step(kg: 70, unit: .lb, up: true))
        #expect(abs(lbUp - 154.4 / 2.20462) < 1e-9)
        #expect(CutOnboardingLogic.bodyweight(kg: lbUp, unit: .lb).number == "154.4")
        let lbDown = try #require(CutOnboardingLogic.step(kg: 70, unit: .lb, up: false))
        #expect(CutOnboardingLogic.bodyweight(kg: lbDown, unit: .lb).number == "154.2")
    }

    @Test func steppingInOneUnitAndReadingInTheOtherNeverDrifts() throws {
        var kg = 70.0
        for _ in 0..<25 { kg = try #require(CutOnboardingLogic.step(kg: kg, unit: .lb, up: true)) }
        #expect(CutOnboardingLogic.bodyweight(kg: kg, unit: .lb).number == "156.8")
        for _ in 0..<25 { kg = try #require(CutOnboardingLogic.step(kg: kg, unit: .lb, up: false)) }
        #expect(CutOnboardingLogic.bodyweight(kg: kg, unit: .lb).number == "154.3")
        #expect(CutOnboardingLogic.bodyweight(kg: kg, unit: .kg).number == "70.0")
    }

    @Test func boundsAreThirtyToTwoHundredKilogramsInEitherUnit() {
        #expect(CutOnboardingLogic.tenthsBounds(.kg) == 300...2000)
        #expect(CutOnboardingLogic.tenthsBounds(.lb) == 662...4409)
        #expect(CutOnboardingLogic.step(kg: 30, unit: .kg, up: false) == nil)
        #expect(CutOnboardingLogic.step(kg: 200, unit: .kg, up: true) == nil)
        // 30 kg reads 66.1 lb, below the first whole tenth inside the range: down does nothing.
        #expect(CutOnboardingLogic.step(kg: 30, unit: .lb, up: false) == nil)
        #expect(CutOnboardingLogic.step(kg: 200, unit: .lb, up: true) == nil)
        let model = CutOnboardingLogic.bodyweight(kg: 30, unit: .kg)
        #expect(!model.canDecrease); #expect(model.canIncrease)
        let top = CutOnboardingLogic.bodyweight(kg: 200, unit: .lb)
        #expect(top.canDecrease); #expect(!top.canIncrease)
        // A held button never passes a bound.
        #expect(CutOnboardingLogic.step(kg: 199.5, unit: .kg, up: true, tenthsPerStep: 10) == 200)
        #expect(CutOnboardingLogic.step(kg: 30.4, unit: .kg, up: false, tenthsPerStep: 10) == 30)
    }

    @Test func aValueAboveTheRangeStepsDownATenthAsLegacyDid() throws {
        // Preferences allows up to 250 kg; the legacy page then stepped down by 0.1, not to 200.
        let down = try #require(CutOnboardingLogic.step(kg: 250, unit: .kg, up: false))
        #expect(abs(down - 249.9) < 1e-9)
        #expect(CutOnboardingLogic.step(kg: 250, unit: .kg, up: true) == nil)
    }

    @Test func heldButtonsSpeedUpAfterTenRepeats() {
        #expect(CutOnboardingLogic.tenthsPerStep(repeats: 0) == 1)
        #expect(CutOnboardingLogic.tenthsPerStep(repeats: 9) == 1)
        #expect(CutOnboardingLogic.tenthsPerStep(repeats: 10) == 10)
        #expect(CutOnboardingLogic.step(kg: 70, unit: .lb, up: true, tenthsPerStep: 10).map {
            CutOnboardingLogic.bodyweight(kg: $0, unit: .lb).number } == "155.3")
    }

    @Test func unitTitlesMatchTheSwitch() {
        #expect(WeightUnit.allCases.map(CutOnboardingLogic.unitTitle) == ["Kilograms", "Pounds"])
    }
}
