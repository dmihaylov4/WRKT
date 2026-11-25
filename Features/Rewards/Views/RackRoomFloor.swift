// Features/Rewards/Views/RackRoomFloor.swift
//
// The home gym mood's floor: real gym flooring instead of a smooth slab with raised strips.
// - tiles (default): matte charcoal rubber tiles with EPDM flecks, each tile a touch lighter or
//   darker than its neighbours, the joints where the old floor lines were (x 0.24 + 0.48 k, z
//   -0.15 + 0.8 k), so the lines the owner liked are now the gaps between tiles;
// - platform: a lifting platform, oak planks in the middle (|x| < 0.72) and rubber either side,
//   the same joints running across.
// VOLIA_RACK_FLOOR=tiles|platform picks one in debug builds.
//
// The textures (colour, normal) are drawn once per process off the main thread and shared. The
// mesh is one quad with texture coordinates in floor metres over the texture's period.

import CoreGraphics
import Foundation
import RealityKit
import simd
import UIKit

nonisolated enum RackFloorStyle: String, CaseIterable, Sendable {
    case tiles
    case platform

    static let defaultStyle: RackFloorStyle = .tiles

    static func resolve(_ value: String?) -> RackFloorStyle {
        value.flatMap(RackFloorStyle.init(rawValue:)) ?? defaultStyle
    }

    static var current: RackFloorStyle {
        #if DEBUG
        return resolve(ProcessInfo.processInfo.environment["VOLIA_RACK_FLOOR"])
        #else
        return defaultStyle
        #endif
    }
}

nonisolated enum RackRoomFloorArt {
    /// 768 pixels over 1.92 m by 1.6 m: 2 to 2.5 mm a pixel.
    static let side = 768
    /// Rubber tile size: the old floor lines' spacing.
    static let tile = SIMD2<Float>(0.48, 0.80)
    /// Where a joint runs: x 0.24 + 0.48 k and z -0.15 + 0.8 k (the old strips and seams).
    static let jointOrigin = SIMD2<Float>(0.24, -0.15)
    static let jointHalfWidth: Float = 0.0045
    /// The platform's oak centre reaches this far either side of the bar's middle.
    static let platformHalfWidth: Float = 0.72
    static let plankWidth: Float = 0.12

    /// Metres of floor the texture covers, and the floor point at texture coordinate (0, 0).
    static func period(_ style: RackFloorStyle) -> (size: SIMD2<Float>, origin: SIMD2<Float>) {
        switch style {
        // Four tiles across and two deep, starting on a joint.
        case .tiles: return (SIMD2(tile.x * 4, tile.y * 2), jointOrigin)
        // The whole platform across (oak centre and a rubber band either side), centred.
        case .platform: return (SIMD2(platformHalfWidth * 4, tile.y * 2), SIMD2(-platformHalfWidth * 2, jointOrigin.y))
        }
    }

    struct Images: @unchecked Sendable {
        let color: CGImage
        let normal: CGImage
    }

    static func hash(_ i: Int, _ j: Int, _ seed: Int = 0) -> Float {
        var h = UInt32(truncatingIfNeeded: i &* 73_856_093 ^ j &* 19_349_663 ^ seed &* 83_492_791)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65_535
    }

    /// Smooth value noise in 0...1, `cell` pixels per lattice step, wrapping every `period` pixels.
    static func valueNoise(_ x: Int, _ y: Int, cell: Int, period: Int, seed: Int) -> Float {
        let cells = max(1, period / cell)
        let fx = Float(x) / Float(cell), fy = Float(y) / Float(cell)
        let x0 = Int(fx), y0 = Int(fy)
        let tx = fx - Float(x0), ty = fy - Float(y0)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = hash(x0 % cells, y0 % cells, seed), b = hash((x0 + 1) % cells, y0 % cells, seed)
        let c = hash(x0 % cells, (y0 + 1) % cells, seed), d = hash((x0 + 1) % cells, (y0 + 1) % cells, seed)
        let top = a + (b - a) * sx, bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    /// The style's images: from the disk cache when this build drew them before, else drawn and
    /// stored (about 0.4 s in a debug build on the simulator, so drawn once per install).
    static func images(_ style: RackFloorStyle, diskCache: Bool = true) -> Images? {
        let n = side
        let url = RackAssetDiskCache.fileURL(kind: "floor", identity: "\(style.rawValue)|\(n)")
        let bytesPerImage = n * n * 4
        if diskCache, let data = RackAssetDiskCache.read(url), data.count == bytesPerImage * 2 {
            let bytes = [UInt8](data)
            return images(color: Array(bytes[0..<bytesPerImage]), normal: Array(bytes[bytesPerImage...]))
        }
        let drawn = pixels(style)
        if diskCache { RackAssetDiskCache.write(Data(drawn.color + drawn.normal), to: url) }
        return images(color: drawn.color, normal: drawn.normal)
    }

    static func images(color: [UInt8], normal: [UInt8]) -> Images? {
        guard let colorImage = LatheFaceArt.rgbaImage(color, side: side, space: CGColorSpace(name: CGColorSpace.sRGB)),
              let normalImage = LatheFaceArt.rgbaImage(normal, side: side, space: CGColorSpaceCreateDeviceRGB()) else { return nil }
        return Images(color: colorImage, normal: normalImage)
    }

    /// sRGB colour and tangent-space normal bytes (RGBA), `side` pixels square, covering `period`.
    static func pixels(_ style: RackFloorStyle) -> (color: [UInt8], normal: [UInt8]) {
        let n = side
        let (size, origin) = period(style)
        var color = [UInt8](repeating: 255, count: n * n * 4)
        var height = [Float](repeating: 0, count: n * n)
        let rubber = SIMD3<Float>(0.135, 0.135, 0.14)
        let fleckGrey = SIMD3<Float>(0.34, 0.34, 0.35)
        let oak = SIMD3<Float>(0.46, 0.33, 0.21)
        for py in 0..<n {
            // Texture v runs up the image: row 0 is the end of the period nearest the viewer (largest z).
            let z = origin.y + (1 - (Float(py) + 0.5) / Float(n)) * size.y
            for px in 0..<n {
                let x = origin.x + (Float(px) + 0.5) / Float(n) * size.x
                let i = py * n + px
                // Joints across (every tile depth) and along (tile width, or the platform's edges).
                let rz = (z - jointOrigin.y) / tile.y
                let jz = abs(rz - rz.rounded()) * tile.y
                let onPlatformWood = style == .platform && abs(x) < platformHalfWidth
                let jx: Float
                if style == .platform {
                    let edge = abs(abs(x) - platformHalfWidth)
                    if onPlatformWood {
                        let rp = x / plankWidth
                        jx = min(edge, abs(rp - rp.rounded()) * plankWidth)
                    } else {
                        jx = edge
                    }
                } else {
                    let rx = (x - jointOrigin.x) / tile.x
                    jx = abs(rx - rx.rounded()) * tile.x
                }
                let joint = min(jx, onPlatformWood ? jx : jz)
                // 0 in the joint, 1 on the tile, a soft 3 mm bevel between.
                let open = max(0, min(1, (joint - jointHalfWidth) / 0.003))
                var c: SIMD3<Float>
                var h: Float = 0
                if onPlatformWood {
                    // Oak planks: per plank tone, long grain streaks.
                    let plank = Int(((x + platformHalfWidth) / plankWidth).rounded(.down))
                    let tone = 0.88 + 0.24 * hash(plank, 7, 3)
                    let grain = valueNoise(px * 6, py / 3, cell: 48, period: n * 6, seed: 11)
                    let fine = valueNoise(px * 12, py, cell: 16, period: n * 12, seed: 12)
                    c = oak * tone * (0.82 + 0.22 * grain + 0.08 * fine)
                    h = 0.15 * fine
                } else {
                    // Rubber: per tile tone, broad mottling and EPDM flecks a few millimetres across.
                    let tx = Int(((x - jointOrigin.x) / tile.x).rounded(.down)) & 1023
                    let tz = Int(((z - jointOrigin.y) / tile.y).rounded(.down)) & 1023
                    let tone = 0.93 + 0.14 * hash(tx, tz, 1)
                    let mottle = valueNoise(px, py, cell: 64, period: n, seed: 2)
                    let fleckCell = hash(px / 2, py / 2, 4)
                    let fleck: Float = fleckCell > 0.90 ? (fleckCell - 0.90) * 10 : 0
                    c = rubber * tone * (0.94 + 0.12 * mottle)
                    c = c + (fleckGrey - c) * (fleck * 0.55)
                    h = 0.35 * (hash(px, py, 5) - 0.5) + 0.4 * fleck
                }
                // Joints: dark gaps, a couple of pixels below the surface.
                c = c * (0.30 + 0.70 * open)
                h += -2.0 * (1 - open)
                color[i * 4] = UInt8(max(0, min(255, c.x * 255)))
                color[i * 4 + 1] = UInt8(max(0, min(255, c.y * 255)))
                color[i * 4 + 2] = UInt8(max(0, min(255, c.z * 255)))
                height[i] = h
            }
        }
        // Normals from the height field (heights in pixels), wrapping at the edges; image rows
        // run down while v runs up, as in LatheFaceArt.normalMap.
        var normal = [UInt8](repeating: 255, count: n * n * 4)
        let strength: Float = 0.6
        for y in 0..<n {
            for x in 0..<n {
                let dx = (height[y * n + (x + 1) % n] - height[y * n + (x - 1 + n) % n]) * 0.5 * strength
                let dy = (height[((y - 1 + n) % n) * n + x] - height[((y + 1) % n) * n + x]) * 0.5 * strength
                let v = simd_normalize(SIMD3<Float>(-dx, -dy, 1))
                let i = (y * n + x) * 4
                normal[i] = UInt8(max(0, min(255, (v.x * 0.5 + 0.5) * 255)))
                normal[i + 1] = UInt8(max(0, min(255, (v.y * 0.5 + 0.5) * 255)))
                normal[i + 2] = UInt8(max(0, min(255, (v.z * 0.5 + 0.5) * 255)))
            }
        }
        return (color, normal)
    }
}

/// Carries finished images out of the drawing task.
private struct RackFloorImagesBox: @unchecked Sendable {
    let images: RackRoomFloorArt.Images?
}

@MainActor
enum RackRoomFloor {
    private static var tasks: [RackFloorStyle: Task<PhysicallyBasedMaterial?, Never>] = [:]
    private static var materials: [RackFloorStyle: PhysicallyBasedMaterial] = [:]

    /// Draws the style's textures off the main thread and builds the material, once per process.
    static func prepare(_ style: RackFloorStyle) async {
        if materials[style] != nil { return }
        let task = tasks[style] ?? Task { @MainActor () -> PhysicallyBasedMaterial? in
            let box = await Task.detached(priority: .userInitiated) { RackFloorImagesBox(images: RackRoomFloorArt.images(style)) }.value
            guard let images = box.images,
                  let color = try? await TextureResource(image: images.color, options: .init(semantic: .color)),
                  let normal = try? await TextureResource(image: images.normal, options: .init(semantic: .normal)) else { return nil }
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: texture(color))
            material.normal = .init(texture: texture(normal))
            // Matte rubber and oiled oak: a soft broad highlight at most.
            material.roughness = .init(floatLiteral: 0.88)
            material.metallic = .init(floatLiteral: 0)
            material.specular = .init(floatLiteral: 0.30)
            return material
        }
        tasks[style] = task
        if let material = await task.value { materials[style] = material }
    }

    /// The prepared floor, or nil when prepare has not finished or failed (the scene then keeps
    /// the plain floor).
    static func makeEntity(_ style: RackFloorStyle) -> ModelEntity? {
        guard let material = materials[style], let mesh = cachedMesh(style) else { return nil }
        let floor = ModelEntity(mesh: mesh, materials: [material])
        floor.name = "moodFloor"
        return floor
    }

    /// The floor's extent: wide past the frame, from the wall to past the camera.
    static let extent = (minX: Float(-6), maxX: Float(6), minZ: Float(-0.125), maxZ: Float(3.0))
    /// The floor's top, where the plain floor's top was.
    static let height: Float = -0.002

    private static var meshes: [RackFloorStyle: MeshResource] = [:]

    static func cachedMesh(_ style: RackFloorStyle) -> MeshResource? {
        if let mesh = meshes[style] { return mesh }
        let (size, origin) = RackRoomFloorArt.period(style)
        let e = extent
        let corners = [SIMD2<Float>(e.minX, e.maxZ), SIMD2(e.maxX, e.maxZ), SIMD2(e.maxX, e.minZ), SIMD2(e.minX, e.minZ)]
        var descriptor = MeshDescriptor(name: "RackRoomFloor")
        descriptor.positions = MeshBuffers.Positions(corners.map { SIMD3($0.x, height, $0.y) })
        descriptor.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: 4))
        descriptor.tangents = MeshBuffers.Tangents(Array(repeating: SIMD3<Float>(1, 0, 0), count: 4))
        // Texture v runs toward the viewer (+z), matching the art (row 0 is the near end).
        descriptor.bitangents = MeshBuffers.Tangents(Array(repeating: SIMD3<Float>(0, 0, 1), count: 4))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(corners.map {
            SIMD2(($0.x - origin.x) / size.x, ($0.y - origin.y) / size.y)
        })
        // Front face up: counter-clockwise seen from above.
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        meshes[style] = mesh
        return mesh
    }

    private static func texture(_ resource: TextureResource) -> MaterialParameters.Texture {
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            descriptor.maxAnisotropy = 16
        }
        return MaterialParameters.Texture(resource, sampler: sampler)
    }
}
