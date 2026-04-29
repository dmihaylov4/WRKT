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

### 2. Route enrichment is too eager at launch

`processRouteFetchQueue(limit: 10)` at [HealthKitManager.swift:1308](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1308) pulls from the `RouteFetchTask` SwiftData table ordered by priority + date and processes up to 10 **pending** tasks — **including pending tasks left over from previous sessions**. Every call path that kicks the queue during cold launch therefore pays for historical backlog, not just current-session work.

Call paths that kick the queue during a cold launch:

1. End of `queueRouteFetching` after an incremental sync completes ([HealthKitManager.swift:1252-1254](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1252)). The queued tasks are correctly scoped to newly added workouts, but the subsequent `processRouteFetchQueue()` call is unscoped.
2. `workoutRouteObserver` callback ([HealthKitManager.swift:298-305](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:298)). `HKObserverQuery` does **not** fire purely on registration, but it does fire shortly after registration whenever HealthKit has fresh route samples it has not yet notified this app about. On cold launch that is effectively every launch after a Watch run.
3. `workoutObserver` callback ([HealthKitManager.swift:245](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:245)) → `syncWorkoutsIncremental` → back to path 1. Transitively handled by Change A (path 1 is already constrained by the session-scoped filter).
4. `repairHealthKitOperationalState` ([HealthKitManager.swift:1020-1023](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1020)) kicks the queue whenever it resets stale/stuck tasks. Transitively handled by Change A (the kick now hits the session-scoped filter during the launch window, so only fresh tasks run).

`processRouteFetchQueueUntilEmpty(batchLimit: 20)` at [HealthKitManager.swift:1430](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1430) is **not** triggered by cold launch. Its only caller is `forceFullResync:672`, which only runs from `HealthAuthSheet.swift:136` and `CardioView.swift:464` (user-initiated). Ignore this path for launch-performance purposes.

Per-task work is expensive when the route is missing: `fetchRoute` ([HealthKitManager.swift:1449](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1449)) issues an association-predicate query, a time-window fallback query, re-requests HK authorization, then retries both queries. That per-task cost is **Finding 3's domain** and is addressed there. This finding addresses only _how many tasks_ the launch window processes.

From the log: 304 missing-route messages and 76 auth prompts during startup. With `limit: 10` per queue call and roughly 8 missing-route messages per workout (see Finding 3), the log implies ~38 historical pending tasks were processed across roughly 4 queue invocations during cold launch.

#### Proposed Fix

Goal: `processRouteFetchQueue` must not process pre-session pending tasks during the cold-launch window. Newly added workouts from this launch's sync remain eligible for immediate enrichment.

##### Define the launch window

Reuse the flag introduced by Finding 1. Add two flags that define a session-scoped launch window:

```swift
// HealthKitManager — stored on the @MainActor-isolated instance.
// Read from @MainActor contexts only. Non-MainActor callers must
// hop via `await MainActor.run { ... }` before reading.
@MainActor var processStartedAt: Date = .now
@MainActor var launchWindowEndsAt: Date = .distantFuture   // set when cold launch done
```

On `didCompleteInitialLaunch = true` inside `handleAppLaunch` (per Finding 1), set `launchWindowEndsAt = .now.addingTimeInterval(5)`. The 5s buffer swallows the observer callbacks that trail bootstrap.

`isInLaunchWindow` is simply `Date.now < launchWindowEndsAt`.

Naming: `processStartedAt` rather than `sessionStartedAt` to avoid collision with the Supabase / auth "session" vocabulary already used in this codebase. It is the time the current process began, nothing more.

Actor-isolation note: both flags live on `HealthKitManager` (already `@MainActor`). Every read in the changes below is on `@MainActor` code, so no lock is required. If a future caller is nonisolated, add a `MainActor.run` hop rather than making these `nonisolated(unsafe)`.

##### Change A: filter `processRouteFetchQueue` during the launch window

Change the descriptor at [HealthKitManager.swift:1327-1330](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1327) so that during the launch window only session-scoped tasks are processed:

```swift
@MainActor
func processRouteFetchQueue(limit: Int = 10) async {
    guard let context = modelContext else { return }

    // ... stale-fetching reset unchanged ...

    // `self` is @MainActor so these reads are race-free; no lock needed.
    let processStart = self.processStartedAt
    let inLaunchWindow = Date.now < self.launchWindowEndsAt

    // Capture the Date into a local before the #Predicate so the macro
    // captures the value, not `self`. `#Predicate` currently refuses to
    // capture arbitrary properties of enclosing types; a plain `let`
    // is the safe form.
    let cutoff = processStart

    let descriptor: FetchDescriptor<RouteFetchTask> = {
        if inLaunchWindow {
            return FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate { $0.status == "pending" && $0.createdAt >= cutoff },
                sortBy: [SortDescriptor(\.priority), SortDescriptor(\.workoutDate, order: .reverse)]
            )
        } else {
            return FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate { $0.status == "pending" },
                sortBy: [SortDescriptor(\.priority), SortDescriptor(\.workoutDate, order: .reverse)]
            )
        }
    }()

    guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
        AppLogger.debug(
            "No pending route fetch tasks (launchWindow=\(inLaunchWindow))",
            category: AppLogger.health
        )
        return
    }

    // ... rest unchanged ...
}
```

`RouteFetchTask.createdAt` already exists (referenced at [HealthKitManager.swift:1369](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1369)), so no schema change is required.

##### Change B: skip observer-triggered queue kicks during the launch window

The `workoutRouteObserver` callback at [HealthKitManager.swift:298-305](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:298) fires shortly after registration when HealthKit has undelivered route changes — in practice, on most cold launches. Guard it:

```swift
workoutRouteObserver = HKObserverQuery(sampleType: routeType, predicate: nil) { [weak self] _, completionHandler, error in
    completionHandler()
    guard let self, error == nil else { return }

    Task { [weak self] in
        guard let self else { return }
        let inLaunchWindow = await MainActor.run { Date.now < self.launchWindowEndsAt }
        if inLaunchWindow {
            AppLogger.info("Skipping observer-triggered route queue during launch window", category: AppLogger.health)
            return
        }
        await self.processRouteFetchQueue()
    }
}
```

Rationale: a route-data-changed callback during launch is either (a) an echo from registration or (b) about to be picked up by the scheduled post-window drain anyway. Nothing user-visible needs it within the 5s window.

The sibling `workoutObserver` at [HealthKitManager.swift:245](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:245) is **intentionally left unguarded**: it triggers `syncWorkoutsIncremental`, which is debounced by `isSyncing` and whose downstream `processRouteFetchQueue` call is already constrained by Change A's session-scoped filter. Suppressing it would risk losing a new-workout import on cold launch.

##### Change C: schedule a deferred drain once the launch window ends

After Changes A and B, historical pending tasks still need to complete eventually. Kick one drain pass when the launch window closes. Put it in `handleAppLaunch` right after `didCompleteInitialLaunch = true`:

```swift
didCompleteInitialLaunch = true
healthKit.launchWindowEndsAt = .now.addingTimeInterval(5)

// Schedule a single post-window drain on a detached task so it does not
// contend with UI work. `HealthKitManager.shared` is a singleton with a
// process lifetime, so strong capture here is intentional — a weak
// capture of a computed property (`healthKit` is a view property that
// resolves to `.shared`) would not behave as expected.
Task.detached {
    try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
    await HealthKitManager.shared.processRouteFetchQueue(limit: 10)
}
```

One drain of 10 tasks, scheduled after first interactive frame, is well-spaced from launch. The existing observers, `BGProcessingTask` path ([HealthKitManager.swift:2485](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:2485)), and user-triggered `retryFailedRouteTaskIfNeeded` ([HealthKitManager.swift:1292](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1292)) continue to drain the rest over time.

This deferred drain is best-effort, not guaranteed. If the app backgrounds quickly after launch, the detached task may be delayed by suspension. That is acceptable because:

1. `BGProcessingTask` remains a fallback
2. cardio entry remains a fallback
3. startup performance is higher priority than immediate historical backlog completion

##### Change D: on-demand retry when user opens a run detail with no route

When a user opens a run detail and the route is absent, trigger a one-off UUID-scoped retry for that workout. The existing `retryFailedRouteTaskIfNeeded` covers `status == "failed"` only. Add a sibling that runs a single pending task for a specific workout:

```swift
@MainActor
func retryPendingRouteTaskIfNeeded(for workoutUUID: UUID) async {
    guard let context = modelContext else { return }
    let uuidString = workoutUUID.uuidString
    let descriptor = FetchDescriptor<RouteFetchTask>(
        predicate: #Predicate { $0.workoutUUID == uuidString && $0.status == "pending" }
    )
    guard let task = try? context.fetch(descriptor).first else { return }

    // Run this one task directly. Do NOT go through the general
    // processRouteFetchQueue path: its sort order can pick the wrong
    // pending task, and there is no existing UUID-scoped entrypoint.
    await processSingleRouteFetchTask(task)
}
```

`processSingleRouteFetchTask(_:)` is a small new helper that extracts the per-task body of `processRouteFetchQueue` (status flip to `"fetching"`, `fetchRoute` call, status flip to `"completed"` / `"failed"`, save context). Wire `retryPendingRouteTaskIfNeeded` into the run-detail view's `.task`. This restores immediacy for the only UI path where route absence is actually user-visible.

Important: do not add a `processRouteFetchQueue(for: uuidString)` overload or pass UUIDs into the general queue. A dedicated single-task path keeps the general queue's serialization and concurrency model untouched.

#### Behaviour impact

What changes:
- Cold launch: queue processes at most N session-scoped tasks, still capped by a small launch budget (N ≤ number of new workouts added by this launch's sync, typically 0 on a warm device).
- Observer-fired queue bursts during the 5s launch window are suppressed.
- Historical pending tasks drain 5 seconds after launch completes, or on user entry into a run detail, or via BGProcessingTask.
- Startup missing-route logs drop from ~300 to single digits.
- Startup auth prompts drop to roughly `N * 2` where `N` = workouts added by this launch's sync (typically 0 on a warm device, so `0`). The final `≤ 1` target across all cases depends on Finding 3 removing the per-task auth retry path.

What stays the same:
- `forceFullResync` (user-triggered from auth sheet and cardio) still runs and still drains to empty. That path is not on the cold-launch critical path.
- `BGProcessingTask` at [HealthKitManager.swift:2485](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:2485) continues to drain the queue in the background.
- `retryFailedRouteTaskIfNeeded` (existing) unchanged.
- Newly imported workouts from this session's sync enrich promptly.

#### Risks

- **Cardio list shows runs without routes during the launch window.** Mitigated by the 5s buffer (short) and by Change D (on-demand retry when user opens a detail view). Cardio list itself does not need route coords for row rendering — only for map thumbnail, which is already lazy.
- **Map snapshot generation for recently-finished runs may be delayed up to 5s.** Acceptable: the feature's own auto-post path ([HealthKitManager.swift:1388-1396](/Users/dimitarmihaylov/dev/WRKT/Features/Health/Services/HealthKitManager.swift:1388)) already runs async post-enrichment.
- **Observer-triggered queue kicks are silenced during the window.** If HK delivers a genuine new-route event during the first 5s (e.g., Watch finishes syncing a fresh route), it waits for the post-window drain. Worst case: 5s delay for the auto-post flow. Acceptable.
- **Session flags must be owned somewhere.** Placing them on `HealthKitManager.shared` keeps the call sites in this file. Alternatively they can live on `AppDependencies` and be read via the injected instance. Pick one before implementation.
- **5s is a tuned constant.** If bootstrap regresses to >5s (large exercise catalog), the window closes before bootstrap finishes and the launch-window guard stops protecting. Mitigation: derive the window from `didCompleteInitialLaunch` rather than a fixed delay — set `launchWindowEndsAt = Date.now.addingTimeInterval(5)` only at the moment the flag flips.
- **Session scoping relies on `createdAt`.** This plan assumes historical tasks are not recreated with a fresh `createdAt` during launch repair paths. If any path recreates old backlog tasks during launch, the session filter will leak backlog back into the launch window. Preserve existing tasks where possible and only mutate status.
- **Queue entrypoints still need shared serialization.** The delayed post-window drain and observer-triggered queue kicks can race each other once the window opens. All queue entrypoints should continue to rely on one common concurrency / status model so only one logical drain runs at a time.

#### Test Plan

Functional:
1. Cold launch after prior session left 50 pending route tasks in SwiftData. Startup logs show **zero** `Processing N route fetch tasks` lines with `N > (new workouts added this session)`. ~5s after launch, one `Processing N route fetch tasks` line appears for the deferred drain.
2. Cold launch after completing a Watch workout. The new workout enriches during launch (session-scoped filter lets it through).
3. Cold launch with HK route permission missing. One `Requesting authorization for 14 data types` line, not many (remainder addressed by Finding 3).
4. Cold launch offline. No crashes, queue kick no-ops gracefully.
5. Open a run-detail view for a historical run whose route task is still pending during the launch window. Route loads within a second or two (Change D path).
6. Background the app during cold launch (before `didCompleteInitialLaunch`). Foreground later. Verify deferred drain still happens (the scheduled detached task should survive scene transitions; confirm with a log line from `processRouteFetchQueue`).
7. Launch, leave foreground for 10 minutes. Eventually all pending historical tasks either complete or get marked failed via their existing age policy.

Quantitative targets (log greps across cold-launch window, first 10s):
- `fetchRouteLocations: HKSampleQuery returned 0 route objects`: **< 10** (down from 304; remaining ones are from session-scoped new workouts only)
- `Requesting authorization for 14 data types...`: **≤ 4** (down from 76; derived as at most 2 auth requests per new workout this session, capping typical launches with 0-2 new workouts at 4). The final **≤ 1** target requires Finding 3.
- `Processing N route fetch tasks`: **0** within first 5s (session-scoped fetch returns empty if no new workouts), **exactly 1** at the ~5s mark (deferred drain)
- `Skipping observer-triggered route queue`: **≥ 1** if any observer fires during the window

Instrumentation:
- `os_signpost` pair around each `processRouteFetchQueue` invocation with event name `RouteQueueDrain` and metadata `(inLaunchWindow, taskCount)`. Time Profiler filtered to this signpost shows drain timing relative to launch.

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
