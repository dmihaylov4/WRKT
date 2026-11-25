import CoreGraphics
import Foundation
import ImageIO
import RealityKit
import simd
import Testing
import UniformTypeIdentifiers
@testable import WRKT

/// The honeycomb LED fixture: its grid, its tube and glow meshes and its painted reflection.
@MainActor
@Suite struct RackHexLightTests {
    @Test func gridSharesSidesAndIsSymmetric() {
        let grid = RackHexGrid(columns: 3, rows: 1, radius: 1)
        // Three cells in a zigzag: 18 sides, two pairs shared.
        #expect(grid.edges.count == 16)
        #expect(RackHexGrid(columns: 1, rows: 1, radius: 1).edges.count == 6)
        // Every tube's mirror about x 0 is a tube too: the sleeves see mirror images.
        for placement in RackHexPlacement.allCases {
            for fixture in RackHexFixture.fixtures(for: placement) {
                let edges = fixture.grid.edges
                func same(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { simd_distance(a, b) < 1e-4 }
                for e in edges {
                    let a = SIMD2(-e.0.x, e.0.y), b = SIMD2(-e.1.x, e.1.y)
                    #expect(edges.contains { (same($0.0, a) && same($0.1, b)) || (same($0.0, b) && same($0.1, a)) }, "\(placement)")
                }
            }
        }
    }

    @Test func distanceIsZeroOnATubeAndLargestAtACentre() {
        let grid = RackHexGrid(radius: 1, covering: (SIMD2(-0.1, -0.1), SIMD2(0.1, 0.1)))
        #expect(grid.cells == [SIMD2(0, 0)])
        let members = RackHexGrid.Membership(grid.cells)
        #expect(abs(grid.distanceToTubes(SIMD2(0, grid.apothem), members: members)) < 1e-5)
        #expect(abs(grid.distanceToTubes(.zero, members: members) - grid.apothem) < 1e-5)
        // Every lattice centre rounds back to its own cell.
        let big = RackHexFixture.fixtures(for: .wall)[0].grid
        for (cell, centre) in zip(big.cells, big.centres) { #expect(big.nearestCell(centre) == cell) }
    }

    @Test func bigWallCoversTheWallWithTheSignInTheMiddleCell() throws {
        let fixture = try #require(RackHexFixture.fixtures(for: .wall).first)
        // Cells three to four times the earlier 0.15 m panel cells, tubes 3 to 4 cm thick.
        #expect(fixture.grid.radius * 2 >= 0.45 && fixture.grid.radius * 2 <= 0.75)
        #expect(fixture.tubeRadius * 2 >= 0.03 && fixture.tubeRadius * 2 <= 0.04)
        #expect(fixture.glowHalfWidth > fixture.tubeRadius * 2)
        // Past both sleeves (plates reach x 0.9) and from behind the stands to above the frame.
        let centres = fixture.grid.centres.map { $0 + SIMD2(fixture.centre.x, fixture.centre.y) }
        #expect(centres.map(\.x).max()! > 1.0 && centres.map(\.x).min()! < -1.0)
        #expect(centres.map(\.y).min()! < 0.6 && centres.map(\.y).max()! > 1.9)
        // A cell centred on the sign, wide enough for the 0.5 m lettering.
        #expect(centres.contains { simd_distance($0, SIMD2(RackRoomMood.signPosition.x, RackRoomMood.signPosition.y)) < 1e-4 })
        #expect(fixture.grid.apothem * 2 > 0.5)
        // In front of the plate zone panel (face at z -0.103), behind the bar.
        #expect(fixture.centre.z - fixture.tubeRadius > -0.103 && fixture.centre.z < 0.0)
        // The high variant keeps every cell above the plates (top at 0.83).
        let high = try #require(RackHexFixture.fixtures(for: .wallHigh).first)
        #expect(high.grid.centres.allSatisfy { $0.y + high.centre.y - high.grid.apothem > 0.6 })
    }

    @Test(arguments: RackHexPlacement.allCases)
    func tubesAreOneMeshAndGlowIsOneMesh(_ placement: RackHexPlacement) throws {
        let mood = RackRoomMood.preset(placement)
        let entities = RackHexLight.makeEntities(mood.fixtures)
        let tubes = try #require(entities.first { $0.name == "moodHexLight" })
        #expect(tubes.model?.materials.count == 1)
        #expect(tubes.model?.mesh.contents.models.count == 1)
        let glows = mood.fixtures.contains { $0.glowHalfWidth > 0 }
        #expect(entities.count == (glows ? 2 : 1))
        if let glow = entities.first(where: { $0.name == "moodHexGlow" }) {
            #expect(glow.model?.materials.count == 1)
            #expect(glow.model?.mesh.contents.models.count == 1)
        }
        let tubeGeometry = RackHexLight.tubeGeometry(mood.fixtures)
        let tubeCount = mood.fixtures.map(\.grid.edges.count).reduce(0, +)
        #expect(tubeGeometry.positions.count == tubeCount * RackHexLight.tubeSides * 2)
        #expect(tubeGeometry.triangles == tubeCount * RackHexLight.tubeSides * 2)
        #expect(tubeGeometry.triangles < 2_000, "a cheap mesh")
        if glows { #expect(RackHexLight.glowGeometry(mood.fixtures).triangles == tubeCount * 2) }
        // Built once: the second call returns the cached mesh.
        #expect(RackHexLight.cachedMesh(mood.fixtures, kind: .tubes) === RackHexLight.cachedMesh(mood.fixtures, kind: .tubes))
    }

    @Test func glowFadesOutAcrossAndAtTheEnds() throws {
        let image = try #require(RackHexLight.glowImage(along: 0.2, width: 64, height: 16))
        let data = try #require(image.dataProvider?.data as Data?)
        let bytes = [UInt8](data)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * 64 + x) * 4 + 3] }
        #expect(alpha(32, 0) < 10 && alpha(32, 15) < 10, "edges fade to nothing")
        #expect(alpha(0, 8) < 10 && alpha(63, 8) < 10, "ends fade to nothing")
        #expect(alpha(32, 8) > 100, "bright at the tube")
    }

    @Test(arguments: RackHexPlacement.allCases)
    func reflectionPaintsTheGridAndStaysSymmetric(_ placement: RackHexPlacement) {
        let w = 256, h = 128
        var pixels = [Float](repeating: 1, count: w * h * 4)
        RackHexReflection.paint(placement, into: &pixels, width: w, height: h)
        var brightest: Float = 0, darkest: Float = 1, asymmetry: Float = 0
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
        // Nothing painted straight behind the viewer at the horizon.
        #expect(pixels[(h / 2 * w) * 4 + 1] == 1)
        if placement == .wall {
            // The wall grid is ahead: the middle column (ahead) at the horizon is painted.
            let ahead = (0..<h).map { pixels[($0 * w + w / 2) * 4 + 1] }
            #expect(ahead.contains { $0 > 10 })
        }
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

@MainActor
@Suite struct RackHexPaintTimingProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_HEX_TIMING"] != nil))
    func timePaint() {
        for placement in RackHexPlacement.allCases {
            var pixels = [Float](repeating: 1, count: 1024 * 512 * 4)
            let start = Date()
            RackHexReflection.paint(placement, into: &pixels, width: 1024, height: 512)
            let fixtures = RackHexFixture.fixtures(for: placement)
            print("HEXTIMING \(placement) \(Date().timeIntervalSince(start)) cells \(fixtures.map(\.grid.cells.count)) tubes \(fixtures.map(\.grid.edges.count)) tubeTris \(RackHexLight.tubeGeometry(fixtures).triangles) glowTris \(RackHexLight.glowGeometry(fixtures).triangles)")
        }
    }
}
