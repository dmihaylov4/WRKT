import Foundation
import Testing
@testable import WRKT

/// The finish screen's XP count-up: items in, timed steps out.
@MainActor
struct CutWinXPCountTests {
    private func item(_ id: String, _ source: String, _ xp: Int) -> CutWinXPItem {
        CutWinLogic.xpItems([XPLineItem(id: id, source: source, xp: xp, icon: "star", detail: nil)])[0]
    }

    private var workoutComplete: CutWinXPItem { item("w", "Workout Complete", 50) }
    private var personalRecord: CutWinXPItem { item("p", "Personal Record", 25) }

    private func summary(xp: Int, items: [XPLineItem], lucky: Bool = false, multiplier: Double = 1) -> RewardSummary {
        RewardSummary(
            xp: xp, coins: 0, levelUpTo: nil, streakOld: 1, streakNew: 1, hitStreakMilestone: false,
            unlockedAchievements: [], prCount: 0, newExerciseCount: 0,
            xpSnapshot: nil, xpLineItems: items, streakFrozen: false, streakBonusXP: 0,
            gotLuckyBonus: lucky, bonusMultiplier: multiplier, earnedPlates: [],
            rewardQueue: BarbellRewardPresentationQueue(primary: nil, compactEvents: []), challengeCompletions: [])
    }

    // MARK: Steps

    @Test func zeroXPHasNoSteps() {
        #expect(CutWinLogic.xpSteps(items: [], totalXP: 0, closingLabel: "Bonus").isEmpty)
        #expect(CutWinLogic.xpSteps(items: [workoutComplete], totalXP: 0, closingLabel: "Bonus").isEmpty)
    }

    @Test func noItemsLandTheWholeTotalUnlabelled() {
        let steps = CutWinLogic.xpSteps(items: [], totalXP: 120, closingLabel: "Bonus")
        #expect(steps.count == 1)
        #expect(steps[0].total == 120)
        #expect(steps[0].label == nil)
    }

    @Test func oneItemIsOneStep() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete], totalXP: 50, closingLabel: "Bonus")
        #expect(steps.map(\.label) == ["+50 Workout complete"])
        #expect(steps.map(\.total) == [50])
        #expect(steps[0].time == CutWinLogic.xpCountStart)
    }

    @Test func severalItemsLandInOrderOneAtATime() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete, personalRecord], totalXP: 75, closingLabel: "Bonus")
        #expect(steps.map(\.label) == ["+50 Workout complete", "+25 Personal record"])
        #expect(steps.map(\.total) == [50, 75])
        #expect(abs(steps[1].time - steps[0].time - CutWinLogic.xpCountInterval) < 0.0001)
    }

    // MARK: Final total

    @Test func aMultiplierAddsAClosingStepSoTheTotalMatches() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete, personalRecord], totalXP: 150, closingLabel: "Lucky bonus")
        #expect(steps.map(\.label) == ["+50 Workout complete", "+25 Personal record", "+75 Lucky bonus"])
        #expect(steps.last?.total == 150)
    }

    @Test func itemsThatOvershootAreHeldAtTheSummaryXP() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete, personalRecord], totalXP: 60, closingLabel: "Bonus")
        #expect(steps.map(\.total) == [50, 60])
        #expect(steps.allSatisfy { $0.total <= 60 })
    }

    @Test func theModelsLastStepAlwaysEqualsTheSummaryXP() {
        let lines = [XPLineItem(id: "w", source: "Workout Complete", xp: 50, icon: "", detail: nil),
                     XPLineItem(id: "p", source: "Personal Record", xp: 25, icon: "", detail: nil)]
        for xp in [1, 40, 75, 113, 150, 1_000] {
            let model = CutWinLogic.model(summary: summary(xp: xp, items: lines, lucky: xp == 113, multiplier: 1.5),
                                          workout: nil, unit: .kg)
            #expect(model.xpSteps.last?.total == xp, "xp \(xp)")
            #expect(CutWinLogic.xpFrame(steps: model.xpSteps, elapsed: 60, reduceMotion: false).total == xp)
        }
        let lucky = CutWinLogic.model(summary: summary(xp: 113, items: lines, lucky: true, multiplier: 1.5),
                                      workout: nil, unit: .kg)
        #expect(lucky.xpSteps.last?.label == "+38 Lucky bonus")
    }

    @Test func zeroValueItemsAreSkipped() {
        let items = CutWinLogic.xpItems([XPLineItem(id: "z", source: "Exercise Logged", xp: 0, icon: "", detail: nil),
                                         XPLineItem(id: "w", source: "Workout Complete", xp: 50, icon: "", detail: nil)])
        #expect(items.map(\.id) == ["w"])
    }

    // MARK: Frames

    @Test func theCountStartsAtZeroAndLandsStepByStep() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete, personalRecord], totalXP: 75, closingLabel: "Bonus")
        let before = CutWinLogic.xpFrame(steps: steps, elapsed: 0, reduceMotion: false)
        #expect(before == CutWinXPFrame(total: 0, landed: 0, labelsLine: nil))
        let first = CutWinLogic.xpFrame(steps: steps, elapsed: steps[0].time, reduceMotion: false)
        #expect(first == CutWinXPFrame(total: 50, landed: 1, labelsLine: "+50 Workout complete"))
        let done = CutWinLogic.xpFrame(steps: steps, elapsed: steps[1].time + 5, reduceMotion: false)
        #expect(done == CutWinXPFrame(total: 75, landed: 2, labelsLine: "+50 Workout complete, +25 Personal record"))
    }

    @Test func reduceMotionShowsTheFinalTotalAndLabelsAtOnce() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete, personalRecord], totalXP: 90, closingLabel: "Bonus")
        let frame = CutWinLogic.xpFrame(steps: steps, elapsed: 0, reduceMotion: true)
        #expect(frame.total == 90)
        #expect(frame.landed == steps.count)
        #expect(frame.labelsLine == "+50 Workout complete, +25 Personal record, +15 Bonus")
    }

    @Test func reduceMotionWithNoStepsShowsNothing() {
        #expect(CutWinLogic.xpFrame(steps: [], elapsed: 0, reduceMotion: true) == CutWinXPFrame(total: 0, landed: 0, labelsLine: nil))
    }

    // MARK: Haptics and copy

    @Test func stepsOnTopOfARewardHapticStaySilent() {
        let schedule = CutWinLogic.rewardHaptics(gotLuckyBonus: true, plateCount: 1)
        #expect(abs((schedule.luckyFollowUp ?? 0) - 0.7) < 0.0001)
        #expect(schedule.plates.count == 1 && abs(schedule.plates[0] - 1.4) < 0.0001)
        let items = [workoutComplete, personalRecord, item("n", "New Exercise", 10)]
        let steps = CutWinLogic.xpSteps(items: items, totalXP: 85, closingLabel: "Bonus", quietTimes: schedule.all)
        // 0.6 is next to the lucky follow-up at 0.7, 1.15 is clear, 1.7 is clear of the plate at 1.4.
        #expect(steps.map(\.haptic) == [false, true, true])
    }

    @Test func withoutRewardHapticsEveryStepTaps() {
        let steps = CutWinLogic.xpSteps(items: [workoutComplete, personalRecord], totalXP: 75, closingLabel: "Bonus",
                                        quietTimes: CutWinLogic.rewardHaptics(gotLuckyBonus: false, plateCount: 0).all)
        #expect(steps.allSatisfy { $0.haptic })
    }

    @Test func labelsAreSentenceCase() {
        #expect(CutWinLogic.sentenceCase("Workout Complete") == "Workout complete")
        #expect(CutWinLogic.sentenceCase("PR") == "Personal record")
        #expect(CutWinLogic.sentenceCase("streak_milestone") == "Streak milestone")
        #expect(CutWinLogic.xpText(0) == "0\u{00A0}XP")
        #expect(CutWinLogic.xpText(1_240) == "+\(CutWinLogic.grouped(1_240))\u{00A0}XP")
    }
}
