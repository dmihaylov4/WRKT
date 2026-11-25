import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import WRKT

/// The home gym mood's floor: matte rubber tiles (or a platform) whose joints are the floor lines.
@MainActor
@Suite struct RackRoomFloorTests {
    private func pixels(_ image: CGImage) -> [UInt8] {
        let n = image.width
        var bytes = [UInt8](repeating: 0, count: n * image.height * 4)
        let ctx = CGContext(data: &bytes, width: n, height: image.height, bitsPerComponent: 8, bytesPerRow: n * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: image.height))
        return bytes
    }

    /// The pixel showing floor point (x, z), for `style`'s period.
    private func pixel(_ bytes: [UInt8], _ style: RackFloorStyle, x: Float, z: Float) -> SIMD3<Float> {
        let n = RackRoomFloorArt.side
        let (size, origin) = RackRoomFloorArt.period(style)
        var u = (x - origin.x) / size.x, v = (z - origin.y) / size.y
        u -= u.rounded(.down); v -= v.rounded(.down)
        let px = min(n - 1, Int(u * Float(n))), py = min(n - 1, Int((1 - v) * Float(n)))
        let i = (py * n + px) * 4
        return SIMD3(Float(bytes[i]), Float(bytes[i + 1]), Float(bytes[i + 2])) / 255
    }

    @Test func tilesAreDarkRubberWithJointsWhereTheFloorLinesWere() throws {
        let images = try #require(RackRoomFloorArt.images(.tiles))
        #expect(images.color.width == RackRoomFloorArt.side && images.normal.width == RackRoomFloorArt.side)
        let bytes = pixels(images.color)
        // The old strips (x 0.24 + 0.48 k) and seams (z -0.15 + 0.8 k) are now joints: darker.
        for x in barbellRackRoomFloorStripXs {
            let joint = pixel(bytes, .tiles, x: x, z: 0.25), tile = pixel(bytes, .tiles, x: x + 0.1, z: 0.25)
            #expect(joint.y < tile.y * 0.75, "joint at x \(x)")
        }
        for z in barbellRackRoomFloorSeamZs {
            let joint = pixel(bytes, .tiles, x: 0.0, z: z), tile = pixel(bytes, .tiles, x: 0.0, z: z + 0.1)
            #expect(joint.y < tile.y * 0.75, "joint at z \(z)")
        }
        // Charcoal, nearly neutral rubber, and tiles that differ a little from their neighbours.
        var means: [Float] = []
        for tx in 0..<4 {
            let x = RackRoomFloorArt.jointOrigin.x + (Float(tx) + 0.5) * RackRoomFloorArt.tile.x
            var sum: Float = 0
            for k in 0..<64 { sum += pixel(bytes, .tiles, x: x + Float(k % 8) * 0.01 - 0.04, z: 0.25 + Float(k / 8) * 0.01).y }
            means.append(sum / 64)
        }
        #expect(means.allSatisfy { $0 > 0.06 && $0 < 0.2 })
        #expect((means.max()! - means.min()!) > 0.003, "tile to tile variation")
        let sample = pixel(bytes, .tiles, x: 0.0, z: 0.25)
        #expect(abs(sample.x - sample.z) < 0.04, "neutral")
    }

    @Test func platformHasOakInTheMiddleAndRubberAtTheSides() throws {
        let images = try #require(RackRoomFloorArt.images(.platform))
        let bytes = pixels(images.color)
        let oak = pixel(bytes, .platform, x: 0.05, z: 0.25), rubber = pixel(bytes, .platform, x: 1.0, z: 0.25)
        #expect(oak.x > oak.z * 1.5 && oak.x > rubber.x * 2, "warm oak centre")
        #expect(abs(rubber.x - rubber.z) < 0.05, "neutral rubber sides")
    }

    @Test func meshMapsFloorMetresOntoThePeriodAndIsBuiltOnce() throws {
        for style in RackFloorStyle.allCases {
            let mesh = try #require(RackRoomFloor.cachedMesh(style))
            #expect(RackRoomFloor.cachedMesh(style) === mesh)
            #expect(mesh.bounds.min.x <= -3 && mesh.bounds.max.x >= 3)
            #expect(mesh.bounds.min.z <= -0.12 && mesh.bounds.max.z >= 1.5)
            #expect(abs(mesh.bounds.max.y - RackRoomFloor.height) < 1e-4)
        }
        #expect(RackFloorStyle.resolve(nil) == .tiles && RackFloorStyle.resolve("platform") == .platform)
    }
}

@Suite struct RackRoomFloorTimingProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HEX_TIMING"] != nil))
    func timeFloorArt() {
        for style in RackFloorStyle.allCases {
            let start = Date()
            _ = RackRoomFloorArt.images(style)
            print("FLOORTIMING \(style) \(Date().timeIntervalSince(start))")
        }
    }
}
