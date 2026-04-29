# Cardio View Deep Dive

Date: 2026-04-14
Scope: `CardioView`, `CardioDetailView`, `CardioCharts`, `HealthKitManager`, cardio `Run` model flow in `WorkoutStoreV2`

## Executive Summary

Cardio View has strong UI ambition, but the underlying model is narrower and less coherent than the rest of the HealthKit pipeline.

Main problems:

1. The screen only supports three cardio types even though the import/store pipeline supports many more.
2. `CardioDetailView` refresh actions mutate the global store, but most of the detail UI still renders a stale value snapshot.
3. Route fetching logic is duplicated across `HealthKitManager` and `CardioDetailView`, creating multiple competing write paths.
4. Full resync only queues detailed route enrichment for the first 20 imported workouts, so older history stays permanently shallow unless manually opened.
5. The cardio UI hard-caps visible history to six weeks and recomputes/sorts repeatedly in-view instead of exposing a clearer data model.

The recurring issue is ownership drift again: HealthKit sync owns one enrichment path, detail view owns another, and the UI reads from a mixture of captured values and global store state.

## Findings

### 1. Cardio View drops most valid cardio activities

Severity: High

`CardioView` defines only three visible activity buckets: running, walking, and cycling ([Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:23)). Its primary filter checks only those three raw strings and otherwise defaults unknown distance workouts to running ([Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:77)).

But the import/store layer clearly supports a broader cardio universe:

- `WorkoutStoreV2.validRuns` explicitly preserves zero-distance cardio like elliptical, stair climbing, rowing, HIIT, dance, kickboxing, and boxing ([Features/WorkoutSession/Services/WorkoutStoreV2.swift](/Users/dimitarmihaylov/dev/WRKT/Features/WorkoutSession/Services/WorkoutStoreV2.swift:26)).
- `HealthKitManager.workoutActivityTypeName(...)` imports hiking, swimming, rowing, elliptical, stair climbing, dance, mixed cardio, cross training, recovery, and more ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1911)).

Result:

- valid cardio workouts can exist in storage but never appear in Cardio View
- zero-distance but legitimate cardio sessions have no surface here
- the UI model is narrower than the data model, so cardio analytics are incomplete by design

Recommendation:

- Replace the hard-coded 3-type enum with either:
  - a broader supported-type model aligned with import semantics
  - or an "All cardio" view plus optional type chips derived from actual stored activity types
- Do not default unsupported types into the running bucket.

### 2. Detail refresh updates store, but the screen mostly stays stale

Severity: High

`CardioDetailView` receives a value `run: Run` and passes that immutable snapshot into its tabs: `OverviewTab(run: run)`, `SplitsTab(run: run)`, and `HeartRateTab(run: run)` ([Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:62)). Both `SplitsTab` and `HeartRateTab` expose refresh/load buttons that call `HealthKitManager.shared.refreshDetailedDataForRun(runId: run.id)` ([Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:493), [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:510), [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:532), [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:584)).

That refresh path writes updated route/splits back into `WorkoutStoreV2` ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1789), [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1806)). But those tabs are not observing the refreshed store item. They still render the old `run` value passed at navigation time.

So the user can tap:

- "Load Splits"
- "Refresh"
- "Load Details"

and the backing store updates successfully, but the visible tab may not update until the screen is recreated.

Recommendation:

- `CardioDetailView` should own a live observable cardio-detail model, or at minimum derive a `currentRun` from the store and pass that through all sections.
- The invariant should be: if refresh mutates cardio detail state, the active detail screen must render the refreshed data immediately.

### 3. Route/data enrichment logic is duplicated in too many places

Severity: Medium-High

HealthKit already has a dedicated route-fetch queue and a dedicated refresh path:

- background enrichment queue in `processRouteFetchQueue(...)` ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1106))
- foreground detailed refresh in `refreshDetailedDataForRun(...)` ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1789))

But `CardioDetailView` duplicates the same responsibilities again:

- `generateMapSnapshotAndShare()` manually retries failed route tasks, fetches route/route-with-HR, and writes directly into `AppDependencies.shared.workoutStore` ([Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:253))
- `fetchRouteOnly()` repeats similar fetch-and-write logic ([Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:320))

Problems:

- same enrichment logic exists in multiple places
- different callers update different subsets of fields
- detail view reaches into global singleton dependencies instead of injected ownership
- harder to reason about retry semantics and idempotency

Recommendation:

- Consolidate all cardio enrichment behind one service/use-case API.
- Detail view should request an action like "ensureRouteAvailable" or "refreshDetailedMetrics", not perform HealthKit orchestration itself.

### 4. Full resync leaves older cardio history under-enriched

Severity: Medium

`forceFullResync()` imports all workouts, but only queues route fetching for `Array(added.prefix(20))` after the full import ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:560), [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:667)).

That means:

- recent workouts get route/splits/dynamics enrichment
- older workouts are imported, but usually remain shallow records
- users must manually open an old workout to trigger deeper enrichment paths

If the product intent is "full resync repairs cardio history," current behavior misses that mark.

Recommendation:

- Either queue all imported cardio workouts with bounded/background processing, or explicitly document full resync as "import summaries first, enrich recent history only."
- Current name and UX imply more completeness than implementation provides.

### 5. Cardio history is arbitrarily capped and view-computed

Severity: Medium

`CardioView` hard-caps visible week history to six weeks via `maxWeeksHistory = 5` and `Array(0...maxWeeksHistory)` ([Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:140)). The view also repeatedly recomputes filtered/sorted arrays in-place:

- `cardioRuns`
- `runsForWeek(offset:)`
- `selectedWeekRuns.sorted(...)`
- `prefix(10)` for cards

all from inside the render layer ([Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:77), [Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:93), [Features/Health/Views/CardioView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioView.swift:301)).

This is not catastrophic with small histories, but it is the wrong shape:

- arbitrary product cap baked into UI
- no explicit "older history" model
- repeated sorting/filtering in the view tree

Recommendation:

- Move cardio grouping/filtering into a dedicated model/view model.
- Expose derived sections like:
  - available activity types
  - selected week summary
  - paged history slices
  - recent visible runs
- If six weeks is intentional, make it a product rule, not just a view constant.

### 6. Source-of-truth usage is inconsistent inside one detail screen

Severity: Medium

`CardioDetailView` already knows its captured `run` can become stale. It defines `latestRun` by reading from `AppDependencies.shared.workoutStore` ([Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:246)). It also keeps local override state for map rendering through `localRouteWithHR` / `localRoute` ([Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:29), [Features/Health/Views/CardioDetailView.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Views/CardioDetailView.swift:181)).

So within one screen:

- map may use local override state
- share flow uses `latestRun`
- overview/splits/heart-rate tabs use original `run`

That creates inconsistent UI where different subtrees may refer to different versions of the same workout.

Recommendation:

- One screen should have one current cardio-detail state object.
- Avoid mixing:
  - initial navigation snapshot
  - singleton store lookup
  - local patch state

### 7. Delete flow is narrower than the rest of cardio lifecycle

Severity: Medium-Low

Deleting a cardio workout removes the HealthKit workout and the local `Run` record ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1005)). That is straightforward, but this cardio subsystem also has:

- route fetch tasks
- auto-post for runs after route enrichment

from the broader pipeline ([Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1204)).

The delete path shown here does not obviously clean up downstream cardio artifacts beyond the local run record.

This may be intentional, but if not, deletion semantics are incomplete.

Recommendation:

- Decide what "delete workout" means across the app:
  - HealthKit only
  - local cardio history only
  - or all derived app artifacts tied to that run
- Then make the delete path enforce that contract.

## Efficiency / Simplicity Opportunities

1. Expand cardio type modeling to match HealthKit import capability.
2. Replace detail-screen singleton reads with an injected observable detail model.
3. Centralize all route/splits enrichment behind one cardio enrichment service.
4. Stop passing stale `Run` snapshots into tabs that have refresh actions.
5. Precompute week slices and recent lists once per selected type/week.
6. Clarify whether resync is summary-only or full enrichment.

## Suggested Refactor Order

1. Fix stale detail rendering first because it creates obvious "refresh did nothing" behavior.
2. Unify route enrichment ownership so there is only one write path.
3. Expand cardio type support so the UI matches the imported data model.
4. Then clean up history derivation and product rules around older weeks/history depth.

## Open Questions

1. Is Cardio View intentionally only for run/walk/cycle, or is it meant to become the general cardio hub?
2. Should "Force Full Re-sync" enrich detailed route/splits data for all historical cardio workouts, or just import summaries?
3. When deleting a cardio workout, should any derived social post also be removed or left intact?

## Bottom Line

Cardio View looks polished, but the data contract is not clean. Biggest issue is stale detail rendering after refresh. Biggest product gap is that the UI only understands three cardio types while the rest of the app imports far more.

---

## Review

Date reviewed: 2026-04-15

### Verified as accurate

**Finding 2 -- Detail refresh updates store but screen stays stale**: Confirmed. `CardioDetailView` receives `let run: Run` as a struct value. All tabs (`OverviewTab`, `SplitsTab`, `HeartRateTab`) receive this same captured snapshot. `SplitsChart(splits: run.splits ?? [])` at `CardioDetailView.swift:525` reads from the original value. `refreshDetailedDataForRun` writes to the store via `store.updateRun(updated)` but nothing in the detail view observes the store for that run. The screen does not update.

**Finding 4 -- Full resync only enriches first 20 workouts**: Confirmed. `HealthKitManager.swift:668` passes `Array(added.prefix(20))` to `queueRouteFetching`.

**Finding 5 -- History capped at 6 weeks, view-computed**: Confirmed. `CardioView.swift:141` declares `private let maxWeeksHistory = 5`, and `Array(0...maxWeeksHistory)` at line 145 produces 6 offsets (0 through 5). Filtering and sorting happen inline in the view body.

**Finding 6 -- Inconsistent source of truth within one screen**: Confirmed. `CardioDetailView.swift:247-248` defines a `latestRun` computed property that reads from `AppDependencies.shared.workoutStore`. The share/map flow uses `latestRun`. Tabs use the original `run` snapshot. Both paths can refer to different versions of the same workout simultaneously.

### Minor clarification

**Finding 5 -- "six weeks"**: The doc text says "six weeks via `maxWeeksHistory = 5`". The constant is named 5 but produces 6 items via `0...maxWeeksHistory`. This is not wrong -- the comment at `CardioView.swift:141` itself says `// 0-5 = 6 weeks total`. The doc is accurate.

### File references

All file paths and types referenced are valid and exist.
