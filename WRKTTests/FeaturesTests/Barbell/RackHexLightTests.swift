import CoreGraphics
import Foundation
import ImageIO
import RealityKit
import simd
import Testing
import UniformTypeIdentifiers
@testable import WRKT

/// The honeycomb LED fixture: its grid, its single mesh and its painted reflection.
@MainActor
@Suite struct RackHexLightTests {
    @Test func gridSharesSidesAndIsSymmetric() {
        let grid = RackHexGrid(columns: 3, rows: 1, radius: 1)
        // Three cells in a zigzag: 18 sides, two pairs shared.
        #expect(grid.edges.count == 16)
        let single = RackHexGrid(columns: 1, rows: 1, radius: 1)
        #expect(single.edges.count == 6)
        // Every tube's mirror about x 0 is a tube too: the sleeves see mirror images.
        let wide = RackHexGrid(columns: 9, rows: 2, radius: 0.075)
        let edges = wide.edges
        func same(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { simd_distance(a, b) < 1e-4 }
        for e in edges {
            let a = SIMD2(-e.0.x, e.0.y), b = SIMD2(-e.1.x, e.1.y)
            #expect(edges.contains { (same($0.0, a) && same($0.1, b)) || (same($0.0, b) && same($0.1, a)) })
        }
    }

    @Test func distanceIsZeroOnATubeAndLargestAtACentre() {
        let grid = RackHexGrid(columns: 1, rows: 1, radius: 1)
        let centres = grid.centres
        #expect(abs(grid.distanceToTubes(SIMD2(0, grid.apothem), centres: centres)) < 1e-5)
        #expect(abs(grid.distanceToTubes(.zero, centres: centres) - grid.apothem) < 1e-5)
    }

    @Test(arguments: RackHexPlacement.allCases)
    func everyPlacementIsOneMeshWithOneMaterial(_ placement: RackHexPlacement) throws {
        let mood = RackRoomMood.preset(placement)
        let entity = try #require(RackHexLight.makeEntity(mood.fixtures))
        let model = try #require(entity.components[ModelComponent.self])
        #expect(model.materials.count == 1)
        #expect(model.mesh.contents.models.count == 1)
        let geometry = RackHexLight.tubeGeometry(mood.fixtures)
        let tubes = mood.fixtures.map(\.grid.edges.count).reduce(0, +)
        #expect(geometry.positions.count == tubes * RackHexLight.tubeSides * 2)
        // A cheap mesh: a few thousand vertices at most.
        #expect(geometry.positions.count < 4_000)
        // Built once: the second call returns the cached mesh.
        #expect(RackHexLight.cachedMesh(mood.fixtures) === RackHexLight.cachedMesh(mood.fixtures))
    }

    @Test func wallPanelHangsOnTheWallAboveTheSign() {
        let mood = RackRoomMood.preset(.wall)
        let panel = try! #require(mood.fixtures.first)
        #expect(!panel.onCeiling)
        // In front of the plate zone panel (face at z -0.103), behind the bar (z 0.12).
        #expect(panel.centre.z - panel.tubeRadius > -0.103)
        // Clear of the sign's letters (about 0.13 high around its centre).
        #expect(panel.centre.y - panel.grid.halfExtent.y > RackRoomMood.signPosition.y + 0.10)
    }

    @Test(arguments: RackHexPlacement.allCases)
    func reflectionPaintsTubesAheadOrOverheadAndStaysSymmetric(_ placement: RackHexPlacement) {
        let w = 256, h = 128
        var pixels = [Float](repeating: 1, count: w * h * 4)
        RackHexReflection.paint(placement, into: &pixels, width: w, height: h)
        var brightest: Float = 0, darkest: Float = 1
        var asymmetry: Float = 0
        for y in 0..<h {
            for x in 0..<w {
                let v = pixels[(y * w + x) * 4 + 1]
                brightest = max(brightest, v); darkest = min(darkest, v)
                // Columns run right to left; the mirror of column x about the view axis is w - 1 - x.
                asymmetry = max(asymmetry, abs(v - pixels[(y * w + (w - 1 - x)) * 4 + 1]))
            }
        }
        #expect(brightest > 10, "tubes painted")
        #expect(darkest < 0.5, "a dark surround behind them")
        #expect(asymmetry < 0.01)
        // Nothing painted below the horizon: the fixtures hang above the bar.
        #expect((h / 2 * w..<h * w).allSatisfy { pixels[$0 * 4 + 1] == 1 })
        // The tubes sit where a ray from the bar's centre meets a fixture: straight up for the
        // ceiling, high and ahead for the wall panel.
        let zenithBand = (0..<(h / 6)).flatMap { y in (0..<w).map { pixels[(y * w + $0) * 4 + 1] } }
        #expect(zenithBand.contains { $0 > 10 })
    }

    /// Writes the painted studio panorama, tone mapped, for a look. TEST_RUNNER_VOLIA_HEX_PANORAMA=<dir>.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HEX_PANORAMA"] != nil))
    func writePaintedPanorama() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_HEX_PANORAMA"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = try #require(Bundle.main.url(forResource: RackStudioEnvironment.resourceName,
                                               withExtension: RackStudioEnvironment.resourceExtension))
        let radiance = try #require(RackStudioEnvironment.decode(Data(contentsOf: url)))
        for placement in [nil] + RackHexPlacement.allCases {
            let image = try #require(RackStudioEnvironment.panorama(radiance, hex: placement))
            // Reinhard tone map to 8 bit for viewing.
            let w = image.width, h = image.height
            var floats = [Float](repeating: 0, count: w * h * 4)
            let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            let ctx = CGContext(data: &floats, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            var bytes = [UInt8](repeating: 255, count: w * h * 4)
            for i in 0..<(w * h) {
                for c in 0..<3 {
                    let v = floats[i * 4 + c]
                    bytes[i * 4 + c] = UInt8(max(0, min(255, pow(v / (1 + v), 1 / 2.2) * 255)))
                }
            }
            let out = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let png = dir.appendingPathComponent("panorama-\(placement?.rawValue ?? "none").png") as CFURL
            let dest = try #require(CGImageDestinationCreateWithURL(png, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, out.makeImage()!, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
    }
}
