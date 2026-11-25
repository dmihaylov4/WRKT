import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// The lathe rack room's home gym mood: a dark room lit by a sign, a strip and a lamp.
@MainActor
@Suite struct RackRoomMoodTests {
    @Test func onlyTheLathePlatesGetTheMood() {
        #expect(RackRoomMood.current(for: .legacy) == nil)
        #expect(RackRoomMood.resolve("off") == nil)
        #expect(RackRoomMood.resolve(nil)?.variant == RackRoomMood.defaultVariant)
        #expect(RackRoomMood.resolve("nonsense")?.variant == RackRoomMood.defaultVariant)
        for variant in RackRoomMood.Variant.allCases {
            #expect(RackRoomMood.resolve(variant.rawValue)?.variant == variant)
        }
    }

    @Test func fixturesStayInsideTheLightAndEntityBudget() {
        for variant in RackRoomMood.Variant.allCases {
            let root = Entity()
            RackRoomMood.preset(variant).addFixtures(to: root, signText: "VOLIA", keyScale: 1)
            var models = 0, spots = 0, shadowed = 0, points = 0
            func visit(_ entity: Entity) {
                if entity.components[ModelComponent.self] != nil { models += 1 }
                if entity.components[SpotLightComponent.self] != nil { spots += 1 }
                if entity.components[SpotLightComponent.Shadow.self] != nil { shadowed += 1 }
                if entity.components[PointLightComponent.self] != nil { points += 1 }
                entity.children.forEach(visit)
            }
            visit(root)
            #expect(models == 3, "\(variant): lamp, sign and strip")
            #expect(spots == 1 && shadowed == 1, "\(variant): one shadowed light")
            #expect(points <= 3, "\(variant)")
        }
    }

    @Test func lampIsSoftAndCentred() {
        for variant in RackRoomMood.Variant.allCases {
            let mood = RackRoomMood.preset(variant)
            // Left and right sleeves stay mirror images: every light sits on the centre line or in
            // mirrored pairs (the strip's two washes).
            #expect(mood.lampPosition.x == 0 && mood.lampTarget.x == 0)
            // A soft edge: the inner cone well inside the outer, so no hard disc on the floor or wall.
            #expect(mood.lampOuterAngle - mood.lampInnerAngle >= 40)
        }
    }

    @Test func dimmedRoomIsDarkerButKeepsItsHue() {
        let theme = RoomThemePreset.preset(for: "brick_powerhouse")
        let mood = RackRoomMood.preset(.lime)
        let dark = theme.dimmed(by: mood.roomBrightness, floor: mood.floorBrightness)
        #expect(dark.backdropColor.barbellHSB.brightness < theme.backdropColor.barbellHSB.brightness * 0.5)
        #expect(abs(dark.backdropColor.barbellHSB.hue - theme.backdropColor.barbellHSB.hue) < 0.01)
        #expect(dark.floorColor.barbellHSB.brightness > dark.backdropColor.barbellHSB.brightness)
    }

    @Test func signIsTheBrandLime() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        RackRoomMood.lime.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.8) < 0.02 && abs(g - 1) < 0.02 && b < 0.02)
    }
}
