# Training Science Implementation Plan
Date: 2026-05-07 (revised)

This document is the full priority-ordered implementation plan for making the workout, planning,
and exercise features more science-based. It incorporates the social accountability goal of the
app: holding yourself and your friends to their plans. The sequence builds data foundations first,
delivers real-time in-workout value early, then layers intelligence on top as data accumulates.

All new views follow the app design language: `ChamferedRectangle` for cards, `DS.Semantic.*`
tokens for color, `DS.Typography` / `.dsFont()` for text, `DS.Chip` for status labels,
`DS.PrimaryButtonStyle` / `DS.SecondaryButtonStyle` for buttons, `DS.Palette.marone` (#CCFF00)
for active/brand states. No emojis. No em dashes.

---

## Priority 1: RPE/RIR Capture — DONE

### What it is
RPE (Rate of Perceived Exertion, 1-10) and RIR (Reps in Reserve, 0-5+) are per-set effort
ratings. RPE 8 = hard but manageable. RPE 10 = failure. RIR 2 = two reps left before failure.

### Why it matters
`SetInput` stores reps, weight, completion, timing, and rest but has no effort signal
(`Core/Models/WorkoutEntry.swift:67`). Two 100%-complete workouts can be RPE 6 (easy) and
RPE 9.5 (grinding). Every intelligent feature in this plan — autoregulation, deload detection,
fatigue tracking — depends on per-set effort data. This is the data foundation.

### Science basis
Zourdos et al. (2016) validated RPE-based autoregulation. Mann et al. (2010) showed it
outperforms fixed-load progression for trained lifters. Israetel's MRV framework is built on RIR:
hypertrophy sweet spot is RIR 2-3; consistently hitting RIR 0-1 accumulates fatigue.

### What was built

**Model (`Core/Models/WorkoutEntry.swift`):**
- Added `rpe: Double?` and `rir: Int?` to `SetInput`.
- Both use `try?` in the existing custom decoder — nil for all sets recorded before this
  field existed. All existing call sites unaffected (both default to nil in memberwise init).

**Three-state set row (`SetRowViews.swift`):**
`SetRowUnified` now branches on state rather than just dimming:
- **Completed (collapsed):** single compact row — checkmark, "Set N", "10 × 45kg" summary,
  RPE badge (capsule, brand color, only shown when rpe is non-nil). Tap does nothing —
  swipe left to mark incomplete. Re-completing requires going through Log This Set again
  which would re-fire the rest timer, so tap-to-uncomplete was intentionally excluded.
- **Active (expanded):** full steppers + RPE chip strip + Log This Set button.
- **Pending (not completed, not active):** compact row matching completed height — hollow
  circle, "Set N", reps×weight dimmed in secondary color. Tap activates it.

**RPE chip strip:**
- Values: `[6, 7, 8, 8.5, 9, 9.5, 10]` — 7 chips. Starts at 6 (not 7) because RPE 6 is
  a valid working-set rating during deload weeks and technique sessions.
- Half-point precision only above 7.5 — the range where lifters make finer distinctions.
- No Skip button — tapping a selected chip deselects it (sets rpe = nil), which is
  identical to what Skip would do. Two paths to the same state is redundant.
- Shown only for `SetTag.working`. Hidden for warmup and backoff.
- Selected chip: brand background, black foreground. Unselected: brand tint 10%, brand text.
- Tap toggles selection with `.easeInOut(0.12)` animation.

**Swipe action fix (`ExcerciseSessionView.swift`):**
- Removed the `ZStack` approach (SwiftUI ignores custom backgrounds in swipe action labels).
- Now uses `.tint(DS.Palette.marone)` on the button and `.foregroundStyle(.black)` on the
  label — the correct pattern for branded swipe actions with dark text.

### Files changed
- `Core/Models/WorkoutEntry.swift`
- `Features/WorkoutSession/Views/ExerciseSession/SetRowViews.swift`
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift`

### Migration safety
Confirmed safe. `SetInput` is a plain Codable struct. Existing stored workouts decode with
`rpe = nil` and `rir = nil`. No SwiftData migration needed.

### Dependencies
None. Built first. Priorities 7 and 8 depend on accumulated RPE data from this feature.

---

## Priority 2: Equipment Preference Filter

### What it is
A one-time setting in Preferences: the user selects which equipment their gym has. Every
exercise list in the app — workout builder, exercise browser, planner — then filters automatically.

### Why it matters
A home gym user sees cable machine, leg press, and Smith machine exercises in every search.
This is noise at the exact moment of planning. Exercise adherence research shows reducing
selection friction is the largest lever on compliance.

### What already exists
The infrastructure is fully in place:
- `EquipBucket` enum with 8 types: `Features/ExerciseRepository/Models/ExerciseFilters.swift:14`
- `ExerciseFilters` struct has an `equipment: EquipBucket` field
- Filter logic runs in `ExerciseCache.getPage()` and `ExerciseRepository.matchesFilters()`
- The per-screen single-bucket chip already works everywhere

Missing: persisting a multi-select preference and auto-injecting it at the repository level.

### What to build

**Storage:**
- `@AppStorage("available_equipment")` storing comma-separated `EquipBucket.rawValue` strings.
- Empty = no filter (show everything). This is the default.

**`ExerciseFilters` change:**
- Add `availableEquipment: Set<EquipBucket> = []`
- In `ExerciseCache.getPage()` and `getTotalCount()`: if `availableEquipment` is non-empty,
  exclude exercises whose `equipBucket` is not in the set — except `.bodyweight`, which always
  passes.

**Repository injection:**
- `ExerciseRepository` reads the preference and injects it into every `loadFirstPage(with:)` call
- Expose `refreshForEquipmentChange()` — reloads with the current search state plus updated
  preference. Called from the Preferences UI on every toggle.

**Preferences UI (`Features/Profile/Views/PreferencesView.swift`):**
New card section titled "Gym Equipment". Layout: a scrollable list of toggle rows, one per
`EquipBucket` (excluding `.all` and `.bodyweight`).

Each row: `HStack` — SF Symbol for the equipment type, display name, `Spacer()`, `Toggle`.
Background: `DS.Semantic.card`. Container: `ChamferedRectangle(.medium)` with
`DS.Semantic.border` stroke at 1pt.

Display names:
| `EquipBucket` | Label |
|---|---|
| `.barbell` | Barbell |
| `.dumbbell` | Dumbbells |
| `.cable` | Cable Machine |
| `.machine` | Machines |
| `.kettlebell` | Kettlebell |
| `.pullupbar` | Pullup Bar |
| `.other` | Other / Bands |

Footer text (`.dsFont(.footnote)`, `DS.Semantic.textSecondary`):
"Bodyweight exercises always appear. Tap a category to hide exercises you can't do."

Active state: selected toggle uses `DS.Palette.marone` tint (set via `.tint(DS.Palette.marone)`)
on the `Toggle`.

### Files to touch
- `Features/ExerciseRepository/Models/ExerciseCache.swift` — `availableEquipment` filter check
- `Features/ExerciseRepository/Services/ExerciseRepository.swift` — preference injection
- `Features/Profile/Views/PreferencesView.swift` — equipment section

### Migration safety
No SwiftData changes. `ExerciseFilters` is a plain struct. Preference persisted via
`@AppStorage` (UserDefaults). Existing users see no filter applied until they configure it.

### Dependencies
None.

---

## Priority 3: Rest Period Intelligence — DONE

### What it is
The rest timer already fires after every set. This priority makes the suggested rest duration
science-aware: the recommendation is derived from the current rep range and set tag, not just
the compound/isolation binary.

### Why it matters
`RestTimerPreferences` already stores per-exercise overrides and compound/isolation defaults
(180s and 90s). But a 4-rep strength set and a 15-rep pump set for the same compound exercise
have different optimal rest periods (4-5 min vs 60-90 s). The data to derive this is already
in `SetInput` (reps). This is zero-infrastructure cost, purely wiring.

### Science basis
Schoenfeld et al. (2016): 3-5 min rest for strength (1-5 rep range), 1.5-2 min for hypertrophy
(6-12 rep range), 60-90 s for endurance/pump (13+ reps). Shorter rest reduces total volume
output for strength goals. The app can recommend without enforcing.

### What already exists
- `RestTimerPreferences.restDuration(for:)` — returns seconds based on compound/isolation
- `RestTimerPreferences` already has `defaultCompoundSeconds` (180s) and
  `defaultIsolationSeconds` (90s) stored per user
- Rest timer fires when a set is logged

### What to build

**New function on `RestTimerPreferences`:**
```swift
func recommendedRestSeconds(for exercise: Exercise, reps: Int, tag: SetTag) -> Int
```
Logic:
- `tag == .warmup`: return 60
- `tag == .backoff`: return 90
- `reps <= 5`: return 240 (4 min — strength zone)
- `reps <= 12`: return perExerciseOverride ?? (isCompound ? 180 : 90)
- `reps > 12`: return 60

**Inline banner in the active set row (`SetRowUnified`):**
When the user changes reps in an active working set and the rep count falls in the strength
zone (<=5) or pump zone (>12), and their current rest timer differs from the recommendation
by more than 30 seconds, a compact banner appears between the RPE strip and the "Log This
Set" button.

Trigger: `onChange(of: set.reps)` with a 0.5s debounce (via `DispatchWorkItem`) to avoid
flickering during long-press stepper accelerations.

Banner layout: `HStack` — `Image(systemName: "clock")` in `DS.Semantic.textSecondary`,
tip text in `.dsFont(.caption)` `DS.Semantic.textSecondary`, `Spacer()`, dismiss `xmark`
button.

Tip text:
- Strength zone (reps <= 5): "4 min rest for strength sets"
- Pump zone (reps > 12): "1 min rest for high-rep sets"

**Dismissal — count-limited (3x per zone):**
Dismiss counts stored in `@AppStorage`:
- `"rest_rec_strength_dismiss_count"` — Int, increments when user taps xmark in strength zone
- `"rest_rec_pump_dismiss_count"` — Int, increments when user taps xmark in pump zone

Banner is suppressed when the zone's dismiss count reaches 3. The two zones are independent:
dismissing the strength tip does not suppress the pump tip and vice versa.

Banner auto-hides when the set becomes inactive (user taps another set) or is logged.

### Files to touch
- `Features/WorkoutSession/Views/RestTimer/RestTimerPreferences.swift` — new function
- `Features/WorkoutSession/Views/ExerciseSession/SetRowViews.swift` — `RestZone` enum,
  banner view, debounce state, `evaluateRestZone`, `scheduleRestBannerEvaluation`

### Migration safety
No model changes. `RestTimerPreferences` uses UserDefaults. No SwiftData migration needed.

### Dependencies
None. `SetInput.reps` already exists.

---

## Priority 4: Adherence as Accountability Signal

### What it is
Track planned vs. completed workouts at the session level and surface the adherence rate where
it creates accountability: on the home screen and visible to friends.

### Why it matters
`WeeklyProgressCard` on the home screen already shows a progress bar and "X of Y workouts"
(`Features/Home/Components/Cards/WeeklyProgressCard.swift`). But this counts any logged workout
— not specifically whether the user followed their plan. Someone who skips leg day and replaces
it with a casual chest session looks identical to someone who executed their plan exactly.
Adherence is the accountability metric the social layer should amplify.

### Science basis
Program adherence is the largest predictor of outcomes across all fitness goals — larger than
any programming variable. Making adherence visible to friends creates accountability through
social pressure, which is independently validated (Carron et al., 2012: social support is the
strongest correlate of exercise adherence).

### What already exists
- `WeeklyProgressCard` shows workout count vs. target (not plan-aware)
- `PlannerStore` knows planned workouts vs. completed
- `FriendActivityCard` on home shows friend activity
- `PRAutoPostService` auto-posts PRs to the social feed

### What to build

**Adherence model:**
Add `PlanAdherence` struct:
```swift
struct PlanAdherence {
    let week: Date          // start of ISO week
    let plannedSessions: Int
    let completedOnPlan: Int   // workout matched a planned session
    let completedOffPlan: Int  // logged without a matching planned session
    var rate: Double { plannedSessions > 0 ? Double(completedOnPlan) / Double(plannedSessions) : 1.0 }
}
```

**`PlannerStore` addition:**
`func adherence(forWeek: Date) -> PlanAdherence` — compares `PlannedWorkout` completion status
against the week start. Cheap: iterate `WorkoutSplit.planBlocks` for the week.

**`WeeklyProgressCard` revision:**
Replace the generic count with plan-aware language when a plan is active:
- Header: "This Week" (unchanged)
- Primary number: `completedOnPlan` / `plannedSessions` (e.g., "3 / 5 sessions")
- Secondary text: if `completedOffPlan > 0`, show "also \(n) unplanned" in
  `DS.Semantic.textSecondary`
- Progress bar fill color:
  - `rate >= 1.0`: `DS.Status.success`
  - `rate >= 0.6`: `DS.Palette.marone`
  - `rate < 0.6`: `DS.Status.warning`
- If no plan is active: fall back to current behavior (total sessions vs. goal).

**Friend accountability nudge (new `FriendAdherenceCard`):**
On the home screen, if one or more friends have `rate < 0.5` for the current week and have
granted visibility, show a compact card:

Layout: `HStack(spacing: 12)` — avatar stack (up to 3 overlap), label "2 friends are behind on
their plan this week", `Spacer()`, secondary action "Send nudge" as
`DS.SecondaryButtonStyle(size: .compact)`.

Background: `DS.Semantic.card`. Shape: `ChamferedRectangle(.large)`. Border:
`ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1)`.
Label: `.dsFont(.subheadline, weight: .medium)`, `DS.Semantic.textPrimary`.

"Send nudge" creates a push notification to the friend: "Your friend is checking in on you —
time to train?" Requires the friend's notification permission and a matching Supabase function.
Rate-limit: one nudge per friend per 24 hours.

**Social visibility opt-in:**
In Preferences, under a "Social Sharing" section:
- Toggle: "Share my weekly adherence with friends" (off by default)
- Caption: "Friends can see whether you're on track with your plan."
- When on, adherence rate is included in the profile data fetched by `ProfileRepository`.

### Files to touch
- `Features/WorkoutSession/Services/PlannerStore.swift` — `adherence(forWeek:)`
- `Core/Models/` or `Features/WorkoutSession/Models/` — `PlanAdherence` struct
- `Features/Home/Components/Cards/WeeklyProgressCard.swift` — plan-aware display
- `Features/Home/Components/Cards/` — new `FriendAdherenceCard.swift`
- `Features/Home/Components/SmartCardCarousel.swift` — insert `FriendAdherenceCard` when data
  is available
- `Features/Profile/Views/PreferencesView.swift` — social sharing opt-in toggle

### Migration safety
`PlanAdherence` is a transient computed struct — never persisted. `PlannedWorkout` already
has the `status` field needed to compute adherence. No SwiftData changes required.

### Dependencies
Requires `PlannerStore` to have planned sessions for the active week. Works without a plan
(falls back to unplanned count).

---

## Priority 5: e1RM Plateau Detection and Projection — DONE

### What it is
Detect when a lifter's estimated 1RM has been flat for 3+ consecutive weeks and surface the
insight proactively — in the planner, in the workout session, and on the e1RM chart as a
projection line.

### Why it matters
The e1RM chart exists (`ExerciseStatisticsView.swift`) and the `TrendDirection` label exists.
But a user stuck on the same squat e1RM for 6 weeks has no signal that their program is stalling.
The data exists; the gap is surfacing it where it drives action.

### Science basis
A flat e1RM trend (< 1% change/week) for 3+ consecutive weeks in a trained lifter is a clear
signal that the current stimulus is no longer novel. Common causes: insufficient overload,
inadequate recovery, or monotonous stimulus. Each has a different fix.

### What already exists
- e1RM computed per session in `ExerciseStatsAggregator.swift:706` (Epley formula)
- `E1RMChart` in `ExerciseStatisticsView.swift`
- `TrendDirection` enum: improving / stable / declining / insufficient
- `e1rmProgression: [ProgressPoint]` available as chart data

### What to build

**Plateau detection in `ExerciseStatsAggregator`:**
Add `PlateauState` to `ExerciseStatModels`:
```swift
struct PlateauState {
    let isPlateaued: Bool
    let weeksFlat: Int
    let lastProgressDate: Date?
}
```
Plateau = rolling slope of `e1rmProgression` < 1% per week for 3+ consecutive weeks with
at least 3 data points in the window. Expose as `plateauState: PlateauState` on `ExerciseStat`.

**Projection overlay on `E1RMChart`:**
Compute a simple linear regression on the last 6-8 data points. Extend 4 weeks forward as a
dashed line in `DS.Semantic.textSecondary.opacity(0.5)`.

Endpoint annotation: a small label "~120kg by Jun 2" in `.dsFont(.caption)`,
`DS.Semantic.textSecondary`. Cap the projection: if slope < threshold, show nothing.

**Planner surface:**
On each planned exercise row where `plateauState.isPlateaued == true`, show an inline indicator
below the exercise name:
`DS.Chip(title: "\(n) weeks without progress", systemImage: "arrow.right.arrow.left", tone: .gold)`
Tapping the chip opens a contextual action sheet with two options:
1. "Add 2.5kg to next session" — patches the ghost weight directly
2. "Consider a deload" — links to the deload suggestion flow (Priority 8)

**Workout session surface:**
If the same weight has been used for 3+ consecutive sessions of the same exercise, show a
collapsible inline banner between the exercise header and the first set row:

Layout: `HStack` — `Image(systemName: "chart.line.flattrend.xyaxis")` in
`DS.Semantic.accentGold`, label text, `Spacer()`, "Increase weight" chip.
Background: `DS.Semantic.accentGold.opacity(0.08)`. Shape: `RoundedRectangle(cornerRadius: 10)`.
Border: `DS.Semantic.accentGold.opacity(0.3)` stroke, 1pt.
Text: "3 sessions at [X]kg — try increasing the load." `.dsFont(.footnote)`,
`DS.Semantic.textSecondary`.
"Increase weight" is `DS.Chip(title: "Try +2.5kg", tone: .gold)` — tapping pre-fills the
weight stepper with the suggested value for all sets in that exercise.

Banner is collapsible (chevron.up/down). Dismissed state persists in `@State` for the session.

### Files to touch
- `Features/Statistics/Services/ExerciseStatsAggregator.swift` — plateau detection
- `Features/Statistics/Models/ExerciseStatModels.swift` — `PlateauState` struct
- `Features/Statistics/Views/ExerciseStatisticsView.swift` — projection overlay
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` — plateau banner
- `Features/Planner/Views/` — plateau chip on planned exercise row

### Migration safety
`ExerciseStatistics` and all types in `ExerciseStatModels.swift` are plain structs computed
in memory by `ExerciseStatsAggregator` — none are SwiftData `@Model` classes. `PlateauState`
is added to `ExerciseStatistics` as a computed value, never persisted. No SwiftData migration.

### Dependencies
None for detection. Priority 7 (RPE autoregulation) improves root-cause explanation.

---

## Priority 6: Movement Pattern Balance Surfacing — DONE

### What it is
Push/pull ratio and movement pattern breakdown are already computed and persisted after each
workout. This priority wires those signals into the planner and post-workout flow so the user
encounters them at moments of decision, not buried in a stats screen.

### Why it matters
Most users overtrain push (chest/shoulders) relative to pull (back/rear delts). The recommended
pull:push ratio for shoulder health is 1.0-1.5. Someone doing 4 chest exercises and 1 row per
week builds rotator cuff overuse risk that manifests as injury months later. The `TrainingBalanceSection`
view and the `PushPullBalance` SwiftData model already exist and compute this. The gap is surfacing it.

### Science basis
Gray Cook and McGill's corrective literature, plus sports science consensus: anterior-dominant
programming is the leading cause of overuse injuries in recreational lifters.

### What already exists
- `PushPullBalance` SwiftData model: pushVolume, pullVolume, ratio
- `MovementPatternBalance` SwiftData model: compoundVolume, isolationVolume, hingeVolume, squatVolume
- `TrainingBalanceSection` view with green/yellow/red status
- `StatsAggregator` computes and persists after each workout
- `TrainingBalanceIcon` at `Features/Statistics/Views/ProfileStatsSection.swift:84`

### What to build

**Planner weekly view banner:**
Compute the projected push:pull ratio from `PlannedWorkout` data for the current week.
If ratio > 2.0 (push-heavy) or < 0.5 (pull-heavy), show a non-blocking inline banner at
the top of the weekly planner:

"This week's plan is push-heavy (ratio 2.4). Consider adding a row or pull variation."

Layout: `HStack` — `Image(systemName: "scale.3d")` in `DS.Semantic.accentWarm`,
label text in `.dsFont(.footnote)` `DS.Semantic.textSecondary`, `Spacer()`,
dismiss button (xmark, `DS.Semantic.textSecondary`).
Background: `DS.Semantic.accentWarm.opacity(0.08)`. Shape: `RoundedRectangle(cornerRadius: 10)`.
Border: `DS.Semantic.accentWarm.opacity(0.3)` stroke, 1pt.

**Post-workout surface:**
After saving a workout, if the rolling 4-week push:pull ratio is outside 0.8-2.0, include a
single line on the completion screen below the summary stats:
"Push:pull ratio this month: 2.3. More pulling would support shoulder health."
Style: `.dsFont(.footnote)`, `DS.Semantic.textSecondary`. No action required. Informational only.

**Profile badge extension:**
Extend `TrainingBalanceIcon` to emit a caution ring when ratio is outside 0.8-2.0:
replace the current neutral stroke with `DS.Semantic.accentWarm` stroke at 1.5pt.
No label change needed.

**Classification fixes:**
Add explicit `moveBucket` overrides for exercises that misclassify by name-matching:
hip thrust, Romanian deadlift, sumo deadlift, and cable pull-through should be `hinge`,
not whatever they currently resolve to. Done as a constant override map in
`ExerciseRepository` or `ExerciseFilters`.

### Files to touch
- `Features/Statistics/Views/ProfileStatsSection.swift` — caution ring on `TrainingBalanceIcon`
- `Features/Planner/Views/` — projected balance banner on weekly view
- `Features/WorkoutSession/Views/` — post-workout single-line note on completion screen
- `Features/ExerciseRepository/Models/ExerciseFilters.swift` — `moveBucket` overrides

### Migration safety
`PushPullBalance` and `MovementPatternBalance` are `@Model` classes but no new fields are
added — only existing fields are read and surfaced. The classification override map is a
constant in code. No SwiftData migration needed.

### Dependencies
None. All data exists. This is purely wiring and light classification fixes.

---

## Priority 7: RPE-Aware Autoregulation

### What it is
Replace the binary completion-percentage check in `ProgressionStrategy.autoregulated` with a
continuous RPE-based rule. If RPE data is not available, fall back to the existing logic.

### Why it matters
Completion percentage is a coarse signal. Two lifters both completing 4x8 at 100kg: one averaged
RPE 6.5 (clearly ready to progress), one averaged RPE 9.2 (barely hanging on). The current
rule treats them identically. RPE makes the right call automatically.

### Science basis
Mann et al. (2010), Zourdos et al. (2016): RPE-based autoregulation outperforms fixed-load
progression for intermediate and advanced lifters. Basic rule: actual RPE below target RPE by
more than 1.5 points means increase load; within ±1.0 means hold; above target by more than
1.0 means hold or reduce.

### What already exists
- `ProgressionStrategy` enum with `autoregulated` case (uses completion % only)
- `WeightSuggestionHelper` checks last 3 workouts for plateau

### What to build

**`PlannedExercise` addition:**
Add `targetRPE: Double?` (default nil = use completion-based logic).
In the planner exercise editor (`ExerciseEditSheet.swift`), add an optional "Target effort"
row: a horizontal stepper showing RPE 6, 7, 7.5, 8, 8.5, 9. Default is blank (no target).
Label: "Target effort (RPE)". Below the stepper: a caption explaining the scale in one line:
"RPE 8 = 2 reps left. RPE 9 = 1 rep left." Style: `.dsFont(.footnote)`, `DS.Semantic.textSecondary`.

**Progression logic in `ProgressionStrategy.autoregulated`:**
When generating the next session's ghost weight, check if >= 2 sessions have RPE data:
- Average RPE < targetRPE - 1.5: increase weight by the configured step
- Average RPE within targetRPE ± 1.0: hold weight
- Average RPE > targetRPE + 1.0: hold, flag with `PlateauState` override
- No RPE data or `targetRPE == nil`: use current completion-% logic unchanged

**`WeightSuggestionHelper` surface:**
In the weight suggestion tooltip that already appears in the workout session, append the RPE
context when data exists:
"Last session: RPE 7.2 — below target, try +2.5kg"
"Last session: RPE 9.1 — at limit, same weight recommended"
Style: `.dsFont(.footnote)`, `DS.Semantic.textSecondary`, shown below the weight suggestion.

### Files to touch
- `Features/WorkoutSession/Models/PlannerModels.swift` — `targetRPE` on `PlannedExercise`
- `Features/WorkoutSession/Services/PlannerStore.swift` — RPE-aware ghost weight generation
- `Core/Utilities/WeightSuggestionHelper.swift` — RPE context in suggestion text
- `Features/Planner/Views/Components/ExerciseEditSheet.swift` — target RPE stepper

### Migration safety
`PlannedExercise` IS a SwiftData `@Model`. Adding `targetRPE` requires a schema change.
Safe pattern — declare it as optional with a nil default:
```swift
var targetRPE: Double? = nil
```
SwiftData treats this as a lightweight migration: a nullable column is added and all
existing `PlannedExercise` rows get `nil` automatically. No `VersionedSchema` or
`MigrationPlan` required. This is consistent with how the codebase has handled all previous
`@Model` additions (no migration files exist in the project).

### Dependencies
Requires Priority 1 (RPE capture) to have accumulated data across at least 2 sessions per
exercise. Ship Priority 1 first; build this 4-6 weeks later once data exists.

---

## Priority 8: Smart Deload Signals and HealthKit Recovery

### What it is
Instead of a fixed deload schedule, the app detects fatigue accumulation from training data
and HealthKit recovery signals and surfaces a deload suggestion card on the planner.

### Why it matters
A fixed schedule deloads unnecessarily when the lifter is fresh, and never fires when they
are genuinely fatigued. The combination of RPE trend, e1RM trend, volume drop, and resting
heart rate from HealthKit gives a reliable multi-signal read without requiring any extra
user input.

### Science basis
Zatsiorsky and Kraemer's fatigue-fitness model: training produces fitness gains and fatigue
simultaneously. Deloading allows fatigue to dissipate while fitness is retained, producing
supercompensation. HRV and resting heart rate are validated non-invasive recovery indicators
(Kiviniemi et al., 2010): resting HR elevated >5 bpm above baseline for 3+ days correlates
with under-recovery.

### What already exists
- `trendDirection` (improving/stable/declining) on exercise stats
- `PlateauState` (from Priority 5)
- HealthKit already integrated for workouts; `HKQuantityTypeIdentifier.restingHeartRate` and
  `HKQuantityTypeIdentifier.heartRateVariabilitySDNN` are readable without additional permissions
  if the user has a connected Apple Watch

### What to build

**HealthKit recovery signal (`HealthKitManager` addition):**
New function: `func recentRestingHRBaseline() async -> (baseline: Double, recent3Day: Double)?`
- Fetch resting HR samples for the last 30 days
- Compute 30-day median as baseline
- Compute 3-day average as recent signal
- Return nil if fewer than 5 samples exist
- No new permission needed if HealthKit access is already authorized

**Fatigue signal computation (`ExerciseStatsAggregator`):**
After each workout, compute a `FatigueSignal` struct:
```swift
struct FatigueSignal {
    let rpeCreep: Bool      // RPE increasing at same weight across last 3 sessions
    let e1rmDecline: Bool   // e1RM declining for 2+ consecutive sessions
    let volumeDrop: Bool    // sets completed < 80% of planned for 2+ sessions
    let hrElevated: Bool    // resting HR > baseline + 5 bpm for 3+ days
}
```
Aggregate to `programFatigueLevel: Int` (0-3, one point per true signal). Store in
`PlannerStore` for the active program.

**Deload suggestion card on the planner:**
When `programFatigueLevel >= 2` for the active program:

Show a `DeloadSuggestionCard` as the first card in the planner's weekly view. It does not
block or replace the plan — it is a dismissable card.

Layout:
```
[Icon: heart.rate.circle]  Your body may need a break
                           3 of 4 fatigue signals detected this week.
                           A deload reduces load to 60% for 7 days.

                [Dismiss]  [Schedule Deload Week]
```
Background: `DS.Semantic.card`. Shape: `ChamferedRectangle(.large)`.
Border: `ChamferedRectangle(.large).stroke(DS.Semantic.accentWarm.opacity(0.3), lineWidth: 1)`.
Icon: `Image(systemName: "heart.rate.circle")` in `DS.Semantic.accentWarm`.
Title: `.dsFont(.sectionTitle)`, `DS.Semantic.textPrimary`.
Body text: `.dsFont(.body)`, `DS.Semantic.textSecondary`.
"Dismiss": `DS.TertiaryButtonStyle(size: .compact)`.
"Schedule Deload Week": `DS.SecondaryButtonStyle(size: .compact)` with `DS.Semantic.accentWarm`
foreground. Override the secondary style tint for this button using `.foregroundStyle`.

Scheduling a deload creates a 7-day planned period in `PlannerStore` with all loads at 60%
and volume at 50% of the baseline week.

**Calibration constraints:**
- Do not surface if `programFatigueLevel < 2`
- Do not suggest deload more than once every 3 weeks
- Do not surface if fewer than 3 sessions in the last 14 days (not enough data; likely
  already recovered from inactivity)
- User can dismiss permanently for the current week

### Files to touch
- `Core/Services/HealthKitManager.swift` — `recentRestingHRBaseline()`
- `Features/Statistics/Services/ExerciseStatsAggregator.swift` — `FatigueSignal` computation
- `Features/WorkoutSession/Services/PlannerStore.swift` — program-level fatigue aggregation,
  deload week generation
- `Features/Planner/Views/` — new `DeloadSuggestionCard.swift`

### Migration safety
`FatigueSignal` is a transient struct computed after each workout — never persisted.
HealthKit queries use read-only APIs already authorized. No SwiftData migration needed.

### Dependencies
Best signal requires Priority 1 (RPE data). Can use e1RM + volume + HealthKit HR alone as
a weaker signal before RPE data accumulates.

---

## Priority 9: Weekly Muscle Volume vs. Science-Based Targets

### What it is
Show the user's weekly sets per muscle group alongside evidence-based MEV/MAV ranges.
"You trained quads 6 sets this week. Target for hypertrophy: 10-20 sets."

### Why it matters
The movement pattern balance (Priority 6) tells the user their ratio is off. This tells them
exactly which muscle group is under- or over-trained and by how much — an actionable number
the user can act on in the planner.

### Science basis
Israetel, Hoffman, and Smith (2019) — Renaissance Periodization landmark tables:
MEV (Minimum Effective Volume) is the threshold for stimulus. MAV (Maximum Adaptive Volume)
is the sweet spot. MRV (Maximum Recoverable Volume) is the ceiling before recovery suffers.
Published per-muscle ranges exist and are widely validated.

### What to build

**Constant table (`ExerciseFilters` or dedicated `MuscleVolumeTargets.swift`):**
```swift
struct MuscleVolumeTarget {
    let muscleGroup: String
    let mev: Int   // minimum effective sets/week
    let mav: Int   // maximum adaptive sets/week (top of sweet spot)
    let mrv: Int   // maximum recoverable volume
}
```

Example values (per RP tables):
| Muscle Group | MEV | MAV | MRV |
|---|---|---|---|
| Chest | 8 | 16 | 22 |
| Back | 10 | 20 | 25 |
| Quads | 8 | 16 | 20 |
| Hamstrings | 6 | 12 | 16 |
| Shoulders | 6 | 16 | 20 |
| Biceps | 8 | 14 | 20 |
| Triceps | 6 | 12 | 18 |
| Glutes | 4 | 12 | 16 |
| Calves | 8 | 16 | 20 |
| Abs | 8 | 16 | 20 |

**Volume counting (`StatsAggregator` addition):**
`func weeklySetCount(for muscleGroup: String, weekStart: Date) -> Int`
Count working sets (excluding warmup) for exercises where `muscleGroup` appears in
`primaryMuscles` or `secondaryMuscles`, for the current ISO week.

**`MuscleVolumeCard` (new home screen card):**
A scrollable horizontal stack of muscle group rows, each showing:
- Muscle group name (`.dsFont(.caption, weight: .semibold)`, `DS.Semantic.textPrimary`)
- Set count / MAV range (e.g., "9 / 10-20") (`.dsFont(.footnote)`, `DS.Semantic.textSecondary`)
- A thin progress bar:
  - Below MEV: `DS.Status.warning` fill
  - MEV to MAV: `DS.Palette.marone` fill
  - MAV to MRV: `DS.Status.success` fill
  - Above MRV: `DS.Status.error` fill

Card background: `DS.Semantic.card`. Shape: `ChamferedRectangle(.large)`.
Title: "Muscle Volume This Week" in `.dsFont(.sectionTitle)`.

Show a max of 6 muscle groups in the card, sorted by distance from MEV ascending (most
under-trained first). A "See all" link expands to a full list.

This card appears on the home screen `SmartCardCarousel` only when the user has a plan with
at least 2 completed sessions in the current week.

### Files to touch
- `Core/Models/` or `Features/Statistics/Models/` — `MuscleVolumeTarget`, target table
- `Features/Statistics/Services/ExerciseStatsAggregator.swift` — `weeklySetCount(for:weekStart:)`
- `Features/Home/Components/Cards/` — new `MuscleVolumeCard.swift`
- `Features/Home/Components/SmartCardCarousel.swift` — insert card when conditions met

### Migration safety
`MuscleVolumeTarget` is a constant table in code, not persisted. `weeklySetCount` is computed
from existing `WorkoutEntry` data. No SwiftData migration needed.

### Dependencies
Benefits from Priority 6 (movement pattern data already computed).

---

## Priority 10: Exercise Substitutions

### What it is
A "Swap" affordance on each exercise in the active workout and in the planner, backed by
a similarity score that returns the best alternatives for the movement.

### Why it matters
Without this, users skip exercises or pick random replacements that break training intent.
A bench press substitute in a hotel gym should be dumbbell press, not a cable fly.

### Science basis
Pedrosa et al. (2022): exercise variation produces independent hypertrophy benefits through
different load angles and strength-curve loading. An alternatives system is also a variation
rotation tool for advanced programs.

### What already exists
Every exercise has `equipBucket`, `moveBucket`, `primaryMuscles`, `mechanic` (compound/isolation).
`ExerciseRepository.byID` is an O(1) lookup index.

### What to build

**Similarity scoring in `ExerciseRepository`:**
```swift
func alternatives(for exerciseID: String, availableEquipment: Set<EquipBucket>) -> [Exercise]
```
Score all exercises against reference:
- `moveBucket` match: +3
- `primaryMuscles[0]` match: +3
- `mechanic` match: +2
- Equipment in `availableEquipment`: +1
- Different `equipBucket` than reference: +1 (ensures it's a genuine alternative)

Return top 5 by score, excluding the reference exercise.

**Workout session swap sheet:**
On the exercise header row in the active workout, add a "Swap" text button
(`DS.TertiaryButtonStyle(size: .compact)`, label "Swap exercise") to the right of the
exercise name.

Tapping opens a sheet (`presentationDetents([.medium])`).

Sheet layout:
- Title: "Alternatives for [Exercise Name]" `.dsFont(.cardTitle)`
- Subtitle: "Same movement, different equipment" `.dsFont(.footnote)`, `DS.Semantic.textSecondary`
- List of up to 5 alternatives, each as a `ChamferedRectangle(.medium)` card:
  - Exercise name (`.dsFont(.subheadline, weight: .semibold)`)
  - Match reason chips: e.g., `DS.Chip(title: "Same movement", tone: .brand)`,
    `DS.Chip(title: "Dumbbell", tone: .soft)`
  - "Select" button: `DS.SecondaryButtonStyle(size: .compact)`

Swapping replaces the exercise in the current workout session only — not the plan.

**Planner alternatives affordance:**
On each planned exercise row in the split editor, a secondary icon button
(`Image(systemName: "arrow.2.squarepath")`, `DS.Semantic.textSecondary`) that opens the
same alternatives sheet. Swapping here updates the `PlannedExercise` in the plan.

### Files to touch
- `Features/ExerciseRepository/Services/ExerciseRepository.swift` — `alternatives(for:availableEquipment:)`
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift` — swap button + sheet
- `Features/Planner/Views/Components/ExerciseEditSheet.swift` — alternatives affordance

### Migration safety
No model changes. Similarity scoring uses existing `Exercise` fields. No SwiftData migration.

### Dependencies
Priority 2 (equipment preference) improves alternative quality by filtering to available
equipment. Can be built independently.

---

## Priority 11: Block Periodization (Planner v2)

### What it is
Programs divide into 3-4 week blocks: Accumulation (high volume, moderate intensity),
Intensification (lower volume, higher intensity), Realization (peak/test week). Volume and
intensity targets vary by block, not just linear weekly progression.

### Why it matters
Linear progression breaks down for intermediate and advanced lifters because the body adapts
to monotonous stimuli within weeks. Periodization deliberately cycles the training stimulus.

### Science basis
Issurin (2010) and subsequent meta-analyses: block periodization produces superior strength
and power gains vs. traditional linear periodization for trained athletes. DUP (Daily
Undulating Periodization) is the most flexible modern model: different rep targets per session
within the same week.

### What already exists
- `WorkoutSplit` has `planBlocks`, `anchorDate`, `cursor`
- `ProgressionStrategy` enum: linear, percentage, autoregulated, static
- No mesocycle or block layer above `WorkoutSplit`

### What to build

**New model layer:**
`ProgramBlock` struct:
```swift
struct ProgramBlock: Codable {
    var name: String           // "Accumulation", "Intensification", "Peak"
    var durationWeeks: Int
    var targetRepRange: ClosedRange<Int>   // e.g., 8...12
    var intensityModifier: Double          // 0.9 = 90% of 1RM estimate
    var volumeModifier: Double             // 1.0 = baseline, 0.5 = deload
    var progressionOverrides: [String: ProgressionStrategy]  // keyed by exercise ID
}
```

`WorkoutSplit` gains `blocks: [ProgramBlock]?` (nil = legacy flat program, no migration needed
for existing splits).

`PlannerStore.generatePlannedWorkouts()` uses the block the cursor is currently in to set
ghost rep targets and weight percentage.

**SwiftData migration:**
Add `blocks` as an optional JSON-encoded field on the `WorkoutSplit` model. Use a
`VersionedSchema` migration. Existing splits get `blocks = nil` and continue to work as before.

**Periodized templates (`SplitTemplates.swift`):**
Add two templates:
1. "Hypertrophy Block": 4-week Accumulation (8-12 reps, 70-80% intensity) +
   3-week Intensification (4-6 reps, 80-87%) + 1-week Deload
2. "Strength Peak": 4-week Volume (5-8 reps) + 3-week Intensity (3-5 reps) +
   2-week Peak (1-3 reps) + 1-week Deload

**Planner setup carousel new step (`PlannerSetupCarouselView.swift`):**
Insert a "Program structure" step between split selection and frequency selection.

Two options presented as `ChamferedRectangle(.medium)` selection cards:
1. "Simple" — linear progression, same rep ranges every week. Current behavior.
2. "Periodized" — block-based. Shows a mini timeline graphic:
   `HStack` of colored blocks (brand for accumulation, warm for intensification,
   secondary for deload) with week counts beneath each.

Both cards: `.dsFont(.cardTitle)`, description in `.dsFont(.footnote)`, `DS.Semantic.textSecondary`.
Selected card: `DS.Palette.marone.opacity(0.1)` background, `DS.Palette.marone` border 2pt.
Unselected card: `DS.Semantic.card` background, `DS.Semantic.border` border 1pt.

### Files to touch
- `Features/WorkoutSession/Models/PlannerModels.swift` — `ProgramBlock` Codable struct, add `periodizationBlocksData: Data?` to `WorkoutSplit`
- `Features/WorkoutSession/Services/PlannerStore.swift` — block-aware generation
- `Features/WorkoutSession/Models/SplitTemplates.swift` — periodized template definitions
- `Features/Planner/Views/PlannerSetupCarouselView.swift` — program structure step

### Migration safety
`WorkoutSplit` IS a SwiftData `@Model`. Store `[ProgramBlock]` as a JSON-encoded `Data?`
field rather than as a `@Model` relationship — this avoids a relationship migration entirely:
```swift
var periodizationBlocksData: Data? = nil   // JSON-encoded [ProgramBlock]

var periodizationBlocks: [ProgramBlock] {
    get {
        guard let data = periodizationBlocksData else { return [] }
        return (try? JSONDecoder().decode([ProgramBlock].self, from: data)) ?? []
    }
    set {
        periodizationBlocksData = try? JSONEncoder().encode(newValue)
    }
}
```
`Data? = nil` is an optional property with a nil default — SwiftData adds a nullable column
and existing `WorkoutSplit` rows get `nil` automatically. No `VersionedSchema` needed.
`ProgramBlock` itself is a plain `Codable` struct, not a `@Model`.

### Dependencies
Build after all other priorities. Priorities 1-10 all work within the existing flat program model.

---

## Sequencing Summary

| # | Feature | Effort | Key output | Unlocks |
|---|---|---|---|---|
| 1 | RPE/RIR capture | Low | Per-set effort data | 7, 8 |
| 2 | Equipment preference filter | Low | Friction-free exercise picker | 10 |
| 3 | Rest period intelligence | Low | Real-time rest guidance | nothing |
| 4 | Adherence as accountability signal | Medium | Plan compliance + friend nudges | social layer |
| 5 | e1RM plateau detection + projection | Low-medium | Proactive stall signal | 7 |
| 6 | Movement pattern balance surfacing | Low | Injury-prevention nudges | 9 |
| 7 | RPE-aware autoregulation | Medium | Intelligent load progression | 8 |
| 8 | Smart deload signals + HealthKit recovery | Medium | Fatigue-aware deload card | nothing |
| 9 | Weekly muscle volume vs. targets | Medium | MEV/MAV progress card | nothing |
| 10 | Exercise substitutions | Medium | In-workout swap sheet | nothing |
| 11 | Block periodization | High | Mesocycle planner | nothing |

**Parallel tracks:**
- 1 and 2 in parallel (no shared code)
- 3 and 4 in parallel (no shared code)
- 5 and 6 in parallel (no shared code)
- 7 after 1 has shipped and accumulated data (4-6 weeks gap)
- 8 after 7
- 9 after 6
- 10 after 2
- 11 last

---

## Caution: Injury and Medical Language

If injury or limitation filtering is added in future, use measured language throughout:
"may be less suitable for," "consider alternatives if you have," "high spinal load."
Never imply medical safety decisions or categorically contraindicate exercises. Users with
real injuries should consult a physiotherapist or sports medicine professional. The app
surfaces considerations, not prescriptions.
