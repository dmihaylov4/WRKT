# WRKT — Concurrency Audit Report

**Date:** 2026-02-18
**Scope:** Swift concurrency issues — data races, actor isolation violations, unsafe Task captures, Sendable gaps, continuation misuse
**Files audited:** 6 key files + transitive dependencies

---

## Summary

| Severity | Count | Key Themes |
|----------|-------|------------|
| CRITICAL | 2 | Continuation double-resume; infinite retry loop |
| HIGH | 6 | Missing `@MainActor` on singletons; non-isolated mutable classes; fire-and-forget Tasks |
| MEDIUM | 8 | Timer callback isolation; Supabase callback threading; parallel processing contention |
| LOW | 5 | Minor API contract violations; documentation-level concerns |

---

## CRITICAL Issues

### C1. `fetchRoute` continuation can resume more than once

- **File:** `Features/Health/Services/HealthKitManager.swift` ~line 1119–1148
- **Issue:** The `HKWorkoutRouteQuery` handler is called multiple times (once per batch of route data). On each invocation, if there is an error, the continuation resumes with `throwing`. But the query may have already called the handler with data previously. If an error occurs on a later batch, this results in a double resume — which is undefined behavior with `withCheckedThrowingContinuation` (crash) or silent corruption with `withUnsafeContinuation`.
- **Risk:** Runtime crash from resuming a continuation more than once. The error path can fire on any batch, even after `points.append(contentsOf:)` was called on previous batches.
- **Fix:** Use a boolean flag to guard all continuation resume calls:
```swift
var didResume = false
let q = HKWorkoutRouteQuery(route: route) { _, locations, done, err in
    if didResume { return }
    if let err {
        didResume = true
        cont.resume(throwing: err)
        return
    }
    if let locations { points.append(contentsOf: locations) }
    if done {
        didResume = true
        cont.resume(returning: points)
    }
}
```

---

### C2. `sendWorkoutState` infinite retry loop without backoff or limit

- **File:** `Core/Services/WatchConnectivityManager.swift` ~line 261–271
- **Issue:** The error handler in `sendWorkoutState` unconditionally retries after 1 second with no retry count limit. If the watch is technically "reachable" but the send keeps failing (e.g., session is deactivating), this creates an infinite loop of retry Tasks, each holding a strong reference to `state`.
- **Risk:** Unbounded memory growth, battery drain, and potential explosion of concurrent retry Tasks.
- **Fix:** Add a retry counter (e.g., max 3 retries) and exponential backoff, or remove the retry entirely since the debounce mechanism already handles resending on state changes.

---

## HIGH Issues

### H1. `WinScreenCoordinator` is not `@MainActor` but uses `@Published` and is accessed from `@MainActor` contexts

- **File:** `Features/Rewards/Services/WinScreenCoordinator.swift` ~line 14–19
- **Issue:** `WinScreenCoordinator` is a plain `ObservableObject` with `@Published` properties but no `@MainActor` annotation on the class. Its methods are annotated `@MainActor` individually, but the `incoming` `PassthroughSubject` sink runs on `DispatchQueue.main` which is subtly different from `@MainActor` under strict concurrency. It is a `static let shared` singleton accessed from `Task.detached` and `Task { @MainActor in }` blocks, yet the class itself has no isolation guarantee.
- **Risk:** Data race on `@Published` properties if accessed from non-main-actor contexts. The `.collect(.byTime(DispatchQueue.main, ...))` Combine operator dispatches to GCD main queue, not `@MainActor`, which can interleave with `@MainActor`-isolated code.
- **Fix:** Add `@MainActor` to the class declaration.

---

### H2. `RestTimerManager` is not `@MainActor` but is accessed as `@MainActor` singleton

- **File:** `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift` ~line 25–26
- **Issue:** `RestTimerManager` is a plain `ObservableObject` without `@MainActor` class annotation, yet it is accessed synchronously from `@MainActor`-isolated code (e.g., `WatchConnectivityManager.handleWatchMessage` calls `RestTimerManager.shared.pauseTimer()` without `await`). These calls are only safe because the callers happen to be on `@MainActor`, but the type itself provides no guarantee.
- **Risk:** If any code path calls `RestTimerManager.shared` from a non-MainActor context, it creates a data race on its `@Published` state. This is a latent bug that will surface if the call graph changes.
- **Fix:** Add `@MainActor` to `RestTimerManager`.

---

### H3. `PartnerStats` is a mutable class without any isolation guarantees

- **File:** `Shared/VirtualRunSharedModels.swift` ~line 127–157
- **Issue:** `PartnerStats` is a plain `class` (not `@MainActor`, not an actor, not `Sendable`) with mutable `private(set)` properties (`rawDistanceM`, `heartRate`, `isPaused`, etc.) and an `update(from:)` method. It is created on `@MainActor` in `VirtualRunManager` and accessed from `@MainActor` Timer callbacks and `WatchConnectivityManager` delegate callbacks (which dispatch to `@MainActor`). However, it is also passed across isolation boundaries (e.g., in `handleVirtualRunSnapshot` which uses a bare `Task {}` without `@MainActor`).
- **Risk:** If `PartnerStats` is ever accessed from a non-main-actor context, there is a potential data race since it is a reference type with mutable state.
- **Fix:** Either make `PartnerStats` a value type (`struct`), annotate it `@MainActor`, or make it conform to `Sendable` with internal synchronization.

---

### H4. `Task {}` without `@MainActor` in `handleVirtualRunSnapshot` (iOS) accesses `@MainActor` properties

- **File:** `Core/Services/WatchConnectivityManager.swift` ~line 829–847
- **Issue:** The `Task {}` on line 829 does NOT specify `@MainActor`, yet the enclosing class is `@MainActor`. In Swift 5.x, the Task inherits the actor context from the enclosing scope, so this is likely safe. However, this is fragile and the behavior changes in Swift 6 strict concurrency mode. The task accesses `activeVirtualRunId`, `activeVirtualRunUserId` which are `@MainActor`-isolated properties.
- **Risk:** Under Swift 6 strict concurrency, this would be flagged as an actor isolation violation. Currently it works due to context inheritance, but it is a maintenance hazard.
- **Fix:** Explicitly mark the Task as `Task { @MainActor in ... }`.

---

### H5. `deleteWorkoutIfExists` uses fire-and-forget `Task` that may not complete before method returns

- **File:** `Features/Health/Services/HealthKitManager.swift` ~line 925–937
- **Issue:** `deleteWorkoutIfExists` is a synchronous (non-async) method that internally spawns a `Task { @MainActor in }` to do the actual deletion. The caller (`syncWorkoutsIncremental`) may proceed to `context.save()` before the deletion task runs, resulting in a race condition where the deletion is lost.
- **Risk:** Deleted HealthKit workouts may not be properly removed from the local store, causing ghost entries.
- **Fix:** Make `deleteWorkoutIfExists` an `async` method and `await` it, or use `await MainActor.run {}` instead of `Task`.

---

### H6. `KalmanFilter` and `ReconnectionManager` are non-isolated mutable classes owned by `@MainActor` `VirtualRunManager`

- **File:** `WRKT Watch Watch App/VirtualRunManager.swift` ~line 675–743
- **Issue:** `KalmanFilter` is a plain `class` with mutable internal state (`lat`, `lon`, `variance`). `ReconnectionManager` similarly has mutable `retryCount` and `retryTask`. Both are properties of the `@MainActor`-isolated `VirtualRunManager`, so they are accessed from `@MainActor`. However, they are not themselves annotated `@MainActor`, so nothing prevents them from being accidentally passed to or called from a background context.
- **Risk:** Latent data race if these objects are ever accessed off-MainActor. The `ReconnectionManager.scheduleReconnect` spawns a `Task` that calls `action()` and then recursively calls `scheduleReconnect` — this recursive task chain does not guarantee MainActor isolation.
- **Fix:** Add `@MainActor` to both `KalmanFilter` and `ReconnectionManager`, or make them `struct`s where appropriate.

---

## MEDIUM Issues

### M1. Watch `requestNotificationPermission` callback captures `self` without `@MainActor` dispatch

- **File:** `WRKT Watch Watch App/WatchConnectivityManager.swift` ~line 564–570
- **Issue:** The `requestAuthorization` completion handler captures `self.logger` implicitly (via `self`), but `self` is a singleton (`shared`), so this is technically not a leak. However, the handler is `nonisolated` (called from system on arbitrary thread) and accesses `self.logger` which is a property of a `@MainActor` class.
- **Risk:** Under strict concurrency, accessing `self.logger` from a nonisolated completion handler is an isolation violation.
- **Fix:** Capture `logger` explicitly as `let logger = self.logger` before the closure, or wrap the callback body in `Task { @MainActor in }`.

---

### M2. Watch `scheduleVirtualRunNotification` callback captures `self` from nonisolated context

- **File:** `WRKT Watch Watch App/WatchConnectivityManager.swift` ~line 589–595
- **Issue:** Same pattern as M1. The UNUserNotificationCenter `add` completion handler runs on an arbitrary thread and captures `self.logger`.
- **Risk:** Actor isolation violation under strict concurrency.
- **Fix:** Same as M1.

---

### M3. iOS `WatchConnectivityManager.sendLocalNotification` callback captures `self` implicitly

- **File:** `Core/Services/WatchConnectivityManager.swift` ~line 1243–1249
- **Issue:** The `UNUserNotificationCenter.add` completion handler accesses `AppLogger` (static, fine) but is called on an arbitrary queue. This is benign since `AppLogger` uses static methods, but the closure implicitly captures `self`.
- **Risk:** Minor. No actual data race since only static methods are called, but this is a Sendable conformance gap.
- **Fix:** No action needed unless targeting Swift 6 strict concurrency.

---

### M4. `forceFullResync` parallel tasks serialized by MainActor hops

- **File:** `Features/Health/Services/HealthKitManager.swift` ~line 644–716
- **Issue:** Inside the `withTaskGroup`, each child task calls `await MainActor.run { store.runs.first(where:...) }`. This is correct but introduces contention: all parallel tasks need to hop to MainActor to check for existing runs, serializing the "parallel" processing.
- **Risk:** Performance degradation under load. No data race, but the parallelism benefit is undermined by frequent MainActor hops.
- **Fix:** Pre-build a lookup dictionary (e.g., `[UUID: Run]`) on MainActor before entering the task group, then pass it as a `Sendable` value into the child tasks.

---

### M5. `VirtualRunRepository` timer callback accesses `self` without `@MainActor` dispatch

- **File:** `Features/Social/Services/VirtualRunRepository.swift` ~line 403–406
- **Issue:** The Timer callback calls `self?.persistSnapshotToDB()`. Timer callbacks on the main RunLoop fire on the main thread, which aligns with `@MainActor`. However, Timer closures are not formally `@MainActor`-isolated in the type system.
- **Risk:** Under strict concurrency checking, this will be flagged as a potential isolation violation.
- **Fix:** Wrap the timer callback body in `Task { @MainActor in self?.persistSnapshotToDB() }`.

---

### M6. `WorkoutStoreV2` persistence uses `Task.detached` — thread safety of `WorkoutStorage` unclear

- **File:** `Features/WorkoutSession/Services/WorkoutStoreV2.swift` ~line 1272–1294
- **Issue:** `persistWorkouts`, `persistCurrentWorkout`, and `persistRuns` all use `Task.detached(priority: .utility)` to write to storage. They capture local copies of the data (good pattern). However, `WorkoutStorage.shared` is accessed from the detached task, and its thread-safety depends on its implementation.
- **Risk:** If `WorkoutStorage` is not thread-safe, these concurrent writes could race. Multiple persist calls in quick succession could interleave.
- **Fix:** Verify that `WorkoutStorage` uses actor isolation or internal serialization. Consider using a serial `DispatchQueue` or actor for persistence operations.

---

### M7. `VirtualRunRepository.subscribeToSnapshots` — Supabase callbacks may fire on background threads

- **File:** `Features/Social/Services/VirtualRunRepository.swift` ~line 329–411
- **Issue:** The `onBroadcast` and `onPostgresChange` callbacks invoke `onUpdate(snapshot)` directly. The `onUpdate` closure is provided by the caller and likely updates `@MainActor`-isolated UI state. If Supabase Realtime delivers these callbacks on a background thread, the `onUpdate` call would be a MainActor isolation violation.
- **Risk:** UI state corruption if the callback fires on a background thread.
- **Fix:** Wrap `onUpdate(snapshot)` in `Task { @MainActor in onUpdate(snapshot) }` inside the callbacks.

---

### M8. Watch `VirtualRunManager` timer callbacks access `self` via `[weak self]` but don't verify MainActor

- **File:** `WRKT Watch Watch App/VirtualRunManager.swift` ~line 139–168
- **Issue:** Timer callbacks (e.g., `startConfirmationTimeout`, `startCountdown`) use `[weak self]` and directly mutate `self.phase` and call `self.declineRun()`. Timer callbacks on the main RunLoop technically run on the main thread, but they are not formally `@MainActor`-isolated in the type system. The `VirtualRunManager` is `@MainActor`, so these calls should go through proper actor isolation.
- **Risk:** Swift 6 strict concurrency will flag these as violations. Currently safe in practice because main RunLoop timers fire on the main thread.
- **Fix:** Wrap timer callback bodies in `Task { @MainActor [weak self] in ... }`.

---

## LOW Issues

### L1. `WCSession.sendMessage` reply handlers access `@MainActor` state without explicit dispatch

- **File:** `Core/Services/WatchConnectivityManager.swift` ~line 261, 757, 775
- **Issue:** `sendMessage` reply handlers and error handlers are called on an arbitrary thread by WatchConnectivity. Some are properly wrapped in `Task { @MainActor in }`, but the reply handlers on lines 262 and 757 simply call `AppLogger` (static, safe).
- **Risk:** Minimal. If future edits add state mutations to these handlers without `@MainActor` dispatch, it would create a data race.
- **Fix:** No immediate action needed. Add a comment noting that reply handlers run on arbitrary threads.

---

### L2. `handleHealthSyncTask` does not cancel the sync if the BGTask expires

- **File:** `Features/Health/Services/HealthKitManager.swift` ~line 1834–1847
- **Issue:** The `expirationHandler` calls `task.setTaskCompleted(success: false)`, but the `Task` spawned continues running even after the BGTask is marked complete. `syncWorkoutsIncremental()` may continue running after iOS has reclaimed the background execution time.
- **Risk:** iOS may terminate the app if it continues executing after the background task is marked complete. Minor in practice since iOS is lenient, but it violates the API contract.
- **Fix:** Store the `Task` handle and cancel it in the `expirationHandler`.

---

### L3. `queueRouteFetching` uses `Task.detached` which won't inherit cancellation

- **File:** `Features/Health/Services/HealthKitManager.swift` ~line 1008–1009
- **Issue:** `Task.detached { [weak self] in await self?.processRouteFetchQueue() }` creates a detached task that cannot be cancelled by parent task cancellation.
- **Risk:** The route fetch queue processing will continue even if the parent sync operation is cancelled or the view disappears.
- **Fix:** Use a regular `Task` instead of `Task.detached` if cancellation propagation is desired.

---

### L4. Watch notification `completionHandler()` called before async processing finishes

- **File:** `WRKT Watch Watch App/WatchConnectivityManager.swift` ~line 688–710
- **Issue:** In `userNotificationCenter(_:didReceive:withCompletionHandler:)`, the `completionHandler()` is called synchronously on line 709, while the `Task { @MainActor in }` on line 698 may not have completed yet. WatchKit documentation says the completion handler should be called after processing is complete.
- **Risk:** Minor. The notification action may not be fully processed before the system considers it handled.
- **Fix:** Move `completionHandler()` inside the `Task { @MainActor in }` block, after the processing completes.

---

### L5. `HKHealthStore` accessed from both `@MainActor` and nonisolated contexts

- **File:** `Features/Health/Services/HealthKitManager.swift` ~line 30
- **Issue:** `let store = HKHealthStore()` is a stored property on a `@MainActor` class, accessed from continuation closures that run on arbitrary HealthKit callback threads. `HKHealthStore` is thread-safe, so this is safe in practice.
- **Risk:** None in practice. `HKHealthStore` is documented as thread-safe.
- **Fix:** No action needed. Could add `nonisolated` to the property declaration for clarity if targeting Swift 6.
