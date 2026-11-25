// Features/Rewards/Views/LathePlateGeometry.swift
//
// One mesh per plate, made by turning a 2D profile around the bar axis the way a lathe would:
// bore, hub, recessed face, raised lip and a rounded rim, with filleted edges so every edge
// catches a highlight. Pure geometry (no RealityKit), so it can be built off the main thread and
// tested on its own. LathePlateBuilder turns the data into a MeshResource and materials.
//
// Plate space matches the legacy plates: the axis is local y (the plate entity is then turned a
// quarter turn about z so the axis lies along the bar), faces at y = +/- thickness / 2.

import Foundation
import simd

// MARK: - Switch

/// Which plates the rack room scene builds. `.lathe` is the one-mesh plate (real bevels, true
/// metal, studio environment, one shadowed key); `.legacy` is the many-part plate the App Store
/// build ships. Follows the new rack room switch (RackRoomRelease): lathe in Debug builds and for
/// TestFlight testers on the new design, legacy for App Store installs and testers who switched
/// the new design off.
nonisolated enum RackPlateStyle: String, Equatable, Sendable {
    case legacy
    case lathe

    /// Launch-environment key that forces a style in debug builds: VOLIA_RACK_PLATES=legacy|lathe.
    static let overrideKey = "VOLIA_RACK_PLATES"

    /// The rule, separated from the build flag so tests can pin every case. The override is read
    /// only when `allowsOverrides` (Debug builds).
    static func resolve(newRoom: Bool, allowsOverrides: Bool, environment: [String: String]) -> RackPlateStyle {
        if allowsOverrides, let raw = environment[overrideKey], let forced = RackPlateStyle(rawValue: raw) { return forced }
        return newRoom ? .lathe : .legacy
    }

    /// The style this launch uses, resolved once.
    static let current: RackPlateStyle = resolve(newRoom: RackRoomRelease.isNewRoomEnabled,
                                                 allowsOverrides: RackRoomRelease.allowsLaunchOverrides,
                                                 environment: RackRoomRelease.overrideEnvironment)
}

// MARK: - Profile

/// The material slots of a lathe plate mesh, in the order of the model's materials array.
nonisolated enum LatheSlot {
    /// Rim, lip, edges and the outer wall.
    static let body: UInt32 = 0
    /// Bore and hub (a steel insert on bumpers, the machined boss on iron).
    static let hub: UInt32 = 1
    /// The flat recessed face that carries the lettering (planar UVs).
    static let face: UInt32 = 2
    static let count = 3
}

nonisolated enum LathePlateFamily: String, Hashable, Sendable, CaseIterable {
    /// Thick rubber with a steel hub insert and a well rounded rim.
    case bumper
    /// Calibrated competition plate: a little thinner, flatter face, crisper rim.
    case competition
    /// Cast iron: deep recess, raised lip and boss, soft cast edges.
    case castIron
    /// Machined metal (raw iron, steel, chrome, gold, brass): thin, shallow recess, crisp bevels.
    case machined
}

/// One corner of the half profile, from the bore's mid plane over the top face to the rim's mid
/// plane. `fillet` rounds the corner with `segments` steps (0 keeps a crease).
nonisolated struct LatheProfileCorner: Equatable, Sendable {
    var r: Float
    var y: Float
    var fillet: Float = 0
    var segments: Int = 2
    /// Slot of the rounded corner's faces. nil takes the outgoing edge's slot.
    var slot: UInt32?
}

nonisolated struct LatheProfile: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        let family: LathePlateFamily
        let outerRadius: Float
        let thickness: Float
    }

    let family: LathePlateFamily
    let outerRadius: Float
    let thickness: Float
    let boreRadius: Float
    /// Top half corners, first (bore, y 0) to last (rim, y 0).
    let corners: [LatheProfileCorner]
    /// Slot of each top half edge: corners[i] to corners[i + 1].
    let edgeSlots: [UInt32]
    /// The planar face UVs span this radius (the plate's outer radius): the face texture is the
    /// whole plate disc, of which the recessed face is the ring that shows.
    var faceUVRadius: Float { outerRadius }

    var key: Key { Key(family: family, outerRadius: outerRadius, thickness: thickness) }

    /// The profile for a family at the legacy plate's outer radius and thickness (the physics
    /// shapes and the bar layout use those, so they never change). Hubs stand 1.5 to 3 mm proud of
    /// the faces, like the legacy chrome bore ring.
    static func make(family: LathePlateFamily, outerRadius R: Float, thickness T: Float, boreRadius rb: Float) -> LatheProfile {
        let t = T / 2
        // Radii scale with the plate so a smaller plate (the starter) keeps its proportions.
        let k = R / 0.22
        let corners: [LatheProfileCorner]
        let slots: [UInt32]
        let body = LatheSlot.body, hub = LatheSlot.hub, face = LatheSlot.face
        switch family {
        case .bumper:
            corners = [
                LatheProfileCorner(r: rb, y: 0),
                LatheProfileCorner(r: rb, y: t + 0.002, fillet: 0.0015, segments: 2),
                LatheProfileCorner(r: 0.054 * k, y: t + 0.002, fillet: 0.0015, segments: 2),
                LatheProfileCorner(r: 0.054 * k, y: t - 0.003),
                LatheProfileCorner(r: 0.176 * k, y: t - 0.003, fillet: 0.003, segments: 2),
                LatheProfileCorner(r: 0.186 * k, y: t, fillet: 0.003, segments: 2),
                LatheProfileCorner(r: R, y: t, fillet: 0.009, segments: 4),
                LatheProfileCorner(r: R, y: 0),
            ]
            slots = [hub, hub, hub, face, body, body, body]
        case .competition:
            corners = [
                LatheProfileCorner(r: rb, y: 0),
                LatheProfileCorner(r: rb, y: t + 0.0015, fillet: 0.0012, segments: 2),
                LatheProfileCorner(r: 0.060 * k, y: t + 0.0015, fillet: 0.0012, segments: 2),
                LatheProfileCorner(r: 0.060 * k, y: t - 0.002),
                LatheProfileCorner(r: 0.168 * k, y: t - 0.002, fillet: 0.002, segments: 2),
                LatheProfileCorner(r: 0.176 * k, y: t, fillet: 0.002, segments: 2),
                LatheProfileCorner(r: R, y: t, fillet: 0.005, segments: 3),
                LatheProfileCorner(r: R, y: 0),
            ]
            slots = [hub, hub, hub, face, body, body, body]
        case .castIron:
            corners = [
                LatheProfileCorner(r: rb, y: 0),
                LatheProfileCorner(r: rb, y: t + 0.003, fillet: 0.0015, segments: 2),
                LatheProfileCorner(r: 0.058 * k, y: t + 0.003, fillet: 0.003, segments: 3),
                LatheProfileCorner(r: 0.072 * k, y: t - 0.008, fillet: 0.003, segments: 2, slot: hub),
                LatheProfileCorner(r: 0.170 * k, y: t - 0.008, fillet: 0.003, segments: 2),
                LatheProfileCorner(r: 0.186 * k, y: t, fillet: 0.003, segments: 2),
                LatheProfileCorner(r: R, y: t, fillet: 0.006, segments: 4),
                LatheProfileCorner(r: R, y: 0),
            ]
            slots = [hub, hub, hub, face, body, body, body]
        case .machined:
            corners = [
                LatheProfileCorner(r: rb, y: 0),
                LatheProfileCorner(r: rb, y: t + 0.0015, fillet: 0.001, segments: 2),
                LatheProfileCorner(r: 0.056 * k, y: t + 0.0015, fillet: 0.0015, segments: 2),
                LatheProfileCorner(r: 0.060 * k, y: t - 0.004, fillet: 0.0015, segments: 2, slot: hub),
                LatheProfileCorner(r: 0.172 * k, y: t - 0.004, fillet: 0.0015, segments: 2),
                LatheProfileCorner(r: 0.180 * k, y: t, fillet: 0.0015, segments: 2),
                LatheProfileCorner(r: R, y: t, fillet: 0.004, segments: 3),
                LatheProfileCorner(r: R, y: 0),
            ]
            slots = [hub, hub, hub, face, body, body, body]
        }
        return LatheProfile(family: family, outerRadius: R, thickness: T, boreRadius: rb,
                            corners: corners, edgeSlots: slots)
    }
}

// MARK: - Profile loop

/// One straight piece of the closed profile with the shading normals at its ends. Pieces of a
/// rounded corner carry interpolated normals (smooth); a crease is two pieces meeting with
/// different normals.
nonisolated struct LatheProfileSegment: Equatable, Sendable {
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
    var n0: SIMD2<Float>
    var n1: SIMD2<Float>
    var slot: UInt32
    /// Arc length along the whole loop at each end, 0 to 1 (the lathe V coordinate).
    var v0: Float = 0
    var v1: Float = 0
}

nonisolated enum LatheGeometry {
    /// Outward normal of a profile edge running along `d` (r, y). The loop runs out over the top
    /// face, down the rim, back over the bottom face and up the bore, so outward is left of travel.
    static func outwardNormal(_ d: SIMD2<Float>) -> SIMD2<Float> { SIMD2(-d.y, d.x) }

    /// The full closed loop: the top half, the mirrored bottom half, back to the start.
    static func loopCorners(_ profile: LatheProfile) -> (corners: [LatheProfileCorner], edgeSlots: [UInt32]) {
        let top = profile.corners
        let m = top.count - 1
        var corners = top
        var slots = profile.edgeSlots
        // Bottom half: mirror of the top, walked back from the rim to the bore.
        for j in stride(from: m - 1, through: 1, by: -1) {
            var c = top[j]
            c.y = -c.y
            corners.append(c)
        }
        for j in stride(from: m - 1, through: 0, by: -1) {
            slots.append(profile.edgeSlots[j])
        }
        return (corners, slots)
    }

    /// Straight and rounded pieces of the closed loop, in order, each piece's end the next one's start.
    static func segments(_ profile: LatheProfile) -> [LatheProfileSegment] {
        let (corners, edgeSlots) = loopCorners(profile)
        let n = corners.count
        let points = corners.map { SIMD2<Float>($0.r, $0.y) }

        // Each corner becomes either its own point (crease or straight) or an arc of samples.
        var arcs: [[(p: SIMD2<Float>, n: SIMD2<Float>)]?] = Array(repeating: nil, count: n)
        for i in 0..<n {
            let corner = corners[i]
            guard corner.fillet > 0 else { continue }
            let prev = points[(i - 1 + n) % n], c = points[i], next = points[(i + 1) % n]
            arcs[i] = fillet(prev: prev, corner: c, next: next, radius: corner.fillet, segments: max(1, corner.segments))
        }

        var result: [LatheProfileSegment] = []
        for i in 0..<n {
            let j = (i + 1) % n
            let start = arcs[i]?.last?.p ?? points[i]
            let end = arcs[j]?.first?.p ?? points[j]
            let d = end - start
            if simd_length(d) > 1e-6 {
                let normal = outwardNormal(simd_normalize(d))
                result.append(LatheProfileSegment(p0: start, p1: end, n0: normal, n1: normal, slot: edgeSlots[i]))
            }
            if let arc = arcs[j] {
                let slot = corners[j].slot ?? edgeSlots[j]
                for k in 0..<(arc.count - 1) where simd_length(arc[k + 1].p - arc[k].p) > 1e-7 {
                    result.append(LatheProfileSegment(p0: arc[k].p, p1: arc[k + 1].p, n0: arc[k].n, n1: arc[k + 1].n, slot: slot))
                }
            }
        }
        // V: arc length along the loop.
        let total = result.reduce(Float(0)) { $0 + simd_length($1.p1 - $1.p0) }
        var run: Float = 0
        for k in result.indices {
            result[k].v0 = run / total
            run += simd_length(result[k].p1 - result[k].p0)
            result[k].v1 = run / total
        }
        return result
    }

    /// A round of `radius` tangent to both edges at `corner`, sampled with outward normals. The
    /// tangent length is capped so a round never eats more than 45 % of either edge.
    static func fillet(prev: SIMD2<Float>, corner c: SIMD2<Float>, next: SIMD2<Float>,
                       radius: Float, segments: Int) -> [(p: SIMD2<Float>, n: SIMD2<Float>)]? {
        let inLength = simd_length(c - prev), outLength = simd_length(next - c)
        guard inLength > 1e-6, outLength > 1e-6 else { return nil }
        let dIn = (c - prev) / inLength, dOut = (next - c) / outLength
        let cosTurn = max(-1, min(1, simd_dot(dIn, dOut)))
        let turn = acos(cosTurn)
        guard turn > 1e-3 else { return nil }
        var r = radius
        var tangentLength = r * tan(turn / 2)
        let cap = 0.45 * min(inLength, outLength)
        if tangentLength > cap {
            tangentLength = cap
            r = tangentLength / tan(turn / 2)
        }
        let start = c - dIn * tangentLength
        let nIn = outwardNormal(dIn), nOut = outwardNormal(dOut)
        // A right turn (clockwise) is a convex corner: the centre lies inside the material.
        let convex = (dIn.x * dOut.y - dIn.y * dOut.x) < 0
        let s: Float = convex ? 1 : -1
        let centre = start - nIn * r * s
        let a0 = atan2(nIn.y, nIn.x)
        var delta = atan2(nOut.y, nOut.x) - a0
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return (0...segments).map { k in
            let a = a0 + delta * Float(k) / Float(segments)
            let n = SIMD2<Float>(cos(a), sin(a))
            return (centre + n * r * s, n)
        }
    }
}

// MARK: - Mesh data

/// Vertex and index buffers of a revolved plate, ready for a MeshDescriptor.
nonisolated struct LatheMeshData: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var tangents: [SIMD3<Float>] = []
    var bitangents: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    /// Material slot per triangle.
    var triangleSlots: [UInt32] = []

    var triangleCount: Int { indices.count / 3 }

    /// Angular steps around the axis: 80 keeps the silhouette within 0.2 mm of a circle at the
    /// 22 cm radius and the triangle count inside the 3k to 8k budget.
    static let defaultAngularSegments = 80

    /// Revolves the profile. Lathe UVs on body and hub: u around the axis (0 to 1), v along the
    /// profile (0 to 1), so concentric and turned textures follow the shape. Planar UVs on the face
    /// slot: the plate disc seen face on from outside, upright when the plate hangs on the bar.
    static func revolve(_ profile: LatheProfile, angularSegments: Int = defaultAngularSegments) -> LatheMeshData {
        var data = LatheMeshData()
        let segments = LatheGeometry.segments(profile)
        let steps = max(8, angularSegments)
        let faceScale = 1 / (2 * profile.faceUVRadius)
        data.positions.reserveCapacity(segments.count * (steps + 1) * 2)
        for segment in segments {
            let base = UInt32(data.positions.count)
            let isFace = segment.slot == LatheSlot.face
            // On the bar the plate's local x points up and local z is depth, and the outward face
            // is +y on the left sleeve, -y on the right. Seen from outside, up is +x and right is
            // +z on the +y face, -z on the -y face: lettering reads upright from either side.
            let side: Float = (segment.p0.y + segment.p1.y) >= 0 ? 1 : -1
            for j in 0...steps {
                let a = Float(j) / Float(steps) * 2 * .pi
                let c = cos(a), s = sin(a)
                let around = SIMD3<Float>(-s, 0, c)
                for (p, n, v) in [(segment.p0, segment.n0, segment.v0), (segment.p1, segment.n1, segment.v1)] {
                    let position = SIMD3<Float>(p.x * c, p.y, p.x * s)
                    let normal = simd_normalize(SIMD3<Float>(n.x * c, n.y, n.x * s))
                    data.positions.append(position)
                    data.normals.append(normal)
                    if isFace {
                        data.uvs.append(SIMD2(0.5 + side * position.z * faceScale, 0.5 + position.x * faceScale))
                        data.tangents.append(SIMD3(0, 0, side))
                        data.bitangents.append(SIMD3(1, 0, 0))
                    } else {
                        // Along the profile: the edge direction, left of the outward normal.
                        let d = SIMD2<Float>(n.y, -n.x)
                        data.uvs.append(SIMD2(Float(j) / Float(steps), v))
                        data.tangents.append(around)
                        data.bitangents.append(simd_normalize(SIMD3<Float>(d.x * c, d.y, d.x * s)))
                    }
                }
            }
            for j in 0..<steps {
                let v00 = base + UInt32(2 * j), v10 = v00 + 1
                let v01 = base + UInt32(2 * (j + 1)), v11 = v01 + 1
                data.indices += [v00, v01, v10, v01, v11, v10]
                data.triangleSlots += [segment.slot, segment.slot]
            }
        }
        return data
    }
}
