# Plate Snapshot Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2D procedural `PlateFaceView` thumbnails with RealityKit-accurate PNG snapshots rendered once and cached to disk, so plate thumbnails look identical to the 3D rack view.

**Architecture:** `PlateSnapshotService` uses a temporary off-screen `ARView` (`.nonAR` mode) to render each unique plate using the same `makePlateEntity` / `buildMaterial` / IBL pipeline as `BarbellRealityView`, then calls `ARView.snapshot()` — the only UIKit API that correctly captures Metal-rendered content. Results are written to `Caches/plate_snapshots/`. A new `CachedPlateThumbnail` view wraps `PlateFaceView` as a loading fallback and switches to the cached PNG when available. Rendering is triggered when a plate is awarded and on app launch for already-owned plates.

**Tech Stack:** RealityKit (`ARView`, `PerspectiveCamera`, `AnchorEntity`), `EnvironmentResource` for IBL, `UIGraphicsImageRenderer` for final PNG write, Swift Concurrency, Swift Testing.

---

## File Map

**Create:**
- `Features/Rewards/Services/PlateSnapshotService.swift` — singleton: cache key, disk I/O, ARView render pipeline
- `Features/Rewards/Views/CachedPlateThumbnail.swift` — drop-in `PlateFaceView` wrapper that loads cached PNG
- `WRKTTests/FeaturesTests/Rewards/PlateSnapshotServiceTests.swift`

**Modify:**
- `Features/Rewards/Services/BarbellProgressService.swift` — trigger snapshot after `awardPlates()`
- `App/AppShellView.swift` — pre-warm snapshots for existing plates on launch
- `Features/Profile/Views/Components/PlateCollectionCell.swift` — swap to `CachedPlateThumbnail`
- `Features/Compete/Views/BattleRewardPreviewBlock.swift` — swap to `CachedPlateThumbnail`
- `Features/Rewards/Views/WinScreen.swift` — swap to `CachedPlateThumbnail` in new-plate rows
- `Features/Rewards/Views/BarbellEditorView.swift` — swap to `CachedPlateThumbnail`

---

## Task 1: PlateSnapshotService — cache key and disk storage

**Files:**
- Create: `Features/Rewards/Services/PlateSnapshotService.swift`
- Create: `WRKTTests/FeaturesTests/Rewards/PlateSnapshotServiceTests.swift`

- [ ] **Step 1: Write failing tests for cache key and disk round-trip**

Create `WRKTTests/FeaturesTests/Rewards/PlateSnapshotServiceTests.swift`:

```swift
import Testing
import UIKit
@testable import WRKT

@Suite("PlateSnapshotService cache key and disk I/O")
struct PlateSnapshotServiceTests {

    @Test("cacheKey is stable for same inputs")
    func cacheKeyStable() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion")
        let k2 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion")
        #expect(k1 == k2)
    }

    @Test("cacheKey differs when tierID changes")
    func cacheKeyVariesByTier() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Champion")
        let k2 = PlateSnapshotService.cacheKey(tierID: 6, weightKg: 35, engravingText: "Champion")
        #expect(k1 != k2)
    }

    @Test("cacheKey differs when engravingText changes")
    func cacheKeyVariesByEngraving() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Alpha")
        let k2 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Beta")
        #expect(k1 != k2)
    }

    @Test("writing and reading a UIImage round-trips correctly")
    @MainActor
    func diskRoundTrip() async throws {
        let service = PlateSnapshotService.shared
        let key = "test_roundtrip_\(UUID().uuidString)"

        // Write a 1x1 red image
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        await service.writeToDisk(image: image, key: key)

        let loaded = service.loadFromDisk(key: key)
        #expect(loaded != nil)

        // Cleanup
        try? FileManager.default.removeItem(at: service.cacheURL(for: key))
    }

    @Test("cachedImage returns nil for unknown key")
    @MainActor
    func cachedImageMiss() {
        let service = PlateSnapshotService.shared
        let result = service.cachedImage(tierID: 9999, weightKg: 0, engravingText: "MISSING")
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL (PlateSnapshotService not found)**

```bash
xcodebuild test -project WRKT.xcodeproj -scheme WRKT \
  -destination 'platform=iOS Simulator,id=92CF4ACC-DAEB-4623-A9AE-5BD1BB9D54F8' \
  -only-testing:WRKTTests/PlateSnapshotServiceTests 2>&1 | tail -10
```

Expected: compile error — `cannot find type 'PlateSnapshotService'`

- [ ] **Step 3: Create PlateSnapshotService with cache key and disk I/O**

Create `Features/Rewards/Services/PlateSnapshotService.swift`:

```swift
import UIKit
import RealityKit
import Foundation

@MainActor
final class PlateSnapshotService {
    static let shared = PlateSnapshotService()

    // In-memory cache keyed by cacheKey string
    private var memoryCache: [String: UIImage] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Cache Directory

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plate_snapshots", isDirectory: true)
    }

    func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }

    // MARK: - Cache Key

    /// Stable key for a unique plate appearance. tierID + weightKg + engravingText
    /// drive the 3D entity appearance; liftTypeID is 2D-only and not part of the 3D snapshot.
    static func cacheKey(tierID: Int, weightKg: Double, engravingText: String) -> String {
        let engravingHash = engravingText.isEmpty ? "none" : String(engravingText.hashValue & 0xFFFF_FFFF)
        return "p\(tierID)_\(Int(weightKg * 10))_\(engravingHash)"
    }

    // MARK: - Read

    func cachedImage(tierID: Int, weightKg: Double, engravingText: String) -> UIImage? {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if let mem = memoryCache[key] { return mem }
        return loadFromDisk(key: key)
    }

    func loadFromDisk(key: String) -> UIImage? {
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        memoryCache[key] = image
        return image
    }

    // MARK: - Write

    func writeToDisk(image: UIImage, key: String) async {
        memoryCache[key] = image
        let url = cacheURL(for: key)
        if let data = image.pngData() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Existence check

    func hasCached(tierID: Int, weightKg: Double, engravingText: String) -> Bool {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if memoryCache[key] != nil { return true }
        return FileManager.default.fileExists(atPath: cacheURL(for: key).path)
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
xcodebuild test -project WRKT.xcodeproj -scheme WRKT \
  -destination 'platform=iOS Simulator,id=92CF4ACC-DAEB-4623-A9AE-5BD1BB9D54F8' \
  -only-testing:WRKTTests/PlateSnapshotServiceTests 2>&1 | grep -E "passed|failed|error:" | head -15
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Features/Rewards/Services/PlateSnapshotService.swift \
        WRKTTests/FeaturesTests/Rewards/PlateSnapshotServiceTests.swift
git commit -m "feat(plates): add PlateSnapshotService with cache key and disk I/O"
```

---

## Task 2: PlateSnapshotService — ARView render pipeline

**Files:**
- Modify: `Features/Rewards/Services/PlateSnapshotService.swift`

- [ ] **Step 1: Add the render method to PlateSnapshotService**

Append to `Features/Rewards/Services/PlateSnapshotService.swift` (inside the class, before the final `}`):

```swift
    // MARK: - Render

    /// Renders a plate using an off-screen ARView, captures via ARView.snapshot(),
    /// and writes to disk. If a render is already in-flight for this key, does nothing.
    private var renderingKeys: Set<String> = []

    func renderIfNeeded(tierID: Int, weightKg: Double, engravingText: String) async {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        guard !hasCached(tierID: tierID, weightKg: weightKg, engravingText: engravingText),
              !renderingKeys.contains(key) else { return }

        renderingKeys.insert(key)
        defer { renderingKeys.remove(key) }

        guard let image = await renderPlate(tierID: tierID, weightKg: weightKg, engravingText: engravingText) else {
            return
        }
        await writeToDisk(image: image, key: key)
    }

    private func renderPlate(tierID: Int, weightKg: Double, engravingText: String) async -> UIImage? {
        // Must find a window to add the ARView to — Metal requires a live view hierarchy.
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }

        let size = CGSize(width: 300, height: 300)
        let arView = ARView(
            frame: CGRect(x: -size.width - 10, y: -size.height - 10, width: size.width, height: size.height),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.environment.background = .color(.black)
        window.addSubview(arView)

        defer { arView.removeFromSuperview() }

        // Build plate entity
        let textures = loadPlateTextures(forTierID: tierID)
        let material = buildMaterial(forTierID: tierID, textures: textures)
        let entity = makePlateEntity(
            tierID: tierID,
            textures: textures,
            material: material,
            weightKg: weightKg,
            engravingText: engravingText,
            options: .visualOnly()
        )

        // Stand upright, facing camera (same orientation as SpinningPlateView / showcase)
        let upright = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        entity.transform = Transform(scale: .one, rotation: upright, translation: .zero)

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        // Perspective camera — positioned to frame a single plate (~22.5 cm radius) at scale 1
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 45
        camera.position = [0, 0, 0.65]
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)

        // IBL — same resource as BarbellRealityView for identical lighting
        if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
            let iblEntity = Entity()
            iblEntity.components.set(ImageBasedLightComponent(
                source: .single(ibl),
                intensityExponent: 8
            ))
            anchor.addChild(iblEntity)
            anchor.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
        }

        // Give RealityKit 2 frames to render IBL + materials before snapshotting
        try? await Task.sleep(for: .milliseconds(150))

        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToPhotoLibrary: false) { image in
                continuation.resume(returning: image)
            }
        }
    }
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -10
```

Expected: no output (no errors).

- [ ] **Step 3: Commit**

```bash
git add Features/Rewards/Services/PlateSnapshotService.swift
git commit -m "feat(plates): add ARView render pipeline to PlateSnapshotService"
```

---

## Task 3: CachedPlateThumbnail view

**Files:**
- Create: `Features/Rewards/Views/CachedPlateThumbnail.swift`

- [ ] **Step 1: Create the drop-in view**

Create `Features/Rewards/Views/CachedPlateThumbnail.swift`:

```swift
import SwiftUI

/// Drop-in replacement for PlateFaceView that shows a cached RealityKit PNG
/// if available, falling back to PlateFaceView while the snapshot renders.
///
/// Usage — replace:
///   PlateFaceView(tierID: x, progressionTier: y, liftTypeID: z, weightKg: w)
/// with:
///   CachedPlateThumbnail(tierID: x, progressionTier: y, liftTypeID: z,
///                        weightKg: w, engravingText: e)
struct CachedPlateThumbnail: View {
    let tierID: Int
    let progressionTier: BarbellPlateProgressionTier
    let liftTypeID: String?
    let weightKg: Double
    var engravingText: String = ""
    var showEngravings: Bool = true

    @State private var cachedImage: UIImage? = nil

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                PlateFaceView(
                    tierID: tierID,
                    progressionTier: progressionTier,
                    liftTypeID: liftTypeID,
                    weightKg: weightKg,
                    showEngravings: showEngravings
                )
            }
        }
        .task {
            // Load from cache immediately (synchronous disk read on first access)
            if let image = PlateSnapshotService.shared.cachedImage(
                tierID: tierID, weightKg: weightKg, engravingText: engravingText
            ) {
                cachedImage = image
                return
            }
            // Not cached — trigger async render, then reload
            await PlateSnapshotService.shared.renderIfNeeded(
                tierID: tierID, weightKg: weightKg, engravingText: engravingText
            )
            cachedImage = PlateSnapshotService.shared.cachedImage(
                tierID: tierID, weightKg: weightKg, engravingText: engravingText
            )
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -10
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Features/Rewards/Views/CachedPlateThumbnail.swift
git commit -m "feat(plates): add CachedPlateThumbnail view with PlateFaceView fallback"
```

---

## Task 4: Trigger render on plate award

**Files:**
- Modify: `Features/Rewards/Services/BarbellProgressService.swift`

- [ ] **Step 1: Find `awardPlates` in BarbellProgressService.swift**

The method is `func awardPlates(_ plates: [EarnedPlateInfo], sourceWorkoutID: String?, suppressWinScreen: Bool = false)`.
After the `try context.save()` block succeeds and `syncPayloads` is populated, add a Task to trigger snapshots:

```bash
grep -n "try context.save\|syncPayloads.isEmpty\|WinScreenCoordinator" \
  Features/Rewards/Services/BarbellProgressService.swift | head -10
```

- [ ] **Step 2: Add snapshot trigger after plate award**

In `BarbellProgressService.swift`, inside `awardPlates()`, add immediately after the `if !suppressWinScreen { ... }` block (still inside the `do { ... }` that wraps `context.save()`):

```swift
            // Trigger RealityKit snapshot for each newly awarded plate.
            // Fire-and-forget — snapshot failure never affects plate awarding.
            for payload in syncPayloads {
                Task { @MainActor in
                    await PlateSnapshotService.shared.renderIfNeeded(
                        tierID: payload.tierID,
                        weightKg: payload.weightKg,
                        engravingText: payload.engravingText
                    )
                }
            }
```

`EarnedPlateSyncPayload` has `tierID: Int`, `weightKg: Double`, `engravingText: String` — confirm by running:

```bash
grep -n "struct EarnedPlateSyncPayload\|let tierID\|let weightKg\|let engravingText" \
  Features/Rewards/Models/BarbellModels.swift | head -10
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -10
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add Features/Rewards/Services/BarbellProgressService.swift
git commit -m "feat(plates): trigger snapshot render when new plates are awarded"
```

---

## Task 5: Pre-warm snapshots for existing plates on app launch

**Files:**
- Modify: `App/AppShellView.swift`

- [ ] **Step 1: Find the launch hook in AppShellView**

The `handleAppLaunch()` function (or equivalent) is called during startup. We add snapshot pre-warming there, after the user is authenticated:

```bash
grep -n "handleAppLaunch\|presentPendingBattle\|authService.currentUser\|isLocalMode" \
  App/AppShellView.swift | head -10
```

- [ ] **Step 2: Add pre-warm call**

In `AppShellView.swift`, add a private function:

```swift
private func prewarmPlateSnapshots() async {
    guard let context = dependencies.barbellProgressService.context else { return }
    let plates = (try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? []
    for plate in plates {
        guard !Task.isCancelled else { return }
        await PlateSnapshotService.shared.renderIfNeeded(
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText
        )
    }
}
```

Then in the same block that calls `presentPendingBattleRewardsOnLaunch()` (inside the `!settings.isLocalMode && authService.currentUser != nil` guard), add:

```swift
Task { await prewarmPlateSnapshots() }
```

Note: wrap in a detached `Task` so it doesn't block launch. Pre-warming is best-effort.

- [ ] **Step 3: Verify `context` is accessible**

```bash
grep -n "var context\|context:" Features/Rewards/Services/BarbellProgressService.swift | head -5
```

`BarbellProgressService.context` is `ModelContext?`. If it's `private`, change the access modifier to `internal` or expose a `allOwnedPlateInfos() -> [EarnedPlateInfo]` helper instead:

```swift
// Add to BarbellProgressService if context is private:
func allOwnedPlateInfos() -> [(tierID: Int, weightKg: Double, engravingText: String)] {
    guard let context else { return [] }
    let plates = (try? context.fetch(FetchDescriptor<EarnedPlate>())) ?? []
    return plates.map { ($0.tierID, $0.weightKg, $0.engravingText) }
}
```

Then `prewarmPlateSnapshots()` uses:

```swift
private func prewarmPlateSnapshots() async {
    let plates = dependencies.barbellProgressService.allOwnedPlateInfos()
    for plate in plates {
        guard !Task.isCancelled else { return }
        await PlateSnapshotService.shared.renderIfNeeded(
            tierID: plate.tierID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText
        )
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -10
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add App/AppShellView.swift Features/Rewards/Services/BarbellProgressService.swift
git commit -m "feat(plates): pre-warm snapshots for existing plates on app launch"
```

---

## Task 6: Replace PlateFaceView in PlateCollectionCell

**Files:**
- Modify: `Features/Profile/Views/Components/PlateCollectionCell.swift`

- [ ] **Step 1: Find the PlateFaceView call**

```bash
grep -n "PlateFaceView" Features/Profile/Views/Components/PlateCollectionCell.swift
```

Expected: line ~99 with `PlateFaceView(tierID: plate.tierID, progressionTier: plate.currentTier, liftTypeID: plate.liftTypeID, weightKg: plate.weightKg)`.

- [ ] **Step 2: Replace with CachedPlateThumbnail**

Replace:
```swift
PlateFaceView(
    tierID: plate.tierID,
    progressionTier: plate.currentTier,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg
)
```

With:
```swift
CachedPlateThumbnail(
    tierID: plate.tierID,
    progressionTier: plate.currentTier,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg,
    engravingText: plate.engravingText
)
```

(`plate` is an `EarnedPlate` which has `.engravingText: String`)

- [ ] **Step 3: Build and commit**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -5

git add Features/Profile/Views/Components/PlateCollectionCell.swift
git commit -m "feat(plates): use CachedPlateThumbnail in PlateCollectionCell"
```

---

## Task 7: Replace PlateFaceView in BattleRewardPreviewBlock

**Files:**
- Modify: `Features/Compete/Views/BattleRewardPreviewBlock.swift`

- [ ] **Step 1: Find the PlateFaceView calls**

```bash
grep -n "PlateFaceView\|tierID\|weightKg\|engravingText" \
  Features/Compete/Views/BattleRewardPreviewBlock.swift | head -15
```

- [ ] **Step 2: Read the existing call to understand what data is available**

```bash
sed -n '70,100p' Features/Compete/Views/BattleRewardPreviewBlock.swift
```

- [ ] **Step 3: Replace PlateFaceView with CachedPlateThumbnail**

There is one `PlateFaceView` call inside a sub-view that takes `tierID`, `liftTypeID`, `isWinner`. The view also has access to the `BattleType` (stored as a property). Replace:

```swift
PlateFaceView(
    tierID: tierID,
    progressionTier: .iron,
    liftTypeID: liftTypeID,
    weightKg: isWinner ? 35 : 20
)
.frame(width: 88, height: 88)
.clipped()
```

With:

```swift
CachedPlateThumbnail(
    tierID: tierID,
    progressionTier: .iron,
    liftTypeID: liftTypeID,
    weightKg: isWinner ? 35 : 20,
    engravingText: isWinner ? battleType.winnerEngravingText : battleType.displayName
)
.frame(width: 88, height: 88)
.clipped()
```

`battleType` is already a stored property on the parent view (`BattleRewardPreviewBlock`). Pass it down to the sub-view if needed.

- [ ] **Step 4: Build and commit**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -5

git add Features/Compete/Views/BattleRewardPreviewBlock.swift
git commit -m "feat(plates): use CachedPlateThumbnail in BattleRewardPreviewBlock"
```

---

## Task 8: Replace PlateFaceView in WinScreen

**Files:**
- Modify: `Features/Rewards/Views/WinScreen.swift`

- [ ] **Step 1: Find the PlateFaceView calls**

```bash
grep -n "PlateFaceView" Features/Rewards/Views/WinScreen.swift
```

Expected: lines ~624 and ~653.

- [ ] **Step 2: Read the call context**

```bash
sed -n '618,660p' Features/Rewards/Views/WinScreen.swift
```

The WinScreen has two `PlateFaceView` calls — one inside `RealityPlatePreview` (line ~653) taking `plate: EarnedPlateInfo`, and one for `.conditioningPlate` (line ~624) with a hardcoded tierID 24. Replace them:

**`RealityPlatePreview` (line ~653):** Replace:
```swift
PlateFaceView(
    tierID: plate.tierID,
    progressionTier: .iron,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg
)
.padding(6)
```
With:
```swift
CachedPlateThumbnail(
    tierID: plate.tierID,
    progressionTier: .iron,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg,
    engravingText: plate.engravingText
)
.padding(6)
```

**`.conditioningPlate` (line ~624):** Replace:
```swift
PlateFaceView(
    tierID: 24,
    progressionTier: .iron,
    liftTypeID: nil,
    weightKg: 20
)
.frame(width: 44, height: 44)
.clipped()
```
With:
```swift
CachedPlateThumbnail(
    tierID: 24,
    progressionTier: .iron,
    liftTypeID: nil,
    weightKg: 20,
    engravingText: ""
)
.frame(width: 44, height: 44)
.clipped()
```

- [ ] **Step 4: Build and commit**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -5

git add Features/Rewards/Views/WinScreen.swift
git commit -m "feat(plates): use CachedPlateThumbnail in WinScreen new-plate rows"
```

---

## Task 9: Replace PlateFaceView in BarbellEditorView

**Files:**
- Modify: `Features/Rewards/Views/BarbellEditorView.swift`

- [ ] **Step 1: Find and replace both PlateFaceView calls**

```bash
grep -n "PlateFaceView" Features/Rewards/Views/BarbellEditorView.swift
```

**Line ~396 (grid of `previewPlates`):** Replace:
```swift
PlateFaceView(
    tierID: plate.tierID,
    progressionTier: plate.currentTier,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg,
    showEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
)
.frame(width: 64, height: 64)
```
With:
```swift
CachedPlateThumbnail(
    tierID: plate.tierID,
    progressionTier: plate.currentTier,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg,
    engravingText: plate.engravingText,
    showEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
)
.frame(width: 64, height: 64)
```

**Line ~613 (loadout tile button):** Replace:
```swift
PlateFaceView(
    tierID: plate.tierID,
    progressionTier: plate.currentTier,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg,
    showEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
)
.frame(width: 64, height: 64)
.clipped()
```
With:
```swift
CachedPlateThumbnail(
    tierID: plate.tierID,
    progressionTier: plate.currentTier,
    liftTypeID: plate.liftTypeID,
    weightKg: plate.weightKg,
    engravingText: plate.engravingText,
    showEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
)
.frame(width: 64, height: 64)
.clipped()
```

- [ ] **Step 2: Build and commit**

```bash
xcodebuild build -project WRKT.xcodeproj -scheme WRKT \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' 2>&1 \
  | grep "error:" | grep -v "AppIcon\|Watch Watch App\|stickers" | head -5

git add Features/Rewards/Views/BarbellEditorView.swift
git commit -m "feat(plates): use CachedPlateThumbnail in BarbellEditorView"
```

---

## Task 10: Manual verification

- [ ] **Step 1: Add all new files to Xcode project**

In Xcode navigator, right-click `Features/Rewards/Services` → Add Files → `PlateSnapshotService.swift`.
Right-click `Features/Rewards/Views` → Add Files → `CachedPlateThumbnail.swift`.

- [ ] **Step 2: Delete cached snapshots to start fresh**

In Simulator menu: Device → Erase All Content and Settings (or just delete the app). This clears the `Caches/plate_snapshots/` directory.

- [ ] **Step 3: Launch app and verify pre-warm**

Add a temporary `print` in `prewarmPlateSnapshots()`:
```swift
AppLogger.info("Plate snapshot pre-warm: \(plates.count) plates to check", category: AppLogger.rewards)
```

Open app, wait 10-20 seconds. Expected log output: "Plate snapshot pre-warm: N plates to check".

- [ ] **Step 4: Navigate to plate collection**

Open Profile → Plates. Expected: plates show 2D `PlateFaceView` briefly (< 2s), then switch to the RealityKit-accurate PNG thumbnails. Check against the Rack view — they should look identical.

- [ ] **Step 5: Accept a battle invite to verify BattleRewardPreviewBlock**

The two reward plates should now use the cached 3D snapshot. If no snapshot exists yet (battle plate not owned), `CachedPlateThumbnail` renders on demand and shows the result once done.

- [ ] **Step 6: Run full test suite**

```bash
xcodebuild test -project WRKT.xcodeproj -scheme WRKT \
  -destination 'platform=iOS Simulator,id=92CF4ACC-DAEB-4623-A9AE-5BD1BB9D54F8' \
  -only-testing:WRKTTests/PlateSnapshotServiceTests 2>&1 \
  | grep -E "passed|failed|error:" | head -10
```

Expected: 4 tests pass.
