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
        let c = counts(RackRoomMood.preset(variant, sign: sign))
        // One honeycomb model for every panel, the sign, and the white sign's lime edge.
        #expect(c.models == (sign == .white ? 3 : 2))
        #expect(c.slots == c.models, "one material each")
        #expect(c.names.filter { $0 == "moodHexLight" }.count == 1)
        #expect(c.spots == 1 && c.shadowed == 1, "one shadowed light")
        #expect(c.points <= 3)
        #expect(c.entities <= 6)
        // The old floating tube lamp and the floor strip are gone.
        #expect(!c.names.contains("moodLampTube") && !c.names.contains("moodStrip"))
    }

    @Test func keyIsSoftCentredAndAtTheFixture() {
        for variant in RackRoomMood.Variant.allCases {
            let mood = RackRoomMood.preset(variant)
            // Left and right sleeves stay mirror images: every light on the centre line.
            #expect(mood.keyPosition.x == 0 && mood.keyTarget.x == 0 && mood.washPosition.x == 0)
            #expect(mood.fixtures.allSatisfy { $0.centre.x == 0 && $0.grid.columns % 2 == 1 })
            // A soft edge: the inner cone well inside the outer, so no hard disc on a plate.
            #expect(mood.keyOuterAngle - mood.keyInnerAngle >= 40)
            // The shadows are motivated: the key hangs at one of the panels.
            let nearest = mood.fixtures.map { simd_distance($0.centre, mood.keyPosition) }.min() ?? .infinity
            #expect(nearest < 0.15, "\(variant)")
            // The wash lights the fixture's surround, not the plates on the bar (y 0.6, x 0.68).
            #expect(simd_distance(mood.washPosition, SIMD3(0.55, 0.6, 0.12)) > mood.washRadius)
        }
    }

    @Test func signHaloStaysOffTheBarAndStands() {
        for variant in RackRoomMood.Variant.allCases {
            let mood = RackRoomMood.preset(variant)
            // The sign's colour must not reach the bar (y 0.6) or the plates.
            let halo = RackRoomMood.signPosition + SIMD3(0, 0, 0.06)
            #expect(halo.y - mood.signHaloRadius > 0.6 + 0.05)
            #expect(mood.signHaloRadius <= 0.35)
        }
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
        #expect(dark.floorColor.barbellHSB.brightness > dark.backdropColor.barbellHSB.brightness)
    }

    @Test func signAccentIsTheBrandLime() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        RackRoomMood.lime.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.8) < 0.02 && abs(g - 1) < 0.02 && b < 0.02)
    }
}
