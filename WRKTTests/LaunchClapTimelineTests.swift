import Foundation
import Testing
@testable import WRKT

struct LaunchClapTimelineTests {
    @Test(arguments: [
        [0.0, 0.0], [0.14, 0.0], [0.20, -5.0], [0.28, 22.5],
        [0.34, 22.5], [0.42, 3.0], [0.50, 22.5], [0.62, 22.5],
        [1.0, 0.0], [2.0, 0.0]
    ])
    func armKeyframes(pair: [Double]) {
        #expect(abs(LaunchClapTimeline.leftAngle(at: pair[0]) - pair[1]) < 0.0001)
    }

    @Test func armsAlwaysRotateInOppositeDirections() {
        for step in 0...120 {
            let fraction = Double(step) / 120
            #expect(LaunchClapTimeline.rightAngle(at: fraction) == -LaunchClapTimeline.leftAngle(at: fraction))
        }
    }

    @Test func closingAcceleratesAndFinalOpeningOvershoots() {
        let early = LaunchClapTimeline.leftAngle(at: 0.22) + 5
        let late = 22.5 - LaunchClapTimeline.leftAngle(at: 0.26)
        #expect(early < late)
        #expect(LaunchClapTimeline.leftAngle(at: 0.9) < 0)
    }

    @Test func gateRequiresBothSessionAndAnimation() {
        #expect(!LaunchClapTimeline.canRevealShell(animationFinished: false, sessionReady: false))
        #expect(!LaunchClapTimeline.canRevealShell(animationFinished: true, sessionReady: false))
        #expect(!LaunchClapTimeline.canRevealShell(animationFinished: false, sessionReady: true))
        #expect(LaunchClapTimeline.canRevealShell(animationFinished: true, sessionReady: true))
    }

    @Test func reduceMotionKeepsBothArmsAndScaleAtRest() {
        for step in 0...120 {
            let fraction = Double(step) / 120
            #expect(LaunchClapTimeline.leftAngle(at: fraction, reduceMotion: true) == 0)
            #expect(LaunchClapTimeline.rightAngle(at: fraction, reduceMotion: true) == 0)
            #expect(LaunchClapTimeline.thump(elapsed: fraction * 1.2, reduceMotion: true) == CGSize(width: 1, height: 1))
        }
    }

    @Test func effectsClampBeforeAndAfterTheirWindow() {
        #expect(LaunchClapTimeline.progress(elapsed: 0.33, start: 0.34, duration: 0.22) == 0)
        #expect(LaunchClapTimeline.progress(elapsed: 0.45, start: 0.34, duration: 0.22) > 0.49)
        #expect(LaunchClapTimeline.progress(elapsed: 0.56, start: 0.34, duration: 0.22) == 1)
    }
}
