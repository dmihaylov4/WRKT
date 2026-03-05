# Virtual Run — iPhone Background Execution

> Written: 2026-03-02

## Problem

The virtual run data chain is:

```
Watch A → [WC sendMessage] → Phone A → [Supabase WebSocket] → Phone B → [WC sendMessage] → Watch B
```

When Phone A's screen locks, iOS eventually suspends the WRKT app.
Once suspended:

- `WCSession.isReachable` drops to `false` on Watch A — `sendMessage` fails silently, snapshots queue in-memory
- `vrSnapshot` is not in `criticalMessageTypes` — the in-memory queue evicts snapshots as it fills
- The Supabase broadcast WebSocket dies within ~5 seconds of backgrounding
- No data reaches Supabase → Watch B sees nothing

**Test confirmed:** partner data updates only when the paired phone is unlocked (app in foreground).
When both phones are unlocked, data arrives in ~500ms end-to-end. When either phone is locked, that side's data stops entirely.

---

## Two Viable Solutions

### Approach A — AVAudioSession Background Audio *(recommended)*
### Approach B — Mirrored HKWorkoutSession on iPhone *(Apple-endorsed, higher effort)*

---

## Approach A: AVAudioSession Background Audio

### How It Works

Add `audio` to `UIBackgroundModes`. Activate an `AVAudioSession` with the `.playback` category at the start of a virtual run. iOS sees an active audio session and **never suspends the app** for its duration. WCSession, the Supabase WebSocket, and timers all fire exactly as in the foreground.

The session does not need to be actively playing audio to keep the app alive — it just needs to be *active*. Between audio cues the session is silent. Strava, Nike Run Club, and Garmin Connect all use this exact pattern.

### Industry Precedent

Every major running app in the App Store uses this approach because:
- It is the simplest persistent background mechanism for audio-producing apps
- It has been approved by App Review at massive scale
- `workout-processing` mode requires a full HealthKit workout session on iPhone, which is significant added complexity

### App Review Legitimacy

**Solid, provided the iPhone plays real audio cues.** Declaring `audio` background mode without any user-audible audio output is grounds for rejection. WRKT already has `VirtualRunAudioCues` on the Watch (km markers, lead changes, partner finished). Porting those announcements to the iPhone speaker/AirPods is a genuine UX improvement — users with the phone in an armband get verbal feedback even when the Watch is out of earshot.

### WRKT-Specific Context

The Watch's `VirtualRunAudioCues.swift` uses a **transient** audio session pattern — it activates the session immediately before speaking and deactivates it in `speechSynthesizer(_:didFinish:)`. This is correct for the Watch because `workout-processing` is what keeps the Watch app alive; audio is just for cues.

The iPhone implementation must use a **persistent** session pattern — activate once at run start, leave active throughout, deactivate once at run end. Per-utterance deactivation on iPhone would create windows where the app could be suspended between cues.

---

### Implementation

#### 1. Info.plist — add `audio` background mode

**File:** `WRKT-Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
    <string>fetch</string>
    <string>audio</string>    <!-- add this -->
</array>
```

#### 2. New iPhone audio cues class

**File:** `Features/Social/Services/iPhoneVirtualRunAudioCues.swift`

```swift
import AVFoundation

/// Provides spoken audio cues during a virtual run on iPhone.
///
/// Lifecycle: call `startSession()` when the virtual run becomes active,
/// `endSession()` when it ends. The AVAudioSession is held open persistently
/// between those points so iOS does not suspend the app.
///
/// This is intentionally separate from the Watch's VirtualRunAudioCues —
/// the Watch uses a transient session (activate/deactivate per utterance)
/// because workout-processing keeps the Watch alive. iPhone needs a
/// persistent session because audio is the only background mode keeping it alive.
@MainActor
final class iPhoneVirtualRunAudioCues: NSObject {
    static let shared = iPhoneVirtualRunAudioCues()

    private let synthesizer = AVSpeechSynthesizer()
    private var isSessionActive = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iPhoneVRAudioCuesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "iPhoneVRAudioCuesEnabled") }
    }

    private override init() {
        super.init()
        if UserDefaults.standard.object(forKey: "iPhoneVRAudioCuesEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "iPhoneVRAudioCuesEnabled")
        }
        synthesizer.delegate = self
    }

    // MARK: - Session Lifecycle

    /// Activate the audio session. Call when virtual run becomes active.
    /// Keeps the iPhone app alive in background for the duration.
    func startSession() {
        guard !isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionActive = true
            setupInterruptionHandling()
        } catch {
            // Non-fatal: app may be suspended on lock, but run can continue
            print("[iPhoneVRAudio] Failed to activate session: \(error)")
        }
    }

    /// Deactivate the audio session. Call when virtual run ends.
    /// Restores the user's music/podcast volume.
    func endSession() {
        guard isSessionActive else { return }
        synthesizer.stopSpeaking(at: .immediate)
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        isSessionActive = false
    }

    // MARK: - Cues

    func announceKilometer(_ km: Int) {
        guard isEnabled, isSessionActive else { return }
        let text = km == 1 ? "1 kilometer" : "\(km) kilometers"
        speak(text)
    }

    func announceLeadChange(isLeading: Bool) {
        guard isEnabled, isSessionActive else { return }
        speak(isLeading ? "You took the lead" : "Partner took the lead")
    }

    func announcePartnerFinished() {
        guard isEnabled, isSessionActive else { return }
        speak("Partner finished")
    }

    // MARK: - Private

    private func speak(_ text: String) {
        // Session is already active — just speak
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.volume = 0.8
        synthesizer.speak(utterance)
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    /// Reactivates the audio session after a phone call or other interruption.
    /// Without this, the session dies post-interruption and the app can be suspended.
    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended, isSessionActive {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
}

extension iPhoneVirtualRunAudioCues: AVSpeechSynthesizerDelegate {
    // No deactivation here — session stays active between cues.
    // This is the key difference from the Watch implementation.
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {}
}
```

#### 3. Wire into VirtualRunInviteCoordinator

**File:** `Features/Social/Services/VirtualRunInviteCoordinator.swift`

In `enterActiveRun()`, after the existing guard:
```swift
// Activate audio session to keep iPhone alive in background
iPhoneVirtualRunAudioCues.shared.startSession()
```

In `endRun()` / wherever the run terminates:
```swift
iPhoneVirtualRunAudioCues.shared.endSession()
```

Mirror the existing Watch km milestone logic to also announce on iPhone:
```swift
// In the coordinator where myRunSnapshot is updated or received
let currentKm = Int((myRunSnapshot?.distanceM ?? 0) / 1000)
if currentKm > lastAnnouncedKm {
    lastAnnouncedKm = currentKm
    iPhoneVirtualRunAudioCues.shared.announceKilometer(currentKm)
}
```

---

### Failure Modes and Mitigations

| Failure | What happens | Mitigation |
|---|---|---|
| Session interrupted by phone call | Session deactivated → app can suspend | `interruptionNotification` observer reactivates on `.ended` |
| Session interrupted and call lasts >30s | App suspended during call | Accept — app resumes when call ends and user unlocks; session reactivates via handler |
| User has audio output disabled (no speaker, no headphones in silent mode) | voicePrompt mode respects device behaviour | Expected — cues may not play, but session stays active regardless |
| `setActive(true)` throws on run start | `isSessionActive = false`, app may suspend on lock | Non-fatal; log and continue; run is still functional |

### What This Does NOT Fix

- If the user's phone has **Low Power Mode** enabled, iOS may still limit background execution
- If the user **force-quits** the app from the App Switcher, no background mode survives
- The Supabase broadcast **WebSocket** may still die if the OS aggressively tears down network connections despite the audio background — the existing DB catch-up poll on Phone B covers this

---

## Approach B: Mirrored HKWorkoutSession on iPhone

### How It Works

watchOS 10 / iOS 17 introduced workout session mirroring. When the Watch starts an `HKWorkoutSession`, the companion iPhone app can adopt a mirrored copy of that session via `HKHealthStore.workoutSessionMirroringStartHandler`. This grants the iPhone app `workout-processing` background mode — Apple's purpose-built, indefinite background execution for workout companion apps.

### App Review Legitimacy

Unambiguous. `workout-processing` combined with a Watch workout companion is exactly what Apple designed this mode for. No risk of rejection.

### WRKT Architectural Context

The team previously made an explicit decision against adding `HKWorkoutSession` on iPhone (documented in `docs/enhancements-backlog.md:47`). The reasons remain valid:

1. The VR flow and HK workout lifecycle are deliberately decoupled. The virtual run uses HK only on the Watch, for the runner's own health data. The iPhone is a relay, not a health data recorder.
2. Both users' phone apps need working mirrored sessions. A failure to establish mirroring on either side requires a graceful fallback.
3. Additional HealthKit permissions are required on iPhone, adding to the user onboarding flow.

This approach is documented here for completeness and for future consideration if WRKT ever adds iPhone-side workout tracking.

---

### Implementation

#### 1. Info.plist — add `workout-processing`

**File:** `WRKT-Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
    <string>fetch</string>
    <string>workout-processing</string>    <!-- add this -->
</array>
```

#### 2. HealthKit authorization — add workout types on iPhone

In the iPhone HealthKit authorization request (wherever the app requests HK access), add:

```swift
let typesToRead: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    // ... existing types
]
```

#### 3. Register mirroring handler at app startup

This **must** happen before the Watch workout starts. Register it in the app entry point, not in the VR flow.

**File:** `App/WRKTApp.swift` (or AppDelegate)

```swift
@main
struct WRKTApp: App {
    init() {
        // Must be registered before any Watch workout starts.
        // The system calls this when a Watch workout begins mirroring.
        let healthStore = HKHealthStore()
        healthStore.workoutSessionMirroringStartHandler = { mirroredSession in
            Task { @MainActor in
                VirtualRunMirroringManager.shared.adoptMirroredSession(mirroredSession)
            }
        }
    }
    // ...
}
```

#### 4. iPhone-side mirroring manager

**File:** `Features/Social/Services/VirtualRunMirroringManager.swift`

```swift
import HealthKit

/// Manages the mirrored HKWorkoutSession on iPhone.
/// The session is the mechanism that keeps the iPhone app alive in background
/// during an active Watch workout, via the workout-processing background mode.
@MainActor
final class VirtualRunMirroringManager: NSObject {
    static let shared = VirtualRunMirroringManager()
    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?

    private override init() { super.init() }

    func adoptMirroredSession(_ session: HKWorkoutSession) {
        // Only adopt if a virtual run is actually active
        guard VirtualRunInviteCoordinator.shared.isInActiveRun else {
            // Not a VR workout — ignore (could be a regular workout)
            return
        }
        mirroredSession = session
        session.delegate = self
        // iPhone is now in workout-processing background mode.
        // WCSession, Supabase WebSocket, timers all fire normally.
    }

    func endMirroredSession() {
        mirroredSession = nil
    }
}

extension VirtualRunMirroringManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .ended || toState == .stopped {
            Task { @MainActor in
                self.endMirroredSession()
                // Note: VR may still be active even if Watch workout ended.
                // Do NOT end the VR here — let the VR flow manage its own lifecycle.
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.endMirroredSession()
            // Mirroring failed — app may be suspended if phone locks.
            // The audio fallback approach would be preferable here.
        }
    }
}
```

#### 5. Timing dependency — the critical constraint

The Watch starts its `HKWorkoutSession` during the virtual run countdown, inside `WatchHealthKitManager.startWorkout()`. The mirroring handler on iPhone fires at that moment. If the iPhone app was just launched and the handler wasn't registered before the Watch workout started, the mirrored session will not connect for this run.

**Mitigation:** The handler is registered at app startup (step 3), so as long as the iPhone app has been launched at least once before the Watch starts the workout, it will work. This is a reasonable assumption for a paired VR flow.

---

### Failure Modes and Mitigations

| Failure | What happens | Mitigation |
|---|---|---|
| Handler not registered before Watch workout starts | Mirroring never establishes; app can suspend | Register at app startup, not in VR flow |
| HealthKit authorization not granted on iPhone | `workoutSessionMirroringStartHandler` may not fire | Request HK authorization during onboarding |
| Watch workout ends before VR ends | Mirrored session ends → `workout-processing` revoked | VR and HK lifecycles must be explicitly decoupled |
| Mirroring silently fails (Bluetooth drop) | App gradually loses background priority | Require fallback (audio or `beginBackgroundTask`) |

---

## Side-by-Side Comparison

| | **Approach A: Audio Session** | **Approach B: HKWorkoutSession Mirror** |
|---|---|---|
| **Implementation effort** | 2–3 hours | 1–2 days |
| **iOS / watchOS minimum** | Any | iOS 17+ / watchOS 10+ |
| **Background mechanism** | Active `AVAudioSession` | `workout-processing` mode |
| **Survives phone call interruption** | Only with interruption handler | Yes, natively |
| **App Review risk** | Low — requires real audio cues | None |
| **Architecture impact** | Minimal — isolated new class + 2 call sites | Medium — touches app startup, HK auth, new manager |
| **Failure mode** | Session interrupted + handler missing | Mirroring fails to establish |
| **Graceful degradation** | App may suspend during interruption | App may suspend if mirroring fails |
| **User-visible benefit** | Spoken cues on iPhone (km markers, lead change) | None directly |
| **Industry precedent** | Strava, Nike Run Club, Garmin | Apple Fitness app, paired workout apps |
| **Prior team decision** | No prior decision | Explicitly decided against (enhancements-backlog.md:47) |

---

## Recommendation

**Implement Approach A.**

1. **Simpler and faster.** 2–3 hours versus 1–2 days. The VR implementation is already complex; adding a mirrored HK session introduces coupling between two already-intricate state machines.

2. **The prior architectural decision stands.** The iPhone is a relay, not a health recorder. Adding a mirrored workout session blurs that separation.

3. **Real user value.** iPhone audio cues (km markers, lead changes, partner finished) are a genuine improvement — users running with AirPods connected to their phone get verbal feedback without looking at either device.

4. **Battle-tested.** The audio approach has been used by apps serving hundreds of millions of users and has a known set of failure modes with established mitigations.

5. **App Review is clear.** The declared audio background mode is directly justified by the audio cues feature.

---

## Related Files

| File | Role |
|---|---|
| `WRKT-Info.plist` | Add `audio` to `UIBackgroundModes` |
| `Features/Social/Services/iPhoneVirtualRunAudioCues.swift` | New — persistent audio session + cues |
| `Features/Social/Services/VirtualRunInviteCoordinator.swift` | Wire `startSession()` / `endSession()` calls |
| `WRKT Watch Watch App/Utilities/VirtualRunAudioCues.swift` | Existing Watch cues — transient session pattern, unchanged |
| `docs/virtual-run-audit.md` | Background section cross-references this doc |
