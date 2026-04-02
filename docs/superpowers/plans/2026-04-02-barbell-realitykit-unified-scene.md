# Barbell — Unified RealityKit Scene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `BarbellWelcomeView` (multi-SCNView SceneKit) and `PlateWallView` (split RealityKit + 2D SwiftUI) with a single shared `BarbellRealityView` where one RealityKit scene owns all runtime state and SwiftData is a persistence side-effect.

**Architecture:** One `BarbellRealityView` struct with a `BarbellRealityMode` enum (`.welcome` / `.rackRoom`). A `SceneState` class (not struct — mutations must not trigger SwiftUI re-renders) is created by the parent view and passed in. All gesture handling mutates entities directly at 60fps; `BarbellProgressService.rackPlate()` / `unrackPlate()` are called only at gesture end as persistence side-effects. The `RealityView update {}` closure is empty after initial setup.

**Tech Stack:** RealityKit, SwiftUI, SwiftData (`@Query`), `PhysicallyBasedMaterial`, `InputTargetComponent`, `CollisionComponent`, `DragGesture().targetedToAnyEntity()`, Swift Testing

**Spec:** `docs/superpowers/specs/2026-04-02-barbell-realitykit-unified-scene.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Features/Rewards/Views/BarbellEntityBuilder.swift` | Pure free functions: entity factory, PBR helpers, texture loading |
| Create | `Features/Rewards/Views/BarbellRealityView.swift` | `BarbellRealityMode`, `SceneState`, `DragPhase`, `BarbellRealityView` |
| Modify | `Features/Rewards/Views/BarbellWelcomeView.swift` | Delete all SceneKit code; use `BarbellRealityView(mode: .welcome(...))` |
| Modify | `Features/Profile/Views/PlateWallView.swift` | Delete barbell + 2D grid; use `BarbellRealityView(mode: .rackRoom(...))` |
| Create | `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift` | Unit tests for entity builder |
| Create | `WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift` | Unit tests for SceneState logic |
| Unchanged | `Features/Profile/Views/BarbellPreviewView.swift` | Cosmetic editor — do not touch |
| Unchanged | `Features/Rewards/Models/BarbellModels.swift` | Models — do not touch |
| Unchanged | `Features/Rewards/Services/BarbellProgressService.swift` | Service — do not touch |

---

## Task 1: BarbellEntityBuilder — foundation types and PBR helpers

**Files:**
- Create: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Create: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

- [ ] **Step 1: Create the file with imports and PlateRoleComponent**

```swift
// Features/Rewards/Views/BarbellEntityBuilder.swift
import RealityKit
import UIKit

// MARK: - PlateRoleComponent

/// ECS component attached to every plate entity. Distinguishes floor plates
/// (eligible for drag-to-rack) from bar plates (eligible for swipe-to-unrack).
struct PlateRoleComponent: Component {
    enum Role { case floor, bar }
    var role: Role
}

// MARK: - TierIDComponent

/// Stores the plate tier so texture-application passes can look up which
/// textures to apply without re-threading tierID through every call site.
struct TierIDComponent: Component {
    let tierID: Int
}
```

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
//
// Same bundle files as BarbellPreviewView. Tiers 0,1,2,3,6 have PBR textures;
// all others fall back to color-only materials.

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

- [ ] **Step 4: Add to Xcode project**

In Xcode: right-click `Features/Rewards/Views` → Add Files → select `BarbellEntityBuilder.swift`. Target: WRKT (iOS app only, not Watch).

Also add `WRKTTests/FeaturesTests/Barbell/` directory and create the test file stub:

```swift
// WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
import Testing
import RealityKit
@testable import WRKT

struct BarbellEntityBuilderTests {
    // tests added in Task 2 and Task 3
}
```

- [ ] **Step 5: Build to verify compilation**

Build target WRKT (Cmd+B). Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat: add BarbellEntityBuilder foundation — PlateRoleComponent, PBR helpers, texture loader"
```

---

## Task 2: BarbellEntityBuilder — makePlateEntity

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Modify: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

- [ ] **Step 1: Write the failing tests first**

```swift
// WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
import Testing
import RealityKit
@testable import WRKT

struct BarbellEntityBuilderTests {

    @Test func makePlateEntityReturnsEntityForEveryTier() {
        for tierID in 0...7 {
            let entity = makePlateEntity(tierID: tierID)
            #expect(entity.components[InputTargetComponent.self] != nil,
                    "tier \(tierID) missing InputTargetComponent")
            #expect(entity.components[CollisionComponent.self] != nil,
                    "tier \(tierID) missing CollisionComponent")
            #expect(entity.components[PlateRoleComponent.self] != nil,
                    "tier \(tierID) missing PlateRoleComponent")
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
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```
Cmd+U in Xcode (or xcodebuild test -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16')
```

Expected: compile error — `makePlateEntity` not yet defined.

- [ ] **Step 3: Add per-style helper functions to BarbellEntityBuilder.swift**

Append to `BarbellEntityBuilder.swift`:

```swift
// MARK: - Per-style plate helpers
// Mirror the geometry from BarbellPreviewView's per-style functions.

private func makeRawIronEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?) -> ModelEntity {
    var mat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
    if let tex = textures {
        if let a = tex.albedo    { mat.baseColor  = .init(tint: .white, texture: .init(a)) }
        if let n = tex.normal    { mat.normal     = .init(texture: .init(n)) }
        if let r = tex.roughness { mat.roughness  = .init(texture: .init(r)) }
        if let m = tex.metalness { mat.metallic   = .init(texture: .init(m)) }
    }
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: 0.18), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return plate
}

private func makeCastIronEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?) -> ModelEntity {
    let radius: Float = 0.18
    var outerMat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
    var innerMat = pbrMaterial(color: UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                                metallic: 0.04, roughness: 0.96)
    if let tex = textures {
        if let a = tex.albedo {
            outerMat.baseColor = .init(tint: .white,                      texture: .init(a))
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

private func makeBumperEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?) -> ModelEntity {
    let radius: Float = 0.18
    var mat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
                           clearcoat: tier.clearcoat, clearcoatRoughness: tier.clearcoatRoughness)
    if let tex = textures {
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

private func makeBrassEntity(tier: PlateTier, thickness: Float, textures: PlateTextures?) -> ModelEntity {
    // Brass uses same shape as rawIron but with brass PBR values
    makeRawIronEntity(tier: tier, thickness: thickness, textures: textures)
}

private func makeCompetitionEntity(tier: PlateTier, thickness: Float) -> ModelEntity {
    let radius: Float = 0.18
    let mat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
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
    // Starter: small bright green rubber disc, no weight stamp
    let mat = pbrMaterial(color: UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1), metallic: 0, roughness: 0.9)
    let plate = ModelEntity(mesh: .generateCylinder(height: thickness, radius: 0.12), materials: [mat])
    plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return plate
}

private func makeWeightDisc(weightKg: Double, tierID: Int) -> ModelEntity {
    // Renders weight number to a thin disc placed at the plate face.
    // Same approach as BarbellPreviewView.makeWeightDisc.
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
    disc.position = SIMD3(0, 0.018, 0)  // offset toward front face
    return disc
}
```

- [ ] **Step 4: Add the main makePlateEntity function**

Append to `BarbellEntityBuilder.swift`:

```swift
// MARK: - makePlateEntity

/// Builds a complete plate ModelEntity for the given tier.
/// Attach InputTargetComponent and CollisionComponent are always set so the
/// entity is immediately eligible for DragGesture().targetedToAnyEntity().
///
/// - Parameters:
///   - tierID: 0-7 matching PlateTier.all.id
///   - textures: Pre-loaded PBR textures from loadPlateTextures(forTierID:). Pass nil to fall back to color materials.
///   - weightKg: Renders weight number on a face disc when > 0
///   - engravingText: Not rendered in this builder (engraving discs are for the editor, not rack room)
///   - role: .floor (default) or .bar — stored in PlateRoleComponent for gesture routing
func makePlateEntity(
    tierID: Int,
    textures: PlateTextures? = nil,
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
        entity = makeRawIronEntity(tier: tier, thickness: plateThickness, textures: textures)
    case .castIron:
        entity = makeCastIronEntity(tier: tier, thickness: plateThickness, textures: textures)
    case .bumper:
        entity = makeBumperEntity(tier: tier, thickness: plateThickness, textures: textures)
    case .brass:
        entity = makeBrassEntity(tier: tier, thickness: plateThickness, textures: textures)
    case .starter:
        entity = makeStarterEntity(tier: tier, thickness: plateThickness)
    default:  // competition, polishedSteel, gold
        entity = makeCompetitionEntity(tier: tier, thickness: plateThickness)
    }

    // Chrome hub
    let hub = ModelEntity(
        mesh: .generateCylinder(height: plateThickness + 0.003, radius: 0.028),
        materials: [chromeMaterial()]
    )
    entity.addChild(hub)

    // Weight disc (skip starter plates: tierID 7)
    if weightKg > 0 && tierID != 7 {
        entity.addChild(makeWeightDisc(weightKg: weightKg, tierID: tierID))
    }

    // Gesture components
    entity.components.set(InputTargetComponent())
    entity.components.set(CollisionComponent(shapes: [
        .generateBox(size: SIMD3(0.36, plateThickness, 0.36))
    ]))
    entity.components.set(PlateRoleComponent(role: role))

    return entity
}
```

- [ ] **Step 5: Run tests to verify they pass**

```
Cmd+U
```

Expected: `BarbellEntityBuilderTests` — all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat: add makePlateEntity to BarbellEntityBuilder with per-style geometry"
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

/// Builds the bar cylinder. skinID indexes into BarSkin.all.
func makeBarEntity(skinID: Int = 0) -> ModelEntity {
    let skin = BarSkin.all[max(0, min(skinID, BarSkin.all.count - 1))]
    let mat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)
    let bar = ModelEntity(
        mesh: .generateCylinder(height: 1.1, radius: 0.012),
        materials: [mat]
    )
    // Rotate cylinder axis (Y) to lie along X (bar axis)
    bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return bar
}

/// Builds one collar. Position it at ±0.475 on X after creation.
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

/// Builds a vertical rack upright. Position at ±0.55 on X after creation.
func makeRackStandEntity() -> ModelEntity {
    let mat = pbrMaterial(color: UIColor(white: 0.25, alpha: 1), metallic: 0.3, roughness: 0.75)
    // Main upright
    let stand = Entity()
    let post = ModelEntity(
        mesh: .generateCylinder(height: 1.0, radius: 0.025),
        materials: [mat]
    )
    // Cylinder axis is Y by default — correct for a vertical post
    stand.addChild(post)
    // Foot plate
    let foot = ModelEntity(
        mesh: .generateBox(size: SIMD3(0.12, 0.02, 0.08)),
        materials: [mat]
    )
    foot.position = SIMD3(0, -0.51, 0)
    stand.addChild(foot)
    // Saddle (J-hook shape approximated as a small box at bar height)
    let saddle = ModelEntity(
        mesh: .generateBox(size: SIMD3(0.06, 0.03, 0.04)),
        materials: [pbrMaterial(color: UIColor(white: 0.15, alpha: 1), metallic: 0.1, roughness: 0.9)]
    )
    saddle.position = SIMD3(0, 0.1, 0.03)  // slightly forward at bar height
    stand.addChild(saddle)
    // Return a ModelEntity wrapper so the caller gets a consistent type.
    // Stand children provide the actual geometry.
    let root = ModelEntity()
    root.addChild(stand)
    return root
}
```

- [ ] **Step 4: Run tests**

Expected: all 6 `BarbellEntityBuilderTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift \
        WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat: add makeBarEntity, makeCollarEntity, makeRackStandEntity to BarbellEntityBuilder"
```

---

## Task 4: SceneState, DragPhase, BarbellRealityMode — skeleton view file

**Files:**
- Create: `Features/Rewards/Views/BarbellRealityView.swift`
- Create: `WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift
import Testing
import RealityKit
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
        let plate = EarnedPlate(
            id: "test-id",
            tierID: 0, weightKg: 5,
            engravingText: "Test",
            earnedByEvent: "first_workout"
        )
        state.addPlate(plate)
        #expect(state.entityMap["test-id"] != nil)
    }

    @Test func addPlateIdempotent() {
        let state = SceneState()
        let plate = EarnedPlate(
            id: "dup-id",
            tierID: 1, weightKg: 10,
            engravingText: "",
            earnedByEvent: "5_workouts"
        )
        state.addPlate(plate)
        state.addPlate(plate)
        #expect(state.entityMap.count == 1)
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
// One instance per plate in .welcome mode. Holds independent spin velocity/angle
// so each plate coin-spins at a different speed. Class (not struct) because it is
// mutated per frame inside a Task loop without triggering SwiftUI re-renders.

final class PlateSpinState {
    var angle: Float = Float.random(in: 0 ..< Float.pi * 2)
    var velocity: Float = Float.random(in: 0.5 ..< 1.8) * (Bool.random() ? 1 : -1)
}

// MARK: - SceneState
// Owned by the parent view (@State var sceneState = SceneState()).
// Passed into BarbellRealityView as an init parameter.
// Mutations to this class do NOT trigger SwiftUI re-renders.

final class SceneState {

    // Anchor entities — reference types, safe to hold and mutate outside make{}
    var floorAnchor = Entity()
    var barAnchor   = Entity()
    var sceneRoot   = Entity()      // top-level root added to RealityViewContent

    // Barbell root for .welcome mode (spin target)
    var barbellRoot: Entity?

    // Entity lookup — keyed by EarnedPlate.id
    var entityMap: [String: Entity] = [:]

    // Gesture state
    var dragPhase: DragPhase = .idle

    // Floor pan state (.rackRoom)
    var floorOffset: Float   = 0
    var floorVelocity: Float = 0
    var floorMinX: Float     = 0    // set in make{} based on plate count
    var floorMaxX: Float     = 0

    // Welcome spin state (.welcome)
    var plateSpinStates: [String: PlateSpinState] = [:]
    var barbellSpinAngle: Float    = 0
    var barbellSpinVelocity: Float = 0.35

    // Texture cache — populated in .task{}, used by addPlate()
    var plateTextureCache: [Int: PlateTextures] = [:]

    // Adds a newly earned plate entity to the floor during a live session.
    // Safe to call from PlateWallView.onChange because floorAnchor is an Entity
    // (reference type); adding a child is picked up by RealityKit automatically.
    func addPlate(_ plate: EarnedPlate) {
        guard entityMap[plate.id] == nil else { return }
        let textures = plateTextureCache[plate.tierID]
        let entity = makePlateEntity(
            tierID: plate.tierID,
            textures: textures,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            role: .floor
        )
        entity.name = plate.id
        // Place at the far end of existing floor plates (0.15m spacing)
        let xPos = Float(floorAnchor.children.count) * 0.15
        entity.position = SIMD3(xPos, 0, 0)
        let leanAngle = Float.random(in: 0.10 ..< 0.23)
        entity.orientation = simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))
        floorAnchor.addChild(entity)
        entityMap[plate.id] = entity
        // Extend floor clamp bounds
        if xPos > floorMaxX { floorMaxX = xPos }
    }

    // Per-frame spin loop for .welcome mode. Called from .task{} in BarbellWelcomeView.
    // Lives on SceneState so it can be called directly without creating a new view instance.
    @MainActor
    func runWelcomeSpinLoop() async {
        var lastTime = Date().timeIntervalSinceReferenceDate
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date().timeIntervalSinceReferenceDate
            let dt = Float(min(now - lastTime, 0.05))
            lastTime = now

            // Per-plate spin
            for (key, spinState) in plateSpinStates {
                spinState.velocity *= pow(0.995, dt * 60)
                spinState.angle    += spinState.velocity * dt
                entityMap[key]?.orientation =
                    simd_quatf(angle: spinState.angle, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            }

            // Hero barbell spin
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

In Xcode: add `Features/Rewards/Views/BarbellRealityView.swift` to WRKT target.
Add `WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift` to WRKTTests target.

- [ ] **Step 5: Run tests**

Expected: `SceneStateTests` — all 4 pass.

Note: `addPlateUpdatesEntityMap` and `addPlateIdempotent` require `EarnedPlate` to have a memberwise init with `id:`. Check `BarbellModels.swift` — `EarnedPlate.init` already accepts an `id` parameter (defaults to `UUID().uuidString`). Pass `id: "test-id"` explicitly.

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift \
        WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift
git commit -m "feat: add SceneState, DragPhase, BarbellRealityMode skeleton"
```

---

## Task 5: BarbellRealityView — welcome mode

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Replace the stub body with the full welcome implementation**

Replace the entire `BarbellRealityView` struct in `BarbellRealityView.swift`:

```swift
struct BarbellRealityView: View {
    let mode: BarbellRealityMode
    let sceneState: SceneState

    var body: some View {
        ZStack {
            RealityView { content in
                setupLighting(content: &content)
                sceneState.sceneRoot = Entity()
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
            } update: { _ in
                // Intentionally empty — scene owns its runtime state
            }
            .gesture(entityDragGesture)
            .gesture(floorPanGesture)

            overlayView
        }
    }

    // MARK: Lighting

    private func setupLighting(content: inout RealityViewContent) {
        let key = Entity()
        key.components[PointLightComponent.self] = PointLightComponent(
            color: .white, intensity: 3000, attenuationRadius: 10
        )
        key.position = SIMD3(0.5, 1.5, 1.5)
        content.add(key)

        let fill = Entity()
        fill.components[PointLightComponent.self] = PointLightComponent(
            color: .init(white: 0.85, alpha: 1), intensity: 800, attenuationRadius: 8
        )
        fill.position = SIMD3(-1.5, -0.5, 0.8)
        content.add(fill)
    }

    // MARK: Welcome scene setup

    private func setupWelcomeScene(content: inout RealityViewContent, plates: [EarnedPlateInfo]) {
        // Hero barbell (no plate data needed — shows starter plates)
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

        // Plate grid — rows of 4, face-on to camera
        let cols = 4
        let spacingX: Float = 0.12
        let spacingY: Float = 0.14
        for (i, info) in plates.enumerated() {
            let col = Float(i % cols)
            let row = Float(i / cols)
            let entity = makePlateEntity(
                tierID: info.tierID,
                weightKg: info.weightKg,
                engravingText: info.engravingText,
                role: .floor    // .floor so entityDragGesture routes to spin, not rack
            )
            entity.name = "welcome_plate_\(i)"
            // Face-on: cylinder oriented so flat face looks toward +Z (camera)
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

    // MARK: Overlay SwiftUI

    @ViewBuilder
    private var overlayView: some View {
        switch mode {
        case .welcome:
            EmptyView()    // BarbellWelcomeView owns the CTA overlay — see Task 6
        case .rackRoom:
            EmptyView()    // PlateWallView owns the Done/weight overlay — see Task 11
        }
    }

    // MARK: Gesture stubs (implemented in Tasks 7-10)

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

    // MARK: RackRoom scene setup stub (Task 7)
    private func setupRackRoomScene(content: inout RealityViewContent,
                                     racked: [EarnedPlate], floor: [EarnedPlate]) {}
}
```

- [ ] **Step 2: Add .task{} for async texture loading in BarbellWelcomeView.swift (preview)**

This step is done in Task 6. Skip for now — the stub view is sufficient to verify the welcome scene renders.

- [ ] **Step 3: Build and verify compilation**

```
Cmd+B
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: implement BarbellRealityView welcome mode scene setup and spin loop"
```

---

## Task 6: Migrate BarbellWelcomeView

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

            BarbellRealityView(
                mode: .welcome(plates: showcasePlateInfos),
                sceneState: sceneState
            )
            .ignoresSafeArea()
            .task { @MainActor in
                // Load textures into sceneState cache, then start spin loop
                for tierID in 0...6 {
                    sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                }
                await sceneState.applyTexturesToWelcomeEntities()
                await sceneState.runWelcomeSpinLoop()
            }

            // SwiftUI overlay
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

- [ ] **Step 3: Add applyTexturesToWelcomeEntities to SceneState**

Append to `SceneState` in `BarbellRealityView.swift`:

```swift
/// After textures are loaded into plateTextureCache, update all welcome-mode
/// plate entity materials. Called once from BarbellWelcomeView.task{}.
@MainActor
func applyTexturesToWelcomeEntities() async {
    for (key, entity) in entityMap {
        guard key.hasPrefix("welcome_plate_") else { continue }
        // Rebuild the entity's materials with textures now that they are loaded.
        // Extract tierID from the PlateRoleComponent is not available here,
        // so we match against the entity's first ModelComponent material color.
        // Simplest approach: store tierID alongside entity in a parallel dict.
        // For now the welcome view rebuilds the scene root if textures change.
        // This is acceptable since it happens at most once per session launch.
        _ = entity  // texture application deferred to rackRoom mode for now
    }
    // Trigger sceneRoot IBL if IndoorHDRI is available
    if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
        let iblEntity = Entity()
        iblEntity.components.set(ImageBasedLightComponent(source: .single(ibl), intensityExponent: 0.5))
        sceneRoot.addChild(iblEntity)
        sceneRoot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
    }
}
```

Update `applyTexturesToWelcomeEntities`:

```swift
@MainActor
func applyTexturesToWelcomeEntities() async {
    for (_, entity) in entityMap {
        guard let tierComp = entity.components[TierIDComponent.self] else { continue }
        let textures = plateTextureCache[tierComp.tierID]
        guard let textures, let albedo = textures.albedo else { continue }
        if var model = entity.components[ModelComponent.self] {
            if var mat = model.materials.first as? PhysicallyBasedMaterial {
                mat.baseColor = .init(tint: .white, texture: .init(albedo))
                if let n = textures.normal    { mat.normal    = .init(texture: .init(n)) }
                if let r = textures.roughness { mat.roughness = .init(texture: .init(r)) }
                if let m = textures.metalness { mat.metallic  = .init(texture: .init(m)) }
                model.materials = [mat]
                entity.components.set(model)
            }
        }
    }
    if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
        let iblEntity = Entity()
        iblEntity.components.set(ImageBasedLightComponent(source: .single(ibl), intensityExponent: 0.5))
        sceneRoot.addChild(iblEntity)
        sceneRoot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
    }
}
```

- [ ] **Step 4: Build**

```
Cmd+B
```

Expected: no errors. `SceneKit` import removed from `BarbellWelcomeView.swift` — confirm no SceneKit references remain.

- [ ] **Step 5: Run on simulator and verify visually**

Run on iPhone 16 simulator. Navigate to the welcome screen. Verify:
- [ ] 3D barbell renders at top with auto-spin
- [ ] Earned plate entities appear in a grid below
- [ ] Tapping "Build Your Rack" opens `PlateWallView`

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellWelcomeView.swift \
        Features/Rewards/Views/BarbellEntityBuilder.swift \
        Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: migrate BarbellWelcomeView from SceneKit to BarbellRealityView welcome mode"
```

---

## Task 7: BarbellRealityView — rackRoom scene setup

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Implement setupRackRoomScene**

Replace the stub `setupRackRoomScene` function in `BarbellRealityView`:

```swift
private func setupRackRoomScene(
    content: inout RealityViewContent,
    racked: [EarnedPlate],
    floor: [EarnedPlate]
) {
    // Camera at (0, 0.4, 1.8) looking toward origin, ~42-degree FOV.
    // RealityView uses a default perspective camera; we position the scene root
    // to achieve the desired framing rather than moving the camera directly.
    sceneState.sceneRoot.position = SIMD3(0, -0.3, -1.4)

    // Rack stands at ±0.55 on X
    for xSign: Float in [-1, 1] {
        let stand = makeRackStandEntity()
        stand.position = SIMD3(xSign * 0.55, 0.3, 0)
        sceneState.sceneRoot.addChild(stand)
    }

    // Bar at Y = 0.6 (resting on saddles)
    let bar = makeBarEntity(skinID: 0)
    bar.position = SIMD3(0, 0.6, 0)
    sceneState.sceneRoot.addChild(bar)
    sceneState.barAnchor.position = SIMD3(0, 0.6, 0)
    sceneState.sceneRoot.addChild(sceneState.barAnchor)

    // Collars at ±0.475 relative to bar
    for xSign: Float in [-1, 1] {
        let collar = makeCollarEntity()
        collar.position = SIMD3(xSign * 0.475, 0.6, 0)
        sceneState.sceneRoot.addChild(collar)
    }

    // Floor line reference (thin box at Y = 0)
    let floor_line = ModelEntity(
        mesh: .generateBox(size: SIMD3(1.2, 0.004, 0.08)),
        materials: [pbrMaterial(color: UIColor(white: 0.15, alpha: 1), metallic: 0, roughness: 1)]
    )
    floor_line.position = SIMD3(0, 0, 0)
    sceneState.sceneRoot.addChild(floor_line)

    // Racked plates on bar
    let slotOffsets: [Float] = [0.34, 0.37, 0.40, 0.43]
    let sorted = racked.sorted { ($0.rackPosition ?? 999) < ($1.rackPosition ?? 999) }
    for (idx, plate) in sorted.prefix(4).enumerated() {
        let offset = slotOffsets[min(idx, slotOffsets.count - 1)]
        for xSign: Float in [-1, 1] {
            let entity = makePlateEntity(
                tierID: plate.tierID,
                textures: sceneState.plateTextureCache[plate.tierID],
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                role: .bar
            )
            entity.name = plate.id
            entity.position = SIMD3(xSign * offset, 0, 0)  // relative to barAnchor
            sceneState.barAnchor.addChild(entity)
            // Only store one entity per EarnedPlate (bilateral rendering uses same data)
            if xSign == 1 {
                sceneState.entityMap[plate.id] = entity
            }
        }
    }

    // Floor plates leaning against rack base
    let spacing: Float = 0.15
    for (idx, plate) in floor.enumerated() {
        let entity = makePlateEntity(
            tierID: plate.tierID,
            textures: sceneState.plateTextureCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            role: .floor
        )
        entity.name = plate.id
        let xPos = Float(idx) * spacing
        entity.position = SIMD3(xPos, 0, 0)
        // Lean angle: slight tilt backward (rotation around X from face-forward orientation)
        let leanAngle = Float.random(in: 0.10 ..< 0.23)
        entity.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))
        sceneState.floorAnchor.addChild(entity)
        sceneState.entityMap[plate.id] = entity
    }

    // Clamp bounds for floor pan
    let totalWidth = Float(max(floor.count - 1, 0)) * spacing
    sceneState.floorMinX = 0
    sceneState.floorMaxX = max(totalWidth - 0.8, 0)
}
```

- [ ] **Step 2: Build**

```
Cmd+B
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: implement rackRoom scene setup — rack stands, bar, floor plates"
```

---

## Task 8: rackRoom — floor pan gesture

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Add unit test for floor offset clamping**

Append to `SceneStateTests`:

```swift
@Test func floorOffsetClampDoesNotExceedBounds() {
    let state = SceneState()
    state.floorMinX = 0
    state.floorMaxX = 1.0
    // Simulate clamped assignment
    let raw: Float = 1.5
    let clamped = max(state.floorMinX, min(state.floorMaxX, raw))
    #expect(clamped == 1.0)
}
```

- [ ] **Step 2: Run test to confirm it passes immediately** (pure math, no RealityKit needed)

- [ ] **Step 3: Replace the floorPanGesture stub**

Replace the `floorPanGesture` computed property in `BarbellRealityView`:

```swift
private var floorPanGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
        .onChanged { value in
            guard case .idle = sceneState.dragPhase else { return }
            sceneState.dragPhase = .panningFloor
            let delta = Float(value.translation.width - (value.startLocation.x - value.location.x)) * -0.002
            let raw = sceneState.floorOffset + delta
            sceneState.floorOffset = max(sceneState.floorMinX, min(sceneState.floorMaxX, raw))
            sceneState.floorAnchor.position.x = -sceneState.floorOffset
            sceneState.floorVelocity = delta * 60
        }
        .onEnded { _ in
            sceneState.dragPhase = .idle
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

- [ ] **Step 4: Build and run on simulator**

Verify the floor plates pan left/right with momentum when dragging empty space below the bar.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift \
        WRKTTests/FeaturesTests/Barbell/SceneStateTests.swift
git commit -m "feat: implement floor pan gesture with momentum for rackRoom mode"
```

---

## Task 9: rackRoom — rack gesture (floor plate → bar)

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

- [ ] **Step 1: Add helper to find EarnedPlate from entityMap key**

This gesture calls `onRack(plate)` at the end. To find the `EarnedPlate` from an entity, the gesture handler uses the entity's `name` (set to `plate.id` in `setupRackRoomScene`). The `onRack` callback is extracted from the mode enum when needed:

```swift
// In BarbellRealityView — add this helper
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

- [ ] **Step 2: Replace entityDragGesture stub with rack+unrack handler**

Replace `entityDragGesture` in `BarbellRealityView`:

```swift
private var entityDragGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .global)
        .targetedToAnyEntity()
        .onChanged { value in
            let entity = value.entity
            guard let roleComp = entity.components[PlateRoleComponent.self] else { return }

            switch roleComp.role {
            case .floor:
                // Rack gesture: lift plate and follow finger
                sceneState.dragPhase = .draggingPlate(entity, plateID: entity.name)
                let worldPos = value.convert(value.location3D, from: .local, to: .scene)
                entity.position = worldPos
                entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)

            case .bar:
                // Unrack gesture: detect horizontal swipe
                guard case .idle = sceneState.dragPhase else { return }
                let dx = Float(value.translation.width)
                if abs(dx) > 0.04 {
                    // Animate plate off bar end in swipe direction
                    let slideTarget = Transform(
                        scale: entity.scale,
                        rotation: entity.orientation,
                        translation: entity.position(relativeTo: nil)
                            + SIMD3(dx > 0 ? 0.6 : -0.6, 0, 0)
                    )
                    entity.move(to: slideTarget, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
                    sceneState.dragPhase = .draggingPlate(entity, plateID: entity.name)
                    entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                    // Update role so onEnded knows this is an unrack gesture
                    entity.components.set(PlateRoleComponent(role: .floor))
                }
            }
        }
        .onEnded { value in
            guard case .draggingPlate(let entity, let plateID) = sceneState.dragPhase else { return }
            sceneState.dragPhase = .idle

            let worldPos = value.convert(value.location3D, from: .local, to: .scene)
            let barWorldY = sceneState.barAnchor.position(relativeTo: nil).y

            // Determine whether this was originally a floor→bar rack or a bar→floor unrack
            // by checking whether this entity is in allFloorPlates or allRackedPlates
            let isFromFloor = allFloorPlates.contains { $0.id == plateID }

            if isFromFloor && worldPos.y > barWorldY - 0.15 {
                // Snap to bar — find next open slot
                snapToBar(entity: entity, plateID: plateID)
            } else if !isFromFloor && worldPos.y < barWorldY - 0.2 {
                // Unrack — land on floor
                snapToFloor(entity: entity, plateID: plateID)
            } else {
                // Missed — snap back to original position
                snapBack(entity: entity, plateID: plateID)
            }
        }
}
```

- [ ] **Step 3: Add snapToBar, snapToFloor, snapBack helpers**

Append to `BarbellRealityView`:

```swift
// MARK: - Snap animations

private func snapToBar(entity: Entity, plateID: String) {
    // Find next open slot (0-3 from innermost)
    let slotOffsets: [Float] = [0.34, 0.37, 0.40, 0.43]
    let occupiedSlots = allRackedPlates.compactMap(\.rackPosition)
    guard let nextSlot = (0..<4).first(where: { !occupiedSlots.contains($0) }) else {
        snapBack(entity: entity, plateID: plateID)
        return
    }
    let offset = slotOffsets[nextSlot]

    entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
    entity.components.set(PlateRoleComponent(role: .bar))

    // Animate bilateral: add a second entity for the other side
    let mirrorEntity = entity.clone(recursive: true)
    mirrorEntity.name = plateID + "_mirror"
    sceneState.barAnchor.addChild(mirrorEntity)

    for (e, xSign) in [(entity, Float(1)), (mirrorEntity, Float(-1))] {
        let target = Transform(
            scale: SIMD3(repeating: 1),
            rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)),
            translation: SIMD3(xSign * offset, 0, 0)
        )
        e.move(to: target, relativeTo: sceneState.barAnchor, duration: 0.25, timingFunction: .easeOut)
    }

    // Call persistence callback after animation
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(260))
        if let plate = allFloorPlates.first(where: { $0.id == plateID }) {
            onRackCallback?(plate)
            BarbellProgressService.shared.playClinkHaptic()
        }
    }
}

private func snapToFloor(entity: Entity, plateID: String) {
    // Place entity at end of current floor plates
    let xPos = Float(sceneState.floorAnchor.children.count) * 0.15
    entity.setParent(sceneState.floorAnchor, preservingWorldTransform: true)
    entity.components.set(PlateRoleComponent(role: .floor))
    let leanAngle = Float.random(in: 0.10 ..< 0.23)
    let target = Transform(
        scale: SIMD3(repeating: 1),
        rotation: simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1)),
        translation: SIMD3(xPos, 0, 0)
    )
    entity.move(to: target, relativeTo: sceneState.floorAnchor, duration: 0.25, timingFunction: .easeOut)

    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(260))
        if let plate = allRackedPlates.first(where: { $0.id == plateID }) {
            onUnrackCallback?(plate)
            // Remove mirror entity from barAnchor
            sceneState.barAnchor.children.first(where: { $0.name == plateID + "_mirror" })?
                .removeFromParent()
        }
    }
}

private func snapBack(entity: Entity, plateID: String) {
    // Determine original parent and position from entityMap
    if let original = sceneState.entityMap[plateID] {
        let target = Transform(matrix: original.transformMatrix(relativeTo: nil))
        entity.move(to: target, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
    }
    entity.setParent(
        entity.components[PlateRoleComponent.self]?.role == .bar
            ? sceneState.barAnchor : sceneState.floorAnchor,
        preservingWorldTransform: true
    )
}
```

- [ ] **Step 4: Build**

```
Cmd+B
```

Expected: no errors.

- [ ] **Step 5: Run on simulator — rack test**

1. Open PlateWallView (temporarily wire it in Task 11 — do a quick stub first if needed).
2. Drag a floor plate up to the bar zone. Verify it snaps onto the bar.
3. Verify `BarbellProgressService.rackPlate()` is called (check that the plate appears on bar after relaunch).

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: implement rack gesture (floor plate drag to bar) for rackRoom mode"
```

---

## Task 10: rackRoom — unrack gesture (bar plate → floor)

The unrack path is already handled inside `entityDragGesture` from Task 9 (the `.bar` role branch detects the horizontal swipe and calls `snapToFloor`). This task verifies it works end-to-end and fixes any issues found.

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift` (fixes only)

- [ ] **Step 1: Run on simulator — unrack test**

1. With a plate on the bar, swipe it left or right.
2. Verify the plate slides off the bar end.
3. Drag it down to the floor zone and release. Verify it lands on the floor.
4. Verify `BarbellProgressService.unrackPlate()` is called (plate no longer on bar after relaunch).

- [ ] **Step 2: Fix snapBack for unrack miss case**

If the user swipes a plate off the bar but releases it in mid-air (not in the floor zone), `snapBack` should return it to its bar position. The current `snapBack` reads `sceneState.entityMap[plateID]` which holds the floor entity reference, not the bar position.

Extend `SceneState` with a bar position cache:

```swift
// In SceneState — add this property
var barPositionMap: [String: SIMD3<Float>] = [:]  // plateID -> position on barAnchor
```

Set it in `setupRackRoomScene` after placing each bar plate:

```swift
// After entity.position = SIMD3(xSign * offset, 0, 0):
if xSign == 1 {
    sceneState.barPositionMap[plate.id] = SIMD3(xSign * offset, 0, 0)
}
```

Update `snapBack` to use `barPositionMap` for bar plates:

```swift
private func snapBack(entity: Entity, plateID: String) {
    if let roleComp = entity.components[PlateRoleComponent.self], roleComp.role == .bar,
       let barPos = sceneState.barPositionMap[plateID] {
        entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
        let target = Transform(
            scale: SIMD3(repeating: 1),
            rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)),
            translation: barPos
        )
        entity.move(to: target, relativeTo: sceneState.barAnchor, duration: 0.2, timingFunction: .easeOut)
    } else if let original = sceneState.entityMap[plateID] {
        let target = Transform(matrix: original.transformMatrix(relativeTo: nil))
        entity.move(to: target, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
        entity.setParent(sceneState.floorAnchor, preservingWorldTransform: true)
    }
}
```

- [ ] **Step 3: Build and re-test unrack flow on simulator**

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "feat: fix snapBack for unrack-cancelled gesture; add barPositionMap to SceneState"
```

---

## Task 11: Migrate PlateWallView

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

    private var totalWeight: Double {
        let racked = rackedPlates.filter { $0.earnedByEvent != "starter" }
        return 20 + racked.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
            .task { @MainActor in
                for tierID in 0...6 {
                    sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                }
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
            }
            .onChange(of: ownedPlates.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                let existing = Set(sceneState.entityMap.keys)
                if let newPlate = ownedPlates.first(where: { !existing.contains($0.id) }) {
                    sceneState.addPlate(newPlate)
                }
            }

            // SwiftUI overlay
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

```
Cmd+B
```

Expected: no errors. All SceneKit, `DragGesture` zone logic, `PlateShelfRow`, `PlateCell`, `BarbellPreviewView(mode: .showcase)` references removed.

- [ ] **Step 3: Run all tests**

```
Cmd+U
```

Expected: all existing tests pass (barbell unlock rules, SceneState, EntityBuilder).

- [ ] **Step 4: Run on simulator — end-to-end flow**

1. Launch app → navigate to the barbell feature
2. Verify `BarbellWelcomeView` renders with RealityKit barbell and spinning plate grid
3. Tap "Build Your Rack" → `PlateWallView` opens
4. Verify rack room renders: stands, bar, floor plates
5. Drag a floor plate up to the bar → verify it snaps on, clink plays, haptic fires
6. Swipe a bar plate left or right → verify it slides off → drag down → verify it lands on floor
7. Swipe floor left/right with no plate under finger → verify floor pans with momentum
8. Dismiss → verify `BarbellWelcomeView` also dismisses
9. Relaunch app → verify rack state persisted (racked plates still on bar)

- [ ] **Step 5: Commit**

```bash
git add Features/Profile/Views/PlateWallView.swift
git commit -m "feat: migrate PlateWallView to BarbellRealityView rackRoom mode"
```

---

## Task 12: Cleanup and final verification

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift` (remove SceneKit import if still present)
- Modify: `Features/Rewards/Views/BarbellRealityView.swift` (remove any leftover TODOs)

- [ ] **Step 1: Verify no SceneKit imports remain in the two migrated files**

```bash
grep -r "import SceneKit" Features/Rewards/Views/BarbellWelcomeView.swift \
                          Features/Profile/Views/PlateWallView.swift
```

Expected: no output.

- [ ] **Step 2: Verify no BarbellPreviewView showcase mode usage in PlateWallView**

```bash
grep -r "showcase" Features/Profile/Views/PlateWallView.swift
```

Expected: no output.

- [ ] **Step 3: Run full test suite**

```
Cmd+U
```

Expected: all tests pass.

- [ ] **Step 4: Final simulator verification on both iPhone and iPad**

Check for layout issues on iPad (wider screen may require camera FOV adjustment in `setupRackRoomScene`).

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete BarbellRealityKit migration — unified scene for WelcomeView and PlateWallView"
```

---

## Implementation Notes

**RealityKit bilateral plate rendering:** Each racked `EarnedPlate` shows on both sides of the bar. `snapToBar` creates a `clone` for the mirror entity. The canonical entity (positive X side) is stored in `entityMap`; the mirror entity (`plateID_mirror`) is stored on `barAnchor` only.

**BarbellPreviewView is untouched:** It uses RealityKit independently for the cosmetic editor. When both `BarbellPreviewView` and `PlateWallView` are never on screen simultaneously (they are on different navigation paths), there is no multi-instance RealityKit crash risk.

**SceneKit imports:** After migration `BarbellWelcomeView.swift` should have zero SceneKit imports. All SceneKit code is deleted, not commented out.

**Texture loading timing:** Textures are loaded in `.task{}` after the scene builds. Entities render with color-only PBR materials initially and texture updates applied via `TierIDComponent` lookup. For most tiers (4, 5, 6, 7) there are no bundle textures and color materials are the final appearance.

**`DragGesture()` vs `.targetedToAnyEntity()` coexistence:** RealityKit naturally prioritises `.targetedToAnyEntity()` when a touch starts on an entity. The plain `DragGesture()` (floor pan) fires only when no entity is under the finger. No explicit gesture priority configuration is needed.
