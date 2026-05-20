# Barbell Info Card — SwiftUI Overlay

**Date:** 2026-05-20
**Scope:** Replace the 3D `ModelEntity` info card (baked texture, grainy text) with a native SwiftUI overlay that renders at full display resolution.

---

## Problem

`makeInfoCardEntity` builds a `ModelEntity` with a 700×900pt `UIGraphicsImageRenderer` texture. `TextureResource.generate` applies ASTC GPU compression, degrading text edges. A flat card that always faces the camera gains nothing from being a 3D entity — SwiftUI renders the same content at pixel-perfect quality for free.

---

## Changes

### 1. State — remove entity, add SwiftUI trigger

**File:** `Features/Rewards/Views/BarbellRealityView.swift`

Add one `@State` property to `BarbellRealityView`:

```swift
@State private var infoCardPlate: EarnedPlate? = nil
```

Remove from `SceneState`:
- `var infoCardEntity: Entity?`

Keep in `SceneState` (still needed for tap-same-to-dismiss and debounce):
- `var infoCardPlateID: String?`
- `var infoCardLastShowTime: Date`

---

### 2. showInfoCard / dismissInfoCard

**File:** `Features/Rewards/Views/BarbellRealityView.swift`

Replace the entity-building body of `showInfoCard(plateID:)`:

```swift
private func showInfoCard(plateID: String) {
    let allPlates = allRackedPlates + allFloorPlates
    guard let plate = allPlates.first(where: { $0.id == plateID }) else { return }
    dismissInfoCard(animated: false)
    sceneState.infoCardPlateID      = plateID
    sceneState.infoCardLastShowTime = Date()
    infoCardPlate = plate
}
```

Replace `dismissInfoCard`:

```swift
private func dismissInfoCard(animated: Bool = true) {
    guard infoCardPlate != nil else { return }
    if animated && Date().timeIntervalSince(sceneState.infoCardLastShowTime) < 0.40 { return }
    sceneState.infoCardPlateID = nil
    infoCardPlate = nil
}
```

The 400ms debounce is preserved — same behaviour, no entity removal animation needed.

---

### 3. SwiftUI overlay

**File:** `Features/Rewards/Views/BarbellRealityView.swift`

Add to the outermost container in `body` (wrapping the existing `RealityView` + gesture stack):

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

---

### 4. PlateInfoCardView

**New file:** `Features/Rewards/Views/PlateInfoCardView.swift`

A SwiftUI view that replicates the current card layout using DS tokens. Accepts the plate and a dismiss closure:

```swift
struct PlateInfoCardView: View {
    let plate: EarnedPlate
    let onDismiss: () -> Void
}
```

Layout (top to bottom):

**Header** (tier color background, ~27% of card height):
- Circle with tier initial letter — `DS.Semantic.card` fill at 20% opacity
- Rarity pill — `DS.Semantic.card` fill at 22% opacity, tier rarity label

**Body** (DS.Semantic.card background):
- Tier name — bold, `DS.Semantic.textPrimary`
- Divider — `DS.Semantic.border`
- "WEIGHT" label + value (skip when `plate.weightKg == 0`)
- "HOW YOU EARNED IT" label + event string via `infoCardFormatEvent`
- "EARNED ON" label + formatted date
- Labels: `DS.Semantic.textSecondary`, small semibold
- Values: `DS.Semantic.textPrimary`, medium bold

**Shape:** `DS.ChamferedRectangle` with `.xl` chamfer (TL square, TR chamfered, BR square, BL chamfered — matching the existing texture layout).

Card is horizontally padded (`.padding(.horizontal, 32)`) and vertically centered. No fixed height — SwiftUI sizes to content.

`infoCardFormatEvent` moves from `BarbellEntityBuilder.swift` to `PlateInfoCardView.swift` as a private function (or a free function in the same file).

---

### 5. Delete baked-texture code

**File:** `Features/Rewards/Views/BarbellEntityBuilder.swift`

Delete:
- `func makeInfoCardEntity(plate:) -> ModelEntity`
- `private func makeInfoCardTexture(plate:tier:) -> UIImage`
- `private func infoCardFormatEvent(_ event:) -> String` (moved to `PlateInfoCardView.swift`)

---

## Files Changed

| File | Change |
|------|--------|
| `Features/Rewards/Views/BarbellRealityView.swift` | Add `@State var infoCardPlate`; rewrite `showInfoCard`/`dismissInfoCard`; add overlay; remove `infoCardEntity` from SceneState |
| `Features/Rewards/Views/BarbellEntityBuilder.swift` | Delete `makeInfoCardEntity`, `makeInfoCardTexture`, `infoCardFormatEvent` |
| `Features/Rewards/Views/PlateInfoCardView.swift` | New file — SwiftUI card view |

---

## Out of Scope

- Card content changes (same data as current: weight, earned by, earned on)
- Dismiss-on-swipe or additional gestures
- Animation beyond spring scale+fade
- The `infoCardPlateID` tap-same-to-dismiss logic — unchanged
