# Plan: Virtual Run Status Card (Both-Sides Feedback)

## Context

The Virtual Run invite flow currently has many silent phases:
- **Inviter**: taps "Invite", sheet dismisses, nothing visible happens until run magically starts on Watch or silently fails
- **Invitee**: accepts, spinner appears briefly on the banner, then nothing — no feedback while Watch is being notified
- **Failures**: network errors, Watch unreachable, etc. are silently swallowed

**Goal**: A persistent `VirtualRunFlowStatusCard` floats at the bottom of the screen throughout the entire lifecycle for both users — showing what's happening at every phase and offering retry/cancel actions on failure. It dismisses automatically when the Watch countdown begins.

---

## Architecture Overview

```
AppShellView (global overlay)
  └── VirtualRunFlowStatusCard           ← NEW (floating, bottom, z=998)
        reads: VirtualRunInviteCoordinator.flowPhase
        reads: VirtualRunInviteCoordinator.retryAction

VirtualRunInviteCoordinator              ← EXTENDED (additive only)
  + flowPhase: VirtualRunFlowPhase       ← NEW observable property
  + retryAction: closure                 ← NEW for retry button
  + cancelSentInvite()                   ← NEW (wraps existing Supabase cancel)
  + onWatchConfirmed()                   ← NEW (called by WCM when Watch confirms)

Core/Models/VirtualRunModels.swift       ← ADD 2 enums
WatchConnectivityManager (iOS)           ← ADD notify coordinator on watchConfirmed
```

---

## Step 1 — Add `VirtualRunFlowPhase` enum

**File:** `Core/Models/VirtualRunModels.swift`

Append after existing model definitions:

```swift
/// Tracks the full invite → accept → watch-sync lifecycle for both users
enum VirtualRunFlowPhase: Equatable {
    case idle                                          // No active flow; card hidden
    case sendingInvite                                 // REST call in flight (inviter)
    case waitingForPartner(partnerName: String)        // Invite sent, awaiting acceptance
    case connecting                                    // Invitee accepted, setting up
    case syncingWithWatch(partnerName: String)         // sendVirtualRunStarted called, awaiting Watch
    case watchReady                                    // vr_watch_confirmed received — auto-dismiss in 2s
    case failed(VirtualRunFlowError)
}

enum VirtualRunFlowError: Equatable {
    case sendFailed                   // REST call to create invite failed
    case watchUnreachable             // WCSession not reachable after entering active run
    case acceptFailed                 // REST call to accept invite failed
    case generic(String)              // Catch-all with description
}
```

---

## Step 2 — Extend `VirtualRunInviteCoordinator` (additive only)

**File:** `Features/Social/Services/VirtualRunInviteCoordinator.swift`

### New properties (add near top of class):
```swift
private(set) var flowPhase: VirtualRunFlowPhase = .idle
private(set) var retryAction: (@MainActor @Sendable () async -> Void)?
```

### Phase transitions at existing call sites (no logic changes, only side-effects added):

| Existing code | Add after |
|---|---|
| `trackSentInvite()` body after setting `isWaitingForAcceptance = true` | `flowPhase = .waitingForPartner(partnerName: partnerName)` |
| Top of `acceptInvite()` (before REST call) | `flowPhase = .connecting` |
| Inside `enterActiveRun()` after `sendVirtualRunStarted()` call | `flowPhase = .syncingWithWatch(partnerName: partnerName)` |
| Inside `runEnded()` | `flowPhase = .idle` |
| `catch` blocks in `acceptInvite()` | `flowPhase = .failed(.acceptFailed)` + set `retryAction` |

### New methods:

```swift
/// Called by WatchConnectivityManager when iOS receives vr_watch_confirmed.
/// Signals Watch countdown is live; auto-dismisses card after 2s.
func onWatchConfirmed() {
    flowPhase = .watchReady
    Task {
        try? await Task.sleep(for: .seconds(2))
        if flowPhase == .watchReady { flowPhase = .idle }
    }
}

/// Cancel a pending sent invite (REST + state reset).
func cancelSentInvite() async {
    guard let inviteId = sentInviteId else { flowPhase = .idle; return }
    do {
        // Use declineInvite — there is no separate cancelInvite endpoint.
        try await AppDependencies.shared.virtualRunRepository.declineInvite(inviteId)
    } catch { /* best-effort */ }
    sentInviteId = nil
    sentInvitePartnerName = nil
    sentInvitePartnerId = nil
    isWaitingForAcceptance = false
    flowPhase = .idle
}

/// Set failed state with optional retry closure.
func setFailed(_ error: VirtualRunFlowError, retry: (@MainActor @Sendable () async -> Void)? = nil) {
    flowPhase = .failed(error)
    retryAction = retry
}
```

### Error handling for invite send:

In `VirtualRunInviteView.sendInvite()`, set `.sendingInvite` before the REST call and handle failure.
`sendInvite()` already has a do/catch — extend the existing `catch` block.

**Important:** `VirtualRunInviteView` is a SwiftUI struct (value type), so `[weak self]` cannot be
used in the retry closure. Capture only value types (friend ID, name) and call the shared
coordinator + repository directly:

```swift
// Before the REST call:
VirtualRunInviteCoordinator.shared.flowPhase = .sendingInvite   // (via setFailed companion)

// Replace the generic catch block with:
} catch let vrError as VirtualRunError where vrError == .alreadyInActiveRun {
    // existing stale-run handling unchanged
} catch {
    let fId = friend.profile.id
    let fName = friend.profile.displayName ?? friend.profile.username
    VirtualRunInviteCoordinator.shared.setFailed(.sendFailed, retry: {
        guard let userId = SupabaseAuthService.shared.currentUser?.id else { return }
        let run = try await AppDependencies.shared.virtualRunRepository.sendInvite(to: fId, from: userId)
        VirtualRunInviteCoordinator.shared.trackSentInvite(runId: run.id, partnerId: fId, partnerName: fName)
    })
}
```

The retry closure captures `fId`/`fName` (value types), calls the repository directly, and
calls `trackSentInvite` on success — no `self` capture needed.

---

## Step 3 — Create `VirtualRunFlowStatusCard`

**File:** `Features/Social/Views/Components/VirtualRunFlowStatusCard.swift` (NEW)

### Structure:
```
VirtualRunFlowStatusCard
 ├─ if phase == .idle → EmptyView (card not shown; transition handles animation)
 └─ CardBody (slides in from bottom)
     ├─ Header row: figure.run icon + "Virtual Run" label + X dismiss button
     ├─ Status indicator: ProgressView (waiting phases) OR SF Symbol icon (failed/ready)
     ├─ Message text (phase-specific, cross-fades on change)
     └─ Action buttons (contextual per phase)
```

### Phase → copy mapping:

| Phase | Indicator | Message | Buttons |
|---|---|---|---|
| `.sendingInvite` | `ProgressView` | "Sending invite…" | — |
| `.waitingForPartner(name)` | pulsing dot | "Waiting for **\(name)** to accept" | Cancel Invite |
| `.connecting` | `ProgressView` | "Connecting to run…" | — |
| `.syncingWithWatch(name)` | `ProgressView` | "Starting run on your Watch…" | — |
| `.watchReady` | `checkmark.circle` (brand green) | "Get ready!" | — (auto-dismiss) |
| `.failed(.sendFailed)` | `exclamationmark.triangle` | "Couldn't send the invite" | Try Again / Dismiss |
| `.failed(.watchUnreachable)` | `applewatch.radiowaves.left.and.right` | "Couldn't reach your Watch" | Try Again / Dismiss |
| `.failed(.acceptFailed)` | `exclamationmark.triangle` | "Couldn't join the run" | Try Again / Dismiss |
| `.failed(.generic(msg))` | `exclamationmark.triangle` | msg | Try Again / Dismiss |

### Card Styling (DS system):

Note: `ChamferedRectangle` takes an unnamed `DS.Chamfer` enum parameter, NOT a `chamferSize:` label.
`ChamferedRectangle(chamferSize: DS.Chamfer.xl)` is a type error — use `ChamferedRectangle(.xl)`.

```swift
.background {
    ChamferedRectangle(.xl)
        .fill(DS.Semantic.card)
        .overlay(
            ChamferedRectangle(.xl)
                .strokeBorder(DS.Semantic.border, lineWidth: 1)
        )
}
.shadow(color: .black.opacity(0.2), radius: 16, y: 8)
```

### Animation:
```swift
.transition(.move(edge: .bottom).combined(with: .opacity))
.animation(.spring(response: 0.4, dampingFraction: 0.85), value: phase)
```

Message text cross-fades on phase change via `.contentTransition(.opacity)`.

### Pulsing dot (for waitingForPartner):
A `Circle` that scales 0.8→1.0 with a repeating spring animation — communicates "live" waiting state without a ProgressView spinner.

---

## Step 4 — Wire into `AppShellView`

**File:** `App/AppShellView.swift`

In `mainContentWithOverlays`, add alongside `UndoToastOverlay`:

```swift
VirtualRunFlowStatusCard()
    .padding(.horizontal, 16)
    .padding(.bottom, 74)   // 62pt tab bar + 12pt gap (mirrors liveOverlayCard hardcoded value)
    .zIndex(998)
```

Note: `AppShellView` has no `tabBarHeight` variable. The live overlay card uses `.padding(.bottom, 62)`
hardcoded. Use a similarly hardcoded value — 62 (tab bar) + 12 (gap) = 74.

The card reads `VirtualRunInviteCoordinator.shared.flowPhase` directly and is only visible when `phase != .idle`.

---

## Step 5 — Wire `vr_watch_confirmed` on iOS side

**File:** `Core/Services/WatchConnectivityManager.swift` (iOS)

The `vrWatchConfirmed` case is **already handled** at line ~400 (dispatches to
`handleVirtualRunWatchConfirmed(_:)`). Do NOT add a new switch case — it would be unreachable.

Instead, add one line inside the existing `handleVirtualRunWatchConfirmed(_:)` method,
after the existing `NotificationCenter.default.post(...)` call:

```swift
private func handleVirtualRunWatchConfirmed(_ message: [String: Any]) {
    AppLogger.info("Watch user confirmed virtual run — countdown started", category: AppLogger.app)

    var startTime: Date?
    if let payload = message["payload"] as? Data,
       let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
       let ts = dict["startTime"] as? TimeInterval {
        startTime = Date(timeIntervalSince1970: ts)
    }

    NotificationCenter.default.post(
        name: NSNotification.Name("VirtualRunWatchConfirmed"),
        object: nil,
        userInfo: startTime.map { ["startTime": $0] }
    )

    // ← ADD THIS:
    Task { @MainActor in
        VirtualRunInviteCoordinator.shared.onWatchConfirmed()
    }
}
```

---

## Non-Breaking Guarantees

1. **All coordinator changes are additive** — new properties default to `.idle`, new methods don't touch existing ones. No existing method signatures change.
2. **Phase setting is a side-effect only** — all existing business logic (REST calls, WCSession sends, Supabase subscriptions) is unchanged. We only assign `flowPhase` alongside existing calls.
3. **Card is read-only observer** — it reads coordinator state but drives zero business logic.
4. **`cancelSentInvite()` wraps `declineInvite`** — there is no separate cancel endpoint; `declineInvite` is what the existing `VirtualRunInviteView.cancelActiveRun()` also uses.
5. **`sendingInvite` phase** — set before the REST call in `VirtualRunInviteView.sendInvite()`, transitions to `waitingForPartner` on success or `failed` on error. Existing dismiss-on-success path unchanged.

---

## Files Changed

| File | Change |
|---|---|
| `Core/Models/VirtualRunModels.swift` | Add `VirtualRunFlowPhase` + `VirtualRunFlowError` enums |
| `Features/Social/Services/VirtualRunInviteCoordinator.swift` | Add `flowPhase`, `retryAction`, `setFailed()`, `cancelSentInvite()`, `onWatchConfirmed()` + phase assignments at existing transition points |
| `Features/Social/Views/VirtualRunInviteView.swift` | Wrap `sendInvite()` in do/catch, set `.sendingInvite` before REST call, call `setFailed` in catch |
| `App/AppShellView.swift` | Add `VirtualRunFlowStatusCard` to overlay stack |
| `Core/Services/WatchConnectivityManager.swift` (iOS) | Call `VirtualRunInviteCoordinator.shared.onWatchConfirmed()` on watchConfirmed message |
| **NEW** `Features/Social/Views/Components/VirtualRunFlowStatusCard.swift` | Full card implementation |

---

## Verification

1. **Happy path (inviter)**:
   - Tap invite → card appears "Sending invite…" → "Waiting for Marco to accept"
   - Partner accepts → card transitions to "Starting run on your Watch…"
   - Watch confirms → "Get ready!" (2s auto-dismiss)

2. **Happy path (invitee)**:
   - Accept banner → card appears "Connecting to run…" → "Starting run on your Watch…"
   - Watch confirms → "Get ready!" → card dismisses

3. **Error: network fails on send**:
   - Card shows "Couldn't send the invite" + "Try Again"
   - Retry → phase returns to `sendingInvite`, re-attempts REST call

4. **Error: Watch unreachable**:
   - Card shows "Couldn't reach your Watch" + "Try Again"
   - Retry → re-calls `sendVirtualRunStarted()`

5. **Cancel invite while waiting**:
   - Card in `.waitingForPartner` → tap "Cancel Invite"
   - Supabase invite cancelled, card dismisses

6. **Tab switching while waiting**:
   - Card persists across tab navigation (lives in AppShellView, not SocialView)

7. **No regression**:
   - `isWaitingForAcceptance`, `isInActiveRun`, `pendingInvite` banner — all behave as before
   - Run start, Watch countdown, live stats — completely unaffected
