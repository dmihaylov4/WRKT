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

Right-side racked plates have their own `CollisionComponent` and remain the preferred hit target for right-side touches. The gesture handler already resolves which plate to unrack via `allRackedPlates.max(by:)` regardless of which entity was touched — no handler changes needed.

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

## Out of Scope

- Visual appearance of progression marks (colors, layout, sizes match current)
- Physics, audio, or haptic changes
- Storage slot tap behavior
- `snapToFloor` / `finishUnrack` logic
