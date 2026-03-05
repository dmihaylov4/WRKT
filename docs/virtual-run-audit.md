# Virtual Run Implementation Audit

> Audited: 2026-03-02

## Summary

The architecture is solid — broadcast-primary/CDC-fallback for Supabase, dual-path guaranteed delivery for critical WC messages, idempotency guards throughout, and correct handling of the known invariants. But there are a few real bugs and several latent reliability gaps.

---

## 1. BUGS (Must Fix)

---

### BUG 1 — HIGH: `vrPartnerFinished` guaranteed delivery is silently broken

**File:** `Core/Services/WatchConnectivityManager.swift` ~line 1294

The iOS `sendVirtualRunPartnerFinished` sends two paths: an instant `sendMessage` (correct) and a `transferUserInfo` backup. The backup uses:

```swift
var userInfoMsg: [String: Any] = ["messageType": WatchMessage.vrPartnerFinished.rawValue]
```

The Watch `handleIncomingMessage` guards on:
```swift
guard let type = message["type"] as? String else { return }  // ← expects "type"
```

`"messageType"` is the Watch→iPhone convention. iPhone→Watch must use `"type"`. So the Watch will log `"Invalid message format received - no 'type' key"` and silently drop every `transferUserInfo` backup for partner finished. If the instant `sendMessage` fails (Watch screen off, wrist down), the partner never sees the partner-finished overlay.

**Fix:** Change the backup's top-level key from `"messageType"` to `"type"`:
```swift
var userInfoMsg: [String: Any] = ["type": WatchMessage.vrPartnerFinished.rawValue]
```

---

### BUG 2 — MEDIUM: `sendVirtualRunEnded` (iPhone-initiated) silently drops when Watch is unreachable

**File:** `Core/Services/WatchConnectivityManager.swift` ~line 1252

```swift
func sendVirtualRunEnded() {
    guard let session = session, session.isReachable else { return }  // ← drops silently
    ...
}
```

If called while the Watch screen is off, the Watch is left in `.active` phase indefinitely — active HK workout still running, timers firing, snapshot publishing — with no way to end unless the Watch user independently taps End Run.

The Watch-originated `requestEndRun` correctly sends both `sendMessage` AND `transferUserInfo`. The iPhone-originated end path needs the same treatment. At minimum, a `session.transferUserInfo(["type": WatchMessage.vrRunEnded.rawValue])` fallback is required here.

---

### BUG 3 — MEDIUM: Watch's `handleVirtualRunEnded` fires on duplicate delivery without dedup

**File:** `WRKT Watch Watch App/WatchConnectivityManager.swift` ~line 562

The Watch correctly deduplicates `vrRunStarted` via `lastProcessedVRRunId`. But `handleVirtualRunEnded` has no equivalent guard — it calls `endVirtualRun()` and `endWorkout(discard: false)` unconditionally. If both the instant `sendMessage` and the Watch's own `transferUserInfo` (from `sendRunEndedGuaranteed`) both arrive, `endVirtualRun()` fires twice.

In practice mostly harmless (state already idle, second HK end fails gracefully) but the pattern is fragile.

**Fix:** Add at the top of `handleVirtualRunEnded`:
```swift
guard VirtualRunManager.shared.isInVirtualRun else { return }
```

---

## 2. RELIABILITY GAPS (Should Fix)

---

### GAP 1 — `uiInterpolationInterval = 0.1` is dead code

**File:** `Shared/VirtualRunSharedModels.swift:17`, `WRKT Watch Watch App/Views/VirtualRunView.swift:144`

```swift
static let uiInterpolationInterval: TimeInterval = 0.1  // ← never used
```

The `runPage`'s `TimelineView` fires at **1.0 second** intervals — 10× slower than this constant suggests. The constant isn't referenced anywhere in the actual timing code. Interpolation (`partnerStats.interpolate()`) fires at 1Hz, not 10Hz.

If 10Hz was intentional (smooth distance counter), change `TimelineView(.periodic(from: .now, by: 1.0))` to use the constant. If 1Hz is correct, remove the constant to avoid confusion.

---

### GAP 2 — iOS active run card shows raw (non-interpolated) partner distance

**File:** `Features/Social/Views/Components/VirtualRunFlowStatusCard.swift:217`

```swift
partnerValue: partnerSnap.map { formatDistance($0.distanceM) } ?? "—"
```

On the Watch, `PartnerSection` uses `partner.displayDistanceM` (interpolated — estimates movement between snapshots). The iOS card uses `partnerSnap.distanceM` (raw — jumps every 3s, then sits frozen). The partner appears to stop between snapshots on the iPhone view.

Options: expose a shared interpolation utility, or add a simple extrapolation on the iOS card using `currentPaceSecPerKm` and `clientRecordedAt` from the snapshot.

---

### GAP 3 — `ReconnectionManager` on Watch is never called

**File:** `WRKT Watch Watch App/VirtualRunManager.swift:786`

`reconnectionManager` is instantiated and reset in `endVirtualRun()`, but `scheduleReconnect(action:)` is never called anywhere. The reconnection logic for the Watch→iPhone WC channel is handled implicitly by WCSession's own retry and the queue-on-unreachable pattern. This class is dead code and can mislead future developers.

Either wire it up or remove it.

---

### GAP 4 — Stale data detection uses floating-point equality on `Double`

**File:** `WRKT Watch Watch App/VirtualRunManager.swift:504`

```swift
if heartRate == nil && currentDistance == lastNonZeroDistance && currentDistance > 0 {
```

Works reliably now because both values come from the same property (bitwise identical if unchanged), but fragile across code changes.

**Fix:**
```swift
if heartRate == nil && abs(currentDistance - lastNonZeroDistance) < 0.001 && currentDistance > 0 {
```

---

### GAP 5 — `HRZoneCalculator` returns zone `1` for sub-zone HR; Watch returns `0`

**File:** `Core/Utilities/HRZoneCalculator.swift:130` vs `WRKT Watch Watch App/Utilities/HRZoneHelper.swift:42`

When HR is below 50% maxHR (no meaningful zone):
- iOS calculator returns zone **1** (wrong — zone 1 colour applied)
- Watch helper returns zone **0** → `.clear` background (correct)

**Fix in `HRZoneCalculator.zone(for:)`:**
```swift
return 0  // was: return 1
```

---

## 3. ARCHITECTURE OBSERVATIONS

---

### OBS 1 — `isInVirtualRun` is redundant with `phase != .idle`

**File:** `WRKT Watch Watch App/VirtualRunManager.swift:40`

Both track the same fact and are kept in sync. Any future modification touching one and not the other will diverge. Remove `isInVirtualRun` and use `phase != .idle`, or keep `isInVirtualRun` as the canonical flag and derive the phase from it.

---

### OBS 2 — `HRZoneCalculator` doesn't re-derive from profile age on server push

**File:** `Core/Utilities/HRZoneCalculator.swift:178`

`loadOrCreateConfig()` loads the UserDefaults cache without comparing against the current age. If a user updates their birthday via Supabase profile sync without explicitly calling `recalculate()`, the Watch receives stale `myMaxHR` on the next run.

Whoever reads `userAge` from a profile sync should call `HRZoneCalculator.shared.recalculate()` after updating.

---

### OBS 3 — Partner-finished detection relies on CDC for the Watch notification

**File:** `Features/Social/Services/VirtualRunInviteCoordinator.swift:276`

The Watch only gets the "Partner Finished" overlay after this chain completes:

```
Partner's Watch → WC → Partner's iPhone → completeRun RPC → Supabase → CDC → Our iPhone → WC → Our Watch
```

CDC latency is 0–30s and known unreliable. Consider supplementing with a broadcast event (`"partner_finished"`) that the partner's iPhone publishes immediately after `completeRun`, analogous to how the `"ready"` signal replaced CDC for acceptance detection. This would cut latency from 0–30s to ~100ms.

---

### OBS 4 — `sendVirtualRunPartnerFinished` uses inline dict keys, unlike all other VR messages

All other VR messages use the standard `"data": <Data>` envelope. `partnerFinished` puts data inline in the root dict (`message["partnerDistance"]`). This inconsistency is what makes Bug 1 harder to notice on review, and makes the handler fragile to future refactors.

---

### OBS 5 — Timer closures in `@MainActor` class missing actor annotation

**Files:** `VirtualRunManager.swift:357`, `VirtualRunInviteCoordinator.swift:118`

```swift
let pubTimer = Timer(timeInterval: publishInterval, repeats: true) { [weak self] _ in
    self?.publishCurrentStats()  // @MainActor-isolated method called from non-isolated closure
}
```

Safe at runtime (RunLoop.main fires on the main thread) but will produce Swift 6 strict concurrency warnings.

**Fix:**
```swift
let pubTimer = Timer(timeInterval: publishInterval, repeats: true) { [weak self] _ in
    Task { @MainActor [weak self] in self?.publishCurrentStats() }
}
```

---

## 4. DATA FLOW SPEED Assessment

Round-trip chain for partner data reaching the Watch:

| Leg | Transport | Typical Latency |
|-----|-----------|----------------|
| Watch publishes stats | HealthKit → Timer (3s cadence) | 0–3s |
| Watch → iPhone | WatchConnectivity sendMessage | 50–200ms |
| iPhone → Supabase | Broadcast publish | 30–80ms |
| Supabase → Partner iPhone | Broadcast delivery | 30–80ms |
| Partner iPhone → Watch | WC sendMessage | 50–200ms |

**Best-case end-to-end: ~500ms. Worst-case (low battery mode, 5s cadence): ~5.5s.**

The 3s publish interval is appropriate. At 1Hz Watch display refresh, the max visible lag is ~4s in normal mode. The `50m` and `> 1800 sec/km` pace guards prevent garbage data. `staleDataThreshold (8s)` = ~2–3 missed snapshots before orange. `disconnectThreshold (15s)` = ~5 missed snapshots. All well-calibrated.

---

## Priority Fix List

| # | Severity | Location | Fix |
|---|----------|----------|-----|
| 1 | **HIGH** | iOS WCM `sendVirtualRunPartnerFinished` | Change `"messageType"` → `"type"` in transferUserInfo |
| 2 | **MEDIUM** | iOS WCM `sendVirtualRunEnded` | Add `transferUserInfo` fallback for unreachable Watch |
| 3 | **MEDIUM** | Watch WCM `handleVirtualRunEnded` | Add `guard isInVirtualRun` dedup guard |
| 4 | **MEDIUM** | `VirtualRunSharedModels` | Wire `uiInterpolationInterval` to TimelineView or remove |
| 5 | **MEDIUM** | `VirtualRunFlowStatusCard` | Interpolate partner distance on iOS card |
| 6 | **LOW** | `HRZoneCalculator.zone(for:)` | Return `0` not `1` for sub-zone HR |
| 7 | **LOW** | `VirtualRunManager` | Remove dead `ReconnectionManager` or wire it up |
| 8 | **LOW** | `VirtualRunManager.publishCurrentStats` | Use epsilon for distance staleness comparison |
| 9 | **LOW** | Timer closures | Add `@MainActor` annotation for Swift 6 compliance |
| 10 | **DESIGN** | `VirtualRunInviteCoordinator` | Supplement partner-finished CDC with broadcast event |
