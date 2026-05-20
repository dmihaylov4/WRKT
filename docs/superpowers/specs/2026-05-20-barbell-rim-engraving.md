# Barbell Rim Engraving

**Date:** 2026-05-20
**Scope:** Move all plate engraving text from the center face disc to the outer rim, rendered as arc text with a black metallic PBR material.

---

## Problem

`makeEngravingDisc` renders engraving text (e.g. "Personal Record", "15 Workouts", "Squat") as an arc overlay on the center face disc. This overlaps the weight number and the "VOLIA" arc text, producing a cluttered center. The text should instead follow the curve of the raised outer rim — the dark ring at the plate edge — where it has space to breathe and reads as a premium stamped-metal detail.

---

## Changes

### 1. Text Normalization

**File:** `Features/Rewards/Views/BarbellEntityBuilder.swift`

Add a pure function alongside the other engraving helpers:

```swift
func normalizedRimEngravingText(_ text: String) -> String
```

Rules:
- `"Personal Record"` → `"PR"`
- Any string matching `"N Workouts"` → `"N WORKOUTS"` (e.g. `"15 Workouts"` → `"15 WORKOUTS"`)
- Everything else: `.uppercased()` as-is (`"Squat"` → `"SQUAT"`, `"Bench Press"` → `"BENCH PRESS"`, `"90-Day Streak"` → `"90-DAY STREAK"`)

Called once inside `makeEngravingDisc` before passing text to the renderer. `engravingText` on `EarnedPlate` and all call sites are unchanged.

---

### 2. Disc Geometry and Arc Position

**File:** `Features/Rewards/Views/BarbellEntityBuilder.swift`

**Disc mesh:** extend outer radius from the current ~0.127m cap to `profile.rimOuterRadius`:

```swift
// Before
let outerRadius = min(profile.faceOuterRadius * 0.72,
                      Float(layout.markingRadiusRatio) * profile.outerRadius)
let disc = ModelEntity(
    mesh: cachedPlateRing(height: 0.001,
                          outerRadius: outerRadius,
                          innerRadius: plateBoreRadius), ...)

// After
let disc = ModelEntity(
    mesh: cachedPlateRing(height: 0.001,
                          outerRadius: profile.rimOuterRadius,
                          innerRadius: plateBoreRadius), ...)
```

The disc is transparent everywhere except at the arc text, so the larger mesh costs no visible overdraw — only the text pixels are opaque.

**Arc radius in canvas:** the existing CoreGraphics arc-drawing code uses a pixel radius derived from a layout ratio. Update it to target the rim midpoint:

```swift
let rimMidRadius = (profile.rimOuterRadius + profile.rimInnerRadius) / 2
let arcRadius = (rimMidRadius / profile.outerRadius) * (canvasSize / 2)
```

Text follows the curvature of the rim at its midpoint. The arc spans the same angle range as the current engraving arcs — no change to arc sweep or character spacing.

**Position:** raise the disc to clear the raised outer rim face (rim top is at `profile.thickness * 0.5 + 0.003`):

```swift
// Before
disc.position = SIMD3(0, profile.thickness * 0.5 + 0.013, 0)

// After
disc.position = SIMD3(0, profile.thickness * 0.5 + 0.004, 0)
```

`addFaceDetailPair` is unchanged — arc text appears on both front and back faces.

---

### 3. Material — Black Metallic PBR

**File:** `Features/Rewards/Views/BarbellEntityBuilder.swift`

Replace the ShaderGraph/Unlit engraving material path in `makeEngravingDiscMaterial` with a `PhysicallyBasedMaterial`:

```swift
var mat = PhysicallyBasedMaterial()
mat.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1.0))
mat.metallic  = .init(floatLiteral: 0.72)
mat.roughness = .init(floatLiteral: 0.18)
mat.clearcoat = .init(floatLiteral: 0.45)
mat.clearcoatRoughness = .init(floatLiteral: 0.12)
mat.blending  = .transparent(opacity: .init(texture: .init(maskTex)))
```

`maskTex` is the existing greyscale text render: white pixels where text is drawn (opaque dark metallic), black everywhere else (transparent). This replaces both the ShaderGraph template path and the `makeEngravingDiscUnlitFallback` path — both are removed.

**Result:** near-black text with sharp IBL specular highlights and clearcoat gloss — the appearance of text stamped into dark metal. The material is cached in `_engravingDiscMaterialCache` keyed on `normalizedText` only — the PBR properties (metallic, roughness, clearcoat, base color) are identical across all tiers; only the opacity mask texture varies, and that depends solely on the text string. This allows the same "PR" material to be shared across every tier that produces a PR plate.

---

## Files Changed

| File | Change |
|------|--------|
| `Features/Rewards/Views/BarbellEntityBuilder.swift` | Add `normalizedRimEngravingText`; update disc mesh radius, arc radius, position, and material in `makeEngravingDisc` / `makeEngravingDiscMaterial`; remove ShaderGraph and Unlit fallback paths |

---

## Tests

**File:** `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

```swift
@Test func rimEngravingNormalizesPersonalRecord() {
    #expect(normalizedRimEngravingText("Personal Record") == "PR")
}

@Test func rimEngravingNormalizesWorkoutMilestones() {
    #expect(normalizedRimEngravingText("5 Workouts") == "5 WORKOUTS")
    #expect(normalizedRimEngravingText("15 Workouts") == "15 WORKOUTS")
    #expect(normalizedRimEngravingText("100 Workouts") == "100 WORKOUTS")
}

@Test func rimEngravingUppercasesOtherTypes() {
    #expect(normalizedRimEngravingText("Squat") == "SQUAT")
    #expect(normalizedRimEngravingText("Bench Press") == "BENCH PRESS")
    #expect(normalizedRimEngravingText("90-Day Streak") == "90-DAY STREAK")
}

@Test func engravingDiscPositionedAboveRimFace() throws {
    let tier = try #require(PlateTier.all.first { $0.id == 4 })
    let profile = PlateVisualDesign.profile(for: tier.style)
    let entity = makePlateEntity(
        tierID: 4, weightKg: 20,
        engravingText: "Personal Record",
        showEngravings: true
    )
    let disc = try #require(entity.children.first { $0.name == "engravingDisc" })
    #expect(disc.position.y >= profile.thickness * 0.5 + 0.003)
}
```

---

## Dead Code to Remove

Removing the ShaderGraph path makes the following dead — the implementation plan should clean them up:

- `nonisolated(unsafe) var plateMaterialTemplate: ShaderGraphMaterial?`
- `func preloadPlateMaterialTemplate() async`
- `func loadPlateMaterial(tier:engravingText:prominent:) async throws`
- Call sites in `BarbellRealityView.swift` (`.task {}` preload block) and `BarbellPreviewView.swift` (preload in scene setup)

---

## Out of Scope

- `engravingText` values stored on `EarnedPlate` — unchanged
- Call sites passing `engravingText` into `makePlateEntity` — unchanged
- Arc sweep angle and character spacing — unchanged from current
- `prominentEngraving` parameter — kept but its size effect now applies at the rim radius
