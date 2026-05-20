# Barbell Plate Drag Polish

**Date:** 2026-05-20
**Scope:** Four targeted fixes to the rack room plate interaction — performance, tap UX, gesture coverage, and animation bounds.

---

## Problem

1. **Lag when pulling plates fast**: each plate has up to 22 individual `ModelEntity` children for progression marks (tier rings, chalk, wear, polish). Multiple simultaneous `entity.move()` animations drive 44+ transform updates per frame, causing visible stutter.
2. **Bar plates show info card on tap**: tapping a racked plate triggers the detail info card, which is disruptive during gameplay.
3. **Left-side swipe unreliable**: `barHitZone` exists to handle left-side unrack gestures but sits at z=−0.05 with a 0.05m deep collision box — touch rays at slight angles miss it.
4. **Unrack animation exits view**: `slideTargetX = 0.78` places the plate at the room wall edge, which exits the visible camera frustum before the 200ms animation ends.

---

## Changes

### 1. Progression Mark Texture Bake

**File:** `Features/Rewards/Views/BarbellEntityBuilder.swift`

Replace `addProgressionDetails(to:projection:plateThickness:)` with `makeProgressionOverlayDisc(projection:profile:) -> ModelEntity`.

The new function:
- Renders all progression marks onto a single 512×512 `UIGraphicsImageRenderer` canvas:
  - Tier rings: concentric arcs using `BarbellPlateRenderProjection.tierAccentColor` and the same radii currently used for ring entities (0.198, 0.178, 0.158)
  - Chalk marks: small white rectangles at current angles and radii
  - Grip wear marks: dark brown short strokes at current positions
  - Polish marks: small bright squares at current positions
- Wraps the result as a `TextureResource`
- Creates one flat disc `ModelEntity`:
  - Mesh: `cachedPlateRing(height: 0.001, outerRadius: profile.outerRadius - 0.004, innerRadius: plateBoreRadius)` — covers the full plate face from bore edge to just inside the rim, large enough to include tier rings at radius 0.198m
  - Position: `SIMD3(0, profile.thickness * 0.5 + 0.016, 0)` — sits 3mm above the engraving disc to avoid z-fighting
- Material: `UnlitMaterial` with `.transparent` blending, black transparent background — same pattern as `makeEngravingDiscUnlitFallback`

**Accepted visual tradeoff:** current tier rings use `metallic: 0.9, clearcoat: 0.35` and polish marks use `metallic: 1.0, roughness: 0.18` (PBR). Baking into a single `UnlitMaterial` disc drops these properties — tier rings and polish marks lose their metallic sheen. Chalk and grip wear marks are near-matte and unaffected in practice. This tradeoff is accepted: progression marks are small secondary details and the performance gain outweighs exact PBR parity. A future ShaderGraph mask approach could restore metallic response if needed.

**Meter-to-pixel coordinate mapping:** marks are placed in the plate's local x/z plane. The canvas radius corresponds to `overlayRadius = profile.outerRadius - 0.004`. For a mark at local position `(x, z)`:
```
u = Float((x / overlayRadius + 1.0) * 0.5)
v = Float(1.0 - (z / overlayRadius + 1.0) * 0.5)   // CoreGraphics y-axis is downward
```
Mark rotation around the y-axis by `angle` → `CGAffineTransform(rotationAngle: CGFloat(-angle))` applied to the CGContext before drawing each mark rectangle.

The existing early-exit guard is preserved:
```swift
guard projection != BarbellPlateRenderProjection() else { return }
```

Plates with no progression data skip the disc entirely. Marks are front-face only (matching current behavior — no `addFaceDetailPair`).

**Result:** up to 22 child entities → 1 per plate.

---

### 2. Disable Tap Info Card for Bar Plates

**File:** `Features/Rewards/Views/BarbellRealityView.swift`

In the `onEnded` tap detection block, change one condition:

```swift
// Before
if tapped.components[PlateRoleComponent.self] != nil,
   tapped.name != "barHitZone",

// After
if let role = tapped.components[PlateRoleComponent.self], role.role != .bar,
   tapped.name != "barHitZone",
```

Floor plates and storage slot plates keep info card tap. Bar-racked plates do not. Mirror entities already have no `InputTargetComponent` so this guard only affects the right-side racked entity.

---

### 3. barHitZone — Left-Side Swipe Reliability

**File:** `Features/Rewards/Views/BarbellRealityView.swift`

Two changes to the `barHitZone` setup:

```swift
// Position: move to z=0 (coplanar with plates)
barHitZone.position = SIMD3(0, 0, 0)

// Collision: increase depth 0.05 -> 0.12
shapes: [ShapeResource.generateBox(size: SIMD3(1.6, 0.5, 0.12))]
```

The `.bar` gesture handler resolves which plate to unrack via `allRackedPlates.max(by:)` regardless of which entity was touched — correct unrack behavior is guaranteed no matter which entity wins the hit test. No handler changes needed.

---

### 4. Unrack Animation — Keep Plates In View

**File:** `Features/Rewards/Views/BarbellRealityView.swift`

In the `.bar` gesture handler:

```swift
// Before
let slideTargetX: Float = 0.78
let slideTargetZ: Float = 0.30

// After
let slideTargetX: Float = 0.48
let slideTargetZ: Float = 0.22
```

At x=0.48 the plate lands just past the outermost sleeve — visible on screen, clear of the racked slot area, and clear of the room wall. z=0.22 brings it slightly forward into the lower rack visual depth plane. Mirror slides symmetrically to −0.48. `snapToFloor` and `finishUnrack` run after the 200ms animation as before — no change to those paths.

---

## Files Changed

| File | Change |
|------|--------|
| `Features/Rewards/Views/BarbellEntityBuilder.swift` | Replace `addProgressionDetails` with `makeProgressionOverlayDisc` |
| `Features/Rewards/Views/BarbellRealityView.swift` | Tap guard (1 line), barHitZone position+size (2 lines), slideTarget values (2 lines) |

## Tests

**File:** `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

**Update** `plateRealismPassPreservesProgressionAndWeightLayers` (line 437): after the change, a fully progressed plate produces one child named `"progressionOverlayDisc"` instead of many mark entities. Update the test to assert:
```swift
#expect(entity.children.contains { $0.name == "progressionOverlayDisc" })
```
Remove the bare `entity.children.count >= 8` assertion (count changes with the new structure).

**Add** two new tests:

```swift
@Test func plateWithNoProgressionHasNoOverlayDisc() {
    let entity = makePlateEntity(tierID: 1, weightKg: 10)
    // Default projection (all zeros) skips the overlay entirely
    #expect(!entity.children.contains { $0.name == "progressionOverlayDisc" })
}

@Test func plateWithProgressionHasExactlyOneOverlayDisc() {
    let entity = makePlateEntity(
        tierID: 1,
        weightKg: 10,
        renderProjection: BarbellPlateRenderProjection(chalkUseCount: 8)
    )
    #expect(entity.children.filter { $0.name == "progressionOverlayDisc" }.count == 1)
}
```

Starter plates (tierID 7) skip progression details via the existing `tierID != 7` guard — no additional test needed.

---

## Out of Scope

- Visual appearance of progression marks (colors, layout, sizes match current)
- Physics, audio, or haptic changes
- Storage slot tap behavior
- `snapToFloor` / `finishUnrack` logic
