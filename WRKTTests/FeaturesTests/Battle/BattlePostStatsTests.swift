import Testing
@testable import WRKT

@Suite("BattleType custom icon names")
struct BattleTypeIconTests {

    @Test("volume maps to battle-volume-icon")
    func volumeIcon() {
        #expect(BattleType.volume.customIconName == "battle-volume-icon")
    }

    @Test("consistency maps to battle-consistency-icon")
    func consistencyIcon() {
        #expect(BattleType.consistency.customIconName == "battle-consistency-icon")
    }

    @Test("workoutCount maps to battle-workout-count-icon")
    func workoutCountIcon() {
        #expect(BattleType.workoutCount.customIconName == "battle-workout-count-icon")
    }

    @Test("pr maps to battle-flags-icon")
    func prIcon() {
        #expect(BattleType.pr.customIconName == "battle-flags-icon")
    }

    @Test("exercise maps to battle-opponent-icon")
    func exerciseIcon() {
        #expect(BattleType.exercise.customIconName == "battle-opponent-icon")
    }

    @Test("runningDistance maps to battle-flags-icon")
    func runningDistanceIcon() {
        #expect(BattleType.runningDistance.customIconName == "battle-flags-icon")
    }
}
