# RealityKit Plate Readability Design

Date: 2026-05-05

## Problem

RealityKit barbell plates currently feel too dark and flat. The procedural geometry already has rings, lips, bosses, labels, progression marks, and PBR materials, but the final shot does not give those details enough light, contrast, or visual priority.

The goal is to make plates more pleasing and reward-like without changing reward rules, plate inventory, unlock tiers, or interaction behavior.

## Current Context

The main 3D plate path is built in `Features/Rewards/Views/BarbellEntityBuilder.swift` through `makePlateEntity`, style-specific builders, `PlateDisplaySurface`, and `PlateSidewallSurface`.

The scene path is built in `Features/Rewards/Views/BarbellRealityView.swift` through `RackRoomLightingPreset`, `RoomThemePreset`, camera proxy positioning, wall/floor geometry, bar/rack layout, storage slots, and the welcome/rack-room setup functions.

SwiftUI plate faces in `Features/Rewards/Views/PlateFaceView.swift` already communicate stronger depth through radial gradients, sheen, shadow, and clear face hierarchy. The RealityKit result should move closer to that perceived clarity while staying physically plausible.

## Design Goals

- Plates should read clearly against the room in dark gym, concrete room, and competition platform themes.
- Dark tiers such as Black Bumper and Cast Iron should appear charcoal and dimensional, not nearly black.
- Racked plates should become the visual subject of the rack room scene.
- Material changes should preserve each tier's identity: rubber stays rubber, cast iron stays rough, metallic tiers stay premium without becoming mirror-black.
- The implementation should stay within the existing procedural RealityKit pipeline and existing tests.

## Non-Goals

- No new plate tiers, reward rules, migrations, or catalog reshaping.
- No redesign of drag, rack, unrack, physics, storage, audio, or SwiftData behavior.
- No heavy asset pipeline change such as external USDZ authoring.
- No broad app-wide design-system changes.

## Recommended Approach

Do a focused lighting, material-readability, and composition pass.

### Lighting

Extend the existing rack-room lighting preset with a more intentional three-point read:

- A stronger camera-side key that hits plate faces.
- A soft fill that keeps dark materials from collapsing.
- A subtle rim or side wash to separate plate edges from the backdrop.
- Room-specific light warmth/coolness where useful, while keeping defaults neutral enough for all plate colors.

The existing image-based light should remain, but direct lights should carry readability so the scene does not depend on reflective tiers catching the HDRI at a lucky angle.

### Room Contrast

Keep the room dark, but add local contrast behind the plates:

- Add a subtle wall panel, plate-zone glow, or brighter backing strip behind the bar/storage area.
- Keep this as RealityKit geometry/material so it belongs to the scene.
- Avoid a flat SwiftUI overlay that would make the 3D scene feel composited.

The default dark gym theme should separate plates from the wall more clearly than it does now.

### Plate Materials

Refine `PlateDisplaySurface` and related helper materials:

- Lift dark face colors slightly and add more face-to-rim value contrast.
- Increase bevel/lip highlight strength where it improves shape.
- Keep rough materials rough, but make their base color readable.
- Reduce mirror dependency for high-metal tiers by keeping enough diffuse color and controlled roughness.

The desired result is stronger form, not universally brighter plates.

### Plate Face Hierarchy

Strengthen the RealityKit equivalents of the successful SwiftUI face layers:

- Outer rim should catch a visible highlight.
- Recessed face should be darker than raised geometry but not muddy.
- Center boss should separate cleanly from the bore.
- Weight/brand disc should remain readable from the rack-room camera distance.

Existing procedural geometry should be reused. Add or tune small material/position differences before adding new mesh complexity.

### Composition

Adjust rack-room camera and scene framing so racked plates feel like the subject:

- Slightly improve camera position/scale for rack room if it makes plates larger without breaking touch targets.
- Keep storage slots usable, but avoid making them visually compete with the loaded bar.
- Preserve existing mobile and regular-size-class behavior.

## Testing

Update or add focused tests around policy values rather than visual snapshots:

- Lighting preset maintains stronger camera-side/readability values.
- Dark material policy keeps Black Bumper and Cast Iron above minimum brightness.
- Premium metal policy remains colorful and not mirror-dependent.
- Room presets maintain enough contrast between plate-zone surfaces and dark plates.
- Camera/framing helper outputs remain within expected mobile and regular-size-class ranges.

Manual verification should include:

- Rack room with dark gym theme.
- Rack room with concrete and competition platform themes.
- Welcome barbell.
- Plate wall/editor preview paths that share `makePlateEntity`.
- Black Bumper, Cast Iron, Gold/Royal Gold, Diamond, and Competition tiers.

## Rollout

Implement as a single scoped visual pass:

1. Tune preset data and tests.
2. Tune material policy and tests.
3. Add plate-zone scene contrast.
4. Adjust camera/framing only if the first three changes are not enough.
5. Run the barbell test subset and manually inspect the RealityKit scenes on simulator/device.

If composition changes create interaction regressions, keep the lighting/material changes and defer framing.
