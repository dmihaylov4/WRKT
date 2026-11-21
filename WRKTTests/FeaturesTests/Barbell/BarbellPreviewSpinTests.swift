import Foundation
import Testing
@testable import WRKT

/// The preview's frame loop pauses once the spin is at rest.
@Suite struct BarbellPreviewSpinTests {
    @Test func theAutoSpinSettlesWithinAboutASecond() {
        var velocity: Float = 0.35
        var frames = 0
        while !barbellPreviewSpinIsSettled(velocity: velocity) {
            velocity *= 0.92
            frames += 1
            if frames > 1_000 { break }
        }
        #expect(frames <= 70, "settles after \(frames) frames at 60 Hz")
    }

    @Test func movingSpinIsNotSettled() {
        #expect(!barbellPreviewSpinIsSettled(velocity: 0.35))
        #expect(!barbellPreviewSpinIsSettled(velocity: -0.05))
        #expect(barbellPreviewSpinIsSettled(velocity: 0))
        #expect(barbellPreviewSpinIsSettled(velocity: -0.001))
    }
}
