# Barbell Plate Collection And Storage Plan

Date: 2026-04-29

## Problem

The current Barbell rack room has limited visible storage for floor plates. That works for a small collection, but users will accumulate many earned plates over time. If the 3D rack room remains the only access point, older plates can become effectively hidden or inaccessible.

The key product distinction:

- The 3D rack room should be a focused loadout/editor space.
- The full plate inventory should live in a scalable collection browser.

RealityKit should not render every earned plate. It should render the current barbell plus a small working tray of plates.

## Current Relevant Paths

### Barbell Data And Progress

- `Features/Rewards/Models/BarbellModels.swift`
  - Defines `EarnedPlate`, `BarbellConfig`, and `EarnedPlateInfo`.
  - Current state fields include `isRacked` and `rackPosition`.

- `Features/Rewards/Services/BarbellProgressService.swift`
  - Owns starter plates, rack/unrack operations, backfill, reset, and Supabase sync.
  - Important methods:
    - `configure(context:)`
    - `ensureStarterPlates()`
    - `rackPlate(_:at:)`
    - `unrackPlate(_:)`
    - `runBackfillIfNeeded(completedWorkouts:)`
    - `rackedPlatesForFriend(userID:)`

- `Features/Rewards/Services/BarbellUnlockRules.swift`
  - Defines which workouts award which plates.

- `database_migrations/035_barbell_racked_plates.sql`
  - Current remote table for racked plate showcase sync.

### Rack Room And 3D Rendering

- `Features/Profile/Views/PlateWallView.swift`
  - Own-profile customization/rack room.
  - Queries racked plates and unracked floor plates.
  - Currently passes `rackedPlates` and limited `floorPlates` into `BarbellRealityView`.

- `Features/Rewards/Views/BarbellRealityView.swift`
  - RealityKit scene for welcome/rack room.
  - Defines `SceneState`, storage slots, bar slots, drag, rack, unrack, floor physics, and info cards.
  - Current storage slots are view-level affordances, not a scalable collection model.

- `Features/Profile/Views/BarbellPreviewView.swift`
  - Compact showcase/editor preview.
  - Used by profile and settings-style previews.

- `Features/Social/Views/BarbellShowcaseCard.swift`
  - Own/friend profile barbell card.
  - Own profile opens `PlateWallView`.
  - Friend profile displays remote racked plates.

### Reward And Welcome Flows

- `Features/Rewards/Views/BarbellWelcomeView.swift`
  - Welcome/backfill screen.
  - Shown when `BarbellProgressService.needsWelcomeScreen` is true.

- `Features/Rewards/Views/BarbellMomentView.swift`
  - Post-workout earned-plate moment.
  - Currently should drop newly earned plates into physics rather than animate them onto the bar.

- `Features/Rewards/Services/RewardEngine.swift`
  - Produces reward summaries and earned plates after workouts.

- `Features/Rewards/Views/WinScreen.swift`
  - Presents the reward flow and `BarbellMomentView`.

### App Presentation And Settings

- `App/AppShellView.swift`
  - Presents `BarbellWelcomeView` from `needsWelcomeScreen`.

- `Core/Dependencies/AppDependencies.swift`
  - Configures `BarbellProgressService`.
  - Runs backfill once `WorkoutStoreV2` storage is loaded.

- `Features/Profile/Views/SettingsView.swift`
  - Has DEBUG-only "Show Barbell Welcome" button.

- `Features/Profile/Views/PreferencesView.swift`
  - User preferences area. Relevant as a possible future entry point if plate collection is exposed from settings/preferences.

## Recommended Product Model

Separate the system into two concepts:

1. Barbell Loadout
   - What is currently mounted on the bar.
   - Limited slots, visually meaningful.
   - Shared to profile/social showcase.

2. Plate Collection
   - The complete inventory of earned plates.
   - Scalable SwiftUI grid/list.
   - Searchable, sortable, filterable.
   - Source of truth for all available plates.

The 3D rack room should not be the full inventory. It should be an editor stage with a small working tray.

## Recommended UX

### Rack Room

Purpose: edit the visible barbell loadout and enjoy physics interactions.

Show:

- Currently racked plates.
- A small tray of available plates, for example 6-8 plates.
- A clear button to open the full collection.
- A count like `+24 in collection` when more plates exist offstage.

The tray can be filled by:

- newest unracked plates,
- favorited plates,
- recently selected plates,
- or plates explicitly sent from the collection.

### Plate Collection

Purpose: access every earned plate.

Recommended UI:

- Grid or list of all earned plates.
- Search by engraving/source.
- Sort by:
  - newest,
  - rarity/tier,
  - weight,
  - earned source,
  - racked first.
- Filter by:
  - available,
  - racked,
  - tier/rarity,
  - weight.

Plate card contents:

- plate visual or tier swatch,
- weight,
- engraving,
- rarity/tier,
- earned date/source,
- racked status.

Plate detail actions:

- `Rack`
- `Replace on Bar`
- `Send to Tray`
- `View Details`

### Rack Action

Do not require dragging from the full collection.

Flow:

1. User taps a plate in collection.
2. User chooses `Rack`.
3. If a bar slot is empty, rack immediately.
4. If the bar is full, show a replacement picker:
   - replace outermost,
   - or choose a current racked plate.
5. Persist via `BarbellProgressService`.
6. Rack room/showcase updates from `@Query`.

## Data Model Direction

Keep persisted model focused on durable user intent, not scene placement.

Current durable fields:

- `isRacked`
- `rackPosition`
- earned metadata

Potential additions:

- `isFavorite`
- `lastSelectedAt`
- `trayPosition` or `isInTray`

Avoid making every 3D storage slot a permanent property for every plate. Storage slots are a view concern. A plate's collection existence is durable; where it appears in a temporary rack room tray is presentation state unless the product explicitly supports pinned tray slots.

## Technical Direction

### 1. Keep RealityKit Small

`BarbellRealityView` should render:

- racked plates,
- a bounded number of tray plates,
- physics objects currently active in the scene.

It should not render all `EarnedPlate` rows.

### 2. Add Collection Screen

Create a dedicated collection view, likely near:

- `Features/Profile/Views/PlateCollectionView.swift`

Possible supporting components:

- `Features/Profile/Views/PlateCollectionCard.swift`
- `Features/Profile/ViewModels/PlateCollectionViewModel.swift`

Use SwiftData `@Query` or a small view model over `EarnedPlate`.

### 3. Add Entry Points

Suggested entry points:

- `PlateWallView` top bar or bottom tray: `Collection`
- `BarbellShowcaseCard` own profile area: secondary action or card footer
- Optional settings/preferences link later

### 4. Add Service Operations

Extend `BarbellProgressService` with higher-level operations:

- rack into first available slot,
- replace a chosen racked plate,
- send plate to tray,
- remove from tray,
- favorite/unfavorite.

Keep Supabase sync limited to racked showcase state unless the full collection needs remote backup later.

### 5. Migration And Existing Users

Existing users:

- Keep all `EarnedPlate` rows.
- Keep current `isRacked` and `rackPosition`.
- Show all earned plates in collection.
- Show only racked plates plus bounded tray in rack room.
- Default tray can be newest unracked plates if no tray state exists.

No data loss is needed.

## Implementation Phases

### Phase 1: Product-Safe Access

- Add full Plate Collection screen.
- Link to it from `PlateWallView`.
- Keep current rack room mostly unchanged.
- Show `+N in collection` count when not all floor plates are visible.
- Enable tap-to-rack from collection.

### Phase 2: Loadout Management

- Add replacement picker when bar is full.
- Add racked/unracked filters.
- Add sort/filter UI.
- Add detail sheet for plate metadata.

### Phase 3: Tray Model

- Add favorites or tray pinning.
- Rack room shows racked plates plus tray plates.
- Collection controls tray contents.
- Keep physics interactions for tray plates only.

### Phase 4: Polish And Sync

- Improve friend showcase metadata if needed.
- Consider remote backup of collection state only if required.
- Add tests around:
  - backfill collection count,
  - rack replacement,
  - tray limit,
  - collection filters,
  - no loss of old plates.

## Open Questions

- Should users be able to favorite plates?
- Should tray contents persist, or should tray always be newest available plates?
- Should `Rack` replace outermost by default or always ask when full?
- Should duplicate-looking plates be grouped by type, or shown individually because each plate has unique earned metadata?
- Should friend profiles show only racked plates, or also collection stats?

## Recommendation

Build the Plate Collection first and keep the 3D rack room as a bounded editor. This gives users reliable access to all earned plates while preserving the visual and physics experience where it works best.
