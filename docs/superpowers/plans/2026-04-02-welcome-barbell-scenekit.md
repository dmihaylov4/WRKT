# Welcome Screen Barbell: Unified SceneKit Renderer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the RealityKit barbell in `BarbellWelcomeView` with a SceneKit barbell so it shares the same renderer and light rig as the spinning plate thumbnails below, eliminating the visual lighting mismatch.

**Architecture:** All geometry in `BarbellWelcomeView` — both the barbell hero and the plate grid — will render through `SCNView` with identical SceneKit lights. A new `buildWelcomeBarbellScene()` free function assembles bar + collar + plate geometry as `SCNNode` trees using the same PBR helper and light constants already used by `buildPlateScene()`. `BarbellPreviewView` (RealityKit) is untouched; it continues to be used everywhere else in the app.

**Tech Stack:** SceneKit (`SCNView`, `SCNScene`, `SCNNode`, `SCNMaterial` PBR), SwiftUI `UIViewRepresentable`, existing `PlateTier` data model.

---

## Why the mismatch exists (context)

`BarbellPreviewView` uses RealityKit with:
- Two `PointLightComponent` entities (key at `(0,2,2)` intensity 3000, fill at `(-2,-1,1)` intensity 800)
- Optional IBL from `EnvironmentResource(named: "IndoorHDRI")` at `intensityExponent: 0.5`

The plate thumbnails use SceneKit with:
- Omni key light at `(0.5, 1.5, 1.5)` intensity 80
- Omni fill at `(-1.5, -0.5, 0.8)` intensity 30
- Ambient at intensity 20

Two different rendering engines + two different light setups = impossible to match visually. The fix: build the welcome barbell in SceneKit too.

---

## File Map

**Modify only:**
- `Features/Rewards/Views/BarbellWelcomeView.swift` — add SceneKit barbell builder + state, remove `BarbellPreviewView` usage

No new files. Everything lives alongside the existing `buildPlateScene()` / `buildSCNPlate()` helpers already in `BarbellWelcomeView.swift`.

---

## Task 1: Add shared light-rig constants and SCN PBR helper

All three scene builders (barbell, plates) must use identical light parameters. Currently the plate lights are inline magic numbers. Extract them to file-private constants so the new barbell scene can use the same values without copy-paste drift.

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift` — top of file, after imports

- [ ] **Step 1: Open the file and locate the existing light values in `buildPlateScene()`**

Look at lines ~79-105 in `BarbellWelcomeView.swift`. Note the three lights:
- Key omni: intensity 80, position `(0.5, 1.5, 1.5)`
- Fill omni: intensity 30, position `(-1.5, -0.5, 0.8)`
- Ambient: intensity 20

- [ ] **Step 2: Add constants block immediately after the `PlateUITextureCache` enum (before `PlateSceneView`)**

```swift
// MARK: - Shared scene-kit light constants
//
// All SCNScene instances in this file use identical lights so the barbell
// and plate thumbnails render under the same conditions.

private enum WelcomeLights {
    static let keyIntensity: CGFloat  = 80
    static let keyPosition            = SCNVector3(0.5, 1.5, 1.5)
    static let fillIntensity: CGFloat = 30
    static let fillPosition           = SCNVector3(-1.5, -0.5, 0.8)
    static let ambientIntensity: CGFloat = 20
}

private func addWelcomeLights(to scene: SCNScene) {
    let keyNode = SCNNode()
    keyNode.light = {
        let l = SCNLight()
        l.type = .omni
        l.intensity = WelcomeLights.keyIntensity
        l.color = UIColor.white
        return l
    }()
    keyNode.position = WelcomeLights.keyPosition
    scene.rootNode.addChildNode(keyNode)

    let fillNode = SCNNode()
    fillNode.light = {
        let l = SCNLight()
        l.type = .omni
        l.intensity = WelcomeLights.fillIntensity
        l.color = UIColor(white: 0.85, alpha: 1)
        return l
    }()
    fillNode.position = WelcomeLights.fillPosition
    scene.rootNode.addChildNode(fillNode)

    let ambNode = SCNNode()
    ambNode.light = {
        let l = SCNLight()
        l.type = .ambient
        l.intensity = WelcomeLights.ambientIntensity
        l.color = UIColor(white: 0.8, alpha: 1)
        return l
    }()
    scene.rootNode.addChildNode(ambNode)
}
```

- [ ] **Step 3: Update `buildPlateScene()` to call `addWelcomeLights()` instead of inlining the three light nodes**

Replace the three inline light-node blocks in `buildPlateScene()` (the key/fill/ambient sections, lines ~79-105) with a single call:

```swift
// Before spin root:
addWelcomeLights(to: scene)
```

Remove the now-replaced inline keyNode, fillNode, ambNode blocks.

- [ ] **Step 4: Build and confirm no compile errors**

Open Xcode or run:
```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E 'error:|Build succeeded'
```
Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Views/BarbellWelcomeView.swift
git commit -m "refactor: extract SceneKit light rig into addWelcomeLights() for reuse"
```

---

## Task 2: Build the SceneKit barbell scene

Add `buildWelcomeBarbellScene()` that constructs bar + collars + loaded plates as an `SCNNode` tree, and returns the scene plus a spin-root node for rotation.

The geometry mirrors `BarbellPreviewView`'s `makeBarbellShowcase()` logic but uses SceneKit primitives. Key mapping:

| RealityKit | SceneKit |
|---|---|
| `ModelEntity(mesh: .generateCylinder(height:radius:))` | `SCNNode(geometry: SCNCylinder(radius:height:))` |
| `simd_quatf(angle: .pi/2, axis: (0,0,1))` | `eulerAngles = SCNVector3(0, 0, Float.pi/2)` |
| `pbrMaterial(color:metallic:roughness:)` | `SCNMaterial` with `.lightingModel = .physicallyBased` |
| `plate.position = SIMD3(x, 0, 0)` | `node.position = SCNVector3(x, 0, 0)` |

The barbell cylinder axis is Y in SceneKit; rotate around Z by 90° to lay it horizontally.

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift` — add after `buildSCNPlate()`

- [ ] **Step 1: Add a `pbrSCNMaterial` helper immediately before `buildWelcomeBarbellScene()`**

This deduplicates material creation (mirrors the existing `pbrMat` inside `buildSCNPlate()`):

```swift
private func pbrSCNMaterial(color: UIColor, texture: UIImage? = nil,
                             metallic: Float, roughness: Float) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = texture ?? color
    m.metalness.contents = NSNumber(value: metallic)
    m.roughness.contents = NSNumber(value: roughness)
    return m
}
```

- [ ] **Step 2: Add `buildWelcomeBarbellScene(plates:)` after the helper**

```swift
/// Builds a full barbell scene for the welcome screen hero.
/// Returns the scene and its spin root (rotate spinRoot.eulerAngles.y for spin).
///
/// Coordinate system: bar runs along X. Camera looks toward +Z.
/// Plates: innermost pair at ±0.34, outer pair at ±0.37 (matches showcase slots 0-1).
private func buildWelcomeBarbellScene(plates: [EarnedPlateInfo]) -> (scene: SCNScene, spinRoot: SCNNode) {
    let scene = SCNScene()
    scene.background.contents = UIColor.black

    // Camera — pulled back to frame the full ~1.1-unit wide barbell
    let camNode = SCNNode()
    camNode.camera = {
        let c = SCNCamera()
        c.fieldOfView = 38
        c.zNear = 0.01
        return c
    }()
    camNode.position = SCNVector3(0, 0.08, 1.6)
    scene.rootNode.addChildNode(camNode)

    addWelcomeLights(to: scene)

    let spinRoot = SCNNode()
    scene.rootNode.addChildNode(spinRoot)

    // Bar — SCNCylinder axis is Y; rotate 90° around Z to lay along X
    let chromeMat = pbrSCNMaterial(
        color: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12
    )
    let barCyl = SCNCylinder(radius: 0.012, height: 1.1)
    barCyl.materials = [chromeMat, chromeMat, chromeMat]
    let barNode = SCNNode(geometry: barCyl)
    barNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
    spinRoot.addChildNode(barNode)

    // Collars at ±0.46
    for xSign: Float in [-1, 1] {
        let collarCyl = SCNCylinder(radius: 0.022, height: 0.04)
        collarCyl.materials = [chromeMat, chromeMat, chromeMat]
        let collarNode = SCNNode(geometry: collarCyl)
        collarNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        collarNode.position = SCNVector3(xSign * 0.46, 0, 0)
        spinRoot.addChildNode(collarNode)
    }

    // Plates — bilateral pairs, innermost first
    let slotOffsets: [[Float]] = [
        [-0.34, 0.34],
        [-0.37, 0.37],
        [-0.40, 0.40],
        [-0.43, 0.43],
    ]
    for (index, info) in plates.prefix(4).enumerated() {
        let offsets = slotOffsets[index]
        for xOffset in offsets {
            let plateInner = buildSCNPlate(tierID: info.tierID)
            // buildSCNPlate cylinder axis is Y, already rotated 90° around X so face is +Z.
            // Move the plate to its X slot on the bar.
            let plateNode = SCNNode()
            plateNode.addChildNode(plateInner)
            plateNode.position = SCNVector3(xOffset, 0, 0)
            spinRoot.addChildNode(plateNode)
        }
    }

    return (scene, spinRoot)
}
```

- [ ] **Step 3: Build and confirm no compile errors**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E 'error:|Build succeeded'
```
Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Views/BarbellWelcomeView.swift
git commit -m "feat: add buildWelcomeBarbellScene() SceneKit barbell for welcome screen"
```

---

## Task 3: Add BarbellSceneState and WelcomeBarbellView

Wire the scene into a SwiftUI view using the same UIViewRepresentable + physics-loop pattern as `SpinnablePlateCell`.

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift` — add after `PlateState`

- [ ] **Step 1: Add `BarbellWelcomeState` class after `PlateState`**

```swift
private final class BarbellWelcomeState {
    let scnView = SCNView()
    var spinRoot: SCNNode? = nil
    var rotY: Double = 0
    var velocity: Double = 0.35   // radians/sec, matches BarbellPreviewView initial spin
    var isDragging: Bool = false
    var lastTranslationX: CGFloat = 0
}
```

- [ ] **Step 2: Add `WelcomeBarbellView` after `SpinnablePlateCell`**

```swift
private struct WelcomeBarbellView: View {
    let plates: [EarnedPlateInfo]
    @State private var s = BarbellWelcomeState()

    var body: some View {
        PlateSceneView(scnView: s.scnView)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        s.isDragging = true
                        let delta = Double(value.translation.width - s.lastTranslationX)
                        s.velocity = delta * 60
                        s.rotY += delta * 0.012
                        s.lastTranslationX = value.translation.width
                        s.spinRoot?.eulerAngles.y = Float(s.rotY)
                    }
                    .onEnded { _ in
                        s.isDragging = false
                        s.lastTranslationX = 0
                    }
            )
            .task { @MainActor in
                let (scene, spin) = buildWelcomeBarbellScene(plates: plates)
                // Size the SCNView to match its SwiftUI frame before assigning scene
                s.scnView.frame = CGRect(x: 0, y: 0, width: 340, height: 220)
                s.scnView.scene = scene
                s.scnView.antialiasingMode = .multisampling4X
                s.scnView.backgroundColor = .black
                s.scnView.isOpaque = true
                s.scnView.allowsCameraControl = false
                s.scnView.rendersContinuously = true
                s.spinRoot = spin
                s.spinRoot?.eulerAngles.y = Float(s.rotY)

                var lastTime = Date().timeIntervalSinceReferenceDate
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(16))
                    let now = Date().timeIntervalSinceReferenceDate
                    let dt = min(now - lastTime, 0.05)
                    lastTime = now
                    guard !s.isDragging else { continue }
                    // Decay: ~3% per 60Hz frame, same as SpinnablePlateCell
                    s.velocity *= pow(0.97, dt * 60)
                    s.rotY += s.velocity * dt
                    s.spinRoot?.eulerAngles.y = Float(s.rotY)
                }
            }
    }
}
```

Note: `PlateSceneView` is already defined above and accepts any `SCNView` — it can be reused directly here. The barbell gets a wider frame (340×220) via the enclosing SwiftUI `.frame` modifier set in the next task.

- [ ] **Step 3: Build and confirm no compile errors**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E 'error:|Build succeeded'
```
Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Views/BarbellWelcomeView.swift
git commit -m "feat: add WelcomeBarbellView UIViewRepresentable wrapper with spin physics"
```

---

## Task 4: Swap BarbellPreviewView for WelcomeBarbellView in BarbellWelcomeView

**Files:**
- Modify: `Features/Rewards/Views/BarbellWelcomeView.swift` — `BarbellWelcomeView.body`

- [ ] **Step 1: In `BarbellWelcomeView.body`, replace the `BarbellPreviewView` with `WelcomeBarbellView`**

Find this block (around line 291):
```swift
BarbellPreviewView(mode: .showcase(plates: showcasePlateInfos))
    .allowsHitTesting(true)
```

Replace with:
```swift
WelcomeBarbellView(plates: showcasePlateInfos)
    .frame(width: 340, height: 220)
    .clipShape(RoundedRectangle(cornerRadius: 12))
```

- [ ] **Step 2: Remove `showcasePlateInfos` computed property if it now returns `[EarnedPlateInfo]` — confirm it's still needed**

`WelcomeBarbellView` takes `[EarnedPlateInfo]`, and `showcasePlateInfos` already returns `[EarnedPlateInfo]`. No changes needed there.

- [ ] **Step 3: Remove the RealityKit import if it is now unused**

Search the file for any remaining `RealityKit` or `RealityView` usage. If `BarbellPreviewView` was the only RealityKit consumer in this file, remove the import:
```swift
// remove: import RealityKit  (if present at top of BarbellWelcomeView.swift)
```

`BarbellWelcomeView.swift` uses only SceneKit — verify the top of the file has `import SceneKit` and no `import RealityKit`.

- [ ] **Step 4: Build and confirm no compile errors**

```
xcodebuild build -scheme WRKT -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E 'error:|Build succeeded'
```
Expected: `Build succeeded`

- [ ] **Step 5: Run on simulator and visually verify**

Launch the app on a simulator, trigger the welcome screen (Settings > "Show Welcome Screen" debug button). Confirm:
- Barbell hero renders with matching lighting to the plate thumbnails below
- Dragging the barbell spins it
- Plate thumbnails spin independently
- No crash on open

- [ ] **Step 6: Commit**

```bash
git add Features/Rewards/Views/BarbellWelcomeView.swift
git commit -m "feat: replace RealityKit barbell with SceneKit in BarbellWelcomeView for unified lighting"
```

---

## Camera tuning (if needed after visual check)

If the barbell appears too large or too small in the 340×220 frame, adjust `camNode.position.z` in `buildWelcomeBarbellScene()`:
- Too large: increase Z (e.g. `1.6` → `1.9`)
- Too small: decrease Z (e.g. `1.6` → `1.3`)
- Tilted too high/low: adjust Y (currently `0.08`)

Do not change the plate cell camera (`camNode.position = SCNVector3(0, 0, 0.38)` in `buildPlateScene()`) — that controls the individual thumbnail cells, not the hero.

---

## Self-Review

**Spec coverage:**
- Lighting mismatch fixed: both barbell and plates now use SceneKit + `addWelcomeLights()` with identical parameters. Covered by Tasks 1-4.
- No RealityKit in welcome view: Task 4 removes `BarbellPreviewView` from this screen.
- `BarbellPreviewView` unchanged: plan only touches `BarbellWelcomeView.swift`.
- Drag/spin on barbell: Task 3 `WelcomeBarbellView` includes gesture.
- All plate types: `buildWelcomeBarbellScene()` delegates to existing `buildSCNPlate()` which already handles all tier styles.

**Placeholder scan:** No TBDs, no "implement later", no vague error handling instructions. All steps have code.

**Type consistency:**
- `buildWelcomeBarbellScene(plates:)` returns `(scene: SCNScene, spinRoot: SCNNode)` — consumed in Task 3 `WelcomeBarbellView` correctly.
- `BarbellWelcomeState.spinRoot: SCNNode?` — set and mutated in Task 3.
- `addWelcomeLights(to:)` takes `SCNScene` — called in Task 1 refactor and Task 2 barbell builder.
- `pbrSCNMaterial` is file-private free function — used inside `buildWelcomeBarbellScene()`, does not conflict with `pbrMat` closure inside `buildSCNPlate()`.
