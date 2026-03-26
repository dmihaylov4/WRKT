# Watch App Rename + Idle Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Watch app from "WRKT Watch" to "Volia" and replace the broken "Start Rest" idle screen with a clean branded idle state.

**Architecture:** Two independent changes. The rename is a build-settings edit only. The idle screen replaces the dead `startButton` fallback in `SimpleTimerView` with a new `WatchIdleView` component; the working rest timer countdown/controls are untouched and continue to display when a timer is actually active.

**Tech Stack:** SwiftUI (watchOS), Xcode build settings (pbxproj)

---

## Context

### Current behaviour
`RootView` routes the Watch UI:
- `VirtualRunView` when `virtualRunManager.showVirtualRunUI == true`
- `ActiveWorkoutView` when `healthManager.isWorkoutActive == true`
- `SimpleTimerView` otherwise (the idle/default screen)

`SimpleTimerView` has two internal states:
1. **Timer active** (`connectivity.workoutState.restTimer.isActive == true`): shows a live countdown + skip/pause buttons — **works correctly**
2. **Timer inactive** (idle): shows a `startButton` that fires `.startRestTimer` to the iPhone — **non-functional** (iPhone isn't in a workout, message is ignored)

### What we're building
- `INFOPLIST_KEY_CFBundleDisplayName` → `Volia` in both Debug and Release Watch build configs
- `WatchIdleView` — a new file containing just the branded idle state (Volia wordmark + subtitle)
- `SimpleTimerView` — `startButton` replaced with `WatchIdleView()`; rest-timer logic untouched

---

## File Map

| Action | File | What changes |
|--------|------|-------------|
| Modify | `WRKT.xcodeproj/project.pbxproj` | 2 occurrences of `"WRKT Watch"` → `Volia`; 2 health usage strings |
| Create | `WRKT Watch Watch App/Views/WatchIdleView.swift` | Branded idle screen |
| Modify | `WRKT Watch Watch App/Views/SimpleTimerView.swift` | Replace `startButton` with `WatchIdleView()` |

---

## Task 1: Rename the Watch app

**Files:**
- Modify: `WRKT.xcodeproj/project.pbxproj` lines 2737 and 2777

- [ ] **Step 1: Edit pbxproj — Debug config (line 2737)**

Find and replace:
```
INFOPLIST_KEY_CFBundleDisplayName = "WRKT Watch";
```
With:
```
INFOPLIST_KEY_CFBundleDisplayName = Volia;
```
(Debug build configuration block, around line 2737)

- [ ] **Step 2: Edit pbxproj — Release config (line 2777)**

Same replacement in the Release block (around line 2777).

- [ ] **Step 3: Update the health usage description strings**

In the same two blocks, update:
```
INFOPLIST_KEY_NSHealthShareUsageDescription = "WRKT uses your health data to display heart rate and calories during workouts.";
```
To:
```
INFOPLIST_KEY_NSHealthShareUsageDescription = "Volia uses your health data to display heart rate and calories during workouts.";
```

- [ ] **Step 4: Verify**

Open Xcode, select the Watch target → General tab → Display Name should now show `Volia`.

Or grep to confirm no stray "WRKT Watch" remains:
```bash
grep -n "WRKT Watch" WRKT.xcodeproj/project.pbxproj
```
Expected: no output.

- [ ] **Step 5: Commit**
```bash
git add WRKT.xcodeproj/project.pbxproj
git commit -m "Rename Watch app display name from WRKT Watch to Volia"
```

---

## Task 2: Create WatchIdleView

**Files:**
- Create: `WRKT Watch Watch App/Views/WatchIdleView.swift`

This view is shown when the Watch is open but no workout or rest timer is active. It tells the user the app is ready and workouts are started from the iPhone.

- [ ] **Step 1: Create the file**

`WRKT Watch Watch App/Views/WatchIdleView.swift`:

```swift
// WatchIdleView.swift
// Shown when no workout or rest timer is active.

import SwiftUI

struct WatchIdleView: View {
    private let accent = Color(hex: "#CCFF00")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("VOLIA")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                    .tracking(3)

                Text("Workouts on iPhone")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Build the Watch target in Xcode (Cmd+B). No errors expected — the view uses only SwiftUI primitives and the existing `Color(hex:)` extension already in `ColorExtensions.swift`.

- [ ] **Step 3: Commit**
```bash
git add "WRKT Watch Watch App/Views/WatchIdleView.swift"
git commit -m "Add WatchIdleView branded idle screen for Watch"
```

---

## Task 3: Wire WatchIdleView into SimpleTimerView

**Files:**
- Modify: `WRKT Watch Watch App/Views/SimpleTimerView.swift`

Replace the `startButton` computed property (lines 120-143) with a call to `WatchIdleView()`. The timer display and all haptic/tick logic above it are untouched.

- [ ] **Step 1: Replace `startButton`**

Remove the entire `startButton` private var:
```swift
private var startButton: some View {
    VStack(spacing: 12) {
        Button {
            WKInterfaceDevice.current().play(.start)
            // Request default timer start (90 seconds)
            connectivity.send(type: .startRestTimer, payload: ["durationSeconds": 90])
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 40))
                    .foregroundColor(accentGreen)

                Text("Start Rest")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)

        Text("No active timer")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.4))
    }
}
```

Replace with:
```swift
private var idleView: some View {
    WatchIdleView()
}
```

- [ ] **Step 2: Update the body reference**

In `body`, the `else` branch currently reads `startButton`. Change it to `idleView`:

```swift
// Before:
} else {
    startButton
}

// After:
} else {
    idleView
}
```

- [ ] **Step 3: Remove unused `accentGreen` if only used by `startButton`**

Check if `accentGreen` is used anywhere else in `SimpleTimerView`. If the only remaining use is in `timerDisplay`, keep it. If it was only used by `startButton`, remove it (it's now defined inside `WatchIdleView`).

- [ ] **Step 4: Build and run on Watch simulator**

Run the Watch scheme on a simulator. With no active workout:
- Should show "VOLIA" + "Workouts on iPhone"
- No broken "Start Rest" button

Trigger a rest timer from the iPhone (or mock `connectivity.workoutState.restTimer` in a Preview) to confirm the countdown still displays correctly.

- [ ] **Step 5: Commit**
```bash
git add "WRKT Watch Watch App/Views/SimpleTimerView.swift"
git commit -m "Replace broken Start Rest idle screen with WatchIdleView"
```

---

## Testing Checklist

Before shipping:
- [ ] Watch app shows as "Volia" in the Watch app list on iPhone (Settings > General > Watch app)
- [ ] On Watch: idle state shows "VOLIA" branding, no tappable broken button
- [ ] On Watch: starting a strength workout from iPhone and triggering a rest timer still shows the countdown + skip/pause controls correctly
- [ ] On Watch: virtual run still routes to `VirtualRunView` correctly (RootView logic unchanged)
- [ ] On Watch: `ActiveWorkoutView` still shows during Watch-initiated workouts (RootView logic unchanged)
