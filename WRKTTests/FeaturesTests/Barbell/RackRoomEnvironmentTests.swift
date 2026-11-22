import CoreGraphics
import Foundation
import RealityKit
import Testing
import UIKit
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
        #expect(behind < 3, "a soft box, not a lamp")
    }

    /// The ceiling panel over the back wall lights the tops of plates. The back wall faces the
    /// viewer (+z), so it only receives light from directions with z >= 0: the panel must add
    /// nothing there, only above and ahead of the viewer.
    @Test func ceilingPanelSitsOnlyWhereTheBackWallCannotReceiveIt() {
        let noPanel = RackRoomEnvironment.Strip(pitch: 0, halfWidth: 0, halfLength: 0, radiance: 0)
        for elevation in stride(from: Float(0), through: 90, by: 10) {
            for azimuth in stride(from: Float(-90), through: 90, by: 15) {
                let e = elevation * .pi / 180, a = azimuth * .pi / 180
                let d = SIMD3<Float>(sin(a) * cos(e), sin(e), cos(a) * cos(e))
                guard d.z >= 0.001 else { continue }
                #expect(abs(RackRoomEnvironment.radiance(d) - RackRoomEnvironment.radiance(d, panel: noPanel)) < 0.0001,
                        "no panel light at elevation \(elevation), azimuth \(azimuth)")
            }
        }
        let overBackWall = simd_normalize(SIMD3<Float>(0, 1, -1))
        #expect(RackRoomEnvironment.radiance(overBackWall) > 2, "the panel is bright where plate tops look")
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

/// Grounding shadows: on the scene's plate bodies only, never on previews, spinning plates or snapshots.
@MainActor
@Suite struct PlateGroundingShadowTests {
    @Test func scenePlatesCastFromTheirBodyOnly() {
        for options in [PlateEntityBuildOptions.interactive(role: .bar), .interactive(role: .floor), .barMirror()] {
            let plate = makePlateEntity(tierID: 22, weightKg: 20, options: options)
            #expect(plate.components[GroundingShadowComponent.self]?.castsShadow == true)
            #expect(plate.components[ModelComponent.self] != nil, "the root is the body ring mesh")
            #expect(plate.children.allSatisfy { $0.components[GroundingShadowComponent.self] == nil },
                    "one caster per plate, not one per part")
        }
    }

    @Test func visualOnlyPlatesCastNone() {
        let plate = makePlateEntity(tierID: 22, weightKg: 20, options: .visualOnly())
        #expect(plate.components[GroundingShadowComponent.self] == nil)
    }

    @Test func theKeySpotShadowIsOffByDefault() {
        #expect(RackRoomLightingPreset.readability.keyCastsShadow == false)
    }
}

/// Thin floor geometry shimmered: the lines are fewer and wide enough to cover several pixels.
@Suite struct RackRoomFloorLineTests {
    @Test func linesAreFewWideAndInsideTheRails() {
        #expect(barbellRackRoomFloorLineWidth >= 0.02)
        #expect(barbellRackRoomFloorStripXs.count == 4)
        #expect(barbellRackRoomFloorSeamZs.count == 4)
        #expect(barbellRackRoomFloorStripXs.allSatisfy { abs($0) < 0.82 }, "inside the side rails")
        #expect(barbellRackRoomFloorStripXs.map { -$0 }.sorted() == barbellRackRoomFloorStripXs, "symmetric about the bar")
    }
}

/// Iron is not lacquered, rubber is matte, polished metal keeps only a light coat.
@Suite struct PlateSurfaceFinishTests {
    @Test func ironCarriesAlmostNoClearcoatAnywhere() {
        for tier in PlateTier.all where tier.style == .rawIron || tier.style == .castIron {
            #expect(PlateDisplaySurface.clearcoat(for: tier) <= 0.15, "\(tier.name) face")
            #expect(PlateSidewallSurface.sidewall(for: tier).clearcoat <= 0.15, "\(tier.name) side")
            #expect(PlateSidewallSurface.lip(for: tier).clearcoat <= 0.15, "\(tier.name) lip")
        }
    }

    @Test func rawIronIsDullNotPolished() throws {
        let rusty = try #require(PlateTier.all.first { $0.style == .rawIron })
        #expect(PlateDisplaySurface.roughness(for: rusty) >= 0.40)
        #expect(PlateSidewallSurface.sidewall(for: rusty).roughness >= 0.40)
        #expect(PlateSidewallSurface.lip(for: rusty).roughness >= 0.40)
    }

    @Test func rubberBumpersReadMatte() {
        for tier in PlateTier.all where tier.style == .bumper {
            #expect(PlateDisplaySurface.clearcoat(for: tier) <= 0.15, "\(tier.name) face")
            #expect(PlateSidewallSurface.sidewall(for: tier).clearcoat <= 0.15, "\(tier.name) side")
            #expect(PlateSidewallSurface.lip(for: tier).clearcoat <= 0.15, "\(tier.name) lip")
        }
    }

    @Test func polishedMetalsKeepALightCoatOnly() {
        for tier in PlateTier.all where PlateDisplaySurface.usesReadableMetal(tier) && tier.style != .rawIron {
            #expect((0.2...0.4).contains(PlateDisplaySurface.clearcoat(for: tier)), "\(tier.name)")
        }
    }

    @MainActor @Test func sceneBodyMaterialFollowsThePolicy() throws {
        let castIron = try #require(PlateTier.all.first { $0.style == .castIron })
        let material = buildMaterial(forTierID: castIron.id, textures: nil)
        #expect(material.clearcoat.scale <= 0.15)
    }
}

/// Light rooms get a gentler key so the floor and wall do not blow out; dark rooms keep it all.
@Suite struct RackRoomKeyScaleTests {
    @Test func darkRoomsKeepTheFullKey() {
        for id in ["dark_gym", "neon_garage", "iron_basement", "brick_powerhouse"] {
            let theme = RoomThemePreset.preset(for: id)
            #expect(RackRoomLightingPreset.keyScale(
                brightestSurfaceLuminance: max(theme.floorLuminance, theme.backdropLuminance)) == 1, "\(id)")
        }
    }

    @Test func lightRoomsDimTheKeyButNotToDarkness() {
        for id in ["daylight_studio", "competition_platform", "concrete_room"] {
            let theme = RoomThemePreset.preset(for: id)
            let scale = RackRoomLightingPreset.keyScale(
                brightestSurfaceLuminance: max(theme.floorLuminance, theme.backdropLuminance))
            #expect(scale < 1, "\(id)")
            #expect(scale > 0.4, "\(id)")
        }
    }
}


/// Cast iron in the rack room: plain iron grey instead of the dark colour map, on the body and on
/// the panel and band that used to stay black. Everything else keeps the shared material.
@MainActor
@Suite struct RackRoomIronSurfaceTests {
    /// The tint's mean of red, green and blue (works for grey and colour tints alike).
    private func tint(_ material: PhysicallyBasedMaterial) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ok = material.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(ok)
        return (r + g + b) / 3
    }

    @Test func rackRoomCastIronIsIronGreyAndKeepsItsMetalMaps() {
        let textures = loadPlateTextures(forTierID: 1)
        let room = buildMaterial(forTierID: 1, textures: textures, inRackRoom: true)
        let shared = buildMaterial(forTierID: 1, textures: textures)
        #expect(room.baseColor.texture == nil)
        #expect(tint(room) >= 0.6)
        #expect(room.metallic.texture != nil && room.roughness.texture != nil && room.normal.texture != nil)
        #expect(shared.baseColor.texture != nil, "previews, spinning plates and snapshots keep the colour map")
    }

    @Test func scenePlatePanelAndBandFollowTheBody() throws {
        let body = buildMaterial(forTierID: 1, textures: loadPlateTextures(forTierID: 1), inRackRoom: true)
        let plate = makePlateEntity(tierID: 1, material: body, weightKg: 25, options: .interactive(role: .bar))
        let panel = try #require(plate.children.first { $0.name == "recessedFacePanel" } as? ModelEntity)
        let material = try #require(panel.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(tint(material) >= 0.45)
        #expect(material.metallic.texture != nil)
    }

    @Test func untexturedCastIronAndPreviewPlatesAreUntouched() throws {
        let untextured = buildMaterial(forTierID: 25, textures: nil, inRackRoom: true)
        let plate = makePlateEntity(tierID: 25, material: untextured, weightKg: 20, options: .interactive(role: .bar))
        let panel = try #require(plate.children.first { $0.name == "recessedFacePanel" } as? ModelEntity)
        let material = try #require(panel.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(tint(material) < 0.4, "Iron Circuit keeps its dark finish")

        let body = buildMaterial(forTierID: 1, textures: loadPlateTextures(forTierID: 1), inRackRoom: true)
        let preview = makePlateEntity(tierID: 1, material: body, weightKg: 25, options: .visualOnly())
        let previewPanel = try #require(preview.children.first { $0.name == "recessedFacePanel" } as? ModelEntity)
        let previewMaterial = try #require(previewPanel.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(tint(previewMaterial) < 0.4)
    }
}
