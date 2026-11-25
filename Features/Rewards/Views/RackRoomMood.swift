// Features/Rewards/Views/RackRoomMood.swift
//
// The lathe rack room as a moody home gym: a dark room lit by a honeycomb of white LED tubes
// (RackHexLight), the kind hung in garages and home gyms. The fixture is the brightest thing in
// the frame and carries the scene's one shadowed light, so the shadows come from it; a soft
// point light washes the surface it hangs on. A lit VOLIA sign stays on the back wall as a small
// brand accent with a tight, faint halo: nothing else in the room picks up its colour.
//
// The studio environment stays for reflections on metal but is turned well down, and carries a
// painted copy of the honeycomb (RackHexReflection) so chrome, gold and the bar reflect it.
// RealityKit applies one intensity to an environment's diffuse and specular light alike, so the
// dim room and dimmer metal reflections come together.
//
// Debug builds with lathe plates only (RackPlateStyle). In the launch environment,
// VOLIA_RACK_MOOD=wall|ceiling|both|off picks where the honeycomb hangs (default `wall`) and
// VOLIA_RACK_SIGN=lime|white the sign's letters (default `white`).

import RealityKit
import SwiftUI
import UIKit

struct RackRoomMood: Equatable {
    typealias Variant = RackHexPlacement

    enum SignStyle: String, CaseIterable, Equatable {
        /// Brand lime letters.
        case lime
        /// White letters with a faint lime edge.
        case white
    }

    var variant: Variant
    /// Wall colours (wall, panel, rails, lettering) scaled by this.
    var roomBrightness: CGFloat
    /// Floor colours scaled by this: a little lighter than the walls so the key's pool reads on
    /// it, while the floor away from it still falls to dark.
    var floorBrightness: CGFloat
    var imageBasedLightIntensityExponent: Float

    /// The honeycomb panels: one model between them.
    var fixtures: [RackHexFixture]
    /// Neutral to slightly cool white, about 6000 K.
    var lightColor: UIColor

    // The key: the scene's one shadowed light, a soft spot at the fixture.
    var keyPosition: SIMD3<Float>
    var keyTarget: SIMD3<Float>
    var keyIntensity: Float
    var keyInnerAngle: Float
    var keyOuterAngle: Float
    var keyAttenuation: Float

    // The wash: a point light just off the fixture, lighting the surface around it.
    var washPosition: SIMD3<Float>
    var washIntensity: Float
    var washRadius: Float

    // The sign: emissive letters and a tight halo on the wall behind them.
    var signStyle: SignStyle
    var signHaloIntensity: Float
    var signHaloRadius: Float

    /// The brand lime (DS.Cut.Colors.lime, #CCFF00).
    static let lime = UIColor(DS.Cut.Colors.lime)
    static let coolWhite = UIColor(red: 0.95, green: 0.975, blue: 1.0, alpha: 1)

    /// Room colours fall to this share in every variant: walls near black away from the lights.
    static let darkRoom: CGFloat = 0.42

    /// The sign's centre on the back wall, in front of the plate zone panel (face at z -0.103).
    static let signPosition = SIMD3<Float>(0, 1.00, -0.098)

    static func preset(_ variant: Variant, sign: SignStyle = defaultSignStyle) -> RackRoomMood {
        var mood = RackRoomMood(
            variant: variant,
            roomBrightness: darkRoom,
            floorBrightness: 0.75,
            imageBasedLightIntensityExponent: -1.6,
            fixtures: RackHexFixture.fixtures(for: variant),
            lightColor: coolWhite,
            keyPosition: SIMD3(0, 1.30, 0.02),
            keyTarget: SIMD3(0, 0, 0.80),
            keyIntensity: 14_000,
            keyInnerAngle: 45,
            keyOuterAngle: 85,
            keyAttenuation: 4.0,
            washPosition: SIMD3(0, 1.30, 0.10),
            washIntensity: 2_500,
            washRadius: 0.75,
            signStyle: sign,
            signHaloIntensity: 500,
            signHaloRadius: 0.30
        )
        switch variant {
        case .wall:
            break
        case .ceiling:
            mood.keyPosition = SIMD3(0, 1.42, 0.36)
            mood.keyTarget = SIMD3(0, 0, 0.42)
            mood.washPosition = SIMD3(0, 1.36, 0.04)
            mood.washRadius = 0.70
            mood.washIntensity = 700
        case .both:
            mood.keyPosition = SIMD3(0, 1.42, 0.38)
            mood.keyTarget = SIMD3(0, 0, 0.46)
            mood.washIntensity = 1_800
        }
        return mood
    }

    /// The mood for a scene: lathe plates in the rack room only, nil otherwise (legacy plates and
    /// Release builds never get here: RackPlateStyle is legacy there).
    static func current(for style: RackPlateStyle) -> RackRoomMood? {
        guard style == .lathe else { return nil }
        let environment = ProcessInfo.processInfo.environment
        return resolve(environment["VOLIA_RACK_MOOD"], sign: environment["VOLIA_RACK_SIGN"])
    }

    /// nil or an unknown value takes the default; "off" keeps the bright studio room.
    static func resolve(_ value: String?, sign: String? = nil) -> RackRoomMood? {
        guard let placement = RackHexPlacement.resolve(value) else { return nil }
        return preset(placement, sign: sign.flatMap(SignStyle.init(rawValue:)) ?? defaultSignStyle)
    }

    static let defaultVariant: Variant = RackHexPlacement.defaultPlacement
    static let defaultSignStyle: SignStyle = .white

    // MARK: Building

    /// Adds the honeycomb (one model), the key, the wash and the sign under `root`.
    @MainActor
    func addFixtures(to root: Entity, signText: String, keyScale: Float) {
        if let hex = RackHexLight.makeEntity(fixtures) {
            root.addChild(hex)
        }

        // Key: at the fixture, wide and soft (inner well inside outer) so its edge never crosses
        // the plates or the drop path; the falloff from the fixture makes the pool on the floor.
        let key = Entity()
        key.name = "moodKey"
        key.components.set(SpotLightComponent(color: lightColor, intensity: keyIntensity * keyScale,
                                              innerAngleInDegrees: keyInnerAngle, outerAngleInDegrees: keyOuterAngle,
                                              attenuationRadius: keyAttenuation))
        var shadow = SpotLightComponent.Shadow()
        shadow.depthBias = 2
        key.components.set(shadow)
        root.addChild(key)
        key.look(at: keyTarget, from: keyPosition, relativeTo: root)

        // Wash: the fixture lighting the wall or ceiling right around it; short reach, so it
        // never touches the plates.
        let wash = Entity()
        wash.name = "moodWash"
        wash.components.set(PointLightComponent(color: lightColor, intensity: washIntensity, attenuationRadius: washRadius))
        wash.position = washPosition
        root.addChild(wash)

        addSign(to: root, text: signText)
    }

    @MainActor
    private func addSign(to root: Entity, text signText: String) {
        let font = UIFont(name: "BarlowSemiCondensed-Black", size: 0.20) ?? .systemFont(ofSize: 0.20, weight: .heavy)
        let text = MeshResource.generateText(signText, extrusionDepth: 0.008, font: font,
                                             containerFrame: CGRect(x: -0.8, y: -0.13, width: 1.6, height: 0.26),
                                             alignment: .center, lineBreakMode: .byClipping)
        let sign = ModelEntity(mesh: text, materials: [signStyle == .lime ? Self.glow(Self.lime) : RackHexLight.tubeMaterial()])
        sign.name = "moodSign"
        sign.position = Self.signPosition
        root.addChild(sign)
        if signStyle == .white {
            // The lime edge: the same letters a touch larger, dim lime, just behind the white.
            let edge = ModelEntity(mesh: text, materials: [Self.glow(Self.lime.withBrightness(0.55))])
            edge.name = "moodSignEdge"
            edge.scale = SIMD3(1.03, 1.06, 1)
            edge.position = Self.signPosition + SIMD3(0, 0, -0.003)
            root.addChild(edge)
        }
        // Halo: a faint lime light right at the wall, reaching only the letters' surround.
        let halo = Entity()
        halo.name = "moodSignHalo"
        halo.components.set(PointLightComponent(color: Self.lime, intensity: signHaloIntensity, attenuationRadius: signHaloRadius))
        halo.position = Self.signPosition + SIMD3(0, 0, 0.06)
        root.addChild(halo)
    }

    /// A light source's surface: unlit, so it reads as the brightest thing in its colour.
    static func glow(_ color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }
}

extension RackHexPlacement {
    nonisolated static let defaultPlacement: RackHexPlacement = .wall

    /// The launch environment's VOLIA_RACK_MOOD: nil for "off", the default for nil or unknown.
    nonisolated static func resolve(_ value: String?) -> RackHexPlacement? {
        if value == "off" { return nil }
        return value.flatMap(RackHexPlacement.init(rawValue:)) ?? defaultPlacement
    }

    /// The placement the studio panorama paints, read once where the panorama is built. nil
    /// outside debug builds and when the mood is off.
    nonisolated static var currentForEnvironment: RackHexPlacement? {
        #if DEBUG
        return resolve(ProcessInfo.processInfo.environment["VOLIA_RACK_MOOD"])
        #else
        return nil
        #endif
    }
}

private extension UIColor {
    func withBrightness(_ factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: a)
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
