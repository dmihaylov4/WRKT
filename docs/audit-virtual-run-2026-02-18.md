# WRKT — Virtual Running Feature Audit

**Date:** 2026-02-18
**Scope:** Comprehensive audit of the virtual running feature — reliability, energy, data consistency, UX gaps, architecture, and edge cases

---

## Architecture Overview

The virtual run feature spans 4 layers:

1. **Supabase backend** — invites, completion RPC, snapshot persistence, route storage
2. **iOS app** — invite coordination, Realtime subscription, Watch relay
3. **WatchConnectivity bridge** — bidirectional message passing
4. **watchOS** — HealthKit workout session, state machine, GPS, haptics, audio cues

**Data flow:** Watch collects stats via HealthKit → sends compact snapshot to iPhone via WCSession → iPhone publishes to Supabase Broadcast → partner's iPhone receives via Broadcast → relays to partner's Watch via WCSession. A periodic DB persist (every 30s) provides crash recovery alongside the ephemeral Broadcast channel.

---

## Summary

| Severity | Count | Key Themes |
|----------|-------|------------|
| CRITICAL | 3 | Orphaned active runs, missing DB column for pause state, no invite expiration |
| HIGH | 5 | Lost messages on unreachability, battery drain, polling lifecycle, trigger conflicts |
| MEDIUM | 8 | Kalman filter unused, persist time bug, queue priority, audio conflicts |
| LOW | 5 | UI semantics, localization, debug hardcodes |
| Gaps | 8 | No crash recovery on iOS, no indoor mode, no history UI, no connection indicator |

---

## CRITICAL Issues

### C1. Pause state not persisted to database snapshot schema

- **File:** `Shared/VirtualRunSharedModels.swift` (~line 61, `isPaused` field)
- **File:** Database migrations — no `is_paused` column exists on `virtual_run_snapshots`
- **Issue:** `VirtualRunSnapshot` has an `isPaused` field used in compact dict encoding and by `PartnerStats` to suppress stale/disconnect warnings while paused. However, the DB table `virtual_run_snapshots` has no `is_paused` column. The CDC fallback channel (used for reconnection/crash recovery) decodes snapshots from the DB which will never have `isPaused`, so after a reconnect the partner's pause state is lost.
- **Impact:** After a reconnection, a paused partner appears disconnected. The CDC fallback path can never convey pause state.
- **Recommendation:** Add `is_paused BOOLEAN DEFAULT FALSE` column to `virtual_run_snapshots` via a new migration. Alternatively, if pause state should remain ephemeral, document that CDC fallback does not preserve it and consider sending an explicit pause/resume broadcast event.

---

### C2. Race condition: `endVirtualRun()` called before `sendMessage` completes — run can be orphaned

- **File:** `WRKT Watch Watch App/VirtualRunManager.swift` (~lines 247–271, `requestEndRun()`)
- **Issue:** `requestEndRun()` calls `WatchConnectivityManager.shared.sendMessage(type: .runEnded, payload:)` and then immediately calls `endVirtualRun()`, which clears `currentRunId`, `myStats`, and `partnerStats`. The stats are captured into `payload` before the call, so data is safe. The real risk: the message is queued, but the Watch app terminates shortly after (since the workout ended), and the queued message is lost forever. The iPhone never receives the final stats, so the Supabase RPC is never called, and the run is orphaned as "active" forever.
- **Impact:** If the Watch-to-iPhone message delivery fails at run end, the run remains stuck in "active" status in the database with no final stats. There is no server-side timeout to auto-complete or auto-cancel stale active runs.
- **Recommendation:**
  1. Use `transferUserInfo` (guaranteed delivery) for the `runEnded` message — this survives app termination
  2. Add a server-side scheduled function (Supabase Edge Function on a cron) that auto-cancels runs that have been "active" for more than N hours (e.g., 6 hours) without any snapshot updates

---

### C3. No server-side expiration for pending invites

- **File:** `database_migrations/021_virtual_runs.sql`
- **File:** `Features/Social/Services/VirtualRunRepository.swift`
- **Issue:** Pending invites live in the database indefinitely with status "pending". The Watch has a 60-second confirmation timeout, but on the inviter side there is no timeout. If the invitee never opens the app, the inviter's `isWaitingForAcceptance` state persists until the fallback poll finds a status change. Pending invites are never auto-cancelled server-side and accumulate (capped at 5 per user by rate-limit trigger, but still clutter).
- **Impact:** A user who sent an invite to someone who never responded will have a stale "pending" invite. These count toward the 5-invite rate limit, blocking new runs.
- **Recommendation:** Add `expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '5 minutes'` column to `virtual_runs`. Create a Supabase scheduled function or Postgres cron job that cancels expired pending invites. On the client, check `expires_at` and auto-dismiss expired invites.

---

## HIGH Issues

### H1. `sendVirtualRunPartnerFinished` silently drops if Watch is unreachable

- **File:** `Core/Services/WatchConnectivityManager.swift` (~lines 1197–1212)
- **Issue:** Returns immediately if `session.isReachable` is false. If the Watch screen is off or the app is backgrounded when the partner finishes, the "partner finished" notification is lost.
- **Impact:** The Watch user continues running without knowing their partner already stopped. They only find out when they end their own run and see the summary.
- **Recommendation:** Use `transferUserInfo` for this message (guaranteed delivery), or store the event and retry on next reachability change.

---

### H2. VirtualRunInviteCoordinator polling continues forever

- **File:** `Features/Social/Services/VirtualRunInviteCoordinator.swift` (~lines 43–78)
- **Issue:** `startListening()` starts a 30-second fallback poll timer and a Realtime subscription that run indefinitely. `stopListening()` exists but is not called from any obvious lifecycle event (app backgrounding, logout, etc.).
- **Impact:** Unnecessary network requests every 30 seconds, wasted battery, and unnecessary Supabase Realtime connection when not needed.

#### Research Findings

**iOS WebSocket behavior in background:**
- iOS suspends apps ~5 seconds after backgrounding. When suspended, all timers stop and all WebSocket connections are silently killed by the OS.
- Supabase Realtime uses WebSockets internally. When the app is suspended, the server detects missing heartbeats and drops the connection — silently, with no error callback on the client.
- When the app returns to foreground, the WebSocket is dead but the Supabase client may not know it immediately. There can be a 15-30+ second delay before automatic reconnection.
- **Events during the background period are lost** — Supabase Realtime does NOT queue missed events server-side.

**What major apps do:**
- WhatsApp/Telegram: Maintain persistent socket in foreground. On background, drop connection entirely, rely on APNs for incoming messages. On foreground resume, reconnect + immediate sync to catch up.
- Strava: Uses background location mode during active workouts only. Social features are pure pull-to-refresh on foreground.
- **No iOS app tries to maintain WebSockets in background** for real-time features. The OS doesn't support it.

**Current state in WRKT:**
- `startListening()` is called once on app launch from `AppShellView.swift:432`
- `stopListening()` is **never called anywhere** in the codebase
- `scenePhase` observer exists in `AppShellView` but does not manage the invite coordinator lifecycle
- The invite coordinator is never restarted on foreground resume

#### Recommendation: Stop on background, restart on foreground

This is the correct and only viable approach. The implementation:

1. In `AppShellView.swift` `handleScenePhaseChange`:
   - On `.background`: call `inviteCoordinator.stopListening()` (invalidates timer, unsubscribes Realtime)
   - On `.active`: call `inviteCoordinator.startListening()` (re-subscribes, starts fresh timer, calls `pollOnce()` immediately to catch up)
2. The existing `guard !isListening` in `startListening()` prevents double-subscription
3. Push notifications (already implemented separately) handle truly backgrounded invite delivery

**Risk assessment:** Low. The `startListening()` method already polls immediately on start, catching any events missed during background. The only window for a missed event is the brief moment between app foregrounding and the first poll completing (~1 second).

---

### H3. GPS location at `kCLLocationAccuracyBest` on Watch drains battery

- **File:** `WRKT Watch Watch App/WatchHealthKitManager.swift` (~line 244)
- **Issue:** `desiredAccuracy` is set to `kCLLocationAccuracyBest` for location updates during outdoor workouts. The audit initially suggested this drains excessive battery.

#### Research Findings

**Apple's recommended practice:**
- Apple's own SpeedySloth sample app (the canonical workout app example) uses `kCLLocationAccuracyBest` with `activityType = .fitness` — which is exactly what WRKT does.
- Apple's Energy Efficiency Guide says to avoid `kCLLocationAccuracyBest` *unless* the app needs position within a few meters. **A workout route recording app is explicitly listed as a valid use case.**

**Practical hardware reality on Apple Watch:**
- The Apple Watch GPS chip is the limiting factor, not the software accuracy target. Real-world horizontal accuracy on Apple Watch averages **50-65 meters** regardless of the `desiredAccuracy` setting.
- Apple's documentation states: "Core Location typically provides more accurate data than you have requested." So `kCLLocationAccuracyNearestTenMeters` may produce nearly identical GPS behavior.
- The battery difference between `kCLLocationAccuracyBest` and `kCLLocationAccuracyNearestTenMeters` during an active `HKWorkoutSession` is **marginal (1-3% per hour at most)**, because the GPS radio is already continuously powered on for the workout session.
- Big battery savings only come from stepping down to `kCLLocationAccuracyHundredMeters` or `kCLLocationAccuracyKilometer`, which use Wi-Fi/cell triangulation instead of GPS — unsuitable for route recording.

**`HKWorkoutSession` vs `CLLocationManager`:**
- The `HKWorkoutSession` with `.outdoor` location type controls HealthKit's internal distance calculations but does NOT replace or override the app's `CLLocationManager.desiredAccuracy` setting. They are independent systems.
- WRKT correctly uses both: `HKWorkoutSession` for distance/HR/calories, and a separate `CLLocationManager` for raw GPS route recording via `HKWorkoutRouteBuilder`.

**Potential issue found:** The `gpsMinAccuracyMeters` filter of 20 meters (rejecting any location with `horizontalAccuracy >= 20`) is **very strict** for Apple Watch hardware where typical accuracy is 50-65 meters. This may discard many valid GPS fixes, leading to sparse route data.

#### Recommendation: Keep `kCLLocationAccuracyBest`, no change needed

The current setting follows Apple's recommended pattern for workout apps. Changing it would provide negligible battery savings while potentially reducing route quality. The setting is correct.

**Separate action item (new finding):** Consider relaxing `gpsMinAccuracyMeters` from 20m to 50m for Apple Watch, as the current threshold likely discards the majority of valid GPS fixes on Watch hardware.

---

### H4. No handling for HealthKit authorization revocation mid-run

- **File:** `WRKT Watch Watch App/WatchHealthKitManager.swift`
- **Issue:** If the user revokes HealthKit permissions while a virtual run is active, `HKLiveWorkoutBuilder` silently stops receiving data. There is no observer for authorization changes. `workoutSession(_:didFailWithError:)` only calls `resetState()` but does not notify the virtual run system.
- **Impact:** User's stats freeze at last known value. Partner sees stale data. The run can continue indefinitely with no meaningful metrics.
- **Recommendation:** Observe `HKHealthStore.authorizationStatus` changes. If critical permissions are revoked, notify `VirtualRunManager` to show a warning or end the run gracefully.

---

### H5. Potential trigger name mismatch in snapshot rate limit migrations

- **File:** `database_migrations/024_virtual_runs_p1_broadcast.sql` (creates `enforce_snapshot_rate_limit`)
- **File:** `database_migrations/026_virtual_runs_p3_complete.sql` (drops `trg_check_snapshot_rate_limit`, creates `trg_check_snapshot_plausibility`)
- **Issue:** Migration 026 drops `trg_check_snapshot_rate_limit`, but migration 024 created the trigger as `enforce_snapshot_rate_limit`. Name mismatch means the old trigger may still exist alongside the new one, causing double validation or unexpected failures.
- **Impact:** Potential DB persist failures or redundant trigger execution.
- **Recommendation:** Verify in production. Add a cleanup migration: `DROP TRIGGER IF EXISTS enforce_snapshot_rate_limit ON virtual_run_snapshots;`.

---

## MEDIUM Issues

### M1. Kalman filter result is discarded

- **File:** `WRKT Watch Watch App/VirtualRunManager.swift` (~lines 515–517)
- **Issue:** `_ = kalmanFilter.process(lat:lon:accuracy:)` — the smoothed result is discarded. Raw lat/lon is used in the snapshot.
- **Impact:** GPS jitter is not smoothed despite the infrastructure being in place.
- **Recommendation:** Use the return value: `let smoothed = kalmanFilter.process(...)` and pass `smoothed.lat`/`smoothed.lon` to the snapshot.

---

### M2. `persistState()` saves `startedAt: Date()` instead of actual start time

- **File:** `WRKT Watch Watch App/VirtualRunManager.swift` (~line 651)
- **Issue:** Creates `VirtualRunState` with `startedAt: Date()` (current time) instead of the actual `runStartTime`. Called on every stats update.
- **Impact:** After crash recovery, the elapsed time calculation would be incorrect — showing a much shorter duration than the actual run.
- **Recommendation:** Change to `startedAt: runStartTime ?? Date()`.

---

### M3. Watch message queue has a fixed size of 10 with FIFO eviction — no priority

- **File:** `WRKT Watch Watch App/WatchConnectivityManager.swift` (~lines 177–183)
- **Issue:** When the iPhone is unreachable, messages are queued up to 10. Older messages are dropped. Snapshot messages fire every 2s. If the iPhone is unreachable for 20+ seconds, critical messages (`runEnded`, `pause`, `resume`) could be evicted by routine snapshots.
- **Impact:** The `runEnded` message could be dropped, leaving the run in a stuck state.
- **Recommendation:** Implement priority queuing: never evict `runEnded`, `pause`, or `resume` messages. Only evict older snapshots (keep the latest).

---

### M4. `lastPartnerSnapshot` used for winner determination before RPC completes

- **File:** `Core/Services/WatchConnectivityManager.swift` (~lines 879–887)
- **Issue:** When the Watch ends the run, `handleVirtualRunEnded` uses `lastPartnerSnapshot?.distanceM` to determine `winnerIsMe` for telemetry. This snapshot may be several seconds stale.
- **Impact:** Telemetry data for `winner_is_me` may be inaccurate. Not user-facing but misleading for analytics.
- **Recommendation:** Log telemetry after the RPC response (which returns the completed run JSON), or mark as "estimated".

---

### M5. No cleanup of Realtime subscriptions on app termination

- **File:** `Features/Social/Services/VirtualRunRepository.swift`
- **Issue:** If the app is force-quit or crashes, Realtime channels are not cleaned up.
- **Impact:** Minor server resource waste. Supabase handles this via WebSocket timeouts.
- **Recommendation:** Acceptable as-is.

---

### M6. Both `endRun()` and `completeRun()` exist on VirtualRunRepository

- **File:** `Features/Social/Services/VirtualRunRepository.swift` (~lines 204–242 and 449–471)
- **Issue:** `endRun()` directly updates the row client-side. `completeRun()` uses the server-side RPC with two-phase completion. `endRun()` is still used by the debug view. If accidentally called in production, it would bypass two-phase completion and could overwrite the partner's stats.
- **Impact:** Data corruption risk if misused.
- **Recommendation:** Gate `endRun()` behind `#if DEBUG` or remove it.

---

### M7. `pausedElapsedBeforePause` variable name is misleading

- **File:** `WRKT Watch Watch App/VirtualRunManager.swift` (~lines 306–314)
- **Issue:** The variable accumulates total paused time across multiple pauses. The name suggests it only tracks the elapsed time before a single pause.
- **Impact:** No functional bug. Confusing for maintenance.
- **Recommendation:** Rename to `totalPausedTime`.

---

### M8. Audio cues via AVSpeechSynthesizer may conflict with music playback

- **File:** `WRKT Watch Watch App/Utilities/VirtualRunAudioCues.swift`
- **Issue:** `AVSpeechSynthesizer` ducks or pauses currently playing audio. `stopSpeaking(at: .immediate)` before each utterance causes abrupt audio interruptions.
- **Impact:** Users running with music experience audio ducking at every kilometer, lead change, and partner finish.
- **Recommendation:** Use `AVAudioSession` with `.duckOthers` mixing, or add a "minimal" mode that only uses haptics.

---

## LOW Issues

### L1. Summary view highlights longer duration as "winner"

- **File:** `Features/Social/Views/VirtualRunSummaryView.swift` (~lines 34–37)
- **Issue:** Duration stat row marks longer time as winning. For running, longer duration is not necessarily better.
- **Recommendation:** Show duration as neutral (no win/loss highlight), or clarify it represents "time on feet".

---

### L2. `shortenedName()` doesn't handle long single-word usernames

- **File:** `Features/Social/Views/VirtualRunSummaryView.swift` (~lines 212–215)
- **Issue:** `shortenedName("john_doe_123")` returns the full string, which could break layout.
- **Recommendation:** Truncate to max 12 characters with ellipsis.

---

### L3. VirtualRunFileLogger — correctly isolated (no issue)

- **File:** `WRKT Watch Watch App/Utilities/VirtualRunFileLogger.swift`
- **Issue:** None. Correctly uses `@MainActor` for thread safety.

---

### L4. Debug view hardcodes a test user ID

- **File:** `Features/Social/Views/VirtualRunDebugView.swift` (~line 40)
- **Impact:** Minimal. Debug-only code.

---

### L5. No localization for audio cue strings

- **File:** `WRKT Watch Watch App/Utilities/VirtualRunAudioCues.swift`
- **Issue:** Audio cue strings ("1 kilometer", "Partner finished", etc.) are hardcoded in English.
- **Recommendation:** Use `String(localized:)` for these strings.

---

## Missing Features / Gaps

### Gap 1: No connection quality indicator on Watch UI

There is a `ConnectionHealth` struct and `PartnerStats.connectionStatus` enum, but no Watch UI component shows the user whether their connection to the partner is healthy, stale, or disconnected. The `showDisconnectPrompt` only triggers after 3 minutes of extended disconnect.

**Recommendation:** Add a small connection indicator (green/yellow/red dot) to the Watch virtual run UI.

---

### Gap 2: No crash recovery on the iOS side

The Watch has `persistState()` / `restoreStateIfNeeded()` for crash recovery, but the iOS side has no equivalent. If the iPhone app crashes mid-run, the virtual run state is lost. The Watch continues running, but snapshots cannot be forwarded to Supabase.

**Recommendation:** Persist `activeVirtualRunId` and `activeVirtualRunUserId` to UserDefaults on the iOS side. On app launch, check for an active run in the DB and re-subscribe to Realtime channels.

---

### Gap 3: No treadmill / indoor mode support

`startRunningWorkout()` always uses `.outdoor` location type. If both users are on treadmills, GPS is engaged unnecessarily.

**Recommendation:** Add an option to start a virtual run in "indoor" mode, skipping GPS and route recording.

---

### Gap 4: No synchronized countdown between both users

When the invitee accepts, the inviter's Watch starts its countdown independently based on message arrival time. There is no mechanism to ensure both Watches start at exactly the same moment.

**Recommendation:** Use the server timestamp from `started_at` as the coordinated start time. Both clients should compute their countdown relative to that timestamp.

---

### Gap 5: No support for "catch-up" after reconnection

`fetchLatestSnapshot()` exists in the repository but is never called in production code. After reconnection, partner stats jump from the last-received value to the current value with no transition.

**Recommendation:** Call `fetchLatestSnapshot()` on reconnection (when `sessionReachabilityDidChange` fires as reachable) and update `partnerStats`.

---

### Gap 6: No run history or past results view

The repository has `fetchCompletedRuns()` but there is no UI to browse past virtual runs. The summary overlay is ephemeral.

**Recommendation:** Add a virtual run history section accessible from the social/profile tab.

---

### Gap 7: No re-invite or rematch capability

After a run completes, there is no way to quickly start another run with the same partner.

**Recommendation:** Add a "Run Again" button on the summary screen that pre-fills the invite.

---

### Gap 8: Route comparison map ✅ ALREADY IMPLEMENTED

`VirtualRunMapComparisonView` already exists as page 2 of `VirtualRunSummaryPager`. It shows dual static map snapshots with HR-gradient polylines, start/end markers, and stat pills (distance, pace, HR) for both runners. Routes are uploaded to Supabase Storage after the run, with polling + retry for partner's route. No action needed.

---

## Fix Status

| Issue | Status | Notes |
|-------|--------|-------|
| C1 | FIXED | Migration `030_virtual_run_pause_and_expiry.sql` adds `is_paused` column. No client changes needed — `VirtualRunSnapshot` already maps `isPaused` to `"is_paused"` via CodingKeys. |
| C2 | FIXED | Dual delivery (sendMessage + transferUserInfo) for `runEnded`. iOS `didReceiveUserInfo` handler added. Dedup via `lastProcessedVREndRunId` in UserDefaults. Server-side stale run cleanup via pg_cron (migration 031). |
| C3 | FIXED | Migration `030` adds `expires_at` column with auto-set trigger. Client filters expired invites in `VirtualRunInviteCoordinator`. pg_cron job registered in Supabase. |
| H1 | FIXED | `sendVirtualRunPartnerFinished` now sends via both `sendMessage` (instant) and `transferUserInfo` (guaranteed). Watch deduplicates via `guard !showPartnerFinished`. |
| H2 | FIXED | `stopListening()` called on `.background`, `startListening()` called on `.active` in `AppShellView.handleScenePhaseChange`. Immediate `pollOnce()` on restart catches missed events. |
| H3 | NO CHANGE | `kCLLocationAccuracyBest` is Apple's recommended setting for workout apps. Battery difference is marginal. |
| H4 | FIXED | HealthKit data staleness detection in `publishCurrentStats()`. Sets `showHealthDataWarning` when distance freezes and HR is nil for 30s+. Auto-resets when data resumes. |
| H5 | FIXED | Migration `032_cleanup_duplicate_snapshot_trigger.sql` drops orphaned `enforce_snapshot_rate_limit` trigger and its function. |
| M1 | FIXED | Kalman filter output now used for snapshot coordinates instead of being discarded. |
| M2 | FIXED | `persistState()` now uses `runStartTime ?? Date()` instead of `Date()`. |
| M3 | FIXED | Priority message queuing: critical messages protected from eviction. Non-critical messages evicted first. |
| M4 | FIXED | Telemetry logged after RPC attempt. `partnerDistance` captured before async Task to avoid stale reference. |
| M6 | FIXED | `endRun()` wrapped in `#if DEBUG`. Production uses `completeRun()` RPC exclusively. |
| M7 | FIXED | Renamed `pausedElapsedBeforePause` to `totalPausedDuration` for clarity. |
| M8 | FIXED | Audio session configured with `.duckOthers` for music-friendly speech. `AVSpeechSynthesizerDelegate` deactivates session after speech to restore volume. |
| GPS | FIXED | `gpsMinAccuracyMeters` relaxed from 20m to 50m. Old threshold discarded most valid Watch GPS fixes. |
| Gap 1 | NO CHANGE | Connection indicator already exists in `VirtualRunView.connectionStatus()`. |
| Gap 2 | FIXED | Active run state (`runId`, `userId`, `partnerName`) persisted to UserDefaults via `didSet`. Restored on app launch in `setupSession()`. |
| Gap 5 | FIXED | `fetchLatestSnapshot()` called on reconnect in `sessionReachabilityDidChange` to catch up partner position. |
| Server | CREATED | Migration `031_stale_run_cleanup.sql` — pg_cron job runs hourly, cancels stale active runs. Must be run manually in SQL editor. |

---

## C2 Deep Analysis: Guaranteed Delivery for `runEnded`

### The Problem

When the Watch user ends a virtual run, `VirtualRunManager.requestEndRun()` sends the final stats to iPhone via `WCSession.sendMessage()` (instant but requires reachability) and then immediately calls `endVirtualRun()` which clears all state. If the iPhone is momentarily unreachable, the message gets queued on the Watch side (max 10 messages, FIFO eviction). If the Watch app terminates shortly after (which it will, since the workout session just ended), the queued message is lost. The iPhone never receives final stats, the Supabase RPC is never called, and the run is permanently orphaned as "active".

### Current Architecture

```
Watch                          iPhone                    Supabase
─────                          ──────                    ────────
requestEndRun()
  ├─ sendMessage(.runEnded) ──→ didReceiveMessage()
  │                              ├─ handleVirtualRunEnded()
  │                              │   ├─ completeRun() RPC ──→ UPDATE virtual_runs
  │                              │   ├─ awaitPartner()
  │                              │   └─ uploadRoute()
  └─ endVirtualRun() (clears state)
```

**Failure point:** If `sendMessage` fails (Watch unreachable, iPhone app backgrounded), everything downstream never happens.

### Why `transferUserInfo` Alone Won't Work

The current approach for `vrRunStarted` (iPhone → Watch) uses both `transferUserInfo` AND `sendMessage`:
- `transferUserInfo` for guaranteed delivery (survives app termination)
- `sendMessage` for instant delivery (when reachable)
- Watch deduplicates via `lastProcessedVRRunId` in UserDefaults

For `runEnded` (Watch → iPhone), there's a critical gap: **the iOS `WatchConnectivityManager` does NOT implement `session(_:didReceiveUserInfo:)`**. It only implements `didReceiveMessage`. So even if the Watch sends via `transferUserInfo`, the iPhone would never receive it.

### Recommended Approach: Belt and Suspenders

**Layer 1: Dual delivery from Watch (immediate + guaranteed)**

On the Watch side in `requestEndRun()`, send via both channels:

```swift
func requestEndRun() {
    var payload: [String: Any] = [:]
    if let stats = myStats {
        payload["distance"] = stats.distanceM
        payload["duration"] = stats.durationS
        if let pace = stats.currentPaceSecPerKm { payload["pace"] = pace }
        if let hr = stats.heartRate { payload["heartRate"] = hr }
    }
    if let runId = currentRunId {
        payload["runId"] = runId.uuidString
    }

    // 1. Instant delivery (if reachable)
    WatchConnectivityManager.shared.sendMessage(type: .runEnded, payload: payload)

    // 2. Guaranteed delivery (survives app termination)
    var userInfoMsg: [String: Any] = ["messageType": WatchMessage.vrRunEnded.rawValue]
    if let data = try? JSONSerialization.data(withJSONObject: payload) {
        userInfoMsg["payload"] = data
    }
    WCSession.default.transferUserInfo(userInfoMsg)

    endVirtualRun()
}
```

**Layer 2: iOS receives `transferUserInfo`**

Add `session(_:didReceiveUserInfo:)` to the iOS `WatchConnectivityManager`:

```swift
nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    Task { @MainActor in
        self.handleIncomingMessage(userInfo)
    }
}
```

This is the same pattern already used on the Watch side (line 718 in Watch WatchConnectivityManager).

**Layer 3: Dedup on iOS**

Add a `lastProcessedVREndRunId` (similar to Watch's `lastProcessedVRRunId`) to prevent double-processing when both `sendMessage` AND `transferUserInfo` deliver:

```swift
private var lastProcessedVREndRunId: UUID? {
    get { UserDefaults.standard.string(forKey: "lastProcessedVREndRunId").flatMap(UUID.init) }
    set { UserDefaults.standard.set(newValue?.uuidString, forKey: "lastProcessedVREndRunId") }
}
```

In `handleVirtualRunEnded`, check and set this before processing.

**Layer 4: Server-side stale run cleanup (safety net)**

Even with guaranteed delivery, there are edge cases (both devices dead, iCloud account signed out, etc.). Add a server-side cleanup:

```sql
-- Via pg_cron (run every hour):
-- Cancel runs that have been 'active' for 6+ hours with no recent snapshot
SELECT cron.schedule(
    'cleanup-stale-virtual-runs',
    '0 * * * *',
    $$UPDATE virtual_runs
      SET status = 'cancelled', ended_at = NOW()
      WHERE status = 'active'
        AND started_at < NOW() - INTERVAL '6 hours'
        AND NOT EXISTS (
            SELECT 1 FROM virtual_run_snapshots
            WHERE virtual_run_id = virtual_runs.id
              AND client_recorded_at > NOW() - INTERVAL '1 hour'
        )$$
);
```

### Implementation Files

| # | File | Change |
|---|------|--------|
| 1 | `WRKT Watch Watch App/VirtualRunManager.swift` | Add `transferUserInfo` call in `requestEndRun()`, include `runId` in payload |
| 2 | `Core/Services/WatchConnectivityManager.swift` | Add `session(_:didReceiveUserInfo:)` delegate method |
| 3 | `Core/Services/WatchConnectivityManager.swift` | Add `lastProcessedVREndRunId` dedup in `handleVirtualRunEnded()` |
| 4 | `database_migrations/031_stale_run_cleanup.sql` | pg_cron job for 6-hour stale run auto-cancellation |

### Risk Assessment

- **Layer 1 (dual send):** Zero risk — additive, no existing behavior changes. `sendMessage` still fires for instant delivery.
- **Layer 2 (didReceiveUserInfo):** Low risk — the handler just routes to the existing `handleIncomingMessage()` which already handles `vrRunEnded`. Same pattern as the Watch side.
- **Layer 3 (dedup):** Low risk — prevents double-processing. Without it, `completeRun()` RPC would be called twice (server handles this idempotently, but it's wasteful).
- **Layer 4 (server cleanup):** Zero risk — only affects runs that are already broken (active for 6+ hours with no activity). Safety net only.

### Why Not Just `transferUserInfo` Alone?

`transferUserInfo` delivery is **not instant** — iOS batches and delivers when it decides (could be seconds to minutes). The summary overlay and partner notification should appear immediately when possible. Using both channels gives us: instant delivery when reachable + guaranteed delivery when not.

---

## Priority Fix Order (All Complete)

1. ~~**C1**~~ DONE — `is_paused` column added
2. ~~**C3**~~ DONE — `expires_at` column + client filtering + pg_cron registered
3. ~~**C2**~~ DONE — Dual delivery for `runEnded` + iOS `didReceiveUserInfo` + dedup + server cleanup
4. ~~**H3**~~ NO CHANGE NEEDED — `kCLLocationAccuracyBest` is correct per Apple's SpeedySloth sample
5. ~~**H2**~~ DONE — Lifecycle-aware polling wired to `scenePhase` in `AppShellView`
6. ~~**H1**~~ DONE — Dual delivery for partner-finished (sendMessage + transferUserInfo) + dedup
7. ~~**M3**~~ DONE — Priority message queuing protects critical messages from eviction
8. ~~**M2**~~ DONE — `persistState()` uses `runStartTime ?? Date()` instead of `Date()`
9. ~~**M1**~~ DONE — Kalman filter output used for snapshot coordinates
10. ~~**H5**~~ DONE — Migration 032 drops orphaned `enforce_snapshot_rate_limit` trigger
11. ~~**GPS**~~ DONE — `gpsMinAccuracyMeters` relaxed from 20m to 50m
12. ~~**Server cleanup**~~ CREATED — Migration 031: pg_cron job for stale active runs (must be run in SQL editor)
13. ~~**H4**~~ DONE — HealthKit data staleness detection: if distance freezes and HR is nil for 30s+, `showHealthDataWarning` flag is set. Resets automatically when data resumes.
14. ~~**M4**~~ DONE — Telemetry logged after RPC attempt instead of before. Captures `partnerDistance` before async Task to avoid stale reference.
15. ~~**M6**~~ DONE — `endRun()` wrapped in `#if DEBUG`. Only `VirtualRunDebugView` calls it; production uses `completeRun()` RPC.
16. ~~**M7**~~ DONE — Renamed `pausedElapsedBeforePause` to `totalPausedDuration` across all usage sites.
17. ~~**M8**~~ DONE — Audio session configured with `.playback` category, `.voicePrompt` mode, `.duckOthers` option. Music volume ducks during speech and restores after via `AVSpeechSynthesizerDelegate.didFinish`.
18. ~~**Gap 1**~~ NO CHANGE — Connection indicator already exists in `VirtualRunView.connectionStatus()` (Live/Stale/Lost/Paused).
19. ~~**Gap 2**~~ DONE — `activeVirtualRunId`, `activeVirtualRunUserId`, `activeVirtualRunPartnerName` persisted to UserDefaults via `didSet`. Restored in `setupSession()` on app launch. Incoming `vrRunEnded` messages now work after iOS app crash.
20. ~~**Gap 5**~~ DONE — `fetchLatestSnapshot()` called on reconnect in `sessionReachabilityDidChange`. Catches up partner position after disconnect. `activeVirtualRunPartnerId` added for reconnect lookup.

### Remaining (future features, not reliability issues)

- **Gap 3** — Indoor/treadmill mode (skip GPS, use accelerometer distance)
- **Gap 4** — Synchronized countdown (current ~200-500ms offset is acceptable)
- **Gap 6** — Virtual run history UI (repository method exists, needs view)
- **Gap 7** — Re-invite / rematch button on summary screen
- **Gap 8** — ✅ Already implemented (`VirtualRunMapComparisonView` + `VirtualRunSummaryPager`)
