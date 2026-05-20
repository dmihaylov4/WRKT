# Barbell Plate Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix plate drag lag, rim engraving quality, info card graininess, and several UX issues in the barbell rack room.

**Architecture:** Eight independent tasks touching two existing files (`BarbellEntityBuilder.swift`, `BarbellRealityView.swift`) and one new file (`PlateInfoCardView.swift`). Tasks 1–2 are fully independent; Tasks 3–6 build the rim engraving pipeline sequentially; Tasks 7–8 replace the 3D info card with a SwiftUI overlay.

**Tech Stack:** RealityKit, SwiftUI, UIKit CoreGraphics, Swift Testing, PhysicallyBasedMaterial, DS design tokens

---

## File Map

| File | Role |
|------|------|
| `Features/Rewards/Views/BarbellEntityBuilder.swift` | Add progression mark material cache; rewrite engraving disc renderer and material; delete 3D info card functions |
| `Features/Rewards/Views/BarbellRealityView.swift` | Fix barHitZone, tap guard, slide target; wire SwiftUI overlay; delete 3D card show/dismiss entity code |
| `Features/Rewards/Views/PlateInfoCardView.swift` | New — native SwiftUI info card |
| `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift` | New tests for mark naming, text normalization, disc position |

---

## Task 1: Progression Mark Material Caching

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Test: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

**Context:** `addProgressionDetails` (line ~1588) creates a fresh `pbrMaterial(...)` call for every plate built. Four plates on the bar = four distinct chalk materials — RealityKit cannot batch their draw calls. Fix: cache materials at process level, keyed by mark type and tier. Entity count and PBR values are unchanged; only the material creation path changes.

- [ ] **Step 1: Write the failing test**

Open `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift` and add:

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

- [ ] **Step 2: Run the test — verify it fails**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests/progressionMarksRespectProjectionCounts 2>&1 | grep -E "passed|failed|error"
```

Expected: FAIL — mark entities have no `.name` set yet, all filter results are 0.

- [ ] **Step 3: Add the cache declaration**

In `Features/Rewards/Views/BarbellEntityBuilder.swift`, find the block at line ~1114 where `_weightDiscMaterialCache` and `_engravingDiscMaterialCache` are declared. Add immediately after them:

```swift
private nonisolated(unsafe) var _progressionMarkMaterialCache: [String: PhysicallyBasedMaterial] = [:]
```

- [ ] **Step 4: Rewrite `addProgressionDetails` to use the cache and name entities**

Find `private func addProgressionDetails(to entity: ModelEntity, projection: BarbellPlateRenderProjection, plateThickness: Float)` and replace its body with:

```swift
    guard projection != BarbellPlateRenderProjection() else { return }

    let faceY = plateThickness * 0.5 + 0.004

    // Tier rings
    for index in 0..<projection.tierRingCount {
        let outerRadius = Float(0.198 - Double(index) * 0.020)
        let innerRadius = max(plateBoreRadius + 0.010, outerRadius - 0.004)
        let alpha = CGFloat(0.92 - Double(index) * 0.14)
        let ringKey = "tierRing_\(projection.progressionTier.rawValue)_\(index)"
        let mat: PhysicallyBasedMaterial
        if let cached = _progressionMarkMaterialCache[ringKey] {
            mat = cached
        } else {
            let built = pbrMaterial(
                color: projection.tierAccentColor.withAlphaComponent(alpha),
                metallic: projection.progressionTier == .iron ? 0.25 : 0.9,
                roughness: projection.progressionTier == .gold ? 0.18 : 0.26,
                clearcoat: projection.progressionTier.rank >= BarbellPlateProgressionTier.chrome.rank ? 0.35 : 0
            )
            _progressionMarkMaterialCache[ringKey] = built
            mat = built
        }
        let ring = ModelEntity(
            mesh: cachedPlateRing(height: 0.001, outerRadius: outerRadius, innerRadius: innerRadius),
            materials: [mat]
        )
        ring.name = "tierRing_\(index)"
        ring.position.y = faceY + Float(index) * 0.0002
        entity.addChild(ring)
    }

    // Chalk marks
    let chalkMat: PhysicallyBasedMaterial
    if let cached = _progressionMarkMaterialCache["chalk"] {
        chalkMat = cached
    } else {
        let built = pbrMaterial(color: UIColor(white: 0.88, alpha: 0.72), metallic: 0, roughness: 0.96)
        _progressionMarkMaterialCache["chalk"] = built
        chalkMat = built
    }
    for index in 0..<projection.chalkMarkCount {
        let angle = Float(index) * 1.37
        let radius = Float(0.105 + 0.012 * Float(index % 3))
        let mark = ModelEntity(mesh: cachedBox(size: SIMD3(0.028, 0.0015, 0.006)), materials: [chalkMat])
        mark.name = "chalkMark"
        mark.position = SIMD3(cos(angle) * radius, faceY + 0.002, sin(angle) * radius)
        mark.orientation = simd_quatf(angle: angle + .pi / 5, axis: SIMD3(0, 1, 0))
        entity.addChild(mark)
    }

    // Wear marks
    let wearMat: PhysicallyBasedMaterial
    if let cached = _progressionMarkMaterialCache["wear"] {
        wearMat = cached
    } else {
        let built = pbrMaterial(color: UIColor(white: 0.10, alpha: 0.55), metallic: 0.15, roughness: 0.82)
        _progressionMarkMaterialCache["wear"] = built
        wearMat = built
    }
    for index in 0..<projection.gripWearMarkCount {
        let angle = Float(index) * 1.05 + 0.32
        let mark = ModelEntity(mesh: cachedBox(size: SIMD3(0.040, 0.0018, 0.004)), materials: [wearMat])
        mark.name = "wearMark"
        mark.position = SIMD3(cos(angle) * 0.168, faceY + 0.003, sin(angle) * 0.168)
        mark.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        entity.addChild(mark)
    }

    // Polish marks
    let polishMat: PhysicallyBasedMaterial
    if let cached = _progressionMarkMaterialCache["polish"] {
        polishMat = cached
    } else {
        let built = pbrMaterial(color: UIColor(white: 1.0, alpha: 0.42), metallic: 1, roughness: 0.18)
        _progressionMarkMaterialCache["polish"] = built
        polishMat = built
    }
    for index in 0..<projection.pressPolishMarkCount {
        let angle = Float(index) * 1.23 + 0.74
        let mark = ModelEntity(mesh: cachedBox(size: SIMD3(0.018, 0.0015, 0.018)), materials: [polishMat])
        mark.name = "polishMark"
        mark.position = SIMD3(cos(angle) * 0.075, faceY + 0.004, sin(angle) * 0.075)
        mark.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        entity.addChild(mark)
    }
```

- [ ] **Step 5: Run the test — verify it passes**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests/progressionMarksRespectProjectionCounts 2>&1 | grep -E "passed|failed|error"
```

Expected: PASS

- [ ] **Step 6: Manual performance validation**

This optimization targets GPU draw call batching — unit tests cannot verify it. After the build succeeds, open the rack room on a physical device (not simulator):

1. Earn or add 4 pairs of plates of the same tier (e.g., all cast iron) to the barbell
2. Rapidly swipe-unrack multiple pairs in quick succession
3. Drag floor plates around at speed

Expected: no visible stutter or frame drops during simultaneous plate animations. If there is still noticeable lag, check that `_progressionMarkMaterialCache` is actually being hit (add a `#if DEBUG print(...)` temporarily) and that plates are not being rebuilt from scratch on each rack/unrack cycle.

- [ ] **Step 7: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "perf(barbell): cache progression mark materials for GPU draw call batching"
```

---

## Task 2: barHitZone Reliability, Tap Guard, Slide Target

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`

**Context:** Three small, independent changes to `BarbellRealityView.swift`. (1) `barHitZone` sits at z=−0.05 with a 0.05m deep box — touch rays at angles miss it. (2) Tapping a racked plate incorrectly opens the info card. (3) `slideTargetX = 0.78` exits the visible camera frustum.

- [ ] **Step 1: Fix barHitZone position and collision box**

Find the barHitZone setup block (search for `barHitZone.name = "barHitZone"`). Change:

```swift
// Before
barHitZone.components.set(CollisionComponent(
    shapes: [ShapeResource.generateBox(size: SIMD3(1.6, 0.5, 0.05))],
    filter: barHitZoneCollisionFilter
))
barHitZone.position = SIMD3(0, 0, -0.05)

// After
barHitZone.components.set(CollisionComponent(
    shapes: [ShapeResource.generateBox(size: SIMD3(1.6, 0.5, 0.12))],
    filter: barHitZoneCollisionFilter
))
barHitZone.position = SIMD3(0, 0, 0)
```

- [ ] **Step 2: Fix the tap-to-info-card guard**

Find the `onEnded` tap detection block (search for `if tapped.components[PlateRoleComponent.self] != nil`). Change:

```swift
// Before
if tapped.components[PlateRoleComponent.self] != nil,
   tapped.name != "barHitZone",

// After
if let role = tapped.components[PlateRoleComponent.self], role.role != .bar,
   tapped.name != "barHitZone",
```

- [ ] **Step 3: Fix slide target values**

Find `let slideTargetX: Float = 0.78` in the `.bar` gesture case. Change both values:

```swift
// Before
let slideTargetX: Float = 0.78
let slideTargetZ: Float = 0.30

// After
let slideTargetX: Float = 0.48
let slideTargetZ: Float = 0.22
```

- [ ] **Step 4: Build and verify**

```
xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift
git commit -m "fix(barbell): barHitZone depth, disable tap card on bar plates, slide target in view"
```

---

## Task 3: Text Normalization for Rim Engraving

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Test: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

**Context:** `engravingText` values like `"Personal Record"` and `"15 Workouts"` need to be abbreviated/formatted before rendering on the narrow rim. This is a pure function with no side effects.

- [ ] **Step 1: Write the failing tests**

Add to `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`:

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
```

- [ ] **Step 2: Run tests — verify they fail**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests/rimEngravingNormalizesPersonalRecord 2>&1 | grep -E "passed|failed|error"
```

Expected: FAIL — `normalizedRimEngravingText` not defined.

- [ ] **Step 3: Implement the function**

Add to `Features/Rewards/Views/BarbellEntityBuilder.swift` in the `// MARK: - Engraving disc` section, before `makeEngravingDisc`:

```swift
func normalizedRimEngravingText(_ text: String) -> String {
    if text == "Personal Record" { return "PR" }
    // "15 Workouts" -> "15 WORKOUTS"
    let parts = text.split(separator: " ", maxSplits: 1)
    if parts.count == 2,
       Int(parts[0]) != nil,
       parts[1].lowercased() == "workouts" {
        return "\(parts[0]) WORKOUTS"
    }
    return text.uppercased()
}
```

- [ ] **Step 4: Run tests — verify they pass**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests 2>&1 | grep -E "passed|failed|error"
```

Expected: all three new tests PASS, existing tests unaffected.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat(barbell): normalizedRimEngravingText — PR and workout milestone abbreviation"
```

---

## Task 4: Rim Engraving Disc Geometry and Arc Position

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Test: `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`

**Context:** `makeEngravingDisc` creates a small disc (~0.127m outer radius) centered on the inner face. Change it to a full-face disc reaching the outer rim, and update the text arc radius so the text follows the rim curve at its midpoint.

- [ ] **Step 1: Write the failing test**

Add to `WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift`:

```swift
@Test func engravingDiscPositionedAboveRimFace() throws {
    let tier = try #require(PlateTier.all.first { $0.id == 4 })
    let profile = PlateVisualDesign.profile(for: tier.style)
    let entity = makePlateEntity(
        tierID: 4, weightKg: 20,
        engravingText: "Personal Record",
        showEngravings: true
    )
    let disc = try #require(entity.children.first { $0.name == "engravingDisc" })
    // Must clear rim face (+0.003), weight disc (+0.010), and progression marks (up to +0.012)
    #expect(disc.position.y >= profile.thickness * 0.5 + 0.015)
}
```

- [ ] **Step 2: Run test — check current state**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests/engravingDiscPositionedAboveRimFace 2>&1 | grep -E "passed|failed|error"
```

The current disc position is `profile.thickness * 0.5 + 0.013` which may pass already — note the result. The actual fix matters for the arc radius, not just position.

- [ ] **Step 3: Update `makeEngravingDisc`**

Find `private func makeEngravingDisc(engravingText: String, tier: PlateTier, prominent: Bool) -> ModelEntity`. Replace its full body with:

```swift
    let profile = PlateVisualDesign.profile(for: tier.style)
    let normalizedText = normalizedRimEngravingText(engravingText)
    // Key includes tier.id (determines rim radii via style) and prominent (affects font size).
    // Same text on bumper vs cast iron has different arc radius — wrong key = wrong geometry.
    let cacheKey = "\(normalizedText)_\(tier.id)_\(prominent)"
    let material: any RealityKit.Material
    if let cached = _engravingDiscMaterialCache[cacheKey] {
        material = cached
    } else {
        // Still calls old signature — Task 5 updates both this call and the function body together.
        let built = makeEngravingDiscMaterial(engravingText: normalizedText, tier: tier, prominent: prominent)
        _engravingDiscMaterialCache[cacheKey] = built
        material = built
    }
    let disc = ModelEntity(
        mesh: cachedPlateRing(height: 0.001,
                              outerRadius: profile.rimOuterRadius,
                              innerRadius: plateBoreRadius),
        materials: [material]
    )
    disc.name = "engravingDisc"
    // +0.016 clears the raised rim face (+0.003), weight disc (+0.010), and
    // all progression marks (highest polish mark at faceY+0.008 = thickness*0.5+0.012).
    disc.position = SIMD3(0, profile.thickness * 0.5 + 0.016, 0)
    return disc
```

- [ ] **Step 4: Run test — verify it passes**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests/engravingDiscPositionedAboveRimFace 2>&1 | grep -E "passed|failed|error"
```

Expected: PASS

- [ ] **Step 5: Build to confirm no compile errors**

```
xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected: BUILD SUCCEEDED — Task 4 still uses the old `makeEngravingDiscMaterial` signature so the build is clean.

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift WRKTTests/FeaturesTests/Barbell/BarbellEntityBuilderTests.swift
git commit -m "feat(barbell): engraving disc spans rim band, arc text at rim midpoint radius"
```

---

## Task 5: Engraving Disc Material — Black Metallic PBR Arc Text

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`

**Context:** Replace `makeEngravingDiscMaterial` (which branches between ShaderGraph and Unlit fallback) with a single `PhysicallyBasedMaterial` that renders the text as an arc using `drawArcText`, uses the white render as an opacity mask, and applies dark metallic PBR properties. The `prominent` parameter adjusts font size.

- [ ] **Step 1: Update the call site in `makeEngravingDisc`**

In the body of `makeEngravingDisc` that was updated in Task 4, find:

```swift
        let built = makeEngravingDiscMaterial(engravingText: normalizedText, tier: tier, prominent: prominent)
```

Change to:

```swift
        let built = makeEngravingDiscMaterial(normalizedText: normalizedText, profile: profile, prominent: prominent)
        // cacheKey already includes tier.id and prominent — same text on different styles stays separate
```

- [ ] **Step 2: Replace `makeEngravingDiscMaterial`**

Find `private func makeEngravingDiscMaterial(engravingText: String, tier: PlateTier, prominent: Bool) -> any RealityKit.Material`. Replace the entire function with:

```swift
private func makeEngravingDiscMaterial(normalizedText: String, profile: PlateVisualProfile, prominent: Bool) -> any RealityKit.Material {
    let canvasSize: CGFloat = 512
    let half = canvasSize / 2
    let rimMidRadius = CGFloat((profile.rimOuterRadius + profile.rimInnerRadius) / 2)
    let arcRadius = rimMidRadius / CGFloat(profile.outerRadius) * half
    let fontSize = prominent ? canvasSize * 0.09 : canvasSize * 0.065
    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: fontSize, weight: prominent ? .black : .bold),
        .foregroundColor: UIColor.white
    ]

    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasSize, height: canvasSize), format: format)
    let image = renderer.image { _ in
        drawArcText(
            normalizedText,
            center: CGPoint(x: half, y: half),
            radius: arcRadius,
            startAngle: -.pi * 0.82,
            endAngle: -.pi * 0.18,
            attributes: textAttrs,
            outward: true
        )
    }

    var mat = PhysicallyBasedMaterial()
    mat.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1.0))
    mat.metallic = .init(floatLiteral: 0.72)
    mat.roughness = .init(floatLiteral: 0.18)
    mat.clearcoat = .init(floatLiteral: 0.45)
    mat.clearcoatRoughness = .init(floatLiteral: 0.12)
    if let cg = image.cgImage,
       let maskTex = try? TextureResource.generate(from: cg, options: .init(semantic: .raw)) {
        mat.blending = .transparent(opacity: .init(texture: .init(maskTex)))
    }
    return mat
}
```

- [ ] **Step 3: Delete `makeEngravingDiscUnlitFallback`**

Find and delete the entire `private func makeEngravingDiscUnlitFallback(engravingText: String, tier: PlateTier, prominent: Bool) -> UnlitMaterial` function (lines ~1390–1438).

- [ ] **Step 4: Build and verify**

```
xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected: BUILD SUCCEEDED. If there are references to `makeEngravingDiscUnlitFallback` elsewhere, delete them.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift
git commit -m "feat(barbell): rim engraving uses black metallic PBR arc text"
```

---

## Task 6: Dead Code Cleanup — ShaderGraph Engraving Paths

**Files:**
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`
- Modify: `Features/Profile/Views/BarbellPreviewView.swift`
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift`
- Modify: `Features/Rewards/Views/BarbellMomentView.swift`

**Context:** The ShaderGraph engraving path (`plateMaterialTemplate`, `preloadPlateMaterialTemplate`, `loadPlateMaterial`) is now dead — `makeEngravingDiscMaterial` no longer reads `plateMaterialTemplate`. Remove all of it. The function is called from three view files; all call sites must be removed before deleting the declaration or the build fails.

- [ ] **Step 1: Remove all preload call sites first**

Before deleting the function, remove every call to it — otherwise the build fails mid-cleanup.

In `Features/Profile/Views/BarbellPreviewView.swift` (line ~351), delete:
```swift
await preloadPlateMaterialTemplate()
```

In `Features/Rewards/Views/BarbellWelcomeView.swift` (line ~99), delete:
```swift
await preloadPlateMaterialTemplate()
```

In `Features/Rewards/Views/BarbellMomentView.swift` (line ~82), delete:
```swift
await preloadPlateMaterialTemplate()
```

Confirm no remaining call sites:
```
grep -rn "preloadPlateMaterialTemplate\|plateMaterialTemplate\|loadPlateMaterial" /Users/dimitarmihaylov/dev/WRKT --include="*.swift" | grep -v "BarbellEntityBuilder"
```

Expected: no output.

- [ ] **Step 2: Delete dead declarations from BarbellEntityBuilder**

In `Features/Rewards/Views/BarbellEntityBuilder.swift`, find and delete:

1. `nonisolated(unsafe) var plateMaterialTemplate: ShaderGraphMaterial? = nil` (line ~1117)
2. The entire `func preloadPlateMaterialTemplate() async { ... }` function (line ~1209)
3. The entire `func loadPlateMaterial(tier:engravingText:prominent:) async throws -> ShaderGraphMaterial { ... }` function (line ~1220)

- [ ] **Step 3: Build and verify**

```
xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all barbell tests**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests 2>&1 | grep -E "passed|failed|error"
```

Expected: all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellEntityBuilder.swift Features/Profile/Views/BarbellPreviewView.swift Features/Rewards/Views/BarbellWelcomeView.swift Features/Rewards/Views/BarbellMomentView.swift
git commit -m "chore(barbell): remove dead ShaderGraph engraving template code"
```

---

## Task 7: PlateInfoCardView — Native SwiftUI Card

**Files:**
- Create: `Features/Rewards/Views/PlateInfoCardView.swift`

**Context:** Replaces the baked-texture `ModelEntity` card with a native SwiftUI view. Accepts an `EarnedPlate` and a dismiss closure. Uses DS design tokens and `ChamferedRectangle` to match the existing visual design.

- [ ] **Step 1: Create the file**

Create `Features/Rewards/Views/PlateInfoCardView.swift` with the following full implementation:

```swift
import SwiftUI

struct PlateInfoCardView: View {
    let plate: EarnedPlate
    let onDismiss: () -> Void

    private var tier: PlateTier? { PlateTier.all.first { $0.id == plate.tierID } }

    var body: some View {
        if let tier {
            VStack(spacing: 0) {
                header(tier: tier)
                body(tier: tier)
            }
            .clipShape(ChamferedRectangle(.xl))
            .overlay(
                ChamferedRectangle(.xl)
                    .stroke(DS.Semantic.border, lineWidth: 1)
            )
            .padding(.horizontal, 32)
        }
    }

    private func header(tier: PlateTier) -> some View {
        ZStack {
            tier.plateColor.opacity(0.88)
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 52, height: 52)
                    Text(String(tier.name.prefix(1)))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                Text(tier.rarity.rawValue.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.22), in: Capsule())
            }
            .padding(.vertical, 20)
        }
    }

    private func body(tier: PlateTier) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tier.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .padding(.top, 16)
                .padding(.horizontal, 20)
            Divider()
                .overlay(DS.Semantic.border)
                .padding(.top, 12)
                .padding(.horizontal, 20)
            if plate.weightKg > 0 {
                infoRow(
                    label: "WEIGHT",
                    value: plate.weightKg.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(plate.weightKg)) kg"
                        : String(format: "%.1f kg", plate.weightKg)
                )
            }
            infoRow(label: "HOW YOU EARNED IT", value: infoCardFormatEvent(plate.earnedByEvent))
            infoRow(label: "EARNED ON", value: {
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .none
                return df.string(from: plate.earnedAt)
            }())
        }
        .padding(.bottom, 20)
        .background(DS.Semantic.card)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .padding(.top, 14)
        .padding(.horizontal, 20)
    }
}

private func infoCardFormatEvent(_ event: String) -> String {
    switch event {
    case "starter":         return "Awarded at account creation"
    case "first_workout":   return "Completed your first workout"
    default: break
    }
    if event.hasPrefix("pr_") { return "Hit a personal record" }
    if event.hasPrefix("strength_milestone_") {
        let n = event.replacingOccurrences(of: "strength_milestone_", with: "")
        return "Reached strength milestone \(n)"
    }
    return event.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
}
```

- [ ] **Step 2: Build and verify**

```
xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Features/Rewards/Views/PlateInfoCardView.swift
git commit -m "feat(barbell): PlateInfoCardView — native SwiftUI plate detail card"
```

---

## Task 8: BarbellRealityView — SwiftUI Overlay Wiring

**Files:**
- Modify: `Features/Rewards/Views/BarbellRealityView.swift`
- Modify: `Features/Rewards/Views/BarbellEntityBuilder.swift`

**Context:** Replace the 3D `ModelEntity` info card approach with a SwiftUI overlay triggered by `@State`. Remove `infoCardEntity` from `SceneState`, rewrite `showInfoCard`/`dismissInfoCard`, add the overlay to `body`, and delete the now-dead baked-texture functions from `BarbellEntityBuilder`.

- [ ] **Step 1: Remove `infoCardEntity` from SceneState**

In `Features/Rewards/Views/BarbellRealityView.swift`, find `SceneState` (line ~120). Delete:

```swift
var infoCardEntity: Entity? = nil
```

Keep `var infoCardPlateID: String?` and `var infoCardLastShowTime: Date` — still needed.

- [ ] **Step 2: Add `@State` property to BarbellRealityView**

Find `struct BarbellRealityView: View` and add alongside the other `@State` properties:

```swift
@State private var infoCardPlate: EarnedPlate? = nil
```

- [ ] **Step 3: Replace `showInfoCard`**

The actual function signature is `private func showInfoCard(for plateID: String)` with call sites using `showInfoCard(for: tapID)`. Find this function (search for `func showInfoCard(for`) and replace its entire body — keep the existing signature unchanged:

```swift
private func showInfoCard(for plateID: String) {
    let allPlates = allRackedPlates + allFloorPlates
    guard let plate = allPlates.first(where: { $0.id == plateID }) else { return }
    dismissInfoCard(animated: false)
    sceneState.infoCardPlateID      = plateID
    sceneState.infoCardLastShowTime = Date()
    infoCardPlate = plate
}
```

- [ ] **Step 4: Replace `dismissInfoCard`**

Find `private func dismissInfoCard(animated: Bool = true)` (line ~1860). Replace the entire function:

```swift
private func dismissInfoCard(animated: Bool = true) {
    guard infoCardPlate != nil else { return }
    if animated && Date().timeIntervalSince(sceneState.infoCardLastShowTime) < 0.40 { return }
    sceneState.infoCardPlateID = nil
    infoCardPlate = nil
}
```

- [ ] **Step 5: Add SwiftUI overlay to `body`**

Find the outermost container in `var body: some View`. Wrap it (or add `.overlay` to the outermost view modifier chain):

```swift
.overlay {
    if let plate = infoCardPlate {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .onTapGesture { dismissInfoCard() }
        PlateInfoCardView(plate: plate) {
            dismissInfoCard()
        }
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}
.animation(.spring(duration: 0.28), value: infoCardPlate?.id)
```

- [ ] **Step 6: Delete baked-texture functions from BarbellEntityBuilder**

In `Features/Rewards/Views/BarbellEntityBuilder.swift`, find and delete:

1. `func makeInfoCardEntity(plate: EarnedPlate) -> ModelEntity` — the full function (line ~1859)
2. `private func makeInfoCardTexture(plate: EarnedPlate, tier: PlateTier) -> UIImage` — the full function (line ~1879)
3. `private func infoCardFormatEvent(_ event: String) -> String` — the full function (line ~2037). This logic now lives in `PlateInfoCardView.swift`.

- [ ] **Step 7: Build and verify**

```
xcodebuild build -scheme WRKT 2>&1 | grep -E "error:|BUILD FAILED|BUILD SUCCEEDED"
```

Expected: BUILD SUCCEEDED. If there are remaining references to `makeInfoCardEntity` or `infoCardEntity`, delete them.

- [ ] **Step 8: Run full barbell test suite**

```
xcodebuild test -scheme WRKT -only-testing WRKTTests/BarbellEntityBuilderTests 2>&1 | grep -E "passed|failed|error"
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add Features/Rewards/Views/BarbellRealityView.swift Features/Rewards/Views/BarbellEntityBuilder.swift
git commit -m "feat(barbell): replace 3D info card entity with SwiftUI overlay"
```
