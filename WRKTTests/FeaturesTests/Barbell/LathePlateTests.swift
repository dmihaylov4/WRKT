import CoreGraphics
import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// The lathe plate prototype: one revolved mesh per plate, true metal, the studio environment and
/// the debug-only switch.
@MainActor
@Suite struct LathePlateTests {
    private static let liveTiers = PlateTier.all.filter { $0.id != 7 }

    private func profile(_ family: LathePlateFamily, tier: PlateTier.PlateStyle) -> LatheProfile {
        let visual = PlateVisualDesign.profile(for: tier)
        return LatheProfile.make(family: family, outerRadius: visual.outerRadius, thickness: visual.thickness,
                                 boreRadius: visual.boreRadius)
    }

    private var everyProfile: [LatheProfile] {
        [profile(.bumper, tier: .bumper), profile(.competition, tier: .competition),
         profile(.castIron, tier: .castIron), profile(.machined, tier: .polishedSteel),
         profile(.bumper, tier: .starter)]
    }

    // MARK: Mesh

    @Test func everyProfileIsAClosedLoop() {
        for profile in everyProfile {
            let segments = LatheGeometry.segments(profile)
            #expect(segments.count > 20, "\(profile.family)")
            for (k, segment) in segments.enumerated() {
                let next = segments[(k + 1) % segments.count]
                #expect(simd_distance(segment.p1, next.p0) < 1e-5, "\(profile.family) gap after piece \(k)")
            }
            #expect(segments.first?.v0 == 0)
            #expect(abs((segments.last?.v1 ?? 0) - 1) < 1e-5)
        }
    }

    @Test func straightPiecesHaveNormalsAtRightAnglesAndRoundsAreTangent() {
        for profile in everyProfile {
            for segment in LatheGeometry.segments(profile) where segment.n0 == segment.n1 {
                let d = simd_normalize(segment.p1 - segment.p0)
                #expect(abs(simd_dot(d, segment.n0)) < 1e-3, "\(profile.family)")
            }
        }
    }

    @Test func meshStaysInsideTheTriangleBudget() {
        for profile in everyProfile {
            let data = LatheMeshData.revolve(profile)
            #expect((3_000...8_000).contains(data.triangleCount), "\(profile.family): \(data.triangleCount) triangles")
            #expect(data.positions.count < 20_000)
            #expect(data.triangleSlots.count == data.triangleCount)
            #expect(Set(data.triangleSlots) == [LatheSlot.body, LatheSlot.hub, LatheSlot.face], "\(profile.family) uses three slots")
            #expect(data.indices.allSatisfy { Int($0) < data.positions.count })
        }
    }

    @Test func normalsAreUnitLengthAndFaceOutward() {
        for profile in everyProfile {
            let data = LatheMeshData.revolve(profile)
            #expect(data.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
            #expect(data.tangents.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
            #expect(data.bitangents.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
            // Counter-clockwise winding seen from outside: each triangle's geometric normal agrees
            // with its vertex normals (the materials cull back faces).
            var disagreeing = 0
            for t in 0..<data.triangleCount {
                let a = data.positions[Int(data.indices[t * 3])]
                let b = data.positions[Int(data.indices[t * 3 + 1])]
                let c = data.positions[Int(data.indices[t * 3 + 2])]
                let geometric = simd_cross(b - a, c - a)
                guard simd_length(geometric) > 1e-12 else { continue }
                if simd_dot(geometric, data.normals[Int(data.indices[t * 3])]) <= 0 { disagreeing += 1 }
            }
            #expect(disagreeing == 0, "\(profile.family)")
        }
    }

    @Test func meshKeepsThePlateDimensions() {
        for profile in everyProfile {
            let data = LatheMeshData.revolve(profile)
            let maxRadius = data.positions.map { simd_length(SIMD2($0.x, $0.z)) }.max() ?? 0
            let minRadius = data.positions.map { simd_length(SIMD2($0.x, $0.z)) }.min() ?? 0
            let rimHalf = data.positions.filter { simd_length(SIMD2($0.x, $0.z)) > profile.outerRadius * 0.9 }.map { abs($0.y) }.max() ?? 0
            #expect(abs(maxRadius - profile.outerRadius) < 1e-4)
            #expect(abs(minRadius - profile.boreRadius) < 1e-4)
            // The rim is exactly the legacy thickness; only the hub stands proud, by at most 3 mm.
            #expect(abs(rimHalf - profile.thickness / 2) < 1e-4)
            #expect((data.positions.map { abs($0.y) }.max() ?? 0) <= profile.thickness / 2 + 0.0031)
        }
    }

    @Test func identicalPlatesShareOneMesh() {
        let gold = try! #require(PlateTier.all.first { $0.id == 6 })
        let chrome = try! #require(PlateTier.all.first { $0.id == 5 })
        let red = try! #require(PlateTier.all.first { $0.id == 14 })
        let lime = try! #require(PlateTier.all.first { $0.id == 22 })
        let castIron = try! #require(PlateTier.all.first { $0.id == 1 })
        #expect(cachedLatheMesh(for: latheProfile(for: gold)) === cachedLatheMesh(for: latheProfile(for: chrome)))
        #expect(cachedLatheMesh(for: latheProfile(for: red)) === cachedLatheMesh(for: latheProfile(for: lime)))
        #expect(cachedLatheMesh(for: latheProfile(for: red)) !== cachedLatheMesh(for: latheProfile(for: castIron)))
    }

    // MARK: Entity

    @Test func lathePlateIsOneModelWithThreeSlotsAndTheLegacyCollision() {
        for tier in Self.liveTiers {
            let lathe = makePlateEntity(tierID: tier.id, weightKg: 20, engravingText: "Bench 100", plateStyle: .lathe)
            let legacy = makePlateEntity(tierID: tier.id, weightKg: 20, engravingText: "Bench 100")
            #expect(lathe.children.isEmpty, "tier \(tier.id) has no child parts")
            #expect(lathe.model?.materials.count == LatheSlot.count, "tier \(tier.id)")
            #expect(lathe.orientation == legacy.orientation)
            let latheShapes = lathe.components[CollisionComponent.self]?.shapes
            let legacyShapes = legacy.components[CollisionComponent.self]?.shapes
            #expect(latheShapes?.count == legacyShapes?.count)
            #expect(latheShapes?.first?.bounds == legacyShapes?.first?.bounds, "tier \(tier.id) collides like before")
            #expect(lathe.components[PhysicsBodyComponent.self]?.massProperties.mass
                    == legacy.components[PhysicsBodyComponent.self]?.massProperties.mass)
            #expect(lathe.components[TierIDComponent.self]?.tierID == tier.id)
        }
    }

    @Test func metalPlatesAreTrueMetalAndColouredPlatesAreNot() {
        for tier in Self.liveTiers {
            let body = LatheFinish.body(for: tier)
            switch tier.style {
            case .bumper, .starter:
                #expect(body.metallic == 0 && body.roughness >= 0.6, "tier \(tier.id) rubber")
                #expect(LatheFinish.hub(for: tier).metallic == 1, "tier \(tier.id) steel insert")
            case .competition where tier.metallic < 0.5:
                #expect(body.metallic == 0 && body.clearcoat > 0, "tier \(tier.id) powder coat")
            case .castIron:
                #expect(body.metallic == 1 && (0.5...0.6).contains(body.roughness) && body.surface == .cast)
            default:
                #expect(body.metallic == 1 && body.clearcoat == 0, "tier \(tier.id) metal without lacquer")
                #expect(body.roughness <= 0.45, "tier \(tier.id)")
            }
        }
        #expect(LatheFinish.body(for: PlateTier.all.first { $0.id == 5 }!).roughness <= 0.15, "chrome is polished")
    }

    @Test func defaultPlateBuildStaysLegacy() {
        // Previews, the spinning plate and thumbnails never ask for a style and keep their parts.
        let plate = makePlateEntity(tierID: 22, weightKg: 20)
        #expect(!plate.children.isEmpty)
    }

    @Test func prepareBuildsTheFaceSoTheSceneNeedsNoDrawing() async {
        let request = LathePlateRequest(tierID: 15, weightKg: 20, engravingText: "", projection: BarbellPlateRenderProjection())
        await prepareLathePlates([request])
        let tier = PlateTier.all.first { $0.id == 15 }!
        let spec = latheFaceSpec(tier: tier, weightKg: 20, engravingText: "", projection: BarbellPlateRenderProjection(), showEngravings: true)
        #expect(spec.weightLabel == "20 KG")
        #expect(LatheFaceArt.images(for: spec) != nil)
    }

    // MARK: Switch

    @Test func releaseAlwaysResolvesToLegacy() {
        #expect(RackPlateStyle.resolve(isDebugBuild: false, environment: [:]) == .legacy)
        #expect(RackPlateStyle.resolve(isDebugBuild: false, environment: [RackPlateStyle.overrideKey: "lathe"]) == .legacy)
    }

    @Test func debugDefaultsToLatheAndHonoursTheOverride() {
        #expect(RackPlateStyle.resolve(isDebugBuild: true, environment: [:]) == .lathe)
        #expect(RackPlateStyle.resolve(isDebugBuild: true, environment: [RackPlateStyle.overrideKey: "legacy"]) == .legacy)
        #expect(RackPlateStyle.resolve(isDebugBuild: true, environment: [RackPlateStyle.overrideKey: "nonsense"]) == .lathe)
    }

    // MARK: Studio environment

    @Test func studioHDRIShipsAndDecodes() throws {
        let url = try #require(Bundle.main.url(forResource: RackStudioEnvironment.resourceName,
                                               withExtension: RackStudioEnvironment.resourceExtension))
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(size < 2_000_000)
        let radiance = try #require(RackStudioEnvironment.decode(try Data(contentsOf: url)))
        #expect(radiance.width == 1024 && radiance.height == 512)
        let luminance = stride(from: 0, to: radiance.rgb.count, by: 3).map { radiance.rgb[$0] * 0.2126 + radiance.rgb[$0 + 1] * 0.7152 + radiance.rgb[$0 + 2] * 0.0722 }
        // Soft boxes far brighter than the dark surround.
        #expect((luminance.max() ?? 0) > 50)
        #expect(luminance.sorted()[luminance.count / 4] < 0.3)
    }

    @Test func studioLightIsBalancedToNeutral() throws {
        let url = try #require(Bundle.main.url(forResource: RackStudioEnvironment.resourceName,
                                               withExtension: RackStudioEnvironment.resourceExtension))
        let radiance = try #require(RackStudioEnvironment.decode(try Data(contentsOf: url)))
        let gains = RackStudioEnvironment.whiteBalance(radiance)
        // A gentle correction, not a recolouring.
        #expect(gains.min() > 0.8 && gains.max() < 1.25)
    }

    @Test func studioEnvironmentLoadsAsARealityKitEnvironment() async {
        let environment = await sharedRackStudioEnvironmentResource()
        #expect(environment != nil)
    }

    @Test func malformedHDRIsRejected() {
        #expect(RackStudioEnvironment.decode(Data("not an image".utf8)) == nil)
        #expect(RackStudioEnvironment.decode(Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 4 +X 4\n".utf8)) == nil)
    }
}
