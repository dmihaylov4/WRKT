# Concrete Fix Roadmap By File

Date: 2026-04-14
Scope: Train, Plan, Feed, Cardio, Profile

## How To Use This Roadmap

This is ordered by leverage:

1. Fix product-contract bugs first.
2. Then collapse split ownership paths.
3. Then improve persistence/performance.

Each item lists the main files to touch and the concrete outcome to reach.

## Phase 1: Correctness And User-Trust Fixes

### 1. Planned workout start/completion contract

Goal:

- Starting a planned workout must launch the planned workout.
- Finishing it must mark the planned workout complete through the real production path.

Files:

- [Features/Planner/Components/DayActionCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/Components/DayActionCard.swift)
- [Features/Planner/CalendarMonthView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/CalendarMonthView.swift)
- [Features/WorkoutSession/Services/PlannerStore.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/PlannerStore.swift)
- [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)

Concrete changes:

- Change `.startWorkout(date)` handling so it resolves and starts the actual planned workout for that day.
- Thread planned-workout identity into the active workout/completion flow.
- Call `completePlannedWorkout(...)` from the real finish path, not as an orphan helper.
- Add one integration test or deterministic manual test path:
  - tap planned workout start
  - complete session
  - verify planner state becomes completed

### 2. Profile reset-all truthfulness

Goal:

- Reset behavior and reset copy must match exactly.

Files:

- [Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift)
- [Core/Persistence/WorkoutStorage.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift)
- [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)
- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift)

Concrete changes:

- Decide contract:
  - preserve imported cardio/runs
  - or wipe everything local
- Update `resetAllData()` and `resetHealthKitState()` to enforce that contract.
- Update alert/footer copy to match real behavior.
- If preserving runs:
  - do not call `wipeAllData()` in a way that deletes runs
  - do not call `store.clearAllRuns()`

### 3. Feed delete/undo semantics

Goal:

- Delete flow must either be truly reversible or clearly non-reversible.

Files:

- [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift)
- [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift)
- [Features/Social/Views/Components/PostCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/Components/PostCard.swift)

Concrete changes:

- Remove fake "undo" that recreates a new post, or replace delete with soft-delete/tombstone semantics.
- If keeping undo:
  - backend must restore same post identity
  - associated likes/comments must remain coherent
- Adjust delete confirmation text to reflect actual reversibility.

### 4. Cardio detail refresh stale rendering

Goal:

- After loading splits/details, the visible detail screen must update immediately.

Files:

- [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift)
- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift)
- [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)

Concrete changes:

- Replace captured `run` rendering with a live `currentRun` sourced from store or a detail view model.
- Pass live data into `OverviewTab`, `SplitsTab`, and `HeartRateTab`.
- Keep refresh actions, but make them update the active screen state deterministically.

## Phase 2: Collapse Split Ownership Paths

### 5. Train rest timer / next-set generation ownership

Goal:

- One owner for timer-driven set generation.

Files:

- [Features/WorkoutSession/Services/RestTimerManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/RestTimerManager.swift)
- [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)
- [Features/WorkoutSession/Views/WorkoutDetail/WorkoutDetail.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Views/WorkoutDetail/WorkoutDetail.swift)
- exercise row / live overlay files involved in next-set auto generation

Concrete changes:

- Choose one mutation owner for "rest finished -> generate next set".
- Move orchestration there.
- Make `RestTimerManager` `@MainActor` if it remains UI-coupled.
- Remove duplicate generation logic from overlays/screens.

### 6. Feed post mutations out of views

Goal:

- Views render. Social mutation flows live below the view layer.

Files:

- [Features/Social/Views/Components/PostCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/Components/PostCard.swift)
- [Features/Social/Views/EditPostView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/EditPostView.swift)
- [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift)
- [Features/Social/ViewModels/PostDetailViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/PostDetailViewModel.swift)
- [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift)

Concrete changes:

- Extract route-map backfill into a dedicated service/use-case.
- Inject that service instead of constructing `PostRepository()` inside views.
- Make edit screen actions flow through one model owner.
- Remove hidden writes from render-time `.task`.

### 7. Cardio enrichment ownership

Goal:

- One API for ensuring route/splits/HR detail exists.

Files:

- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift)
- [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift)
- [Features/Social/Services/CardioAutoPostService.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/CardioAutoPostService.swift)

Concrete changes:

- Introduce one public enrichment call, for example:
  - `ensureDetailedCardioData(for runId:)`
  - `ensureRouteAvailable(for runId:)`
- Make detail/share/autopost paths call that API instead of duplicating fetch logic.

### 8. Profile dashboard state owner

Goal:

- `ProfileView` becomes a composition screen, not an orchestration hub.

Files:

- [Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift)
- new profile dashboard view model/coordinator file
- [Features/Profile/Models/WeeklyProgressTypes.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Models/WeeklyProgressTypes.swift)

Concrete changes:

- Move dashboard state derivation into one owner.
- Move cache invalidation logic out of scattered `onChange`.
- Move HealthKit sync trigger to screen-level owner.
- Move tutorial flow to a small dedicated helper/model if it stays.

## Phase 3: Persistence, Querying, And Performance

### 9. Train save coalescing and flush rules

Goal:

- Fewer writes during active editing, zero ambiguity at lifecycle boundaries.

Files:

- [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)
- storage/persistence files called by workout store

Concrete changes:

- Add soft-edit coalescing window of `250-500ms`.
- Keep one pending save task.
- Force immediate flush on:
  - app background
  - workout finish
  - workout discard
  - entry remove/replace
  - timer-driven auto-generation

### 10. Feed pagination rewrite

Goal:

- One ordered feed stream, one cursor contract.

Files:

- [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift)
- backend query/RPC or Supabase SQL path that powers feed
- [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift)

Concrete changes:

- Replace dual-query own/other merge with one backend-ordered result set.
- Use composite cursor `(created_at, id)`.
- Overfetch one row to derive `hasMore`.
- Add append-time dedupe by `post.id`.

### 11. Planner editor data loss fixes

Goal:

- Editing planned workouts must preserve notes/progression strategy unless explicitly changed.

Files:

- [Features/Planner/Views/PlannedWorkoutEditor.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/Views/PlannedWorkoutEditor.swift)
- [Features/WorkoutSession/Models/PlannerModels.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Models/PlannerModels.swift)
- [Features/WorkoutSession/Services/PlannerStore.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/PlannerStore.swift)

Concrete changes:

- Preserve notes and progression strategy on edit save.
- Preserve `notes` explicitly; current round-trip drops them.
- Add explicit field ownership instead of rebuilding with defaults.
- Add regression test for edit-without-touching-those-fields.

### 12. Comment count source-of-truth cleanup

Goal:

- No `NotificationCenter` repair loop for core feed correctness.

Files:

- [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift)
- [Features/Social/ViewModels/PostDetailViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/PostDetailViewModel.swift)
- [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift)

Concrete changes:

- Choose durable count ownership:
  - backend-maintained counts
  - or fully derived counts
- Remove `NotificationCenter` count patch relay once true source exists.

### 13. Cardio history model and type support

Goal:

- Cardio UI should reflect actual imported cardio universe.

Files:

- [Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift)
- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift)
- [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift)

Concrete changes:

- Replace hard-coded 3-type filter with derived/supportable cardio categories.
- Add "All cardio" or broader type set.
- Move weekly slicing/filtering/sorting out of the view layer.

### 14. Profile cache invalidation cleanup

Goal:

- Profile dashboard stays fresh without ad hoc refresh hacks.

Files:

- [Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift)
- [Features/Profile/Models/WeeklyProgressTypes.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Models/WeeklyProgressTypes.swift)
- stats aggregator files used by `store.stats`

Concrete changes:

- Replace count-based refresh triggers with domain-driven invalidation.
- Make weekly progress recompute on all real dependencies:
  - goals
  - weekly summaries
  - runs
  - completed workouts
  - reward cutoff changes

## Phase 4: Cleanup And Consistency

### 15. Remove dead/broken UI affordances

Files:

- [Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift)
- [Features/Profile/Views/SettingsView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/SettingsView.swift)
- any comparable empty/dead links found during implementation

Concrete changes:

- Fix empty `NavigationLink` in PR Collection header.
- Audit hidden or placeholder buttons/links while touching these screens.

### 16. Barbell metadata centralization

Goal:

- Rewards/barbell metadata lives in one shared domain location.

Files:

- [Features/Profile/Views/BarbellPreviewView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/BarbellPreviewView.swift)
- [Features/Rewards/Models/BarbellModels.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/BarbellModels.swift)
- [Features/Rewards/Services/BarbellProgressService.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Services/BarbellProgressService.swift)
- [Features/Rewards/Views/BarbellEntityBuilder.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Views/BarbellEntityBuilder.swift)

Concrete changes:

- Move static `PlateTier` / `BarSkin` / `StickerOption` definitions out of the profile view file.
- Make profile/rewards/rendering all read from same metadata source.

## Suggested Implementation Order

### Sprint 1

- `PreferencesView.swift`
- `WorkoutStorage.swift`
- `HealthKitManager.swift`
- `DayActionCard.swift`
- `CalendarMonthView.swift`
- `PlannerStore.swift`
- `WorkoutStoreV2.swift`
- `FeedViewModel.swift`

Deliverables:

- honest reset behavior
- planned workout start/completion fixed
- feed delete/undo semantics corrected
- cardio detail refresh visibly fixed

Note:

- planned workout completion wiring will likely require dependency/context injection so `WorkoutStoreV2` can resolve and complete the matching `PlannedWorkout` through planner-owned code.

### Sprint 2

- `CardioDetailView.swift`
- `HealthKitManager.swift`
- `PostCard.swift`
- `EditPostView.swift`
- `PostRepository.swift`
- `ProfileView.swift`

Deliverables:

- views stop owning major writes
- cardio enrichment path unified
- profile gets clearer state ownership

### Sprint 3

- `WorkoutStoreV2.swift`
- `PostRepository.swift`
- `PlannedWorkoutEditor.swift`
- `CardioView.swift`
- `WeeklyProgressTypes.swift`
- stats aggregator files

Deliverables:

- save coalescing
- real feed pagination
- planner edit preservation
- cardio type/model cleanup
- profile invalidation cleanup

## Bottom Line

If you want maximum payoff with minimum churn:

1. fix the contract bugs
2. move writes out of views
3. centralize domain ownership
4. then optimize persistence/querying

That order reduces both user-facing bugs and future architectural drift.

---

## Review

Date reviewed: 2026-04-15

### Verified as accurate

All 16 file references were checked. Every path exists:
- `Features/WorkoutSession/Services/PlannerStore.swift`
- `Features/Social/Services/CardioAutoPostService.swift`
- `Features/Profile/Models/WeeklyProgressTypes.swift`
- `Features/Rewards/Services/BarbellProgressService.swift`
- `Features/WorkoutSession/Models/PlannerModels.swift`
- All others referenced in Sprint 1-3

The diagnoses underlying each fix item are confirmed (see individual feature deep dives). The ordering is sound: Phase 1 items are all confirmed broken in current code.

### One flag: Sprint 1 includes `PlannerStore.swift` for planned workout completion

The roadmap correctly identifies that `PlannerStore.completePlannedWorkout(...)` has no call site and needs to be wired into `WorkoutStoreV2.finishCurrentWorkout()`. Verified: the function exists only at its definition. No code calls it. This is not just a wiring issue -- the call needs to happen in a context where the `PlannedWorkout` SwiftData object is accessible, which `WorkoutStoreV2` currently does not have. A dependency or context injection step will be required, and this is not reflected in the roadmap's "concrete changes" list.

### One gap in Phase 3

Item 11 (Planner editor data loss) correctly identifies that `savePlannedWorkout()` rebuilds `PlannedExercise` with `progressionStrategy: .static`. The concrete change "preserve all editable and non-editable fields when round-tripping" is accurate. However, it does not call out the `notes` field specifically -- `loadExistingWorkout()` reads notes into `@State` but `savePlannedWorkout()` does not write them back. Both notes and progressionStrategy are dropped. The fix needs to cover both.

This gap has now been addressed in the roadmap text.
