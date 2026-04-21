# Startup Performance Remediation Plan

Date: 2026-04-21
Scope: Cold app launch and first interactive seconds after foreground activation
Status: Investigation complete, implementation not started

## Summary

The app is doing too much eager work during startup. The log from `logs_appstart.rtf` shows three main contributors:

1. Repeated `HealthKit` sync and route-enrichment work during launch.
2. Repeated route-permission retries and route fetch failures for historical runs.
3. Additional eager startup work from rewards, social feed, realtime, and repository bootstrap running at the same time.

This is enough to plausibly explain the reported "laggy on first start" behavior.

The strongest signal is the route-enrichment path:

- `fetchRouteLocations: HKSampleQuery returned 0 route objects` appears 304 times during startup.
- `Requesting authorization for 14 data types...` appears 76 times during startup.
- `System gesture gate timed out` appears once, which is consistent with the main thread or UI pipeline being starved by startup work.

## Key Findings

### 1. HealthKit sync is triggered from multiple startup paths

The same incremental workout sync can run from multiple places:

- [App/WRKTApp.swift](/Users/dimitarmihaylov/dev/WRKT/App/WRKTApp.swift:68)
- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:374)
- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:462)

This means cold launch can overlap:

- app-init sync
- launch-handler sync
- scene-active sync

That is unnecessary and increases the chance that route queues, import work, and rewards validation all pile up at once.

Streak validation is triggered even more aggressively. On a single cold launch it fires from:

- [App/AppShellView.swift:372](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:372) (scene active branch)
- [App/AppShellView.swift:378](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:378) (scene active, after sync)
- [App/AppShellView.swift:407](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:407) (`handleInitialAppear`)
- [App/AppShellView.swift:460](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:460) (`handleAppLaunch`)

`syncWorkoutsIncremental` has a `guard !isSyncing else { return }` at [HealthKitManager.swift:369](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:369) so second and third callers no-op cleanly. `validateWeeklyStreakOnAppear` has no equivalent guard. All four calls execute and each walks every week since goal creation ([StreakResult.swift:818-843](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:818)).

Side note: the `App/WRKTApp.swift:68` sync runs inside `WRKTApp.init`, before `modelContext` is configured. It hits the `guard let context = modelContext else { return }` at [HealthKitManager.swift:365](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:365) and silently no-ops, so the "early" sync is dead code that still pays for auth checks and scheduler noise.

#### Proposed Fix

Reduce to one sync owner and one streak validation owner on cold launch. Keep `scenePhase == .active` behaviour for resume-from-background.

**Change A: delete the app-init sync in [App/WRKTApp.swift:68-74](/Users/dimitarmihaylov/dev/WRKT/App/WRKTApp.swift:68).** Dead code: `modelContext` is nil at `init` time.

**Change B: gate the `scenePhase == .active` sync behind a cold-launch flag in [App/AppShellView.swift:360-381](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:360).** Add `@State private var hasCompletedColdLaunch = false` and set it to `true` at the end of `handleAppLaunch`. Early-return from the `.active` branch when the flag is false:

```swift
} else if newPhase == .active {
    UserDefaults.standard.markActive()
    inviteCoordinator.startListening()

    // Cold launch is owned by handleAppLaunch; only run on resume-from-background.
    guard hasCompletedColdLaunch else { return }

    Task {
        await badgeManager.startRealtimeSubscriptions()
        if healthKit.connectionState == .connected {
            try? await healthKit.syncWorkoutsIncremental()
            RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)
        }
    }
}
```

**Change C: delete the streak validation in `handleInitialAppear` ([App/AppShellView.swift:407](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:407)).** `handleAppLaunch` already validates on cold launch. `handleInitialAppear` runs earlier in the same cold launch on the main actor and `validateWeeklyStreakOnAppear` walks every week since goal creation ([StreakResult.swift:818-843](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:818)) — main-thread cost scales with goal age.

**Change D: reorder `handleAppLaunch` so streak validation runs _after_ the sync.** Current order at [AppShellView.swift:459-466](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:459) is `bootstrap → validate → sync`. The pre-sync validation sees pre-sync workouts: if the user opens the app right after a Watch workout, the streak reflects the old state until the next foreground resume. Currently path C (`.active` branch, [AppShellView.swift:378](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:378)) papers over this by re-validating after the sync. Once we delete path C on cold launch we need `handleAppLaunch` to own the post-sync validation too:

```swift
private func handleAppLaunch() async {
    dependencies.configure(with: modelContext)
    await dependencies.bootstrap()

    if healthKit.connectionState == .connected {
        await healthKit.syncWorkoutsIncremental()
        await healthKit.syncExerciseTimeIncremental()
    }

    // Validate AFTER sync so new Watch workouts are reflected in the streak
    RewardsEngine.shared.validateWeeklyStreakOnAppear(store: store)

    // …remainder of handleAppLaunch unchanged…

    hasCompletedColdLaunch = true
}
```

**Result:** exactly one `syncWorkoutsIncremental` call and one `validateWeeklyStreakOnAppear` call on cold launch, and the validation sees the freshest data. Background-to-foreground still syncs and validates via the `.active` branch.

#### Behaviour impact

What changes:
- Cold launch: HK sync runs once (post-bootstrap), not up to three times.
- Streak validation: once, not four times.
- Launch logs drop significantly; overlapping auth checks and scheduler contention reduced.

What stays the same:
- Background-to-foreground still syncs and validates.
- HealthKit observer at [HealthKitManager.swift:245](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:245) still catches new watch workouts independently of launch sync.
- Manual sync paths (`ConnectionsView.swift:107`, `WorkoutStoreV2.swift:1188`, `CardioView.swift:387/434/455`) unaffected.
- `BGProcessingTask` path ([HealthKitManager.swift:2485](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:2485)) unaffected.

#### Risks

- If `handleAppLaunch` fails before sync (bootstrap timeout, `modelContext` nil, unhandled throw), cold launch performs zero sync. Currently the redundant paths A/C provide accidental fallback. Mitigation: wrap the sync block in a `defer`-style error log so skipped syncs surface in logs.
- `hasCompletedColdLaunch` must survive scene transitions. SwiftUI `@State` on the root `AppShellView` persists across `scenePhase` changes within the same process, so this is safe. Edge case: if the user backgrounds the app _during_ `handleAppLaunch` (before the flag is set) and foregrounds before it completes, the `.active` branch will early-return and skip its sync. `handleAppLaunch`'s own sync still runs, so this is acceptable.
- Streak validation now runs _after_ sync inside `handleAppLaunch`. Cold launch shows the pre-sync streak briefly until the sync completes. In practice the UI driven by the streak (rewards, home card) loads after the same async chain, so this is not user-visible on a modern device. Verify on a cold launch with a pending Watch workout.

#### Test Plan

Functional:
1. Delete app, reinstall, cold launch. Logs should show exactly one sync start and one `Streak validation STARTED`.
2. Kill app (not delete), cold launch. Same expectation.
3. Complete a workout on Watch, wait for Watch-to-iPhone HK sync, then cold launch. Workout appears in Cardio tab via the observer path. Streak reflects the new workout — this is the regression guard for Change D.
4. Cold launch, background 30s, foreground. `.active` branch fires sync and validation once.
5. Cold launch, background, complete Watch workout while backgrounded, foreground. Sync picks up the new workout and streak updates.
6. HK disconnected: cold launch produces no sync logs.
7. Offline cold launch: sync attempts, fails gracefully, no crash.
8. Background the app during `handleAppLaunch` (quickly swipe up during first second of launch), foreground. Verify sync still completes and the `.active` branch does not double-sync.

Instrumentation:
- Add `os_signpost` around `syncWorkoutsIncremental` in `handleAppLaunch` and verify the signpost appears exactly once in a Time Profiler trace of cold launch.
- Count `Streak validation STARTED` occurrences in the startup log and verify it equals 1.

### 2. Route enrichment is too eager and too retry-heavy at launch

The route queue is processed aggressively:

- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1308)
- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1430)

The route fetch logic is also expensive when route data is missing:

- first association predicate
- then time-window fallback
- then re-request `HealthKit` authorization
- then retry both queries

Relevant code:

- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1449)
- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1494)

This is likely the single biggest startup cost.

### 3. Route enrichment appears to duplicate route lookup work

Detailed run enrichment calls `fetchRouteWithHeartRate`, which itself calls `fetchRoute`, and then can call `fetchRoute` again in the fallback path.

Relevant code:

- [Features/Health/Services/HealthKitManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:2008)

When route permissions are missing or route series are unavailable, this multiplies already-expensive failure work.

### 4. Weekly streak validation is repeated during startup

Historical streak rebuild runs more than once during launch flow. The expensive portion walks back through historical weeks:

- [Features/Rewards/Models/StreakResult.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Rewards/Models/StreakResult.swift:818)

Launch paths also trigger validation in multiple places:

- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:372)
- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:460)

This is not the main problem, but it adds avoidable load.

### 5. Social feed work is eager on startup

Friend activity fetch requests the merged feed immediately and scans up to 50 posts:

- [Features/Home/ViewModels/HomeViewModel.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Home/ViewModels/HomeViewModel.swift:265)

This is probably secondary compared with `HealthKit`, but it still contributes startup pressure.

### 6. Bootstrap waits for full exercise catalog before proceeding

App dependencies bootstrap waits for the full exercise catalog:

- [Core/Dependencies/AppDependencies.swift](/Users/dimitarmihaylov/dev/WRKT/Core/Dependencies/AppDependencies.swift:188)

This can be acceptable if the work is truly off the critical UI path. If not, it contributes to startup latency.

### 7. Realtime subscriptions are started from overlapping lifecycle paths

Realtime startup is triggered from:

- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:369)
- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:484)

The implementation always stops old subscriptions before starting again:

- [Features/Social/Services/NotificationBadgeManager.swift](/Users/dimitarmihaylov/dev/WRKT/Features/Social/Services/NotificationBadgeManager.swift:74)

This adds noise and work during startup, though it is probably not the primary cause of lag.

## What Looks Normal

- Dependency initialization and basic service configuration.
- Push registration.
- Image cache setup.
- WatchConnectivity activation.
- One incremental `HealthKit` sync after launch.
- One realtime subscription start when the app becomes interactive.

## What Does Not Look Normal

- 304 missing-route logs during startup.
- 76 repeated authorization requests during startup.
- Multiple overlapping `HealthKit` sync triggers.
- Historical route queue processing while the app is still becoming interactive.
- Repeated streak validation during the same startup.

## Most Likely Root Cause Ranking

### P0

Historical `HealthKit` route enrichment is running too aggressively during startup, with expensive retries and authorization re-requests when route data is missing.

### P1

Incremental `HealthKit` sync is triggered from multiple startup paths and likely overlaps with route work.

### P2

Streak validation, feed fetch, and realtime setup are adding secondary startup load and contention.

## Remediation Goals

1. Make the app interactive first.
2. Run only one authoritative startup sync path.
3. Defer historical enrichment until after first render or explicit user entry into cardio surfaces.
4. Stop repeated `HealthKit` authorization loops for missing route data.
5. Reduce log spam so real regressions remain visible.

## Proposed Fix Plan

## Phase 1: Stop Duplicate Launch Work

Goal: ensure each startup subsystem has one clear owner and no cold-start overlap.

### Implementation Spec

#### Workout Sync Ownership

Use two owners only:

1. Cold launch owner:
   - [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:455)
   - `handleAppLaunch()`

2. Resume-from-background owner:
   - [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:360)
   - scene phase `.active` handler

Remove launch-triggered sync from:

- [App/WRKTApp.swift](/Users/dimitarmihaylov/dev/WRKT/App/WRKTApp.swift:68)

Reason:

- `WRKTApp.init()` too early.
- `handleAppLaunch()` already owns dependency configuration and bootstrap.
- Sync after dependency setup safer and easier coordinate.

#### Required Lifecycle Guards

Do not rely only on removing one call site. Add explicit guards so cold launch and foreground activation cannot both run sync during same startup window.

Need state like:

1. `isPerformingInitialLaunch`
2. `didCompleteInitialLaunchSync`
3. optional `lastForegroundSyncAt`

Required behavior:

1. During cold launch:
   - `.active` handler must not trigger foreground sync if initial launch path still running.
2. After cold launch completes:
   - future real foreground resumes may trigger sync.
3. If app becomes active repeatedly in quick succession:
   - debounce or min-interval guard should prevent redundant sync bursts.

#### Cold Launch Order

Cold launch path should run in this order:

1. configure dependencies
2. bootstrap dependencies
3. sync workouts
4. sync exercise time
5. validate weekly streak
6. start realtime / invite listening / other non-critical launch work

Reason:

- streak validation before sync can use stale workout data
- launching after a new Watch workout must validate against freshly imported state

#### Weekly Streak Ownership

Use one cold-start owner only.

Preferred owner:

- [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:455)
  inside `handleAppLaunch()`

Remove duplicate cold-start validation from other startup paths if they exist only to support first launch correctness.

Foreground resume can keep its own validation only if:

1. it is truly needed for app-resume correctness
2. it is blocked during initial launch window

#### Realtime Ownership

Use same ownership model:

1. cold launch owner in `handleAppLaunch()`
2. resume owner in scene-phase `.active`
3. `.active` path must no-op during initial launch window

This avoids:

- stop/start churn
- duplicate badge refresh
- duplicate subscription setup during cold start

### Concrete Changes

1. Delete startup `HealthKit` sync from [App/WRKTApp.swift](/Users/dimitarmihaylov/dev/WRKT/App/WRKTApp.swift:68)
2. Keep cold-start sync in [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:462)
3. Keep foreground sync in [App/AppShellView.swift](/Users/dimitarmihaylov/dev/WRKT/App/AppShellView.swift:374), but gate it so it only runs on true resume
4. Move cold-start streak validation to after launch sync inside `handleAppLaunch()`
5. Consolidate cold-start realtime startup under `handleAppLaunch()`

### Acceptance Criteria

- Cold launch logs exactly one startup `syncWorkoutsIncremental()` path.
- Cold launch does not also trigger scene-phase foreground sync.
- Cold launch shows one post-sync streak validation pass.
- Cold launch shows one realtime startup path.
- Resume from background still syncs once.
- Watch workout import after resume still works.

### Verification Checklist

1. Cold launch app from terminated state.
   - expect one launch sync
   - expect no duplicate `.active` sync
2. Send app to background, wait, return to foreground.
   - expect one foreground sync
3. Lock/unlock quickly several times.
   - expect no sync storm
4. Complete Apple Watch workout while app suspended, then reopen app.
   - expect resume sync to import workout

## Phase 2: Defer Historical Route Enrichment

Goal: stop historical cardio enrichment from competing with first render.

### Changes

1. Do not drain the historical route queue during cold launch.
2. Only enqueue new workouts discovered during sync for immediate enrichment.
3. Process historical route tasks later:
   - after first frame plus delay
   - on charger / idle
   - when user enters cardio
   - via background task
4. Cap startup route processing to a very small budget, or zero.

### Acceptance Criteria

- No large `Processing N route fetch tasks` bursts during first launch seconds.
- Historical route queue can still drain eventually, but off the critical path.

## Phase 3: Fix Route Authorization Retry Behavior

Goal: prevent repeated authorization churn when route data is unavailable.

### Changes

1. Do not re-request authorization per workout route failure.
2. Cache route-authorization state separately from general workout authorization.
3. If route access is missing, mark that once and stop retrying for every task.
4. Distinguish:
   - no route exists
   - route exists but permission missing
   - route query failed transiently
5. Add backoff so repeated failures do not re-run immediately on startup.

### Acceptance Criteria

- `Requesting authorization for 14 data types...` does not appear dozens of times on launch.
- Missing route permission produces one actionable warning, not hundreds.

## Phase 4: Eliminate Duplicate Route Fetch Work

Goal: avoid multiple route queries for the same workout during one enrichment pass.

### Changes

1. Refactor detailed run enrichment so route lookup happens once per workout.
2. Reuse the fetched route for:
   - plain route
   - route-with-heart-rate correlation
   - any other derived cardio enrichment

### Acceptance Criteria

- One enrichment pass performs one route retrieval sequence per workout.

## Phase 5: Push Non-Critical Startup Work Later

Goal: reserve startup budget for visible UI readiness.

### Candidates to defer

1. Friend activity feed fetch.
2. Historical streak rebuild if not needed immediately.
3. Pattern-analysis refresh.
4. Any historical stats reindex work not required for first screen render.

### Acceptance Criteria

- Home and Plan can render before social/feed helper work completes.

## Instrumentation Plan

Add lightweight timing around these operations:

1. App cold start to first interactive frame.
2. `AppDependencies.bootstrap()`.
3. `syncWorkoutsIncremental()`.
4. `syncExerciseTimeIncremental()`.
5. `processRouteFetchQueue()`.
6. `validateWeeklyStreakOnAppear(...)`.
7. `getFriendActivityToday()`.

Log each with:

- start timestamp
- end timestamp
- duration ms
- work counts:
  - workouts added
  - route tasks processed
  - posts fetched
  - weeks scanned

## Validation Plan

## Functional Validation

1. Cold launch with `HealthKit` fully authorized.
2. Cold launch with route permission missing.
3. Cold launch with many historical route tasks pending.
4. Launch after completing a watch workout.
5. Launch offline.

## Performance Validation

Measure before and after:

1. Time to first interactive frame.
2. Main-thread utilization during first 10 seconds.
3. Number of startup `HealthKit` authorization requests.
4. Number of route-query failures during first 10 seconds.
5. Number of concurrent startup tasks.

Use:

- Instruments Time Profiler
- SwiftUI / Main Thread checks
- os_signpost or equivalent timing logs

## Suggested Success Metrics

These are reasonable target metrics for the fix:

- Startup `HealthKit` authorization requests: from 76 to <= 1
- Startup missing-route logs: from 304 to < 10
- Startup sync owners: from multiple to exactly 1
- Route queue tasks processed during critical launch window: from dozens to 0-2
- No `System gesture gate timed out` during normal cold launch

## Risks

1. Deferring route enrichment may delay map availability for older runs.
2. Reducing startup sync eagerness could delay watch-workout import if ownership is reassigned incorrectly.
3. Moving streak validation later could temporarily show stale streak UI if not sequenced carefully.

## Risk Mitigations

1. Keep immediate enrichment for newly added workouts only.
2. Provide on-demand route retry when user opens a run detail.
3. Keep one deterministic streak validation owner on cold launch.

## Recommended Implementation Order

1. Remove duplicate launch sync / validation / realtime owners.
2. Stop per-workout authorization re-requests for route failures.
3. Defer historical route queue off cold launch.
4. Deduplicate route fetch inside enrichment.
5. Defer feed and secondary social work if startup is still heavy.

## Definition of Done

This issue is resolved when:

1. Cold launch is visibly smoother.
2. There is one authoritative startup sync path.
3. Historical route enrichment no longer floods startup logs.
4. Route permission issues do not trigger repeated authorization loops.
5. Startup logs are short enough that new regressions are obvious.

## Appendix: Evidence Snapshot

From the investigated startup log:

- `fetchRouteLocations: HKSampleQuery returned 0 route objects`: 304 times
- `Requesting authorization for 14 data types...`: 76 times
- `Streak validation STARTED`: 2 times
- `Fetching friend activity for user`: 1 time
- HealthKit launch sync markers: 2 distinct startup sync triggers logged
- `System gesture gate timed out`: 1 time

This points to startup overload, not just verbose logging.
