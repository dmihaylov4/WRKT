# Live Activities Implementation Plan for WRKT

## 🎯 Goals
1. Replace unreliable notifications with Live Activities
2. Show rest timer on lock screen & Dynamic Island
3. Add interactive controls (pause, skip, adjust time)
4. Display live workout stats during sessions
5. Auto-start/stop rest timers
6. Auto-generate next set when timer completes

---

## 📋 Architecture Overview

### Components Needed

1. **ActivityAttributes** (Data Model)
   - Defines static and dynamic data for Live Activity
   - Separate models for RestTimer and LiveWorkout

2. **Widget Extension** (UI)
   - Lock screen view
   - Dynamic Island compact view
   - Dynamic Island expanded view
   - Notification view (when dismissed from Dynamic Island)

3. **Activity Manager** (Business Logic)
   - Start/update/stop Live Activities
   - Handle button interactions
   - Sync with RestTimerManager

4. **Integration Points**
   - Hook into RestTimerManager
   - Hook into WorkoutStoreV2
   - Background update handling

---

## 🏗️ Implementation Steps

### Phase 1: Setup (30 min)

#### 1.1 Create Widget Extension Target
```bash
File > New > Target > Widget Extension
Name: WRKTWidgetExtension
Include Live Activity: ✅ Yes
```

#### 1.2 Configure Capabilities
- Add "Push Notifications" to main app
- Add "App Groups" for data sharing between app and widget
  - App Group ID: `group.com.dmihaylov.trak.shared`

#### 1.3 Update Info.plist
```xml
<!-- Main app Info.plist -->
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

---

### Phase 2: Live Activity for Rest Timer (2 hours)

#### 2.1 Create RestTimerActivityAttributes.swift
```swift
import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic data (updates frequently)
        var remainingSeconds: Int
        var endDate: Date
        var isPaused: Bool
        var progress: Double  // 0.0 to 1.0
        var wasAdjusted: Bool
    }

    // Static data (doesn't change during activity)
    var exerciseName: String
    var originalDuration: Int
    var exerciseID: String
}
```

#### 2.2 Create RestTimerLiveActivity.swift (Widget UI)
```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen View
            RestTimerLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    ExerciseNameView(context.attributes.exerciseName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerDisplay(context.state.remainingSeconds)
                }
                DynamicIslandExpandedRegion(.center) {
                    ProgressBar(progress: context.state.progress)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ControlButtons(context: context)
                }
            } compactLeading: {
                // Compact left side (when minimized in Dynamic Island)
                Image(systemName: "timer")
                    .foregroundColor(.yellow)
            } compactTrailing: {
                // Compact right side
                Text(timeString(context.state.remainingSeconds))
                    .font(.system(.caption, design: .rounded).monospacedDigit())
            } minimal: {
                // Most compact (when multiple activities)
                Image(systemName: "timer")
                    .foregroundColor(.yellow)
            }
        }
    }
}
```

#### 2.3 Create LiveActivityManager.swift
```swift
import ActivityKit
import Foundation

@MainActor
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var currentRestTimerActivity: Activity<RestTimerAttributes>?
    private var updateTimer: Timer?

    // MARK: - Rest Timer Activity

    func startRestTimerActivity(
        exerciseName: String,
        exerciseID: String,
        duration: TimeInterval,
        endDate: Date
    ) {
        // End any existing activity
        endRestTimerActivity()

        let attributes = RestTimerAttributes(
            exerciseName: exerciseName,
            originalDuration: Int(duration),
            exerciseID: exerciseID
        )

        let contentState = RestTimerAttributes.ContentState(
            remainingSeconds: Int(duration),
            endDate: endDate,
            isPaused: false,
            progress: 1.0,
            wasAdjusted: false
        )

        do {
            let activity = try Activity<RestTimerAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )

            currentRestTimerActivity = activity
            startUpdateLoop()

            AppLogger.success("Live Activity started for \(exerciseName)", category: AppLogger.app)
        } catch {
            AppLogger.error("Failed to start Live Activity: \(error)", category: AppLogger.app)
        }
    }

    func updateRestTimer(remainingSeconds: Int, isPaused: Bool, wasAdjusted: Bool) {
        guard let activity = currentRestTimerActivity else { return }

        let totalDuration = Double(activity.attributes.originalDuration)
        let progress = totalDuration > 0 ? (Double(remainingSeconds) / totalDuration) : 0

        let contentState = RestTimerAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            endDate: Date().addingTimeInterval(Double(remainingSeconds)),
            isPaused: isPaused,
            progress: progress,
            wasAdjusted: wasAdjusted
        )

        Task {
            await activity.update(using: contentState)
        }
    }

    func endRestTimerActivity(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        stopUpdateLoop()

        guard let activity = currentRestTimerActivity else { return }

        Task {
            await activity.end(using: nil, dismissalPolicy: dismissalPolicy)
        }

        currentRestTimerActivity = nil
    }

    // MARK: - Auto-update Loop

    private func startUpdateLoop() {
        stopUpdateLoop()

        // Update every second while timer is running
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let activity = self.currentRestTimerActivity else { return }

            let remaining = max(0, Int(activity.contentState.endDate.timeIntervalSinceNow))

            if remaining <= 0 {
                // Timer completed
                self.endRestTimerActivity(dismissalPolicy: .immediate)
            } else if !activity.contentState.isPaused {
                // Update countdown
                self.updateRestTimer(
                    remainingSeconds: remaining,
                    isPaused: false,
                    wasAdjusted: activity.contentState.wasAdjusted
                )
            }
        }
    }

    private func stopUpdateLoop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}
```

#### 2.4 Integrate with RestTimerManager
```swift
// In RestTimerManager.swift

func startTimer(duration: TimeInterval, exerciseID: String, exerciseName: String) {
    // ... existing code ...

    // Start Live Activity
    Task { @MainActor in
        LiveActivityManager.shared.startRestTimerActivity(
            exerciseName: exerciseName,
            exerciseID: exerciseID,
            duration: duration,
            endDate: endDate
        )
    }
}

func stopTimer() {
    // ... existing code ...

    // End Live Activity
    Task { @MainActor in
        LiveActivityManager.shared.endRestTimerActivity()
    }
}

func pauseTimer() {
    // ... existing code ...

    // Update Live Activity
    Task { @MainActor in
        LiveActivityManager.shared.updateRestTimer(
            remainingSeconds: Int(remainingSeconds),
            isPaused: true,
            wasAdjusted: hasBeenAdjusted
        )
    }
}

func resumeTimer() {
    // ... existing code ...

    // Update Live Activity
    Task { @MainActor in
        LiveActivityManager.shared.updateRestTimer(
            remainingSeconds: Int(remaining),
            isPaused: false,
            wasAdjusted: hasBeenAdjusted
        )
    }
}
```

---

### Phase 3: Live Activity for Active Workout (2 hours)

#### 3.1 Create WorkoutActivityAttributes.swift
```swift
struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentExercise: String
        var currentSet: Int
        var totalSets: Int
        var exercisesCompleted: Int
        var totalExercises: Int
        var elapsedTime: Int  // seconds
        var isResting: Bool
        var restRemaining: Int?
    }

    var workoutName: String?
    var startTime: Date
}
```

#### 3.2 Features
- Show current exercise name
- Display set progress (3/4)
- Show elapsed workout time
- Exercise completion (5/8 exercises)
- Quick actions: "Finish Workout", "Rest Timer"
- Dynamic Island shows current exercise

---

### Phase 4: Interactive Controls (1 hour)

#### 4.1 App Intent for Button Actions
```swift
import AppIntents

struct AdjustRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Rest Timer"

    @Parameter(title: "Seconds to Add")
    var seconds: Int

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            RestTimerManager.shared.adjustTime(by: TimeInterval(seconds))
        }
        return .result()
    }
}

struct PauseRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Rest Timer"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            RestTimerManager.shared.pauseTimer()
        }
        return .result()
    }
}

struct SkipRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Rest"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            RestTimerManager.shared.skipTimer()
        }
        return .result()
    }
}
```

#### 4.2 Add Buttons to Lock Screen View
```swift
struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // Exercise name
            Text(context.attributes.exerciseName)
                .font(.headline)

            // Timer display
            HStack {
                Image(systemName: "timer")
                Text(timeString(context.state.remainingSeconds))
                    .font(.system(.title, design: .rounded).monospacedDigit())
            }

            // Progress bar
            ProgressView(value: context.state.progress)
                .tint(.yellow)

            // Control buttons
            HStack(spacing: 16) {
                Button(intent: AdjustRestTimerIntent(seconds: -15)) {
                    Label("-15s", systemImage: "minus.circle")
                }

                Button(intent: context.state.isPaused ? ResumeRestTimerIntent() : PauseRestTimerIntent()) {
                    Label(
                        context.state.isPaused ? "Resume" : "Pause",
                        systemImage: context.state.isPaused ? "play.circle" : "pause.circle"
                    )
                }

                Button(intent: AdjustRestTimerIntent(seconds: 15)) {
                    Label("+15s", systemImage: "plus.circle")
                }

                Button(intent: SkipRestTimerIntent(), role: .destructive) {
                    Label("Skip", systemImage: "forward.circle")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }
}
```

---

### Phase 5: Automatic Features (1.5 hours)

#### 5.1 Auto-Start Rest Timer After Set
```swift
// In ExerciseSessionView or wherever sets are completed

func completeSet() {
    // ... mark set as complete ...

    // Auto-start rest timer if enabled
    if RestTimerPreferences.shared.isEnabled {
        let duration = RestTimerPreferences.shared.restDuration(for: exercise)
        RestTimerManager.shared.startTimer(
            duration: duration,
            exerciseID: exercise.id,
            exerciseName: exercise.name
        )
    }
}
```

#### 5.2 Auto-Generate Next Set on Timer Completion
```swift
// Already implemented in your RestTimerManager.completeTimer()
// Just ensure it triggers set generation
```

#### 5.3 Smart Timer Management
- Don't start timer on last set of exercise
- Skip timer if user immediately starts next set
- Pause timer when app goes to background for >5 minutes
- Resume timer when app returns

---

## 🎨 Design Specifications

### Lock Screen View
```
┌─────────────────────────────────┐
│  🏋️ Bench Press                 │
│                                   │
│       ⏱️ 2:45                    │
│  ████████████░░░░░ 75%           │
│                                   │
│  [-15s] [⏸️ Pause] [+15s] [Skip]│
└─────────────────────────────────┘
```

### Dynamic Island Compact
```
⏱️ 2:45
```

### Dynamic Island Expanded
```
┌────────────────────────┐
│   Bench Press          │
│   ████████░░ 2:45      │
│   [-15] [⏸️] [+15] [❌]│
└────────────────────────┘
```

---

## 📱 Minimum iOS Version
- **Live Activities**: iOS 16.1+
- **Dynamic Island**: iPhone 14 Pro and later
- **Fallback**: Keep existing notifications for iOS 15 and earlier

---

## ⚠️ Important Considerations

### 1. Live Activity Limits
- Maximum 8 hours duration
- Updates should be < 1 per second (you're updating every 1s, which is fine)
- Max 50 push notification updates per day (you're using local updates, so unlimited)

### 2. Testing
- Live Activities only work on physical devices
- Won't work in Simulator (except for Xcode previews)

### 3. Permissions
- No special permission needed for Live Activities
- They're automatically enabled when app is installed

### 4. Battery Impact
- Minimal - Live Activities are very efficient
- Much better than keeping app open in background

---

## 🚀 Benefits Over Current System

| Feature | Current Notifications | Live Activities |
|---------|---------------------|-----------------|
| **Reliability** | ❌ Can be delayed/dropped | ✅ Always visible |
| **Visual Feedback** | ❌ Only when notification shows | ✅ Always on lock screen |
| **Interactive** | ❌ No | ✅ Buttons work on lock screen |
| **Real-time Updates** | ❌ No | ✅ Every second |
| **Dynamic Island** | ❌ No | ✅ Yes (iPhone 14 Pro+) |
| **Background Reliability** | ❌ 30 sec limit | ✅ Works for 8 hours |
| **User Experience** | 😐 OK | 🤩 Amazing |

---

## 📋 Implementation Checklist

### Setup
- [ ] Create Widget Extension target
- [ ] Configure App Groups
- [ ] Enable Live Activities in Info.plist
- [ ] Add necessary imports

### Rest Timer Live Activity
- [ ] Create RestTimerAttributes
- [ ] Create RestTimerLiveActivity widget
- [ ] Create lock screen view
- [ ] Create Dynamic Island views
- [ ] Implement LiveActivityManager
- [ ] Integrate with RestTimerManager
- [ ] Add interactive buttons (App Intents)
- [ ] Test on physical device

### Workout Live Activity (Optional Phase 2)
- [ ] Create WorkoutActivityAttributes
- [ ] Create WorkoutLiveActivity widget
- [ ] Show current exercise/set
- [ ] Show elapsed time
- [ ] Quick action buttons

### Automatic Features
- [ ] Auto-start timer after set completion
- [ ] Auto-generate next set on timer completion
- [ ] Smart pause/resume on background
- [ ] Skip timer on last set

### Polish
- [ ] Handle iOS version fallback
- [ ] Add loading states
- [ ] Error handling
- [ ] Haptic feedback
- [ ] Accessibility labels
- [ ] Dark mode support

---

## 🎯 Expected Timeline

- **Phase 1 (Setup)**: 30 min
- **Phase 2 (Rest Timer)**: 2 hours
- **Phase 3 (Workout Activity)**: 2 hours
- **Phase 4 (Interactive Controls)**: 1 hour
- **Phase 5 (Automatic Features)**: 1.5 hours
- **Testing & Polish**: 1 hour

**Total: ~8 hours of development**

---

## 📚 Resources

- [Apple: ActivityKit Documentation](https://developer.apple.com/documentation/activitykit)
- [WWDC22: Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2022/10184/)
- [Live Activities Tutorial](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [App Intents for Interactive Widgets](https://developer.apple.com/documentation/appintents)

---

**Status**: Ready for implementation
**Priority**: High - Will significantly improve user experience
**Complexity**: Medium - Straightforward with good documentation
**Impact**: 🌟🌟🌟🌟🌟 Very High
