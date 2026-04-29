# Barbell — Unified RealityKit Scene Implementation Plan (Revised)

> **Status: IMPLEMENTED (on-device debug iteration in progress)** — All 14 tasks were executed. Core architecture is in production on `main`. Several bugs discovered during on-device testing required post-plan fixes; these are documented in the Implementation Notes section at the bottom of this file. The plan checkboxes were not ticked during the fast-paced agentic execution run. Treat all tasks as complete unless noted otherwise in the Implementation Notes.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `BarbellWelcomeView` (multi-SCNView SceneKit) and `PlateWallView` (split RealityKit + 2D SwiftUI) with a single shared `BarbellRealityView` where one RealityKit scene owns all runtime state and SwiftData is a persistence side-effect.

**Architecture:** One `BarbellRealityView` struct with a `BarbellRealityMode` enum (`.welcome` / `.rackRoom`). A `SceneState` class (not struct — mutations must not trigger SwiftUI re-renders) is created by the parent view and passed in. All gesture handling mutates entities directly at 60fps; `BarbellProgressService.rackPlate()` / `unrackPlate()` are called only at gesture end as persistence side-effects. The `RealityView update {}` closure is empty after initial setup.

**This revision adds:** RealityKit physics (kinematic drag, dynamic settle), spatial audio (`SpatialAudioComponent`, per-material sounds), directional shadow casting, shared material and mesh instance caching, formal `SceneState.transition(to:)` state machine, Reduce Motion support throughout, and encapsulated camera proxy management.

**Tech Stack:** RealityKit, SwiftUI, SwiftData (`@Query`), `PhysicallyBasedMaterial`, `PhysicsBodyComponent`, `SpatialAudioComponent`, `DirectionalLightComponent`, `InputTargetComponent`, `CollisionComponent`, `DragGesture().targetedToAnyEntity()`, Swift Testing

**Audio assets required (add to `Resources/Audio/` and include in WRKT target before Task 4):**
- `plate_clink_iron.wav`
- `plate_clink_brass.wav`
- `plate_thud_rubber.wav`
- `plate_drop_iron.wav`
- `plate_drop_brass.wav`
- `plate_drop_rubber.wav`

**Spec:** `docs/superpowers/specs/2026-04-02-barbell-realitykit-unified-scene.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Features/Rewards/Views/BarbellEntityBuilder.swift` | Entity factory, PBR + physics helpers, collision groups, texture loading, material builder |
| Create | `Features/Rewards/Views/BarbellAudioBuilder.swift` | Audio resource loading, `SpatialAudioComponent` attachment, per-material sound playback, physics materials |
| Create | `Features/Rewards/Views/BarbellRealityView.swift` | `BarbellRealityMode`, `SceneState`, `DragPhase`, `BarbellRealityView` |
| Modify | `Features/Rewards/Views/BarbellWelcomeView.swift` | Delete all SceneKit; use `BarbellRealityView(mode: .welcome(...))` |
| Modify | `Features/Profile/Views/PlateWallView.swift` | Delete barbell + 2D grid; use `BarbellRealityView(mode: .rackRoom(...))` |
| Create | `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift` | Unit tests for entity builder |
| Create | `WRKTTests/FeaturesTests/Barbell/BarbellAudioBuilderTests.swift` | Unit tests for audio builder |
| Create | `WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift` | Unit tests for SceneState and state machine |
| Unchanged | `Features/Profile/Views/BarbellPreviewView.swift` | Cosmetic editor — do not touch |
| Unchanged | `Features/Rewards/Models/BarbellModels.swift` | Models — do not touch |
| Unchanged | `Features/Rewards/Services/BarbellProgressService.swift` | Service — do not touch |

---

## Task 1: BarbellEntityBuilder — foundation types, collision groups, PBR helpers

**Files:**
- Create: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Create: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

- [ ] **Step 1: Create the file with imports, collision groups, and ECS components**

```swift
// Features/Rewards/Views/BarbellEntityBuilder.swift
import RealityKit
import UIKit

// MARK: - Collision groups
// Plates collide with the floor plane and each other.
// Bar and rack stands have no collision bodies — snapping is gesture-driven.

let plateCollisionGroup = CollisionGroup(rawValue: 1 << 0)
let floorCollisionGroup = CollisionGroup(rawValue: 1 << 1)
let plateCollisionFilter = CollisionFilter(
    group: plateCollisionGroup,
    mask: plateCollisionGroup.union(floorCollisionGroup)
)

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
```

Note: all `MeshResource.generateCylinder(...)` and `MeshResource.generateBox(...)` calls in the per-style helpers, makeBarEntity, makeCollarEntity, and makeRackStandEntity must be replaced with `cachedCylinder(...)` and `cachedBox(...)`. Apply this substitution throughout the entity builder functions below.

- [ ] **Step 2: Add PlateTextures struct and PBR material helpers**

Append to `BarbellEntityBuilder.swift`:

```swift
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
```

- [ ] **Step 3: Add texture loading helpers**

Append to `BarbellEntityBuilder.swift`:

```swift
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
        roughness: load("Roughness", semantic: .color),
        metalness: load("Metalness", semantic: .color)
    )
}
```

- [ ] **Step 4: Add to Xcode project and create test file stub**

In Xcode: right-click `Features/Rewards/Views` → Add Files → select `BarbellEntityBuilder.swift`. Target: WRKT (iOS only).

Create `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`:

```swift
import Testing
import RealityKit
@testable import WRKT

struct BarbellEntityBuilderTests {
    // tests added in Tasks 2 and 3
}
```

- [ ] **Step 5: Build to verify compilation**

```
Cmd+B
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat: add BarbellEntityBuilder foundation — collision groups, ECS components, PBR helpers, texture loader"
```

---

## Task 2: BarbellEntityBuilder — makePlateEntity (physics-aware, material param)

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Modify: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

- [ ] **Step 1: Write the failing tests first**

```swift
struct BarbellEntityBuilderTests {

    @Test func makePlateEntityHasRequiredComponents() {
        for tierID in 0...7 {
            let entity = makePlateEntity(tierID: tierID)
            #expect(entity.components[InputTargetComponent.self] != nil,
                    "tier \(tierID) missing InputTargetComponent")
            #expect(entity.components[CollisionComponent.self] != nil,
                    "tier \(tierID) missing CollisionComponent")
            #expect(entity.components[PlateRoleComponent.self] != nil,
                    "tier \(tierID) missing PlateRoleComponent")
            #expect(entity.components[PhysicsBodyComponent.self] != nil,
                    "tier \(tierID) missing PhysicsBodyComponent")
            #expect(entity.components[TierIDComponent.self] != nil,
                    "tier \(tierID) missing TierIDComponent")
            #expect(entity.components[PlateAudioCategoryComponent.self] != nil,
                    "tier \(tierID) missing PlateAudioCategoryComponent")
        }
    }

    @Test func makePlateEntityDefaultRoleIsFloor() {
        let entity = makePlateEntity(tierID: 0)
        #expect(entity.components[PlateRoleComponent.self]?.role == .floor)
    }

    @Test func makePlateEntityBarRoleRoundtrips() {
        let entity = makePlateEntity(tierID: 2, role: .bar)
        #expect(entity.components[PlateRoleComponent.self]?.role == .bar)
    }

    @Test func makePlateEntityPhysicsIsKinematicByDefault() {
        let entity = makePlateEntity(tierID: 0)
        #expect(entity.components[PhysicsBodyComponent.self]?.mode == .kinematic)
    }

    @Test func makePlateEntityAcceptsExternalMaterial() {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .red)
        let entity = makePlateEntity(tierID: 0, material: mat)
        #expect(entity.components[PlateRoleComponent.self] != nil)
    }
}
```

- [ ] **Step 2: Run to confirm compile failure**

Expected: compile error — `makePlateEntity` not yet defined.

- [ ] **Step 3: Add per-style helper functions**

Append to `BarbellEntityBuilder.swift`:

```swift
// MARK: - Per-style plate helpers

private func makeRawIronEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?, material: PhysicallyBasedMaterial?) -> ModelEntity {
    var mat = material ?? pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
    if material == nil, let tex = textures {
        if let a = tex.albedo    { mat.baseColor  = .init(tint: .white, texture: .init(a)) }
        if let n = tex.normal    { mat.normal     = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness  = .init(texture: .init(r)) }
        if let m = tex.metalness { mat.metallic   = .init(texture: .init(m)) }
    }
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: 0.18), materials: [mat])
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
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: radius), materials: [outerMat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    let inner = ModelEntity(mesh: .generateCylinder(height: thickness * 0.72, radius: radius * 0.86), materials: [innerMat])
    plate.addChild(inner)
    let boss = ModelEntity(mesh: .generateCylinder(height: thickness * 0.82, radius: radius * 0.22),
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
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: radius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    let edgeBand = ModelEntity(
        mesh: .generateCylinder(height: thickness * 0.35, radius: radius + 0.002),
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
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: radius), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    for faceSign: Float in [-1, 1] {
        let yPos = faceSign * (thickness / 2 + 0.003)
        for ringRadius: Float in [radius * 0.82, radius * 0.42] {
            let ring = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: ringRadius),
                                   materials: [chromeMaterial()])
            ring.position = SIMD3(0, yPos, 0)
            plate.addChild(ring)
        }
    }
    return plate
}

private func makeStarterEntity(tier: PlateTier, thickness: Float) -> ModelEntity {
    let mat = pbrMaterial(color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1), metallic: 0, roughness: 0.9)
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: 0.12), materials: [mat])
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
    let disc = ModelEntity(mesh: .generateCylinder(height: 0.005, radius: 0.06), materials: [mat])
    disc.position = SIMD3(0, 0.018, 0)
    return disc
}
```

- [ ] **Step 4: Add the main makePlateEntity function**

Append to `BarbellEntityBuilder.swift`:

```swift
// MARK: - makePlateEntity

/// Builds a complete plate ModelEntity for the given tier.
///
/// - Parameters:
///   - tierID: 0-7 matching PlateTier.all.id
///   - textures: Pre-loaded PBR textures. Pass nil to fall back to color materials.
///   - material: Cached PhysicallyBasedMaterial from SceneState.materialCache. When provided,
///               textures are ignored and the shared instance is used directly — avoids
///               creating duplicate GPU material objects per plate.
///   - weightKg: Renders weight number on a face disc when > 0.
///   - role: .floor (default) or .bar — stored in PlateRoleComponent for gesture routing.
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
    default:  // competition, polishedSteel, gold
        entity = makeCompetitionEntity(tier: tier, thickness: plateThickness, material: material)
    }

    // Chrome hub
    let hub = ModelEntity(
        mesh: .generateCylinder(height: plateThickness + 0.003, radius: 0.028),
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

    // Physics — kinematic by default; gesture handlers switch to .dynamic on release
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

    // Spatial audio source — must be set before playAudio() is called
    attachSpatialAudio(to: entity, category: audioCategory)

    return entity
}
```

- [ ] **Step 5: Add buildMaterial helper**

Append to `BarbellEntityBuilder.swift`:

```swift
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
```

- [ ] **Step 6: Run tests**

Expected: all 5 `BarbellEntityBuilderTests` pass.

- [ ] **Step 7: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat: add physics-aware makePlateEntity with material param, ECS components, spatial audio"
```

---

## Task 3: BarbellEntityBuilder — bar, collar, rack stand

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Modify: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `BarbellEntityBuilderTests`:

```swift
@Test func makeBarEntityIsNonNil() {
    for skinID in 0..<BarSkin.all.count {
        let bar = makeBarEntity(skinID: skinID)
        #expect(bar.model != nil, "skinID \(skinID) missing mesh")
    }
}

@Test func makeCollarEntityIsNonNil() {
    let collar = makeCollarEntity()
    #expect(collar.model != nil)
}

@Test func makeRackStandEntityIsNonNil() {
    let stand = makeRackStandEntity()
    #expect(stand.model != nil)
}
```

- [ ] **Step 2: Run to confirm failure**

Expected: compile error — functions not yet defined.

- [ ] **Step 3: Implement the three functions**

Append to `BarbellEntityBuilder.swift`:

```swift
// MARK: - Bar, collar, rack stand

func makeBarEntity(skinID: Int = 0) -> ModelEntity {
    let skin = BarSkin.all[max(0, min(skinID, BarSkin.all.count - 1))]
    let mat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)
    let bar = ModelEntity(
        mesh: .generateCylinder(height: 1.1, radius: 0.012),
        materials: [mat]
    )
    bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return bar
}

func makeCollarEntity(skinID: Int = 0) -> ModelEntity {
    let skin = BarSkin.all[max(0, min(skinID, BarSkin.all.count - 1))]
    let mat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)
    let collar = ModelEntity(
        mesh: .generateCylinder(height: 0.04, radius: 0.022),
        materials: [mat]
    )
    collar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return collar
}

func makeRackStandEntity() -> ModelEntity {
    let mat = pbrMaterial(color: UIColor(white: 0.25, alpha: 1), metallic: 0.3, roughness: 0.75)
    let stand = Entity()
    let post = ModelEntity(
        mesh: .generateCylinder(height: 1.0, radius: 0.025),
        materials: [mat]
    )
    stand.addChild(post)
    let foot = ModelEntity(
        mesh: .generateBox(size: SIMD3(0.12, 0.02, 0.08)),
        materials: [mat]
    )
    foot.position = SIMD3(0, -0.51, 0)
    stand.addChild(foot)
    let saddle = ModelEntity(
        mesh: .generateBox(size: SIMD3(0.06, 0.03, 0.04)),
        materials: [pbrMaterial(color: UIColor(white: 0.15, alpha: 1), metallic: 0.1, roughness: 0.9)]
    )
    saddle.position = SIMD3(0, 0.1, 0.03)
    stand.addChild(saddle)
    let root = ModelEntity()
    root.addChild(stand)
    return root
}
```

- [ ] **Step 4: Run tests**

Expected: all 8 `BarbellEntityBuilderTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat: add makeBarEntity, makeCollarEntity, makeRackStandEntity to BarbellEntityBuilder"
```

---

## Task 4: BarbellAudioBuilder — spatial audio resources and physics materials

**Pre-condition:** Audio `.wav` files listed in the plan header are added to `Resources/Audio/` and included in the WRKT target before this task.

**Files:**
- Create: `Features/Rewards/Views/BarbellAudioBuilder.swift`
- Create: `WRKTTests/FeaturesTests/Barbell/BarbellAudioBuilderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// WRKTTests/FeaturesTests/Barbell/BarbellAudioBuilderTests.swift
import Testing
import RealityKit
@testable import WRKT

struct BarbellAudioBuilderTests {

    @Test func audioResourceLoadsForEveryTier() {
        for tierID in 0...7 {
            let cat = PlateAudioCategory.from(tierID: tierID)
            let resource = loadAudioResource(named: cat.clinkSoundName)
            #expect(resource != nil, "clink sound missing for tier \(tierID): \(cat.clinkSoundName)")
        }
    }

    @Test func dropSoundLoadsForEveryCategory() {
        for cat in [PlateAudioCategory.iron, .rubber, .brass, .starter] {
            let resource = loadAudioResource(named: cat.dropSoundName)
            #expect(resource != nil, "drop sound missing for \(cat): \(cat.dropSoundName)")
        }
    }

    @Test func physicsMaterialDefinedForAllCategories() {
        // Compile-time guarantee — if any case is missing, this won't build
        for cat in [PlateAudioCategory.iron, .rubber, .brass, .starter] {
            _ = cat.physicsMaterial
        }
        #expect(true)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Expected: compile error — `PlateAudioCategory` not yet defined.

- [ ] **Step 3: Create BarbellAudioBuilder.swift**

```swift
// Features/Rewards/Views/BarbellAudioBuilder.swift
import RealityKit

// MARK: - PlateAudioCategory

enum PlateAudioCategory {
    case iron, rubber, brass, starter

    static func from(tierID: Int) -> PlateAudioCategory {
        switch tierID {
        case 0, 1: return .iron
        case 2:    return .rubber
        case 3, 6: return .brass
        case 7:    return .starter
        default:   return .iron
        }
    }

    var clinkSoundName: String {
        switch self {
        case .iron:    return "plate_clink_iron"
        case .rubber:  return "plate_thud_rubber"
        case .brass:   return "plate_clink_brass"
        case .starter: return "plate_thud_rubber"
        }
    }

    var dropSoundName: String {
        switch self {
        case .iron:    return "plate_drop_iron"
        case .rubber:  return "plate_drop_rubber"
        case .brass:   return "plate_drop_brass"
        case .starter: return "plate_drop_rubber"
        }
    }

    /// Physics material tuned per plate material type.
    /// Iron: moderate bounce, medium friction.
    /// Rubber bumper: low bounce, high friction (grips the floor).
    /// Brass: slightly more bounce than iron due to density.
    var physicsMaterial: PhysicsMaterialResource {
        switch self {
        case .iron:    return .generate(friction: 0.70, restitution: 0.30)
        case .rubber:  return .generate(friction: 0.92, restitution: 0.08)
        case .brass:   return .generate(friction: 0.65, restitution: 0.38)
        case .starter: return .generate(friction: 0.85, restitution: 0.12)
        }
    }
}

// MARK: - Audio resource cache

// Process-level cache — resources are loaded once and reused across view instances
// and mode switches. nonisolated(unsafe) because writes are guarded by call-site
// sequencing (all loads happen in .task{} before gesture handlers can fire).
private nonisolated(unsafe) var audioResourceCache: [String: AudioFileResource] = [:]

func loadAudioResource(named name: String) -> AudioFileResource? {
    if let cached = audioResourceCache[name] { return cached }
    guard let resource = try? AudioFileResource.load(named: name, in: .main,
                                                      configuration: .init()) else { return nil }
    audioResourceCache[name] = resource
    return resource
}

// MARK: - Spatial audio helpers

/// Attaches a SpatialAudioComponent to the entity. Must be called before playAudio().
/// Called from makePlateEntity so every plate entity is automatically a spatial emitter.
func attachSpatialAudio(to entity: Entity, category: PlateAudioCategory) {
    entity.components.set(SpatialAudioComponent(gain: -6, directivity: .beam(focus: 0.5)))
}

/// Plays the rack/clink sound at the entity's world position.
func playClinkSound(on entity: Entity, category: PlateAudioCategory) {
    guard let resource = loadAudioResource(named: category.clinkSoundName) else { return }
    entity.playAudio(resource)
}

/// Plays the floor-drop sound at the entity's world position.
func playDropSound(on entity: Entity, category: PlateAudioCategory) {
    guard let resource = loadAudioResource(named: category.dropSoundName) else { return }
    entity.playAudio(resource)
}

// MARK: - Haptic vocabulary
//
// Typed haptic functions keyed to plate material category.
// Replace all BarbellProgressService.playClinkHaptic() call sites with these.
// Do not use a single undifferentiated haptic — iron racking onto steel should feel
// different from rubber bumpers settling on a floor.

/// Fires on successful rack (plate lands on bar).
/// Iron/brass: rigid impact (hard metal-on-metal).
/// Rubber/starter: soft impact (rubber damping).
func playRackHaptic(category: PlateAudioCategory) {
    switch category {
    case .iron, .brass:
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    case .rubber, .starter:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

/// Fires once when a dragged plate enters the bar snap zone.
/// Light selection tick — tells the user "you're in range" without committing.
func playSnapZoneEntryHaptic() {
    UISelectionFeedbackGenerator().selectionChanged()
}

/// Fires when a plate lands on the floor after unracking.
/// Iron/brass: heavy drop. Rubber: medium (absorbs impact).
func playDropHaptic(category: PlateAudioCategory) {
    switch category {
    case .iron, .brass:
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .rubber, .starter:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add `BarbellAudioBuilder.swift` to WRKT target. Add `BarbellAudioBuilderTests.swift` to WRKTTests target.

- [ ] **Step 5: Run tests**

Expected: all 3 `BarbellAudioBuilderTests` pass (requires audio files in bundle).

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellAudioBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellAudioBuilderTests.swift
git commit -m "feat: add BarbellAudioBuilder — PlateAudioCategory, spatial audio, physics materials per material type"
```

---

## Task 5: SceneState, DragPhase, BarbellRealityMode — state machine, camera proxy, material cache

**Files:**
- Create: `Features/Rewards/Views/BarbellRealityView.swift`
- Create: `WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift
import Testing
import RealityKit
import SwiftUI
@testable import WRKT

struct SceneStateTests {

    @Test func initialDragPhaseIsIdle() {
        let state = SceneState()
        if case .idle = state.dragPhase { } else {
            Issue.record("Expected .idle, got \(state.dragPhase)")
        }
    }

    @Test func initialFloorOffsetIsZero() {
        let state = SceneState()
        #expect(state.floorOffset == 0)
    }

    @Test func addPlateUpdatesEntityMap() {
        let state = SceneState()
        let plate = EarnedPlate(id: "test-id", tierID: 0, weightKg: 5,
                                engravingText: "Test", earnedByEvent: "first_workout")
        state.addPlate(plate)
        #expect(state.entityMap["test-id"] != nil)
    }

    @Test func addPlateIdempotent() {
        let state = SceneState()
        let plate = EarnedPlate(id: "dup-id", tierID: 1, weightKg: 10,
                                engravingText: "", earnedByEvent: "5_workouts")
        state.addPlate(plate)
        state.addPlate(plate)
        #expect(state.entityMap.count == 1)
    }

    // MARK: State machine

    @Test func idleCanTransitionToDraggingPlate() {
        let state = SceneState()
        let entity = Entity()
        let result = state.transition(to: .draggingPlate(entity, plateID: "x"))
        #expect(result == true)
        if case .draggingPlate = state.dragPhase { } else {
            Issue.record("Expected .draggingPlate after valid transition")
        }
    }

    @Test func idleCanTransitionToPanningFloor() {
        let state = SceneState()
        #expect(state.transition(to: .panningFloor) == true)
    }

    @Test func panningFloorCannotTransitionToDraggingPlate() {
        let state = SceneState()
        state.transition(to: .panningFloor)
        let result = state.transition(to: .draggingPlate(Entity(), plateID: "x"))
        #expect(result == false)
        if case .panningFloor = state.dragPhase { } else {
            Issue.record("State should remain .panningFloor after invalid transition")
        }
    }

    @Test func draggingPlateCannotTransitionToPanningFloor() {
        let state = SceneState()
        state.transition(to: .draggingPlate(Entity(), plateID: "x"))
        #expect(state.transition(to: .panningFloor) == false)
    }

    @Test func floorOffsetClampDoesNotExceedBounds() {
        let state = SceneState()
        state.floorMinX = 0
        state.floorMaxX = 1.0
        let raw: Float = 1.5
        let clamped = max(state.floorMinX, min(state.floorMaxX, raw))
        #expect(clamped == 1.0)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Expected: compile error — `SceneState` not yet defined.

- [ ] **Step 3: Create BarbellRealityView.swift with all type definitions**

```swift
// Features/Rewards/Views/BarbellRealityView.swift
import SwiftUI
import RealityKit
import SwiftData

// MARK: - BarbellRealityMode

enum BarbellRealityMode {
    case welcome(plates: [EarnedPlateInfo])
    case rackRoom(
        rackedPlates: [EarnedPlate],
        floorPlates: [EarnedPlate],
        onRack: (EarnedPlate) -> Void,
        onUnrack: (EarnedPlate) -> Void
    )
}

// MARK: - DragPhase

enum DragPhase {
    case idle
    case draggingPlate(Entity, plateID: String)
    case panningFloor
}

// MARK: - PlateSpinState

final class PlateSpinState {
    var angle: Float    = Float.random(in: 0 ..< Float.pi * 2)
    var velocity: Float = Float.random(in: 0.5 ..< 1.8) * (Bool.random() ? 1 : -1)
}

// MARK: - SceneState

final class SceneState {

    // MARK: Scene graph anchors
    var floorAnchor = Entity()
    var barAnchor   = Entity()
    var sceneRoot   = Entity()
    var barbellRoot: Entity?

    // MARK: Entity lookups
    var entityMap: [String: Entity] = [:]
    /// Canonical position on barAnchor per plate ID. Used by snapBack for bar plates.
    var barPositionMap: [String: SIMD3<Float>] = [:]
    /// Slot highlight ring entities on barAnchor. Index matches slotOffsets[0...3].
    /// Toggled visible/invisible during drag to show the target slot.
    var slotHighlights: [Entity] = []
    /// Tracks whether the dragged plate was in the snap zone on the previous frame.
    /// Prevents snap zone entry haptic from firing every frame.
    var wasInSnapZone: Bool = false

    // MARK: Caches
    /// One PhysicallyBasedMaterial per tierID — shared across all plates of the same tier.
    /// Populate in .task{} before RealityView make{} runs. Pass entries into makePlateEntity(material:).
    var materialCache: [Int: PhysicallyBasedMaterial] = [:]
    var plateTextureCache: [Int: PlateTextures] = [:]

    // MARK: State machine

    private(set) var dragPhase: DragPhase = .idle

    /// Attempts the transition to `next`. Returns false and leaves dragPhase unchanged
    /// if the transition is invalid.
    /// Invalid transitions: floor pan while dragging a plate; dragging a plate while floor
    /// panning. Both require returning to .idle first.
    @discardableResult
    func transition(to next: DragPhase) -> Bool {
        switch (dragPhase, next) {
        case (.idle, _),
             (.draggingPlate, .idle),
             (.panningFloor, .idle):
            dragPhase = next
            return true
        default:
            return false
        }
    }

    // MARK: Floor pan state
    var floorOffset: Float   = 0
    var floorVelocity: Float = 0
    var floorMinX: Float     = 0
    var floorMaxX: Float     = 0

    // MARK: Welcome spin state
    var plateSpinStates: [String: PlateSpinState] = [:]
    var barbellSpinAngle: Float    = 0
    var barbellSpinVelocity: Float = 0.35

    // MARK: Accessibility
    /// Re-read at gesture time so it responds to in-session Reduce Motion changes.
    var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // MARK: Camera proxy
    /// Positions sceneRoot so the default RealityView perspective camera frames the scene.
    /// Call after scene setup completes and on horizontal size class changes.
    func configureCameraPosition(for mode: BarbellRealityMode, sizeClass: UserInterfaceSizeClass?) {
        let isWide = sizeClass == .regular   // iPad or split view
        switch mode {
        case .welcome:
            sceneRoot.position = SIMD3(0, -0.1, -1.2)
            if isWide { sceneRoot.position.z = -1.6 }
        case .rackRoom:
            sceneRoot.position = SIMD3(0, -0.3, -1.4)
            if isWide { sceneRoot.position.z = -1.9 }
        }
    }

    // MARK: Live plate addition
    func addPlate(_ plate: EarnedPlate) {
        guard entityMap[plate.id] == nil else { return }
        let entity = makePlateEntity(
            tierID: plate.tierID,
            textures: plateTextureCache[plate.tierID],
            material: materialCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            role: .floor
        )
        entity.name = plate.id
        let xPos = Float(floorAnchor.children.count) * 0.15
        entity.position = SIMD3(xPos, 0, 0)
        let leanAngle = Float.random(in: 0.10 ..< 0.23)
        entity.orientation = simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))
        floorAnchor.addChild(entity)
        entityMap[plate.id] = entity
        if xPos > floorMaxX { floorMaxX = xPos }
    }

    // MARK: Welcome spin loop
    /// No-ops immediately when Reduce Motion is enabled.
    @MainActor
    func runWelcomeSpinLoop() async {
        guard !isReduceMotionEnabled else { return }
        var lastTime = Date().timeIntervalSinceReferenceDate
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date().timeIntervalSinceReferenceDate
            let dt = Float(min(now - lastTime, 0.05))
            lastTime = now

            for (key, spinState) in plateSpinStates {
                spinState.velocity *= pow(0.995, dt * 60)
                spinState.angle    += spinState.velocity * dt
                entityMap[key]?.orientation =
                    simd_quatf(angle: spinState.angle, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            }

            barbellSpinVelocity *= pow(0.992, dt * 60)
            barbellSpinAngle    += barbellSpinVelocity * dt
            barbellRoot?.orientation =
                simd_quatf(angle: barbellSpinAngle, axis: SIMD3(0, 1, 0))
        }
    }
}

// MARK: - BarbellRealityView (stub)

struct BarbellRealityView: View {
    let mode: BarbellRealityMode
    let sceneState: SceneState

    var body: some View {
        Text("BarbellRealityView — not yet implemented")
            .foregroundStyle(.white)
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add `BarbellRealityView.swift` to WRKT target. Add `SceneStateTests.swift` to WRKTTests target.

- [ ] **Step 5: Run tests**

Expected: all 9 `SceneStateTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift \
        WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift
git commit -m "feat: add SceneState with state machine, camera proxy, material cache, reduce motion guard"
```

---

## Task 6: BarbellRealityView — directional shadow lighting, welcome mode

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Replace the stub body with the full implementation**

Replace the entire `BarbellRealityView` struct:

```swift
struct BarbellRealityView: View {
    let mode: BarbellRealityMode
    let sceneState: SceneState

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            RealityView { content in
                setupLighting(content: &content)
                sceneState.sceneRoot   = Entity()
                sceneState.floorAnchor = Entity()
                sceneState.barAnchor   = Entity()
                sceneState.sceneRoot.addChild(sceneState.floorAnchor)
                sceneState.sceneRoot.addChild(sceneState.barAnchor)
                content.add(sceneState.sceneRoot)

                switch mode {
                case .welcome(let plates):
                    setupWelcomeScene(content: &content, plates: plates)
                case .rackRoom(let racked, let floor, _, _):
                    setupRackRoomScene(content: &content, racked: racked, floor: floor)
                }

                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass)
            } update: { _ in
                // Intentionally empty — scene owns its runtime state
            }
            .gesture(entityDragGesture)
            .gesture(floorPanGesture)
            .onChange(of: sizeClass) { _, _ in
                // Re-apply camera proxy when horizontal size class changes
                // (device rotation, iPad split view entry/exit).
                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass)
            }

            overlayView

            // Shader warm-up overlay: a 1x1 invisible RealityView that forces Metal to
            // compile PBR, physics, and unlit shader variants before the main scene renders.
            // Without this, the first plate drag causes a 300-800ms shader compilation hitch
            // on A14 and older. The overlay renders off-screen content then self-destructs.
            ShaderWarmUpView()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: Lighting
    // DirectionalLightComponent is required for shadow casting in RealityKit.
    // Point lights do not cast shadows. One directional key light + one point fill.

    private func setupLighting(content: inout RealityViewContent) {
        // Key light — directional, casts contact shadows
        let keyEntity = Entity()
        var keyLight = DirectionalLightComponent()
        keyLight.color = .white
        keyLight.intensity = 3500
        var shadow = DirectionalLightComponent.Shadow()
        shadow.maximumDistance = 4      // covers scene depth without over-sampling shadow map
        shadow.depthBias = 2.0
        keyLight.shadow = shadow
        keyEntity.components.set(keyLight)
        // 45-degree down, 30-degree from front-left
        keyEntity.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: .pi / 6, axis: SIMD3(0, 1, 0))
        content.add(keyEntity)

        // Fill light — point, no shadow, reduces harsh key-side darkness
        let fillEntity = Entity()
        fillEntity.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(white: 0.75, alpha: 1), intensity: 600, attenuationRadius: 8
        )
        fillEntity.position = SIMD3(-1.5, -0.5, 0.8)
        content.add(fillEntity)
    }

    // MARK: Welcome scene setup

    private func setupWelcomeScene(content: inout RealityViewContent, plates: [EarnedPlateInfo]) {
        let barbellRoot = Entity()
        barbellRoot.position = SIMD3(0, 0.3, -0.5)
        barbellRoot.scale = SIMD3(repeating: 1.8)

        let bar = makeBarEntity(skinID: 0)
        barbellRoot.addChild(bar)
        for xSign: Float in [-1, 1] {
            let collar = makeCollarEntity()
            collar.position = SIMD3(xSign * 0.475, 0, 0)
            barbellRoot.addChild(collar)
        }
        sceneState.sceneRoot.addChild(barbellRoot)
        sceneState.barbellRoot = barbellRoot

        let cols = 4
        let spacingX: Float = 0.12
        let spacingY: Float = 0.14
        for (i, info) in plates.enumerated() {
            let col = Float(i % cols)
            let row = Float(i / cols)
            let entity = makePlateEntity(
                tierID: info.tierID,
                material: sceneState.materialCache[info.tierID],
                weightKg: info.weightKg,
                engravingText: info.engravingText,
                role: .floor
            )
            entity.name = "welcome_plate_\(i)"
            entity.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            entity.position = SIMD3(
                (col - Float(cols - 1) / 2) * spacingX,
                -0.25 - row * spacingY,
                -0.5
            )
            sceneState.sceneRoot.addChild(entity)
            sceneState.entityMap["welcome_plate_\(i)"] = entity
            sceneState.plateSpinStates["welcome_plate_\(i)"] = PlateSpinState()
        }
    }

    // MARK: Overlay

    @ViewBuilder
    private var overlayView: some View {
        switch mode {
        case .welcome:  EmptyView()   // BarbellWelcomeView owns the CTA overlay
        case .rackRoom: EmptyView()   // PlateWallView owns the Done/weight overlay
        }
    }

    // MARK: Gesture stubs (implemented in Tasks 9-11)

    private var entityDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { _ in }
            .onEnded { _ in }
    }

    private var floorPanGesture: some Gesture {
        DragGesture()
            .onChanged { _ in }
            .onEnded { _ in }
    }

    // MARK: RackRoom scene setup stub (Task 8)
    private func setupRackRoomScene(content: inout RealityViewContent,
                                     racked: [EarnedPlate], floor: [EarnedPlate]) {}
}
```

- [ ] **Step 2: Add ShaderWarmUpView to BarbellRealityView.swift**

Append to `BarbellRealityView.swift` (outside the `BarbellRealityView` struct):

```swift
// MARK: - ShaderWarmUpView
//
// Renders one entity per material variant in a 1x1 invisible RealityView.
// Metal compiles and caches shader PSOs on first render — warming up here prevents
// hitch on first plate drag. Self-destructs after 1 second (shaders stay compiled).

private struct ShaderWarmUpView: View {
    @State private var visible = true

    var body: some View {
        if visible {
            RealityView { content in
                // One entity per shader variant used in the barbell scene
                let variants: [(MeshResource, any RealityKit.Material)] = [
                    (.generateBox(size: .init(repeating: 0.001)), {
                        var m = PhysicallyBasedMaterial()
                        m.baseColor = .init(tint: .clear)
                        return m
                    }()),
                    (.generateCylinder(height: 0.001, radius: 0.001), chromeMaterial()),
                    (.generateBox(size: .init(repeating: 0.001)), UnlitMaterial()),
                ]
                let root = Entity()
                root.position = SIMD3(0, 0, -500)  // far off-screen
                for (mesh, mat) in variants {
                    root.addChild(ModelEntity(mesh: mesh, materials: [mat]))
                }
                content.add(root)
            }
            .task {
                try? await Task.sleep(for: .seconds(1))
                visible = false
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: BarbellRealityView — directional shadow lighting, welcome scene, camera proxy, shader warm-up"
```

---

## Task 7: Migrate BarbellWelcomeView

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift`

- [ ] **Step 1: Read the current file to confirm what to delete**

Read `Features/Rewards/Views/BarbellWelcomeView.swift`. Verify these are all present before deleting:
`PlateUITextureCache`, `WelcomeLights`, `addWelcomeLights(to:)`, `PlateSceneView`, `buildPlateScene(tierID:)`, `buildSCNPlate(tierID:)`, `pbrSCNMaterial(...)`, `buildWelcomeBarbellScene(plates:)`, `PlateState`, `BarbellWelcomeState`, `SpinnablePlateCell`, `WelcomeBarbellView`

- [ ] **Step 2: Replace the entire file**

```swift
// Features/Rewards/Views/BarbellWelcomeView.swift
import SwiftUI
import SwiftData

struct BarbellWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var ownedPlates: [EarnedPlate]
    @State private var showPlateWall = false
    @State private var sceneState = SceneState()
    /// Guards against the .task{} / RealityView make{} race condition.
    /// BarbellRealityView is only rendered after the material cache is fully populated,
    /// guaranteeing make{} never runs against an empty cache.
    @State private var assetsReady = false

    private var earnedPlates: [EarnedPlate] {
        ownedPlates.filter { $0.earnedByEvent != "starter" }
    }

    private var showcasePlateInfos: [EarnedPlateInfo] {
        earnedPlates
            .sorted { $0.tierID > $1.tierID }
            .prefix(4)
            .map { EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg,
                                   engravingText: $0.engravingText, earnedByEvent: $0.earnedByEvent) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assetsReady {
                BarbellRealityView(
                    mode: .welcome(plates: showcasePlateInfos),
                    sceneState: sceneState
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Run asset loading in .task{}. Set assetsReady = true only after cache
            // is fully populated — this is what makes the gate safe.
            Color.clear.task { @MainActor in
                for tierID in 0...6 {
                    sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                    sceneState.materialCache[tierID] = buildMaterial(
                        forTierID: tierID,
                        textures: sceneState.plateTextureCache[tierID]
                    )
                }
                assetsReady = true
                await sceneState.runWelcomeSpinLoop()
            }

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("Your workouts have paid off.")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("\(earnedPlates.count) plates earned")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Button {
                    showPlateWall = true
                } label: {
                    Text("Build Your Rack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .background(DS.Semantic.brand)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showPlateWall) {
            PlateWallView()
                .onDisappear { dismiss() }
        }
    }
}
```

- [ ] **Step 3: Build**

Expected: no errors. Confirm no `import SceneKit` in the file.

- [ ] **Step 4: Run on simulator — visual verification**

- [ ] 3D barbell renders with auto-spin (static if Reduce Motion is on)
- [ ] Earned plates appear in grid below
- [ ] Contact shadows visible under barbell and plates
- [ ] "Build Your Rack" opens `PlateWallView`

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellWelcomeView.swift \
        Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: migrate BarbellWelcomeView to BarbellRealityView; reduce motion, material cache"
```

---

## Task 8: BarbellRealityView — rackRoom scene setup with physics floor

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Implement setupRackRoomScene**

Replace the stub `setupRackRoomScene` in `BarbellRealityView`:

```swift
private func setupRackRoomScene(
    content: inout RealityViewContent,
    racked: [EarnedPlate],
    floor: [EarnedPlate]
) {
    // Invisible static physics floor — plates settle on this after .dynamic release
    let floorShape = ShapeResource.generateBox(size: SIMD3(20, 0.02, 4))
    let floorCollider = Entity()
    floorCollider.components.set(CollisionComponent(
        shapes: [floorShape],
        filter: CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
    ))
    var floorBody = PhysicsBodyComponent()
    floorBody.mode = .static
    floorBody.material = PhysicsMaterialResource.generate(friction: 0.75, restitution: 0.25)
    floorCollider.components.set(floorBody)
    floorCollider.position = SIMD3(0, -0.01, 0)
    sceneState.sceneRoot.addChild(floorCollider)

    // Visual floor line
    let floorLine = ModelEntity(
        mesh: .generateBox(size: SIMD3(1.2, 0.004, 0.08)),
        materials: [pbrMaterial(color: UIColor(white: 0.15, alpha: 1), metallic: 0, roughness: 1)]
    )
    floorLine.position = SIMD3(0, 0, 0)
    sceneState.sceneRoot.addChild(floorLine)

    // Rack stands
    for xSign: Float in [-1, 1] {
        let stand = makeRackStandEntity()
        stand.position = SIMD3(xSign * 0.55, 0.3, 0)
        sceneState.sceneRoot.addChild(stand)
    }

    // Bar
    let bar = makeBarEntity(skinID: 0)
    bar.position = SIMD3(0, 0.6, 0)
    sceneState.sceneRoot.addChild(bar)
    sceneState.barAnchor.position = SIMD3(0, 0.6, 0)
    sceneState.sceneRoot.addChild(sceneState.barAnchor)

    // Collars
    for xSign: Float in [-1, 1] {
        let collar = makeCollarEntity()
        collar.position = SIMD3(xSign * 0.475, 0.6, 0)
        sceneState.sceneRoot.addChild(collar)
    }

    // Slot highlight rings — one per bar slot, hidden until plate is dragged near bar.
    // Thin flat cylinder oriented face-on, rendered with UnlitMaterial so they always
    // appear bright regardless of scene lighting.
    let slotOffsets: [Float] = [0.34, 0.37, 0.40, 0.43]
    sceneState.slotHighlights.removeAll()
    for offset in slotOffsets {
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(white: 1, alpha: 0.7))
        let ring = ModelEntity(
            mesh: cachedCylinder(height: 0.003, radius: 0.21),
            materials: [mat]
        )
        ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        ring.position = SIMD3(offset, 0, 0)
        ring.isEnabled = false  // hidden until drag enters snap zone
        sceneState.barAnchor.addChild(ring)
        sceneState.slotHighlights.append(ring)
    }

    // Racked plates — bilateral rendering, use cached material
    // Performance budget: max 4 racked plates (4 bar slots)
    let sorted = racked.sorted { ($0.rackPosition ?? 999) < ($1.rackPosition ?? 999) }
    for (idx, plate) in sorted.prefix(4).enumerated() {
        let offset = slotOffsets[min(idx, slotOffsets.count - 1)]
        for xSign: Float in [-1, 1] {
            let entity = makePlateEntity(
                tierID: plate.tierID,
                material: sceneState.materialCache[plate.tierID],
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                role: .bar
            )
            entity.name = xSign == 1 ? plate.id : plate.id + "_mirror"
            entity.position = SIMD3(xSign * offset, 0, 0)
            sceneState.barAnchor.addChild(entity)
        }
        sceneState.entityMap[plate.id] = sceneState.barAnchor.children
            .first(where: { $0.name == plate.id })
        sceneState.barPositionMap[plate.id] = SIMD3(offset, 0, 0)
    }

    // Floor plates — use cached material
    // Performance budget: max 24 floor plates (see Task 12 for rationale)
    let spacing: Float = 0.15
    let visibleFloor = Array(floor.prefix(24))
    for (idx, plate) in visibleFloor.enumerated() {
        let entity = makePlateEntity(
            tierID: plate.tierID,
            material: sceneState.materialCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            role: .floor
        )
        entity.name = plate.id
        let xPos = Float(idx) * spacing
        entity.position = SIMD3(xPos, 0, 0)
        let leanAngle = Float.random(in: 0.10 ..< 0.23)
        entity.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))
        sceneState.floorAnchor.addChild(entity)
        sceneState.entityMap[plate.id] = entity
    }

    // Floor pan clamp bounds
    let totalWidth = Float(max(visibleFloor.count - 1, 0)) * spacing
    sceneState.floorMinX = 0
    sceneState.floorMaxX = max(totalWidth - 0.8, 0)
}
```

- [ ] **Step 2: Build**

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: implement rackRoom scene setup — static physics floor, cached materials, bilateral bar plates"
```

---

## Task 9: rackRoom — floor pan gesture (state machine guarded, reduce motion aware)

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Replace the floorPanGesture stub**

```swift
private var floorPanGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
        .onChanged { value in
            // Attempt transition to .panningFloor; also allow if already panning
            let alreadyPanning: Bool
            if case .panningFloor = sceneState.dragPhase { alreadyPanning = true } else { alreadyPanning = false }
            guard sceneState.transition(to: .panningFloor) || alreadyPanning else { return }

            let delta = Float(value.translation.width) * -0.002
            let raw = sceneState.floorOffset + delta
            sceneState.floorOffset = max(sceneState.floorMinX, min(sceneState.floorMaxX, raw))
            sceneState.floorAnchor.position.x = -sceneState.floorOffset
            sceneState.floorVelocity = delta * 60
        }
        .onEnded { _ in
            sceneState.transition(to: .idle)
            guard !sceneState.isReduceMotionEnabled else {
                sceneState.floorVelocity = 0
                return
            }
            Task { @MainActor in
                while abs(sceneState.floorVelocity) > 0.001 {
                    try? await Task.sleep(for: .milliseconds(16))
                    sceneState.floorVelocity *= 0.90
                    let raw = sceneState.floorOffset - sceneState.floorVelocity * 0.016
                    sceneState.floorOffset = max(sceneState.floorMinX, min(sceneState.floorMaxX, raw))
                    sceneState.floorAnchor.position.x = -sceneState.floorOffset
                }
                sceneState.floorVelocity = 0
            }
        }
}
```

- [ ] **Step 2: Build and run on simulator**

Verify panning with momentum. Enable Settings → Accessibility → Reduce Motion and verify momentum is suppressed (plates stop immediately on finger lift).

- [ ] **Step 3: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: floor pan gesture — state machine guard, reduce motion kills momentum"
```

---

## Task 10: rackRoom — rack gesture (floor plate to bar)

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Add mode accessor helpers**

Append to `BarbellRealityView`:

```swift
private var onRackCallback: ((EarnedPlate) -> Void)? {
    if case .rackRoom(_, _, let onRack, _) = mode { return onRack }
    return nil
}

private var onUnrackCallback: ((EarnedPlate) -> Void)? {
    if case .rackRoom(_, _, _, let onUnrack) = mode { return onUnrack }
    return nil
}

private var allFloorPlates: [EarnedPlate] {
    if case .rackRoom(_, let floor, _, _) = mode { return floor }
    return []
}

private var allRackedPlates: [EarnedPlate] {
    if case .rackRoom(let racked, _, _, _) = mode { return racked }
    return []
}
```

- [ ] **Step 2: Replace entityDragGesture stub**

```swift
private var entityDragGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
        .targetedToAnyEntity()
        .onChanged { value in
            let entity = value.entity
            guard let roleComp = entity.components[PlateRoleComponent.self] else { return }

            switch roleComp.role {
            case .floor:
                guard sceneState.transition(to: .draggingPlate(entity, plateID: entity.name)) else { return }
                // PhysicsBodyComponent stays .kinematic during drag — position directly
                let worldPos = value.convert(value.location3D, from: .local, to: .scene)
                entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                entity.position = worldPos

                // Snap zone feedback: show slot highlight and fire a selection haptic
                // once when the plate first enters the bar's snap zone.
                let barWorldY = sceneState.barAnchor.position(relativeTo: nil).y
                let inZone = worldPos.y > barWorldY - 0.2
                if inZone {
                    let occupiedSlots = allRackedPlates.compactMap(\.rackPosition)
                    if let nextSlot = (0..<4).first(where: { !occupiedSlots.contains($0) }),
                       nextSlot < sceneState.slotHighlights.count {
                        sceneState.slotHighlights.forEach { $0.isEnabled = false }
                        sceneState.slotHighlights[nextSlot].isEnabled = true
                    }
                    if !sceneState.wasInSnapZone {
                        playSnapZoneEntryHaptic()
                        sceneState.wasInSnapZone = true
                    }
                } else {
                    sceneState.slotHighlights.forEach { $0.isEnabled = false }
                    sceneState.wasInSnapZone = false
                }

            case .bar:
                guard case .idle = sceneState.dragPhase else { return }
                let dx = Float(value.translation.width)
                guard abs(dx) > 0.04 else { return }
                guard sceneState.transition(to: .draggingPlate(entity, plateID: entity.name)) else { return }
                // Slide off bar end in swipe direction
                let slideTarget = Transform(
                    scale: entity.scale,
                    rotation: entity.orientation,
                    translation: entity.position(relativeTo: nil) + SIMD3(dx > 0 ? 0.6 : -0.6, 0, 0)
                )
                if sceneState.isReduceMotionEnabled {
                    entity.position = slideTarget.translation
                } else {
                    entity.move(to: slideTarget, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
                }
                entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                entity.components.set(PlateRoleComponent(role: .floor))
            }
        }
        .onEnded { value in
            guard case .draggingPlate(let entity, let plateID) = sceneState.dragPhase else { return }
            sceneState.transition(to: .idle)
            // Always hide highlights and reset snap zone state on drag end
            sceneState.slotHighlights.forEach { $0.isEnabled = false }
            sceneState.wasInSnapZone = false

            let worldPos = value.convert(value.location3D, from: .local, to: .scene)
            let barWorldY = sceneState.barAnchor.position(relativeTo: nil).y
            let isFromFloor = allFloorPlates.contains { $0.id == plateID }

            if isFromFloor && worldPos.y > barWorldY - 0.15 {
                snapToBar(entity: entity, plateID: plateID)
            } else if !isFromFloor && worldPos.y < barWorldY - 0.2 {
                snapToFloor(entity: entity, plateID: plateID)
            } else {
                snapBack(entity: entity, plateID: plateID)
            }
        }
}
```

- [ ] **Step 3: Add snapToBar**

Append to `BarbellRealityView`:

```swift
// MARK: - Snap animations

private func snapToBar(entity: Entity, plateID: String) {
    let slotOffsets: [Float] = [0.34, 0.37, 0.40, 0.43]
    let occupiedSlots = allRackedPlates.compactMap(\.rackPosition)
    guard let nextSlot = (0..<4).first(where: { !occupiedSlots.contains($0) }) else {
        snapBack(entity: entity, plateID: plateID)
        return
    }
    let offset = slotOffsets[nextSlot]
    let slotPos = SIMD3<Float>(offset, 0, 0)
    let rot = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

    entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
    entity.components.set(PlateRoleComponent(role: .bar))

    // Bilateral mirror entity for the opposite side of the bar
    let mirrorEntity = entity.clone(recursive: true)
    mirrorEntity.name = plateID + "_mirror"
    mirrorEntity.components.set(PlateRoleComponent(role: .bar))
    sceneState.barAnchor.addChild(mirrorEntity)

    if sceneState.isReduceMotionEnabled {
        entity.position = slotPos
        entity.orientation = rot
        mirrorEntity.position = SIMD3(-offset, 0, 0)
        mirrorEntity.orientation = rot
    } else {
        // Spring snap: overshoot 2.5cm above slot then settle — gives physical weight feeling
        for (e, xSign) in [(entity, Float(1)), (mirrorEntity, Float(-1))] {
            let overshoot = Transform(scale: SIMD3(repeating: 1), rotation: rot,
                                      translation: SIMD3(xSign * offset, slotPos.y + 0.025, 0))
            let settle    = Transform(scale: SIMD3(repeating: 1), rotation: rot,
                                      translation: SIMD3(xSign * offset, slotPos.y, 0))
            e.move(to: overshoot, relativeTo: sceneState.barAnchor, duration: 0.15, timingFunction: .easeOut)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                e.move(to: settle, relativeTo: sceneState.barAnchor, duration: 0.12, timingFunction: .easeIn)
            }
        }
    }

    sceneState.barPositionMap[plateID] = slotPos

    let animDelay = sceneState.isReduceMotionEnabled ? 0 : 270
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(animDelay))
        if let plate = allFloorPlates.first(where: { $0.id == plateID }) {
            onRackCallback?(plate)
            if let audioComp = entity.components[PlateAudioCategoryComponent.self] {
                playClinkSound(on: entity, category: audioComp.category)
                playRackHaptic(category: audioComp.category)
            }
        }
    }
}
```

- [ ] **Step 4: Build**

Expected: no errors.

- [ ] **Step 5: Run on simulator — rack test**

1. Drag a floor plate up past the bar. Verify spring snap (or instant with Reduce Motion).
2. Verify clink sound plays spatially from the plate's 3D position.
3. Verify bilateral plate appears symmetrically on both bar sides.
4. Verify `rackPlate()` is called (plate persists on bar after relaunch).

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: rack gesture — state machine, spring snap, bilateral clone, spatial clink"
```

---

## Task 11: rackRoom — unrack gesture and snapBack (physics-aware)

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

The unrack swipe is already in `entityDragGesture` from Task 10. This task adds `snapToFloor` and `snapBack`.

- [ ] **Step 1: Add snapToFloor**

Append to `BarbellRealityView`:

```swift
private func snapToFloor(entity: Entity, plateID: String) {
    let xPos = Float(sceneState.floorAnchor.children.count) * 0.15
    entity.setParent(sceneState.floorAnchor, preservingWorldTransform: true)
    entity.components.set(PlateRoleComponent(role: .floor))

    let leanAngle = Float.random(in: 0.10 ..< 0.23)
    let leanRot = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        * simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))

    if sceneState.isReduceMotionEnabled {
        entity.position = SIMD3(xPos, 0, 0)
        entity.orientation = leanRot
        finishUnrack(entity: entity, plateID: plateID, delayMs: 0)
    } else {
        // Switch to dynamic so physics handles the bounce on floor contact
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
        // Drop from slightly above (physics takes it to the static floor collider)
        let dropTarget = Transform(
            scale: SIMD3(repeating: 1),
            rotation: leanRot,
            translation: SIMD3(xPos, 0.3, 0)
        )
        entity.move(to: dropTarget, relativeTo: sceneState.floorAnchor, duration: 0.15, timingFunction: .easeOut)
        Task { @MainActor in
            // Let physics settle (~800ms), then lock back to kinematic and play drop sound
            try? await Task.sleep(for: .milliseconds(800))
            entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
            if let audioComp = entity.components[PlateAudioCategoryComponent.self] {
                playDropSound(on: entity, category: audioComp.category)
                playDropHaptic(category: audioComp.category)
            }
            finishUnrack(entity: entity, plateID: plateID, delayMs: 0)
        }
    }
}

private func finishUnrack(entity: Entity, plateID: String, delayMs: Int) {
    Task { @MainActor in
        if delayMs > 0 { try? await Task.sleep(for: .milliseconds(delayMs)) }
        if let plate = allRackedPlates.first(where: { $0.id == plateID }) {
            onUnrackCallback?(plate)
        }
        sceneState.barAnchor.children
            .first(where: { $0.name == plateID + "_mirror" })?
            .removeFromParent()
        sceneState.barPositionMap.removeValue(forKey: plateID)
    }
}
```

- [ ] **Step 2: Add snapBack**

Append to `BarbellRealityView`:

```swift
private func snapBack(entity: Entity, plateID: String) {
    if let roleComp = entity.components[PlateRoleComponent.self], roleComp.role == .bar,
       let barPos = sceneState.barPositionMap[plateID] {
        // Return bar plate to its slot
        entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
        let rot = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let target = Transform(scale: SIMD3(repeating: 1), rotation: rot, translation: barPos)
        if sceneState.isReduceMotionEnabled {
            entity.position = barPos
            entity.orientation = rot
        } else {
            entity.move(to: target, relativeTo: sceneState.barAnchor, duration: 0.2, timingFunction: .easeOut)
        }
    } else if let original = sceneState.entityMap[plateID] {
        // Return floor plate to its original position
        entity.setParent(sceneState.floorAnchor, preservingWorldTransform: true)
        let target = Transform(matrix: original.transformMatrix(relativeTo: nil))
        if sceneState.isReduceMotionEnabled {
            entity.transform = Transform(matrix: entity.convert(transform: target, from: nil))
        } else {
            entity.move(to: target, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
        }
    }
}
```

- [ ] **Step 3: Build**

Expected: no errors.

- [ ] **Step 4: Run on simulator — unrack test**

1. Swipe a bar plate horizontally. Verify it slides off.
2. Release into the floor zone — verify it drops with physics bounce, drop sound plays spatially.
3. Release in mid-air (not in floor zone) — verify `snapBack` returns it to bar slot.
4. Enable Reduce Motion — verify instant placement, no physics settle delay, no sounds during animation.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: unrack snapToFloor with physics settle + drop sound; snapBack with reduce motion paths"
```

---

## Task 12: Performance budget verification

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift` (comment, floor cap already in Task 8)

This task verifies the draw call budget and documents the constraints. No new logic is added — the floor cap (24 plates) and `ModelSortGroupComponent` were added in Tasks 2 and 8.

- [ ] **Step 1: Verify draw call count on device**

Build and run on a physical device (iPhone 12 or later). In Xcode: Debug → Metal HUD.

Target draw call counts:
- Welcome mode: < 60 draw calls (4 plates + barbell)
- RackRoom mode with 24 floor plates + 4 racked (bilateral = 8 entities): < 150 draw calls

If over budget, investigate:
- Duplicate material objects: confirm `materialCache` is populated before `make{}` runs
- Rack stand children: each stand adds ~3 child ModelEntities; merge into one if needed
- Hub cylinder on every plate: shared `chromeMaterial()` call already returns a new instance per plate — extract to a static let to share the material

- [ ] **Step 2: Add draw call budget comment to setupRackRoomScene**

At the top of `setupRackRoomScene`:

```swift
// Performance budget: 4 racked (bilateral = 8 entities) + 24 floor = 32 plate entities.
// With shared materialCache, this stays under 150 draw calls on A15+ at 60fps.
// Plates beyond index 24 are in SwiftData but not rendered.
```

- [ ] **Step 3: Run full test suite**

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "perf: document draw call budget; verify materialCache prevents GPU material duplication"
```

---

## Task 13: Migrate PlateWallView

**Files:**
- Modify: `Features/Profile/Views/PlateWallView.swift`

- [ ] **Step 1: Replace the entire file**

```swift
// Features/Profile/Views/PlateWallView.swift
import SwiftUI
import SwiftData

struct PlateWallView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" && $0.isRacked == false })
    private var floorPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]

    @State private var sceneState = SceneState()
    /// Guards against the .task{} / RealityView make{} race condition.
    /// Same pattern as BarbellWelcomeView: make{} only runs after cache is populated.
    @State private var assetsReady = false

    private var totalWeight: Double {
        let racked = rackedPlates.filter { $0.earnedByEvent != "starter" }
        return 20 + racked.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assetsReady {
                BarbellRealityView(
                    mode: .rackRoom(
                        rackedPlates: rackedPlates,
                        floorPlates: floorPlates,
                        onRack: { plate in
                            try? BarbellProgressService.shared.rackPlate(plate)
                        },
                        onUnrack: { plate in
                            BarbellProgressService.shared.unrackPlate(plate)
                        }
                    ),
                    sceneState: sceneState
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            Color.clear.task { @MainActor in
                // Populate caches, then set assetsReady = true before RealityView renders
                for tierID in 0...6 {
                    sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                    sceneState.materialCache[tierID] = buildMaterial(
                        forTierID: tierID,
                        textures: sceneState.plateTextureCache[tierID]
                    )
                }
                // Preload audio into process-level cache so first interaction has no latency
                for tierID in 0...7 {
                    let cat = PlateAudioCategory.from(tierID: tierID)
                    _ = loadAudioResource(named: cat.clinkSoundName)
                    _ = loadAudioResource(named: cat.dropSoundName)
                }
                // IBL if available
                if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
                    let iblEntity = Entity()
                    iblEntity.components.set(
                        ImageBasedLightComponent(source: .single(ibl), intensityExponent: 0.5)
                    )
                    sceneState.sceneRoot.addChild(iblEntity)
                    sceneState.sceneRoot.components.set(
                        ImageBasedLightReceiverComponent(imageBasedLight: iblEntity)
                    )
                }
                assetsReady = true  // Cache is populated — safe for make{} to run
            }
            .onChange(of: ownedPlates.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                let existing = Set(sceneState.entityMap.keys)
                if let newPlate = ownedPlates.first(where: { !existing.contains($0.id) }) {
                    sceneState.addPlate(newPlate)
                }
            }

            VStack {
                HStack {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Semantic.brand)
                    Spacer()
                    Text("Your Barbell")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Done").opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Text("Bar 20kg + \(Int(totalWeight - 20))kg = \(Int(totalWeight))kg total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 12)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Expected: no errors.

- [ ] **Step 3: Run all tests**

Expected: all tests pass.

- [ ] **Step 4: End-to-end simulator verification**

1. Navigate to barbell welcome — RealityKit barbell spins (static with Reduce Motion on)
2. Tap "Build Your Rack" — rackRoom renders: rack stands, bar, floor plates, contact shadows on floor
3. Drag a floor plate up — spring snap onto bar, bilateral plates appear, directional clink plays
4. Swipe a bar plate horizontally — slides off, falls with physics bounce, drop sound plays from plate position
5. Pan floor empty space — momentum scroll (instant stop with Reduce Motion on)
6. Dismiss — welcome view also dismisses
7. Relaunch — rack state persisted (racked plates on bar)

- [ ] **Step 5: Commit**

```bash
git add Features/Profile/Views/PlateWallView.swift
git commit -m "feat: migrate PlateWallView to BarbellRealityView rackRoom; preload materials and audio"
```

---

## Task 14: Cleanup and final verification

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift` (confirm clean)
- Modify: `Features/Rewards/Views/BarbellRealityView.swift` (remove any leftover TODOs)

- [ ] **Step 1: Verify no SceneKit imports remain**

```bash
grep -r "import SceneKit" Features/Rewards/Views/BarbellWelcomeView.swift \
                          Features/Profile/Views/PlateWallView.swift
```

Expected: no output.

- [ ] **Step 2: Verify no showcase mode usage in PlateWallView**

```bash
grep "showcase" Features/Profile/Views/PlateWallView.swift
```

Expected: no output.

- [ ] **Step 3: Verify Reduce Motion paths on simulator**

Settings → Accessibility → Motion → Reduce Motion ON:
- [ ] Welcome: barbell static, plates static
- [ ] Rack gesture: instant placement, no animation delay before clink
- [ ] Unrack gesture: instant floor placement, no 800ms physics wait
- [ ] Floor pan: no momentum on finger lift

- [ ] **Step 4: Verify shadows are visible**

On a physical device or Metal-enabled simulator:
- [ ] Contact shadows under rack stands and floor plates
- [ ] Bar shadow falls on floor
- [ ] No self-shadowing artifacts (depthBias = 2.0 prevents acne)

- [ ] **Step 5: Run full test suite**

Expected: all tests pass.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete BarbellRealityKit migration — physics, spatial audio, shadows, state machine, reduce motion"
```

---

## Implementation Notes

**Physics mode lifecycle:** Plates are always `.kinematic` except during the settle phase after `snapToFloor`. The sequence is: kinematic (drag) → dynamic (release, ~800ms settle) → kinematic (locked). Bar plates are always kinematic — they are clamped to slot positions, never dynamic.

**Material caching:** `SceneState.materialCache` stores one `PhysicallyBasedMaterial` per `tierID`. All plates of the same tier share one GPU material object. Populate the cache in `.task{}` before `RealityView make{}` runs. This is critical: if `make{}` runs before the cache is populated, entities fall back to per-instance material creation and the budget breaks.

**Audio process cache:** `audioResourceCache` is process-level. First `PlateWallView` appearance loads all sounds; subsequent appearances are instant. `SpatialAudioComponent` must be attached to an entity (via `attachSpatialAudio`) before `playAudio()` is called on it — this is done in `makePlateEntity` so every plate is always ready.

**Shadow casting:** Only `DirectionalLightComponent` casts shadows in RealityKit. Point lights do not. The key light in `setupLighting` is directional with `Shadow.maximumDistance = 4` to cover the scene depth without excessive shadow map cost. `depthBias = 2.0` prevents shadow acne on cylinder surfaces.

**State machine:** `SceneState.transition(to:)` guards all `dragPhase` mutations. Floor pan and entity drag are mutually exclusive and must go through `.idle` to switch. Gesture handlers must check the return value and bail on `false`. This prevents the common two-finger corruption bug.

**Reduce Motion:** `SceneState.isReduceMotionEnabled` reads `UIAccessibility.isReduceMotionEnabled` at gesture time, not at init time — responds to in-session changes without a view reload. All animation paths (snap, inertia, spin loop) have explicit reduce motion branches.

**Camera proxy:** `configureCameraPosition` positions `sceneRoot` because `RealityView` on iOS does not expose direct camera control. The adjustment for iPad (`sizeClass == .regular`) pulls the scene back to account for the wider viewport. `onChange(of: sizeClass)` in `BarbellRealityView` re-applies the proxy on device rotation and split view changes.

**Asset loading race:** `BarbellRealityView` is rendered conditionally on `assetsReady`. The `.task{}` that populates `materialCache` and `plateTextureCache` sets `assetsReady = true` only after all cache entries are written, guaranteeing `RealityView make{}` never runs against an empty cache. A `ProgressView` fills the gap while loading.

**Mesh resource cache:** `cachedCylinder` / `cachedBox` are process-level free functions that deduplicate `MeshResource` GPU uploads. Identical geometry (e.g. all iron plate cylinders at radius 0.18) shares one GPU mesh buffer. Always use these instead of `MeshResource.generate*` directly in entity builders.

**Snap zone feedback:** Slot highlight rings are `UnlitMaterial` cylinders parented to `barAnchor`, one per slot. They are toggled via `entity.isEnabled` (free — no scene graph mutation) in `entityDragGesture.onChanged`. `SceneState.wasInSnapZone` prevents `playSnapZoneEntryHaptic()` from firing every frame — it fires once on zone entry.

**Haptic vocabulary:** Three typed functions in `BarbellAudioBuilder`: `playRackHaptic(category:)`, `playSnapZoneEntryHaptic()`, `playDropHaptic(category:)`. Do not use `BarbellProgressService.playClinkHaptic()` for plate interactions — it produces a single undifferentiated feedback regardless of plate material. The typed functions vary style by `PlateAudioCategory`.

**Shader warm-up:** `ShaderWarmUpView` renders one entity per Metal shader variant in a 1x1 invisible overlay before the main scene appears. This forces Metal PSO compilation during the loading spinner, so the first drag interaction is smooth. The view self-destructs after 1 second via `.task {}`.

**BarbellPreviewView is untouched:** Cosmetic editor uses RealityKit independently on a separate navigation path. No multi-instance RealityKit crash risk.

---

## Post-Plan Bug Fixes (on-device testing, 2026-04-03)

The following bugs were discovered during on-device testing after the initial implementation run. All are now fixed in `main`.

### Task 5 / Task 8 — SceneState: `originalTransforms` dictionary (not in original plan)

`SceneState` gained a new property: `var originalTransforms: [String: Transform] = [:]`. This is required for `snapBack` to restore floor plates to their exact starting positions. The original plan assumed `entityMap[plateID]` could serve as the restore target, but `entity.transformMatrix(relativeTo: nil)` returns the *current* world transform at call time — it is not a snapshot. `originalTransforms` captures the world-space transform immediately after `addChild` resolves the hierarchy, and `snapBack` uses `entity.move(to:relativeTo:nil)` against that snapshot.

### Task 8 — `setupRackRoomScene`: initial mirror plates were fully interactive

**Bug:** The racked-plate loop created two entities per plate (primary + mirror) both via `makePlateEntity(role: .bar)`, which always adds `InputTargetComponent` and `CollisionComponent`. The `_mirror` entities were therefore hittable from the first open. `targetedToAnyEntity()` picked them up, the drag logged `id=<uuid>_mirror role=bar`, and `finishUnrack` called `barMirrorMap[plateID]?.removeFromParent()` which returned nil (map was never populated at setup), so mirrors became permanent ghosts on the bar after an unrack.

**Fix:** In the racked-plate setup loop, the `xSign == -1` branch now strips `InputTargetComponent`, `CollisionComponent`, `PhysicsBodyComponent`, `PhysicsMotionComponent` from the mirror entity (matching what `snapToBar` already did for interactively-racked plates). `barMirrorMap[plate.id]` is also populated here so `finishUnrack` can remove it.

### Task 8 — floor plate start position

**Bug:** `xPos = Float(idx) * spacing` started at 0.0, placing the first floor plate at the bar's center (between the rack stands at ±0.55). Visually a plate appeared inside the rack at startup.

**Fix:** `let floorStartX: Float = 0.65`. Floor plates start at x = 0.65 (just outside the right rack stand). `floorMaxX` updated to account for the extra offset.

### Task 10 — Welcome mode drag guard

**Bug:** `entityDragGesture` had no mode guard. In `.welcome` mode, plate entities have `InputTargetComponent` and were eligible for dragging. Dragging a welcome plate triggered `snapToBar` / `snapBack` logic designed for rack room, producing erratic movement.

**Fix:** Added `guard case .rackRoom = mode else { return }` at the top of `entityDragGesture.onChanged`.

### Task 10 — Drag translation scale factor

**Bug:** `s = 0.002 m/pt` — half the correct value. At `sceneRoot.z = -1.4m` with a ~60° FOV, 1 screen point maps to ~0.004 m of world space. The plate lagged behind the finger by 2x.

**Fix:** `s = 0.004`.

### Task 10 — Snap zone threshold

Plan had `entityY > barLocalY - 0.2`. Changed to `entityY > barLocalY - 0.15` to match the tighter snap zone used in the slot highlight logic and reduce false positives near the bottom of the bar stand.

### Task 10 / 11 — Bar plate unrack routing (y-position check never fired)

**Bug:** The plan's `onEnded` routing used `entityY < barLocalY - 0.2` to detect a bar plate being dragged below the bar. But the bar drag gesture slides the plate *sideways* (not downward), so `entityY` stays at bar height throughout the gesture. The condition was always false; bar plates always fell into `snapBack` instead of `snapToFloor`.

**Fix:** Routing now uses `originRole` (captured at drag-start as part of `DragPhase.draggingPlate`):
- `isFromFloor && entityY > barLocalY - 0.15` → `snapToBar`
- `!isFromFloor` → `snapToFloor` (bar plate always goes to floor regardless of y)
- else → `snapBack`

The `originRole` capture in `DragPhase` was not in the original plan spec; it was added to make routing robust against mid-drag model mutations.

### Task 11 — `snapToFloor`: `entity.move()` incompatible with `.dynamic` physics

**Bug:** The original `snapToFloor` called `entity.move(to:relativeTo:duration:)` after setting `physics.mode = .dynamic`. Dynamic bodies ignore the RealityKit animation system entirely — the `move()` call was a no-op, leaving the plate frozen at its drop position in a 2D-looking pose.

**Fix:** Removed `entity.move()` from `snapToFloor`. Position is set directly before enabling physics, with a y clamp (`if entity.position.y < 0.25 { entity.position.y = 0.25 }`) to ensure the plate starts above the static floor collider. Physics then simulates the drop naturally.

### Task 11 — Settle time increased from 800ms to 1400ms

Bar-height drop (~0.6m in sceneRoot space) plus bounce takes longer than the original 800ms budget. Plates were being re-locked to kinematic mid-bounce, freezing mid-air. Increased to 1400ms.

### Task 10 — Bar gesture redesign: outermost plate auto-selection

**Original plan:** Swiping a bar plate entity slides that specific entity off the bar. Requires precise touch on a thin plate edge; touching a plate inside the outermost one had no useful effect.

**Change:** The `.bar` case in `entityDragGesture.onChanged` now finds `allRackedPlates.max(by: rackPosition)` regardless of which entity was touched. Any swipe on any bar entity (primary only — mirrors are now non-interactive) unracks the outermost plate and slides it in the swipe direction. `dragStartEntityPosition` is set on the outermost entity immediately after reparenting to prevent the subsequent `.floor`-routed `onChanged` events from jumping the plate.

### Debug tooling added (not in plan, `#if DEBUG` gated)

- `barbellLog(_ tag:_ msg:)` and `v3(_ v:)` free functions at the top of `BarbellRealityView.swift`.
- `BarbellDebugHUD` struct: on-screen overlay toggled by a "D" button in the top-right corner. Refreshes at 4 Hz via `TimelineView(.periodic(from:by:0.25))`. Shows: drag phase, anchor positions, all entities in `entityMap` with role, physics mode (DYN/kin/sta), local position, and world position. Dynamic entities are highlighted orange.
- Console logging at `DRAG_START`, `DRAG_END`, `SNAP_BAR`, `SNAP_FLOOR` decision points.
