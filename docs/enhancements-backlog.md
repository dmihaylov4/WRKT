# Enhancements Backlog

Tracked improvements deferred until after the audit cycle. Each item includes context and a clear implementation path.

---

## ENH-1 · HomeView Hero During Virtual Run

**Status**: Deferred — implement after all audits complete
**Context**: During a virtual run the HomeView hero is blank because it only knows about regular strength workouts. The Watch is running and sending live snapshots to the iPhone, but nothing surfaces them in the hero.

### Goal

When the user is in an active virtual run, the HomeView hero should switch from the strength-workout display to a VR live-stats display — mirroring what the Apple Watch shows, but on the phone. This creates a natural "glanceable companion" for the person who left their phone on a treadmill or desk.

### Data Already Available on iPhone

The iPhone receives every Watch snapshot via WCSession (`WatchConnectivityManager.shared`). The coordinator already tracks run state:

- `VirtualRunInviteCoordinator.shared.isInActiveRun` — true while VR is running
- `VirtualRunInviteCoordinator.shared.activeRunId` — the current run UUID
- Snapshots are forwarded from Watch → iPhone → Supabase Broadcast; the iPhone is the bridge

The missing piece is exposing the latest received snapshot to the UI layer.

### Suggested Implementation

1. **Expose latest snapshot in `VirtualRunInviteCoordinator`**
   Add a `@Published var latestMySnapshot: VirtualRunSnapshot?` property. Populate it in `WatchConnectivityManager.handleVirtualRunSnapshot()` (the function that already receives snapshots from the Watch before forwarding to Supabase).

2. **Add a `VRHeroView` component**
   A compact view that reads from `VirtualRunInviteCoordinator.shared`:
   - My distance, pace, and HR (from `latestMySnapshot`)
   - Partner name and their latest distance (from `partnerStats` snapshots already flowing through `WatchConnectivityManager`)
   - Elapsed duration (computed from `activeRunStartTime`)

3. **Conditionally swap the hero in `HomeView`**
   ```swift
   // In HomeView body
   if VirtualRunInviteCoordinator.shared.isInActiveRun {
       VRHeroView()
   } else {
       // existing strength workout hero
   }
   ```

4. **No HKWorkoutSession on iPhone needed**
   The Watch owns the HK recording. The iPhone hero reads entirely from WCSession snapshot data — no duplicate Health.app entries.

### Notes

- The Watch→iPhone snapshot pipeline already exists and is tested. This is purely a UI addition.
- The auto-end bug that this enhancement is related to was fixed separately (CRIT-3 follow-up): `buildWatchWorkoutState()` now returns `isActive: true` during a virtual run so the Watch's `HKWorkoutSession` is never auto-terminated by an `isActive: false` state sync.

---
