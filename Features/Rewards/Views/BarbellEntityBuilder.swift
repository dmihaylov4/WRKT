// Features/Rewards/Views/BarbellEntityBuilder.swift
import RealityKit
import UIKit

// MARK: - Collision groups
// Plates collide with the floor plane, each other, and the physical bar/rack surfaces.

let plateCollisionGroup = CollisionGroup(rawValue: 1 << 0)
let floorCollisionGroup = CollisionGroup(rawValue: 1 << 1)
let plateCollisionFilter = CollisionFilter(
    group: plateCollisionGroup,
    mask: plateCollisionGroup.union(floorCollisionGroup)
)
let floorCollisionFilter = CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
// Bar hit zone: separate group with empty mask so it never physically collides with plates or floor.
// Used only for gesture ray-cast hit testing (InputTargetComponent + CollisionComponent).
let barHitZoneCollisionGroup = CollisionGroup(rawValue: 1 << 2)
let barHitZoneCollisionFilter = CollisionFilter(group: barHitZoneCollisionGroup, mask: [])

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

func cachedPlateRing(height: Float, outerRadius: Float, innerRadius: Float) -> MeshResource {
    let key = "ring_h\(height)_or\(outerRadius)_ir\(innerRadius)"
    if let cached = meshResourceCache[key] { return cached }
    let mesh = makePlateRingMesh(height: height, outerRadius: outerRadius, innerRadius: innerRadius)
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

private func makePlateRingMesh(height: Float, outerRadius: Float, innerRadius: Float) -> MeshResource {
    let segments = 96
    let halfHeight = height / 2
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    func appendVertex(_ position: SIMD3<Float>, _ normal: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
        positions.append(position)
        normals.append(normal)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    for i in 0..<segments {
        let a0 = Float(i) / Float(segments) * .pi * 2
        let a1 = Float(i + 1) / Float(segments) * .pi * 2
        let c0 = cos(a0), s0 = sin(a0)
        let c1 = cos(a1), s1 = sin(a1)

        let outerTop0 = SIMD3(outerRadius * c0,  halfHeight, outerRadius * s0)
        let outerTop1 = SIMD3(outerRadius * c1,  halfHeight, outerRadius * s1)
        let outerBot0 = SIMD3(outerRadius * c0, -halfHeight, outerRadius * s0)
        let outerBot1 = SIMD3(outerRadius * c1, -halfHeight, outerRadius * s1)
        let innerTop0 = SIMD3(innerRadius * c0,  halfHeight, innerRadius * s0)
        let innerTop1 = SIMD3(innerRadius * c1,  halfHeight, innerRadius * s1)
        let innerBot0 = SIMD3(innerRadius * c0, -halfHeight, innerRadius * s0)
        let innerBot1 = SIMD3(innerRadius * c1, -halfHeight, innerRadius * s1)

        let u0 = Float(i) / Float(segments)
        let u1 = Float(i + 1) / Float(segments)

        func discUV(_ p: SIMD3<Float>) -> SIMD2<Float> {
            SIMD2((p.x / outerRadius + 1) * 0.5, (p.z / outerRadius + 1) * 0.5)
        }

        // Top annulus. Use radial UVs so existing circular plate textures keep their look.
        do {
            let n = SIMD3<Float>(0, 1, 0)
            let a = appendVertex(outerTop0, n, discUV(outerTop0))
            let b = appendVertex(outerTop1, n, discUV(outerTop1))
            let c = appendVertex(innerTop1, n, discUV(innerTop1))
            let d = appendVertex(innerTop0, n, discUV(innerTop0))
            indices += [a, d, c, a, c, b]
        }

        // Bottom annulus.
        do {
            let n = SIMD3<Float>(0, -1, 0)
            let a = appendVertex(outerBot1, n, discUV(outerBot1))
            let b = appendVertex(outerBot0, n, discUV(outerBot0))
            let c = appendVertex(innerBot0, n, discUV(innerBot0))
            let d = appendVertex(innerBot1, n, discUV(innerBot1))
            indices += [a, d, c, a, c, b]
        }

        // Outer wall.
        do {
            let n0 = simd_normalize(SIMD3<Float>(c0, 0, s0))
            let n1 = simd_normalize(SIMD3<Float>(c1, 0, s1))
            let a = appendVertex(outerTop1, n1, SIMD2(u1, 1))
            let b = appendVertex(outerTop0, n0, SIMD2(u0, 1))
            let c = appendVertex(outerBot0, n0, SIMD2(u0, 0))
            let d = appendVertex(outerBot1, n1, SIMD2(u1, 0))
            indices += [a, b, c, a, c, d]
        }

        // Inner bore wall.
        do {
            let n0 = simd_normalize(SIMD3<Float>(-c0, 0, -s0))
            let n1 = simd_normalize(SIMD3<Float>(-c1, 0, -s1))
            let a = appendVertex(innerTop0, n0, SIMD2(u0, 1))
            let b = appendVertex(innerTop1, n1, SIMD2(u1, 1))
            let c = appendVertex(innerBot1, n1, SIMD2(u1, 0))
            let d = appendVertex(innerBot0, n0, SIMD2(u0, 0))
            indices += [a, b, c, a, c, d]
        }
    }

    var descriptor = MeshDescriptor(name: "PlateRing")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)
    return (try? MeshResource.generate(from: [descriptor])) ?? MeshResource.generateCylinder(height: height, radius: outerRadius)
}

private func plateRingCollisionShapes(outerRadius: Float, innerRadius: Float, thickness: Float) -> [ShapeResource] {
    let radialDepth = outerRadius - innerRadius
    let sideCenter = (outerRadius + innerRadius) / 2
    let crossWidth = innerRadius * 2
    return [
        ShapeResource.generateBox(size: SIMD3(radialDepth, thickness, outerRadius * 2))
            .offsetBy(translation: SIMD3(-sideCenter, 0, 0)),
        ShapeResource.generateBox(size: SIMD3(radialDepth, thickness, outerRadius * 2))
            .offsetBy(translation: SIMD3(sideCenter, 0, 0)),
        ShapeResource.generateBox(size: SIMD3(crossWidth, thickness, radialDepth))
            .offsetBy(translation: SIMD3(0, 0, -sideCenter)),
        ShapeResource.generateBox(size: SIMD3(crossWidth, thickness, radialDepth))
            .offsetBy(translation: SIMD3(0, 0, sideCenter))
    ]
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
    mat.faceCulling = .none
    return mat
}

// Process-level singleton -- shared across all hub caps to avoid one material object per plate.
// nonisolated(unsafe) matches the mesh cache pattern; written once before RealityView runs.
private nonisolated(unsafe) var _sharedChromeMaterial: PhysicallyBasedMaterial?
private let plateBoreRadius: Float = 0.034

func chromeMaterial() -> PhysicallyBasedMaterial {
    if let cached = _sharedChromeMaterial { return cached }
    let mat = pbrMaterial(color: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12)
    _sharedChromeMaterial = mat
    return mat
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
    let plate = ModelEntity(mesh: cachedPlateRing(height: thickness, outerRadius: 0.22, innerRadius: plateBoreRadius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return plate
}

private func makeCastIronEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    let radius: Float = 0.22
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
    let plate = ModelEntity(mesh: cachedPlateRing(height: thickness, outerRadius: radius, innerRadius: plateBoreRadius), materials: [outerMat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    let inner = ModelEntity(mesh: cachedPlateRing(height: thickness * 0.72, outerRadius: radius * 0.86, innerRadius: plateBoreRadius), materials: [innerMat])
    plate.addChild(inner)
    let boss = ModelEntity(mesh: cachedPlateRing(height: thickness * 0.82, outerRadius: radius * 0.22, innerRadius: plateBoreRadius),
                            materials: [pbrMaterial(color: tier.plateColor, metallic: 0.06, roughness: 0.95)])
    plate.addChild(boss)
    return plate
}

private func makeBumperEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    let radius: Float = 0.22
    var mat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
                           clearcoat: tier.clearcoat, clearcoatRoughness: tier.clearcoatRoughness)
    if material == nil, let tex = textures {
        if let a = tex.albedo    { mat.baseColor = .init(tint: .white, texture: .init(a)) }
        if let n = tex.normal    { mat.normal    = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness = .init(texture: .init(r)) }
    }
    let plate = ModelEntity(mesh: cachedPlateRing(height: thickness, outerRadius: radius, innerRadius: plateBoreRadius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    let edgeBand = ModelEntity(
        mesh: cachedPlateRing(height: thickness * 0.35, outerRadius: radius + 0.002, innerRadius: plateBoreRadius),
        materials: [pbrMaterial(color: UIColor(white: 0.35, alpha: 1), metallic: 0.1, roughness: 0.88)]
    )
    plate.addChild(edgeBand)
    return plate
}

private func makeBrassEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    makeRawIronEntity(tier: tier, thickness: thickness, textures: textures, material: material)
}

private func makeCompetitionEntity(tier: PlateTier, thickness: Float, material: PhysicallyBasedMaterial?) -> ModelEntity {
    let radius: Float = 0.22
    let mat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
                           clearcoat: tier.clearcoat, clearcoatRoughness: tier.clearcoatRoughness)
    let plate = ModelEntity(mesh: cachedPlateRing(height: thickness, outerRadius: radius, innerRadius: plateBoreRadius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    for faceSign: Float in [-1, 1] {
        let yPos = faceSign * (thickness / 2 + 0.003)
        for ringRadius: Float in [radius * 0.82, radius * 0.42] {
            let ring = ModelEntity(mesh: cachedPlateRing(height: 0.004, outerRadius: ringRadius, innerRadius: plateBoreRadius),
                                   materials: [chromeMaterial()])
            ring.position = SIMD3(0, yPos, 0)
            plate.addChild(ring)
        }
    }
    return plate
}

private func makeStarterEntity(tier: PlateTier, thickness: Float) -> ModelEntity {
    let mat = pbrMaterial(color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1), metallic: 0, roughness: 0.9)
    let plate = ModelEntity(mesh: cachedPlateRing(height: thickness, outerRadius: 0.15, innerRadius: plateBoreRadius), materials: [mat])
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
    let disc = ModelEntity(mesh: cachedPlateRing(height: 0.005, outerRadius: 0.075, innerRadius: plateBoreRadius), materials: [mat])
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

    // Chrome hub ring. The mesh is annular, so the barbell bore is real geometry rather
    // than a dark disc painted on top of a solid plate.
    let hub = ModelEntity(
        mesh: cachedPlateRing(height: plateThickness + 0.003, outerRadius: 0.048, innerRadius: plateBoreRadius),
        materials: [chromeMaterial()]
    )
    entity.addChild(hub)

    // Weight disc
    if weightKg > 0 && tierID != 7 {
        entity.addChild(makeWeightDisc(weightKg: weightKg, tierID: tierID))
    }

    // Gesture + physics collider. Use four ring segments instead of one solid box so the
    // barbell can occupy the real center hole instead of colliding with an invisible plug.
    let collisionRadius: Float = tier.style == .starter ? 0.15 : 0.22
    let collisionShapes = plateRingCollisionShapes(
        outerRadius: collisionRadius,
        innerRadius: plateBoreRadius,
        thickness: plateThickness
    )
    entity.components.set(InputTargetComponent())
    entity.components.set(CollisionComponent(shapes: collisionShapes, filter: plateCollisionFilter))

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

// MARK: - Bar, collar, rack stand

func makeBarEntity(skinID: Int = 0) -> ModelEntity {
    let skin = BarSkin.all[max(0, min(skinID, BarSkin.all.count - 1))]
    let mat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)
    let barLength: Float = 1.6
    let barRadius: Float = 0.012
    let bar = ModelEntity(
        mesh: cachedCylinder(height: barLength, radius: barRadius),
        materials: [mat]
    )
    bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    bar.components.set(CollisionComponent(
        shapes: [ShapeResource.generateBox(size: SIMD3(barRadius * 2.4, barLength, barRadius * 2.4))],
        filter: floorCollisionFilter
    ))
    var staticBody = PhysicsBodyComponent()
    staticBody.mode = .static
    staticBody.material = PhysicsMaterialResource.generate(friction: 0.42, restitution: 0.12)
    bar.components.set(staticBody)
    return bar
}

func makeCollarEntity(skinID: Int = 0) -> ModelEntity {
    let skin = BarSkin.all[max(0, min(skinID, BarSkin.all.count - 1))]
    let mat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)
    let collar = ModelEntity(
        mesh: cachedCylinder(height: 0.04, radius: 0.022),
        materials: [mat]
    )
    collar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return collar
}

func makeRackStandEntity() -> ModelEntity {
    let mat = pbrMaterial(color: UIColor(white: 0.25, alpha: 1), metallic: 0.3, roughness: 0.75)
    let rackFilter = CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
    var staticBody = PhysicsBodyComponent()
    staticBody.mode = .static

    let stand = Entity()
    let post = ModelEntity(
        mesh: cachedCylinder(height: 1.0, radius: 0.025),
        materials: [mat]
    )
    // Box slightly wider than the visual cylinder (0.025 radius) so plates feel the post
    // without requiring a precise hit on the 0.025m surface.
    post.components.set(CollisionComponent(
        shapes: [ShapeResource.generateBox(size: SIMD3(0.06, 1.0, 0.06))],
        filter: rackFilter
    ))
    post.components.set(staticBody)
    stand.addChild(post)

    let foot = ModelEntity(
        mesh: cachedBox(size: SIMD3(0.12, 0.02, 0.08)),
        materials: [mat]
    )
    foot.position = SIMD3(0, -0.51, 0)
    stand.addChild(foot)

    // J-hook saddle -- bar (radius 0.012) rests in the shelf channel.
    // Stand is at world y=0.3; bar center is at world y=0.6 -> stand-local barLocalY=0.30.
    // Shelf top is placed at bar bottom (barLocalY - barRadius) so bar visually rests on it.
    let hookMat = pbrMaterial(color: UIColor(white: 0.62, alpha: 1), metallic: 0.55, roughness: 0.35)
    let barLocalY: Float = 0.30
    let barRadius: Float = 0.012  // matches makeBarEntity radius

    // Back plate (the vertical J-spine, sits flush against post front face)
    let hookBack = ModelEntity(
        mesh: cachedBox(size: SIMD3(0.065, 0.13, 0.022)),
        materials: [hookMat]
    )
    // z: post radius (0.025) + half back depth (0.011) = 0.036
    hookBack.position = SIMD3(0, barLocalY, 0.036)
    hookBack.components.set(CollisionComponent(
        shapes: [ShapeResource.generateBox(size: SIMD3(0.065, 0.13, 0.022))],
        filter: rackFilter
    ))
    hookBack.components.set(staticBody)
    stand.addChild(hookBack)

    // Shelf (horizontal channel; bar rests on its top surface)
    let shelfThick: Float = 0.012
    let shelfDepth: Float = 0.070
    let shelf = ModelEntity(
        mesh: cachedBox(size: SIMD3(0.065, shelfThick, shelfDepth)),
        materials: [hookMat]
    )
    // Shelf top = bar bottom = barLocalY - barRadius
    // Shelf center y = (barLocalY - barRadius) - shelfThick/2
    // Shelf center z: from post front (0.025) forward by half shelfDepth
    shelf.position = SIMD3(0,
                            barLocalY - barRadius - shelfThick / 2,
                            0.025 + shelfDepth / 2)
    stand.addChild(shelf)

    // Front lip (prevents bar from rolling forward off the shelf)
    let lipH: Float = 0.036
    let lip = ModelEntity(
        mesh: cachedBox(size: SIMD3(0.065, lipH, 0.014)),
        materials: [hookMat]
    )
    // Lip bottom at shelf top; center z at shelf front edge + half lip depth
    lip.position = SIMD3(0,
                         barLocalY - barRadius + lipH / 2,
                         0.025 + shelfDepth + 0.007)
    stand.addChild(lip)

    let root = ModelEntity()
    root.addChild(stand)
    return root
}

// MARK: - Plate info card

/// Builds a thin 3D card entity textured with plate tier info.
/// Card faces the camera (+Z in sceneRoot-local = toward camera).
/// Parent: sceneRoot. Position: caller places it near the plate.
func makeInfoCardEntity(plate: EarnedPlate) -> ModelEntity {
    guard let tier = PlateTier.all.first(where: { $0.id == plate.tierID }) else {
        return ModelEntity()
    }
    let image = makeInfoCardTexture(plate: plate, tier: tier)
    var mat = UnlitMaterial()
    if let cg = image.cgImage,
       let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
        mat.color = .init(texture: .init(tex))
        // transparent blending lets the alpha=0 chamfer corners show through to the scene.
        mat.blending = .transparent(opacity: .init(floatLiteral: 1.0))
    }
    let card = ModelEntity(
        mesh: cachedBox(size: SIMD3(0.85, 1.10, 0.006)),
        materials: [mat]
    )
    card.name = "infoCard_\(plate.id)"
    return card
}

private func makeInfoCardTexture(plate: EarnedPlate, tier: PlateTier) -> UIImage {
    let w: CGFloat = 700
    let h: CGFloat = 900
    // Chamfer size matching DS.ChamferedRectangle .xl (scaled to texture space).
    // ChamferedRectangle: TL square, TR chamfered, BR square, BL chamfered.
    let chamfer: CGFloat = 52
    // opaque=false: areas outside the chamfered path stay alpha=0 (transparent).
    // mat.blending=.transparent in makeInfoCardEntity renders those pixels as see-through.
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
    return renderer.image { _ in
        let bg = CGRect(x: 0, y: 0, width: w, height: h)

        // Chamfered card outline path (reused for BG, header clip, and border).
        func cardPath(_ rect: CGRect) -> UIBezierPath {
            let c = chamfer
            let p = UIBezierPath()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))                      // TL square
            p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))               // top edge
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))               // TR chamfer
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))                   // right edge → BR square
            p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))               // bottom edge
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))               // BL chamfer
            p.close()
            return p
        }

        // Card background
        UIColor(white: 0.09, alpha: 1).setFill()
        cardPath(bg).fill()

        // Header stripe -- tier color, top ~27% of card height
        let headerH: CGFloat = 242
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tier.plateColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let brightness = 0.299 * r + 0.587 * g + 0.114 * b
        let headerColor = brightness < 0.15
            ? UIColor(red: r + 0.20, green: g + 0.20, blue: b + 0.20, alpha: 0.90)
            : tier.plateColor.withAlphaComponent(0.88)
        // Header path: only TR chamfered (TL/BL/BR all square) to match card outline.
        let headerPath = UIBezierPath()
        headerPath.move(to: CGPoint(x: 0, y: 0))                                  // TL square
        headerPath.addLine(to: CGPoint(x: w - chamfer, y: 0))                     // top edge
        headerPath.addLine(to: CGPoint(x: w, y: chamfer))                         // TR chamfer
        headerPath.addLine(to: CGPoint(x: w, y: headerH))                         // right edge
        headerPath.addLine(to: CGPoint(x: 0, y: headerH))                         // bottom edge
        headerPath.close()
        headerColor.setFill()
        headerPath.fill()

        // Tier initial circle
        let circleSize: CGFloat = 90
        let circleRect = CGRect(x: (w - circleSize) / 2, y: 66, width: circleSize, height: circleSize)
        UIColor(white: 1, alpha: 0.20).setFill()
        UIBezierPath(ovalIn: circleRect).fill()
        let initial = String(tier.name.prefix(1))
        let initAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 46),
            .foregroundColor: UIColor.white
        ]
        let initSz = (initial as NSString).size(withAttributes: initAttrs)
        (initial as NSString).draw(
            at: CGPoint(x: circleRect.midX - initSz.width / 2, y: circleRect.midY - initSz.height / 2),
            withAttributes: initAttrs
        )

        // Rarity pill
        let rarityText = tier.rarity.rawValue.uppercased()
        let rarityAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.white
        ]
        let raritySz = (rarityText as NSString).size(withAttributes: rarityAttrs)
        let pillPad: CGFloat = 18
        let pillRect = CGRect(x: (w - raritySz.width - pillPad * 2) / 2,
                              y: 182,
                              width: raritySz.width + pillPad * 2,
                              height: raritySz.height + 12)
        UIColor(white: 1, alpha: 0.22).setFill()
        UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2).fill()
        (rarityText as NSString).draw(
            at: CGPoint(x: pillRect.minX + pillPad, y: pillRect.minY + 6),
            withAttributes: rarityAttrs
        )

        // Tier name
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 46),
            .foregroundColor: UIColor.white
        ]
        let nameSz = (tier.name as NSString).size(withAttributes: nameAttrs)
        (tier.name as NSString).draw(
            at: CGPoint(x: (w - nameSz.width) / 2, y: 264),
            withAttributes: nameAttrs
        )

        // Divider
        UIColor(white: 0.28, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: 48, y: 336, width: w - 96, height: 1)).fill()

        // Data rows
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: UIColor(white: 0.50, alpha: 1)
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 34),
            .foregroundColor: UIColor.white
        ]

        var y: CGFloat = 358

        // Weight (skip for starter plate)
        if plate.weightKg > 0 {
            ("WEIGHT" as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: labelAttrs)
            y += 34
            let wStr = plate.weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(plate.weightKg)) kg" : String(format: "%.1f kg", plate.weightKg)
            (wStr as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: valueAttrs)
            y += 62
        }

        // How earned
        let eventText = infoCardFormatEvent(plate.earnedByEvent)
        ("HOW YOU EARNED IT" as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: labelAttrs)
        y += 34
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineBreakMode = .byWordWrapping
        paraStyle.lineSpacing = 4
        let eventAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .medium),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paraStyle
        ]
        (eventText as NSString).draw(
            in: CGRect(x: 48, y: y, width: w - 96, height: 110),
            withAttributes: eventAttrs
        )
        y += 88

        // Date earned
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let dateStr = df.string(from: plate.earnedAt)
        ("EARNED ON" as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: labelAttrs)
        y += 34
        (dateStr as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: valueAttrs)

        // Chamfered border
        UIColor(white: 0.32, alpha: 1).setStroke()
        let border = cardPath(bg.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 3
        border.stroke()
    }
}

private func infoCardFormatEvent(_ event: String) -> String {
    switch event {
    case "starter":           return "Awarded at account creation"
    case "first_workout":     return "Completed your first workout"
    default: break
    }
    if event.hasPrefix("pr_") { return "Hit a personal record" }
    if event.hasPrefix("strength_milestone_") {
        let n = event.replacingOccurrences(of: "strength_milestone_", with: "")
        return "Reached strength milestone \(n)"
    }
    return event.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
}
