 Barbell — Unified RealityKit Scene Implementation Plan (Revised)

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


FULL TASK FILE 2026-04-02-barbell-realitykit-unified-scene.md
