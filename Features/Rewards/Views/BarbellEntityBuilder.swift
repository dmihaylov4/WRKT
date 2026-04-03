// Features/Rewards/Views/BarbellEntityBuilder.swift
import RealityKit
import UIKit

// MARK: - Collision groups
// Plates collide with the floor plane and each other.
// Bar and rack stands have no collision bodies -- snapping is gesture-driven.

let plateCollisionGroup = CollisionGroup(rawValue: 1 << 0)
let floorCollisionGroup = CollisionGroup(rawValue: 1 << 1)
let plateCollisionFilter = CollisionFilter(
    group: plateCollisionGroup,
    mask: plateCollisionGroup.union(floorCollisionGroup)
)

// MARK: - PlateAudioCategory
// Cases defined here so ECS components in this file compile independently.
// Logic (clinkSoundName, dropSoundName, physicsMaterial, from(tierID:)) is in BarbellAudioBuilder.swift extension.

enum PlateAudioCategory {
    case iron, rubber, brass, starter
}

// MARK: - PlateRoleComponent

/// ECS component attached to every plate entity. Distinguishes floor plates
/// (eligible for drag-to-rack) from bar plates (eligible for swipe-to-unrack).
struct PlateRoleComponent: Component {
    enum Role { case floor, bar }
    var role: Role
}

// MARK: - TierIDComponent

/// Stores the plate tier so texture and audio passes can look up data
/// without re-threading tierID through every call site.
struct TierIDComponent: Component {
    let tierID: Int
}

// MARK: - PlateAudioCategoryComponent

/// Stores the audio category so snap handlers can play the correct sound
/// without re-deriving it from tierID at gesture time.
struct PlateAudioCategoryComponent: Component {
    let category: PlateAudioCategory
}

// MARK: - Mesh resource cache
//
// Process-level cache so identical cylinder/box geometries are uploaded to the GPU once.
// Without this, each plate entity calls MeshResource.generateCylinder independently,
// producing duplicate GPU mesh buffers even for same-tier plates.
// Use cachedCylinder / cachedBox throughout all entity builders instead of
// MeshResource.generate* directly.

private nonisolated(unsafe) var meshResourceCache: [String: MeshResource] = [:]

func cachedCylinder(height: Float, radius: Float) -> MeshResource {
    let key = "cyl_h\(height)_r\(radius)"
    if let cached = meshResourceCache[key] { return cached }
    let mesh = MeshResource.generateCylinder(height: height, radius: radius)
    meshResourceCache[key] = mesh
    return mesh
}

func cachedBox(size: SIMD3<Float>) -> MeshResource {
    let key = "box_\(size.x)_\(size.y)_\(size.z)"
    if let cached = meshResourceCache[key] { return cached }
    let mesh = MeshResource.generateBox(size: size)
    meshResourceCache[key] = mesh
    return mesh
}

// MARK: - PlateTextures

struct PlateTextures {
    var albedo: TextureResource?
    var normal: TextureResource?
    var roughness: TextureResource?
    var metalness: TextureResource?
}

// MARK: - PBR helpers

func pbrMaterial(
    color: UIColor,
    metallic: Float,
    roughness: Float,
    clearcoat: Float = 0,
    clearcoatRoughness: Float = 0
) -> PhysicallyBasedMaterial {
    var mat = PhysicallyBasedMaterial()
    mat.baseColor = .init(tint: color)
    mat.metallic = .init(floatLiteral: metallic)
    mat.roughness = .init(floatLiteral: roughness)
    mat.clearcoat = .init(floatLiteral: clearcoat)
    mat.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
    return mat
}

func chromeMaterial() -> PhysicallyBasedMaterial {
    pbrMaterial(color: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12)
}

// MARK: - Texture loading

func loadPlateTextures(forTierID tierID: Int) -> PlateTextures {
    let prefix: String
    switch tierID {
    case 0: prefix = "RustyIron"
    case 1: prefix = "CastIron"
    case 2: prefix = "Rubber"
    case 3, 6: prefix = "Brass"
    default: return PlateTextures()
    }
    return loadBundleTextures(prefix: prefix)
}

private func loadBundleTextures(prefix: String) -> PlateTextures {
    func load(_ suffix: String, semantic: TextureResource.Semantic) -> TextureResource? {
        let name = "\(prefix)_\(suffix)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let uiImage = UIImage(contentsOfFile: url.path),
              let sourceCG = uiImage.cgImage else { return nil }
        let w = sourceCG.width, h = sourceCG.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let rgba = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: rgba, options: .init(semantic: semantic))
    }
    return PlateTextures(
        albedo:    load("Color",     semantic: .color),
        normal:    load("Normal",    semantic: .normal),
        roughness: load("Roughness", semantic: .raw),
        metalness: load("Metalness", semantic: .raw)
    )
}
