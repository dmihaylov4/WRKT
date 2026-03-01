# Virtual Run — Implementation Reference

This document describes how the virtual run feature works end-to-end. Its purpose is to
prevent regressions when making future changes. Read the relevant section before touching
any of the files listed below.

---

## System Overview

Two users run simultaneously, each on their own Apple Watch. The Watch is the source of
truth for live stats. The iPhone acts as a relay: it forwards Watch snapshots to Supabase
(Realtime broadcast), receives the partner's snapshots back, and forwards them to the local
Watch. The iPhone also manages the invite flow, the HealthKit route upload after the run,
and the post-run summary.

```
Watch A ──snapshots──▶ iPhone A ──Supabase broadcast──▶ iPhone B ──partner update──▶ Watch B
Watch B ──snapshots──▶ iPhone B ──Supabase broadcast──▶ iPhone A ──partner update──▶ Watch A
```

---

## Key Files

| File | Role |
|---|---|
| `WRKT Watch Watch App/VirtualRunManager.swift` | Watch-side state machine, timers, GPS, haptics |
| `WRKT Watch Watch App/WatchConnectivityManager.swift` | Watch↔iPhone WCSession messaging |
| `WRKT Watch Watch App/WatchHealthKitManager.swift` | HKWorkoutSession for the run |
| `WRKT Watch Watch App/Views/VirtualRunView.swift` | Watch UI (split screen, overlays) |
| `WRKT Watch Watch App/Utilities/VirtualRunAudioCues.swift` | TTS audio feedback |
| `Core/Services/WatchConnectivityManager.swift` | iPhone↔Watch WCSession messaging |
| `Features/Social/Services/VirtualRunInviteCoordinator.swift` | Invite flow, Realtime, partner-finished detection |
| `Features/Social/Services/VirtualRunRepository.swift` | Supabase DB operations |
| `Features/Health/Services/HealthKitManager.swift` | Route fetch after run (iOS) |
| `Shared/VirtualRunSharedModels.swift` | Shared constants, `VirtualRunSnapshot`, `PartnerStats` |

---

## Phase 1 — Invite Flow (iOS only)

1. **Inviter** sends invite → Supabase creates a `virtual_runs` row with `status = pending`.
   - `VirtualRunInviteCoordinator.trackSentInvite()` stores `sentInviteId` and sets
     `isWaitingForAcceptance = true`.
   - Realtime subscription + 30-second fallback poll watches for the row to go `.active`.

2. **Invitee** receives the invite row via Realtime (or poll).
   - `pendingInvite` is set; a banner appears on iPhone.
   - User taps Accept → `acceptInvite()` → Supabase RPC sets `status = active`.

3. **Both sides** detect `status = active`:
   - Subscribe to Realtime snapshot channel for `runId`.
   - Fetch partner's profile (for `maxHR`).
   - Call `WatchConnectivityManager.sendVirtualRunStarted(...)` to notify their Watch.

**Invariant**: `VirtualRunInviteCoordinator.isInActiveRun` must be `true` while the run is
active so that the partner-finished detection logic fires on Realtime updates. It is reset
in `runEnded()`, which is called both when the Watch ends the run and when the iOS run
coordinator detects completion.

---

## Phase 2 — Watch Notification & Confirmation

`sendVirtualRunStarted` on iPhone sends the same message **twice**:
1. `session.sendMessage(...)` — instant delivery if Watch is awake.
2. `session.transferUserInfo(...)` — guaranteed delivery even if Watch is asleep.

The Watch deduplicates using `lastProcessedVRRunId` (persisted in `UserDefaults`).

On Watch, `handleVirtualRunStarted` calls `VirtualRunManager.setPendingRun(...)`, which:
- Sets `phase = .pendingConfirmation`.
- Starts a 60-second confirmation timeout (auto-decline if user ignores).
- Schedules a time-sensitive local notification to wake the Watch screen.

User taps **Go!** → `confirmRun()`:
- Sends `vrWatchConfirmed` with a `startTime` timestamp to iPhone (coordinated start).
- Transitions to `phase = .countdown(3)`.
- Starts a 3-second timer, then calls `finishCountdownAndStart()`.

**Invariant**: Do not call `VirtualRunManager.startVirtualRun()` directly — always go
through `finishCountdownAndStart()` so the HK session starts atomically with the run state.

---

## Phase 3 — Active Run

### Watch-side timers (started in `startTimers()`)

| Timer | Interval | Purpose |
|---|---|---|
| `heartbeatTimer` | 3 s | Sends heartbeat to iPhone; calls `checkExtendedDisconnect()` |
| `statsPublishTimer` | 2 s (5 s low-battery) | Reads HK data, publishes snapshot to iPhone |
| `batteryTimer` | 60 s | Checks battery level; enables low-battery mode below 20% |

Interpolation is driven by `TimelineView(.periodic(from:by: 1.0))` in `VirtualRunView`,
not by a timer. `PartnerStats.interpolate()` is called on each tick to smooth partner
distance between snapshots.

### Snapshot flow

1. `publishCurrentStats()` reads `WatchHealthKitManager.shared.distance` and `.heartRate`.
2. `updateMyStats(...)` applies Kalman-filtered GPS, increments `localSeq`, builds a
   `VirtualRunSnapshot`, and calls `WatchConnectivityManager.sendMessage(type: .snapshot, ...)`.
3. iPhone `WatchConnectivityManager.handleVirtualRunSnapshot` forwards it to Supabase via
   `VirtualRunRepository.publishSnapshot(snapshot)`.
4. Supabase Realtime broadcasts to the partner's iPhone.
5. Partner's iPhone `VirtualRunInviteCoordinator` receives it (via snapshot subscription)
   and calls `WatchConnectivityManager.sendVirtualRunPartnerUpdate(snapshot)`.
6. Partner's Watch receives `vrPartnerUpdate` → `receivePartnerUpdate(snapshot)` →
   `PartnerStats.update(from:)` (seq-guarded, out-of-order snapshots are dropped).

### Compact encoding

WCSession payloads use single-character keys to stay under the 65 KB message limit:

```
"d" = distanceM   "t" = durationS   "p" = paceSecPerKm
"h" = heartRate   "k" = calories    "la" = latitude   "lo" = longitude
"s" = seq         "c" = clientRecordedAt (Unix timestamp)
"r" = runId       "u" = userId      "pa" = isPaused
```

---

## Phase 4 — HealthKit Session

`VirtualRunManager.finishCountdownAndStart()` calls
`WatchHealthKitManager.shared.startRunningWorkout()`, which calls the private
`startWorkout(activityType: .running, locationType: .outdoor)`.

Key points:
- **`typesToShare`** must include `heartRate`, `activeEnergyBurned`, `distanceWalkingRunning`,
  `workoutType`, and `workoutRoute`. Without the quantity types, `HKLiveWorkoutDataSource`
  cannot write them.
- **`routeBuilder`** (`HKWorkoutRouteBuilder`) is created only for `.outdoor` workouts.
  It receives filtered GPS locations (accuracy < 50 m) from `CLLocationManagerDelegate`.
- **`CLLocationManager.desiredAccuracy` must remain `kCLLocationAccuracyBest`** for outdoor
  workouts. On Apple Watch the GPS chip is shared hardware between the `CLLocationManager`
  (route builder) and the `HKWorkoutSession` (distance tracking). Setting a lower accuracy
  (e.g. `kCLLocationAccuracyNearestTenMeters`) prevents the chip from acquiring satellite
  lock, which causes `HKLiveWorkoutDataSource` to never deliver `distanceWalkingRunning`
  samples — distance stays 0 for the entire run while heart rate (optical sensor) continues
  to work. `distanceFilter` does not affect GPS chip mode and can be tuned independently.
- `routeBuilder.finishRoute(with: workout, metadata: nil)` is called inside `endWorkout()`
  after `builder.finishWorkout()` completes. This is async and can take several seconds.

### Race condition guard (critical)

`endWorkout()` **immediately** nils `self.session` and `self.builder` and captures them into
local variables before starting any async work. This prevents a concurrent `startWorkout()`
call (e.g., a strength workout starting while the route is still being finalised) from having
its new session wiped by the cleanup of the old one.

```swift
// DO NOT revert this pattern:
let sessionToEnd = session
let builderToEnd = builder
let routeBuilderToEnd = routeBuilder
isWorkoutActive = false
self.session = nil
self.builder = nil
// ... async work uses sessionToEnd / builderToEnd / routeBuilderToEnd ...
```

---

## Phase 5 — Partner Finished

The iOS side detects partner completion via Supabase Realtime:
- `VirtualRunInviteCoordinator.handleRunStatusChanged` sees partner stats appear on the
  `virtual_runs` row (`inviteeDurationS != nil` / `inviterDurationS != nil`).
- Calls `WatchConnectivityManager.sendVirtualRunPartnerFinished(...)`, which sends via **both**
  `sendMessage` (instant) and `transferUserInfo` (guaranteed).

On Watch:
- `handleVirtualRunPartnerFinished` → `VirtualRunManager.handlePartnerFinished(...)`.
- Sets `partnerHasFinished = true` (permanent for the run lifetime) and
  `showPartnerFinished = true` (transient — cleared when overlay is dismissed).
- Shows `partnerFinishedOverlay` with distance + pace and "Keep Going" / "End My Run".

**`checkExtendedDisconnect()` is guarded by `partnerHasFinished`** (not `showPartnerFinished`).
After the partner finishes their Watch stops sending data, making their status appear
`.disconnected`. Without this guard the "Partner Lost" notification would fire every 3 minutes
for as long as the local runner continues. The permanent flag survives overlay dismissal.

```swift
// DO NOT change this guard to showPartnerFinished:
guard !partnerHasFinished else { return }
```

---

## Phase 6 — Run End

### Watch-initiated (user taps "End Run")

1. `requestEndRun()` sends `vrRunEnded` via **both** `sendMessage` and `transferUserInfo`.
2. `endVirtualRun()` stops all timers, resets all state.
3. `WatchHealthKitManager.shared.endWorkout(discard: false)` saves the HK workout.

### iPhone-initiated (cancelled from iOS side)

1. `WatchConnectivityManager.sendVirtualRunEnded()` sends `vrRunEnded` via `sendMessage`.
2. Watch `handleVirtualRunEnded()` → `VirtualRunManager.endVirtualRun()` +
   `WatchHealthKitManager.shared.endWorkout(discard: false)`.

### Deduplication

`vrRunEnded` may arrive **twice** (once from `sendMessage`, once from `transferUserInfo`).
- iPhone side: deduped by `lastProcessedVREndRunId` (persisted in `UserDefaults`).
- Watch side: `endVirtualRun()` sets `phase = .idle` on the first call;
  subsequent calls to `endWorkout()` are no-ops because `isWorkoutActive` is already `false`.

---

## Phase 7 — Route Upload (iOS, after run)

After `handleVirtualRunEnded` on iPhone:
1. `uploadVirtualRunRoute(runId:userId:)` is called in a background Task.
2. It polls `findRecentRunningWorkout()` (HK query, 15-minute window) with up to **18 retries
   at 10-second intervals** (3-minute total window). Watch→iPhone HealthKit sync takes
   30–60 seconds after the workout ends.
3. Once the workout is found, `HealthKitManager.shared.fetchRouteWithHeartRate(for:)` fetches
   GPS + HR data.
4. Route is Douglas-Peucker simplified and uploaded to Supabase Storage as
   `VirtualRunRouteData`.

**Invariant**: Do not shorten the retry window or reduce the delay. Watch HealthKit sync is
inherently slow — 18 × 10 s = 3 min is the minimum reliable window.

---

## Partner Snapshot Delivery — Known Failure Modes & Mitigations

### Problem 1: Watch not reachable — silent message drop

`WCSession.isReachable` is `true` on iPhone only when the Watch app is in the foreground. When
the user lowers their wrist, the Watch app backgrounds, making `isReachable = false`. The original
code silently dropped partner snapshot messages in this state.

**Fix (iOS `WatchConnectivityManager`):**
- Added `pendingPartnerSnapshot: VirtualRunSnapshot?` — stores the latest dropped snapshot.
- `sendVirtualRunPartnerUpdate` logs a warning and sets `pendingPartnerSnapshot` when not reachable.
- `sessionReachabilityDidChange` flushes `pendingPartnerSnapshot` immediately when Watch becomes
  reachable again (before the slower DB catch-up path).
- Only the **latest** snapshot is queued — older ones are stale and overwritten.
- `pendingPartnerSnapshot` is cleared alongside `lastPartnerSnapshot` in `sendVirtualRunStarted`.

### Problem 2: Dead broadcast WebSocket after app foreground during active run

iOS kills WebSocket connections ~5 seconds after the app suspends. The Supabase Realtime
`broadcastChannel` object persists in memory but its underlying WebSocket is dead. When the app
returns to the foreground, `isSubscribedToSnapshots` (based on `broadcastChannel != nil`) reports
`true` — but no `onUpdate` callbacks ever fire, so `sendVirtualRunPartnerUpdate` is never called.

**Fix (`VirtualRunInviteCoordinator.startListening()`):**
- Added an `else if isInActiveRun` branch alongside the existing `isWaitingForAcceptance` branch.
- When foregrounding during an active run, `subscribeToSnapshots(runId:onUpdate:)` is called
  unconditionally. `VirtualRunRepository.subscribeToSnapshots` always unsubscribes the existing
  channel before resubscribing, so it is safe to call mid-run.
- This gives a fresh WebSocket connection with the same `onUpdate` handler.

**Invariant**: Do not remove either the `pendingPartnerSnapshot` queue or the `isInActiveRun`
re-subscribe branch. Without them partner data silently stops flowing whenever the iPhones
leave the foreground.

### Pace calculation thresholds (expected behaviour for short test runs)

`publishCurrentStats()` only emits a non-nil pace when:
1. `currentDistance > 50 m` — below this the GPS noise dominates.
2. Computed pace ≤ 1800 sec/km (30 min/km cap).

Short indoor test runs (< 50 m) and walking-pace runs will correctly show `--` for pace.
This is not a bug — pace will display correctly on real outdoor runs.

---

## Connection Health & Disconnect Detection

`PartnerStats.connectionStatus` is computed from `dataAge` (time since last snapshot):

| Age | Status |
|---|---|
| < 8 s | `.connected` |
| 8–15 s | `.stale` |
| > 15 s | `.disconnected` |
| any (if `isPaused`) | `.paused` |

`checkExtendedDisconnect()` fires on every heartbeat (every 3 s). If the partner's status
is `.disconnected` for **3 continuous minutes**, `showDisconnectPrompt = true` and a haptic
fires. The user can dismiss ("Keep Waiting") or end the run.

This check is suppressed if `partnerHasFinished == true` (see Phase 5).

---

## WCSession Message Protocol

### Key naming rule

| Direction | Key for message type |
|---|---|
| iPhone → Watch (all messages) | `"type"` |
| Watch → iPhone (all messages) | `"messageType"` |

This asymmetry is intentional and load-bearing. **Do not unify these keys** without updating
both `handleIncomingMessage` (Watch) and `handleWatchMessage` (iPhone) simultaneously.

### iPhone → Watch messages (`"type"` key)

| Type value | Trigger | Delivery |
|---|---|---|
| `"workoutState"` | Any workout state change | `sendMessage` |
| `"startWatchWorkout"` | Explicit HK session start | `sendMessage` |
| `"endWatchWorkout"` | Explicit HK session end | `sendMessage` |
| `"discardWatchWorkout"` | Discard without saving | `sendMessage` |
| `"vr_started"` | Run accepted | `sendMessage` + `transferUserInfo` |
| `"vr_ended"` | Run cancelled from iPhone | `sendMessage` only |
| `"vr_partner"` | Partner snapshot update | `sendMessage` only |
| `"vr_partner_finished"` | Partner finished | `sendMessage` + `transferUserInfo` |
| `"vr_heartbeat"` | Connection keepalive | `sendMessage` only |

### Watch → iPhone messages (`"messageType"` key)

| Type value | Trigger | Delivery |
|---|---|---|
| `"vr_snapshot"` | Every 3 s during active run | `sendMessage` |
| `"vr_heartbeat"` | Every 3 s | `sendMessage` |
| `"vr_ended"` | User ends run | `sendMessage` + `transferUserInfo` |
| `"vr_watch_confirmed"` | User taps Go! | `sendMessage` |
| `"vr_pause"` / `"vr_resume"` | Pause / resume | `sendMessage` |
| `"completeSet"` etc. | Strength workout actions | `sendMessage` |

---

## Audio Cues (`VirtualRunAudioCues`)

`VirtualRunAudioCues.shared` uses `AVSpeechSynthesizer` with `.playback`/`.voicePrompt`
AVAudioSession (ducks other audio). It announces:
- Each completed kilometre.
- Lead changes (taking / losing the lead).
- Partner finished.

The session is activated before speech and deactivated in `speechSynthesizer(_:didFinish:)`.
Audio cues only fire during virtual runs. They do not affect the strength workout HK session.

---

## Timing Constants (do not reduce without testing)

```swift
snapshotPublishInterval  = 3.0 s   // Watch publishes stats to iPhone
heartbeatInterval        = 3.0 s   // Watch sends heartbeat; disconnect check fires
staleDataThreshold       = 8.0 s   // Partner shown as stale
disconnectThreshold      = 15.0 s  // Partner shown as disconnected
extendedDisconnectTimeout = 180 s  // "Partner Lost" prompt shown
routeUploadRetries       = 18      // × 10 s = 3 min window for HK sync
```

---

## Key Invariants — Do Not Break

1. **`typesToShare` on Watch** must include `heartRate`, `activeEnergyBurned`,
   `distanceWalkingRunning`, `workoutRoute`, and `workoutType`. Missing any of these silently
   prevents `HKLiveWorkoutDataSource` from collecting that metric.

2. **`endWorkout()` must capture `session`/`builder`/`routeBuilder` into locals and nil the
   instance properties before any `await`**. Reverting to the old pattern (nil-ing in
   `resetState()` at the end) causes the race condition where a concurrently-started strength
   workout gets its session wiped.

3. **`checkExtendedDisconnect()` must guard on `partnerHasFinished`**, not on
   `showPartnerFinished`. Using `showPartnerFinished` means the guard disappears when the
   user dismisses the overlay, re-triggering the notification every 3 minutes.

4. **`vrRunEnded` is deduped on both sides** via `lastProcessedVREndRunId` (iPhone,
   `UserDefaults`) and `isWorkoutActive` guard (Watch). Do not remove either.

5. **`lastProcessedVRRunId` (Watch) deduplicates `vrRunStarted`**. It is cleared in
   `handleVirtualRunEnded()` so the next run is not blocked.

6. **`VirtualRunInviteCoordinator.didSendPartnerFinished`** prevents double-sending
   `vrPartnerFinished`. It is reset in `runEnded()` and `startRunAsInviter()` / `acceptInvite()`.

7. **Supabase snapshot subscription** filters out the local user's own snapshots
   (`guard snapshot.userId != myId`). Removing this filter would create a feedback loop
   where each user's own data is echoed back as partner data.

8. **`PartnerStats.update(from:)` is seq-guarded** (`guard snapshot.seq > lastSeq`).
   Out-of-order or duplicate snapshots are silently dropped. The `seq` counter is local to
   each Watch session and starts at 0 on every `startVirtualRun()`.

9. **`CLLocationManager.desiredAccuracy` must be `kCLLocationAccuracyBest`** for outdoor
   running workouts. Reducing it (even to `kCLLocationAccuracyNearestTenMeters`) prevents
   satellite GPS lock on Apple Watch, silently breaking `HKLiveWorkoutDataSource` distance
   tracking for the entire run. This is a shared-hardware constraint, not a software bug.
   Do not change this in the name of energy optimisation without first verifying that distance
   still accumulates on a real outdoor run.
