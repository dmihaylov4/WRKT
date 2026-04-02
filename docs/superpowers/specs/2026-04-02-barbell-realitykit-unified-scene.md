# Barbell — Unified RealityKit Scene

**Date:** 2026-04-02
**Status:** Approved, ready for implementation

## Problem

`BarbellWelcomeView` uses SceneKit with one `SCNView` per `SpinnablePlateCell` — one view per 3D object, which is architecturally incorrect. `PlateWallView` splits the barbell (RealityKit) from the plate collection (2D SwiftUI), making unified 3D interaction impossible. Both screens should operate as a single RealityKit scene where the scene owns runtime state and persistence is a side effect.

## Scope

Migrate `BarbellWelcomeView` and `PlateWallView` to a single shared `BarbellRealityView`. `BarbellPreviewView` (the cosmetic editor) is out of scope — it is a different screen with different purpose and already works correctly.

## Files

### New
- `Features/Rewards/Views/BarbellEntityBuilder.swift` — pure entity factory functions, no SwiftUI or state
- `Features/Rewards/Views/BarbellRealityView.swift` — single `RealityView` with two modes, all gesture handling, scene state

### Modified
- `Features/Rewards/Views/BarbellWelcomeView.swift` — remove all SceneKit code (`WelcomeBarbellView`, `SpinnablePlateCell`, `PlateState`, `BarbellWelcomeState`, `PlateSceneView`, `buildWelcomeBarbellScene`, `buildSCNPlate`, `buildPlateScene`, `pbrSCNMaterial`, `WelcomeLights`, `PlateUITextureCache`). Replace with `BarbellRealityView(mode: .welcome(plates:))` plus SwiftUI overlay.
- `Features/Profile/Views/PlateWallView.swift` — remove `BarbellPreviewView(mode: .showcase)` and 2D `ScrollView` plate grid. Replace with `BarbellRealityView(mode: .rackRoom(...))` plus SwiftUI overlay.

### Unchanged
- `Features/Rewards/Models/BarbellModels.swift`
- `Features/Rewards/Services/BarbellProgressService.swift`
- `Features/Profile/Views/BarbellPreviewView.swift`

## BarbellEntityBuilder

Pure free functions. No SwiftUI. No state. Shared by both modes.

```swift
func makePlateEntity(tierID: Int) -> ModelEntity
func makeBarEntity(skinID: Int) -> ModelEntity
func makeCollarEntity() -> ModelEntity
func makeRackStandEntity() -> ModelEntity
```

Uses `MeshResource.generateCylinder(height:radius:)` for all geometry. Materials use `PhysicallyBasedMaterial` with the same PBR values already defined in `PlateTier.all` and `BarSkin.all`. Texture loading via `TextureResource.load(named:)` using the same bundle files as the existing SceneKit implementation.

Each plate entity gets:
- `InputTargetComponent` — makes it eligible for `.targetedToAnyEntity()` gestures
- `CollisionComponent` with `ShapeResource.generateCylinder` — required for gesture hit testing
- `PlateRoleComponent` — custom component indicating `.floor` or `.bar`, used by gesture handlers to distinguish rack from unrack

Bar and rack stand entities get no `InputTargetComponent` — touches pass through to the plain `DragGesture` floor pan.

## BarbellRealityMode

```swift
enum BarbellRealityMode {
    case welcome(plates: [EarnedPlateInfo])
    case rackRoom(
        rackedPlates: [EarnedPlate],
        floorPlates: [EarnedPlate],
        onRack: (EarnedPlate) -> Void,
        onUnrack: (EarnedPlate) -> Void
    )
}
```

`onRack` and `onUnrack` callbacks are passed in by the parent. The scene never calls into SwiftData directly.

`SceneState` is created by the parent (`PlateWallView`) and passed into `BarbellRealityView` as an init parameter. This gives the parent a direct reference to the scene so it can call `sceneState.addPlate(info:)` when a new plate is earned — no callback registration, no reactive loop. `PlateWallView` detects new plates via `onChange(of: ownedPlates.count)`, finds the new `EarnedPlate`, and calls `sceneState.addPlate` directly.

## BarbellRealityView — Scene State

`SceneState` is a class (not a struct) so mutations do not trigger SwiftUI re-renders. All runtime 3D state lives here.

```swift
final class SceneState {
    var entityMap: [String: Entity] = [:]   // EarnedPlate.id -> Entity
    var floorAnchor = Entity()              // parent of all floor plate entities
    var barAnchor = Entity()                // parent of all bar plate entities
    var dragPhase: DragPhase = .idle
    var floorOffset: Float = 0             // current X translation of floorAnchor
    var floorVelocity: Float = 0           // for momentum on pan release
}

enum DragPhase {
    case idle
    case draggingPlate(Entity, plateID: String)
    case panningFloor
}
```

`@State private var scene = SceneState()` inside `BarbellRealityView`. Mutations to `SceneState` properties and to entity transforms happen directly — zero `@State` writes during gesture handling.

## BarbellRealityView — Scene Setup

`RealityView make { }` runs once:

1. Build bar, collar, rack stand entities via `BarbellEntityBuilder` and add to scene
2. For each plate in the initial array: call `makePlateEntity`, assign a stable name matching `EarnedPlate.id`, add to `floorAnchor` or `barAnchor` based on `isRacked`, store reference in `entityMap`
3. For `.welcome` mode: start per-entity spin animations via `entity.playAnimation` with repeating rotation around Y; position plate entities in a grid layout below the hero barbell

`RealityView update { }` is empty. The scene manages its own state after `make`.

## Gesture Handling

Two gestures on the `RealityView`, coexisting without conflict:

### DragGesture().targetedToAnyEntity() — plate interaction

RealityKit resolves which entity was touched. No manual hit testing.

**Rack (floor plate → bar):**
- `.onChanged`: set `dragPhase = .draggingPlate(entity, plateID)`, move entity position to follow finger in world space using `value.convert(value.location3D, from: .local, to: .scene)`
- `.onEnded`: check entity's world Y position against bar zone threshold
  - In bar zone: `snapToBar()` animation, reparent entity from `floorAnchor` to `barAnchor`, call `onRack(plate)` callback (persistence side effect)
  - Outside bar zone: `snapBack()` animation to original floor position

**Unrack (bar plate → floor):**
- `.onChanged`: detect swipe direction via `value.translation.width`; once `|dx| > threshold`, animate plate sliding off its bar end; transition to floor drag phase, entity follows finger
- `.onEnded`: check entity world Y position against floor zone threshold
  - In floor zone: entity lands on floor, reparent to `floorAnchor`, call `onUnrack(plate)` callback
  - Above floor zone: `snapBack()` animation to original bar position

Entity type distinguished by `entity.components[PlateRoleComponent.self]?.role`.

### DragGesture() — floor pan

Fires only when touch does not start on an entity (natural RealityKit exclusion).

- `.onChanged`: set `dragPhase = .panningFloor`, `floorAnchor.position.x += delta`, clamp to `[minFloorX, maxFloorX]`, track `floorVelocity`
- `.onEnded`: apply momentum — `floorVelocity` decays per frame via a `Task` loop, `floorAnchor.position.x` updates each frame until velocity drops below threshold

## Data Flow

```
INITIAL LOAD
Parent @Query (PlateWallView / BarbellWelcomeView)
  -> passes [EarnedPlate] as init parameters to BarbellRealityView
  -> RealityView make { } builds entityMap, scene is ready
  -> @Query responsibility ends here for normal operation

DURING GESTURE (60fps)
Finger moves
  -> SceneState.dragPhase updated
  -> entity.position / entity.transform mutated directly
  -> no SwiftData, no @State, no SwiftUI

ON ACTION COMPLETE
Gesture ends (rack or unrack confirmed)
  -> onRack(plate) or onUnrack(plate) callback fires
  -> parent calls BarbellProgressService.shared.rackPlate() / unrackPlate()
  -> SwiftData write — persistence side effect only
  -> does not drive any visual update, scene already reflects correct state

EXTERNAL CHANGE (new plate earned mid-session)
BarbellProgressService earns a plate
  -> PlateWallView onChange(of: ownedPlates.count) detects new entry
  -> PlateWallView calls sceneState.addPlate(info:) directly (it owns the reference)
  -> sceneState.addPlate creates entity, adds to floorAnchor, updates entityMap
  -> no callback registration, no update closure, no reactive diff
```

## .welcome Mode Layout

- Hero barbell: bar + collar + 2 starter plates at center, auto-spin at 0.35 rad/s with momentum decay on drag
- Plate grid: entities arranged in rows of 4 below the barbell, each spinning independently at randomised initial velocity
- Drag on plate entity: updates that entity's spin velocity from gesture delta (same mechanic as current `SpinnablePlateCell`)
- SwiftUI ZStack overlay above `RealityView`: title text, plate count, "Build Your Rack" button, dismiss

## .rackRoom Mode Layout

- Two rack stand entities flanking the bar at ±0.55 on X
- Bar + collars at Y = 0.6 (elevated, resting on stands)
- Racked plate entities as children of `barAnchor`, bilateral pairs at slot offsets matching current `buildWelcomeBarbellScene` values
- Floor line at Y = 0 (rack base)
- Floor plate entities as children of `floorAnchor`, leaning at randomised angles (-6 to -13 degrees) spaced evenly on X
- Camera: fixed, positioned at (0, 0.4, 1.8), looking toward origin, ~42 degree FOV — frames bar + floor without cropping
- SwiftUI ZStack overlay: Done button, "Your Barbell" title, weight label (Bar 20kg + Xkg = Ykg total)

## What Does Not Change

- `BarbellProgressService.rackPlate()` / `unrackPlate()` — called exactly as today, from gesture callbacks
- `EarnedPlate`, `BarbellConfig`, `EarnedPlateInfo` — untouched
- `BarbellPreviewView` — untouched
- Supabase sync in `BarbellProgressService` — untouched
- Clink haptic on rack — called from the `onRack` callback path as today
