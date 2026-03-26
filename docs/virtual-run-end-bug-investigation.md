# Virtual Run "Both Runs End" Bug — Investigation Notes

## Bug Description
When User A presses "End Run" on their Apple Watch during a virtual run, **both** users' runs appear to end — instead of only User A's run ending.

User B observation: "User B just sees the VirtualRunView disappear and both see the win screen. User B doesn't see partner finishes at all."

## Root Cause — IDENTIFIED AND FIXED

### The Chain of Events

1. `sendVirtualRunStarted()` on iPhone ALWAYS sends via `transferUserInfo` (guaranteed delivery, FIFO queue).
2. Between test runs, the previous run's `transferUserInfo` remains in Apple's delivery queue.
3. When it arrives during the **current** active run on Watch B, `handleVirtualRunStarted(previousRunId)` is called.
4. `lastProcessedVRRunId` = `currentRunId` ≠ `previousRunId`, so the dedup check passes.
5. Without the guard fix, `setPendingRun(previousRunId)` would be called during an active run, setting `phase = .pendingConfirmation`.
6. 60 seconds later, `confirmationTimeoutTimer` fires → `declineRun()` → `phase = .idle` (VirtualRunView disappears on Watch B).
7. `declineRun()` sends `vrRunEnded` with an **empty payload** (no runId, no stats) to iPhone B.
8. iPhone B's stale-run guard (`if let payloadRunId = runIdFromPayload`) is skipped because the payload has no runId.
9. iPhone B calls `complete_virtual_run` RPC with `duration_s = 0` (IS NOT NULL) — this is treated as a valid submission.
10. If User A already submitted stats, both sides now have non-null `duration_s` → `complete_virtual_run` marks run `completed`.
11. Both phones show the win screen.

This also explains why User B never sees "Partner Finished" overlay: `sendVirtualRunPartnerFinished`'s guaranteed delivery path used the wrong WCSession key (`"messageType"` instead of `"type"`), so Watch B silently dropped it.

## What `complete_virtual_run` SQL Function Does — CONFIRMED CORRECT

Migration 028 is applied to Supabase. The function:
- Saves the calling user's stats only
- Only marks run as `completed` when **both** users have non-null `duration_s`
- If only one user has submitted, status stays `'active'`

This was **NOT** the root cause. `duration_s = 0` from `declineRun()` counts as non-null.

## Fixes Applied

### Fix 1: Guard against stale `vrRunStarted` during active run (root cause fix)
**File**: `WRKT Watch Watch App/VirtualRunManager.swift` — `setPendingRun()`

Added `guard phase == .idle` at the top of `setPendingRun()`. If Watch is already active/paused/counting down, the stale `vrRunStarted` message is silently discarded with a warning log. Prevents the confirmation timeout from firing during an active run.

### Fix 2: Include runId in `declineRun()` payload
**File**: `WRKT Watch Watch App/VirtualRunManager.swift` — `declineRun()`

`declineRun()` now captures `pendingRunInfo?.runId` before clearing state and includes it in the `vrRunEnded` payload. iPhone's stale-run guard can now detect and reject a stale decline if it arrives after a new run has already started.

### Fix 3: Correct WCSession key in `sendVirtualRunPartnerFinished` transferUserInfo
**File**: `Core/Services/WatchConnectivityManager.swift` — `sendVirtualRunPartnerFinished()`

Changed `"messageType"` to `"type"` in the `transferUserInfo` call. Watch's `handleIncomingMessage` dispatches on `message["type"]`; messages with `"messageType"` were silently dropped. This restores guaranteed delivery of the "Partner Finished" overlay to Watch B.

## Known Separate Bug (Not Fixed — Minor)

`declineRun()` on Watch sends `type: .runEnded` — same message type as End Run (different flow). Now that it includes a runId, iPhone can distinguish it. The stale-run guard on iPhone also uses `lastProcessedVREndRunId` as a dedup, so double-processing is prevented.

## What `sendVirtualRunEnded()` Does

The only iPhone-side function that sends `vrRunEnded` to the Watch. It is **only** called from `VirtualRunDebugView` — never from any automatic flow.

## What CANNOT Cause Watch B to End (Confirmed)

- `VirtualRunInviteCoordinator.runEnded()` does NOT send `vrRunEnded` to Watch B
- `sendVirtualRunEnded()` is only called from the debug view
- The CDC path only sends `vrPartnerFinished` to Watch B (shows overlay, does not end run)
- `handlePartnerFinished` on Watch B only sets `showPartnerFinished = true`, no auto-end
- No `.onChange`/`.onReceive` in VirtualRunView that auto-triggers run end
