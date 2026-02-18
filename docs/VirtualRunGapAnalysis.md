# GAP Analysis: Virtual Run vs. Industry Standards

Compared against: Strava Beacon, Nike Run Club, Peloton, Zwift

---

## 1. Security & Privacy — CRITICAL GAPS

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **Location privacy** | Raw lat/lon stored in `virtual_run_snapshots` | Strava/Nike: location data is ephemeral or end-to-end encrypted; never persisted in plaintext on shared tables | **HIGH** — A compromised Supabase or RLS bug leaks real-time GPS of users. Snapshots should omit lat/lon or encrypt them client-side. | **FIXED** — lat/lon columns dropped from `virtual_run_snapshots` (migration `023`). `publishSnapshot()` also nils out lat/lon client-side before upload. |
| **Rate-limit bypass** | Trigger-based, 1 snapshot/sec | Server-side rate limiting per API key + IP + user token | **MEDIUM** — Postgres triggers can be bypassed via direct SQL if RLS is misconfigured. Add API-layer rate limiting (e.g., Supabase Edge Function as a proxy). | Open |
| **No DELETE RLS policy** | Not mentioned | Explicit deny on DELETE for snapshots | **MEDIUM** — Without it, Supabase default may allow deletes. | **FIXED** — DELETE deny policy added on `virtual_run_snapshots` (migration `023`). |
| **Invite spam** | No rate limit on `sendInvite()` | Throttle invites per user (e.g., max 5 pending invites) | **LOW-MEDIUM** — A user could spam invites to harass others. | Open |
| **Winner spoofing** | `winner_id` set client-side | Winner determined server-side (Edge Function compares stats) | **MEDIUM** — A malicious client can claim victory by setting `winner_id` directly via UPDATE. Move winner calculation to an Edge Function or Postgres trigger. | **FIXED** — `complete_virtual_run()` RPC function calculates winner server-side with row-level locking. Client calls RPC instead of setting `winner_id` directly. |
| **Snapshot spoofing** | No server-side validation of distance/pace values | Zwift/Peloton: server-side plausibility checks (max speed, physiological HR limits) | **MEDIUM** — A user can report fake distance. Add basic sanity checks (e.g., pace < 2:00/km = reject, HR > 250 = reject). | Open |

---

## 2. Scalability & Real-time Architecture

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **Polling for invites** | 5-second Timer polling | WebSocket/Realtime subscription on `virtual_runs` table | **HIGH** — Polling every 5s is wasteful and adds 0-5s latency. You already use Supabase Realtime for snapshots — use it for invite detection too. This eliminates the polling timer entirely. | **FIXED** — `virtual_runs` added to Supabase Realtime publication (migration `023`). `VirtualRunInviteCoordinator` refactored from 5s polling to Realtime-first with 30s fallback poll as safety net. |
| **Realtime channel per run** | `"virtual_run_\(runId)"` — works for 2 users | Dedicated pub/sub channels with presence | **LOW** — Fine for 1:1. If you ever expand to group runs, you'll need a fan-out strategy. | Open |
| **Snapshot table as message bus** | UPSERT + CDC for real-time sync | Dedicated message broker or Supabase Broadcast (no persistence needed for live data) | **MEDIUM** — Using a DB table + CDC as a real-time bus adds ~200-500ms latency vs. Supabase Broadcast channels (~50ms). Snapshots are ephemeral — consider `channel.send(type: .broadcast, ...)` for live data, and only persist the final summary. | **FIXED** — Hybrid approach: Supabase Broadcast for low-latency live sync (primary, ~50ms), DB UPSERT every 30s for crash recovery (secondary). CDC channel kept as fallback for reconnection. Migration `024` relaxes rate-limit trigger accordingly. |
| **No concurrent run guard** | Not mentioned | Enforce single active run per user (DB constraint or check) | **MEDIUM** — A user could theoretically have multiple active runs. Add a partial unique index: `CREATE UNIQUE INDEX ON virtual_runs (inviter_id) WHERE status = 'active'` (and same for invitee). | **FIXED** — Partial unique indexes on `inviter_id` and `invitee_id` where `status = 'active'` (migration `023`). Client-side guards added to `sendInvite()` and `acceptInvite()`. |

---

## 3. Data Integrity & Consistency

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **Clock sync** | `client_recorded_at` from Watch, `server_received_at` from Postgres | NTP-relative timestamps or server-authoritative time with client offset | **MEDIUM** — Watch clock and iPhone clock can drift. Pace/duration comparisons between two users on different devices need a common time reference. Consider computing a `server_offset` on session start. | Open |
| **Final stats race condition** | Both users send `endRun` independently | One source of truth for completion (first-to-end triggers server-side finalization) | **MEDIUM** — If both users end simultaneously, two UPDATE calls race on the same row. The second UPDATE may overwrite the first user's stats. Use a Postgres function with `SELECT ... FOR UPDATE` or handle via Edge Function with conflict resolution. | **FIXED** — `complete_virtual_run()` RPC uses `SELECT ... FOR UPDATE` row-level locking. Each caller's stats are written independently; partner stats backfilled from snapshots with `COALESCE` (won't overwrite). |
| **Distance discrepancy** | Each user reports own distance | Zwift: server reconciles and shows authoritative distance | **LOW** — Acceptable for casual social runs. But the "winner" determination uses unvalidated self-reported data. | Open |
| **Seq number gaps** | Partner only accepts higher `seq` | Industry: detect gaps and request retransmission or interpolate | **LOW** — Acceptable given the UPSERT model (only latest matters). | Open |

---

## 4. Resilience & Error Handling

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **Crash recovery** | UserDefaults persistence, `restoreStateIfNeeded()` | Same + HealthKit workout session auto-recovery (`HKWorkoutSession` survives crashes natively) | **LOW** — Good. But the spec doesn't mention handling the case where the iPhone app is killed mid-run. If the iPhone dies, snapshots stop flowing to Supabase. The Watch should detect iPhone unreachable and queue snapshots locally for later upload. | Open |
| **Reconnection** | Exponential backoff, max 10 attempts, max 30s | Same + jitter (randomized delay to avoid thundering herd) | **LOW** — Add jitter: `delay * (0.5 + random(0.5))`. | Open |
| **Graceful degradation** | Connection states: connected/stale/disconnected | Industry also shows "solo mode" after extended disconnect — auto-finalize if partner gone >5 min | **MEDIUM** — No timeout for extended disconnection. If a partner's phone dies, the other user sees "Lost" forever. Add an auto-end or "continue solo" prompt after ~3-5 minutes of disconnection. | **FIXED** — `extendedDisconnectTimeout` (180s) added to `VirtualRunConstants`. `VirtualRunManager` monitors partner disconnect duration on each heartbeat tick. After 3 min, a "Partner Lost" overlay prompts "End Run" or "Keep Waiting". |
| **HealthKit auth failure** | Checks authorization, requests if needed | Industry: graceful fallback (manual entry, reduced functionality) | **LOW** — What happens if HK auth is denied mid-run? Spec doesn't address. | Open |
| **WatchConnectivity session not activated** | Not mentioned | Check `WCSession.isSupported` and `activationState` before all sends | **LOW** — Likely handled but not documented. | Open |

---

## 5. UX & Feature Parity

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **Audio cues** | Haptics only | Nike/Peloton: voice callouts for splits, lead changes, partner milestones | **MEDIUM** — Haptics alone may be missed during intense activity. Consider `AVSpeechSynthesizer` or audio clips for key events. | Open |
| **Pre-run ready check** | 60s auto-decline, then countdown | Zwift: both users must confirm "ready" before countdown begins | **LOW-MEDIUM** — The inviter never explicitly confirms readiness after the invitee accepts. They're auto-started. Consider a mutual ready-check. | Open |
| **Mid-run pause** | Not mentioned | Strava/Nike: pause support with auto-pause on stop detection | **MEDIUM** — No pause capability. If a user needs to stop at a traffic light, their time keeps running while their partner's may not. HKWorkoutSession supports pause/resume natively. | **FIXED** — `.paused` phase added to `VirtualRunPhase`. Watch UI has pause/resume button + full-screen "PAUSED" overlay. HK workout pauses/resumes natively. Elapsed time excludes paused duration. Partner sees "Paused" status instead of "Lost". `isPaused` flag added to snapshots and `PartnerStats`. |
| **In-run chat/reactions** | Not mentioned | Peloton/Zwift: emoji reactions, "high five", audio clips | **LOW** — Nice-to-have for social engagement. | Open |
| **Split times** | Km milestones with haptic | Industry: per-km split display with comparison to partner's same km | **LOW** — Splits are detected but not stored or compared. | Open |
| **Post-run sharing** | Summary overlay | Strava/Nike: shareable image card, social feed post | **LOW** — Beyond MVP scope, but a natural next step. | Open |

---

## 6. Battery & Performance

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **10Hz interpolation timer** | `Timer` at 0.1s for smooth display | SwiftUI `TimelineView` or `withAnimation` | **LOW-MEDIUM** — A 10Hz timer on Watch is aggressive for battery. Consider using `TimelineView(.periodic(every: 0.5))` in SwiftUI, which is system-optimized for always-on display and battery. | Open |
| **GPS accuracy filter** | `horizontalAccuracy < 50m` | Industry: < 20m, with speed-based adaptive filtering | **LOW** — Your `gpsMinAccuracyMeters` constant is 20m, but the filter in code uses 50m. Inconsistency — tighten to 20m. | Open |
| **Background execution** | RunLoop `.common` mode timers | `HKWorkoutSession` extended runtime + `ProcessInfo.performExpiringActivity` | **LOW** — HKWorkoutSession gives you background runtime, but the spec doesn't mention handling `WKApplicationRefreshBackgroundTask` for cases where the app is suspended. | Open |

---

## 7. Observability & Monitoring

| Area | Your Spec | Industry Standard | Gap | Status |
|------|-----------|-------------------|-----|--------|
| **Metrics/telemetry** | Debug JSON logger (Watch only) | Server-side metrics: latency p50/p95, snapshot delivery rate, error rate, run completion rate | **HIGH** — No production observability. You won't know if runs are failing silently. Add lightweight telemetry: run start/end events, snapshot delivery latency, error counts. Even a simple `virtual_run_events` table would help. | **FIXED** — `virtual_run_events` table created (migration `025`) with RLS policies. `VirtualRunTelemetry` service logs all lifecycle events (`inviteSent`, `inviteAccepted`, `runStarted`, `runCompleted`, `runCancelled`, `disconnectOccurred`, `reconnectSucceeded`) and snapshot publish latency. `AppLogger.virtualRun` category added for unified console logging. |
| **Error reporting** | Log to file, transfer to iPhone | Sentry/Crashlytics with breadcrumbs | **MEDIUM** — File-based logging is great for debugging but won't surface issues in production. | Open |

---

## Summary — Priority Matrix

| Priority | Gap | Effort | Status |
|----------|-----|--------|--------|
| **P0** | Replace invite polling with Realtime subscription | Low | **DONE** |
| **P0** | Add server-side winner calculation (Edge Function) | Low | **DONE** (Postgres RPC) |
| **P0** | Add concurrent active run guard (unique index) | Low | **DONE** |
| **P0** | Strip or encrypt lat/lon from snapshots table | Medium | **DONE** |
| **P1** | Use Supabase Broadcast instead of table CDC for live sync | Medium | **DONE** (Hybrid: Broadcast primary + DB persist every 30s) |
| **P1** | Add extended-disconnect auto-end (3-5 min timeout) | Low | **DONE** (3-min timeout with "End Run" / "Keep Waiting" prompt) |
| **P1** | Add production telemetry/observability | Medium | **DONE** (`virtual_run_events` table + `VirtualRunTelemetry` service) |
| **P1** | Add pause/resume support | Medium | **DONE** (`.paused` phase, HK pause/resume, partner "Paused" indicator) |
| **P1** | Add end-run race condition protection | Low | **DONE** (via `complete_virtual_run` RPC with `FOR UPDATE`) |
| **P2** | Add snapshot plausibility checks | Low | Open |
| **P2** | Add invite rate limiting | Low | Open |
| **P2** | Add jitter to reconnection backoff | Trivial | Open |
| **P2** | Replace 10Hz Timer with TimelineView | Low | Open |
| **P2** | Audio cues for key events | Medium | Open |
| **P2** | Fix GPS accuracy constant inconsistency (50m vs 20m) | Trivial | Open |

---

## Implementation Log

### P0 Fixes — Completed 2025-02-12

**Migration:** `database_migrations/023_virtual_runs_p0_fixes.sql`
- Enabled Realtime on `virtual_runs` table
- Added partial unique indexes for concurrent run guard
- Created `complete_virtual_run()` SECURITY DEFINER RPC with row locking and server-side winner calculation
- Dropped `latitude`/`longitude` columns from `virtual_run_snapshots`
- Added DELETE deny policy on snapshots

**Swift Changes:**
- `VirtualRunRepository.swift` — Added `completeRun()` RPC, `subscribeToVirtualRunChanges()`, location stripping in `publishSnapshot()`, active-run guards on `sendInvite()`/`acceptInvite()`
- `VirtualRunInviteCoordinator.swift` — Refactored from 5s polling to Realtime-first + 30s fallback poll (`startListening()`/`stopListening()`)
- `WatchConnectivityManager.swift` — Replaced broken `endRun()` call (hardcoded invitee stats to 0, winner always nil) with `completeRun()` RPC
- `VirtualRunModels.swift` — Added `VirtualRunError` enum
- `AppShellView.swift` — Changed `startPolling()` to `startListening()`

**Verified:**
- Concurrent guard rejects duplicate active runs (unique index violation)
- `complete_virtual_run()` RPC correctly determines winner by distance
- Realtime invite banner appears in ~1s
- `latitude`/`longitude` columns removed from snapshots table

---

### P1 Fixes — Completed 2025-02-13

#### P1-D: Pause/Resume Support

**Swift Changes:**
- `VirtualRunSharedModels.swift` — Added `isPaused` to `VirtualRunSnapshot` (compact key `"pa"`) and `PartnerStats`. Added `.paused` case to `PartnerStats.ConnectionStatus`. Added `.pause`/`.resume` to `VirtualRunMessageType`.
- `WatchWorkoutModels.swift` — Added `.vrPause`/`.vrResume` to `WatchMessage` enum.
- `VirtualRunManager.swift` — Added `.paused` to `VirtualRunPhase`. Added `pauseRun()`/`resumeRun()` methods that stop/restart timers, pause/resume HK workout, and notify iPhone. Elapsed time excludes paused duration.
- `VirtualRunView.swift` — Added pause/resume button, full-screen "PAUSED" overlay, partner "Paused" status indicator.
- `WatchConnectivityManager.swift` (Watch) — Maps `.pause`/`.resume` to `.vrPause`/`.vrResume` message types.
- `WatchConnectivityManager.swift` (iPhone) — Handles `vrPause`/`vrResume` messages, posts notifications, relays pause state to partner via snapshot `isPaused` flag.

#### P1-B: Extended-Disconnect Auto-End

**Swift Changes:**
- `VirtualRunSharedModels.swift` — Added `extendedDisconnectTimeout = 180` to `VirtualRunConstants`.
- `VirtualRunManager.swift` — Added `disconnectStartTime`/`showDisconnectPrompt` state. `checkExtendedDisconnect()` runs on heartbeat tick; triggers prompt after 3 minutes of partner disconnect.
- `VirtualRunView.swift` — Added "Partner Lost" overlay with "End Run" and "Keep Waiting" options.

#### P1-A: Supabase Broadcast for Live Sync

**Migration:** `database_migrations/024_virtual_runs_p1_broadcast.sql`
- Replaced 1s rate-limit trigger with relaxed 10s trigger (DB writes now happen every ~30s).
- **Hotfix:** Trigger now stamps `NEW.server_received_at := NOW()` before the rate-limit comparison. The `DEFAULT NOW()` on the column only fires on INSERT, not on the UPDATE path of an UPSERT — without this fix every UPSERT compared identical timestamps and was always rejected.

**Swift Changes:**
- `VirtualRunRepository.swift` — Hybrid sync: Broadcast channel primary (~50ms latency) + DB UPSERT every 30s for crash recovery. Added `publishSnapshotViaBroadcast()`, `persistSnapshotToDB()`, `fetchLatestSnapshot()`, `toJSONObject()`/`fromJSONObject()` helpers. `subscribeToSnapshots()` creates both Broadcast + CDC channels; CDC serves as reconnection fallback.

#### P1-C: Production Telemetry

**Migration:** `database_migrations/025_virtual_run_telemetry.sql`
- Created `virtual_run_events` table with indexes on `run_id`, `event_type`, `created_at`.
- RLS: users can INSERT own events, SELECT events for runs they participate in.

**New File:** `Features/Social/Services/VirtualRunTelemetry.swift`
- Fire-and-forget event logger. Maps `VirtualRunEvent` cases to event_type strings + `AnyJSON` data. Silently catches all errors.

**Swift Changes:**
- `AppLogger.swift` — Added `virtualRun` logger category.
- `VirtualRunRepository.swift` — Instrumented `sendInvite()`, `acceptInvite()`, `declineInvite()` with telemetry.
- `WatchConnectivityManager.swift` (iPhone) — Instrumented `runStarted`, `runCompleted`, `runCancelled` events. Added snapshot latency tracking (logs when >500ms).

---

### P1 Backend Verification — 2025-02-13

Tested against live Supabase (`wjkokxhdpuoacazaohsa`) with two users.

**Test run:** `f37f3ddf-87c1-4547-bcd8-5ef229cafe8c`

| Test | Result |
|------|--------|
| `virtual_run_events` table — insert all event types | All 8 events inserted (HTTP 201). JSONB `data` column stores structured payloads correctly. |
| Full telemetry lifecycle trail | `invite_sent` → `invite_accepted` → `run_started` (×2) → `disconnect_occurred` → `reconnect_succeeded` → `snapshot_latency` → `run_completed` |
| Snapshot UPSERT (both users) | HTTP 201 on initial insert, HTTP 200 on subsequent UPSERTs with correct column mapping |
| Relaxed rate limit (10s) | Blocks rapid writes (<10s apart) with `P0001`; allows writes >10s apart |
| `complete_virtual_run()` RPC | User A wins (1200m vs 480m). Invitee stats backfilled from snapshot via `COALESCE`. Status set to `completed`, `winner_id` set correctly. |

**Bug found & fixed during testing:**
- `check_snapshot_rate_limit()` trigger compared `NEW.server_received_at - OLD.server_received_at`, but on the UPDATE path of an UPSERT the `DEFAULT NOW()` does not fire — `NEW.server_received_at` kept the old value, so the diff was always 0 and every UPSERT was rejected. Fixed by adding `NEW.server_received_at := NOW()` before the comparison. Migration file and live DB both updated.
