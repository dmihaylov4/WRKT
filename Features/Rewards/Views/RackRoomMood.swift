// Features/Rewards/Views/RackRoomMood.swift
//
// The lathe rack room as a moody home gym: dark walls and floor, lit by a big honeycomb of white
// LED tubes covering the back wall behind the rack (RackHexLight), the kind hung in garages and
// home gyms. The VOLIA sign sits in the honeycomb's middle cell: white letters with a faint lime
// edge, a small brand accent that throws no coloured light.
//
// The lights stand in for the grid as a large area light behind the bar:
// - the one shadowed light, a wide soft spot high and in front of the bar, as if the grid's top
//   rows and their bounce off the ceiling were lighting the room: it fills the bar, stands and
//   plate faces from above and in front and drops soft shadows under them onto the floor;
// - a wash in front of the wall that lights the wall around the tubes and adds a little fill;
// - two rim lights against the wall behind the sleeves, one each side, which put the white edge
//   a lit wall gives on the plate rims, the bar ends and the stands.
// The surfaces stay dark (walls near black, a dark glossier floor that picks up a sheen) so the
// light does the work.
//
// The studio environment stays for reflections on metal but is turned well down, and carries a
// painted copy of the honeycomb (RackHexReflection).
//
// Debug builds with lathe plates only (RackPlateStyle). In the launch environment,
// VOLIA_RACK_MOOD=wall|wallHigh|panel|ceiling|off picks the honeycomb (default `wallHigh`) and
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

    /// A point light without shadows.
    struct Point: Equatable {
        var name: String
        var position: SIMD3<Float>
        var intensity: Float
        var radius: Float
    }

    var variant: Variant
    /// Wall colours (wall, panel, rails, lettering) scaled by this.
    var roomBrightness: CGFloat
    /// Floor colours scaled by this.
    var floorBrightness: CGFloat
    /// The floor's roughness: a dark rubber with enough sheen to pick up the grid.
    var floorRoughness: Float
    var imageBasedLightIntensityExponent: Float

    /// The honeycomb: one tube model and one glow model between them.
    var fixtures: [RackHexFixture]
    /// Neutral to slightly cool white, about 6000 K.
    var lightColor: UIColor

    // The key: the scene's one shadowed light.
    var keyPosition: SIMD3<Float>
    var keyTarget: SIMD3<Float>
    var keyIntensity: Float
    var keyInnerAngle: Float
    var keyOuterAngle: Float
    var keyAttenuation: Float

    /// The wash and the two rims.
    var points: [Point]

    var signStyle: SignStyle

    /// The brand lime (DS.Cut.Colors.lime, #CCFF00).
    static let lime = UIColor(DS.Cut.Colors.lime)
    static let coolWhite = UIColor(red: 0.95, green: 0.975, blue: 1.0, alpha: 1)

    /// Room colours fall to this share in every variant: walls near black away from the lights.
    static let darkRoom: CGFloat = 0.42

    /// The sign's centre on the back wall, in front of the plate zone panel (face at z -0.103).
    static let signPosition = RackHexFixture.signCentre

    static func preset(_ variant: Variant, sign: SignStyle = defaultSignStyle) -> RackRoomMood {
        RackRoomMood(
            variant: variant,
            roomBrightness: darkRoom,
            floorBrightness: 0.30,
            floorRoughness: 0.30,
            imageBasedLightIntensityExponent: -1.6,
            fixtures: RackHexFixture.fixtures(for: variant),
            lightColor: coolWhite,
            keyPosition: SIMD3(0, 2.10, 1.00),
            keyTarget: SIMD3(0, 0.30, 0.15),
            keyIntensity: 28_000,
            keyInnerAngle: 35,
            keyOuterAngle: 80,
            keyAttenuation: 5.0,
            points: [
                Point(name: "moodWash", position: SIMD3(0, 1.25, 0.30), intensity: 2_800, radius: 1.4),
                Point(name: "moodRim", position: SIMD3(-0.70, 1.05, -0.03), intensity: 2_500, radius: 0.75),
                Point(name: "moodRim", position: SIMD3(0.70, 1.05, -0.03), intensity: 2_500, radius: 0.75)
            ],
            signStyle: sign
        )
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
    static let defaultSignStyle: SignStyle = .lime

    // MARK: Building

    /// Adds the honeycomb (tubes and glow), the key, the wash, the rims and the sign under `root`.
    @MainActor
    func addFixtures(to root: Entity, signText: String, keyScale: Float) {
        for entity in RackHexLight.makeEntities(fixtures) {
            root.addChild(entity)
        }

        // Key: high and in front, wide and soft (inner well inside outer) so its edge never
        // crosses the plates or the drop path.
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

        for point in points {
            let light = Entity()
            light.name = point.name
            light.components.set(PointLightComponent(color: lightColor, intensity: point.intensity, attenuationRadius: point.radius))
            light.position = point.position
            root.addChild(light)
        }

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
    }

    /// A light source's surface: unlit, so it reads as the brightest thing in its colour.
    static func glow(_ color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }
}

extension RackHexPlacement {
    nonisolated static let defaultPlacement: RackHexPlacement = .wallHigh

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
    func dimmed(by factor: CGFloat, floor floorFactor: CGFloat? = nil, floorRoughness floorRoughnessOverride: Float? = nil) -> RoomThemePreset {
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
            floorColor: dim(floorColor, floorFactor ?? factor), floorMetallic: floorMetallic, floorRoughness: floorRoughnessOverride ?? floorRoughness,
            stripColor: dim(stripColor, floorFactor ?? factor), bumperColor: dim(bumperColor), bumperMetallic: bumperMetallic,
            bumperRoughness: bumperRoughness, plateZoneColor: dim(plateZoneColor), plateZoneMetallic: plateZoneMetallic,
            plateZoneRoughness: plateZoneRoughness, wallTextColor: dim(wallTextColor),
            swiftUIBackground: Color(dim(UIColor(swiftUIBackground)))
        )
    }
}
