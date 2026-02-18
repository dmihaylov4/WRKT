# Virtual Run — Technical Implementation Specification

## Overview

Virtual Run allows two users to run together remotely in real-time, seeing each other's distance, pace, heart rate, and connection status on their Apple Watches. Stats sync through Supabase Realtime (Postgres CDC) and are relayed between iPhone and Watch via WatchConnectivity.

---

## Architecture Diagram

```
┌─────────────┐          WatchConnectivity          ┌──────────────┐
│  Watch App  │ ◄──── sendMessage / transferUserInfo ────► │  iPhone App  │
│ (VirtualRun │                                      │  (Coordinator │
│  Manager)   │                                      │   + Repo)     │
└──────┬──────┘                                      └──────┬───────┘
       │                                                     │
       │  HKWorkoutSession                                   │  Supabase Client
       │  CLLocationManager                                  │
       │  WKInterfaceDevice (haptics)                        ▼
       │                                              ┌──────────────┐
       │                                              │   Supabase   │
       │                                              │  - Postgres  │
       │                                              │  - Realtime  │
       │                                              │  - Edge Fn   │
       │                                              └──────────────┘
       ▼
  HealthKit (HR, Distance, Calories, Route)
```

---

## File Inventory

| File | Target | Purpose |
|------|--------|---------|
| `Shared/VirtualRunSharedModels.swift` | iOS + Watch | Constants, `VirtualRunSnapshot`, `PartnerStats`, `ConnectionHealth`, `VirtualRunState`, `VirtualRunMessageType` |
| `Core/Models/VirtualRunModels.swift` | iOS | `VirtualRun` (Supabase row), `VirtualRunStatus`, `RunSummary`, `VirtualRunCompletionData`, `VirtualRunEvent` |
| `Features/Social/Services/VirtualRunRepository.swift` | iOS | Supabase CRUD + Realtime subscription + push notifications |
| `Features/Social/Services/VirtualRunInviteCoordinator.swift` | iOS | Singleton. Polls for pending invites, tracks sent invites, orchestrates accept/decline flow |
| `Features/Social/Services/VirtualRunSummaryCoordinator.swift` | iOS | Singleton. Holds `VirtualRunCompletionData` for the summary overlay |
| `Core/Services/WatchConnectivityManager.swift` | iOS | WCSession delegate on iPhone side. Forwards snapshots to Supabase, sends VR start/end/partner to Watch |
| `WRKT Watch Watch App/VirtualRunManager.swift` | Watch | Singleton. Run state machine, timers, GPS Kalman filter, haptics, battery optimization, crash recovery |
| `WRKT Watch Watch App/WatchConnectivityManager.swift` | Watch | WCSession delegate on Watch side. Handles VR messages, schedules local notifications |
| `WRKT Watch Watch App/WatchHealthKitManager.swift` | Watch | `HKWorkoutSession` + `HKLiveWorkoutBuilder` + `CLLocationManager` + `HKWorkoutRouteBuilder` |
| `WRKT Watch Watch App/Utilities/VirtualRunFileLogger.swift` | Watch | JSON Lines logger for debugging. Writes to Documents/VRLogs, transfers via `WCSession.transferFile` |
| `WRKT Watch Watch App/Utilities/HRZoneHelper.swift` | Watch | Maps HR to 5-zone model (50/60/70/80/90% of maxHR) |
| `WRKT Watch Watch App/Views/VirtualRunView.swift` | Watch | SwiftUI view: confirmation, countdown, split-screen active run, always-on display |
| `Features/Social/Views/VirtualRunInviteView.swift` | iOS | Friend list picker to send invite |
| `Features/Social/Views/Components/VirtualRunInviteBanner.swift` | iOS | Banner UI shown when receiving an invite |
| `Features/Social/Views/VirtualRunSummaryView.swift` | iOS | Head-to-head summary with staggered slam animation |
| `Features/Social/Views/VirtualRunSummaryOverlay.swift` | iOS | Thin wrapper in `AppShellView` showing summary as full-screen overlay |
| `Features/Social/Views/VirtualRunDebugView.swift` | iOS (DEBUG) | Debug panel for single-device testing with simulated partner snapshots |
| `database_migrations/021_virtual_runs.sql` | Supabase | Schema, RLS policies, rate-limit trigger, Realtime publication |

---

## Database Schema

### `virtual_runs` table

```sql
id                          UUID PRIMARY KEY (auto-generated)
inviter_id                  UUID REFERENCES profiles(id)
invitee_id                  UUID REFERENCES profiles(id)
status                      TEXT  -- 'pending' | 'active' | 'completed' | 'cancelled'
started_at                  TIMESTAMPTZ  -- set when invitee accepts
ended_at                    TIMESTAMPTZ  -- set on completion
created_at                  TIMESTAMPTZ DEFAULT NOW()
-- Summary (populated on completion):
inviter_distance_m          DOUBLE PRECISION
inviter_duration_s          INTEGER
inviter_avg_pace_sec_per_km INTEGER
inviter_avg_heart_rate      INTEGER
invitee_distance_m          DOUBLE PRECISION
invitee_duration_s          INTEGER
invitee_avg_pace_sec_per_km INTEGER
invitee_avg_heart_rate      INTEGER
winner_id                   UUID REFERENCES profiles(id)
```

Indexes:
- `idx_virtual_runs_status` — partial index on `status = 'active'`
- `idx_virtual_runs_users` — composite on `(inviter_id, invitee_id)`

RLS:
- SELECT: `auth.uid() = inviter_id OR auth.uid() = invitee_id`
- INSERT: `auth.uid() = inviter_id`
- UPDATE: `auth.uid() = inviter_id OR auth.uid() = invitee_id`

### `virtual_run_snapshots` table

```sql
id                      UUID PRIMARY KEY (auto-generated)
virtual_run_id          UUID REFERENCES virtual_runs(id) ON DELETE CASCADE
user_id                 UUID REFERENCES profiles(id)
distance_m              DOUBLE PRECISION DEFAULT 0
duration_s              INTEGER DEFAULT 0
current_pace_sec_per_km INTEGER
heart_rate              INTEGER
calories                INTEGER
latitude                DOUBLE PRECISION
longitude               DOUBLE PRECISION
seq                     INTEGER DEFAULT 0
client_recorded_at      TIMESTAMPTZ
server_received_at      TIMESTAMPTZ DEFAULT NOW()
UNIQUE (virtual_run_id, user_id)  -- only latest snapshot kept per user per run
```

Key constraints:
- **UPSERT on `(virtual_run_id, user_id)`** — each user only has one row per run, continuously overwritten with latest stats
- **Rate limit trigger** (`enforce_snapshot_rate_limit`): Prevents more than 1 snapshot/second by comparing `NEW.server_received_at - OLD.server_received_at`. Important: client must explicitly set `server_received_at` on every upsert, otherwise PostgREST omits it from the UPDATE SET clause and the diff = 0, triggering the rate limit.
- **Realtime enabled**: `ALTER PUBLICATION supabase_realtime ADD TABLE virtual_run_snapshots` + `REPLICA IDENTITY FULL`

RLS:
- SELECT: User must be participant of the referenced `virtual_run`
- INSERT: `user_id = auth.uid()` (can only write own snapshots)
- UPDATE: `user_id = auth.uid()`

---

## Run Lifecycle — Step by Step

### Phase 1: Invite

1. **Inviter** opens `VirtualRunInviteView` → selects a friend → calls `VirtualRunRepository.sendInvite(to:from:)`
2. Repository inserts a row in `virtual_runs` with `status = 'pending'`
3. Fire-and-forget: calls `sendInvitePush(to:from:runId:)` which invokes the **Supabase Edge Function** `send-push` with:
   ```swift
   PushPayload(
       user_id: inviteeId.uuidString,
       title: "Virtual Run Invite",
       body: "\(name) wants to run with you!",
       data: ["type": "virtual_run_invite", "run_id": ..., "actor_id": ...],
       sound: "default"
   )
   // Invoked via: client.functions.invoke("send-push", options: .init(body: payload))
   ```
4. `VirtualRunInviteCoordinator.shared.trackSentInvite(runId:partnerId:partnerName:)` stores the invite ID and sets `isWaitingForAcceptance = true`

### Phase 2: Invite Polling & Detection

`VirtualRunInviteCoordinator` is a `@MainActor @Observable` singleton that:

- **Starts polling** on app launch (`startPolling()`) with a `Timer` firing every **5 seconds** (added to `.common` RunLoop mode)
- Each poll calls:
  1. `fetchPendingInvites(for: userId)` — queries `virtual_runs WHERE invitee_id = me AND status = 'pending'`
  2. If a pending invite is found → sets `pendingInvite` + fetches inviter's `UserProfile` → plays `Haptics.success()`
  3. If `isWaitingForAcceptance` (inviter side) → calls `fetchRun(byId: sentInviteId)` to check if status changed to `.active` (accepted), `.cancelled` (declined), or still `.pending`

### Phase 3: Accept (Invitee)

1. Invitee taps accept on `VirtualRunInviteBanner` → `VirtualRunInviteCoordinator.acceptInvite()`
2. Calls `VirtualRunRepository.acceptInvite(runId)` which UPDATEs:
   - `status` → `"active"`
   - `started_at` → current ISO8601 timestamp
3. Sets `isInActiveRun = true`
4. **Subscribes to Supabase Realtime** via `repo.subscribeToSnapshots(runId:)`:
   - Creates channel `"virtual_run_\(runId)"`
   - Listens for Postgres INSERT/UPDATE on `virtual_run_snapshots` WHERE `virtual_run_id = runId`
   - Callback filters out own snapshots (`snapshot.userId != myId`) and forwards partner snapshots to Watch via `WatchConnectivityManager.shared.sendVirtualRunPartnerUpdate(snapshot)`
5. Fetches partner's `maxHR` from their profile
6. Calls `WatchConnectivityManager.shared.sendVirtualRunStarted(...)` → sends to Watch

### Phase 4: Inviter Detects Acceptance

1. Inviter's poll detects `run.status == .active` → calls `startRunAsInviter(run:userId:)`
2. Same flow: subscribe to Realtime snapshots, fetch partner maxHR, notify Watch

### Phase 5: iPhone → Watch Run Start

`WatchConnectivityManager.sendVirtualRunStarted()` (iOS side):

```swift
func sendVirtualRunStarted(runId:, partnerId:, partnerName:, myUserId:, myMaxHR:, partnerMaxHR:)
```

**Delivery strategy (triple redundancy):**
1. `session.transferUserInfo(message)` — **guaranteed delivery**, survives app not running
2. If `session.isReachable`: `session.sendMessage(message, ...)` — immediate delivery
3. If not reachable: `session.updateApplicationContext(message)` — queues for next wake + stores in `pendingVirtualRunStart` for retry when reachable

Watch side handles in `handleVirtualRunStarted()`:
- **Deduplication**: Tracks `lastProcessedVRRunId` to skip duplicate deliveries from sendMessage + transferUserInfo
- Creates `PartnerStats` and calls `VirtualRunManager.shared.setPendingRun(...)`

### Phase 6: Watch Confirmation & Countdown

**`VirtualRunManager.setPendingRun()`:**
- Sets `phase = .pendingConfirmation`
- Plays `WKInterfaceDevice.current().play(.notification)` haptic
- Starts **60-second auto-decline timeout** (`startConfirmationTimeout()`)

**Watch local notification** (scheduled from `WatchConnectivityManager`):
```swift
let content = UNMutableNotificationContent()
content.title = "Virtual Run"
content.body = "\(partnerName) wants to run with you!"
content.categoryIdentifier = "VIRTUAL_RUN_INVITE"
content.interruptionLevel = .timeSensitive  // breaks through DND
// Actionable: "Start Run" button (foreground action)
// Trigger: 0.5s delay
```

If user taps "Start Run" action → `VirtualRunManager.shared.confirmRun()` is auto-called.

**`confirmRun()`:**
1. Cancels timeout, cancels notification
2. Sets `phase = .countdown(3)` — starts 3-second countdown timer
3. Plays `.click` haptic each second
4. Sends `watchConfirmed` message to iPhone with coordinated start time (`Date() + 3.0`)

**`finishCountdownAndStart()`:**
1. Calls `WatchHealthKitManager.shared.startRunningWorkout()` → starts HealthKit session
2. Calls `startVirtualRun(...)` → enters `.active` phase

### Phase 7: Active Run — Data Collection & Sync

#### HealthKit Workout Session (Watch)

```swift
func startRunningWorkout() async throws {
    // HKWorkoutConfiguration:
    //   activityType: .running
    //   locationType: .outdoor

    // Creates HKWorkoutSession + HKLiveWorkoutBuilder
    // Data source: HKLiveWorkoutDataSource (automatic HR, distance, calories)
    // Route builder: HKWorkoutRouteBuilder (for GPS track)
    // Starts CLLocationManager for GPS
}
```

**Data sources collected by HKLiveWorkoutBuilder:**
- `heartRate` — via `statistics.mostRecentQuantity()`, converted to bpm
- `activeEnergyBurned` — via `statistics.sumQuantity()`, in kcal
- `distanceWalkingRunning` — via `statistics.sumQuantity()`, in meters

Updates arrive via `HKLiveWorkoutBuilderDelegate.workoutBuilder(_:didCollectDataOf:)`.

#### GPS Tracking (Watch)

```swift
// CLLocationManager setup:
manager.desiredAccuracy = kCLLocationAccuracyBest
manager.activityType = .fitness

// Location filtering (didUpdateLocations):
let filtered = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy < 50 }

// Route recording:
try await routeBuilder.insertRouteData(filtered)

// Last location stored as `lastLocation` for snapshot lat/lon
```

Authorization flow: checks `authorizedWhenInUse/authorizedAlways`, otherwise calls `requestWhenInUseAuthorization()`.

#### GPS Kalman Filter (Watch — `VirtualRunManager`)

Smooths GPS coordinates to reduce noise:

```swift
class KalmanFilter {
    // processNoise = VirtualRunConstants.gpsKalmanProcessNoise (0.008)
    // minAccuracy = 1m

    func process(lat:, lon:, accuracy:) -> (lat, lon) {
        // First reading: initialize directly
        // Subsequent: predict (variance += processNoise) then update (Kalman gain)
        let k = variance / (variance + accuracy * accuracy)
        self.lat += k * (lat - self.lat)
        self.lon += k * (lon - self.lon)
        variance = (1 - k) * variance
    }
}
```

#### Timers Started in Active Phase

| Timer | Interval | Purpose |
|-------|----------|---------|
| **Heartbeat** | 3.0s (`heartbeatInterval`) | Sends `.heartbeat` message via WC to iPhone |
| **Interpolation** | 0.1s (10Hz, `uiInterpolationInterval`) | Calls `partnerStats.interpolate()` for smooth display |
| **Stats Publish** | 2.0s normal / 5.0s low battery | Reads HK data, builds snapshot, sends to iPhone |
| **Battery Check** | 60.0s | Checks `WKInterfaceDevice.current().batteryLevel`, toggles `isLowBatteryMode` at 20% |

All timers use `Timer(timeInterval:repeats:block:)` + `RunLoop.main.add(timer, forMode: .common)` for background reliability.

#### Stats Publishing Flow (every 2s)

```
Watch (publishCurrentStats)
  ├── Read WatchHealthKitManager: .heartRate, .distance, .lastLocation
  ├── Calculate pace: (durationS / distanceM) * 1000  (min 50m distance, max 1800 sec/km)
  ├── Apply Kalman filter to GPS
  ├── Build VirtualRunSnapshot (increment localSeq)
  ├── Convert to compact dict (single-letter keys for small payload)
  │   { "r": runId, "u": userId, "d": distance, "t": duration, "s": seq, "c": timestamp,
  │     "p": pace, "h": hr, "la": lat, "lo": lon }
  ├── Send via WatchConnectivityManager.sendMessage(type: .snapshot, payload: compactDict)
  ├── Check km milestones → play .success haptic
  └── Persist state to UserDefaults (crash recovery)

iPhone (handleVirtualRunSnapshot)
  ├── Deserialize compact dict → VirtualRunSnapshot
  └── Publish to Supabase: UPSERT into virtual_run_snapshots (conflict on virtual_run_id, user_id)
      └── Sets server_received_at = Date() explicitly (required for rate-limit trigger)

Supabase Realtime (CDC on virtual_run_snapshots)
  └── Broadcasts INSERT/UPDATE to partner's subscribed channel

Partner's iPhone (Realtime callback)
  ├── Decode VirtualRunSnapshot
  ├── Filter: skip own snapshots (snapshot.userId != myId)
  └── Forward to partner's Watch: sendVirtualRunPartnerUpdate(snapshot)
      └── Serializes to compact dict, sends via WCSession.sendMessage

Partner's Watch (handleVirtualRunPartnerUpdate)
  ├── Decode compact dict → VirtualRunSnapshot
  └── VirtualRunManager.receivePartnerUpdate(snapshot)
      ├── PartnerStats.update(from: snapshot) — only accepts higher seq numbers
      ├── Updates connectionHealth.lastHeartbeatReceived
      └── checkLeadChange() → haptic feedback
```

#### Partner Stats Interpolation (10Hz)

```swift
func interpolate() {
    guard !isDisconnected else { return }

    // Estimate forward movement based on current pace
    if let pace = currentPaceSecPerKm, pace > 0 {
        let metersPerSecond = 1000.0 / Double(pace)
        let estimatedProgress = metersPerSecond * dataAge
        displayDistanceM = rawDistanceM + min(estimatedProgress, 50)  // cap at 50m extrapolation
    }

    displayDurationS = rawDurationS + Int(dataAge)
}
```

#### Connection Health Monitoring

```swift
struct ConnectionHealth {
    var lastHeartbeatSent: Date
    var lastHeartbeatReceived: Date
    var consecutiveFailures: Int

    var isHealthy: Bool {
        Date().timeIntervalSince(lastHeartbeatReceived) < 6.0  // heartbeatTimeout
    }
}

// PartnerStats connection status thresholds:
// - connected: dataAge < 8.0s (staleDataThreshold)
// - stale:     dataAge < 15.0s (disconnectThreshold)  → shows "Xs" in orange
// - disconnected: dataAge >= 15.0s                     → shows "Lost" in red
```

#### Lead Change Haptics

```swift
func checkLeadChange() {
    let difference = abs(myDistance - partnerDistance)
    guard difference > 10.0 (leadChangeThreshold) else { return }
    guard timeSinceLastHaptic > 5.0 (leadChangeDebounce) else { return }

    if currentLeader != lastLeader {
        if I'm leading   → WKInterfaceDevice.play(.success)
        if partner leads  → WKInterfaceDevice.play(.failure)
    }
}
```

#### Km Milestone Haptics

```swift
let currentKm = Int(currentDistance / 1000)
if currentKm > lastKmMilestone {
    lastKmMilestone = currentKm
    WKInterfaceDevice.current().play(.success)
}
```

### Phase 8: End Run

**From Watch (`requestEndRun()`):**
1. Builds final stats payload: `{ distance, duration, pace, heartRate }`
2. Sends `.runEnded` message to iPhone
3. Calls `endVirtualRun()` locally (stops timers, resets state, clears persisted state)
4. Ends HealthKit workout: `WatchHealthKitManager.shared.endWorkout(discard: false)`
   - `builder.endCollection(at: Date())`
   - `builder.finishWorkout()`
   - `routeBuilder.finishRoute(with: workout, metadata: nil)` — attaches GPS route
5. Auto-transfers log file to iPhone via `WCSession.transferFile`
6. Plays `.stop` haptic

**iPhone handles `vrRunEnded`:**
1. Parses final stats from Watch payload
2. Builds `VirtualRunCompletionData` with my stats + last known partner snapshot
3. Shows summary: `VirtualRunSummaryCoordinator.shared.show(completionData)`
4. Unsubscribes from Realtime: `virtualRunRepository.unsubscribeFromSnapshots()`
5. Updates Supabase: `virtualRunRepository.endRun(runId, summary:)` → sets status to `"completed"`, records all stats + winner
6. Resets state, posts `VirtualRunEndedFromWatch` notification
7. Calls `VirtualRunInviteCoordinator.shared.runEnded()`

**From iPhone (sending end to Watch):**
- `WatchConnectivityManager.sendVirtualRunEnded()` sends `{ type: "vr_ended" }`
- Watch handles: ends virtual run + ends HealthKit workout

### Phase 9: Summary Screen

`VirtualRunSummaryView` displays head-to-head comparison with staggered animation:

- **T+0.0s**: Icon (`.spring` with bounce)
- **T+0.3s**: "Virtual Run Complete" title
- **T+0.6s onwards**: Stat rows appear 150ms apart, each with `Haptics.medium()`
  - DISTANCE: higher distance wins (green highlight)
  - DURATION: longer duration highlighted
  - PACE: **lower pace wins** (faster = better)
  - AVG HR: higher HR = "worked harder"
- **T+1.3s**: "Continue" button

Overlay is placed in `AppShellView` via `VirtualRunSummaryOverlay` at `zIndex(999)`.

---

## Notifications

### Push Notification (Invite — iOS → iOS)

- **When**: After `sendInvite()` creates the row
- **How**: Supabase Edge Function `send-push`
- **Payload**: `{ user_id, title: "Virtual Run Invite", body: "\(name) wants to run with you!", data: { type, run_id, actor_id }, sound: "default" }`

### Local Notification (Watch)

- **When**: Watch receives `vrRunStarted` message
- **How**: `UNUserNotificationCenter.current().add(request)`
- **Content**: Title "Virtual Run", body "\(partnerName) wants to run with you!"
- **Category**: `VIRTUAL_RUN_INVITE` with action "Start Run" (foreground)
- **Interruption level**: `.timeSensitive` (breaks through DND/Focus)
- **Trigger**: `UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)`
- **Cancellation**: `cancelVirtualRunNotification()` on confirm/decline/end

---

## WatchConnectivity Message Types

```swift
enum WatchMessage: String {
    // Virtual Run messages:
    case vrSnapshot       = "vr_snapshot"        // Watch → iPhone: my stats
    case vrHeartbeat      = "vr_heartbeat"       // Bidirectional: keep-alive
    case vrPartnerUpdate  = "vr_partner"         // iPhone → Watch: partner's stats
    case vrRunStarted     = "vr_started"         // iPhone → Watch: run accepted
    case vrRunEnded       = "vr_ended"           // Bidirectional: run completed
    case vrPartnerFinished = "vr_partner_finished" // iPhone → Watch: partner ended
    case vrWatchConfirmed = "vr_watch_confirmed" // Watch → iPhone: user confirmed countdown
}
```

Message format: `[String: Any]` dictionary with `"messageType"` or `"type"` key.

Payloads are serialized as `Data` (JSON) under `"payload"` or `"data"` key.

### Delivery Guarantees

| Method | Reliability | Used For |
|--------|-------------|----------|
| `sendMessage` | Only when reachable, fast | Snapshots, heartbeats, partner updates |
| `transferUserInfo` | Guaranteed (queued), survives app termination | VR run start |
| `updateApplicationContext` | Latest-value-wins, persists | VR run start (fallback) |
| `transferFile` | Guaranteed, large data | Debug log files |

---

## Battery Optimization

- **Low battery mode**: Activates at **20%** battery (`lowBatteryThreshold`)
- **Effect**: Publish interval increases from **2.0s** → **5.0s** (`lowBatteryPublishInterval`)
- **Battery monitoring**: `WKInterfaceDevice.current().isBatteryMonitoringEnabled = true`
- **Check frequency**: Every 60 seconds
- **Navigation debouncing**: WC messages debounced at 300ms to reduce radio usage
- **Snapshot compact encoding**: Single-letter keys (`d`, `t`, `s`, `p`, `h`, `la`, `lo`) to minimize payload size

---

## Crash Recovery

State is persisted to `UserDefaults` on every stats update:

```swift
struct VirtualRunState: Codable {
    let runId: UUID
    let partnerId: UUID
    let partnerName: String
    let myLastDistance: Double
    let myLastDuration: Int
    let startedAt: Date
    let lastSeq: Int
}
```

Key: `"virtual_run_state"`. Cleared on run end. Restored via `restoreStateIfNeeded()`.

---

## Reconnection

`ReconnectionManager` uses **exponential backoff**:

```swift
// Base delay: 1.0s, doubles each retry, max 30.0s
// Max attempts: 10
let delay = min(pow(2.0, retryCount) * 1.0, 30.0)
```

iPhone-side also queues messages when Watch is unreachable:
- Message queue: max 10 items, FIFO with drop-oldest
- Processed when reachability changes to `true`
- Retry on send failure: up to 3 retries with 0.5s incremental backoff

---

## Debug Logging (Watch)

`VirtualRunFileLogger` writes structured JSON Lines files:

```json
{"ts":"2025-01-01T12:00:00.000Z","cat":"snapshot_out","msg":"Publishing stats","data":{"distance":1234,"duration":600}}
```

Categories: `connectivity`, `healthkit`, `snapshot_out`, `snapshot_in`, `partner`, `phase`, `error`

- Writes to `Documents/VRLogs/vr_log_<timestamp>.jsonl`
- Buffered (flushed every 2.0s)
- Pruned to max 5 log files
- Transferred to iPhone via `WCSession.transferFile(logURL, metadata: ["type": "vrLog"])`
- iPhone receives in `session(_:didReceive file:)`, copies to `tmp/WatchVRLogs/`
- Viewable in `VirtualRunDebugView`

---

## HR Zone Visualization (Watch)

The active run view is split vertically: top half = my stats, bottom half = partner stats. Background color changes based on HR zone:

```swift
enum HRZoneHelper {
    // Zone boundaries as fraction of maxHR:
    // Zone 1 (Light):     50-59%  → blue
    // Zone 2 (Moderate):  60-69%  → green
    // Zone 3 (Aerobic):   70-79%  → yellow
    // Zone 4 (Threshold): 80-89%  → orange
    // Zone 5 (Max):       90%+    → red
    // Below 50%: no color (clear)
}
```

A 5-color **Zone Bar** (blue|green|yellow|orange|red) separates the two halves.

The `maxHR` value is fetched from the user's profile (derived from birth year) and sent in the run start message. Defaults to 190 if unavailable.

---

## Always-On Display (Watch)

When `isLuminanceReduced == true`:
- Reduced opacity (30-50%)
- Minimal layout: distance, duration, HR, partner distance
- No interactive controls
- Zone colors at 50% opacity
- Content scales: my distance at 38pt, partner distance at 20pt

---

## Constants Reference

```swift
enum VirtualRunConstants {
    // Sync intervals
    static let snapshotPublishInterval: TimeInterval = 2.0
    static let uiInterpolationInterval: TimeInterval = 0.1  // 10Hz
    static let watchForwardInterval: TimeInterval = 0.5

    // Connection health
    static let heartbeatInterval: TimeInterval = 3.0
    static let heartbeatTimeout: TimeInterval = 6.0
    static let staleDataThreshold: TimeInterval = 8.0
    static let disconnectThreshold: TimeInterval = 15.0

    // Reconnection
    static let reconnectBaseDelay: TimeInterval = 1.0
    static let reconnectMaxDelay: TimeInterval = 30.0
    static let reconnectMaxAttempts: Int = 10

    // Haptics
    static let leadChangeThreshold: Double = 10.0  // meters
    static let leadChangeDebounce: TimeInterval = 5.0

    // GPS
    static let gpsKalmanProcessNoise: Double = 0.008
    static let gpsMinAccuracyMeters: Double = 20.0

    // Battery
    static let lowBatteryThreshold: Float = 0.20
    static let lowBatteryPublishInterval: TimeInterval = 5.0
}
```
