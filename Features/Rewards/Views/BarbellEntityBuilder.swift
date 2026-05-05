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

// MARK: - Plate entity build options

struct PlateEntityBuildOptions {
    var includesInput: Bool
    var includesCollision: Bool
    var includesPhysics: Bool
    var includesAudio: Bool
    var role: PlateRoleComponent.Role

    static func interactive(role: PlateRoleComponent.Role = .floor) -> PlateEntityBuildOptions {
        PlateEntityBuildOptions(
            includesInput: true,
            includesCollision: true,
            includesPhysics: true,
            includesAudio: true,
            role: role
        )
    }

    static func visualOnly(role: PlateRoleComponent.Role = .floor) -> PlateEntityBuildOptions {
        PlateEntityBuildOptions(
            includesInput: false,
            includesCollision: false,
            includesPhysics: false,
            includesAudio: false,
            role: role
        )
    }
}

// MARK: - Progression render projection

struct BarbellPlateRenderProjection: Equatable {
    let progressionTier: BarbellPlateProgressionTier
    let chalkUseCount: Int
    let gripWearCount: Int
    let pressUseCount: Int

    init(
        progressionTier: BarbellPlateProgressionTier = .iron,
        chalkUseCount: Int = 0,
        gripWearCount: Int = 0,
        pressUseCount: Int = 0
    ) {
        self.progressionTier = progressionTier
        self.chalkUseCount = max(0, chalkUseCount)
        self.gripWearCount = max(0, gripWearCount)
        self.pressUseCount = max(0, pressUseCount)
    }

    init(plate: EarnedPlate) {
        self.init(
            progressionTier: plate.currentTier,
            chalkUseCount: plate.chalkUseCount,
            gripWearCount: plate.gripWearCount,
            pressUseCount: plate.pressUseCount
        )
    }

    var tierRingCount: Int {
        switch progressionTier {
        case .iron: return 0
        case .steel: return 1
        case .chrome: return 2
        case .gold, .obsidian, .cosmic: return 3
        }
    }

    var chalkMarkCount: Int { min(chalkUseCount / 4, 8) }
    var gripWearMarkCount: Int { min(gripWearCount / 5, 6) }
    var pressPolishMarkCount: Int { min(pressUseCount / 6, 5) }

    var tierAccentColor: UIColor {
        switch progressionTier {
        case .iron: return UIColor(white: 0.66, alpha: 1)
        case .steel: return UIColor(red: 0.70, green: 0.74, blue: 0.76, alpha: 1)
        case .chrome: return UIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1)
        case .gold: return UIColor(red: 1.0, green: 0.72, blue: 0.18, alpha: 1)
        case .obsidian: return UIColor(red: 0.18, green: 0.16, blue: 0.22, alpha: 1)
        case .cosmic: return UIColor(red: 0.35, green: 0.78, blue: 1.0, alpha: 1)
        }
    }
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

func cachedRoundedBox(size: SIMD3<Float>, cornerRadius: Float) -> MeshResource {
    let key = "rbox_\(size.x)_\(size.y)_\(size.z)_r\(cornerRadius)"
    if let cached = meshResourceCache[key] { return cached }
    let mesh = MeshResource.generateBox(
        width: size.x,
        height: size.y,
        depth: size.z,
        cornerRadius: cornerRadius
    )
    meshResourceCache[key] = mesh
    return mesh
}

private func makePlateRingMesh(height: Float, outerRadius: Float, innerRadius: Float) -> MeshResource {
    let segments = max(24, Int((outerRadius / 0.22) * 64))
    let halfHeight = height / 2
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var tangents: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    func appendVertex(_ position: SIMD3<Float>, _ normal: SIMD3<Float>, _ uv: SIMD2<Float>, _ tangent: SIMD3<Float>) -> UInt32 {
        positions.append(position)
        normals.append(normal)
        uvs.append(uv)
        tangents.append(tangent)
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
            let t = SIMD3<Float>(1, 0, 0)
            let a = appendVertex(outerTop0, n, discUV(outerTop0), t)
            let b = appendVertex(outerTop1, n, discUV(outerTop1), t)
            let c = appendVertex(innerTop1, n, discUV(innerTop1), t)
            let d = appendVertex(innerTop0, n, discUV(innerTop0), t)
            indices += [a, d, c, a, c, b]
        }

        // Bottom annulus.
        do {
            let n = SIMD3<Float>(0, -1, 0)
            let t = SIMD3<Float>(1, 0, 0)
            let a = appendVertex(outerBot1, n, discUV(outerBot1), t)
            let b = appendVertex(outerBot0, n, discUV(outerBot0), t)
            let c = appendVertex(innerBot0, n, discUV(innerBot0), t)
            let d = appendVertex(innerBot1, n, discUV(innerBot1), t)
            indices += [a, d, c, a, c, b]
        }

        // Outer wall.
        do {
            let n0 = simd_normalize(SIMD3<Float>(c0, 0, s0))
            let n1 = simd_normalize(SIMD3<Float>(c1, 0, s1))
            let t0 = simd_normalize(SIMD3<Float>(-s0, 0, c0))
            let t1 = simd_normalize(SIMD3<Float>(-s1, 0, c1))
            let a = appendVertex(outerTop1, n1, SIMD2(u1, 1), t1)
            let b = appendVertex(outerTop0, n0, SIMD2(u0, 1), t0)
            let c = appendVertex(outerBot0, n0, SIMD2(u0, 0), t0)
            let d = appendVertex(outerBot1, n1, SIMD2(u1, 0), t1)
            indices += [a, b, c, a, c, d]
        }

        // Inner bore wall.
        do {
            let n0 = simd_normalize(SIMD3<Float>(-c0, 0, -s0))
            let n1 = simd_normalize(SIMD3<Float>(-c1, 0, -s1))
            let t0 = simd_normalize(SIMD3<Float>(s0, 0, -c0))
            let t1 = simd_normalize(SIMD3<Float>(s1, 0, -c1))
            let a = appendVertex(innerTop0, n0, SIMD2(u0, 1), t0)
            let b = appendVertex(innerTop1, n1, SIMD2(u1, 1), t1)
            let c = appendVertex(innerBot1, n1, SIMD2(u1, 0), t1)
            let d = appendVertex(innerBot0, n0, SIMD2(u0, 0), t0)
            indices += [a, b, c, a, c, d]
        }
    }

    var descriptor = MeshDescriptor(name: "PlateRing")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.tangents = MeshBuffers.Tangents(tangents)
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

struct PlateSidewallSurface: Equatable {
    let color: UIColor
    let metallic: Float
    let roughness: Float
    let clearcoat: Float
    let clearcoatRoughness: Float

    static func sidewall(for tier: PlateTier) -> PlateSidewallSurface {
        if usesShinyMetalSidewall(tier) {
            return PlateSidewallSurface(
                color: PlateDisplaySurface.sidewallColor(for: tier),
                metallic: PlateDisplaySurface.metallic(for: tier),
                roughness: PlateDisplaySurface.sidewallRoughness(for: tier),
                clearcoat: PlateDisplaySurface.clearcoat(for: tier),
                clearcoatRoughness: min(0.08, tier.clearcoatRoughness)
            )
        }

        let color: UIColor
        switch tier.style {
        case .bumper where tier.id == 2:
            color = UIColor(white: 0.18, alpha: 1)
        case .bumper:
            color = PlateDisplaySurface.sidewallColor(for: tier).barbellDimmed(by: 0.18)
        case .castIron, .starter:
            color = UIColor(white: 0.18, alpha: 1)
        case .rawIron:
            color = tier.plateColor.withAlphaComponent(0.95)
        default:
            color = tier.plateColor
        }
        return PlateSidewallSurface(
            color: color,
            metallic: tier.style == .bumper ? 0 : max(0, tier.metallic * 0.75),
            roughness: min(1, max(0.50, tier.roughness + 0.10)),
            clearcoat: max(0.14, tier.clearcoat * 0.72),
            clearcoatRoughness: min(1, tier.clearcoatRoughness + 0.20)
        )
    }

    static func lip(for tier: PlateTier) -> PlateSidewallSurface {
        if usesShinyMetalSidewall(tier) {
            return PlateSidewallSurface(
                color: PlateDisplaySurface.lipColor(for: tier),
                metallic: min(0.72, max(0.42, PlateDisplaySurface.metallic(for: tier) + 0.04)),
                roughness: max(0.18, min(0.30, tier.roughness + 0.17)),
                clearcoat: PlateDisplaySurface.clearcoat(for: tier),
                clearcoatRoughness: min(0.06, tier.clearcoatRoughness)
            )
        }

        let lipColor: UIColor
        switch tier.style {
        case .rawIron:
            lipColor = UIColor(red: 0.18, green: 0.08, blue: 0.03, alpha: 1)
        case .castIron:
            lipColor = PlateDisplaySurface.sidewallColor(for: tier).barbellBrightened(by: 0.16)
        case .bumper:
            lipColor = PlateDisplaySurface.sidewallColor(for: tier).barbellBrightened(by: tier.id == 2 ? 0.18 : 0.10)
        case .polishedSteel, .gold, .brass:
            lipColor = tier.plateColor.withAlphaComponent(0.96)
        case .competition:
            lipColor = tier.plateColor.withAlphaComponent(0.96)
        default:
            lipColor = UIColor(white: 0.08, alpha: 1)
        }
        return PlateSidewallSurface(
            color: lipColor,
            metallic: tier.style == .bumper ? 0 : tier.metallic,
            roughness: min(1, max(0.52, tier.roughness + 0.10)),
            clearcoat: tier.clearcoat * 0.62,
            clearcoatRoughness: min(1, tier.clearcoatRoughness + 0.22)
        )
    }

    private static func usesShinyMetalSidewall(_ tier: PlateTier) -> Bool {
        tier.id != 2 && tier.id != 4 && tier.id != 7 && tier.metallic >= 0.15
    }
}

struct PlateDisplaySurface {
    typealias HSB = (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat)

    static func usesReadableMetal(_ tier: PlateTier) -> Bool {
        tier.id != 2 && tier.id != 4 && tier.id != 7 && tier.metallic >= 0.85
    }

    static func faceColor(for tier: PlateTier) -> UIColor {
        readableColor(for: tier, saturationBoost: saturationBoost(for: tier), brightnessBoost: brightnessBoost(for: tier), minimumBrightness: minimumFaceBrightness(for: tier))
    }

    static func sidewallColor(for tier: PlateTier) -> UIColor {
        readableColor(for: tier, saturationBoost: saturationBoost(for: tier) + 0.05, brightnessBoost: brightnessBoost(for: tier) + 0.03, minimumBrightness: minimumSidewallBrightness(for: tier))
    }

    static func lipColor(for tier: PlateTier) -> UIColor {
        readableColor(for: tier, saturationBoost: saturationBoost(for: tier) + 0.08, brightnessBoost: brightnessBoost(for: tier) + 0.05, minimumBrightness: minimumSidewallBrightness(for: tier))
    }

    static func metallic(for tier: PlateTier) -> Float {
        guard usesReadableMetal(tier) else { return tier.metallic }
        return min(0.58, max(0.38, tier.metallic * 0.58))
    }

    static func roughness(for tier: PlateTier) -> Float {
        guard usesReadableMetal(tier) else { return tier.roughness }
        return max(0.18, min(0.34, tier.roughness + 0.18))
    }

    static func sidewallRoughness(for tier: PlateTier) -> Float {
        guard usesReadableMetal(tier) else { return tier.roughness }
        return max(0.12, min(0.26, tier.roughness + 0.10))
    }

    static func clearcoat(for tier: PlateTier) -> Float {
        guard usesReadableMetal(tier) else { return tier.clearcoat }
        return min(0.72, max(0.48, tier.clearcoat * 0.70))
    }

    private static func saturationBoost(for tier: PlateTier) -> CGFloat {
        switch tier.style {
        case .competition, .gold, .brass, .rawIron:
            return 0.24
        case .bumper where tier.id != 2:
            return 0.24
        default:
            return 0.12
        }
    }

    private static func brightnessBoost(for tier: PlateTier) -> CGFloat {
        switch tier.style {
        case .competition, .gold, .brass, .rawIron:
            return 0.22
        case .bumper where tier.id != 2:
            return 0.22
        default:
            return 0.14
        }
    }

    private static func minimumFaceBrightness(for tier: PlateTier) -> CGFloat {
        switch tier.style {
        case .castIron:
            return 0.32
        case .bumper:
            return tier.id == 2 ? 0.32 : 0.42
        case .starter:
            return 0
        default:
            return usesReadableMetal(tier) ? 0.72 : 0
        }
    }

    private static func minimumSidewallBrightness(for tier: PlateTier) -> CGFloat {
        switch tier.style {
        case .castIron:
            return 0.34
        case .bumper:
            return tier.id == 2 ? 0.34 : 0.44
        case .starter:
            return 0
        default:
            return usesReadableMetal(tier) ? 0.74 : 0
        }
    }

    private static func readableColor(
        for tier: PlateTier,
        saturationBoost: CGFloat,
        brightnessBoost: CGFloat,
        minimumBrightness: CGFloat
    ) -> UIColor {
        let hsb = tier.plateColor.barbellHSB
        return UIColor(
            hue: hsb.hue,
            saturation: min(1, hsb.saturation + saturationBoost),
            brightness: min(1, max(minimumBrightness, hsb.brightness + brightnessBoost)),
            alpha: hsb.alpha
        )
    }
}

struct BumperPlateSurface: Equatable {
    let color: UIColor
    let metallic: Float
    let roughness: Float
    let clearcoat: Float
    let clearcoatRoughness: Float

    static func centerHub(for tier: PlateTier) -> BumperPlateSurface {
        BumperPlateSurface(
            color: PlateDisplaySurface.faceColor(for: tier).barbellDimmed(by: tier.id == 2 ? 0.55 : 0.34),
            metallic: 0,
            roughness: 0.90,
            clearcoat: 0.08,
            clearcoatRoughness: 0.78
        )
    }

    var material: PhysicallyBasedMaterial {
        pbrMaterial(
            color: color,
            metallic: metallic,
            roughness: roughness,
            clearcoat: clearcoat,
            clearcoatRoughness: clearcoatRoughness
        )
    }
}

extension UIColor {
    var barbellHSB: PlateDisplaySurface.HSB {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            var white: CGFloat = 0
            getWhite(&white, alpha: &a)
            return (0, 0, white, a)
        }
        return (h, s, b, a)
    }

    func barbellBrightened(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(
            red: min(1, r + (1 - r) * amount),
            green: min(1, g + (1 - g) * amount),
            blue: min(1, b + (1 - b) * amount),
            alpha: a
        )
    }

    func barbellDimmed(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let factor = max(0, min(1, 1 - amount))
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }
}

// MARK: - PBR helpers

// doubleSided defaults to true because ring meshes have cylindrical walls that face all directions.
// Culling back-faces on a ring punches holes in the outer/inner walls, letting the scene
// background show through. Pass doubleSided: false only for purely flat, one-sided decal geometry.
func pbrMaterial(
    color: UIColor,
    metallic: Float,
    roughness: Float,
    clearcoat: Float = 0,
    clearcoatRoughness: Float = 0,
    doubleSided: Bool = true
) -> PhysicallyBasedMaterial {
    var mat = PhysicallyBasedMaterial()
    mat.baseColor = .init(tint: color)
    mat.metallic = .init(floatLiteral: metallic)
    mat.roughness = .init(floatLiteral: roughness)
    mat.clearcoat = .init(floatLiteral: clearcoat)
    mat.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
    mat.faceCulling = doubleSided ? .none : .back
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

/// Holds shared material instances for a single plate build.
struct PlateMaterialCache {
    let darkRubber: PhysicallyBasedMaterial
    let chrome: PhysicallyBasedMaterial

    init() {
        darkRubber = pbrMaterial(
            color: UIColor(white: 0.025, alpha: 1),
            metallic: 0,
            roughness: 0.92,
            clearcoat: 0.12,
            clearcoatRoughness: 0.70
        )
        chrome = chromeMaterial()
    }
}

private nonisolated(unsafe) var _dishMaterialCache: [String: PhysicallyBasedMaterial] = [:]

private func shadowDishMaterial(from base: PlateTier, factor: CGFloat = 0.72) -> PhysicallyBasedMaterial {
    let key = "\(base.id)_\(factor)"
    if let cached = _dishMaterialCache[key] { return cached }
    let mat = pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: base).barbellDimmed(by: base.style == .castIron || base.style == .bumper ? 0.18 : 1 - factor),
        metallic: PlateDisplaySurface.metallic(for: base),
        roughness: min(1.0, PlateDisplaySurface.roughness(for: base) + 0.10),
        clearcoat: max(0, PlateDisplaySurface.clearcoat(for: base) - 0.08),
        clearcoatRoughness: min(1.0, base.clearcoatRoughness + 0.20)
    )
    _dishMaterialCache[key] = mat
    return mat
}

// MARK: - Texture loading

// Prefix-level cache so all tiers that share the same source images (e.g. every Rubber-family
// tier) reuse identical TextureResource objects. Without this, 12 Rubber tiers each create 4
// separate GPU texture uploads from the same pixel data, exhausting Metal's drawable budget
// and causing CAMetalLayer nextDrawable to return nil.
@MainActor var _bundleTexturesByPrefix: [String: PlateTextures] = [:]

@MainActor
func loadPlateTextures(forTierID tierID: Int) -> PlateTextures {
    let prefix: String
    switch tierID {
    case 1: prefix = "CastIron"
    case 2, 10, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23: prefix = "Rubber"
    case 3: prefix = "Brass"
    default: return PlateTextures()
    }
    return loadBundleTextures(prefix: prefix)
}

@MainActor
private func loadBundleTextures(prefix: String) -> PlateTextures {
    if let cached = _bundleTexturesByPrefix[prefix] { return cached }
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
    let textures = PlateTextures(
        albedo:    load("Color",     semantic: .color),
        normal:    load("Normal",    semantic: .normal),
        roughness: load("Roughness", semantic: .raw),
        metalness: load("Metalness", semantic: .raw)
    )
    _bundleTexturesByPrefix[prefix] = textures
    return textures
}

// MARK: - Per-style plate helpers

private func makeRaisedOuterRim(profile: PlateVisualProfile, material: PhysicallyBasedMaterial) -> ModelEntity {
    let rim = ModelEntity(
        mesh: cachedPlateRing(
            height: profile.thickness + 0.006,
            outerRadius: profile.rimOuterRadius,
            innerRadius: profile.rimInnerRadius
        ),
        materials: [material]
    )
    rim.name = "raisedOuterRim"
    return rim
}

private func makeRecessedFacePanel(profile: PlateVisualProfile, material: PhysicallyBasedMaterial) -> ModelEntity {
    let panel = ModelEntity(
        mesh: cachedPlateRing(
            height: max(0.004, profile.thickness - profile.dishDepth),
            outerRadius: profile.faceOuterRadius,
            innerRadius: profile.faceInnerRadius
        ),
        materials: [material]
    )
    panel.name = "recessedFacePanel"
    return panel
}

private func makeCenterBoss(profile: PlateVisualProfile, material: PhysicallyBasedMaterial) -> ModelEntity {
    let boss = ModelEntity(
        mesh: cachedPlateRing(
            height: 0.001,
            outerRadius: profile.bossOuterRadius,
            innerRadius: plateBoreRadius
        ),
        materials: [material]
    )
    boss.name = "centerBoss"
    boss.position.y = profile.thickness * 0.5 + 0.0005
    return boss
}

private func makeGlossAccentRing(profile: PlateVisualProfile, tier: PlateTier) -> ModelEntity {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 1
    tier.plateColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    let highlight = UIColor(
        red: min(1, r * 1.18 + 0.16),
        green: min(1, g * 1.18 + 0.16),
        blue: min(1, b * 1.18 + 0.16),
        alpha: 1
    )
    let ring = ModelEntity(
        mesh: cachedPlateRing(
            height: 0.001,
            outerRadius: min(profile.outerRadius - 0.012, profile.rimOuterRadius + 0.004),
            innerRadius: max(profile.bossOuterRadius + 0.026, profile.rimInnerRadius - 0.010)
        ),
        materials: [pbrMaterial(
            color: highlight,
            metallic: tier.style == .bumper ? 0 : max(0.25, tier.metallic),
            roughness: tier.style == .bumper ? max(0.74, tier.roughness) : max(0.018, min(0.12, tier.roughness * 0.38)),
            clearcoat: tier.style == .bumper ? min(0.18, tier.clearcoat) : max(0.68, tier.clearcoat),
            clearcoatRoughness: tier.style == .bumper ? max(0.55, tier.clearcoatRoughness) : min(0.08, tier.clearcoatRoughness),
            doubleSided: true
        )]
    )
    ring.name = "glossAccentRing"
    ring.position.y = profile.thickness * 0.5 + 0.006
    return ring
}

private func makeBackFaceCopy(of entity: ModelEntity, profile: PlateVisualProfile) -> ModelEntity {
    let copy = entity.clone(recursive: true)
    copy.name = "\(entity.name)_back"
    copy.position.y = -entity.position.y
    return copy
}

private func addFaceDetailPair(_ detail: ModelEntity, to plate: ModelEntity, profile: PlateVisualProfile) {
    plate.addChild(detail)
    plate.addChild(makeBackFaceCopy(of: detail, profile: profile))
}

private func makeOuterRubberBand(profile: PlateVisualProfile, tier: PlateTier, cache: PlateMaterialCache) -> ModelEntity {
    let materials: [RealityKit.Material]
    if tier.metallic >= 0.15 && tier.id != 2 && tier.id != 4 && tier.id != 7 {
        let surface = PlateSidewallSurface.sidewall(for: tier)
        materials = [pbrMaterial(
            color: surface.color,
            metallic: surface.metallic,
            roughness: surface.roughness,
            clearcoat: surface.clearcoat,
            clearcoatRoughness: surface.clearcoatRoughness
        )]
    } else if tier.style == .competition {
        // Colored competition plates: darkened plate color instead of near-black rubber
        materials = [pbrMaterial(
            color: tier.plateColor.barbellDimmed(by: 0.28),
            metallic: 0.04,
            roughness: 0.72,
            clearcoat: tier.clearcoat * 0.5,
            clearcoatRoughness: tier.clearcoatRoughness + 0.25
        )]
    } else {
        materials = [cache.darkRubber]
    }
    let band = ModelEntity(
        mesh: cachedPlateRing(
            height: profile.thickness + 0.010,
            outerRadius: profile.outerBandRadius,
            innerRadius: max(profile.rimInnerRadius, profile.outerRadius - 0.020)
        ),
        materials: materials
    )
    band.name = "outerRubberBand"
    return band
}

private func makeOuterSidewallBand(profile: PlateVisualProfile, tier: PlateTier) -> ModelEntity {
    let surface = PlateSidewallSurface.sidewall(for: tier)
    let material = pbrMaterial(
        color: surface.color,
        metallic: surface.metallic,
        roughness: surface.roughness,
        clearcoat: surface.clearcoat,
        clearcoatRoughness: surface.clearcoatRoughness,
        doubleSided: true
    )
    let band = ModelEntity(
        mesh: cachedPlateRing(
            height: profile.thickness + 0.018,
            outerRadius: profile.outerRadius + 0.007,
            innerRadius: max(plateBoreRadius, profile.outerRadius - 0.026)
        ),
        materials: [material]
    )
    band.name = "outerSidewallBand"
    return band
}

private func makeOuterSidewallLip(profile: PlateVisualProfile, tier: PlateTier) -> ModelEntity {
    let surface = PlateSidewallSurface.lip(for: tier)
    let lip = ModelEntity(
        mesh: cachedPlateRing(
            height: 0.006,
            outerRadius: profile.outerRadius + 0.010,
            innerRadius: max(plateBoreRadius, profile.outerRadius - 0.030)
        ),
        materials: [pbrMaterial(
            color: surface.color,
            metallic: surface.metallic,
            roughness: surface.roughness,
            clearcoat: surface.clearcoat,
            clearcoatRoughness: surface.clearcoatRoughness,
            doubleSided: true
        )]
    )
    lip.name = "outerSidewallLip"
    lip.position.y = profile.thickness * 0.5 + 0.003
    return lip
}

private func makeMoldedFaceRing(
    name: String,
    outerRadius: Float,
    innerRadius: Float,
    profile: PlateVisualProfile,
    material: PhysicallyBasedMaterial
) -> ModelEntity {
    let ring = ModelEntity(
        mesh: cachedPlateRing(height: 0.001, outerRadius: outerRadius, innerRadius: innerRadius),
        materials: [material]
    )
    ring.name = name
    ring.position.y = profile.thickness * 0.5 + 0.0005
    return ring
}

private func addCastIronGripCues(to plate: ModelEntity, profile: PlateVisualProfile, material: PhysicallyBasedMaterial) {
    guard profile.hasGripCues else { return }
    let cueMesh = cachedRoundedBox(size: SIMD3(0.045, 0.004, 0.014), cornerRadius: 0.001)
    for index in 0..<3 {
        let angle = Float(index) * (2 * .pi / 3)
        let cue = ModelEntity(mesh: cueMesh, materials: [material])
        cue.name = "castIronGripCue_\(index)"
        cue.position = SIMD3(cos(angle) * 0.135, profile.thickness * 0.5 + 0.004, sin(angle) * 0.135)
        cue.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        plate.addChild(cue)
    }
}

private func makeRawIronEntity(
    tier: PlateTier,
    textures: PlateTextures?,
    material: PhysicallyBasedMaterial?
) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    var mat = material ?? pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: tier),
        metallic: PlateDisplaySurface.metallic(for: tier),
        roughness: min(1, PlateDisplaySurface.roughness(for: tier) + 0.04),
        clearcoat: PlateDisplaySurface.clearcoat(for: tier),
        clearcoatRoughness: tier.clearcoatRoughness
    )
    if material == nil, let tex = textures {
        if let a = tex.albedo    { mat.baseColor  = .init(tint: PlateDisplaySurface.faceColor(for: tier), texture: .init(a)) }
        if let n = tex.normal    { mat.normal     = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness  = .init(texture: .init(r)) }
        if let m = tex.metalness { mat.metallic   = .init(texture: .init(m)) }
    }
    let dishMat = shadowDishMaterial(from: tier)
    let plate = ModelEntity(
        mesh: cachedPlateRing(height: profile.thickness, outerRadius: profile.outerRadius, innerRadius: plateBoreRadius),
        materials: [mat]
    )
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    plate.addChild(makeOuterSidewallBand(profile: profile, tier: tier))
    addFaceDetailPair(makeOuterSidewallLip(profile: profile, tier: tier), to: plate, profile: profile)
    plate.addChild(makeRaisedOuterRim(profile: profile, material: mat))
    plate.addChild(makeRecessedFacePanel(profile: profile, material: dishMat))
    addFaceDetailPair(makeCenterBoss(profile: profile, material: mat), to: plate, profile: profile)
    return plate
}

private func makeCastIronEntity(
    tier: PlateTier,
    textures: PlateTextures?,
    material: PhysicallyBasedMaterial?
) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    var outerMat = material ?? pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: tier),
        metallic: PlateDisplaySurface.metallic(for: tier),
        roughness: PlateDisplaySurface.usesReadableMetal(tier) ? PlateDisplaySurface.roughness(for: tier) : 0.98,
        clearcoat: PlateDisplaySurface.clearcoat(for: tier),
        clearcoatRoughness: tier.clearcoatRoughness
    )
    var dishMat = shadowDishMaterial(from: tier, factor: 0.58)
    if material == nil, let tex = textures {
        if let a = tex.albedo {
            outerMat.baseColor = .init(tint: PlateDisplaySurface.faceColor(for: tier), texture: .init(a))
            dishMat.baseColor = .init(tint: PlateDisplaySurface.faceColor(for: tier).barbellDimmed(by: 0.12), texture: .init(a))
        }
        if let n = tex.normal    { outerMat.normal = .init(texture: .init(n)); dishMat.normal = .init(texture: .init(n)) }
        if let r = tex.roughness { outerMat.roughness = .init(texture: .init(r)); dishMat.roughness = .init(texture: .init(r)) }
        if let m = tex.metalness { outerMat.metallic = .init(texture: .init(m)); dishMat.metallic = .init(texture: .init(m)) }
    }
    let plate = ModelEntity(
        mesh: cachedPlateRing(height: profile.thickness, outerRadius: profile.outerRadius, innerRadius: plateBoreRadius),
        materials: [outerMat]
    )
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    plate.addChild(makeOuterSidewallBand(profile: profile, tier: tier))
    addFaceDetailPair(makeOuterSidewallLip(profile: profile, tier: tier), to: plate, profile: profile)
    plate.addChild(makeRaisedOuterRim(profile: profile, material: outerMat))
    plate.addChild(makeRecessedFacePanel(profile: profile, material: dishMat))
    addFaceDetailPair(makeCenterBoss(profile: profile, material: outerMat), to: plate, profile: profile)
    addCastIronGripCues(to: plate, profile: profile, material: outerMat)
    return plate
}

private func makeBumperEntity(
    tier: PlateTier,
    textures: PlateTextures?,
    material: PhysicallyBasedMaterial?,
    cache: PlateMaterialCache
) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    var faceMat = material ?? pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: tier),
        metallic: PlateDisplaySurface.metallic(for: tier),
        roughness: PlateDisplaySurface.usesReadableMetal(tier) ? PlateDisplaySurface.roughness(for: tier) : max(0.78, tier.roughness),
        clearcoat: PlateDisplaySurface.clearcoat(for: tier),
        clearcoatRoughness: max(0.35, tier.clearcoatRoughness)
    )
    if material == nil, let tex = textures {
        if let a = tex.albedo    { faceMat.baseColor = .init(tint: PlateDisplaySurface.faceColor(for: tier), texture: .init(a)) }
        if let n = tex.normal    { faceMat.normal    = .init(texture: .init(n)) }
        if let r = tex.roughness { faceMat.roughness = .init(texture: .init(r)) }
    }
    let plate = ModelEntity(
        mesh: cachedPlateRing(height: profile.thickness, outerRadius: profile.outerRadius, innerRadius: plateBoreRadius),
        materials: [faceMat]
    )
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    plate.addChild(makeOuterSidewallBand(profile: profile, tier: tier))
    addFaceDetailPair(makeOuterSidewallLip(profile: profile, tier: tier), to: plate, profile: profile)
    plate.addChild(makeOuterRubberBand(profile: profile, tier: tier, cache: cache))
    let ringSpecs = PlateVisualDesign.faceRingSpecs(for: tier.style)
    if ringSpecs.count == 2 {
        addFaceDetailPair(makeMoldedFaceRing(name: "moldedFaceRing_outer", outerRadius: ringSpecs[0].outerRadius, innerRadius: ringSpecs[0].innerRadius, profile: profile, material: faceMat), to: plate, profile: profile)
        addFaceDetailPair(makeMoldedFaceRing(name: "moldedFaceRing_inner", outerRadius: ringSpecs[1].outerRadius, innerRadius: ringSpecs[1].innerRadius, profile: profile, material: faceMat), to: plate, profile: profile)
    }
    addFaceDetailPair(makeCenterBoss(profile: profile, material: BumperPlateSurface.centerHub(for: tier).material), to: plate, profile: profile)
    return plate
}

private func makeBrassEntity(
    tier: PlateTier,
    textures: PlateTextures?,
    material: PhysicallyBasedMaterial?
) -> ModelEntity {
    makeRawIronEntity(tier: tier, textures: textures, material: material)
}

private func makeCompetitionEntity(
    tier: PlateTier,
    material: PhysicallyBasedMaterial?,
    cache: PlateMaterialCache
) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    let faceMat = material ?? pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: tier),
        metallic: PlateDisplaySurface.metallic(for: tier),
        roughness: PlateDisplaySurface.usesReadableMetal(tier) ? PlateDisplaySurface.roughness(for: tier) : max(0.68, tier.roughness),
        clearcoat: PlateDisplaySurface.clearcoat(for: tier),
        clearcoatRoughness: tier.clearcoatRoughness
    )
    let chromeMat = cache.chrome
    let plate = ModelEntity(
        mesh: cachedPlateRing(height: profile.thickness, outerRadius: profile.outerRadius, innerRadius: plateBoreRadius),
        materials: [faceMat]
    )
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    plate.addChild(makeOuterSidewallBand(profile: profile, tier: tier))
    addFaceDetailPair(makeOuterSidewallLip(profile: profile, tier: tier), to: plate, profile: profile)
    plate.addChild(makeOuterRubberBand(profile: profile, tier: tier, cache: cache))
    let ringSpecs = PlateVisualDesign.faceRingSpecs(for: tier.style)
    if ringSpecs.count == 2 {
        addFaceDetailPair(makeMoldedFaceRing(name: "competitionChromeRing_outer", outerRadius: ringSpecs[0].outerRadius, innerRadius: ringSpecs[0].innerRadius, profile: profile, material: chromeMat), to: plate, profile: profile)
        addFaceDetailPair(makeMoldedFaceRing(name: "competitionChromeRing_inner", outerRadius: ringSpecs[1].outerRadius, innerRadius: ringSpecs[1].innerRadius, profile: profile, material: chromeMat), to: plate, profile: profile)
    }
    addFaceDetailPair(makeCenterBoss(profile: profile, material: chromeMat), to: plate, profile: profile)
    return plate
}

private func makeStarterEntity(tier: PlateTier) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    let mat = pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: tier),
        metallic: PlateDisplaySurface.metallic(for: tier),
        roughness: PlateDisplaySurface.roughness(for: tier),
        doubleSided: true
    )
    let plate = ModelEntity(
        mesh: cachedPlateRing(height: profile.thickness, outerRadius: profile.outerRadius, innerRadius: plateBoreRadius),
        materials: [mat]
    )
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    plate.addChild(makeOuterSidewallBand(profile: profile, tier: tier))
    addFaceDetailPair(makeOuterSidewallLip(profile: profile, tier: tier), to: plate, profile: profile)
    plate.addChild(makeRaisedOuterRim(profile: profile, material: mat))
    plate.addChild(makeRecessedFacePanel(profile: profile, material: shadowDishMaterial(from: tier, factor: 0.82)))
    addFaceDetailPair(makeCenterBoss(profile: profile, material: mat), to: plate, profile: profile)
    return plate
}

private func drawCenteredText(
    _ text: String,
    at point: CGPoint,
    angle: CGFloat,
    attributes: [NSAttributedString.Key: Any]
) {
    let str = text as NSString
    let size = str.size(withAttributes: attributes)
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.translateBy(x: point.x, y: point.y)
    context.rotate(by: angle)
    str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attributes)
    context.restoreGState()
}

private func drawArcText(
    _ text: String,
    center: CGPoint,
    radius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    attributes: [NSAttributedString.Key: Any],
    outward: Bool
) {
    let chars = Array(text)
    guard chars.count > 1 else { return }
    for (index, char) in chars.enumerated() {
        let t = CGFloat(index) / CGFloat(chars.count - 1)
        let angle = startAngle + (endAngle - startAngle) * t
        let point = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
        let rotation = outward ? angle + .pi / 2 : angle - .pi / 2
        drawCenteredText(String(char), at: point, angle: rotation, attributes: attributes)
    }
}

private nonisolated(unsafe) var _weightDiscMaterialCache: [String: UnlitMaterial] = [:]
private nonisolated(unsafe) var _engravingDiscMaterialCache: [String: UnlitMaterial] = [:]

private func makeWeightDisc(weightKg: Double, tier: PlateTier) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    let artwork = PlateVisualDesign.faceArtwork(for: tier.style)
    let layout = PlateVisualDesign.markingLayout(for: tier.style)
    let label = weightKg.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(weightKg))" : String(format: "%.1f", weightKg)
    let cacheKey = "\(tier.id)_\(label)"
    let material: UnlitMaterial
    if let cached = _weightDiscMaterialCache[cacheKey] {
        material = cached
    } else {
        material = makeWeightDiscMaterial(label: label, tier: tier, artwork: artwork)
        _weightDiscMaterialCache[cacheKey] = material
    }

    let outerRadius = min(profile.faceOuterRadius * 0.72, Float(layout.markingRadiusRatio) * profile.outerRadius)
    let disc = ModelEntity(mesh: cachedPlateRing(height: 0.001, outerRadius: outerRadius, innerRadius: plateBoreRadius), materials: [material])
    // Sit above hub/progression detail layers to avoid label z-fighting shimmer in RealityKit.
    disc.position = SIMD3(0, profile.thickness * 0.5 + 0.010, 0)
    return disc
}

private func makeWeightDiscMaterial(
    label: String,
    tier: PlateTier,
    artwork: PlateFaceArtworkPolicy
) -> UnlitMaterial {
    let side: CGFloat = 128
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    let image = renderer.image { ctx in
        UIColor.clear.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let textColor = bumperPlateTextColor(for: tier)
        if artwork.showsBrandText {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.145, weight: .black),
                .foregroundColor: textColor.withAlphaComponent(0.82)
            ]
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = side * 0.365
            drawArcText(
                artwork.brandText,
                center: center,
                radius: radius,
                startAngle: -.pi * 0.78,
                endAngle: -.pi * 0.22,
                attributes: attrs,
                outward: true
            )
            drawArcText(
                artwork.brandText,
                center: center,
                radius: radius,
                startAngle: .pi * 0.22,
                endAngle: .pi * 0.78,
                attributes: attrs,
                outward: false
            )
        }
        let weightAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: side * 0.080),
            .foregroundColor: textColor.withAlphaComponent(0.78)
        ]
        let sideLabel = "\(label) KG"
        drawCenteredText(
            sideLabel,
            at: CGPoint(x: side * 0.76, y: side * 0.52),
            angle: .pi / 2,
            attributes: weightAttrs
        )
        drawCenteredText(
            sideLabel,
            at: CGPoint(x: side * 0.24, y: side * 0.48),
            angle: -.pi / 2,
            attributes: weightAttrs
        )
    }
    var mat = UnlitMaterial()
    if let cg = image.cgImage,
       let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
        mat.color = .init(texture: .init(tex))
    }
    return mat
}

// MARK: - Engraving disc

private func bumperPlateTextColor(for tier: PlateTier) -> UIColor {
    // White Bumper and any other light-colored plate need dark text.
    let face = PlateDisplaySurface.faceColor(for: tier)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    face.getRed(&r, green: &g, blue: &b, alpha: &a)
    let luminance = 0.299 * r + 0.587 * g + 0.114 * b
    return luminance > 0.65 ? UIColor(white: 0.12, alpha: 1) : .white
}

private func makeEngravingDisc(engravingText: String, tier: PlateTier, prominent: Bool) -> ModelEntity {
    let profile = PlateVisualDesign.profile(for: tier.style)
    let layout = PlateVisualDesign.markingLayout(for: tier.style)
    let cacheKey = "\(tier.id)_\(prominent)_\(engravingText)"
    let material: UnlitMaterial
    if let cached = _engravingDiscMaterialCache[cacheKey] {
        material = cached
    } else {
        let built = makeEngravingDiscMaterial(engravingText: engravingText, tier: tier, prominent: prominent)
        _engravingDiscMaterialCache[cacheKey] = built
        material = built
    }
    let outerRadius = min(profile.faceOuterRadius * 0.72, Float(layout.markingRadiusRatio) * profile.outerRadius)
    let disc = ModelEntity(
        mesh: cachedPlateRing(height: 0.001, outerRadius: outerRadius, innerRadius: plateBoreRadius),
        materials: [material]
    )
    disc.name = "engravingDisc"
    // Sit 3 mm above the weight disc (+0.010) to avoid z-fighting.
    disc.position = SIMD3(0, profile.thickness * 0.5 + 0.013, 0)
    return disc
}

private func makeEngravingDiscMaterial(engravingText: String, tier: PlateTier, prominent: Bool) -> UnlitMaterial {
    let side: CGFloat = 128
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    let textColor = bumperPlateTextColor(for: tier)

    let image = renderer.image { _ in
        if prominent {
            // Milestone plates: split "25 Workouts" -> large "25" over smaller "WORKOUTS".
            let parts = engravingText.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let numStr = String(parts[0])
                let labelStr = String(parts[1]).uppercased()
                let numAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: side * 0.30, weight: .black),
                    .foregroundColor: textColor.withAlphaComponent(0.92)
                ]
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: side * 0.145, weight: .heavy),
                    .foregroundColor: textColor.withAlphaComponent(0.78)
                ]
                let numSz = (numStr as NSString).size(withAttributes: numAttrs)
                let labelSz = (labelStr as NSString).size(withAttributes: labelAttrs)
                let totalH = numSz.height + 2 + labelSz.height
                (numStr as NSString).draw(
                    at: CGPoint(x: (side - numSz.width) / 2, y: (side - totalH) / 2),
                    withAttributes: numAttrs
                )
                (labelStr as NSString).draw(
                    at: CGPoint(x: (side - labelSz.width) / 2, y: (side + totalH) / 2 - labelSz.height),
                    withAttributes: labelAttrs
                )
            } else {
                drawFittedEngravingText(engravingText, side: side, maxFontSize: side * 0.165, weight: .black, color: textColor.withAlphaComponent(0.92))
            }
        } else {
            drawFittedEngravingText(engravingText, side: side, maxFontSize: side * 0.115, weight: .bold, color: textColor.withAlphaComponent(0.80))
        }
    }

    var mat = UnlitMaterial()
    if let cg = image.cgImage,
       let tex = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
        mat.color = .init(texture: .init(tex))
        mat.blending = .transparent(opacity: .init(floatLiteral: 1.0))
    }
    return mat
}

private func drawFittedEngravingText(
    _ text: String,
    side: CGFloat,
    maxFontSize: CGFloat,
    weight: UIFont.Weight,
    color: UIColor
) {
    var fontSize = maxFontSize
    var font = UIFont.systemFont(ofSize: fontSize, weight: weight)
    var sz = (text as NSString).size(withAttributes: [.font: font])
    let maxWidth = side * 0.88
    while sz.width > maxWidth && fontSize > 7 {
        fontSize -= 1
        font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        sz = (text as NSString).size(withAttributes: [.font: font])
    }
    (text as NSString).draw(
        at: CGPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2),
        withAttributes: [.font: font, .foregroundColor: color]
    )
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
///   - options: Controls whether runtime-only components are attached. Defaults to a fully
///              interactive plate using `role`; preview/showcase surfaces can pass `.visualOnly`.
///
/// Physics: when enabled, PhysicsBodyComponent is set with mode .kinematic.
/// Gesture handlers switch to .dynamic on release so the plate settles via physics,
/// then back to .kinematic after ~800ms settling time.
func makePlateEntity(
    tierID: Int,
    textures: PlateTextures? = nil,
    material: PhysicallyBasedMaterial? = nil,
    weightKg: Double = 0,
    engravingText: String = "",
    prominentEngraving: Bool = false,
    showEngravings: Bool = true,
    renderProjection: BarbellPlateRenderProjection = BarbellPlateRenderProjection(),
    role: PlateRoleComponent.Role = .floor,
    options: PlateEntityBuildOptions? = nil
) -> ModelEntity {
    guard let tier = PlateTier.all.first(where: { $0.id == tierID }) else {
        return ModelEntity()
    }

    let buildOptions = options ?? .interactive(role: role)
    let profile = PlateVisualDesign.profile(for: tier.style)
    let plateThickness = profile.thickness
    let materialCache = PlateMaterialCache()
    let entity: ModelEntity

    switch tier.style {
    case .rawIron:
        entity = makeRawIronEntity(tier: tier, textures: textures, material: material)
    case .castIron:
        entity = makeCastIronEntity(tier: tier, textures: textures, material: material)
    case .bumper:
        entity = makeBumperEntity(tier: tier, textures: textures, material: material, cache: materialCache)
    case .brass:
        entity = makeBrassEntity(tier: tier, textures: textures, material: material)
    case .starter:
        entity = makeStarterEntity(tier: tier)
    case .competition:
        entity = makeCompetitionEntity(tier: tier, material: material, cache: materialCache)
    case .polishedSteel, .gold:
        // High-tier plates use the base cylinder shape with their own PBR properties;
        // chrome rings are competition-specific and must not appear on these tiers.
        entity = makeRawIronEntity(tier: tier, textures: textures, material: material)
    }

    // Weight disc
    // Note: the chrome hub ring is now added by each style builder via makeCenterBoss.
    // Adding a second hub disc here at the same radius caused z-fighting with the boss geometry.
    let artwork = PlateVisualDesign.faceArtwork(for: tier.style, showEngravings: showEngravings)
    if artwork.showsWeightText && weightKg > 0 && tierID != 7 {
        addFaceDetailPair(makeWeightDisc(weightKg: weightKg, tier: tier), to: entity, profile: profile)
    }
    if tierID != 7 {
        addFaceDetailPair(makeGlossAccentRing(profile: profile, tier: tier), to: entity, profile: profile)
    }
    if showEngravings && !engravingText.isEmpty && tierID != 7 {
        addFaceDetailPair(makeEngravingDisc(engravingText: engravingText, tier: tier, prominent: prominentEngraving), to: entity, profile: profile)
    }
    if tierID != 7 {
        addProgressionDetails(to: entity, projection: renderProjection, plateThickness: plateThickness)
    }

    // Gesture + physics collider. Use four ring segments instead of one solid box so the
    // barbell can occupy the real center hole instead of colliding with an invisible plug.
    if buildOptions.includesInput {
        entity.components.set(InputTargetComponent())
    }
    if buildOptions.includesCollision {
        let collisionRadius = profile.outerRadius
        let collisionShapes = plateRingCollisionShapes(
            outerRadius: collisionRadius,
            innerRadius: plateBoreRadius,
            thickness: plateThickness
        )
        entity.components.set(CollisionComponent(shapes: collisionShapes, filter: plateCollisionFilter))
    }

    // Physics -- kinematic by default; gesture handlers switch to .dynamic on release
    let audioCategory = PlateAudioCategory.from(tierID: tierID)
    if buildOptions.includesPhysics {
        var physicsBody = PhysicsBodyComponent()
        physicsBody.massProperties = .init(mass: Float(max(weightKg, 1.25)))
        physicsBody.material = audioCategory.physicsMaterial
        physicsBody.mode = .kinematic
        entity.components.set(physicsBody)
        entity.components.set(PhysicsMotionComponent())
    }

    // Metadata components
    entity.components.set(PlateRoleComponent(role: buildOptions.role))
    entity.components.set(TierIDComponent(tierID: tierID))
    entity.components.set(PlateAudioCategoryComponent(category: audioCategory))

    // Transparent tiers need explicit sort order to prevent z-fighting
    if tier.style == .starter {
        entity.components.set(ModelSortGroupComponent(
            group: ModelSortGroup(depthPass: .postPass), order: 0
        ))
    }

    // Spatial audio source -- must be set before playAudio() is called
    if buildOptions.includesAudio {
        attachSpatialAudio(to: entity, category: audioCategory)
    }

    return entity
}

private func addProgressionDetails(
    to entity: ModelEntity,
    projection: BarbellPlateRenderProjection,
    plateThickness: Float
) {
    guard projection != BarbellPlateRenderProjection() else { return }

    let faceY = plateThickness * 0.5 + 0.004
    for index in 0..<projection.tierRingCount {
        let outerRadius = Float(0.198 - Double(index) * 0.020)
        let innerRadius = max(plateBoreRadius + 0.010, outerRadius - 0.004)
        let alpha = CGFloat(0.92 - Double(index) * 0.14)
        let mat = pbrMaterial(
            color: projection.tierAccentColor.withAlphaComponent(alpha),
            metallic: projection.progressionTier == .iron ? 0.25 : 0.9,
            roughness: projection.progressionTier == .gold ? 0.18 : 0.26,
            clearcoat: projection.progressionTier.rank >= BarbellPlateProgressionTier.chrome.rank ? 0.35 : 0
        )
        let ring = ModelEntity(
            mesh: cachedPlateRing(height: 0.001, outerRadius: outerRadius, innerRadius: innerRadius),
            materials: [mat]
        )
        ring.position.y = faceY + Float(index) * 0.0002
        entity.addChild(ring)
    }

    let chalkMat = pbrMaterial(color: UIColor(white: 0.88, alpha: 0.72), metallic: 0, roughness: 0.96)
    for index in 0..<projection.chalkMarkCount {
        let angle = Float(index) * 1.37
        let radius = Float(0.105 + 0.012 * Float(index % 3))
        let mark = ModelEntity(mesh: cachedBox(size: SIMD3(0.028, 0.0015, 0.006)), materials: [chalkMat])
        mark.position = SIMD3(cos(angle) * radius, faceY + 0.002, sin(angle) * radius)
        mark.orientation = simd_quatf(angle: angle + .pi / 5, axis: SIMD3(0, 1, 0))
        entity.addChild(mark)
    }

    let wearMat = pbrMaterial(color: UIColor(white: 0.10, alpha: 0.55), metallic: 0.15, roughness: 0.82)
    for index in 0..<projection.gripWearMarkCount {
        let angle = Float(index) * 1.05 + 0.32
        let mark = ModelEntity(mesh: cachedBox(size: SIMD3(0.040, 0.0018, 0.004)), materials: [wearMat])
        mark.position = SIMD3(cos(angle) * 0.168, faceY + 0.003, sin(angle) * 0.168)
        mark.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        entity.addChild(mark)
    }

    let polishMat = pbrMaterial(color: UIColor(white: 1.0, alpha: 0.42), metallic: 1, roughness: 0.18)
    for index in 0..<projection.pressPolishMarkCount {
        let angle = Float(index) * 1.23 + 0.74
        let mark = ModelEntity(mesh: cachedBox(size: SIMD3(0.018, 0.0015, 0.018)), materials: [polishMat])
        mark.position = SIMD3(cos(angle) * 0.075, faceY + 0.004, sin(angle) * 0.075)
        mark.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        entity.addChild(mark)
    }
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
    let useStaticFallback = BarbellRealityPerformanceBudget.shouldUseStaticFallback(forTierID: tierID)
    var mat = pbrMaterial(
        color: PlateDisplaySurface.faceColor(for: tier),
        metallic: PlateDisplaySurface.metallic(for: tier),
        roughness: useStaticFallback ? max(PlateDisplaySurface.roughness(for: tier), 0.45) : PlateDisplaySurface.roughness(for: tier),
        clearcoat: useStaticFallback ? 0 : PlateDisplaySurface.clearcoat(for: tier),
        clearcoatRoughness: useStaticFallback ? 1 : tier.clearcoatRoughness
    )
    if !useStaticFallback, let tex = textures {
        if let a = tex.albedo    { mat.baseColor  = .init(tint: PlateDisplaySurface.faceColor(for: tier), texture: .init(a)) }
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

func makeRackStandEntity(rackStyleID: String = "matte_black") -> ModelEntity {
    let bodyMat: PhysicallyBasedMaterial
    let hookMat: PhysicallyBasedMaterial
    switch rackStyleID {
    case "brushed_steel":
        bodyMat = pbrMaterial(color: UIColor(red: 0.70, green: 0.72, blue: 0.75, alpha: 1), metallic: 0.85, roughness: 0.30)
        hookMat = pbrMaterial(color: UIColor(red: 0.75, green: 0.77, blue: 0.80, alpha: 1), metallic: 0.90, roughness: 0.22)
    case "brass_accent_rack":
        bodyMat = pbrMaterial(color: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1), metallic: 0.50, roughness: 0.58)
        hookMat = pbrMaterial(color: UIColor(red: 0.90, green: 0.68, blue: 0.24, alpha: 1), metallic: 0.95, roughness: 0.12)
    default: // matte_black
        bodyMat = pbrMaterial(color: UIColor(white: 0.25, alpha: 1), metallic: 0.3, roughness: 0.75)
        hookMat = pbrMaterial(color: UIColor(white: 0.62, alpha: 1), metallic: 0.55, roughness: 0.35)
    }

    let rackFilter = CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
    var staticBody = PhysicsBodyComponent()
    staticBody.mode = .static

    let stand = Entity()
    let post = ModelEntity(
        mesh: cachedCylinder(height: 1.0, radius: 0.025),
        materials: [bodyMat]
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
        materials: [bodyMat]
    )
    foot.position = SIMD3(0, -0.51, 0)
    stand.addChild(foot)

    // J-hook saddle -- bar (radius 0.012) rests in the shelf channel.
    // Stand is at world y=0.3; bar center is at world y=0.6 -> stand-local barLocalY=0.30.
    // Shelf top is placed at bar bottom (barLocalY - barRadius) so bar visually rests on it.
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

    if rackStyleID == "brass_accent_rack" {
        let accentMat = pbrMaterial(color: UIColor(red: 0.90, green: 0.68, blue: 0.24, alpha: 1), metallic: 0.95, roughness: 0.12)
        let bandMesh = cachedBox(size: SIMD3(0.070, 0.030, 0.070))
        for y in [-0.30, 0.06, 0.42] as [Float] {
            let band = ModelEntity(mesh: bandMesh, materials: [accentMat])
            band.position = SIMD3(0, y, 0)
            stand.addChild(band)
        }

        let footCap = ModelEntity(
            mesh: cachedBox(size: SIMD3(0.135, 0.018, 0.090)),
            materials: [accentMat]
        )
        footCap.position = SIMD3(0, -0.485, 0)
        stand.addChild(footCap)
    }

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
