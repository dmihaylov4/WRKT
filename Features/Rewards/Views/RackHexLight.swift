// Features/Rewards/Views/RackHexLight.swift
//
// The honeycomb LED light of a garage or home gym: thin bright white tubes forming a grid of
// connected hexagons. Built procedurally as one mesh (every tube merged) with one unlit material,
// so the whole fixture is a single draw. RackRoomMood places it on the back wall, on the ceiling
// over the bar, or both, and hangs the room's one shadowed light at it.
//
// The pay-off is the reflection: RealityKit lights metal from the environment map, which knows
// nothing of the fixture's mesh, so the same honeycomb is painted into the studio panorama in
// the direction the plates and bar see it (RackHexReflection). Both are built once.

import RealityKit
import simd
import UIKit

/// Where the honeycomb hangs. Also the mood's variant (VOLIA_RACK_MOOD).
nonisolated enum RackHexPlacement: String, CaseIterable, Sendable {
    /// On the back wall behind the bar, above the sign.
    case wall
    /// On the ceiling over the bar, its front edge at the top of the frame.
    case ceiling
    /// A smaller panel on each.
    case both

    var hasWall: Bool { self != .ceiling }
    var hasCeiling: Bool { self != .wall }
}

/// A flat-topped honeycomb: `columns` columns of `rows` cells, odd columns raised half a cell,
/// centred on the origin. An odd column count keeps it symmetric about x 0, so the two sleeves
/// see mirror images.
nonisolated struct RackHexGrid: Hashable, Sendable {
    var columns: Int
    var rows: Int
    /// Centre to corner, in the grid's units.
    var radius: Float

    var apothem: Float { radius * Float(3).squareRoot() / 2 }

    /// Cell centres, centred on the origin.
    var centres: [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        for c in 0..<columns {
            for r in 0..<rows {
                points.append(SIMD2(Float(c) * 1.5 * radius, Float(r) * 2 * apothem + (c % 2 == 1 ? apothem : 0)))
            }
        }
        guard !points.isEmpty else { return [] }
        let low = points.reduce(points[0], simd_min), high = points.reduce(points[0], simd_max)
        let mid = (low + high) / 2
        return points.map { $0 - mid }
    }

    /// Half the size of the box around every tube centre line.
    var halfExtent: SIMD2<Float> {
        let c = centres
        guard let first = c.first else { return .zero }
        let high = c.reduce(simd_abs(first)) { simd_max($0, simd_abs($1)) }
        return high + SIMD2(radius, apothem)
    }

    /// Every tube once: the cells' sides with shared sides merged.
    var edges: [(SIMD2<Float>, SIMD2<Float>)] {
        var seen = Set<SIMD4<Int32>>()
        var result: [(SIMD2<Float>, SIMD2<Float>)] = []
        func key(_ p: SIMD2<Float>) -> SIMD2<Int32> { SIMD2(Int32((p.x * 10_000).rounded()), Int32((p.y * 10_000).rounded())) }
        for centre in centres {
            let corners = (0..<6).map { k -> SIMD2<Float> in
                let angle = Float(k) * .pi / 3
                return centre + radius * SIMD2(cos(angle), sin(angle))
            }
            for k in 0..<6 {
                let a = corners[k], b = corners[(k + 1) % 6]
                let ka = key(a), kb = key(b)
                let edge = (ka.x, ka.y) < (kb.x, kb.y) ? SIMD4(ka.x, ka.y, kb.x, kb.y) : SIMD4(kb.x, kb.y, ka.x, ka.y)
                if seen.insert(edge).inserted { result.append((a, b)) }
            }
        }
        return result
    }

    /// Distance from `p` to the nearest tube centre line (exact inside the grid, close outside).
    func distanceToTubes(_ p: SIMD2<Float>, centres: [SIMD2<Float>]) -> Float {
        let c30: Float = Float(3).squareRoot() / 2
        var best = Float.greatestFiniteMagnitude
        for centre in centres {
            let q = p - centre
            // The hexagon's own distance: its three side normals point at 30, 90 and 150 degrees.
            let d = max(abs(q.y), abs(q.x * c30 + q.y * 0.5), abs(-q.x * c30 + q.y * 0.5))
            best = min(best, abs(d - apothem))
        }
        return best
    }
}

/// One honeycomb panel in the room: a grid, where its centre is and which way it faces.
nonisolated struct RackHexFixture: Equatable, Sendable {
    var grid: RackHexGrid
    var centre: SIMD3<Float>
    /// Wall panels face the viewer (+z); ceiling panels face down.
    var onCeiling: Bool
    /// Tube radius in metres.
    var tubeRadius: Float

    /// The grid's 2D point placed in the room.
    func place(_ p: SIMD2<Float>) -> SIMD3<Float> {
        onCeiling ? centre + SIMD3(p.x, 0, p.y) : centre + SIMD3(p.x, p.y, 0)
    }

    var normal: SIMD3<Float> { onCeiling ? SIMD3(0, -1, 0) : SIMD3(0, 0, 1) }

    /// Wall panel: above the sign, behind the bar. Ceiling panel: over the bar, its front edge at
    /// the top of the frame. `both` hangs a smaller one of each.
    static func fixtures(for placement: RackHexPlacement) -> [RackHexFixture] {
        let small = placement == .both
        var result: [RackHexFixture] = []
        if placement.hasWall {
            result.append(RackHexFixture(grid: RackHexGrid(columns: small ? 9 : 11, rows: 2, radius: small ? 0.065 : 0.075),
                                         centre: SIMD3(0, small ? 1.30 : 1.31, -0.094), onCeiling: false, tubeRadius: 0.0065))
        }
        if placement.hasCeiling {
            result.append(RackHexFixture(grid: RackHexGrid(columns: small ? 5 : 7, rows: small ? 2 : 3, radius: small ? 0.11 : 0.12),
                                         centre: SIMD3(0, 1.44, small ? 0.38 : 0.36), onCeiling: true, tubeRadius: 0.009))
        }
        return result
    }

    /// Tube centre lines in the room.
    var segments: [(SIMD3<Float>, SIMD3<Float>)] {
        grid.edges.map { (place($0.0), place($0.1)) }
    }
}

enum RackHexLight {
    /// Sides of each tube's cross-section.
    static let tubeSides = 6

    /// Positions, normals and triangle indices for `fixtures`' tubes: a six-sided prism per
    /// tube, each a little longer than its side so the joints close.
    nonisolated static func tubeGeometry(_ fixtures: [RackHexFixture]) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for fixture in fixtures {
            let t = fixture.tubeRadius
            for (a, b) in fixture.segments {
                let axis = simd_normalize(b - a)
                let side = simd_normalize(simd_cross(axis, fixture.normal))
                let start = a - axis * t * 0.6, end = b + axis * t * 0.6
                let base = UInt32(positions.count)
                for k in 0..<tubeSides {
                    let angle = Float(k) / Float(tubeSides) * 2 * .pi
                    let n = cos(angle) * side + sin(angle) * fixture.normal
                    positions.append(start + n * t); normals.append(n)
                    positions.append(end + n * t); normals.append(n)
                }
                for k in 0..<UInt32(tubeSides) {
                    let k2 = (k + 1) % UInt32(tubeSides)
                    let s0 = base + k * 2, e0 = s0 + 1, s1 = base + k2 * 2, e1 = s1 + 1
                    indices += [s0, s1, e1, s0, e1, e0]
                }
            }
        }
        return (positions, normals, indices)
    }

    /// The tubes' surface: white, unlit and outside the tone mapper, so they read as the
    /// brightest thing in the room.
    static func tubeMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white)
        return material
    }

    /// One model for every fixture of a mood: one mesh, one material. Cached per fixture set.
    static func makeEntity(_ fixtures: [RackHexFixture]) -> ModelEntity? {
        guard let mesh = cachedMesh(fixtures) else { return nil }
        let entity = ModelEntity(mesh: mesh, materials: [tubeMaterial()])
        entity.name = "moodHexLight"
        return entity
    }

    private static var meshCache: [[RackHexFixtureKey]: MeshResource] = [:]

    static func cachedMesh(_ fixtures: [RackHexFixture]) -> MeshResource? {
        let key = fixtures.map(RackHexFixtureKey.init)
        if let mesh = meshCache[key] { return mesh }
        let geometry = tubeGeometry(fixtures)
        var descriptor = MeshDescriptor(name: "RackHexLight")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        meshCache[key] = mesh
        return mesh
    }
}

private struct RackHexFixtureKey: Hashable {
    let grid: RackHexGrid
    let centre: SIMD3<Float>
    let onCeiling: Bool
    let tubeRadius: Float
    init(_ fixture: RackHexFixture) {
        grid = fixture.grid; centre = fixture.centre; onCeiling = fixture.onCeiling; tubeRadius = fixture.tubeRadius
    }
}

// MARK: - Reflection

/// The honeycomb painted into the studio panorama, so polished metal reflects it. The
/// environment sits at infinity, so each direction gets what a ray from the bar's centre in that
/// direction would hit: the fixtures are traced from there. Seen from the bar both placements are
/// high overhead (the wall panel hangs 0.7 m above and just behind the bar), which is what the
/// bar and the tops of plate rims reflect; plate faces, seen edge on, reflect the room ahead at
/// the horizon and keep their colour.
nonisolated enum RackHexReflection {
    /// Where the rays start: the bar's centre.
    static let viewpoint = SIMD3<Float>(0, 0.6, 0.12)
    /// Tube radiance (linear, before the scene's environment intensity).
    static let radiance: Float = 16
    /// The studio behind a panel is scaled by this, so the tubes read against dark.
    static let backdrop: Float = 0.2
    /// Tubes are painted wider than they are (a few pixels at 1k), so the prefiltered map keeps
    /// them on polished metal.
    static let widen: Float = 1.8

    /// Paints `placement`'s panels into a linear RGBA float panorama, `width` by `height`, in
    /// RealityKit's layout (column 0 behind the viewer, the middle column ahead, row 0 at the
    /// zenith). Only rows above the horizon are visited. Symmetric about the view axis.
    static func paint(_ placement: RackHexPlacement, into pixels: inout [Float], width w: Int, height h: Int) {
        let tint = SIMD3<Float>(0.96, 0.985, 1.0)
        for fixture in RackHexFixture.fixtures(for: placement) {
            let centres = fixture.grid.centres
            let halfWidth = fixture.tubeRadius * widen, feather = fixture.tubeRadius * widen
            let half = fixture.grid.halfExtent + SIMD2(repeating: halfWidth + feather)
            // The dark surround reaches a little past the tubes and fades out.
            let margin: Float = fixture.grid.radius * 0.8
            for y in 0..<(h / 2) {
                let elevation = (0.5 - (Float(y) + 0.5) / Float(h)) * .pi
                for x in 0..<w {
                    let azimuth = (1 - (Float(x) + 0.5) / Float(w)) * 2 * .pi
                    let d = SIMD3<Float>(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
                    // The ray from the viewpoint to the fixture's plane, in the grid's coordinates.
                    let along = fixture.onCeiling ? d.y : -d.z
                    guard along > 0.05 else { continue }
                    let offset = fixture.onCeiling ? fixture.centre.y - viewpoint.y : viewpoint.z - fixture.centre.z
                    let hit = viewpoint + d * (offset / along) - fixture.centre
                    let p = fixture.onCeiling ? SIMD2(hit.x, hit.z) : SIMD2(hit.x, hit.y)
                    let outside = simd_max(simd_abs(p) - half, .zero)
                    let outsideDistance = simd_length(outside)
                    guard outsideDistance < margin else { continue }
                    let surround = 1 - outsideDistance / margin
                    let dim = 1 - (1 - backdrop) * surround * surround * (3 - 2 * surround)
                    var line: Float = 0
                    if outsideDistance <= 0 {
                        let distance = fixture.grid.distanceToTubes(p, centres: centres)
                        line = max(0, min(1, 1 - (distance - halfWidth) / feather))
                    }
                    let i = (y * w + x) * 4
                    for c in 0..<3 {
                        pixels[i + c] = pixels[i + c] * dim + radiance * tint[c] * line
                    }
                }
            }
        }
    }
}
