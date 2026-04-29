# Train View Deep Dive

Date: 2026-04-14

## Scope

For this review, "Train View" includes:

- Train tab shell entry: `App/AppShellView.swift`
- Train home hub: `Features/Home/HomeViewNew.swift`, `Features/Home/ViewModels/HomeViewModel.swift`
- Exercise browse / selection path: `Features/ExerciseRepository/*`
- Active workout / live overlay: `Features/WorkoutSession/Views/LiveWorkout/*`
- Exercise logging flow: `Features/WorkoutSession/Views/ExerciseSession/*`
- Rest timer state + UI: `Features/WorkoutSession/Views/RestTimer/*`
- Workout persistence / domain state: `Features/WorkoutSession/Services/WorkoutStoreV2.swift`

## High-Level Read

Train is functionally rich and user-facing flow is ambitious:

- Hub -> choose workout -> browse exercises -> log sets -> auto-rest -> live overlay -> save workout.
- App already has good product instincts: isolated hero timer leaf in home, persistent current workout, auto-prefill from history, superset support, watch/widget hooks, HealthKit matching.

Main problem: too much Train behavior lives in shared singleton state and cross-view side effects. Result:

- hard ownership boundaries
- duplicated logic
- high redraw/write churn during active sessions
- several correctness bugs hiding in edge cases

## Current Flow Map

1. Train tab mounts `HomeViewNew` from `App/AppShellView.swift:250-256`.
2. Home creates `HomeViewModel` on first appear and refreshes on every appear: `Features/Home/HomeViewNew.swift:322-342`.
3. Workout selection pushes browse routes via `NavigationPath`: `Features/Home/HomeViewNew.swift:176-199`, `216-244`.
4. Adding/logging exercises mutates `WorkoutStoreV2`: `Features/WorkoutSession/Services/WorkoutStoreV2.swift:435-816`.
5. Rest timer state lives in singleton `RestTimerManager`: `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:25-755`.
6. Live overlay and exercise session both react to timer completion and pending-set notifications:
   - `Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift:90-197`
   - `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift:156-166`, `1031-1149`
7. Persistence happens in detached background saves from many mutation points: `Features/WorkoutSession/Services/WorkoutStoreV2.swift:490`, `560`, `594`, `645`, `653`, `686`, `713`, `739`, `789`, `816`, `1288-1318`.

## What Is Working Well

### 1. Home timer isolation is correct

`TimerIsolatedHeroButton` isolates `RestTimerManager` observation from the `NavigationStack`, which is good defensive SwiftUI engineering:

- `Features/Home/HomeViewNew.swift:363-386`

This likely prevented scroll resets / navigation invalidation from timer ticks.

### 2. Storage safety improved

`WorkoutStoreV2` guards writes until storage loads:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:78-82`, `1288-1318`

That is good protection against blank overwrite on failed load.

### 3. Train UX has strong continuity

Good user-value features already exist:

- workout recovery / persistence
- auto-prefill from history
- rest timer integration
- widget/watch interaction
- HealthKit match backfill

This is not a weak feature. It is a feature with good ambition and weak boundaries.

## Findings

### Critical 1. PR detection is wrong for almost every non-10-rep set

`HomeViewModel.checkForPR` compares every working set against `bestWeightForExactReps(..., reps: 10)` instead of comparing against the set's actual rep count:

- `Features/Home/ViewModels/HomeViewModel.swift:196-205`

Impact:

- false-positive PR cards on Train home
- user trust damage
- especially wrong for low-rep strength work and high-rep accessories

Example:

- historical best at 10 reps = 80kg
- user does 5 reps at 90kg
- app marks PR even if historical 5-rep best is 110kg

Recommendation:

- compare against `set.reps`, not hardcoded `10`
- ideally use same PR engine/index used at workout finish, not home-screen custom logic

### Critical 2. Rest timer has no single owner for "generate next set"

Set generation after rest completion is implemented in multiple places:

- store path: `Features/WorkoutSession/Services/WorkoutStoreV2.swift:842-938`
- live overlay path: `Features/WorkoutSession/Views/LiveWorkout/LiveWorkoutOverlayCard.swift:105-197`
- exercise session path: `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift:1031-1149`
- timer posts shared notification: `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:270-290`

Impact:

- duplicated business logic
- drift risk between flows
- edge-case bugs when overlay + sheet + timer all active
- hard to prove exactly one set gets generated and exactly one place owns `actualRestSeconds`

Even where duplicates are avoided by "last set incomplete" checks, ownership is still fragmented and fragile.

Recommendation:

- make `WorkoutStoreV2` or a dedicated `WorkoutSessionCoordinator` sole owner of post-rest set generation
- views should render state only
- timer should emit one event, not business behavior

### Critical 3. `RestTimerManager` still lacks `@MainActor`

`RestTimerManager` is an `ObservableObject` singleton with published UI state, UIKit interaction, NotificationCenter callbacks, and UserDefaults-backed mutation, but class is not main-actor isolated:

- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:25-37`

Impact:

- concurrency safety gap
- future Swift 6 strict-mode pain
- hidden thread assumptions across timer updates, widget commands, and lifecycle callbacks

Code already shows actor confusion via repeated `Task { @MainActor in ... }` hops:

- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:149-157`, `179-181`, `214-224`, `326-333`, `352-359`, `386-393`

Recommendation:

- mark whole type `@MainActor`
- then remove redundant main-actor hops

### High 4. Train state lives in a god store

`WorkoutStoreV2` owns:

- current workout
- completed workouts
- cardio runs
- PR index
- HealthKit matching
- undo behavior
- stats invalidation
- reward unlocking
- watch messaging
- notification side effects
- discard windows / ignored UUIDs

See:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:11-1324`

Impact:

- any Train bug requires understanding huge surface area
- testing small behaviors becomes expensive
- unrelated writes trigger broad observation churn
- persistence and domain logic too interleaved

Recommendation:

- split into focused collaborators:
  - `CurrentWorkoutStore`
  - `WorkoutHistoryStore`
  - `WorkoutPersistenceCoordinator`
  - `WorkoutHealthKitMatcher`
  - `WorkoutRewardsAdapter`

### High 5. Exercise session dependency injection is backwards

`ExerciseSessionViewModel` accepts optional `workoutStore`, then `ExerciseSessionView` injects real dependency later in `onAppear`:

- `Features/WorkoutSession/ViewModels/ExerciseSessionViewModel.swift:17`, `69-83`
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift:72-79`, `190-210`

Impact:

- partially initialized view model
- lifecycle-order dependency
- harder unit testing
- more fragile first-render behavior

Recommendation:

- pass `store` at init-time
- make `workoutStore` non-optional
- keep `onAppear` for view lifecycle only, not dependency wiring

### High 6. Active workout writes are too chatty and detached

Many user actions call `persistCurrentWorkout()` immediately, and persistence is done with detached tasks:

- mutation sites across `Features/WorkoutSession/Services/WorkoutStoreV2.swift:435-816`
- persistence impl: `1288-1318`

Impact:

- write amplification during active workout
- harder ordering guarantees under rapid edits
- potential stale-save races when multiple detached tasks overlap

Recommendation:

- define durability invariant first:
  - last meaningful workout state must reach durable storage before app crosses lifecycle boundaries it already knows about
- treat these as hard sync points and flush immediately:
  - app entering background
  - workout finish
  - workout discard
  - entry removal / replacement
  - timer-driven auto-generation of a set
- treat rapid in-row edits as soft sync points:
  - steppers
  - typing into reps/weight/duration fields
- for soft sync points, coalesce writes with a concrete window of `250-500ms`
- keep one serialized persistence pipeline, not many detached fire-and-forget saves
- on hard sync points, force flush any pending coalesced write before continuing

This keeps optimization non-arbitrary:

- burst edits do not spam disk
- lifecycle boundaries do not rely on debounce luck

### High 7. `removeEntry` leaves empty workout alive

This line is effectively a no-op branch:

- `Features/WorkoutSession/Services/WorkoutStoreV2.swift:644`

```swift
currentWorkout = w.entries.isEmpty ? w : w
```

Impact:

- empty workout persists after deleting last exercise
- app can carry hidden "active" workout object with zero entries
- state model becomes ambiguous: no workout vs empty workout

Recommendation:

- decide invariant
- most likely: if last entry removed, set `currentWorkout = nil`, stop timer, persist nil

### High 8. Set rows still subscribe directly to rest timer

These row views still observe `RestTimerManager.shared` directly:

- `Features/WorkoutSession/Views/ExerciseSession/BodyweightSetRow.swift:25-27`
- `Features/WorkoutSession/Views/ExerciseSession/TimedSetRow.swift:25`

You already created isolated badge pattern in:

- `Features/WorkoutSession/Views/ExerciseSession/SetRowViews.swift:498-527`

Impact:

- visible rows redraw every timer tick
- wasted work during active rests
- inconsistent optimization across row types

Recommendation:

- apply same isolated badge/subview approach to bodyweight and timed rows

### Medium 9. Home refresh does network work every time Train reappears

`HomeViewNew` calls `viewModel.refresh()` in `onAppear`, and refresh rebuilds carousel which can fetch feed data:

- `Features/Home/HomeViewNew.swift:322-342`
- `Features/Home/ViewModels/HomeViewModel.swift:52-56`, `76-131`, `231-254`

Impact:

- repeated feed fetches on tab switching
- no visible cancellation / caching policy
- Train home responsiveness tied to Social backend

Recommendation:

- cache friend activity for short TTL
- refresh only on first appear, pull-to-refresh, or explicit invalidation
- consider making social card independently refreshable

### Medium 10. Home view still carries "unfinished migration" signals

File header still says:

- `Features/Home/HomeViewNew.swift:5-6`

```swift
//  Redesigned Home screen with focused hub structure
//  TODO: Rename to HomeViewNew.swift after testing
```

But file is already named `HomeViewNew.swift`.

Impact:

- small thing, but signals Train home is still in transition
- usually correlates with "temporary structure became permanent structure"

Recommendation:

- rename type to stable domain name, likely `TrainView` or `TrainHomeView`
- remove migration comments once feature is productized

### Medium 11. Rest timer still relies on many delayed closures

Examples:

- `Features/Home/HomeViewNew.swift:185-198`
- `Features/WorkoutSession/Views/RestTimer/RestTimerState.swift:227-232`, `282-296`, `441-443`, `477-483`, `488-493`
- `Features/WorkoutSession/Views/ExerciseSession/ExcerciseSessionView.swift:162-164`, `248-250`

Impact:

- timing-sensitive behavior
- difficult cancellation
- more edge bugs under rapid navigation/backgrounding

Recommendation:

- replace user-flow-critical delays with structured async tasks where possible
- keep delays only for pure animation polish

## Efficiency Opportunities

### 1. Move Train to explicit feature coordinators

Best leverage improvement.

Suggested ownership:

- `TrainHomeCoordinator`: home cards, refresh policy, hero state
- `WorkoutSessionCoordinator`: logging, progression, active entry, post-rest generation
- `RestTimerManager`: timer only
- `WorkoutStore`: persistence-backed source of workout truth

### 2. Normalize one event pipeline

Current system uses:

- direct method calls
- `NotificationCenter`
- singleton polling/observation
- AppStorage/UserDefaults flags
- sheets and overlay side effects

Train would be more reliable with one typed event path for workout-session events.

### 3. Reduce singleton observation surface

Big redraw sources:

- `WorkoutStoreV2`
- `ExerciseRepository`
- `RestTimerManager`

Observation should happen closer to leaves, not broad container views.

### 4. Separate domain rules from SwiftUI views

A lot of workout rules currently live in views:

- Exercise session set generation
- live overlay timer completion behavior
- home recommendation navigation rules

Move rules to services/coordinators so views become predictable.

## Suggested Refactor Order

### Phase 1: correctness first

1. Fix PR detection in `HomeViewModel`
2. Fix empty-workout invariant in `removeEntry`
3. Make one owner for post-rest set generation
4. Add `@MainActor` to `RestTimerManager`

### Phase 2: performance / reliability

1. isolate timer subscriptions in all row variants
2. coalesce current-workout persistence
3. stop unnecessary home refetch on every appear

### Phase 3: architecture cleanup

1. remove optional view-model injection
2. split `WorkoutStoreV2`
3. rename `HomeViewNew` to stable train-home naming

## Bottom Line

Train View is one of strongest product areas in app, but also one of most fragile engineering areas.

Best summary:

- product ambition: good
- feature density: high
- state ownership: weak
- timer/session correctness: too distributed
- performance profile: acceptable now, but carrying preventable churn

If I were choosing only three fixes first, I would do:

1. PR detection bug
2. single owner for rest-completion set generation
3. current-workout persistence + store boundary cleanup

---

## Review

Date reviewed: 2026-04-15

### Verified as accurate

**Critical 1 -- PR detection hardcoded to reps:10**: Confirmed. `HomeViewModel.swift:200` calls `bestWeightForExactReps(exercise:, reps: 10)` unconditionally, regardless of the logged set's actual rep count.

**Critical 2 -- No single owner for next-set generation**: Confirmed. The logic exists independently in `WorkoutStoreV2.swift:842-938`, `LiveWorkoutOverlayCard.swift:105-197`, and `ExcerciseSessionView.swift:1031-1149`.

**Critical 3 -- `RestTimerManager` lacks `@MainActor`**: Confirmed. Class declaration at `RestTimerState.swift:25` is `class RestTimerManager: ObservableObject` with no actor annotation.

**High 7 -- `removeEntry` is a no-op for empty workouts**: Confirmed. `WorkoutStoreV2.swift:644` reads `currentWorkout = w.entries.isEmpty ? w : w`. Both branches assign the same `w`, so an empty workout is never cleared.

**Medium 10 -- HomeViewNew stale TODO comment**: Confirmed. `HomeViewNew.swift:6` says `// TODO: Rename to HomeViewNew.swift after testing` but the file is already named `HomeViewNew.swift`. The comment is orphaned.

**High 8 -- Set rows observe RestTimerManager directly**: Confirmed. `BodyweightSetRow.swift:25-27` and `TimedSetRow.swift:25` subscribe to `RestTimerManager.shared` directly rather than using the isolated badge approach already present in `SetRowViews.swift:498-527`.

### No issues found

All file references, line number citations, and code descriptions checked out. The claim about `WorkoutStoreV2` chatty persistence (finding 6) and the dependency injection issue in `ExerciseSessionViewModel` (finding 5) are directionally correct based on the described patterns, though not individually re-verified line-by-line here.
