# 🎯 COMPREHENSIVE IMPLEMENTATION PLAN: UNIFIED ACTIVITY STREAKS

---

## 📋 EXECUTIVE SUMMARY

**Recommended Approach:** **Unified Single Streak** tracking all workout types (strength + cardio)

**Why?** This aligns with industry best practices (Apple Fitness, Strava, Peloton) and better supports your goal: **push people to work out and reward consistency, regardless of type**.

---

## 🎨 UX DESIGN DECISIONS

### 1. **One Unified Streak** ✅
**Rationale:**
- **Simpler mental model** - Users track ONE number, not multiple
- **Encourages variety** - Cross-training counts toward same goal
- **Industry standard** - Apple Fitness Close Your Rings, Strava, Peloton all use unified streaks
- **Motivational** - "I worked out today" vs "I did strength today but lost my cardio streak"

**User Story:**
> "As a user, whether I lift weights, go for a run, or ride my bike, I'm staying active and my streak should continue."

### 2. **Win Screen Timing for HealthKit Workouts** ✅

**Option A: On App Open** (Recommended)
- Check for new HealthKit activities since last app session
- Show win screen immediately if streak extended/milestone hit
- Use app lifecycle `onAppear` in `AppShellView`

**Option B: On Calendar View** (Alternative)
- Show win screen when user navigates to calendar/home
- More contextual but might be missed if user doesn't visit

**Recommendation:** **Option A** - Ensures users never miss their celebration

### 3. **Calendar Visualization** ✅

**Current State:**
- Yellow dot = strength workout
- White dot = cardio run
- Yellow border = in active streak

**Proposed Enhancement:**
```
✓ Keep dual indicators (different workout types visible at a glance)
✓ Unified streak border (yellow) applies to BOTH types
✓ Flame icon on "today" if streak is active
✓ Day detail shows both workout types with clear separation
```

**Visual Hierarchy:**
```
┌─────────────────────┐
│  December 2024      │
├─────────────────────┤
│ Mo Tu We Th Fr Sa Su│
│                   🔥1│  ← Today with streak
│  2  3  4  5  6  7  8│
│  ●  ●  ○  ●  ●  ○  ●│  ← Yellow=strength, White=cardio
│  └──┬──┘           │
│     └─ Streak border │
└─────────────────────┘
```

### 4. **Activity Types Counting Toward Streaks** ✅

**From HealthKit:**
- Running 🏃
- Cycling 🚴
- Swimming 🏊
- Walking (if > 30min or > 3km)
- HIIT workouts
- Yoga (from Apple Fitness+)
- Other cardio workouts

**From In-App:**
- Completed strength workouts
- Logged individual sets (debatable - see below)

**Edge Case:** Should logging 1 set count as "activity"?
- **Current:** Yes (via `set_logged` event)
- **Recommendation:** Require minimum threshold (e.g., 3 sets or 10 minutes) to count as daily activity
- **Rationale:** Prevents gaming the system, maintains integrity

---

## 🏗️ TECHNICAL IMPLEMENTATION

### **Phase 1: Data Model & Storage** (Foundation)

#### 1.1 Update `RewardProgress` Model
**File:** `Features/Rewards/Views/RewardProgress.swift`

```swift
@Model final class RewardProgress {
    // ... existing fields ...

    // NEW: Track activity types contributing to streak
    var lastActivityType: String? = nil  // "strength", "cardio", "both"

    // NEW: For analytics/badges
    var totalStrengthDays: Int = 0
    var totalCardioDays: Int = 0
    var consecutiveMixedDays: Int = 0  // Both in same day
}
```

#### 1.2 Update `WorkoutStorageContainer`
**File:** `Core/Persistence/WorkoutStorage.swift`

```swift
struct WorkoutStorageContainer: Codable {
    var metadata: StorageMetadata
    var workouts: [CompletedWorkout]
    var prIndex: [String: ExercisePRsV2]

    // NEW: Track last processed HealthKit sync for win screen detection
    var lastHealthKitProcessedDate: Date?
}
```

---

### **Phase 2: Reward Engine Updates** (Core Logic)

#### 2.1 Add Cardio Activity Events
**File:** `Features/Rewards/Services/RewardEngine.swift:186`

```swift
func countsAsActivity(event: String) -> Bool {
    switch event {
    case "workout_completed", "set_logged", "warmup_completed",
         "mobility_completed", "pr_achieved",
         "cardio_completed":  // NEW EVENT
        return true
    default:
        return false
    }
}
```

#### 2.2 XP Rules for Cardio
**File:** `Features/Rewards/Models/StreakResult.swift:75-106`

Add to XP calculation switch:
```swift
case "cardio_completed":
    let duration = metadata["durationMinutes"] as? Int ?? 0
    let distance = metadata["distanceKm"] as? Double ?? 0

    // Base XP
    xpEarned += 15
    items.append(XPLineItem(label: "Cardio workout completed", xp: 15))

    // Duration bonuses
    if duration >= 30 {
        xpEarned += 10
        items.append(XPLineItem(label: "30+ min cardio", xp: 10))
    }
    if duration >= 60 {
        xpEarned += 15
        items.append(XPLineItem(label: "60+ min cardio", xp: 15))
    }

    // Distance bonuses (for runs/cycling)
    if distance >= 5.0 {
        xpEarned += 10
        items.append(XPLineItem(label: "5K+ distance", xp: 10))
    }
    if distance >= 10.0 {
        xpEarned += 20
        items.append(XPLineItem(label: "10K+ distance", xp: 20))
    }
```

#### 2.3 Enhanced Activity Type Tracking
**File:** `Features/Rewards/Models/StreakResult.swift:208`

Update `updateStreaks()` to track activity types:
```swift
func updateStreaks(
    progress: RewardProgress,
    activityDate: Date,
    activityType: String  // NEW: "strength" or "cardio"
) -> Int {
    // ... existing streak logic ...

    // NEW: Track activity type
    let todayStart = cal.startOfDay(for: activityDate)
    if let lastActivity = progress.lastActivityAt,
       cal.isDate(lastActivity, inSameDayAs: todayStart) {
        // Same day - check if mixed
        if progress.lastActivityType != activityType {
            progress.lastActivityType = "both"
            progress.consecutiveMixedDays += 1
        }
    } else {
        progress.lastActivityType = activityType
    }

    // Increment counters
    if activityType == "strength" {
        progress.totalStrengthDays += 1
    } else {
        progress.totalCardioDays += 1
    }

    // ... rest of existing logic ...
}
```

---

### **Phase 3: HealthKit Integration** (Cardio Detection)

#### 3.1 Process New Cardio Workouts
**File:** `Features/Health/Services/HealthKitManager.swift:584`

Modify `importWorkoutIdempotent()`:
```swift
func importWorkoutIdempotent(_ workout: HKWorkout, context: ModelContext) {
    // ... existing import logic ...

    // NEW: Check if this should trigger reward processing
    if shouldCountAsActivity(workout) {
        Task { @MainActor in
            await processNewCardioActivity(workout)
        }
    }
}

private func shouldCountAsActivity(_ workout: HKWorkout) -> Bool {
    // Define minimum thresholds
    let durationMinutes = workout.duration / 60.0
    let distanceKm = (workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo))) ?? 0

    switch workout.workoutActivityType {
    case .running, .cycling, .swimming, .hiking:
        return durationMinutes >= 10 || distanceKm >= 1.0

    case .walking:
        return durationMinutes >= 30 || distanceKm >= 3.0

    case .yoga, .functionalStrengthTraining, .coreTraining,
         .flexibility, .highIntensityIntervalTraining:
        return durationMinutes >= 15

    case .traditionalStrengthTraining:
        // Don't double-count if tracked in app
        return false

    default:
        return durationMinutes >= 20
    }
}
```

#### 3.2 New Activity Processing
**File:** `Features/Health/Services/HealthKitManager.swift` (new function)

```swift
@MainActor
private func processNewCardioActivity(_ workout: HKWorkout) async {
    // Check if already processed
    let workoutDate = workout.startDate
    let storage = WorkoutStorage.shared

    guard let lastProcessed = storage.lastHealthKitProcessedDate,
          workoutDate > lastProcessed else {
        return  // Already processed
    }

    // Trigger reward event
    let metadata: [String: Any] = [
        "durationMinutes": Int(workout.duration / 60.0),
        "distanceKm": (workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo))) ?? 0,
        "workoutType": workout.workoutActivityType.name,
        "calories": workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
    ]

    await RewardEngine.shared.process(
        event: "cardio_completed",
        activityDate: workoutDate,
        metadata: metadata
    )

    // Update last processed timestamp
    storage.lastHealthKitProcessedDate = Date()
}
```

---

### **Phase 4: Win Screen on App Launch** (User Experience)

#### 4.1 App Launch Check
**File:** `App/AppShellView.swift` (modify existing)

```swift
struct AppShellView: View {
    @State private var pendingRewardSummary: RewardSummary?
    @State private var showWinScreen: Bool = false

    var body: some View {
        // ... existing layout ...
        .task {
            // NEW: Check for cardio activities on app launch
            await checkForNewHealthKitActivities()
        }
        .sheet(isPresented: $showWinScreen) {
            if let summary = pendingRewardSummary {
                WinScreen(summary: summary)
            }
        }
    }

    @MainActor
    private func checkForNewHealthKitActivities() async {
        // Only check if HealthKit is connected
        guard HealthKitManager.shared.connectionState == .connected else { return }

        // Sync incrementally
        await HealthKitManager.shared.syncWorkoutsIncremental()

        // Check if any summaries were generated
        // (RewardEngine will post notifications automatically)
    }
}
```

#### 4.2 Coordinate Win Screen Display
**File:** `Features/Rewards/Services/WinScreenCoordinator.swift` (enhance existing)

Add state to track app launch summaries:
```swift
final class WinScreenCoordinator: ObservableObject {
    @Published var pendingSummaryForAppLaunch: RewardSummary?

    private func handleRewardSummary(_ summary: RewardSummary) {
        // ... existing batching logic ...

        // NEW: If this came from background HealthKit sync, queue for app launch
        if summary.xpLineItems.contains(where: { $0.label.contains("Cardio") }) {
            pendingSummaryForAppLaunch = mergedSummary
        }
    }
}
```

---

### **Phase 5: Calendar Enhancements** (Visual Polish)

#### 5.1 Update Streak Border Logic
**File:** `Features/Planner/CalendarMonthView.swift:92`

```swift
private func isInActiveStreak(_ d: Date) -> Bool {
    guard streakLength > 0 else { return false }
    let today = cal.startOfDay(for: .now)
    guard let windowStart = cal.date(byAdding: .day, value: -(streakLength - 1), to: today)
    else { return false }
    let startOfD = cal.startOfDay(for: d)
    let inWindow = (startOfD >= windowStart) && (startOfD <= today)

    // UPDATED: Check for ANY activity type
    return inWindow && hasAnyActivity(on: d)
}

private func hasAnyActivity(on date: Date) -> Bool {
    let workouts = store.workouts(on: date)
    let runs = store.runs(on: date)

    // Check if workouts meet minimum threshold
    let hasSubstantialWorkout = workouts.contains { workout in
        let setCount = workout.entries.flatMap { $0.sets }.filter { $0.isCompleted }.count
        return setCount >= 3  // Minimum threshold
    }

    // Check if runs meet minimum threshold
    let hasSubstantialRun = runs.contains { run in
        (run.durationSec >= 600) ||  // 10+ minutes
        (run.distanceKm >= 1.0)       // 1+ km
    }

    return hasSubstantialWorkout || hasSubstantialRun
}
```

#### 5.2 Enhanced Day Detail
**File:** `Features/Planner/CalendarMonthView.swift:695`

Update runs section to show streak contribution:
```swift
// Runs Section
ForEach(runs) { run in
    HStack {
        Image(systemName: run.workoutType == "Cycling" ? "bicycle" : "figure.run")
            .foregroundStyle(.white)

        VStack(alignment: .leading, spacing: 2) {
            Text(run.workoutName ?? run.workoutType ?? "Run")
                .font(.subheadline)

            HStack(spacing: 12) {
                Text("\(run.distanceKm, specifier: "%.2f") km")
                Text(formatDuration(run.durationSec))

                // NEW: Streak indicator
                if contributedToStreak(run) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
    }
}

private func contributedToStreak(_ run: Run) -> Bool {
    // Check if this run helped maintain streak on its date
    let runDate = Calendar.current.startOfDay(for: run.date)
    let workoutsOnSameDay = store.workouts(on: run.date)

    // If there were already workouts, run didn't contribute
    guard workoutsOnSameDay.isEmpty else { return false }

    // Check minimum thresholds
    return (run.durationSec >= 600) || (run.distanceKm >= 1.0)
}
```

---

## 📊 ACHIEVEMENT OPPORTUNITIES (Bonus Features)

### New Badge Ideas
**File:** `Features/Rewards/Models/RewardsRules.swift`

```swift
// Cross-training badges
"tri_threat": Achievement(
    name: "Tri Threat",
    desc: "Strength, cardio, and yoga in one week",
    xp: 100
)

"cardio_king": Achievement(
    name: "Cardio King",
    desc: "10 cardio workouts in 30 days",
    xp: 150
)

"balanced_warrior": Achievement(
    name: "Balanced Warrior",
    desc: "Equal strength and cardio days this month",
    xp: 200
)

"ultra_endurance": Achievement(
    name: "Ultra Endurance",
    desc: "Complete a 2+ hour cardio session",
    xp: 300
)
```

---

## 🚀 IMPLEMENTATION PHASES

### **Week 1: Foundation** ✅
- [ ] Update `RewardProgress` model with activity type tracking
- [ ] Add `lastHealthKitProcessedDate` to storage
- [ ] Write migration code for existing users
- [ ] Add "cardio_completed" event type
- [ ] Define XP rules for cardio activities

### **Week 2: Core Logic** ✅
- [ ] Update `updateStreaks()` to accept activity type
- [ ] Implement `shouldCountAsActivity()` in HealthKitManager
- [ ] Add `processNewCardioActivity()` function
- [ ] Update `countsAsActivity()` in RewardEngine
- [ ] Write unit tests for streak calculation

### **Week 3: Win Screen Integration** ✅
- [ ] Add app launch check in AppShellView
- [ ] Update WinScreenCoordinator for background summaries
- [ ] Test win screen display timing
- [ ] Add haptic feedback for cardio celebrations
- [ ] Polish animations

### **Week 4: Calendar & Polish** ✅
- [ ] Update calendar streak border logic
- [ ] Add streak contribution indicators
- [ ] Enhance day detail with activity types
- [ ] Add minimum threshold enforcement
- [ ] Update existing tests

### **Week 5: Testing & Refinement** ✅
- [ ] End-to-end testing (complete cardio → see win screen)
- [ ] Test edge cases (midnight boundaries, same-day activities)
- [ ] Performance testing (large HealthKit libraries)
- [ ] Beta testing with real users
- [ ] Bug fixes and polish

---

## 🧪 TESTING CHECKLIST

### Unit Tests
- [ ] Streak calculation with mixed activity types
- [ ] Minimum threshold enforcement
- [ ] XP calculation for cardio events
- [ ] Activity type tracking (strength, cardio, both)
- [ ] Streak freeze with cardio workouts

### Integration Tests
- [ ] HealthKit import → Reward event → Win screen
- [ ] Multiple cardio workouts in one day
- [ ] Cardio + strength on same day
- [ ] App launch detection of new activities
- [ ] Calendar visualization with mixed activities

### Edge Cases
- [ ] Workout at 11:59 PM (day boundary)
- [ ] Cardio before app opens (background sync)
- [ ] Duplicate HealthKit entries
- [ ] Very long cardio sessions (> 4 hours)
- [ ] Multiple apps writing to HealthKit

---

## 🔒 MIGRATION STRATEGY

### Existing Users
```swift
// In WorkoutStorage migration
func migrateToUnifiedStreaks() {
    // Existing streak data is preserved
    // No need to recalculate - just extend going forward

    // Initialize new fields
    if progress.lastActivityType == nil {
        progress.lastActivityType = "strength"  // Assume existing streaks are strength-based
        progress.totalStrengthDays = progress.currentStreak
        progress.totalCardioDays = 0
    }
}
```

### Communication
**In-app message on first launch after update:**
```
🎉 Streaks Just Got Better!

Your workouts AND cardio activities now count
toward your streak. Keep moving every day! 🔥

[Got it]
```

---

## 📈 ANALYTICS TO TRACK

Post-launch metrics to measure success:
- **Streak retention rate** (before vs after)
- **Average streak length** (before vs after)
- **% users with mixed activity days**
- **Cardio workout frequency**
- **Win screen views from app launch** (engagement metric)
- **Achievement unlock rate** (new cross-training badges)

---

## ⚠️ POTENTIAL PITFALLS & MITIGATIONS

### 1. **Battery Drain from Frequent HealthKit Syncs**
**Solution:** Keep existing 5-minute throttle, only check on app launch

### 2. **Duplicate Win Screens** (cardio + strength same day)
**Solution:** WinScreenCoordinator's existing 400ms batching handles this

### 3. **Gaming the System** (log 1 set to maintain streak)
**Solution:** Implement minimum thresholds (3 sets or 10 minutes)

### 4. **HealthKit Authorization Denied**
**Solution:** Show helpful onboarding, graceful degradation (strength-only streaks)

### 5. **Imported Historical Data**
**Solution:** Only process workouts after install date to avoid retroactive rewards

---

## 🎯 SUCCESS CRITERIA

This implementation succeeds when:
1. ✅ **Users maintain longer streaks** (cardio on rest days counts)
2. ✅ **Cross-training increases** (analytics show mixed activity days)
3. ✅ **Win screens feel natural** (no spam, proper timing)
4. ✅ **Calendar is clear** (users understand which days count)
5. ✅ **No performance regression** (battery, sync speed)
6. ✅ **Zero crashes** from HealthKit integration

---

## 💡 ALTERNATIVE APPROACHES (Considered & Rejected)

### ❌ Separate Streaks (Strength vs Cardio)
**Why Rejected:** Adds complexity, splits user focus, doesn't encourage variety

### ❌ Cardio-Only Win Screens
**Why Rejected:** Creates two-tier system, makes cardio feel less important

### ❌ Manual Cardio Logging
**Why Rejected:** Friction! Users already track in other apps, why duplicate effort?

---

## 🎨 FUTURE ENHANCEMENTS

Post-MVP ideas:
- **Streak insights** - "Your streak includes 15 strength + 10 cardio days"
- **Activity heatmap** - Calendar colored by workout type intensity
- **Smart rest day detection** - Yoga/stretching counts but doesn't affect main streak
- **Social streaks** - Compare with friends (Game Center integration)
- **Streak insurance** - Earn freeze tokens through achievements

---

## 📚 REFERENCES & INSPIRATION

**Apps with unified activity streaks:**
- Apple Fitness (Close Your Rings - Move, Exercise, Stand)
- Strava (Days Active)
- Peloton (Weekly Streak)
- MyFitnessPal (Logging Streak)

**Key UX Principle:**
> "The best streak system is one the user doesn't have to think about. If they moved their body with intent, they maintained their streak."

---

## ✅ RECOMMENDED NEXT STEPS

1. **Review this plan** with your team/stakeholders
2. **Create GitHub issues** for each phase
3. **Set up feature flag** for gradual rollout
4. **Design win screen variations** for cardio (cycling/running specific imagery?)
5. **Write ADR** (Architecture Decision Record) documenting the "unified streak" choice
6. **Start with Phase 1** (data model updates)

---

## 📝 NOTES

This plan is designed to be:
- **Efficient** - Reuses existing architecture patterns
- **Scalable** - Handles any workout type HealthKit can track
- **Modern** - Follows 2024 fitness app UX best practices
- **User-focused** - Reduces friction, increases motivation
- **Developer-friendly** - Clear phases, testable components, graceful degradation
