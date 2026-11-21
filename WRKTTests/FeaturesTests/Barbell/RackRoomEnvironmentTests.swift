import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import WRKT

/// The rack room's procedural light probe: a dim gym with overhead strip lamps along the bar.
@Suite struct RackRoomEnvironmentTests {
    private func direction(pitch: Float, along: Float = 0) -> SIMD3<Float> {
        let p = pitch * .pi / 180, a = along * .pi / 180
        return simd_normalize(SIMD3(sin(a), cos(p) * cos(a), sin(p) * cos(a)))
    }

    @Test func everyStripIsFarBrighterThanTheRoom() {
        let wall = RackRoomEnvironment.radiance(SIMD3(0, 0, -1))
        for strip in RackRoomEnvironment.strips {
            let lamp = RackRoomEnvironment.radiance(direction(pitch: strip.pitch))
            #expect(lamp > wall * 20, "strip at \(strip.pitch) degrees reads as a lamp")
        }
    }

    @Test func stripsRunAlongTheBarAndEnd() {
        let front = RackRoomEnvironment.strips[0]
        let centre = RackRoomEnvironment.radiance(direction(pitch: front.pitch))
        #expect(RackRoomEnvironment.radiance(direction(pitch: front.pitch, along: 40)) > centre * 0.9)
        #expect(RackRoomEnvironment.radiance(direction(pitch: front.pitch, along: 80)) < 0.5)
    }

    @Test func roomStaysDimAndTheFloorPoolsUnderTheLamps() {
        let backWall = RackRoomEnvironment.radiance(SIMD3(0, 0, -1))
        let floorBelow = RackRoomEnvironment.radiance(SIMD3(0, -1, 0))
        let floorFar = RackRoomEnvironment.radiance(simd_normalize(SIMD3(0, -0.15, -1)))
        #expect(backWall < 0.1)
        #expect(floorBelow > floorFar)
        #expect(floorBelow < 0.2)
    }

    @Test func softGlowBehindTheViewerLightsFlatFaces() {
        let behind = RackRoomEnvironment.radiance(simd_normalize(SIMD3(0, 0.27, 1)))
        let ahead = RackRoomEnvironment.radiance(simd_normalize(SIMD3(0, 0.27, -1)))
        #expect(behind > ahead * 4)
        #expect(behind < 1)
    }

    @Test func panoramaIsTwoToOneLinearFloat() throws {
        let image = try #require(RackRoomEnvironment.panorama())
        #expect(image.width == RackRoomEnvironment.width)
        #expect(image.height == RackRoomEnvironment.width / 2)
        #expect(image.bitsPerComponent == 32)
    }

    @MainActor @Test func environmentIsBuiltOnceAndShared() async {
        async let first = sharedRackRoomEnvironmentResource()
        async let second = sharedRackRoomEnvironmentResource()
        let a = await first, b = await second
        #expect(a != nil, "the procedural environment loads on the simulator")
        #expect(a === b)
        #expect(await sharedRackRoomEnvironmentResource() === a)
    }
}

/// The debug tuning hook's parser: "name=value,name=value".
@Suite struct RackRoomLightingOverrideTests {
    @Test func parsesPairsAndSkipsMalformedOnes() {
        let values = rackRoomLightingOverrides("ibl=1.5, key = 30000,bad,rim=x,=2")
        #expect(values == ["ibl": 1.5, "key": 30_000])
        #expect(rackRoomLightingOverrides(nil).isEmpty)
    }

    @Test func withoutOverridesTheSceneUsesThePreset() {
        // The test process sets no VOLIA_RACK_LIGHT.
        #expect(RackRoomLightingPreset.current.imageBasedLightIntensityExponent
                == RackRoomLightingPreset.readability.imageBasedLightIntensityExponent)
    }
}
