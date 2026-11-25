// Features/Rewards/Views/RackRoomMood.swift
//
// The lathe rack room as a moody home gym: a dark room lit by a few sources you can see. A lit
// VOLIA sign on the back wall in the brand lime, an LED strip along the foot of the wall, and a
// tube lamp hanging over the bar that carries the one shadowed light. The studio environment
// stays for reflections on metal but is turned well down; RealityKit applies one intensity to an
// environment's diffuse and specular light alike, so the dim room and dimmer metal reflections
// come together (the lights' highlights carry the metal instead).
//
// Debug builds with lathe plates only (RackPlateStyle). VOLIA_RACK_MOOD=lime|blue|warm|off in the
// launch environment picks a variant; the default is `lime`.

import RealityKit
import SwiftUI
import UIKit

struct RackRoomMood: Equatable {
    enum Variant: String, CaseIterable, Equatable {
        /// The lime sign leads: a brand-coloured glow on the wall and a lime rim on bar and plates.
        case lime
        /// The cool LED strip leads: a blue-white wash up the wall behind the rack.
        case blue
        /// The warm lamp over the bar leads: a pool of light with the room falling to black.
        case warm
    }

    var variant: Variant
    /// Wall colours (wall, panel, rails, lettering) scaled by this.
    var roomBrightness: CGFloat
    /// Floor colours scaled by this: lighter than the walls so the lamp's pool reads on it, while
    /// the floor away from the lamp still falls to dark.
    var floorBrightness: CGFloat
    var imageBasedLightIntensityExponent: Float

    // Overhead lamp: an emissive tube, and the scene's one shadowed light, a soft spot under it.
    var lampPosition: SIMD3<Float>
    var lampColor: UIColor
    var lampIntensity: Float
    var lampTarget: SIMD3<Float>
    var lampInnerAngle: Float
    var lampOuterAngle: Float
    var lampAttenuation: Float

    // The sign: emissive letters and one point light in front of them.
    var signColor: UIColor
    var signIntensity: Float
    var signRadius: Float

    // The LED strip: an emissive line on the baseboard and two point lights washing the wall.
    var stripColor: UIColor
    var stripIntensity: Float
    var stripRadius: Float

    /// The brand lime (DS.Cut.Colors.lime, #CCFF00).
    static let lime = UIColor(DS.Cut.Colors.lime)
    static let warmWhite = UIColor(red: 1.0, green: 0.84, blue: 0.62, alpha: 1)
    static let coolStrip = UIColor(red: 0.62, green: 0.80, blue: 1.0, alpha: 1)

    /// Room colours fall to this share in every variant: walls near black away from the lights.
    static let darkRoom: CGFloat = 0.42

    static func preset(_ variant: Variant) -> RackRoomMood {
        var mood = RackRoomMood(
            variant: variant,
            roomBrightness: darkRoom,
            floorBrightness: 0.75,
            imageBasedLightIntensityExponent: -1.6,
            lampPosition: SIMD3(0, 1.36, 0.32),
            lampColor: warmWhite,
            lampIntensity: 12_000,
            lampTarget: SIMD3(0, 0, 0.42),
            lampInnerAngle: 30,
            lampOuterAngle: 82,
            lampAttenuation: 4.0,
            signColor: lime,
            signIntensity: 6_000,
            signRadius: 1.5,
            stripColor: coolStrip,
            stripIntensity: 1_500,
            stripRadius: 1.1
        )
        switch variant {
        case .lime:
            mood.signIntensity = 11_000
            mood.signRadius = 1.7
        case .blue:
            mood.signIntensity = 3_500
            mood.stripIntensity = 9_000
            mood.stripRadius = 1.4
            mood.stripColor = UIColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1)
        case .warm:
            mood.lampIntensity = 22_000
            mood.signIntensity = 3_000
            mood.stripIntensity = 900
        }
        return mood
    }

    /// The mood for a scene: lathe plates in the rack room only, nil otherwise (legacy plates and
    /// Release builds never get here: RackPlateStyle is legacy there).
    static func current(for style: RackPlateStyle) -> RackRoomMood? {
        guard style == .lathe else { return nil }
        return resolve(ProcessInfo.processInfo.environment["VOLIA_RACK_MOOD"])
    }

    /// nil or an unknown value takes the default; "off" keeps the bright studio room.
    static func resolve(_ value: String?) -> RackRoomMood? {
        if value == "off" { return nil }
        return preset(value.flatMap(Variant.init(rawValue:)) ?? defaultVariant)
    }

    static let defaultVariant: Variant = .lime

    // MARK: Building

    /// Adds the lamp, sign and strip (meshes and lights) under `root`. Three meshes, one shadowed
    /// spot and three point lights.
    @MainActor
    func addFixtures(to root: Entity, signText: String, keyScale: Float) {
        // Lamp: a short warm tube hanging over the bar, and the shadowed spot under it. The spot
        // is wide and soft (inner well inside outer) so its edge never crosses the plates or the
        // drop path; the falloff from a point 0.9 m over the bar makes the pool.
        let tube = ModelEntity(mesh: cachedCylinder(height: 0.60, radius: 0.014),
                               materials: [Self.glow(lampColor)])
        tube.name = "moodLampTube"
        tube.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        tube.position = lampPosition + SIMD3(0, 0.03, 0)
        root.addChild(tube)

        let lamp = Entity()
        lamp.name = "moodLamp"
        lamp.components.set(SpotLightComponent(color: lampColor, intensity: lampIntensity * keyScale,
                                               innerAngleInDegrees: lampInnerAngle, outerAngleInDegrees: lampOuterAngle,
                                               attenuationRadius: lampAttenuation))
        var shadow = SpotLightComponent.Shadow()
        shadow.depthBias = 2
        lamp.components.set(shadow)
        root.addChild(lamp)
        lamp.look(at: lampTarget, from: lampPosition, relativeTo: root)

        // Sign: lit letters on the back wall, above the bar, and a lime point light just in front.
        let font = UIFont(name: "BarlowSemiCondensed-Black", size: 0.20) ?? .systemFont(ofSize: 0.20, weight: .heavy)
        let text = MeshResource.generateText(signText, extrusionDepth: 0.008, font: font,
                                             containerFrame: CGRect(x: -0.8, y: -0.13, width: 1.6, height: 0.26),
                                             alignment: .center, lineBreakMode: .byClipping)
        let sign = ModelEntity(mesh: text, materials: [Self.glow(signColor)])
        sign.name = "moodSign"
        // In front of the plate zone panel (its face is at z -0.103).
        sign.position = SIMD3(0, 1.02, -0.098)
        root.addChild(sign)
        let signLight = Entity()
        signLight.name = "moodSignLight"
        signLight.components.set(PointLightComponent(color: signColor, intensity: signIntensity, attenuationRadius: signRadius))
        // Out from the wall so the glow spreads instead of pooling in one spot behind the letters.
        signLight.position = SIMD3(0, 1.00, 0.16)
        root.addChild(signLight)

        // Strip: an LED line on top of the baseboard behind the rack, washing up the wall.
        let strip = ModelEntity(mesh: cachedBox(size: SIMD3(2.30, 0.010, 0.010)), materials: [Self.glow(stripColor)])
        strip.name = "moodStrip"
        strip.position = SIMD3(0, 0.108, -0.110)
        root.addChild(strip)
        for x: Float in [-0.55, 0.55] {
            let wash = Entity()
            wash.name = "moodStripLight"
            wash.components.set(PointLightComponent(color: stripColor, intensity: stripIntensity, attenuationRadius: stripRadius))
            wash.position = SIMD3(x, 0.26, 0.10)
            root.addChild(wash)
        }
    }

    /// A light source's surface: unlit, so it reads as the brightest thing in its colour.
    static func glow(_ color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }
}

extension RoomThemePreset {
    /// The same room with every colour's brightness scaled: the mood's dark home gym.
    func dimmed(by factor: CGFloat, floor floorFactor: CGFloat? = nil) -> RoomThemePreset {
        func dim(_ c: UIColor, _ factor: CGFloat = factor) -> UIColor {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            if c.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
                return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: a)
            }
            var w: CGFloat = 0
            c.getWhite(&w, alpha: &a)
            return UIColor(white: w * factor, alpha: a)
        }
        return RoomThemePreset(
            backdropColor: dim(backdropColor), backdropMetallic: backdropMetallic, backdropRoughness: backdropRoughness,
            floorColor: dim(floorColor, floorFactor ?? factor), floorMetallic: floorMetallic, floorRoughness: floorRoughness,
            stripColor: dim(stripColor, floorFactor ?? factor), bumperColor: dim(bumperColor), bumperMetallic: bumperMetallic,
            bumperRoughness: bumperRoughness, plateZoneColor: dim(plateZoneColor), plateZoneMetallic: plateZoneMetallic,
            plateZoneRoughness: plateZoneRoughness, wallTextColor: dim(wallTextColor),
            swiftUIBackground: Color(dim(UIColor(swiftUIBackground)))
        )
    }
}
