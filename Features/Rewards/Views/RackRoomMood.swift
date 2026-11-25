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
    static var signPosition: SIMD3<Float> { RackHexFixture.signCentre }

    static func preset(_ variant: Variant, sign: SignStyle = defaultSignStyle) -> RackRoomMood {
        RackRoomMood(
            variant: variant,
            roomBrightness: darkRoom,
            floorBrightness: 0.30,
            floorRoughness: 0.85,
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

    /// The sign's width: this share of the sign cell's inner width (between its tubes).
    static let signWidthFraction: Float = 0.55

    /// The sign's width in metres: inside the big grid's middle cell, or the earlier fixtures'
    /// open wall.
    var signWidth: Float {
        guard let wall = fixtures.first(where: { !$0.onCeiling && $0.glowHalfWidth > 0 }) else { return 0.34 }
        return Self.signWidthFraction * 2 * (wall.grid.radius - wall.tubeRadius)
    }

    /// The VOLIA logo mark (two chamfered arms, VMarkShape) as a flat lit sign; a custom room
    /// name is shown instead, as text fitted to the same width.
    @MainActor
    private func addSign(to root: Entity, text signText: String) {
        let width = signWidth
        let mesh: MeshResource?
        let scale: Float
        if signText == "VOLIA" {
            mesh = Self.cachedLogoMesh()
            scale = width
        } else {
            let font = UIFont(name: "BarlowSemiCondensed-Black", size: 0.20) ?? .systemFont(ofSize: 0.20, weight: .heavy)
            let text = MeshResource.generateText(signText, extrusionDepth: 0.006, font: font,
                                                 containerFrame: CGRect(x: -0.8, y: -0.13, width: 1.6, height: 0.26),
                                                 alignment: .center, lineBreakMode: .byClipping)
            mesh = text
            // Fit to the width, and to a height that keeps long and short names inside the cell.
            let extent = text.bounds.extents
            scale = min(width / max(extent.x, 0.001), (width * 0.45) / max(extent.y, 0.001))
        }
        guard let mesh else { return }
        let sign = ModelEntity(mesh: mesh, materials: [signStyle == .lime ? Self.glow(Self.lime) : RackHexLight.tubeMaterial()])
        sign.name = "moodSign"
        sign.scale = SIMD3(scale, scale, 1)
        // Centred on the cell: the text mesh's own centre may sit off its origin.
        let centre = mesh.bounds.center * SIMD3(scale, scale, 1)
        sign.position = Self.signPosition - SIMD3(centre.x, centre.y, 0)
        root.addChild(sign)
        if signStyle == .white {
            // The lime edge: the same shape a touch larger, dim lime, just behind the white.
            let edge = ModelEntity(mesh: mesh, materials: [Self.glow(Self.lime.withBrightness(0.55))])
            edge.name = "moodSignEdge"
            edge.scale = SIMD3(scale * 1.04, scale * 1.06, 1)
            edge.position = sign.position + SIMD3(0, 0, -0.003)
            root.addChild(edge)
        }
    }

    /// The logo mark one unit wide, centred on its origin, facing +z, 1 cm deep (in units of
    /// its width, so scaled with it). Built once.
    @MainActor
    static func cachedLogoMesh() -> MeshResource? {
        if let mesh = _logoMesh { return mesh }
        let geometry = logoGeometry()
        var descriptor = MeshDescriptor(name: "RackLogoMark")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        let mesh = try? MeshResource.generate(from: [descriptor])
        _logoMesh = mesh
        return mesh
    }

    @MainActor private static var _logoMesh: MeshResource?

    /// The two arms of VMarkShape (each a convex hexagon in the logo's viewBox, y down), mapped to
    /// a mark one unit wide with y up: a front face fanned from the first corner and side walls.
    static func logoGeometry(depth: Float = 0.03) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        let box = VMarkShape.viewBox
        let unit = Float(1 / box.width)
        func point(_ p: CGPoint) -> SIMD2<Float> {
            SIMD2(Float(p.x - box.midX) * unit, -Float(p.y - box.midY) * unit)
        }
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for arm in [VMarkShape.leftArm, VMarkShape.rightArm] {
            var corners = arm.map(point)
            // Counter-clockwise seen from the front (+z), so the fan faces the viewer.
            var area: Float = 0
            for i in corners.indices { let a = corners[i], b = corners[(i + 1) % corners.count]; area += a.x * b.y - b.x * a.y }
            if area < 0 { corners.reverse() }
            let base = UInt32(positions.count)
            for c in corners { positions.append(SIMD3(c.x, c.y, 0)); normals.append(SIMD3(0, 0, 1)) }
            for i in 1..<(corners.count - 1) { indices += [base, base + UInt32(i), base + UInt32(i + 1)] }
            for i in corners.indices {
                let a = corners[i], b = corners[(i + 1) % corners.count]
                let edge = b - a
                let n = simd_normalize(SIMD3(edge.y, -edge.x, 0))
                let s = UInt32(positions.count)
                positions += [SIMD3(a.x, a.y, 0), SIMD3(b.x, b.y, 0), SIMD3(b.x, b.y, -depth), SIMD3(a.x, a.y, -depth)]
                normals += [n, n, n, n]
                indices += [s, s + 2, s + 1, s, s + 3, s + 2]
            }
        }
        return (positions, normals, indices)
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
