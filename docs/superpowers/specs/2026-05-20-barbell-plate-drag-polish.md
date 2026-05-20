# Barbell Plate Drag Polish

**Date:** 2026-05-20
**Scope:** Four targeted fixes to the rack room plate interaction — performance, tap UX, gesture coverage, and animation bounds.

---

## Problem

1. **Lag when pulling plates fast**: `addProgressionDetails` calls `pbrMaterial(...)` fresh on every plate build, producing unique `PhysicallyBasedMaterial` instances per plate. RealityKit cannot batch draw calls across entities that hold distinct material instances. With multiple plates animating simultaneously each plate's marks cost independent draw calls, causing GPU stutter.
2. **Bar plates show info card on tap**: tapping a racked plate triggers the detail info card, which is disruptive during gameplay.
3. **Left-side swipe unreliable**: `barHitZone` exists to handle left-side unrack gestures but sits at z=−0.05 with a 0.05m deep collision box — touch rays at slight angles miss it.
4. **Unrack animation exits view**: `slideTargetX = 0.78` places the plate at the room wall edge, which exits the visible camera frustum before the 200ms animation ends.

---

## Changes

### 1. Progression Mark Material Caching

**File:** `Features/Rewards/Views/BarbellEntityBuilder.swift`

**Root cause:** `addProgressionDetails` creates fresh `PhysicallyBasedMaterial` instances on every call — one per mark type per plate build. Four plates on the bar = four distinct chalk materials, four distinct wear materials, etc. RealityKit batches draw calls only across entities that share the same material resource. Unique instances prevent batching.

**Fix:** Add a process-level material cache alongside the existing `_weightDiscMaterialCache` and `_engravingDiscMaterialCache`:

```swift
nonisolated(unsafe) var _progressionMarkMaterialCache: [String: PhysicallyBasedMaterial] = [:]
```

Cache keys and their corresponding materials:

| Key | Material |
|-----|----------|
| `"chalk"` | `pbrMaterial(color: UIColor(white: 0.88, alpha: 0.72), metallic: 0, roughness: 0.96)` |
| `"wear"` | `pbrMaterial(color: UIColor(white: 0.10, alpha: 0.55), metallic: 0.15, roughness: 0.82)` |
| `"polish"` | `pbrMaterial(color: UIColor(white: 1.0, alpha: 0.42), metallic: 1, roughness: 0.18)` |
| `"tierRing_<tierName>_<index>"` | Ring material with `tierAccentColor`, metallic, roughness, clearcoat per tier+index |

`addProgressionDetails` is otherwise unchanged in structure — same entity count, same positions, same PBR values. Only the material creation path changes: look up the cache key, create and store on miss, reuse on hit.

Also name each mark entity so tests can filter them:
- Chalk marks: `mark.name = "chalkMark"`
- Wear marks: `mark.name = "wearMark"`
- Polish marks: `mark.name = "polishMark"`
- Tier rings: `ring.name = "tierRing_\(index)"`

**Result:** All chalk marks across all plates share one `PhysicallyBasedMaterial` instance, all wear marks share one, all polish marks share one, tier rings share per-tier-per-index. RealityKit batches these into a small number of draw calls regardless of how many plates are on screen. No visual change — same PBR metallic, roughness, clearcoat properties on every mark.

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
| `Features/Rewards/Views/BarbellEntityBuilder.swift` | Add `_progressionMarkMaterialCache`; update `addProgressionDetails` to use it; name mark entities |
| `Features/Rewards/Views/BarbellRealityView.swift` | Tap guard (1 line), barHitZone position+size (2 lines), slideTarget values (2 lines) |

---

## Tests

**File:** `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

**Keep unchanged:** `plateRealismPassPreservesProgressionAndWeightLayers` (line 437) — entity count and PBR components are identical after the refactor, so `children.count >= 8` and the component assertions still hold.

**Add** one new test verifying mark counts match the projection and named entities are present (relies on the naming added to `addProgressionDetails`):

```swift
@Test func progressionMarksRespectProjectionCounts() {
    // chalkUseCount 16 -> chalkMarkCount 4, gripWearCount 10 -> 2, pressUseCount 12 -> 2
    let projection = BarbellPlateRenderProjection(
        progressionTier: .gold,
        chalkUseCount: 16,
        gripWearCount: 10,
        pressUseCount: 12
    )
    let entity = makePlateEntity(tierID: 1, weightKg: 10, renderProjection: projection)
    #expect(entity.children.filter { $0.name == "chalkMark" }.count == projection.chalkMarkCount)
    #expect(entity.children.filter { $0.name == "wearMark" }.count == projection.gripWearMarkCount)
    #expect(entity.children.filter { $0.name == "polishMark" }.count == projection.pressPolishMarkCount)
    #expect(entity.children.filter { $0.name.hasPrefix("tierRing") }.count == projection.tierRingCount)
}
```

---

## Out of Scope

- Visual appearance of progression marks — colors, layout, sizes, and PBR properties are unchanged
- Physics, audio, or haptic changes
- Storage slot tap behavior
- `snapToFloor` / `finishUnrack` logic
