import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// The lathe rack room's home gym mood: a dark room lit by a honeycomb LED light and a small sign.
@MainActor
@Suite struct RackRoomMoodTests {
    @Test func onlyTheLathePlatesGetTheMood() {
        #expect(RackRoomMood.current(for: .legacy) == nil)
        #expect(RackRoomMood.resolve("off") == nil)
        #expect(RackRoomMood.resolve(nil)?.variant == RackRoomMood.defaultVariant)
        #expect(RackRoomMood.resolve("nonsense")?.variant == RackRoomMood.defaultVariant)
        #expect(RackRoomMood.resolve(nil)?.signStyle == RackRoomMood.defaultSignStyle)
        #expect(RackRoomMood.resolve("wall", sign: "lime")?.signStyle == .lime)
        for variant in RackRoomMood.Variant.allCases {
            #expect(RackRoomMood.resolve(variant.rawValue)?.variant == variant)
        }
    }

    private struct Counts {
        var models = 0, slots = 0, spots = 0, shadowed = 0, points = 0, entities = 0
        var names: [String] = []
    }

    private func counts(_ mood: RackRoomMood) -> Counts {
        let root = Entity()
        mood.addFixtures(to: root, signText: "VOLIA", keyScale: 1)
        var c = Counts()
        func visit(_ entity: Entity) {
            c.entities += 1
            c.names.append(entity.name)
            if let model = entity.components[ModelComponent.self] { c.models += 1; c.slots += model.materials.count }
            if entity.components[SpotLightComponent.self] != nil { c.spots += 1 }
            if entity.components[SpotLightComponent.Shadow.self] != nil { c.shadowed += 1 }
            if entity.components[PointLightComponent.self] != nil { c.points += 1 }
            entity.children.forEach(visit)
        }
        root.children.forEach(visit)
        return c
    }

    @Test(arguments: RackRoomMood.Variant.allCases, RackRoomMood.SignStyle.allCases)
    func fixturesStayInsideTheLightAndEntityBudget(_ variant: RackRoomMood.Variant, _ sign: RackRoomMood.SignStyle) {
        let mood = RackRoomMood.preset(variant, sign: sign)
        let c = counts(mood)
        let glows = mood.fixtures.contains { $0.glowHalfWidth > 0 }
        // Tubes, glow (big grids), the sign, and the white sign's lime edge.
        #expect(c.models == 2 + (glows ? 1 : 0) + (sign == .white ? 1 : 0))
        #expect(c.slots == c.models, "one material each")
        #expect(c.names.filter { $0 == "moodHexLight" }.count == 1)
        #expect(c.names.filter { $0 == "moodHexGlow" }.count == (glows ? 1 : 0))
        #expect(c.spots == 1 && c.shadowed == 1, "one shadowed light")
        #expect(c.points <= 3)
        #expect(c.entities <= 9)
        // The old floating tube lamp, the floor strip and the sign's coloured light are gone.
        #expect(!c.names.contains("moodLampTube") && !c.names.contains("moodStrip") && !c.names.contains("moodSignHalo"))
    }

    @Test func lightsAreSoftAndMirrored() {
        for variant in RackRoomMood.Variant.allCases {
            let mood = RackRoomMood.preset(variant)
            // Left and right sleeves stay mirror images: the key on the centre line, points on it
            // or in mirrored pairs.
            #expect(mood.keyPosition.x == 0 && mood.keyTarget.x == 0)
            let xs = mood.points.map(\.position.x)
            for (point, x) in zip(mood.points, xs) {
                #expect(x == 0 || mood.points.contains { $0.position.x == -x && $0.position.y == point.position.y
                    && $0.position.z == point.position.z && $0.intensity == point.intensity }, "\(variant)")
            }
            #expect(mood.fixtures.allSatisfy { $0.centre.x == 0 })
            // A soft edge: the inner cone well inside the outer, so no hard disc on a plate.
            #expect(mood.keyOuterAngle - mood.keyInnerAngle >= 40)
            // High and in front of the bar (bar at y 0.6, z 0.12), aimed down past it.
            #expect(mood.keyPosition.y > 1.5 && mood.keyPosition.z > 0.12)
            // Rims sit against the wall behind the bar, the wash in front of the wall.
            #expect(mood.points.filter { $0.name == "moodRim" }.allSatisfy { $0.position.z < 0.12 })
        }
    }

    @Test func roomStaysDarkSurfacedWithAMatteFloor() {
        let theme = RoomThemePreset.preset(for: "dark_gym")
        let mood = RackRoomMood.preset(.wall)
        let dark = theme.dimmed(by: mood.roomBrightness, floor: mood.floorBrightness, floorRoughness: mood.floorRoughness)
        #expect(dark.backdropColor.barbellHSB.brightness < 0.15)
        #expect(dark.floorColor.barbellHSB.brightness < 0.25)
        #expect(dark.floorRoughness >= 0.8, "rubber is matte: no mirror sheen")
    }

    @Test(arguments: RackRoomMood.Variant.allCases)
    func signIsTheLogoMarkInsideTheMiddleCell(_ variant: RackRoomMood.Variant) throws {
        let mood = RackRoomMood.preset(variant)
        let root = Entity()
        mood.addFixtures(to: root, signText: "VOLIA", keyScale: 1)
        let sign = try #require(root.children.first { $0.name == "moodSign" } as? ModelEntity)
        let bounds = sign.visualBounds(relativeTo: root)
        // The logo's proportions, not a word's.
        let aspect = bounds.extents.x / bounds.extents.y
        #expect(abs(aspect - Float(VMarkShape.aspectRatio)) < 0.05)
        // About half the cell's inner width, centred on the cell.
        #expect(abs(bounds.extents.x - mood.signWidth) < 0.005)
        #expect(simd_distance(SIMD2(bounds.center.x, bounds.center.y),
                              SIMD2(RackRoomMood.signPosition.x, RackRoomMood.signPosition.y)) < 0.01)
        guard let wall = mood.fixtures.first(where: { $0.glowHalfWidth > 0 }) else { return }
        let inner = 2 * (wall.grid.radius - wall.tubeRadius)
        #expect(mood.signWidth >= 0.5 * inner && mood.signWidth <= 0.6 * inner)
        // Every corner of the sign's box sits inside the hexagon, clear of the tube and its glow.
        let c30: Float = Float(3).squareRoot() / 2
        let clear = wall.grid.apothem - wall.tubeRadius - wall.glowHalfWidth
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                let p = SIMD2(sx * bounds.extents.x / 2, sy * bounds.extents.y / 2)
                let d = max(abs(p.y), abs(p.x * c30 + p.y * 0.5), abs(-p.x * c30 + p.y * 0.5))
                #expect(d < clear, "\(variant)")
            }
        }
    }

    @Test func customRoomNameFitsTheSameCell() throws {
        let mood = RackRoomMood.preset(.wallHigh)
        let root = Entity()
        mood.addFixtures(to: root, signText: "IRON CAVE GYM", keyScale: 1)
        let sign = try #require(root.children.first { $0.name == "moodSign" } as? ModelEntity)
        let bounds = sign.visualBounds(relativeTo: root)
        #expect(bounds.extents.x <= mood.signWidth + 0.005)
        #expect(abs(bounds.center.x) < 0.01 && abs(bounds.center.y - RackRoomMood.signPosition.y) < 0.01)
    }

    @Test func lightIsNeutralToCoolWhite() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        RackRoomMood.coolWhite.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(b >= r && r > 0.9 && b - r < 0.08)
    }

    @Test func dimmedRoomIsDarkerButKeepsItsHue() {
        let theme = RoomThemePreset.preset(for: "brick_powerhouse")
        let mood = RackRoomMood.preset(.wall)
        let dark = theme.dimmed(by: mood.roomBrightness, floor: mood.floorBrightness)
        #expect(dark.backdropColor.barbellHSB.brightness < theme.backdropColor.barbellHSB.brightness * 0.5)
        #expect(abs(dark.backdropColor.barbellHSB.hue - theme.backdropColor.barbellHSB.hue) < 0.01)
    }

    @Test func signAccentIsTheBrandLime() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        RackRoomMood.lime.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.8) < 0.02 && abs(g - 1) < 0.02 && b < 0.02)
    }
}

/// Which rooms get the mood: the dark rooms do, the pale rooms keep their own colours.
@MainActor
@Suite struct RackRoomMoodRoomTests {
    @Test func paleRoomsKeepTheirOwnLookAndDarkRoomsGetTheMood() {
        for room in ["concrete_room", "competition_platform", "daylight_studio"] {
            #expect(RackRoomMood.current(for: .lathe, roomThemeID: room) == nil)
        }
        for room in ["dark_gym", "neon_garage", "iron_basement", "brick_powerhouse"] {
            #expect(RackRoomMood.current(for: .lathe, roomThemeID: room) == RackRoomMood.current(for: .lathe))
            #expect(RackRoomMood.current(for: .legacy, roomThemeID: room) == nil)
        }
    }

    @Test func everyRoomAUserCanOwnIsDecided() {
        let rooms = BarbellCosmeticCatalog.current.items.filter { $0.kind == .roomTheme }.map(\.id)
        #expect(Set(rooms) == ["dark_gym", "concrete_room", "competition_platform", "neon_garage",
                               "iron_basement", "daylight_studio", "brick_powerhouse"])
    }
}
