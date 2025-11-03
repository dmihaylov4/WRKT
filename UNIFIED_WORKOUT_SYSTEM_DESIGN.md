# Unified Workout System Design
## Multi-Modal Exercise Tracking (Strength, Pilates, Yoga, Mobility)

**Version:** 1.0
**Date:** 2025-10-31
**Status:** Design Phase

---

## Design Philosophy: The Apple Way

### Core Principles

1. **Intelligent Adaptation** - The UI adapts to context, not the user to the UI
2. **Unified Experience** - One workout flow that handles all exercise types seamlessly
3. **Progressive Disclosure** - Show only what's relevant, hide complexity
4. **Consistency** - Same patterns, different content
5. **Zero Mode Switching** - No "switch to Pilates mode" or separate apps

### User Experience Goals

- ✅ Add Pilates exercises to strength workouts without friction
- ✅ UI automatically shows timer for holds, reps for calisthenics, weight for strength
- ✅ Unified workout session view that "just works"
- ✅ Stats and achievements work across all exercise types
- ✅ No learning curve - intuitive for existing users

---

## Data Architecture

### Single Unified Exercise Catalog

**Decision: Use ONE `exercises_clean.json` file**

**Rationale:**
- Unified search and filtering experience
- Easy to mix exercise types in one workout
- Single source of truth
- Better performance (one load operation)
- Simpler codebase maintenance

### Exercise Model Extension

```json
{
  "id": "pilates-hundred",
  "name": "Hundred",
  "category": "pilates",
  "trackingMode": "timed",
  "primaryMuscles": ["abs"],
  "secondaryMuscles": ["hip flexors"],
  "equipment": "mat",
  "mechanic": null,
  "instructions": "...",
  "youtubeId": "...",
  "defaultDurationSeconds": 100,
  "recommendedRestSeconds": 30
}
```

### New Fields (Backward Compatible)

```swift
// Add to Exercise model
category: String              // "strength", "pilates", "yoga", "mobility", "cardio"
trackingMode: String          // "weighted", "timed", "bodyweight", "distance"
defaultDurationSeconds: Int?  // For timed exercises (optional)
recommendedRestSeconds: Int?  // Context-aware rest timer
```

### SetInput Model Enhancement

```swift
struct SetInput: Codable {
    // Existing fields
    var reps: Int                 // Used for: weighted, bodyweight
    var weight: Double            // Used for: weighted only
    var tag: SetTag              // Used for: all types
    var isCompleted: Bool        // Used for: all types

    // New fields (optional, backward compatible)
    var durationSeconds: Int = 0  // Used for: timed exercises
    var trackingMode: TrackingMode = .weighted  // Determines which fields are active

    // Computed
    var displayValue: String {
        switch trackingMode {
        case .weighted:
            return "\(reps) × \(weight) kg"
        case .timed:
            return formatDuration(durationSeconds)
        case .bodyweight:
            return "\(reps) reps"
        }
    }
}

enum TrackingMode: String, Codable {
    case weighted      // reps + weight (current behavior)
    case timed         // duration only
    case bodyweight    // reps only (weight = 0)
}
```

---

## UI/UX Design System

### 1. Exercise Browser (Unified)

#### Filter Bar (Top)
```
┌──────────────────────────────────────────────────┐
│ 🔍 Search                               ⚙️ Filter │
└──────────────────────────────────────────────────┘

Filters (Horizontal Scroll):
[All] [Strength] [Pilates] [Yoga] [Mobility]
[Upper Body] [Lower Body] [Core] [Full Body]
[Barbell] [Dumbbell] [Bodyweight] [Mat]
```

#### Exercise List (Adaptive Metadata)

**Strength Exercise:**
```
┌─────────────────────────────────────────┐
│ 🏋️ Barbell Bench Press                  │
│ Chest • Compound • Barbell              │
│ ⚡️ 12 PRs • Last: 80kg × 8              │
└─────────────────────────────────────────┘
```

**Pilates Exercise:**
```
┌─────────────────────────────────────────┐
│ 🧘 Hundred                               │
│ Core • Pilates • Mat                    │
│ ⏱ Best: 2:15 • Last: 1:45               │
└─────────────────────────────────────────┘
```

**Bodyweight Exercise:**
```
┌─────────────────────────────────────────┐
│ 💪 Pull-ups                              │
│ Back • Bodyweight • Bar                 │
│ 🔥 Max: 15 reps • Last: 12 reps         │
└─────────────────────────────────────────┘
```

### 2. Set Input Interface (Adaptive)

#### Design Pattern: **Contextual Set Card**

The set input card morphs based on `trackingMode`:

##### A. Weighted Mode (Current)
```
┌────────────────────────────────────────────┐
│ Set 1 • Working                       [✓]  │
│                                            │
│  Reps              Weight                  │
│  ┌──────┐         ┌──────────┐            │
│  │   8  │         │  80  kg  │            │
│  └──────┘         └──────────┘            │
│                                            │
│  Suggested: 8 × 82.5 kg  [Use]            │
└────────────────────────────────────────────┘
```

##### B. Timed Mode (Pilates/Holds)
```
┌────────────────────────────────────────────┐
│ Set 1 • Working                       [✓]  │
│                                            │
│           ⏱ 01:45                          │
│        Duration                            │
│                                            │
│  [−15s]    [Start Timer]    [+15s]        │
│                                            │
│  Target: 01:00  Last: 01:30               │
└────────────────────────────────────────────┘
```

##### C. Bodyweight Mode
```
┌────────────────────────────────────────────┐
│ Set 1 • Working                       [✓]  │
│                                            │
│           Reps                             │
│         ┌──────┐                           │
│         │  12  │                           │
│         └──────┘                           │
│                                            │
│  PR: 15 reps  Last: 12 reps               │
└────────────────────────────────────────────┘
```

### 3. Live Workout View (Seamless Transitions)

```
┌──────────────────────────────────────────────────┐
│ LIVE WORKOUT                    [Finish] [...]   │
├──────────────────────────────────────────────────┤
│                                                  │
│ Current:                                         │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                  │
│ [Exercise-specific UI here - see above]         │
│                                                  │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                  │
│ Up Next:                                         │
│ • Pilates Roll-Up (Timed)                       │
│ • Overhead Press (Weighted)                     │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Key UX Detail:** When advancing from Bench Press (weighted) to Pilates Hundred (timed), the set input morphs smoothly with a subtle animation.

### 4. Rest Timer (Context-Aware)

```swift
// Automatically use appropriate rest time
let restDuration = switch exercise.trackingMode {
case .weighted where exercise.mechanic == "compound":
    RestTimerPreferences.shared.defaultCompoundSeconds
case .weighted:
    RestTimerPreferences.shared.defaultIsolationSeconds
case .timed, .bodyweight:
    exercise.recommendedRestSeconds ?? 30  // Shorter for Pilates/mobility
}
```

---

## Progress Tracking & Achievements

### Unified Dex System

**Unlock Criteria (Adaptive):**

```swift
func shouldUnlockDex(exercise: Exercise, set: SetInput) -> Bool {
    guard set.isCompleted && set.tag == .working else { return false }

    return switch exercise.trackingMode {
    case .weighted:
        set.reps > 0 && set.weight > 0
    case .timed:
        set.durationSeconds >= 30  // At least 30s hold
    case .bodyweight:
        set.reps > 0
    }
}
```

**Dex Display (Adaptive):**

```
Strength Exercise Dex Tile:
┌─────────────────┐
│  🏆             │
│                 │
│ Bench Press     │
│ PR: 100kg × 5   │
└─────────────────┘

Pilates Exercise Dex Tile:
┌─────────────────┐
│  🏆             │
│                 │
│ Hundred         │
│ Best: 2:15      │
└─────────────────┘
```

### Volume & Stats Tracking

```swift
// Unified stat calculation
extension CompletedWorkout {
    var totalVolume: WorkoutVolume {
        var weighted: Double = 0      // kg lifted
        var timeUnderTension: Int = 0 // seconds
        var totalReps: Int = 0        // bodyweight

        for entry in entries {
            let exercise = repo.exercise(byID: entry.exerciseID)

            for set in entry.sets where set.isCompleted {
                switch exercise?.trackingMode {
                case .weighted:
                    weighted += Double(set.reps) * set.weight
                case .timed:
                    timeUnderTension += set.durationSeconds
                case .bodyweight:
                    totalReps += set.reps
                default:
                    break
                }
            }
        }

        return WorkoutVolume(
            weightedKg: weighted,
            timeSeconds: timeUnderTension,
            reps: totalReps
        )
    }
}
```

### Achievement System (Multi-Type)

```swift
// Examples:
"ach.pilates.hundred.60s"    // Hold Hundred for 60 seconds
"ach.pilates.rollup.10reps"  // 10 consecutive Roll-ups
"ach.bodyweight.pullup.15"   // 15 pull-ups in one set
"ach.strength.bench.100kg"   // Bench press 100kg
```

---

## Implementation Phases

### Phase 1: Foundation (1-2 days)
- [ ] Extend `Exercise` model with new fields
- [ ] Add `trackingMode` and `durationSeconds` to `SetInput`
- [ ] Update JSON schema
- [ ] Add Pilates exercises to `exercises_clean.json`
- [ ] Ensure backward compatibility (migrations)

### Phase 2: UI Adaptation (2-3 days)
- [ ] Create `TimedSetView` component
- [ ] Create `BodyweightSetView` component
- [ ] Update `ExerciseSessionView` to switch between views
- [ ] Add duration picker UI
- [ ] Test transitions between exercise types

### Phase 3: Progress System (1-2 days)
- [ ] Update dex unlock logic for all types
- [ ] Add duration-based PRs to tracking
- [ ] Update stats aggregation
- [ ] Modify workout summary to show all metrics

### Phase 4: Exercise Browser (1 day)
- [ ] Add category filters
- [ ] Update exercise metadata display
- [ ] Show type-specific icons/badges

### Phase 5: Polish & Testing (1-2 days)
- [ ] Smooth transitions/animations
- [ ] Rest timer context awareness
- [ ] Edge case testing
- [ ] User testing with mixed workouts

**Total Estimate:** 7-10 days for complete implementation

---

## Technical Specifications

### Exercise JSON Schema Extension

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "id": { "type": "string" },
    "name": { "type": "string" },
    "category": {
      "type": "string",
      "enum": ["strength", "pilates", "yoga", "mobility", "cardio"]
    },
    "trackingMode": {
      "type": "string",
      "enum": ["weighted", "timed", "bodyweight", "distance"]
    },
    "primaryMuscles": { "type": "array" },
    "secondaryMuscles": { "type": "array" },
    "equipment": { "type": "string" },
    "mechanic": { "type": "string", "nullable": true },
    "instructions": { "type": "string" },
    "youtubeId": { "type": "string", "nullable": true },
    "defaultDurationSeconds": { "type": "integer", "nullable": true },
    "recommendedRestSeconds": { "type": "integer", "nullable": true }
  },
  "required": ["id", "name", "category", "trackingMode", "primaryMuscles"]
}
```

### Model Changes

**File:** `Core/Models/WorkoutEntry.swift`

```swift
// Add to SetInput
struct SetInput: Hashable, Codable {
    var reps: Int
    var weight: Double
    var tag: SetTag = .working
    var autoWeight: Bool = true
    var didSeedFromMemory: Bool = false
    var isCompleted: Bool = false
    var isGhost: Bool = false
    var isAutoGeneratedPlaceholder: Bool = false

    // NEW FIELDS
    var durationSeconds: Int = 0
    var trackingMode: TrackingMode = .weighted

    enum TrackingMode: String, Codable {
        case weighted
        case timed
        case bodyweight
    }
}
```

**File:** `Core/Models/ExerciseDefinition.swift`

```swift
struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String?
    let mechanic: String?
    let instructions: String?
    let youtubeId: String?

    // NEW FIELDS
    let category: String
    let trackingMode: String
    let defaultDurationSeconds: Int?
    let recommendedRestSeconds: Int?

    // Computed
    var isTimedExercise: Bool { trackingMode == "timed" }
    var isBodyweightExercise: Bool { trackingMode == "bodyweight" }
}
```

### Example Pilates Exercises (JSON)

```json
[
  {
    "id": "pilates-hundred",
    "name": "Hundred",
    "category": "pilates",
    "trackingMode": "timed",
    "primaryMuscles": ["abs"],
    "secondaryMuscles": ["hip flexors"],
    "equipment": "mat",
    "mechanic": null,
    "instructions": "Lie on your back, lift legs to tabletop, curl head and shoulders up. Pump arms vigorously for 100 counts while breathing (5 breaths in, 5 breaths out).",
    "youtubeId": "dQw4w9WgXcQ",
    "defaultDurationSeconds": 100,
    "recommendedRestSeconds": 30
  },
  {
    "id": "pilates-roll-up",
    "name": "Roll-Up",
    "category": "pilates",
    "trackingMode": "bodyweight",
    "primaryMuscles": ["abs"],
    "secondaryMuscles": ["hip flexors"],
    "equipment": "mat",
    "mechanic": "compound",
    "instructions": "Start lying flat, arms overhead. Roll up vertebra by vertebra reaching toward toes, then roll back down with control.",
    "youtubeId": "dQw4w9WgXcQ",
    "recommendedRestSeconds": 30
  },
  {
    "id": "pilates-single-leg-circle",
    "name": "Single Leg Circle",
    "category": "pilates",
    "trackingMode": "bodyweight",
    "primaryMuscles": ["hip flexors", "abs"],
    "secondaryMuscles": ["obliques"],
    "equipment": "mat",
    "mechanic": "isolation",
    "instructions": "Lie on back, one leg extended to ceiling. Draw circles with the leg, keeping hips stable. 5 circles each direction per leg.",
    "youtubeId": "dQw4w9WgXcQ",
    "recommendedRestSeconds": 20
  },
  {
    "id": "pilates-plank",
    "name": "Plank Hold",
    "category": "pilates",
    "trackingMode": "timed",
    "primaryMuscles": ["abs", "core"],
    "secondaryMuscles": ["shoulders", "glutes"],
    "equipment": "mat",
    "mechanic": "isometric",
    "instructions": "Hold plank position on forearms or hands, maintaining straight line from head to heels. Engage core throughout.",
    "youtubeId": "dQw4w9WgXcQ",
    "defaultDurationSeconds": 60,
    "recommendedRestSeconds": 30
  }
]
```

---

## User Flows

### Flow 1: Mixed Workout Session

```
User starts workout:
  "Push Day + Core"

Adds exercises:
  1. Barbell Bench Press (weighted)
  2. Overhead Press (weighted)
  3. Pilates Hundred (timed)
  4. Plank Hold (timed)

During workout:
  → Bench Press: Shows reps + weight input
  → Finishes, rest timer: 3:00
  → Overhead Press: Shows reps + weight input
  → Finishes, rest timer: 3:00
  → Hundred: UI smoothly transitions to timer
  → Starts 1:45 hold, rest timer: 0:30
  → Plank: Timer interface remains
  → Finishes workout

Summary shows:
  • 8,500 kg lifted
  • 3:45 time under tension
  • 4 exercises completed
  • 2 new dex entries unlocked
```

### Flow 2: Pure Pilates Session

```
User starts workout:
  "Pilates Core Flow"

All exercises are timed/bodyweight:
  → UI never shows weight fields
  → Rest timers are shorter (30s)
  → Stats show total time
  → Achievements: "60s plank streak!"
```

---

## Migration Strategy

### Backward Compatibility

**Old Data (before update):**
```json
{
  "reps": 10,
  "weight": 80,
  "tag": "working",
  "isCompleted": true
}
```

**After Update (automatic migration):**
```json
{
  "reps": 10,
  "weight": 80,
  "tag": "working",
  "isCompleted": true,
  "durationSeconds": 0,
  "trackingMode": "weighted"
}
```

**Migration Code:**
```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    reps = try container.decode(Int.self, forKey: .reps)
    weight = try container.decode(Double.self, forKey: .weight)
    // ...existing fields...

    // NEW: Default values for new fields
    durationSeconds = (try? container.decode(Int.self, forKey: .durationSeconds)) ?? 0
    trackingMode = (try? container.decode(TrackingMode.self, forKey: .trackingMode)) ?? .weighted
}
```

---

## Success Metrics

### User Experience
- [ ] Users can add Pilates exercises without tutorial
- [ ] Workout flow feels identical for all exercise types
- [ ] No reported confusion about "modes" or "types"
- [ ] Smooth transitions validated in user testing

### Technical
- [ ] Zero crashes from new exercise types
- [ ] <100ms UI adaptation time
- [ ] All existing workouts load correctly
- [ ] Stats aggregate properly for mixed workouts

### Adoption
- [ ] 20% of users try Pilates exercises in first month
- [ ] 10% create mixed workout sessions
- [ ] Dex unlocking works for all types

---

## Open Questions

1. **Yoga flows:** Should we add a "circuit" mode for sequences?
2. **Cardio integration:** Distance-based tracking (running, cycling)?
3. **Custom exercises:** Should users be able to pick tracking mode?
4. **Workout templates:** Pre-made Pilates routines?

---

## Next Steps

1. **Review & Approve** this document
2. **Create Pilates exercise list** (20-30 core exercises)
3. **Begin Phase 1** implementation
4. **User testing** with beta group (mixed workout athletes)

---

**Document Owner:** Claude & Dimitar
**Last Updated:** 2025-10-31
**Status:** ✅ Ready for Implementation
