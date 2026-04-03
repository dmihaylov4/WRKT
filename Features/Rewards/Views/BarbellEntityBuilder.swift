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

// MARK: - Per-style plate helpers

private func makeRawIronEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    var mat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
    if material == nil, let tex = textures {
        if let a = tex.albedo    { mat.baseColor  = .init(tint: .white, texture: .init(a)) }
        if let n = tex.normal    { mat.normal     = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness  = .init(texture: .init(r)) }
        if let m = tex.metalness { mat.metallic   = .init(texture: .init(m)) }
    }
    let plate = ModelEntity(mesh: cachedCylinder(height: thickness, radius: 0.18), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return plate
}

private func makeCastIronEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    let radius: Float = 0.18
    var outerMat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
    var innerMat = pbrMaterial(color: UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                                metallic: 0.04, roughness: 0.96)
    if material == nil, let tex = textures {
        if let a = tex.albedo {
            outerMat.baseColor = .init(tint: .white, texture: .init(a))
            innerMat.baseColor = .init(tint: UIColor(white: 0.6, alpha: 1), texture: .init(a))
        }
        if let n = tex.normal    { outerMat.normal    = .init(texture: .init(n))
                                    innerMat.normal    = .init(texture: .init(n)) }
        if let r = tex.roughness { outerMat.roughness = .init(texture: .init(r))
                                    innerMat.roughness = .init(texture: .init(r)) }
        if let m = tex.metalness { outerMat.metallic  = .init(texture: .init(m))
                                    innerMat.metallic  = .init(texture: .init(m)) }
    }
    let plate = ModelEntity(mesh: cachedCylinder(height: thickness, radius: radius), materials: [outerMat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    let inner = ModelEntity(mesh: cachedCylinder(height: thickness * 0.72, radius: radius * 0.86), materials: [innerMat])
    plate.addChild(inner)
    let boss = ModelEntity(mesh: cachedCylinder(height: thickness * 0.82, radius: radius * 0.22),
                            materials: [pbrMaterial(color: tier.plateColor, metallic: 0.06, roughness: 0.95)])
    plate.addChild(boss)
    return plate
}

private func makeBumperEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    let radius: Float = 0.18
    var mat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
                           clearcoat: tier.clearcoat, clearcoatRoughness: tier.clearcoatRoughness)
    if material == nil, let tex = textures {
        if let a = tex.albedo    { mat.baseColor = .init(tint: .white, texture: .init(a)) }
        if let n = tex.normal    { mat.normal    = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness = .init(texture: .init(r)) }
    }
    let plate = ModelEntity(mesh: cachedCylinder(height: thickness, radius: radius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    let edgeBand = ModelEntity(
        mesh: cachedCylinder(height: thickness * 0.35, radius: radius + 0.002),
        materials: [pbrMaterial(color: UIColor(white: 0.35, alpha: 1), metallic: 0.1, roughness: 0.88)]
    )
    plate.addChild(edgeBand)
    return plate
}

private func makeBrassEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    makeRawIronEntity(tier: tier, thickness: thickness, textures: textures, material: material)
}

private func makeCompetitionEntity(tier: PlateTier, thickness: Float, material: PhysicallyBasedMaterial?) -> ModelEntity {
    let radius: Float = 0.18
    let mat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
                           clearcoat: tier.clearcoat, clearcoatRoughness: tier.clearcoatRoughness)
    let plate = ModelEntity(mesh: cachedCylinder(height: thickness, radius: radius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    for faceSign: Float in [-1, 1] {
        let yPos = faceSign * (thickness / 2 + 0.003)
        for ringRadius: Float in [radius * 0.82, radius * 0.42] {
            let ring = ModelEntity(mesh: cachedCylinder(height: 0.004, radius: ringRadius),
                                   materials: [chromeMaterial()])
            ring.position = SIMD3(0, yPos, 0)
            plate.addChild(ring)
        }
    }
    return plate
}

private func makeStarterEntity(tier: PlateTier, thickness: Float) -> ModelEntity {
    let mat = pbrMaterial(color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1), metallic: 0, roughness: 0.9)
    let plate = ModelEntity(mesh: cachedCylinder(height: thickness, radius: 0.12), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return plate
}

private func makeWeightDisc(weightKg: Double, tierID: Int) -> ModelEntity {
    let side: CGFloat = 128
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    let image = renderer.image { ctx in
        UIColor.clear.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let label = weightKg.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weightKg))" : String(format: "%.1f", weightKg)
        let textColor: UIColor = [0, 1, 2].contains(tierID) ? .white : .black
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 44),
            .foregroundColor: textColor
        ]
        let str = label as NSString
        let sz = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2),
                 withAttributes: attrs)
    }
    var mat = UnlitMaterial()
    if let cg = image.cgImage,
       let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
        mat.color = .init(texture: .init(tex))
    }
    let disc = ModelEntity(mesh: cachedCylinder(height: 0.005, radius: 0.06), materials: [mat])
    disc.position = SIMD3(0, 0.018, 0)
    return disc
}

// MARK: - makePlateEntity

/// Builds a complete plate ModelEntity for the given tier.
///
/// - Parameters:
///   - tierID: 0-7 matching PlateTier.all.id
///   - textures: Pre-loaded PBR textures. Pass nil to fall back to color materials.
///   - material: Cached PhysicallyBasedMaterial from SceneState.materialCache. When provided,
///               textures are ignored and the shared instance is used directly -- avoids
///               creating duplicate GPU material objects per plate.
///   - weightKg: Renders weight number on a face disc when > 0.
///   - role: .floor (default) or .bar -- stored in PlateRoleComponent for gesture routing.
///
/// Physics: PhysicsBodyComponent is always set with mode .kinematic.
/// Gesture handlers switch to .dynamic on release so the plate settles via physics,
/// then back to .kinematic after ~800ms settling time.
func makePlateEntity(
    tierID: Int,
    textures: PlateTextures? = nil,
    material: PhysicallyBasedMaterial? = nil,
    weightKg: Double = 0,
    engravingText: String = "",
    role: PlateRoleComponent.Role = .floor
) -> ModelEntity {
    guard let tier = PlateTier.all.first(where: { $0.id == tierID }) else {
        return ModelEntity()
    }

    let plateThickness: Float = 0.03
    let entity: ModelEntity

    switch tier.style {
    case .rawIron:
        entity = makeRawIronEntity(tier: tier, thickness: plateThickness, textures: textures, material: material)
    case .castIron:
        entity = makeCastIronEntity(tier: tier, thickness: plateThickness, textures: textures, material: material)
    case .bumper:
        entity = makeBumperEntity(tier: tier, thickness: plateThickness, textures: textures, material: material)
    case .brass:
        entity = makeBrassEntity(tier: tier, thickness: plateThickness, textures: textures, material: material)
    case .starter:
        entity = makeStarterEntity(tier: tier, thickness: plateThickness)
    case .competition:
        entity = makeCompetitionEntity(tier: tier, thickness: plateThickness, material: material)
    case .polishedSteel, .gold:
        // High-tier plates use the base cylinder shape with their own PBR properties;
        // chrome rings are competition-specific and must not appear on these tiers.
        entity = makeRawIronEntity(tier: tier, thickness: plateThickness, textures: textures, material: material)
    }

    // Chrome hub
    let hub = ModelEntity(
        mesh: cachedCylinder(height: plateThickness + 0.003, radius: 0.028),
        materials: [chromeMaterial()]
    )
    entity.addChild(hub)

    // Weight disc
    if weightKg > 0 && tierID != 7 {
        entity.addChild(makeWeightDisc(weightKg: weightKg, tierID: tierID))
    }

    // Gesture components
    let collisionShape = ShapeResource.generateBox(size: SIMD3(0.36, plateThickness, 0.36))
    entity.components.set(InputTargetComponent())
    entity.components.set(CollisionComponent(shapes: [collisionShape], filter: plateCollisionFilter))

    // Physics -- kinematic by default; gesture handlers switch to .dynamic on release
    let audioCategory = PlateAudioCategory.from(tierID: tierID)
    var physicsBody = PhysicsBodyComponent()
    physicsBody.massProperties = .init(mass: Float(max(weightKg, 1.25)))
    physicsBody.material = audioCategory.physicsMaterial
    physicsBody.mode = .kinematic
    entity.components.set(physicsBody)
    entity.components.set(PhysicsMotionComponent())

    // Metadata components
    entity.components.set(PlateRoleComponent(role: role))
    entity.components.set(TierIDComponent(tierID: tierID))
    entity.components.set(PlateAudioCategoryComponent(category: audioCategory))

    // Transparent tiers need explicit sort order to prevent z-fighting
    if tier.style == .starter {
        entity.components.set(ModelSortGroupComponent(
            group: ModelSortGroup(depthPass: .postPass), order: 0
        ))
    }

    // Spatial audio source -- must be set before playAudio() is called
    attachSpatialAudio(to: entity, category: audioCategory)

    return entity
}

// MARK: - Material builder (for SceneState.materialCache population)

/// Builds a PhysicallyBasedMaterial for the given tier with textures applied.
/// Store the result in SceneState.materialCache[tierID] and pass it into
/// makePlateEntity(material:) to share one GPU material object across all plates
/// of the same tier rather than creating one per entity.
func buildMaterial(forTierID tierID: Int, textures: PlateTextures?) -> PhysicallyBasedMaterial {
    guard let tier = PlateTier.all.first(where: { $0.id == tierID }) else {
        return PhysicallyBasedMaterial()
    }
    var mat = pbrMaterial(
        color: tier.plateColor,
        metallic: tier.metallic,
        roughness: tier.roughness,
        clearcoat: tier.clearcoat,
        clearcoatRoughness: tier.clearcoatRoughness
    )
    if let tex = textures {
        if let a = tex.albedo    { mat.baseColor  = .init(tint: .white, texture: .init(a)) }
        if let n = tex.normal    { mat.normal     = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness  = .init(texture: .init(r)) }
        if let m = tex.metalness { mat.metallic   = .init(texture: .init(m)) }
    }
    return mat
}

// MARK: - Stubs (replaced by BarbellAudioBuilder.swift in Task 4)

// Stub -- replaced by BarbellAudioBuilder.swift in Task 4
func attachSpatialAudio(to entity: Entity, category: PlateAudioCategory) {}

extension PlateAudioCategory {
    static func from(tierID: Int) -> PlateAudioCategory { .iron }
    var physicsMaterial: PhysicsMaterialResource { .generate(friction: 0.7, restitution: 0.3) }
}
