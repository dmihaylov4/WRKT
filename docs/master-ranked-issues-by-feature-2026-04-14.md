# Master Ranked Issue List By Feature

Date: 2026-04-14
Scope: app navigation features reviewed so far:

- Train
- Plan
- Feed
- Cardio
- Profile

Note:

- This ranked list intentionally excludes the weekly streak / freeze investigation because that issue cuts across Profile, Rewards, app lifecycle, and validation logic rather than belonging cleanly to a single reviewed navigation tab.

## Recommendation

For planning, per-feature is better.

Why:

- it matches how product and QA think
- it shows user impact more clearly
- it makes prioritization easier by surface area

For implementation, by-file is better.

Why:

- that is how engineers actually land fixes
- ownership and merge sequencing are clearer

Best workflow:

1. Prioritize from this feature-ranked list.
2. Execute from the file roadmap.

## Implementation Updates

Date: 2026-04-15

The following ranked issues have now been fixed in code.

### Fixed Now

- `Train / P1 / PR detection uses wrong rep logic`
  Change locations:
  [Features/Home/ViewModels/HomeViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Home/ViewModels/HomeViewModel.swift:176)
  [Features/Home/ViewModels/HomeViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Home/ViewModels/HomeViewModel.swift:195)
  What changed:
  Home recent-PR detection no longer compares every workout against a hardcoded 10-rep benchmark. It now compares each weighted set against historical same-rep and E1RM data from workouts before that workout date.

- `Train / P1 / removeEntry leaves empty workout alive`
  Change locations:
  [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift:627)
  What changed:
  Removing the last remaining entry now clears `currentWorkout` entirely, stops the rest timer, and sends a watch discard message instead of leaving an empty active workout shell alive.

- `Plan / P0 / Planned workout "Start" does not start the planned workout`
  Change locations:
  [Features/Planner/Components/DayActionCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/Components/DayActionCard.swift:18)
  [Features/Planner/CalendarMonthView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/CalendarMonthView.swift:1009)
  What changed:
  Today-plan `Start` now launches the actual planned workout path and opens the live workout tab instead of entering generic quick-start.

- `Plan / P0 / Planned workout completion lifecycle is disconnected`
  Change locations:
  [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift:93)
  [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift:349)
  [Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift:1632)
  [Features/WorkoutSession/Services/PlannerStore.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/PlannerStore.swift:229)
  [Core/Dependencies/AppDependencies.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Dependencies/AppDependencies.swift:147)
  What changed:
  Planned workouts now complete through `PlannerStore` from both workout-finish paths, so planner state updates when a planned workout is finished.

- `Profile / P0 / Reset-all warning contradicts actual reset behavior`
  Change locations:
  [Features/Profile/Views/PreferencesView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/PreferencesView.swift:500)
  [Core/Persistence/WorkoutStorage.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Persistence/WorkoutStorage.swift:820)
  [Persistence/Persistence.swift](/Users/dimitarmihaylov/dev/WRKT/Persistence/Persistence.swift:95)
  What changed:
  Reset-all now preserves cardio/runs in both legacy and current storage, no longer fake-disconnects HealthKit, and clears any active workout session so UI does not stay live after reset.

- `Cardio / P0 / Detail refresh updates store, but detail screen stays stale`
  Change locations:
  [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:20)
  [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:41)
  [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:251)
  What changed:
  Cardio detail now renders from the latest `Run` in `WorkoutStoreV2`, so refreshes for route, splits, and heart-rate data update the visible screen in place.

- `Cardio / P2 / History model hard-capped and view-computed`
  Change locations:
  [Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:139)
  [Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:223)
  What changed:
  Cardio week history is no longer capped to six weeks. The UI now derives the oldest available week from real cardio data, supports arrow and swipe navigation across the full recorded history, and replaces the old page dots with a compact history status label.

- `Cardio / P1 / Route enrichment logic duplicated across manager and detail view`
  Change locations:
  [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1747)
  [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:258)
  [Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:1124)
  What changed:
  Cardio enrichment now runs through one shared `HealthKitManager` path that loads route, route-with-heart-rate, splits, heart-rate samples and min/max values, workout metadata, calories, and running dynamics. `CardioDetailView` no longer hand-rolls route fetch/update logic, and `CardioView` run cards now render route previews from `routeWithHR` too, so newly enriched routes become visible outside the detail screen immediately.

- `Cardio / P1 / Full resync only enriches first 20 workouts`
  Change locations:
  [Features/Health/Models/RouteModels.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Models/RouteModels.swift:181)
  [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:667)
  [Features/Health/Views/HealthAuthSheet.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/HealthAuthSheet.swift:136)
  What changed:
  Historical cardio enrichment now targets all HealthKit-backed runs that still need detail repair instead of arbitrarily stopping at the first 20 added workouts. `Run` now defines explicit completeness rules (`needsHistoricalEnrichment`), full resync queues every eligible run, and the route/enrichment queue is drained in batches until empty. Historical resync/enrichment tasks now also suppress cardio auto-post creation, so repairing old HealthKit data no longer floods Feed with retroactive workout posts.

- `Feed / P0 / Delete "undo" is fake undo`
  Change locations:
  [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:31)
  [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:265)
  What changed:
  Feed post delete is now a delayed hard-delete with a 5-second cancel window. Undo cancels the pending delete and restores the original post in place instead of re-creating a new post with a new identity.

- `Feed / P0 / Feed pagination is structurally unreliable`
  Change locations:
  [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift:4)
  [Features/Social/Services/PostRepository.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/PostRepository.swift:94)
  [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:28)
  [Core/Services/RepositoryProtocols.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Services/RepositoryProtocols.swift:15)
  What changed:
  Feed pagination now uses one merged `workout_posts` query, ordered by `created_at desc, id desc`, with a composite cursor (`created_at|id`) and `limit + 1` page probing. Client-side merging of separately paged own/other streams is removed.

- `Feed / P1 / Views perform backend writes during render/edit flows`
  Change locations:
  [Features/Social/ViewModels/FeedViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/ViewModels/FeedViewModel.swift:358)
  [Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:99)
  [Features/Social/Views/FeedView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/FeedView.swift:287)
  [Features/Social/Views/EditPostView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/EditPostView.swift:4)
  [Features/Social/Views/Components/PostCard.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Views/Components/PostCard.swift:9)
  What changed:
  Route-map backfill writes no longer happen directly inside `PostCard` or `EditPostView`. Feed views now emit intent closures only, while `FeedViewModel.backfillRouteMap(for:)` owns the HealthKit fetch, map generation, image upload, post-image update, in-flight dedupe, and local feed-state update.

- `Profile / P1 / Cache invalidation and orchestration sprawl`
  Change locations:
  [Features/Profile/ViewModels/ProfileScreenViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/ViewModels/ProfileScreenViewModel.swift:1)
  [Features/Profile/Views/ProfileView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Profile/Views/ProfileView.swift:12)
  What changed:
  Staged refactor landed. `ProfileScreenViewModel` now owns the profile screen’s expensive cache rebuilds, stats refresh trigger, HealthKit sync throttling, week-progress cache, milestone cache, and dex preview cache. `ProfileView` still uses the same external data sources and UI structure, but no longer owns those orchestration methods directly. This reduces split ownership risk without changing the screen all at once.
  Verification note:
  Workout-completion -> Profile refresh was manually confirmed in-app. HealthKit/cardio-driven Profile refresh was not yet validated and remains the main follow-up test for this staged refactor.

- `Plan / P1 / Editing planned workouts can erase notes/progression strategy`
  Change locations:
  [Features/Planner/Views/PlannedWorkoutEditor.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/Views/PlannedWorkoutEditor.swift:27)
  [Features/Planner/Views/PlannedWorkoutEditor.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/Views/PlannedWorkoutEditor.swift:209)
  [Features/Planner/Views/PlannedWorkoutEditor.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Planner/Views/PlannedWorkoutEditor.swift:226)
  What changed:
  Planned workout editing now preserves each exercise’s existing `progressionStrategy` and `notes` instead of rebuilding edited exercises with hardcoded `.static` progression and dropped notes. Small exercise edits no longer silently erase unrelated planner metadata.

- `Database / P1 / Feed query lacks composite order index`
  Change locations:
  [supabase/migrations/20260416094035_add_workout_posts_created_at_id_index.sql](/Users/dimitarmihaylov/dev/WRKT/supabase/migrations/20260416094035_add_workout_posts_created_at_id_index.sql)
  What changed:
  Added a low-risk Supabase migration for `public.workout_posts (created_at desc, id desc)` so the corrected feed pagination query has a matching composite index as feed volume grows.
  Verification note:
  The SQL was also applied successfully in the remote Supabase project. This item is complete from a schema/index perspective.

### Deferred Plan

- `Train / P1 / Rest timer next-set generation split across multiple owners`
  Status:
  Deferred on purpose due to cross-screen regression risk.
  Detailed staged plan:
  [train-rest-timer-watch-sync-staged-plan-2026-04-16.md](/Users/dimitarmihaylov/dev/WRKT/docs/train-rest-timer-watch-sync-staged-plan-2026-04-16.md)
  Planned implementation approach:
  1. Map every timer-finish entry point across timer manager, live overlay, exercise session screen, store, and notification/widget path.
  2. Add one shared `WorkoutStoreV2` domain method for timer-finish handling without removing old paths yet.
  3. Migrate one caller path at a time onto that shared method.
  4. Verify each path before deleting duplicated behavior.
  Why deferred:
  This fix has higher blast radius than the other Train issues and is safer as a staged migration than a single refactor.

## Supabase Follow-Up

Date: 2026-04-15
Scope: live remote inspection of the linked Supabase project (`wjkokxhdpuoacazaohsa`)

This section is not ranked by navigation feature because these findings cut across Feed, schema management, and deployment process rather than one app tab.

### Confirmed Findings

- `Database / P1 / Feed query lacks composite order index`
  Breaks something: Not yet, but likely later
  What breaks:
  The new feed pagination path is correct, but remote `workout_posts` currently has `created_at`, `user_id`, and `visibility` indexes without a composite `(created_at, id)` index. As feed volume grows, the `created_at desc, id desc` cursor query can become less efficient than it should be.
  Live evidence:
  Remote index inspection showed `workout_posts_created_at_idx`, `workout_posts_user_id_idx`, and `workout_posts_visibility_idx`, but no composite feed-order index.
  Recommendation:
  Fixed: migration added locally and SQL applied remotely.

- `Database / P1 / Local migration history does not match remote project`
  Breaks something: Yes, for schema workflow
  What breaks:
  `supabase db pull --linked --schema public` failed because the remote migration history does not match local files in `supabase/migrations`. That makes future schema pulls, diffing, and migration hygiene less reliable.
  Live evidence:
  Remote pull failed with a migration-history mismatch pointing at `20260415113810`.
  Recommendation:
  Fixed: the empty pulled placeholder migration was removed locally, and remote migration history was repaired so local and remote now both record only `20260416094035`.

- `Database / P2 / Index set shows some unused or low-value entries`
  Breaks something: No immediate user-visible break
  What breaks:
  Nothing directly today, but index growth appears somewhat ad hoc. Several indexes showed zero usage in live stats, which can mean extra write overhead and harder schema hygiene over time.
  Live evidence:
  Examples included `idx_notifications_metadata`, `profiles_is_private_idx`, `post_comments_created_at_idx`, and `profiles_username_idx`.
  Recommendation:
  Review unused indexes deliberately before removing anything. Do not drop based on one snapshot alone.

- `Database / P2 / Supabase CLI version is behind current release`
  Breaks something: Indirectly
  What breaks:
  Inspection workflow was noisier because the installed CLI (`v2.72.7`) differs from current (`v2.90.0`). Some commands/flags no longer matched the latest docs.
  Recommendation:
  Update the CLI to reduce inspection and migration workflow friction.

### Current Assessment

- No obvious live-database emergency showed up.
- Table sizes are still small, including `public.workout_posts`.
- Bloat is low.
- The concrete DB follow-ups still worth scheduling are:
  1. review low-value/unused indexes deliberately
  2. update the Supabase CLI

## Storage Safety Follow-Up

Date: 2026-04-16
Scope: local file storage backup/recovery plus SwiftData persistence safety

### Current Coverage

- `WorkoutStorage / P1 / Completed workout history has partial backup + auto-recovery`
  Covers:
  `workouts_v2.json` only, which contains completed workouts plus PR index.
  How it works:
  Saves are atomic, backups are copied into `WRKT_Storage/Backups`, backup creation is debounced to once every 5 minutes, and only the latest 5 backups are retained.
  Recovery:
  On app startup, if the main workouts file exists but loads empty, `WorkoutStoreV2` attempts to load the most recent non-empty backup and persists it back to the main file.

- `WorkoutStorage / P1 / Runs now have rotating backup + startup auto-recovery`
  Covers:
  `runs_v2.json`.
  How it works:
  Saves are atomic, runs backups are copied into `WRKT_Storage/Backups`, backup creation is debounced independently from workouts, and only the latest 5 runs backups are retained.
  Recovery:
  On app startup, if the main runs file exists but loads empty, `WorkoutStoreV2` attempts to load the most recent non-empty runs backup and persists it back to the main file.

- `SwiftData / P1 / Rebuildable HealthKit operational state now repairs from durable runs`
  Covers:
  `RouteFetchTask`, `MapSnapshotCache`, and `HealthSyncAnchor`.
  How it works:
  On startup, after durable runs load, `WorkoutStoreV2` now asks `HealthKitManager` to repair low-value operational SwiftData state. Missing route tasks are recreated from `Run.needsHistoricalEnrichment`, orphaned route tasks/snapshot cache rows are deleted, stale route tasks are reset, and expected anchor records are recreated if missing.
  Safety property:
  The repair pass does not modify durable workout/run history. At worst it recreates queue/cache state and restarts enrichment work.
  Validation status:
  Normal app launch and single-run `Get Route` refresh were manually validated after the change. Full re-sync validation is still pending on a secondary device.

### Gaps

- `WorkoutStorage / P1 / Current workout does not have equivalent backup recovery`
  Breaks something: Potentially yes
  What breaks:
  `current_workout_v2.json` still uses atomic writes only. It does not yet have rotating backup + startup auto-recovery like `workouts_v2.json` and `runs_v2.json`.

- `SwiftData / P0 / Persisted model changes can break store opening if not backward-compatible`
  Breaks something: Yes
  What breaks:
  Adding a new required field to an existing SwiftData model can prevent `ModelContainer` initialization on devices with older stored rows. The app falls back to limited mode, but persistence is degraded until the schema change is made backward-compatible or explicitly migrated.
  Live evidence:
  `RouteFetchTask.allowAutoPost` was briefly added as a required field and triggered a startup `SwiftDataError` until it was changed to an optional field.
  Recommendation:
  Treat persisted SwiftData model changes as migration-sensitive. New fields should be optional or migration-backed unless explicitly approved and tested against existing stores.

### Best-Practice Direction

- keep additive SwiftData changes backward-compatible by default
- use explicit migration/versioning for breaking persisted-model changes
- expand backup/recovery only if you decide runs/current workout deserve the same protection as completed workouts
- test persisted-model changes against a device/simulator store with pre-existing data before shipping

## Priority Key

- `P0`: breaks core user contract, causes misleading behavior, or risks data loss/corruption
- `P1`: significant correctness or state-flow problem, but with workaround or narrower scope
- `P2`: weaker correctness/perf/maintainability issue, still worth fixing

---

## Train

### P1. PR detection uses wrong rep logic

Breaks something: Yes

What breaks:

- home/train PR display can report wrong PR state for non-10-rep sets
- users can be shown incorrect progress or miss real PRs

Why ranked here:

- user-visible correctness bug
- directly affects trust in workout data

### P1. Rest timer next-set generation split across multiple owners

Breaks something: Yes

What breaks:

- timer completion behavior can diverge between timer, overlay, store, and exercise UI
- auto-add/set-generation behavior becomes hard to predict
- fixes in one place can leave another path wrong

Why ranked here:

- core workout-flow correctness issue

### P1. `removeEntry` leaves empty workout alive

Breaks something: Yes

What breaks:

- user can remove the last entry and still end up with a logically empty active workout
- downstream save/finish/discard behavior can act on invalid session state

Why ranked here:

- state integrity problem in core flow

### P1. `WorkoutStoreV2` writes too often and with detached save behavior

Breaks something: Potentially yes

What breaks:

- persisted state can lag behind rapid edits
- durability policy is unclear at lifecycle boundaries
- backgrounding/termination windows can leave last edits less reliable than expected

Why ranked here:

- more of a durability risk than guaranteed visible bug, but high leverage

### P2. `RestTimerManager` not `@MainActor`

Breaks something: Potentially yes

What breaks:

- UI-coupled timer state has weaker actor-safety guarantees
- race conditions become easier to introduce

Why ranked here:

- architectural safety issue, less obviously user-facing day one

### P2. `BodyweightSetRow` and `TimedSetRow` redraw on timer ticks

Breaks something: Yes, indirectly

What breaks:

- unnecessary rerender churn during active sessions
- potential jank/battery overhead in long workouts

Why ranked here:

- perf issue, not primary correctness issue

---

## Plan

### P0. Planned workout "Start" does not start the planned workout

Breaks something: Yes

What breaks:

- user taps a planned session but enters generic quick-start flow
- planned workout context is lost at launch
- planner intent and workout execution no longer match

Why ranked here:

- direct product-contract failure

### P0. Planned workout completion lifecycle is disconnected

Breaks something: Yes

What breaks:

- completed planned workouts may never be marked complete in planner state
- plan history/status can stay stale even after workout finished
- planner and workout session become inconsistent

Why ranked here:

- same contract failure at finish time

### P1. Planner UI masks stale state instead of fixing source of truth

Breaks something: Yes

What breaks:

- planner status can appear correct in one view while underlying state remains wrong
- later screens/actions can still operate on stale model data

Why ranked here:

- broad consistency problem

### P1. Editing planned workouts can erase notes/progression strategy

Breaks something: Yes

What breaks:

- existing planner metadata is silently lost on edit
- user intent around progression can be reset to defaults

Why ranked here:

- destructive edit bug

### P2. `CalendarMonthView` is overloaded

Breaks something: Not directly, but it causes fragility

What breaks:

- future planner changes are more likely to regress navigation, state, and actions
- ownership is too broad for safe iteration

Why ranked here:

- maintainability problem with real downstream risk

### P2. Split creation / active split ownership is weak

Breaks something: Potentially yes

What breaks:

- multiple active splits or duplicate creation paths can create ambiguous planner state

Why ranked here:

- less visible immediately, but corrupts planner model over time

### P2. Rolling/flexible planner policy is only partially implemented

Breaks something: Yes

What breaks:

- planner behavior for rolling/flexible modes is incomplete or ambiguous
- users can select policy modes whose lifecycle rules are not fully enforced

Why ranked here:

- product-behavior gap, but not as immediately destructive as start/completion bugs

---

## Feed

### P0. Delete "undo" is fake undo

Breaks something: Yes

What breaks:

- restored post is a new post with new identity/timestamp
- likes/comments/history tied to original post are lost or disconnected
- user believes delete was reversed, but it was actually re-created

Why ranked here:

- strong product-contract break

### P0. Feed pagination is structurally unreliable

Breaks something: Yes

What breaks:

- posts can be skipped, duplicated, or surfaced in unstable order across pages
- `hasMore` can be wrong
- merged own/friend feed order is not trustworthy

Why ranked here:

- core feed correctness issue

### P1. Views perform backend writes during render/edit flows

Breaks something: Yes

What breaks:

- scrolling can mutate backend state through map backfill
- edit screen persistence semantics become split and surprising
- repeated mounts can re-trigger hidden work

Why ranked here:

- major ownership and side-effect issue

### P2. Comment count sync is patched through `NotificationCenter`

Breaks something: Yes

What breaks:

- feed comment counts can remain stale until detail screen loads and repairs them
- feed and detail can disagree on counts

Why ranked here:

- currently validated working in the happy path, but ownership remains fragile because it depends on `NotificationCenter` patching instead of one canonical post-state owner

### P1. Cardio refresh in post detail is local only

Breaks something: Yes

What breaks:

- refreshed cardio post data disappears after leaving screen
- feed and detail can disagree permanently

Why ranked here:

- data-refresh behavior not durable

### P2. Realtime ownership is fragmented

Breaks something: Potentially yes

What breaks:

- subscription lifecycle is harder to reason about
- duplicate handling or missed cleanup becomes more likely

Why ranked here:

- mostly architecture, but with real lifecycle risk

### P2. New-post banner eligibility is too broad

Breaks something: Yes

What breaks:

- feed can announce "new posts" that may not actually belong in the user’s feed slice
- banner count can drift from what refresh will actually reveal

Why ranked here:

- narrower than pagination/undo bugs, but still a user-visible correctness issue

### P2. Feed VM lifecycle tied to view mount/unmount

Breaks something: Potentially yes

What breaks:

- subscription and cleanup behavior can vary with navigation/sheet/tab churn

Why ranked here:

- lifecycle fragility, not top user-contract issue

---

## Cardio

### P0. Detail refresh updates store, but detail screen stays stale

Breaks something: Yes

What breaks:

- user taps load/refresh for splits or heart-rate details and visible UI may not update
- refresh appears broken even when data was fetched successfully

Why ranked here:

- direct user-facing correctness bug

### P2. History model hard-capped and view-computed

Breaks something: Not directly, but limits product behavior

What breaks:

- older weekly history is arbitrarily inaccessible in this UI
- large-history rendering remains less efficient than it should be

Why ranked here:

- more design/perf than severe correctness

---

## Profile

### P0. Reset-all warning contradicts actual reset behavior

Breaks something: Yes

What breaks:

- user consent is taken under false data-preservation wording
- cardio/runs can be wiped even though UI says they will be preserved

Why ranked here:

- highest trust issue in reviewed surfaces

### P1. Apple Health disconnect is cosmetic

Breaks something: Yes

What breaks:

- user may think Health connection/access was revoked when only app-side state changed
- disconnect semantics are misleading

Why ranked here:

- user contract issue, but not destructive like reset-all

### P1. `ProfileView` owns too much orchestration

Breaks something: Yes, indirectly

What breaks:

- sync, stats refresh, tutorial flow, and cache updates are easier to regress
- changes in one profile subsection can unintentionally affect others

Why ranked here:

- architecture causing recurring correctness drift

### P1. Profile cache invalidation incomplete

Breaks something: Yes

What breaks:

- weekly progress, milestones, and derived dashboard state can go stale
- refresh behavior depends on partial triggers, not real dependencies

Why ranked here:

- user-visible stale dashboard risk

### P2. PR Collection has empty `NavigationLink`

Breaks something: Yes

What breaks:

- navigation affordance is effectively missing/broken in PR Collection header

Why ranked here:

- small but concrete UI bug

### P2. Barbell metadata lives in view layer

Breaks something: Not directly today

What breaks:

- reward definitions and visuals can drift over time
- reuse across rewards/profile/barbell systems is weaker than it should be

Why ranked here:

- maintainability issue with medium-term risk

### P2. Social preference toggles use stale captured user/profile state

Breaks something: Yes, weakly

What breaks:

- toggle state can lag or feel inconsistent after async profile updates
- failed writes have no strong visible recovery path

Why ranked here:

- smaller settings correctness/UX issue, but grounded in current code

---

## Overall Top 10 Across Reviewed Features

This section reflects the highest-priority issues still remaining after the fixes listed in `Implementation Updates`.

### 1. Train next-set generation ownership split

Priority: `P1`

Breaks something: Yes

Breaks:

- timer/set behavior consistency
- cross-screen workout behavior

### 2. Profile Apple Health disconnect semantics are still misleading

Priority: `P1`

Breaks something: Yes

Breaks:

- disconnect wording and behavior contract
- user mental model of Health access state

### 3. Train write frequency and detached-save durability policy

Priority: `P1`

Breaks something: Yes

Breaks:

- persistence timing clarity
- lifecycle-boundary durability confidence

### 4. Feed realtime ownership / eligibility cleanup

Priority: `P1`

Breaks something: Potentially yes

Breaks:

- realtime banner/count semantics can still drift
- subscription ownership remains more fragmented than ideal

### 5. Profile cache invalidation and orchestration follow-through

Priority: `P1`

Breaks something: Potentially yes

Breaks:

- some profile triggers still remain view-level
- staged refactor still needs follow-through before ownership is fully clean

### 6. Supabase low-value index review / CLI update

Priority: `P2`

Breaks something: No immediate user-visible break

Breaks:

- schema hygiene and tooling friction

### 7. Feed comment-count ownership cleanup

Priority: `P2`

Breaks something: Potentially yes

Breaks:

- ownership pattern still depends on `NotificationCenter`
- lower urgency after in-app add/delete comment validation passed

### 8. Profile social preference toggles use stale captured user/profile state

Priority: `P2`

Breaks something: Yes, weakly

Breaks:

- toggle state can lag or feel inconsistent after async profile updates
- failed writes have no strong visible recovery path

### 9. PR Collection has empty `NavigationLink`

Priority: `P2`

Breaks something: Yes

Breaks:

- navigation affordance is effectively missing/broken in PR Collection header

### 10. Barbell metadata lives in view layer

Priority: `P2`

Breaks something: Not directly today

Breaks:

- reward definitions and visuals can drift over time
- reuse across rewards/profile/barbell systems is weaker than it should be

## Bottom Line

Per-feature ranked list is better for deciding what to do next.

By-file roadmap is better once you choose the target.

If you want the fastest remaining path with real user impact, I would start with:

1. Profile refactor follow-through, if stale-profile cases still show up in testing
2. Train next-set ownership only if real behavioral drift shows up
3. Supabase low-value index review / CLI update
4. Feed comment-count ownership cleanup only if it starts failing in real use
5. Profile/settings cleanup items after that
