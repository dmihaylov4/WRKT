# WRKT — Master Audit Document
**Date:** 2026-02-23
**Source audits:** Security & Privacy · Swift 6 Concurrency · Memory Leaks · Energy · Modernization
**Total issues:** 61 + 47 modernization items

---

## How to Read This Document

Each issue includes:
- **Problem** — what is wrong
- **Fix** — what changes
- **Files** — what to edit
- **Existing functionality impact** — whether the fix could change observable behaviour for the user or break currently-working code
- **Fix risk** — likelihood that applying the fix introduces a regression (Low / Medium / High)

Issues are ordered within each audit section by severity. Cross-cutting risks (especially to virtual run) are called out explicitly.

---

## Audit 1 — Security & Privacy

### CRITICAL-1 · Missing Privacy Manifest (`PrivacyInfo.xcprivacy`) [DONE]

**Problem:** Apple's automated pipeline rejects builds that use "required reason" APIs (UserDefaults, FileManager timestamps) without a Privacy Manifest. Error: `ITMS-91053: Missing API declaration`. App cannot be submitted.

**Fix:** Create `WRKT/PrivacyInfo.xcprivacy` and add it to the WRKT target. Declare reason codes `CA92.1` (UserDefaults — same-app access) and `C617.1` (FileManager timestamps — own files).

**Files:**
- Create `WRKT/PrivacyInfo.xcprivacy` (new file)
- Add to WRKT target in Xcode

**Existing functionality impact:** None. Purely a new file. No code changes, no runtime effect.

**Fix risk:** Low.

---

### CRITICAL-3 · Supabase Auth Tokens in UserDefaults (should be Keychain) [ DONE ]

**Problem:** JWT access + refresh tokens stored as plain plist in UserDefaults — readable from device backups, forensic tools, and jailbroken devices. Exposure allows an attacker to make authenticated Supabase calls as the user indefinitely.

**Fix:** Create `Core/Security/KeychainHelper.swift` wrapping the Security framework. Replace `UserDefaultsStorage` in `SupabaseClient.swift` with `KeychainAuthStorage` backed by KeychainHelper using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

**Files:**
- Create `Core/Security/KeychainHelper.swift`
- `Core/Services/SupabaseClient.swift` — replace `UserDefaultsStorage` with `KeychainAuthStorage`

**Existing functionality impact:** ⚠️ **One-time forced sign-out for all existing users.** On first launch after the update, the Keychain will be empty (tokens were in UserDefaults). Users will need to log in again. You can mitigate this with a one-time migration: on launch, read from UserDefaults, write to Keychain, delete from UserDefaults. Without migration, all existing sessions are invalidated.

**Fix risk:** Medium. The migration itself is simple; the user-facing forced sign-out is the risk to manage.

---

### HIGH-1 · APNS Device Token Persisted in UserDefaults [DONE]

**Problem:** The device token (a stable, unique per-device identifier) is stored in UserDefaults between launches. Apple recommends treating tokens as sensitive. More practically: iOS delivers a fresh token on every cold launch anyway, so persistence buys nothing.

**Fix:** Remove the `tokenKey` read/write from UserDefaults. Keep token in memory only (`private var deviceToken: String?`). Upload to server from `didRegisterForRemoteNotifications`.

**Files:**
- `Core/Services/PushNotificationService.swift` — remove lines 22 and 79

**Existing functionality impact:** None. iOS reliably delivers the token on every launch. Push notifications continue to work identically.

**Fix risk:** Low.

---

### HIGH-2 · Supabase Anon Key in Info.plist vs. xcconfig [DONE] 

**Problem:** Key is read from Info.plist, which is unencrypted inside the `.ipa`. The key is technically public (Supabase's security relies on RLS, not key secrecy), but best practice is xcconfig files for per-environment keys.

**Fix:** Move `SUPABASE_URL` and `SUPABASE_ANON_KEY` to `WRKT-Debug.xcconfig` and `WRKT-Release.xcconfig`. Update `SupabaseConfig.swift` to read from build settings.

**Files:**
- Create `WRKT-Debug.xcconfig`, `WRKT-Release.xcconfig`
- `Core/Configuration/SupabaseConfig.swift`
- Update Xcode project config settings

**Existing functionality impact:** None if done correctly. This is purely a build configuration change — the same key ends up in the binary.

**Fix risk:** Low (config change only), but if the xcconfig is not linked properly Supabase will fail to initialize. Verify on a clean build.

---

### MEDIUM-1 · APNS Token Prefix Logged to System Logs [DONE]

**Problem:** `tokenString.prefix(20)` is written to the system log — visible in Console.app, crash reporting tools, and on managed (MDM) devices.

**Fix:** Remove the token from the log entirely, or wrap in `#if DEBUG`.

**Files:**
- `Core/Services/PushNotificationService.swift` line 89

**Existing functionality impact:** None. Log-only change.

**Fix risk:** Low.

---

### MEDIUM-2 · User Email Persisted During Signup Flow [ DONE ] 

**Problem:** `signupEmail: String?` on `SupabaseAuthService` may survive app restart if backed by UserDefaults, making a PII email address appear in device backups. Email is PII under GDPR/CCPA.

**Fix:** Confirm the property is in-memory only (no UserDefaults backing). Add `clearSignupState()` called on completion or cancellation.

**Files:**
- `Features/Social/Services/SupabaseAuthService.swift` line 15

**Existing functionality impact:** Minor UX change: if the app crashes mid-signup, the user must re-enter their email on the resend screen. Previously it may have been pre-filled.

**Fix risk:** Low.

---

### LOW-1 · User Birth Year Cached in UserDefaults [DONE]
**Problem:** Birth year is PII under GDPR's "age data" category. Caching it locally is unnecessary if the Supabase profile already stores it.

**Fix:** Remove local UserDefaults cache. Fetch from Supabase profile response on demand.

**Files:**
- `Features/Social/Services/SupabaseAuthService.swift` line 78

**Existing functionality impact:** If HR zone calculations or age-gating depend on the cached value, they will require a network fetch. If the network is unavailable and no in-memory value exists, HR zone calculations would degrade. Evaluate whether the profile is already fetched early enough in the session to have the value ready.

**Fix risk:** Low-Medium. Depends on how soon after launch the birth year is first needed.

---

### LOW-2 · Deep Link URL Validation Too Permissive

**Problem:** `url.path.contains("recovery")` matches any path containing that substring. Any app on the device can open URLs with your custom scheme, potentially triggering flows with crafted URLs.

**Fix:** Replace `contains` with an allowlist of exact paths: `Set(["/recovery", "/confirm", "/signup", "/reset"])`.

**Files:**
- `App/WRKTApp.swift` line 199

**Existing functionality impact:** Any deep link path not in the allowlist will be silently rejected. Audit all deep links the app generates (emails, push notifications) to confirm they use exact paths. If any path doesn't match the allowlist, the link will stop working.

**Fix risk:** Low-Medium. Safe in principle, but requires verifying all existing deep link paths.

---

## Audit 2 — Swift 6 Concurrency

> **Cross-cutting note:** CRIT-3 touches `WatchConnectivityManager.swift` (both Watch and iPhone) — the same file that handles all virtual run message passing. Apply carefully and verify the message protocol table in `docs/virtual-run-implementation.md` still holds after the refactor.

---

### CRIT-1 · `WinScreenCoordinator` Missing `@MainActor` on Class [DONE]

**Problem:** Class has `@Published` properties (must mutate on main thread) and per-method `@MainActor` annotations, but the class itself is not `@MainActor`. Combine `.sink {}` callbacks run on a background thread — calling `@MainActor func enqueue()` across actor boundaries is a silent data race in Swift 5, compile error in Swift 6.

**Fix:** Add `@MainActor` to the class declaration. Remove redundant per-method `@MainActor` annotations.

**Files:**
- `Features/Rewards/Services/WinScreenCoordinator.swift` line 14

**Existing functionality impact:** None. The class already should have been `@MainActor`. Behaviour is identical; the fix enforces the invariant at compile time.

**Fix risk:** Low.

---

### CRIT-2 · `LiveActivityManager.createNewActivity` Incorrectly `nonisolated`

**Problem:** Method is `nonisolated` on a `@MainActor` class, then does `await MainActor.run { self.currentRestTimerActivity = activity }` — sending `self` (non-Sendable) across an actor boundary. Swift 6 error. Also: the `Task` that calls it has no `[weak self]`, creating a retain cycle.

**Fix:** Remove `nonisolated` from `createNewActivity`. `Activity.request()` is safe to call from `@MainActor`. Inline the logic and add `[weak self]` to the calling `Task`.

**Files:**
- `Features/WorkoutSession/Services/LiveActivityManager.swift` lines 67-93, 97

**Existing functionality impact:** None. Live Activity creation and rest timer behaviour unchanged.

**Fix risk:** Low.

---

### CRIT-3 · `nonisolated` WCSession Delegates Sending `self` — ~26 Sites [ DONE. ] Issue not in 26 sites - only 3 sites fixed

**Problem:** WCSession delegate methods are `nonisolated` (Apple calls them on background threads). All three `WatchConnectivityManager`/`WatchHealthKitManager` files create `Task { @MainActor in self.handle...() }` — sending a non-Sendable `@MainActor` reference from an unspecified context. 26 Swift 6 compile errors.

**Fix:** Extract Sendable values (message dictionaries) before the `Task`, then capture `[weak self]`:
```swift
let copy = message
Task { @MainActor [weak self] in
    self?.handleWatchMessage(copy)
}
```

**Files:**
- `Core/Services/WatchConnectivityManager.swift` lines 1330-1493 (11 methods)
- `WRKT Watch Watch App/WatchConnectivityManager.swift` lines 243-754 (9 methods)
- `WRKT Watch Watch App/WatchHealthKitManager.swift` lines 319-412 (6 methods)

**Existing functionality impact:** ⚠️ **Medium risk — touches virtual run message infrastructure.** Functionally equivalent: message handling logic is unchanged, just the capture pattern. However, with `[weak self]` on singleton managers (which are never deallocated), the `guard let self` always succeeds in practice. Verify the `"type"` / `"messageType"` key asymmetry (see `virtual-run-implementation.md`) is preserved. Run a full virtual run end-to-end after this change.

**Fix risk:** Medium. Large surface area (26 sites). Apply mechanically using the pattern above, then regression-test WatchConnectivity.

---

### HIGH-1 · `nonisolated(unsafe)` on Mutable State in `@MainActor` Classes [DONE]

**Problem:** `ProfileViewModel` and `FriendsListViewModel` use `nonisolated(unsafe)` on stored properties — an escape hatch that disables Swift 6 safety checking. The properties are already protected by `@MainActor`; this annotation makes them less safe, not more.

**Fix:** Remove `nonisolated(unsafe)` from both ViewModels. Fix any resulting compiler errors (which reveal real underlying bugs).

**Files:**
- `Features/Social/ViewModels/ProfileViewModel.swift` lines 33-34
- `Features/Social/ViewModels/FriendsListViewModel.swift` lines 27-28

**Existing functionality impact:** None if no compiler errors follow. If removing the annotation surfaces errors, those errors represent real data race bugs to fix.

**Fix risk:** Low (if no errors surface); Medium (if errors indicate real bugs).

---

### HIGH-2 · `RewardsEngine` Strong-Captures `self` in `Task.detached` [DONE]

**Problem:** `Task.detached` has no inherited actor isolation and strongly captures `self`, creating a retain cycle. If the reward screen is dismissed, the object stays alive and the task continues running.

**Fix:** Add `[weak self]` and `guard let self`.

**Files:**
- `Features/Rewards/Models/StreakResult.swift` line 35

**Existing functionality impact:** If the reward screen is dismissed while the task is running, the task now aborts rather than continuing on a dead object. No visible difference in normal usage (user stays on screen until task completes).

**Fix risk:** Low.

---

### HIGH-3 · HealthKit Observer Holds `completionHandler` for 60+ Seconds

**Problem:** `HKObserverQuery` callback calls `completionHandler()` after the full sync completes (up to 60 seconds). This prevents HealthKit from delivering the next batch and can exhaust background execution budget if the watchdog kills the app.

**Fix:** Call `completionHandler()` immediately (even on error), then start the sync independently via a separate `Task`.

**Files:**
- `Features/Health/Services/HealthKitManager.swift` lines 232-257

**Existing functionality impact:** HealthKit can now deliver the next batch while the previous sync is still in progress. If two concurrent syncs could conflict (e.g., both writing to the same local state), add a guard. In most cases, `syncWorkoutsIncremental()` should be idempotent and this is safe.

**Fix risk:** Low-Medium. Verify `syncWorkoutsIncremental` is re-entrant safe.

---

### HIGH-4 · `BattleRepository.createBattle` Network Fetch on Main Actor

**Problem:** `Task { @MainActor in let name = try? await fetchProfile(...) }` executes a network call with the main actor as the execution context. Conceptually wrong: network I/O should not use the main actor.

**Fix:** Perform the `fetchProfile` call outside `@MainActor`, then hop to `@MainActor` only for the notification.

**Files:**
- `Features/Battles/Services/BattleRepository.swift` lines 232-237

**Existing functionality impact:** None. The user still sees the same success notification. The fix is purely about actor context, not result.

**Fix risk:** Low.

---

### HIGH-5 · `VirtualRunMapComparisonView` Uses `Task.detached` for Main-Actor Work

**Problem:** `Task.detached` breaks `@MainActor` isolation. `repo` is main-actor-isolated; accessing it from a detached task is a Swift 6 data race. The view is `@MainActor` — `Task { }` (non-detached) inherits that isolation safely.

**Fix:** Replace `Task.detached` with `Task { }`.

**Files:**
- `Features/Social/Views/VirtualRunMapComparisonView.swift` line 404

**Existing functionality impact:** None. Route upload still happens.

**Fix risk:** Low.

---

### HIGH-6 · `VirtualRunInviteCoordinator` Double-Nested Tasks in Realtime Callback

**Problem:** Supabase Realtime callbacks are called on a background thread. Current code nests two Tasks — outer `Task` (unspecified isolation), inner `Task { @MainActor in self.handleInvite(...) }` — sending `self` across boundaries in both.

**Fix:** Single `Task { @MainActor [weak self] in }` with Sendable payload extracted before the Task.

**Files:**
- `Features/Social/Services/VirtualRunInviteCoordinator.swift` lines 51-64

**Existing functionality impact:** ⚠️ **Moderate risk — invite flow infrastructure.** Functionally the invite is still processed on `@MainActor`. But this is core virtual run invite reception code. After applying the fix, verify that invites are received and `isInActiveRun` transitions correctly (see `virtual-run-implementation.md` Phase 1).

**Fix risk:** Medium. Critical path; run invite flow end-to-end after.

---

### HIGH-7 · Observer Tokens in `nonisolated(unsafe)` Properties — Verify `deinit` Cleanup

**Problem:** Covered by HIGH-1. Additional concern: after removing `nonisolated(unsafe)`, confirm `deinit` removes all `NotificationCenter` observer tokens to prevent observer outliving the ViewModel.

**Files:**
- `Features/Social/ViewModels/ProfileViewModel.swift`
- `Features/Social/ViewModels/FriendsListViewModel.swift`

**Existing functionality impact:** None. Prevents observer-after-dealloc ghost callbacks.

**Fix risk:** Low.

---

### MEDIUM Issues (MED-1 through MED-7)

| ID | Problem | Files | Existing functionality impact | Fix risk |
|----|---------|-------|-------------------------------|----------|
| MED-1 | Redundant `Task { @MainActor in }` inside already-`@MainActor` methods causes one event-loop delay on state mutations | `WorkoutStoreV2.swift:267-272,958-964`, `FeedViewModel.swift:247-253` | Low — removes timing surprise; mutations happen synchronously as expected | Low |
| MED-2 | `StatsAggregator` makes one `MainActor.run` hop per exercise entry (500 entries = 500 context switches) | `Features/Statistics/Services/StatsAggregator.swift:175` | None — batch at end is functionally equivalent | Low |
| MED-3 | `QueryCache.startCleanupTimer` uses `Timer` + `Task { @MainActor in }` mix; better to use a Task-based loop | `Core/Services/QueryCache.swift:201-207` | None — cleanup interval unchanged | Low |
| MED-4 | Watch `WatchConnectivityManager` inner Tasks missing `[weak self]` | `WRKT Watch Watch App/WatchConnectivityManager.swift` | None — singleton never deallocates, but inconsistency is corrected | Low |
| MED-5 | `ProgressTabView.refreshStats` uses `Task.detached` when regular `Task` suffices | `Features/...` | None | Low |
| MED-6 | `VirtualRunDebugView` double-Task pattern same as HIGH-6 | `Features/Social/Views/VirtualRunDebugView.swift` | None — debug view | Low |
| MED-7 | `FeedViewModel.undoDeletePost` strong-captures `self` in `Task` | `Features/Social/ViewModels/FeedViewModel.swift` | None — adds `[weak self]`, task aborts if ViewModel deallocates | Low |

### LOW Issues (LOW-1 through LOW-3)

| ID | Problem | Files | Impact | Risk |
|----|---------|-------|--------|------|
| LOW-1 | `VirtualRunAudioCues` nonisolated `AVAudioSession` deactivation lacks comment | `Utilities/VirtualRunAudioCues.swift` | None — add comment only | Low |
| LOW-2 | `BaseRepository` nonisolated logger functions — verify `AppLogger` wraps `os.Logger` | `Core/` | None if verified | Low |
| LOW-3 | `HealthKitManager.deleteWorkoutIfExists` wraps `@MainActor` code in redundant `Task { @MainActor in }` | `Features/Health/Services/HealthKitManager.swift` | Removes one event-loop delay | Low |

---

## Audit 3 — Memory Leaks

### CRIT-1 · `QueryCache.startCleanupTimer` — Return Value Discarded

**Problem:** `Timer.scheduledTimer(...)` return value is dropped — no stored reference, so `.invalidate()` can never be called. If `startCleanupTimer()` is called twice, two timers accumulate and run forever.

**Fix:** Store in `private var cleanupTimer: Timer?`. Call `cleanupTimer?.invalidate()` at the start of `startCleanupTimer()` (idempotent). Add `deinit { cleanupTimer?.invalidate() }`.

**Files:**
- `Core/Services/QueryCache.swift` line 203

**Existing functionality impact:** Cleanup timer fires as before. Previously calling the method twice would leave an orphaned timer; now it's prevented.

**Fix risk:** Low.

---

### HIGH-1 · `ExerciseSessionViewModel` — NotificationCenter Observer Accumulates

**Problem:** `onAppear` calls `setupWatchNotificationListener()` which registers a new block-based observer every time. After 5 navigate-away-and-back cycles: 6 observers. Every Watch update triggers `reloadFromStore()` 6 times — 6 store reads, 6 SwiftUI re-renders, potential concurrent async operations.

**Fix:** Store the token (`private var watchObserverToken: NSObjectProtocol?`). Guard with `guard watchObserverToken == nil else { return }`. Remove in `deinit`.

**Files:**
- `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift` line 90

**Existing functionality impact:** `reloadFromStore()` now fires exactly once per Watch update instead of N times. This is a bug fix — the previous behaviour caused redundant store reads and potential race conditions.

**Fix risk:** Low.

---

### HIGH-2 · Watch `WatchConnectivityManager` — Observer Token Discarded in `init`

**Problem:** Block-based `NotificationCenter.addObserver` token dropped in `init`. Singleton so no deallocation risk, but token itself is leaked and pattern is inconsistent.

**Fix:** Store in `private var activeNotificationToken: NSObjectProtocol?`. Add `deinit`.

**Files:**
- `WRKT Watch Watch App/WatchConnectivityManager.swift` line 52

**Existing functionality impact:** None. Singleton behaviour unchanged.

**Fix risk:** Low.

---

### HIGH-3 · `LiveActivityManager` — Update Timer Double-Scheduled

**Problem:** `Timer.scheduledTimer(...)` already adds the timer to the RunLoop in `.default` mode. Then `RunLoop.main.add(timer, forMode: .common)` adds the same timer again. During UIScrollView scroll, both registrations fire → timer fires twice per second → 2× Live Activity updates during scroll.

**Fix:** Use `Timer(timeInterval:repeats:block:)` (does not auto-schedule) + `RunLoop.main.add(timer, forMode: .common)` only. Remove `scheduledTimer`.

**Files:**
- `Features/WorkoutSession/Services/LiveActivityManager.swift` line 213

**Existing functionality impact:** Timer fires exactly once per second in all RunLoop modes. Previously it fired twice during scroll. The Live Activity display is unchanged; double updates during scroll are eliminated.

**Fix risk:** Low.

---

### MEDIUM-1 · `VirtualRunDebugView` — Simulation Timer Not Cleaned Up on Disappear

**Problem:** Timer fires every 3 seconds calling `repository.publishSnapshot(snapshot)` — a Supabase write. If user navigates away while simulation is running, the timer continues firing for one more interval.

**Fix:** `.onDisappear { stopSimulation() }`

**Files:**
- `Features/Social/Views/VirtualRunDebugView.swift` line 342

**Existing functionality impact:** None for production. Debug view only.

**Fix risk:** Low.

---

### MEDIUM-2 · Long-Press Timers in 4 Views — No `onDisappear` Cleanup

**Problem:** Long-press stepper timers fire at 10Hz (0.1s). If the view is dismissed mid-press, the timer continues and calls `action()` — potentially incrementing a set value on a view that's gone.

**Fix:** Add `.onDisappear { stopLongPress() }` to each of the 4 views.

**Files:**
- `SetRowViews.swift:470`, `BodyweightSetRow.swift:360`, `RetrospectiveSetEditor.swift:324`, `PlannedWorkoutEditor.swift:668`

**Existing functionality impact:** If a user somehow dismisses a view while long-pressing, the increment stops. Prevents phantom increments. No impact in normal usage.

**Fix risk:** Low.

---

### LOW-1 · `TimedSetRow.exerciseTimer` — No `onDisappear` Cleanup

**Problem:** 1Hz timer counting elapsed seconds continues if user navigates away mid-set.

**Fix:** `.onDisappear { stopExerciseTimer() }`

**Files:**
- `Features/WorkoutSession/Views/ExerciseSession/TimedSetRow.swift` line 245

**Existing functionality impact:** None in normal usage. Edge-case cleanup.

**Fix risk:** Low.

---

## Audit 4 — Energy

### CRIT-1 · Timer Tolerance Missing Across All 17 Timer Sites + 10Hz Rest Timer

**Problem (a):** No timer has `.tolerance` set. Without tolerance, the OS cannot coalesce timer fires — each fires at its exact scheduled time as a separate CPU wake. Apple guideline: ≥10% of interval.

**Problem (b):** The rest timer fires at 10Hz (0.1s) but displays whole-second values. 9 of every 10 fires produce the same integer and are wasted CPU wakes.

**Fix (a):** Add `timer.tolerance = interval * 0.1` to all `Timer` instances at creation.

**Fix (b):** Change rest timer from 0.1s → 1.0s.

**Files:**
- `RestTimerWatchView.swift:20`, `RestTimerState.swift:404,669`
- `WatchHealthKitManager.swift:270`
- `VirtualRunManager.swift:160,395,405,415`
- `TimedSetRow.swift:245`, `LiveActivityManager.swift:213`, `QueryCache.swift:203`

**Existing functionality impact:**

- **Rest timer (0.1s → 1.0s):** Display updates once/second, same as before (values are integers). No user-visible difference. ⚠️ If any code path depends on the timer firing sub-second for accuracy (e.g., exact pause time recording), verify it uses `Date()` directly rather than timer fire count.

- **VirtualRunManager timers with tolerance:** The heartbeat timer (3s + 0.3s tolerance) and snapshot timer (2s + 0.2s tolerance) will fire within ±0.2–0.3 seconds of their scheduled time. The connection health thresholds (8s stale, 15s disconnected) have sufficient margin that ±0.3s tolerance is imperceptible.
  ⚠️ Do NOT increase the virtual run timers' intervals (separate from tolerance) without revisiting the connection health logic — see CRIT-5 below.

**Fix risk:** Low for tolerance. Low for rest timer interval reduction.

---

### CRIT-2 · Virtual Run Invite Detection Uses 30-Second Polling Timer

**Problem:** A fallback polling timer fires every 30 seconds while the app is in the foreground — even though Supabase Realtime already delivers invites immediately over the open WebSocket. 30-minute session = 60 unnecessary network requests.

**Fix:** Remove the polling timer. Register a `UIApplication.willEnterForegroundNotification` observer that calls `pollOnce()` once on foreground resume (to catch events missed while backgrounded).

**Files:**
- `Features/Social/Services/VirtualRunInviteCoordinator.swift` line 71

**Existing functionality impact:** ⚠️ **Trade-off.** During normal foreground use with Realtime working: no change — Realtime delivers instantly. If Realtime is disconnected and the user is in the foreground, they will not receive the invite until they background and foreground the app. In practice this is unlikely (Realtime reconnects automatically), but it's a deliberate trade-off for battery. Add a Realtime connection health check and trigger a poll if the channel is not connected.

**Fix risk:** Low-Medium. Verify invite delivery still works when Realtime reconnects after a background/foreground cycle.

---

### CRIT-3 · 30-Second DB Persist Timer During Virtual Run Is Redundant

**Problem:** During an active virtual run, `persistState()` is called every 2 seconds (with each snapshot) AND a separate DB persist timer writes to Supabase every 30 seconds. The 30-second timer is fully redundant — the 2-second snapshot already is the crash recovery state.

**Fix (Option A — recommended):** Remove the 30-second DB persist timer entirely.
**Fix (Option B — conservative):** Extend to 5 minutes with 30s tolerance.

**Files:**
- `Features/Social/Services/VirtualRunRepository.swift` line 405

**Existing functionality impact:** ⚠️ **If snapshots are failing** (network issues), removing the timer removes the only crash recovery path. However, if snapshots are failing, the run is already broken. Option B retains the safety net at negligible cost (12 writes/hour vs 120). Recommend Option B.

**Fix risk:** Low (Option B). Medium (Option A — verify snapshot failure scenarios).

---

### CRIT-4 · `kCLLocationAccuracyBest` on Apple Watch During Outdoor Workouts [DONE]

**Problem:** Maximum GPS accuracy is requested but the app's own filter rejects any location with `horizontalAccuracy > 50m`. The GPS works at full power for 5m accuracy; you discard anything not within 50m. 10m accuracy is visually identical for route display at running speeds.

Additionally, `locationManagerDidChangeAuthorization` calls `startUpdatingLocation()` unconditionally — even if already running — potentially double-starting.

**Fix:**
```swift
manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
manager.distanceFilter = 5.0
// In locationManagerDidChangeAuthorization:
if !manager.isUpdatingLocation { manager.startUpdatingLocation() }
```

**Files:**
- `WRKT Watch Watch App/WatchHealthKitManager.swift` lines 244, 272 (startLocationUpdates)

**Existing functionality impact:** Route lines may be marginally less precise (10m vs 5m). At running speed (4m/s), this is sub-step accuracy — imperceptible. The `distanceFilter = 5.0` means the delegate fires only when the Watch moves 5 metres rather than on every GPS sample — slightly fewer points in the route, but still high fidelity. The existing accuracy filter (`< 50m`) remains unchanged and is unaffected.

**Fix risk:** Low. GPS accuracy for route tracking is unchanged in practice.

---

### CRIT-5 · Virtual Run Snapshot at 2Hz and Heartbeat at 3Hz

**Problem:** Every 2 seconds: WCSession send → iPhone → Supabase HTTPS write → UserDefaults write. Every 3 seconds: heartbeat. Over 30 minutes: 900 network writes, radio never sleeps, Watch CPU never idles.

**Proposed fix (from audit):** Snapshot 2s → 5s, heartbeat 3s → 10s.

**⚠️ DO NOT APPLY THIS CHANGE WITHOUT CAREFUL ANALYSIS.**

**Why the heartbeat change is risky:**
The heartbeat timer drives `checkExtendedDisconnect()`. `PartnerStats.connectionStatus` thresholds are:
- `< 8s` since last snapshot → `.connected`
- `8–15s` → `.stale`
- `> 15s` → `.disconnected`

With a 10s heartbeat, disconnect checks fire every 10 seconds. After one missed snapshot (at 5s interval), `dataAge` reaches 10s — already past the 8s stale threshold. The partner immediately appears stale without the smooth connected→stale→disconnected progression. With the 3s heartbeat, there were two intermediate checks (at 3s and 6s) showing `.connected` before hitting stale at 8s.

**Recommended approach:**
- Snapshot: 2s → 3s (50% reduction, minor UX impact) [DONE]
- Heartbeat: keep at 3s (disconnect checking depends on it)
- Remove `persistState()` from per-snapshot cycle (move to event-driven only — see below)
- Extend DB persist timer to 5 minutes (see CRIT-3)

**Specifically:** Remove `self.persistState()` from `updateMyStats()` (called every 2s). Keep it in `pauseRun()`, `requestEndRun()`, and the `batteryTimer` callback (60s). [DONE — partial fix applied]

**Files:**
- `Shared/VirtualRunSharedModels.swift` — `snapshotPublishInterval` constant
- `WRKT Watch Watch App/VirtualRunManager.swift` — `updateMyStats()`

**Existing functionality impact:** ⚠️ Any change to `snapshotPublishInterval` or `heartbeatInterval` in `VirtualRunSharedModels.swift` affects both the Watch timers and the connection health display. Review `docs/virtual-run-implementation.md` § "Timing Constants" and § "Connection Health" before changing.

**Fix risk:** High for heartbeat interval. Medium for snapshot interval. Low for removing `persistState()` from the per-snapshot path (it's purely I/O, not logic).

---

### HIGH-1 · WinScreen `repeatForever` Animations — No `onDisappear` Cleanup

**Problem:** `luckyPulse = true` and `shimmer = true` set in `onAppear` but never reset. GPU renders 60–120Hz frames for an infinite animation even if the view is still in the SwiftUI navigation stack.

**Fix:** `.onDisappear { luckyPulse = false; shimmer = false }`

**Files:**
- `Features/Rewards/Views/WinScreen.swift:154,428`

**Existing functionality impact:** Animations stop when the view leaves the screen. They restart correctly when it reappears (onAppear fires again).

**Fix risk:** Low.

---

### HIGH-2 · Skeleton Views Run `repeatForever` Without Cleanup

**Fix:** `.onDisappear { isAnimating = false }` on each skeleton view.

**Files:**
- `SkeletonPostCard.swift:116`, `SkeletonNotificationRow.swift:48`, `SkeletonProfileHeader.swift:85`

**Existing functionality impact:** None. Skeletons re-animate when shown again.

**Fix risk:** Low.

---

### HIGH-3 · `fetch` UIBackgroundMode Declared but Never Used

**Problem:** Declaring `fetch` in `UIBackgroundModes` without implementing `performFetchWithCompletionHandler` confuses iOS scheduling and could draw App Review scrutiny.

**Fix:** Remove `<string>fetch</string>` from `WRKT-Info.plist`. Keep `processing` (used for `BGProcessingTask`).

**Files:**
- `WRKT-Info.plist` line 11

**Existing functionality impact:** None. The mode was unused.

**Fix risk:** Low.

---

### HIGH-4 · `HeroStartWorkoutButton` — 8-Second `repeatForever` Animation at Full Frame Rate [DONE]

**Problem:** 8-second gradient sweep on the main CTA button runs at display refresh rate (up to 120Hz) whenever a workout is active. The home screen is the most-visited screen.

**Fix:** Wrap in `TimelineView(.animation(minimumInterval: 1.0/30.0))` to cap GPU updates at 30fps, or switch to `easeInOut(duration: 2).repeatForever(autoreverses: true)` which SwiftUI can optimize.

**Files:**
- `Features/Home/Components/HeroStartWorkoutButton.swift:100`

**Existing functionality impact:** Animation appears visually identical at 30fps. The gradient sweep is slow enough that sub-30fps updates are imperceptible.

**Fix risk:** Low.

---

### HIGH-5 · `ChallengesBrowseView` and `BattlesListView` — `repeatForever` Without Cleanup

Same pattern as HIGH-1. `.onDisappear { isAnimating = false }` on both.

**Files:** `ChallengesBrowseView.swift:743`, `BattlesListView.swift:714`

**Fix risk:** Low.

---

### HIGH-6 · Widget Command Observer Polls at 2Hz [DONE]

**Problem:** Every 0.5 seconds, the app reads shared `UserDefaults` (cross-process disk read) to check for widget button taps. Over a 60-minute workout: 7,200 disk reads.

**Fix:** Darwin notifications for zero-cost cross-process signalling. Widget extension posts `CFNotificationCenterPostNotification` on tap; main app reads UserDefaults exactly once per tap.

**Files:**
- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:669` — replace timer with `CFNotificationCenterAddObserver`
- Widget extension — add `CFNotificationCenterPostNotification` after writing command

**Existing functionality impact:** ⚠️ **Both sides must be updated simultaneously.** If only the main app is updated (removing the polling timer) but the widget extension is not updated (not posting Darwin notifications), widget taps will never be detected. This is a two-target change — update both the main app and the widget extension in the same release.

**Fix risk:** Medium. Two-target coordination required.

---

### MEDIUM Issues

| ID | Problem | Files | Impact | Risk |
|----|---------|-------|--------|------|
| MED-1 | Supabase `URLSession` ignores Low Power Mode / Low Data Mode | `Core/Services/SupabaseClient.swift`, `BaseRepository.swift` | ⚠️ During Low Power Mode, Supabase calls may defer. Verify virtual run snapshots use a session that is exempt or use a separate session config for real-time data | Medium |
| MED-2 | Partner route download polls every 10s for 6 minutes post-run | `Features/Social/Views/VirtualRunMapComparisonView.swift:482` | Replace with Realtime INSERT subscription on `virtual_run_routes` for `run_id`. Zero polling; instant delivery | Low-Medium |
| MED-3 | `BGProcessingTask` runs on battery power | `Features/Health/Services/HealthKitManager.swift:1897` | `requiresExternalPower = true` delays sync until charging. Users won't see new workouts until phone charges. Acceptable for non-time-critical sync | Low |
| MED-4 | `QueryCache` timer has zero tolerance (see also Memory CRIT-1) | `Core/Services/QueryCache.swift:203` | Add `timer.tolerance = 60.0`. No functional change | Low |

### LOW Issues

| ID | Problem | Files | Impact | Risk |
|----|---------|-------|--------|------|
| LOW-1 | 4 separate `UserDefaults.set` calls at rest timer start (4 disk ops) | `RestTimerState.swift:131-134` | Batch into a single `Codable` write. No user-visible change | Low |
| LOW-2 | 5 atomic file writes per workout save | `Core/Persistence/WorkoutStorage.swift` | Add 500ms debounce or consolidate into wrapper struct | Low |
| LOW-3 | `VirtualRunFileLogger` flushes every 2s on Watch in production | `WRKT Watch Watch App/Utilities/VirtualRunFileLogger.swift` | Wrap flush in `#if DEBUG`. In production, disable or extend to 10s | Low |

---

## Audit 5 — Modernization (ObservableObject → @Observable)

> Deployment target is iOS 17+ (confirmed by existing `@Observable` usage in 8 ViewModels).
> This audit is a separate long-horizon effort. None of these issues affect correctness or App Store submission.

**Scale:** 30 classes using `ObservableObject`, 124 `@Published` properties, 35 `@StateObject` sites, 20 `@ObservedObject` sites.

---

### CRITICAL (Singletons — migrate first, they unblock everything)

| ID | Class | File | Impact | Risk |
|----|-------|------|--------|------|
| CRIT-1 | `WorkoutStoreV2` | `Features/WorkoutSession/Services/WorkoutStoreV2.swift` | Central data store; every workout view re-renders on any property change. Migration eliminates redundant re-renders. ⚠️ Update all `@StateObject var store = WorkoutStoreV2()` → `@State` | Medium |
| CRIT-2 | `ExerciseRepository` | `Features/ExerciseRepository/Services/ExerciseRepository.swift` | Same pattern. Exercise data is read by many views but changes infrequently — all views currently re-render on any change | Medium |
| CRIT-3 | `AppSettings` | `Core/Configuration/AppSettings.swift` | ⚠️ **Breaking change.** Must update ALL `@EnvironmentObject` injection sites → `.environment(AppSettings.shared)` AND all `@EnvironmentObject var settings` → `@Environment(AppSettings.self) var settings` in a single commit. Missing either side causes a runtime crash, not a compile error | High |
| CRIT-4 | `HRZoneCalculator` | `Core/Utilities/HRZoneCalculator.swift` | Fewer consumers; same migration pattern. Lower priority | Low |

---

### HIGH (26 ViewModels)

Migration pattern is identical for all 26: remove `ObservableObject` conformance, remove all `@Published`, add `@Observable` to the class, add `@ObservationIgnored` to internal properties (cancellables, queues, timers).

View-side changes:
- `@StateObject` → `@State`
- `@ObservedObject` → plain property (or `@Bindable` if bindings are needed)

Priority targets (highest `@Published` count and usage frequency):

| ViewModel | @Published count | File | Notes |
|-----------|-----------------|------|-------|
| `ExerciseSessionViewModel` | 12 | `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift` | Highest impact — active during workouts |
| `ExerciseSearchVM` | 6 | `Features/Planner/ViewModels/ExerciseSearchVM.swift` | Used during exercise search |
| `FeedViewModel` | ~6 | `Features/Social/ViewModels/FeedViewModel.swift` | Social feed |
| `ChallengesViewModel` | ~5 | `Features/Challenges/ViewModels/ChallengesViewModel.swift` | |
| `BattleViewModel` | ~5 | `Features/Battles/ViewModels/BattleViewModel.swift` | |
| 21 remaining ViewModels | varies | Various | Migrate after singletons |

**Existing functionality impact:** Fine-grained observation means fewer re-renders — a performance improvement, not a behaviour change. No user-visible functional changes.

**Fix risk:** Medium per class. The migration is mechanical but `@Observable` classes are not `Sendable` — if any ViewModel is passed across actor boundaries, concurrency issues may surface.

---

### MEDIUM

| ID | Problem | Files | Impact | Risk |
|----|---------|-------|--------|------|
| Deprecated `onChange` | 2 instances of `onChange(of:perform:)` — deprecated in iOS 17 | `Features/Statistics/Views/ProfileStatsSection.swift:177-178` | Change to two-parameter form `{ _, newValue in }`. No behaviour change | Low |
| 12 service classes | `RestTimerPreferences`, `CustomSplitStore`, `FavoritesStore`, `ExerciseCache` etc. — `ObservableObject` | Various | Same migration pattern. Lower priority — migrate after ViewModels | Medium |
| Completion handlers | `PushNotificationService` uses callback-based API | `Core/Services/PushNotificationService.swift` | Convert to `async throws`. No behaviour change | Low |

### Breaking Change Reference

| Change | What breaks if done wrong |
|--------|--------------------------|
| `@EnvironmentObject` → `@Environment` | **Runtime crash** if injection site not updated alongside access site |
| `@StateObject` → `@State` | Compile error if `@StateObject` init syntax is used |
| `@ObservedObject` → plain property | Compile error if old attribute is left; need `@Bindable` for `$binding` access |
| `@Observable` + Combine `.sink` on `$property` | `@Observable` does not vend `@Published` publishers — restructure or use `withObservationTracking` |

---

## Remediation Order

### Before Next App Store Submission

1. **[Security CRITICAL-1]** Create `PrivacyInfo.xcprivacy` — **automatic submission rejection without this**
2. **[Security CRITICAL-3]** Migrate auth tokens to Keychain — plan migration to avoid forced sign-out
3. Verify `AuthKey_623J5TADK8.p8` is not in git history: `git log --all -- AuthKey_623J5TADK8.p8`

### Sprint 1 — High-Impact Safety Fixes (no virtual run risk)

4. **[Memory HIGH-1]** ExerciseSessionViewModel observer fix (bug fix — eliminates N-fold store reads)
5. **[Memory HIGH-3]** LiveActivityManager double-timer fix
6. **[Memory CRIT-1]** QueryCache timer storage
7. **[Concurrency CRIT-1,2]** WinScreenCoordinator and LiveActivityManager isolation fixes
8. **[Concurrency HIGH-1,2]** Remove nonisolated(unsafe); RewardsEngine weak self
9. **[Energy HIGH-1,2,5]** Animation onDisappear cleanup (all skeleton + WinScreen + Challenges + Battles)
10. **[Energy HIGH-3]** Remove unused `fetch` UIBackgroundMode
11. **[Energy MED-3]** BGProcessingTask requiresExternalPower = true
12. **[Security HIGH-1, MEDIUM-1]** APNS token persistence and logging

### Sprint 2 — Infrastructure (moderate virtual run touch)

13. **[Concurrency CRIT-3]** WCSession delegate pattern fix (all 26 sites) — **run virtual run end-to-end after**
14. **[Concurrency HIGH-6]** VirtualRunInviteCoordinator Task fix — **run invite flow after**
15. **[Energy CRIT-4]** GPS accuracy reduction on Watch
16. **[Energy CRIT-1b]** Rest timer 10Hz → 1Hz
17. **[Energy CRIT-2]** Replace invite polling with foreground notification
18. **[Energy CRIT-5 partial]** Remove `persistState()` from per-snapshot cycle only
19. **[Memory MEDIUM-2]** Long-press timer onDisappear fixes
20. **[Energy HIGH-6]** Darwin notifications for widget commands (both targets)

### Sprint 3 — Virtual Run Timing (test thoroughly)

21. **[Energy CRIT-3]** DB persist timer: extend to 5 minutes (Option B)
22. **[Energy CRIT-5]** Consider snapshot interval increase (2s → 3s) — verify connection health UX
23. **[Energy MED-2]** Replace partner route polling with Realtime subscription

### Sprint 4 — Modernization

24. Migrate 4 singletons to `@Observable` (especially `AppSettings` — breaking change, do atomically)
25. Migrate 26 ViewModels to `@Observable`
26. Update 35 `@StateObject` → `@State` and 20 `@ObservedObject` → plain property / `@Bindable`
27. Fix 2 deprecated `onChange` usages
28. Migrate 12 service classes

---

## Virtual Run — Issues That Touch the Feature

The following items from this audit interact with virtual run functionality. Consult `docs/virtual-run-implementation.md` before making changes and run a full end-to-end virtual run after each:

| Issue | Risk | What to verify |
|-------|------|----------------|
| Concurrency CRIT-3 | Medium | WCSession message types, `"type"` / `"messageType"` key asymmetry, snapshot delivery, partner-finished |
| Concurrency HIGH-6 | Medium | Invite reception, `isInActiveRun` flag, Realtime subscription |
| Energy CRIT-2 | Low-Medium | Invite delivery after foreground resume |
| Energy CRIT-3 | Medium | Crash recovery if snapshots fail |
| Energy CRIT-5 (heartbeat) | **High** | Connection health display (stale/disconnected thresholds), `checkExtendedDisconnect()` timing |
| Energy CRIT-5 (snapshot) | Medium | Partner interpolation smoothness with 3–5s intervals |
| Energy MED-1 (URLSession) | Medium | Snapshot delivery during Low Power Mode |
