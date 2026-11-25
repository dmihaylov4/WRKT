// Features/Rewards/Views/RackHexLight.swift
//
// The honeycomb LED light of a garage or home gym: thick bright white tubes forming a grid of
// big connected hexagons. The default covers the back wall behind the rack, the VOLIA sign in
// the middle cell. Built procedurally: every tube merged into one mesh with one unlit material,
// and a second mesh of soft-edged quads behind the tubes (one unlit, alpha-faded material) that
// fakes the glow RealityKit on iOS has no bloom for. Both are built once and cached.
//
// RealityKit lights metal from the environment map, which knows nothing of the fixture's mesh, so
// the same honeycomb is painted into the studio panorama in the direction it really is
// (RackHexReflection).

import RealityKit
import simd
import UIKit

/// Where the honeycomb hangs. Also the mood's variant (VOLIA_RACK_MOOD).
nonisolated enum RackHexPlacement: String, CaseIterable, Sendable {
    /// Big cells over the whole back wall, from behind the stands to above the frame, past both
    /// sleeves; the sign sits in the middle cell.
    case wall
    /// The same big cells from just above the plates up, framing the sign; nothing behind the bar.
    case wallHigh
    /// The earlier small panel of thin tubes above the sign.
    case panel
    /// The earlier panel on the ceiling over the bar.
    case ceiling
}

/// A flat-topped honeycomb as a set of cells on the hexagonal lattice (axial coordinates: column
/// `q`, and `r` running up the column), cell centre (1.5 q, sqrt3 (r + q/2)) times the radius,
/// plus `origin`. Odd columns sit half a cell up, so a grid whose cells are mirrored in q is
/// symmetric about x 0: the two sleeves see mirror images.
nonisolated struct RackHexGrid: Hashable, Sendable {
    /// Centre to corner, in the grid's units.
    var radius: Float
    /// Axial coordinates of every cell.
    var cells: [SIMD2<Int32>]
    var origin: SIMD2<Float> = .zero

    var apothem: Float { radius * Float(3).squareRoot() / 2 }

    /// `columns` columns of `rows` cells, centred on the origin (the earlier panels).
    init(columns: Int, rows: Int, radius: Float) {
        self.radius = radius
        var cells: [SIMD2<Int32>] = []
        for c in 0..<columns {
            for k in 0..<rows { cells.append(SIMD2(Int32(c), Int32(k - c / 2))) }
        }
        self.cells = cells
        let points = cells.map { Self.lattice($0, radius: radius) }
        if let first = points.first {
            let low = points.reduce(first, simd_min), high = points.reduce(first, simd_max)
            origin = -(low + high) / 2
        }
    }

    /// Every cell whose centre lies inside the box, with a cell centred on the origin.
    init(radius: Float, covering box: (min: SIMD2<Float>, max: SIMD2<Float>)) {
        self.radius = radius
        let a = radius * Float(3).squareRoot() / 2
        let qMax = Int32((max(abs(box.min.x), abs(box.max.x)) / (1.5 * radius)).rounded(.up))
        let rReach = Int32((max(abs(box.min.y), abs(box.max.y)) / (2 * a)).rounded(.up)) + qMax
        var cells: [SIMD2<Int32>] = []
        for q in -qMax...qMax {
            for r in -rReach...rReach {
                let c = Self.lattice(SIMD2(q, r), radius: radius)
                if c.x >= box.min.x, c.x <= box.max.x, c.y >= box.min.y, c.y <= box.max.y { cells.append(SIMD2(q, r)) }
            }
        }
        self.cells = cells
    }

    static func lattice(_ cell: SIMD2<Int32>, radius: Float) -> SIMD2<Float> {
        let q = Float(cell.x), r = Float(cell.y)
        return SIMD2(1.5 * q, Float(3).squareRoot() * (r + q / 2)) * radius
    }

    /// Cell centres.
    var centres: [SIMD2<Float>] { cells.map { Self.lattice($0, radius: radius) + origin } }

    /// Half the size of the box around every tube centre line, about the origin of the grid's
    /// coordinates (not `origin`).
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

    static let neighbourhood: [SIMD2<Int32>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1), SIMD2(1, -1), SIMD2(-1, 1)]

    /// The cell whose hexagon holds `p` (cube rounding of the axial coordinates).
    func nearestCell(_ p: SIMD2<Float>) -> SIMD2<Int32> {
        let local = (p - origin) / radius
        let q = local.x * 2 / 3
        let r = -local.x / 3 + local.y / Float(3).squareRoot()
        let s = -q - r
        var rq = q.rounded(), rr = r.rounded()
        let rs = s.rounded()
        let dq = abs(rq - q), dr = abs(rr - r), ds = abs(rs - s)
        if dq > dr, dq > ds { rq = -rr - rs } else if dr > ds { rr = -rq - rs }
        return SIMD2(Int32(rq), Int32(rr))
    }

    /// Which cells are in the grid, as a flat table over the cells' bounding range (a set
    /// lookup per pixel made painting the environment several times slower).
    struct Membership: Sendable {
        let low: SIMD2<Int32>
        let size: SIMD2<Int32>
        let table: [Bool]

        init(_ cells: [SIMD2<Int32>]) {
            let low = cells.reduce(SIMD2<Int32>(repeating: .max)) { simd_min($0, $1) }
            let high = cells.reduce(SIMD2<Int32>(repeating: .min)) { simd_max($0, $1) }
            let size = cells.isEmpty ? .zero : high &- low &+ 1
            var table = [Bool](repeating: false, count: Int(size.x) * Int(size.y))
            for cell in cells {
                let i = cell &- low
                table[Int(i.y) * Int(size.x) + Int(i.x)] = true
            }
            self.low = low; self.size = size; self.table = table
        }

        func contains(_ cell: SIMD2<Int32>) -> Bool {
            let i = cell &- low
            guard i.x >= 0, i.y >= 0, i.x < size.x, i.y < size.y else { return false }
            return table[Int(i.y) * Int(size.x) + Int(i.x)]
        }
    }

    /// Distance from `p` to the nearest tube centre line: the boundary of the cell holding `p`
    /// or of a neighbour in the grid.
    func distanceToTubes(_ p: SIMD2<Float>, members: Membership) -> Float {
        let c30: Float = Float(3).squareRoot() / 2
        let home = nearestCell(p)
        var best = Float.greatestFiniteMagnitude
        for offset in Self.neighbourhood {
            let cell = home &+ offset
            guard members.contains(cell) else { continue }
            let q = p - (Self.lattice(cell, radius: radius) + origin)
            // The hexagon's own distance: its three side normals point at 30, 90 and 150 degrees.
            let d = max(abs(q.y), abs(q.x * c30 + q.y * 0.5), abs(-q.x * c30 + q.y * 0.5))
            best = min(best, abs(d - apothem))
        }
        return best
    }
}

/// One honeycomb in the room: a grid, where its centre is and which way it faces.
nonisolated struct RackHexFixture: Hashable, Sendable {
    var grid: RackHexGrid
    var centre: SIMD3<Float>
    /// Wall panels face the viewer (+z); ceiling panels face down.
    var onCeiling: Bool
    /// Tube radius in metres.
    var tubeRadius: Float
    /// Half the width of the glow around each tube, in metres (0: no glow).
    var glowHalfWidth: Float = 0

    /// The grid's 2D point placed in the room.
    func place(_ p: SIMD2<Float>) -> SIMD3<Float> {
        onCeiling ? centre + SIMD3(p.x, 0, p.y) : centre + SIMD3(p.x, p.y, 0)
    }

    var normal: SIMD3<Float> { onCeiling ? SIMD3(0, -1, 0) : SIMD3(0, 0, 1) }

    /// The sign's centre on the back wall (RackRoomMood.signPosition), which the big grid
    /// centres a cell on.
    static let signCentre = SIMD3<Float>(0, 1.00, -0.098)
    /// Tubes hang just in front of the plate zone panel (face at z -0.103).
    static let wallDepth: Float = -0.084

    /// Big wall: cells about 0.64 m across with 3.4 cm tubes, from behind the stands (cell
    /// centres from 0.35 m) to past the top of the frame and past both edges, the sign in the
    /// middle cell. High wall: the same, from just above the plates. Panel and ceiling: the
    /// earlier small fixtures.
    static func fixtures(for placement: RackHexPlacement) -> [RackHexFixture] {
        switch placement {
        case .wall, .wallHigh:
            let bottom: Float = placement == .wall ? 0.35 : 0.98
            // Box in the grid's coordinates, about the sign.
            let grid = RackHexGrid(radius: 0.32, covering: (SIMD2(-1.50, bottom - signCentre.y), SIMD2(1.50, 2.20 - signCentre.y)))
            return [RackHexFixture(grid: grid, centre: SIMD3(0, signCentre.y, wallDepth), onCeiling: false,
                                   tubeRadius: 0.017, glowHalfWidth: 0.075)]
        case .panel:
            return [RackHexFixture(grid: RackHexGrid(columns: 11, rows: 2, radius: 0.075),
                                   centre: SIMD3(0, 1.31, -0.094), onCeiling: false, tubeRadius: 0.0065)]
        case .ceiling:
            return [RackHexFixture(grid: RackHexGrid(columns: 7, rows: 3, radius: 0.12),
                                   centre: SIMD3(0, 1.44, 0.36), onCeiling: true, tubeRadius: 0.009)]
        }
    }

    /// Tube centre lines in the room.
    var segments: [(SIMD3<Float>, SIMD3<Float>)] {
        grid.edges.map { (place($0.0), place($0.1)) }
    }
}

enum RackHexLight {
    /// Sides of each tube's cross-section.
    static let tubeSides = 6

    struct Geometry {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var triangles: Int { indices.count / 3 }
    }

    /// `fixtures`' tubes: a six-sided prism per tube, each a little longer than its side so the
    /// joints close.
    nonisolated static func tubeGeometry(_ fixtures: [RackHexFixture]) -> Geometry {
        var g = Geometry()
        for fixture in fixtures {
            let t = fixture.tubeRadius
            for (a, b) in fixture.segments {
                let axis = simd_normalize(b - a)
                let side = simd_normalize(simd_cross(axis, fixture.normal))
                let start = a - axis * t * 0.6, end = b + axis * t * 0.6
                let base = UInt32(g.positions.count)
                for k in 0..<tubeSides {
                    let angle = Float(k) / Float(tubeSides) * 2 * .pi
                    let n = cos(angle) * side + sin(angle) * fixture.normal
                    g.positions.append(start + n * t); g.normals.append(n)
                    g.positions.append(end + n * t); g.normals.append(n)
                }
                for k in 0..<UInt32(tubeSides) {
                    let k2 = (k + 1) % UInt32(tubeSides)
                    let s0 = base + k * 2, e0 = s0 + 1, s1 = base + k2 * 2, e1 = s1 + 1
                    g.indices += [s0, s1, e1, s0, e1, e0]
                }
            }
        }
        return g
    }

    /// The glow: one flat quad per tube, lying on the fixture's surface just behind the tube,
    /// `glowHalfWidth` either side of it and past its ends. The texture (glowImage) fades to
    /// nothing across and toward the ends, so overlapping quads at the joints blend.
    nonisolated static func glowGeometry(_ fixtures: [RackHexFixture]) -> Geometry {
        var g = Geometry()
        for fixture in fixtures where fixture.glowHalfWidth > 0 {
            let h = fixture.glowHalfWidth
            let back = -fixture.normal * fixture.tubeRadius * 0.95
            for (a, b) in fixture.segments {
                let axis = simd_normalize(b - a)
                let side = simd_normalize(simd_cross(axis, fixture.normal))
                let start = a - axis * h + back, end = b + axis * h + back
                let base = UInt32(g.positions.count)
                for (p, uv) in [(start - side * h, SIMD2<Float>(0, 0)), (end - side * h, SIMD2(1, 0)),
                                (end + side * h, SIMD2(1, 1)), (start + side * h, SIMD2(0, 1))] {
                    g.positions.append(p); g.normals.append(fixture.normal); g.uvs.append(uv)
                }
                // Wound to face +normal (the viewer).
                g.indices += [base, base + 2, base + 1, base, base + 3, base + 2]
            }
        }
        return g
    }

    /// The tubes' surface: white, unlit and outside the tone mapper, so they read as the
    /// brightest thing in the room.
    static func tubeMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white)
        return material
    }

    /// Peak opacity of the glow right at a tube.
    static let glowPeak: Float = 0.55

    /// The glow's texture: white, its brightness and alpha a soft falloff across the quad
    /// (gaussian about the middle) times a ramp in from each end over the overhang. `along` is
    /// the fraction of the quad's length that is overhang at each end.
    nonisolated static func glowImage(along overhang: Float, width: Int = 128, height: Int = 32) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height) - 0.5
            let across = exp(-pow(v / 0.20, 2)) - exp(-pow(0.5 / 0.20, 2))
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let fromEnd = min(u, 1 - u) / max(overhang, 0.001)
                let ramp = min(1, fromEnd)
                let along = ramp * ramp * (3 - 2 * ramp)
                let value = UInt8(max(0, min(255, glowPeak * across * along * 255)))
                let i = (y * width + x) * 4
                bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value; bytes[i + 3] = value
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The glow's surface: unlit, outside the tone mapper, faded by the texture, never writing
    /// depth (it lies behind everything but the wall, and overlapping quads must not cut each other).
    static func glowMaterial(_ fixture: RackHexFixture) -> UnlitMaterial? {
        let length = fixture.grid.radius + 2 * fixture.glowHalfWidth
        guard let image = glowImage(along: fixture.glowHalfWidth / length),
              let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(scale: 1, texture: .init(texture)))
        material.writesDepth = false
        material.faceCulling = .none
        return material
    }

    /// The tubes (one mesh, one material) and, when the fixtures glow, the glow (one mesh, one
    /// material). Meshes, the glow texture and materials are cached per fixture set.
    static func makeEntities(_ fixtures: [RackHexFixture]) -> [ModelEntity] {
        var result: [ModelEntity] = []
        if let mesh = cachedMesh(fixtures, kind: .tubes) {
            let tubes = ModelEntity(mesh: mesh, materials: [tubeMaterial()])
            tubes.name = "moodHexLight"
            result.append(tubes)
        }
        if let glowing = fixtures.first(where: { $0.glowHalfWidth > 0 }), let mesh = cachedMesh(fixtures, kind: .glow) {
            let key = fixtures
            let material = glowMaterialCache[key] ?? glowMaterial(glowing)
            glowMaterialCache[key] = material
            if let material {
                let glow = ModelEntity(mesh: mesh, materials: [material])
                glow.name = "moodHexGlow"
                result.append(glow)
            }
        }
        return result
    }

    enum MeshKind: Hashable { case tubes, glow }

    private static var meshCache: [MeshCacheKey: MeshResource] = [:]
    private static var glowMaterialCache: [[RackHexFixture]: UnlitMaterial?] = [:]

    private struct MeshCacheKey: Hashable {
        let fixtures: [RackHexFixture]
        let kind: MeshKind
    }

    static func cachedMesh(_ fixtures: [RackHexFixture], kind: MeshKind) -> MeshResource? {
        let key = MeshCacheKey(fixtures: fixtures, kind: kind)
        if let mesh = meshCache[key] { return mesh }
        let geometry = kind == .tubes ? tubeGeometry(fixtures) : glowGeometry(fixtures)
        guard !geometry.indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: kind == .tubes ? "RackHexLight" : "RackHexGlow")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        if !geometry.uvs.isEmpty { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(geometry.uvs) }
        descriptor.primitives = .triangles(geometry.indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        meshCache[key] = mesh
        return mesh
    }
}

// MARK: - Reflection

/// The honeycomb painted into the studio panorama, so polished metal reflects it. The
/// environment sits at infinity, so each direction gets what a ray from one viewpoint in that
/// direction would hit: the fixtures are traced from there. The viewpoint sits over the floor in
/// front of the bar, between the bar and plates lying on the floor, so the wall grid fills the
/// half of the sky ahead the way both see it. The studio behind the grid is turned down so the
/// tubes read against a dark wall; the tubes are painted a little wider than they are so the
/// prefiltered map keeps them on polished metal.
nonisolated enum RackHexReflection {
    static let viewpoint = SIMD3<Float>(0, 0.6, 0.45)
    /// Tube radiance (linear, before the scene's environment intensity).
    static let radiance: Float = 20
    /// The studio behind a grid is scaled by this.
    static let backdrop: Float = 0.1
    static let widen: Float = 1.2

    /// Paints `placement`'s grids into a linear RGBA float panorama, `width` by `height`, in
    /// RealityKit's layout (column 0 behind the viewer, the middle column ahead, row 0 at the
    /// zenith). Symmetric about the view axis.
    static func paint(_ placement: RackHexPlacement, into pixels: inout [Float], width w: Int, height h: Int) {
        let tint = SIMD3<Float>(0.96, 0.985, 1.0)
        for fixture in RackHexFixture.fixtures(for: placement) {
            let members = RackHexGrid.Membership(fixture.grid.cells)
            let halfWidth = fixture.tubeRadius * widen, feather = fixture.tubeRadius * widen
            let extent = fixture.grid.halfExtent
            // The dark surround reaches a little past the tubes and fades out.
            let margin: Float = fixture.grid.radius * 0.8
            let offset = fixture.onCeiling ? fixture.centre.y - viewpoint.y : viewpoint.z - fixture.centre.z
            // Per column and per row trigonometry, computed once.
            let columns = (0..<w).map { x -> SIMD2<Float> in
                let azimuth = (1 - (Float(x) + 0.5) / Float(w)) * 2 * .pi
                return SIMD2(sin(azimuth), cos(azimuth))
            }
            for y in 0..<h {
                let elevation = (0.5 - (Float(y) + 0.5) / Float(h)) * .pi
                let cosE = cos(elevation), sinE = sin(elevation)
                for x in 0..<w {
                    let d = SIMD3<Float>(columns[x].x * cosE, sinE, columns[x].y * cosE)
                    // The ray from the viewpoint to the fixture's plane, in the grid's coordinates.
                    let along = fixture.onCeiling ? d.y : -d.z
                    guard along > 0.05 else { continue }
                    let hit = viewpoint + d * (offset / along) - fixture.centre
                    let p = fixture.onCeiling ? SIMD2(hit.x, hit.z) : SIMD2(hit.x, hit.y)
                    let outsideDistance = simd_length(simd_max(simd_abs(p) - extent, .zero))
                    guard outsideDistance < margin else { continue }
                    let surround = 1 - outsideDistance / margin
                    let dim = 1 - (1 - backdrop) * surround * surround * (3 - 2 * surround)
                    let distance = fixture.grid.distanceToTubes(p, members: members)
                    let line = max(0, min(1, 1 - (distance - halfWidth) / feather))
                    let i = (y * w + x) * 4
                    for c in 0..<3 {
                        pixels[i + c] = pixels[i + c] * dim + radiance * tint[c] * line
                    }
                }
            }
        }
    }
}
