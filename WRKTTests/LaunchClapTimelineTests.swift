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

    @Test func clockPausesThroughHitchesInsteadOfSkipping() {
        let clock = LaunchClapClock()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(clock.advance(to: start) == 0)
        // A 1.5 second main-thread stall must not carry the animation past the claps.
        let afterStall = clock.advance(to: start.addingTimeInterval(1.5))
        #expect(abs(afterStall - LaunchClapClock.maxStep) < 0.0001)
        #expect(afterStall < LaunchClapTimeline.impacts[0])
    }

    @Test func clockFollowsRealTimeAtNormalFrameRates() {
        let clock = LaunchClapClock()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var elapsed = clock.advance(to: start)
        for frame in 1...60 {
            elapsed = clock.advance(to: start.addingTimeInterval(Double(frame) / 60))
        }
        #expect(abs(elapsed - 1.0) < 0.0001)
        // The same date twice, as SwiftUI may re-evaluate a frame, adds nothing.
        #expect(clock.advance(to: start.addingTimeInterval(1)) == elapsed)
    }

    @Test func sampledArmCurveCoversTheWholeClap() {
        let clap = LaunchClapTimeline.clapDuration
        let samples = LaunchClapTimeline.samples(from: LaunchClapTimeline.skippedLeadIn, to: clap) {
            LaunchClapTimeline.leftAngle(at: $0 / clap)
        }
        // Starts and ends at rest, reaches the closed angle, and keeps the wind-up and overshoot.
        #expect(samples.first == 0)
        #expect(samples.last == 0)
        #expect(abs((samples.max() ?? 0) - 22.5) < 0.0001)
        #expect((samples.min() ?? 0) < -4)
        // At least 120 samples a second, so straight lines between them are not visible.
        #expect(Double(samples.count - 1) >= (clap - LaunchClapTimeline.skippedLeadIn) * 120)
    }

    @Test func samplesIncludeBothEnds() {
        let samples = LaunchClapTimeline.samples(from: 1, to: 2, rate: 4) { $0 }
        #expect(samples == [1, 1.25, 1.5, 1.75, 2])
    }

    @Test func clockStartsWhereTheArmsBeginToMove() {
        let leadIn = LaunchClapTimeline.skippedLeadIn
        #expect(LaunchClapTimeline.leftAngle(at: leadIn / LaunchClapTimeline.clapDuration) == 0)
        #expect(LaunchClapTimeline.leftAngle(at: (leadIn + 0.02) / LaunchClapTimeline.clapDuration) < 0)
        let clock = LaunchClapClock(startingAt: leadIn)
        #expect(clock.advance(to: Date(timeIntervalSinceReferenceDate: 1_000)) == leadIn)
    }
}
